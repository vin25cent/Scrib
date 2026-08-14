import Foundation
import ScribDomain

public actor InMemoryLocalTranscriptionStore: LocalTranscriptionStoring {
    private var value: StoredLocalTranscription?

    public init() {}

    public func save(_ transcription: StoredLocalTranscription) {
        value = transcription
    }

    public func updateDraft(_ draft: TranscriptDraft) throws {
        guard var value else { throw LocalTranscriptionError.inconsistentCourse }
        value.draft = draft
        self.value = value
    }

    public func latest() -> StoredLocalTranscription? { value }
}

public struct UnavailableTranscriptionModelManager: TranscriptionModelManaging {
    public var availableModels: [TranscriptionModelDescriptor] { LocalTranscriptionModelCatalog.alphaModels }
    public var message: String

    public init(message: String) { self.message = message }

    public func status(for modelID: LocalTranscriptionModelID) async -> TranscriptionModelStatus {
        .init(modelID: modelID, availability: .failed, errorMessage: message)
    }

    public func download(
        _ modelID: LocalTranscriptionModelID,
        progress: @escaping @Sendable (TranscriptionModelStatus) -> Void
    ) async throws -> TranscriptionModelStatus {
        let status = TranscriptionModelStatus(modelID: modelID, availability: .failed, errorMessage: message)
        progress(status)
        throw UnavailableTranscriptionError(message: message)
    }
}

public struct UnavailableTranscriptionEngine: TranscriptionEngine {
    public let descriptor = TranscriptionEngineDescriptor(id: "unavailable", displayName: "Indisponible", version: "0")
    public var message: String

    public init(message: String) { self.message = message }

    public func transcribe(
        _ request: LocalTranscriptionRequest,
        progress: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> LocalTranscriptionResult {
        throw UnavailableTranscriptionError(message: message)
    }

    public func unload() async {}
}

public struct UnavailableTranscriptionError: LocalizedError, Equatable, Sendable {
    public var message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}
