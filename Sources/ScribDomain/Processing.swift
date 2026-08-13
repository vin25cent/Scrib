import Foundation

public enum ProcessingStage: String, Codable, CaseIterable, Sendable {
    case preparing
    case transcribing
    case analyzing
    case rendering
    case publishing
}

public enum CourseStatus: String, Codable, Sendable {
    case draft
    case recording
    case captured
    case queued
    case processing
    case suspended
    case needsAttention
    case completed
}

public struct ProcessingJob: Equatable, Codable, Sendable {
    public let courseID: CourseID
    public var status: CourseStatus
    public var stage: ProcessingStage?
    public var progress: Double
    public var attemptCount: Int

    public init(
        courseID: CourseID,
        status: CourseStatus = .draft,
        stage: ProcessingStage? = nil,
        progress: Double = 0,
        attemptCount: Int = 0
    ) {
        self.courseID = courseID
        self.status = status
        self.stage = stage
        self.progress = min(max(progress, 0), 1)
        self.attemptCount = max(attemptCount, 0)
    }
}
