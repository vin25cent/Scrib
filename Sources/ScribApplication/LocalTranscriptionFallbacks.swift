import Foundation
import ScribDomain

public actor InMemoryLocalTranscriptionStore: LocalTranscriptionStoring {
    private var value: StoredLocalTranscription?
    private var candidate: StoredLocalTranscription?

    public init() {}

    public func save(_ transcription: StoredLocalTranscription) {
        value = transcription
    }

    public func saveReplacementCandidate(_ transcription: StoredLocalTranscription) {
        candidate = transcription
    }

    public func replacementCandidate(for courseID: CourseID) -> StoredLocalTranscription? {
        candidate?.course.id == courseID ? candidate : nil
    }

    public func promoteReplacementCandidate(
        for courseID: CourseID
    ) throws -> StoredLocalTranscription {
        guard let candidate, candidate.course.id == courseID else {
            throw LocalTranscriptionError.noPendingReplacement
        }
        value = candidate
        self.candidate = nil
        return candidate
    }

    public func discardReplacementCandidate(for courseID: CourseID) {
        if candidate?.course.id == courseID { candidate = nil }
    }

    public func updateDraft(_ draft: TranscriptDraft) throws {
        guard var value else { throw LocalTranscriptionError.inconsistentCourse }
        value.draft = draft
        self.value = value
    }

    public func transcription(for courseID: CourseID) -> StoredLocalTranscription? {
        value?.course.id == courseID ? value : nil
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
