import Foundation
import ScribApplication
import ScribDomain

/// A dedicated actor keeps support-file I/O and extraction off the MainActor.
public actor LocalSupportDocumentStore: SupportDocumentImporting {
    private let rootDirectory: URL
    private let manifestURL: URL
    private let validator: SupportImportValidator
    private let extractor: any SupportDocumentExtracting
    private let fileManager: FileManager
    private var storedDocuments: [SupportDocument] = []
    private var hasLoadedManifest = false
    private let manifestWriter: @Sendable (Data, URL) throws -> Void

    public init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let rootDirectory = base.appendingPathComponent("Scrib/Supports", isDirectory: true)
        self.rootDirectory = rootDirectory
        self.manifestURL = rootDirectory.appendingPathComponent("manifest.json")
        self.validator = .init()
        self.extractor = LocalSupportDocumentExtractor()
        self.fileManager = .default
        self.manifestWriter = { data, url in
            try data.write(to: url, options: .atomic)
        }
    }

    public init(
        rootDirectory: URL,
        validator: SupportImportValidator = .init(),
        extractor: any SupportDocumentExtracting = LocalSupportDocumentExtractor(),
        fileManager: FileManager = .default,
        manifestWriter: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.rootDirectory = rootDirectory
        self.manifestURL = rootDirectory.appendingPathComponent("manifest.json")
        self.validator = validator
        self.extractor = extractor
        self.fileManager = fileManager
        self.manifestWriter = manifestWriter
    }

    public func documents() throws -> [SupportDocument] {
        try loadManifestIfNeeded()
        return storedDocuments.sorted { $0.importedAt > $1.importedAt }
    }

    public func importDocument(from sourceURL: URL) throws -> SupportDocument {
        try loadManifestIfNeeded()
        #if os(macOS)
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        #endif

        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let byteCount = Int64(values.fileSize ?? 0)
        let kind = try validator.validate(fileName: sourceURL.lastPathComponent, byteCount: byteCount)
        let id = UUID()
        let ext = sourceURL.pathExtension
        let destinationName = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext.lowercased())"
        let destination = rootDirectory.appendingPathComponent(destinationName)
        try fileManager.copyItem(at: sourceURL, to: destination)

        var document = SupportDocument(
            id: id,
            originalFileName: sourceURL.lastPathComponent,
            localURL: destination,
            kind: kind,
            byteCount: byteCount
        )
        if kind == .word || kind == .pdf {
            do {
                document.extraction = try extractor.extract(
                    documentID: id,
                    fileName: document.originalFileName,
                    kind: kind,
                    from: destination
                )
            } catch SupportExtractionError.generatedByScrib {
                try? fileManager.removeItem(at: destination)
                throw SupportExtractionError.generatedByScrib
            } catch {
                document.extractionFailure = error.localizedDescription
            }
        }
        let updatedDocuments = storedDocuments + [document]
        do {
            try persistManifest(updatedDocuments)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        storedDocuments = updatedDocuments
        return document
    }

    public func deleteDocument(id: UUID) throws {
        try loadManifestIfNeeded()
        guard let document = storedDocuments.first(where: { $0.id == id }) else { return }
        let updatedDocuments = storedDocuments.filter { $0.id != id }

        // Staging the file first lets a manifest-write failure be rolled back
        // without ever leaving a manifest entry that points at a missing file.
        let stagedURL = try stageForDeletion(document.localURL, id: id)
        do {
            try persistManifest(updatedDocuments)
        } catch {
            try? restoreStagedFile(from: stagedURL, to: document.localURL)
            throw error
        }
        storedDocuments = updatedDocuments

        // A failed final cleanup can only leave an unreferenced staging file,
        // never a phantom manifest entry. It is reconciled on the next load.
        if let stagedURL {
            try? fileManager.removeItem(at: stagedURL)
        }
    }

    private func loadManifestIfNeeded() throws {
        guard !hasLoadedManifest else { return }
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            storedDocuments = try JSONDecoder().decode([SupportDocument].self, from: data)
        }
        try reconcileStagedDeletes()
        hasLoadedManifest = true
    }

    private func persistManifest(_ documents: [SupportDocument]) throws {
        try manifestWriter(JSONEncoder().encode(documents), manifestURL)
    }

    private func stageForDeletion(_ url: URL?, id: UUID) throws -> URL? {
        guard let url, fileManager.fileExists(atPath: url.path) else { return nil }
        let stagedURL = rootDirectory.appendingPathComponent(".deleting-\(id.uuidString)")
        try fileManager.moveItem(at: url, to: stagedURL)
        return stagedURL
    }

    private func restoreStagedFile(from stagedURL: URL?, to originalURL: URL?) throws {
        guard let stagedURL, let originalURL,
              fileManager.fileExists(atPath: stagedURL.path) else { return }
        try fileManager.moveItem(at: stagedURL, to: originalURL)
    }

    /// Completes a deletion after a crash, or restores a staged file when the
    /// manifest still references it (crash before the manifest write).
    private func reconcileStagedDeletes() throws {
        let contents = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )
        for stagedURL in contents where stagedURL.lastPathComponent.hasPrefix(".deleting-") {
            let identifier = String(stagedURL.lastPathComponent.dropFirst(".deleting-".count))
            guard let id = UUID(uuidString: identifier),
                  let document = storedDocuments.first(where: { $0.id == id }),
                  let originalURL = document.localURL else {
                try? fileManager.removeItem(at: stagedURL)
                continue
            }
            if fileManager.fileExists(atPath: originalURL.path) {
                try? fileManager.removeItem(at: stagedURL)
            } else {
                try fileManager.moveItem(at: stagedURL, to: originalURL)
            }
        }
    }
}
