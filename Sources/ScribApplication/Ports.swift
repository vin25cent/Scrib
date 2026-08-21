import Foundation
import ScribDomain

public protocol CourseRepository: Sendable {
    func save(_ course: Course) async throws
    func course(id: CourseID) async throws -> Course?
}

@MainActor
public protocol AudioRecording: AnyObject {
    func requestPermission() async -> Bool
    func start(course: Course, directory: URL) throws
    func pause() throws
    func resume() throws
    func stop() throws -> [RecordingSegment]
    func snapshot() -> AudioRecorderSnapshot
}

@MainActor
public protocol RecordingSessionStoring: AnyObject {
    func createSession(course: Course, directory: URL) throws -> RecordingSessionManifest
    func beginSegment(
        sessionID: UUID,
        in directory: URL,
        relativePath: String,
        sequence: Int,
        startedAt: Date
    ) throws -> RecordingSessionManifest.Segment
    func finalizeSegment(
        sessionID: UUID,
        in directory: URL,
        segment: RecordingSegment,
        nextSessionState: RecordingSessionFinalizationState
    ) throws
    func failActiveSegment(
        sessionID: UUID,
        in directory: URL,
        relativePath: String,
        endedAt: Date,
        byteCount: Int64
    ) throws
    func finishSession(sessionID: UUID, in directory: URL) throws
    func recoverableSessions() throws -> [RecoveredRecordingSession]
}

@MainActor
public protocol CourseFileStoring: AnyObject {
    func recordingDirectory(for course: Course) throws -> URL
    func availableCapacity(for directory: URL) throws -> Int64
}

@MainActor
public protocol TeacherAuthorizationStoring: AnyObject {
    func teachers() -> [Teacher]
    func teacher(named name: String) -> Teacher?
    func save(_ teacher: Teacher) throws
}

/// File imports and extraction are deliberately isolated away from the UI actor.
/// Implementations should keep disk I/O, archive parsing and manifest writes in
/// their own concurrency domain.
public protocol SupportDocumentImporting: AnyObject, Sendable {
    func documents() async throws -> [SupportDocument]
    func importDocument(from sourceURL: URL) async throws -> SupportDocument
    func deleteDocument(id: UUID) async throws
}

public protocol SupportDocumentExtracting: Sendable {
    func extract(documentID: UUID, fileName: String, kind: SupportDocumentKind, from url: URL) throws -> SupportDocumentExtraction
}

public protocol AICloudGenerating: Sendable {
    func generate(
        _ request: AIProviderGenerationRequest,
        credential: String?
    ) async throws -> AIProviderGenerationResponse
}

public protocol AISecretStoring: Sendable {
    func hasSecret(for provider: AIProviderID) async throws -> Bool
    func readSecret(for provider: AIProviderID) async throws -> String?
    func saveSecret(_ secret: String, for provider: AIProviderID) async throws
    func deleteSecret(for provider: AIProviderID) async throws
}

public protocol AIGenerationRunStoring: Sendable {
    func runs() async throws -> [AIGenerationRun]
    func run(idempotencyKey: String) async throws -> AIGenerationRun?
    func save(_ run: AIGenerationRun) async throws
}

@MainActor
public protocol AIGenerationPreferencesStoring: AnyObject {
    func load() -> AIGenerationPreferences
    func save(_ preferences: AIGenerationPreferences) throws
}

public protocol TranscriptionEngine: Sendable {
    var descriptor: TranscriptionEngineDescriptor { get }
    func transcribe(
        _ request: LocalTranscriptionRequest,
        progress: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> LocalTranscriptionResult
    func unload() async
}

public protocol TranscriptionModelManaging: Sendable {
    var availableModels: [TranscriptionModelDescriptor] { get }
    func status(for modelID: LocalTranscriptionModelID) async -> TranscriptionModelStatus
    func download(
        _ modelID: LocalTranscriptionModelID,
        progress: @escaping @Sendable (TranscriptionModelStatus) -> Void
    ) async throws -> TranscriptionModelStatus
}

public protocol LocalTranscriptionStoring: Sendable {
    func save(_ transcription: StoredLocalTranscription) async throws
    func updateDraft(_ draft: TranscriptDraft) async throws
    func latest() async throws -> StoredLocalTranscription?
}

public protocol DocumentRendering: Sendable {
    func render(courseID: CourseID, transcript: String) async throws
}

public protocol StructuredDocumentRendering: Sendable {
    func render(_ document: CourseDocument, to destination: URL) throws
}

public protocol ProcessingJobRepository: Sendable {
    func save(_ job: ProcessingJob) async throws
    func job(id: ProcessingJobID) async throws -> ProcessingJob?
    func jobs() async throws -> [ProcessingJob]
    func delete(id: ProcessingJobID) async throws
}
