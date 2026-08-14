import Foundation
import ScribDomain

public protocol CourseRepository: Sendable {
    func save(_ course: Course) async throws
    func course(id: CourseID) async throws -> Course?
}

@MainActor
public protocol AudioRecording: AnyObject {
    func requestPermission() async -> Bool
    func start(courseID: CourseID, directory: URL) throws
    func pause() throws
    func resume() throws
    func stop() throws -> [RecordingSegment]
    func snapshot() -> AudioRecorderSnapshot
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

public protocol TranscriptionEngine: Sendable {
    func transcribe(courseID: CourseID) async throws -> String
}

public protocol DocumentRendering: Sendable {
    func render(courseID: CourseID, transcript: String) async throws
}

public protocol ProcessingJobRepository: Sendable {
    func save(_ job: ProcessingJob) async throws
    func job(id: ProcessingJobID) async throws -> ProcessingJob?
    func jobs() async throws -> [ProcessingJob]
    func delete(id: ProcessingJobID) async throws
}

public struct ProcessingStepResult: Equatable, Sendable {
    public var outputFingerprint: String?

    public init(outputFingerprint: String? = nil) {
        self.outputFingerprint = outputFingerprint
    }
}

public protocol PipelineStepExecuting: Sendable {
    func execute(
        stage: ProcessingStage,
        courseID: CourseID
    ) async throws -> ProcessingStepResult
}

public protocol SystemConditionsMonitoring: Sendable {
    func currentSnapshot() async -> SystemConditionSnapshot
}

public protocol ProcessingNotificationSending: Sendable {
    func processingDidComplete(job: ProcessingJob) async
    func processingNeedsAttention(job: ProcessingJob) async
}
