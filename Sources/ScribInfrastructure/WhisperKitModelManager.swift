#if os(macOS)
import Foundation
import ScribApplication
import ScribDomain
import WhisperKit

public enum WhisperKitModelManagerError: LocalizedError, Sendable {
    case unsupportedModel(LocalTranscriptionModelID)
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedModel(modelID):
            "Le modèle \(modelID.rawValue) n’est pas activé dans cette alpha."
        case let .downloadFailed(message):
            "Le modèle n’a pas pu être téléchargé. Vérifiez la connexion Internet puis réessayez. Détail : \(message)"
        }
    }
}

private struct WhisperKitModelManifest: Codable {
    var locations: [String: String] = [:]
}

public actor WhisperKitModelManager: TranscriptionModelManaging {
    public nonisolated var availableModels: [TranscriptionModelDescriptor] {
        LocalTranscriptionModelCatalog.alphaModels
    }

    private let modelsRoot: URL
    private let manifestURL: URL
    private let fileManager: FileManager

    public init(modelsRoot: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let modelsRoot {
            self.modelsRoot = modelsRoot
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.modelsRoot = support
                .appendingPathComponent("Scrib", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("WhisperKit", isDirectory: true)
        }
        self.manifestURL = self.modelsRoot.appendingPathComponent("models.json")
        try fileManager.createDirectory(at: self.modelsRoot, withIntermediateDirectories: true)
    }

    public func status(for modelID: LocalTranscriptionModelID) -> TranscriptionModelStatus {
        guard let descriptor = LocalTranscriptionModelCatalog.descriptor(for: modelID),
              descriptor.isEnabledInAlpha else {
            return .init(
                modelID: modelID,
                availability: .failed,
                errorMessage: WhisperKitModelManagerError.unsupportedModel(modelID).localizedDescription
            )
        }
        guard let url = installedURL(for: descriptor), isUsableModelDirectory(url) else {
            return .init(modelID: modelID, availability: .notDownloaded)
        }
        return .init(
            modelID: modelID,
            availability: .available,
            progress: 1,
            localURL: url,
            installedSizeBytes: directorySize(url)
        )
    }

    public func download(
        _ modelID: LocalTranscriptionModelID,
        progress: @escaping @Sendable (TranscriptionModelStatus) -> Void
    ) async throws -> TranscriptionModelStatus {
        guard let descriptor = LocalTranscriptionModelCatalog.descriptor(for: modelID),
              descriptor.isEnabledInAlpha else {
            throw WhisperKitModelManagerError.unsupportedModel(modelID)
        }
        let existing = status(for: modelID)
        if existing.availability == .available { return existing }

        progress(.init(modelID: modelID, availability: .downloading, progress: 0))
        do {
            let folder = try await WhisperKit.download(
                variant: descriptor.whisperKitVariant,
                downloadBase: modelsRoot,
                progressCallback: { downloadProgress in
                    if Task.isCancelled { downloadProgress.cancel() }
                    progress(.init(
                        modelID: modelID,
                        availability: .downloading,
                        progress: downloadProgress.fractionCompleted
                    ))
                }
            )
            try Task.checkCancellation()
            try remember(folder: folder, for: modelID)
            let completed = TranscriptionModelStatus(
                modelID: modelID,
                availability: .available,
                progress: 1,
                localURL: folder,
                installedSizeBytes: directorySize(folder)
            )
            progress(completed)
            return completed
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let wrapped = WhisperKitModelManagerError.downloadFailed(error.localizedDescription)
            progress(.init(modelID: modelID, availability: .failed, errorMessage: wrapped.localizedDescription))
            throw wrapped
        }
    }

    private func installedURL(for descriptor: TranscriptionModelDescriptor) -> URL? {
        if let path = loadManifest().locations[descriptor.id.rawValue] {
            let url = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        guard let enumerator = fileManager.enumerator(
            at: modelsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == descriptor.whisperKitVariant {
            if isUsableModelDirectory(url) { return url }
        }
        return nil
    }

    private func isUsableModelDirectory(_ url: URL) -> Bool {
        let names = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
        return names.contains { $0.hasPrefix("AudioEncoder") }
            && names.contains { $0.hasPrefix("TextDecoder") }
            && names.contains { $0.hasPrefix("MelSpectrogram") }
    }

    private func remember(folder: URL, for modelID: LocalTranscriptionModelID) throws {
        var manifest = loadManifest()
        manifest.locations[modelID.rawValue] = folder.path
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private func loadManifest() -> WhisperKitModelManifest {
        guard let data = try? Data(contentsOf: manifestURL) else { return .init() }
        return (try? JSONDecoder().decode(WhisperKitModelManifest.self, from: data)) ?? .init()
    }

    private func directorySize(_ directory: URL) -> Int64? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
#endif
