import Foundation
import ScribApplication
import ScribDomain

@MainActor
public final class LocalSupportDocumentStore: SupportDocumentImporting {
    private let rootDirectory: URL
    private let manifestURL: URL
    private let validator: SupportImportValidator
    private let fileManager: FileManager
    private var storedDocuments: [SupportDocument]

    public convenience init() throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try self.init(rootDirectory: base.appendingPathComponent("Scrib/Supports", isDirectory: true))
    }

    public init(
        rootDirectory: URL,
        validator: SupportImportValidator = .init(),
        fileManager: FileManager = .default
    ) throws {
        self.rootDirectory = rootDirectory
        self.manifestURL = rootDirectory.appendingPathComponent("manifest.json")
        self.validator = validator
        self.fileManager = fileManager
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            self.storedDocuments = try JSONDecoder().decode([SupportDocument].self, from: data)
        } else {
            self.storedDocuments = []
        }
    }

    public func documents() -> [SupportDocument] {
        storedDocuments.sorted { $0.importedAt > $1.importedAt }
    }

    public func importDocument(from sourceURL: URL) throws -> SupportDocument {
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

        let document = SupportDocument(
            id: id,
            originalFileName: sourceURL.lastPathComponent,
            localURL: destination,
            kind: kind,
            byteCount: byteCount
        )
        storedDocuments.append(document)
        do {
            try persistManifest()
        } catch {
            try? fileManager.removeItem(at: destination)
            storedDocuments.removeAll { $0.id == id }
            throw error
        }
        return document
    }

    public func deleteDocument(id: UUID) throws {
        guard let document = storedDocuments.first(where: { $0.id == id }) else { return }
        if let url = document.localURL, fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        storedDocuments.removeAll { $0.id == id }
        try persistManifest()
    }

    private func persistManifest() throws {
        let data = try JSONEncoder().encode(storedDocuments)
        try data.write(to: manifestURL, options: .atomic)
    }
}
