import Foundation

public struct ProcessingJobID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Thermal measurements remain part of the transcription benchmark. They are
/// not used to claim that the activity tracker controls execution.
public enum ThermalCondition: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

/// A concrete activity currently performed by Scrib. This is deliberately not a
/// description of the future end-to-end course pipeline.
public enum ProcessingActivity: String, Codable, Sendable {
    case recording
    case localTranscription

    public var displayName: String {
        switch self {
        case .recording: "Enregistrement"
        case .localTranscription: "Transcription locale"
        }
    }
}

public enum ProcessingStatus: String, Codable, Sendable {
    case pending
    case processing
    case suspended
    case completed
    case failed

    public var displayName: String {
        switch self {
        case .pending: "En attente"
        case .processing: "En cours"
        case .suspended: "Suspendu"
        case .completed: "Terminé"
        case .failed: "Erreur"
        }
    }
}

public struct ProcessingJob: Identifiable, Equatable, Codable, Sendable {
    public let id: ProcessingJobID
    public let courseID: CourseID
    public var courseTitle: String
    public var teachingUnit: String
    public var courseDate: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var activity: ProcessingActivity
    public var status: ProcessingStatus
    public var reportedProgress: Double?
    public var suspensionReason: String?
    public var lastError: String?

    public init(
        id: ProcessingJobID = ProcessingJobID(),
        courseID: CourseID,
        courseTitle: String = "",
        teachingUnit: String = "",
        courseDate: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        activity: ProcessingActivity,
        status: ProcessingStatus = .pending,
        reportedProgress: Double? = nil,
        suspensionReason: String? = nil,
        lastError: String? = nil,
    ) {
        self.id = id
        self.courseID = courseID
        self.courseTitle = courseTitle
        self.teachingUnit = teachingUnit
        self.courseDate = courseDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activity = activity
        self.status = status
        self.reportedProgress = reportedProgress.map { min(max($0, 0), 1) }
        self.suspensionReason = suspensionReason
        self.lastError = lastError
    }

    public init(course: Course, activity: ProcessingActivity, createdAt: Date = Date()) {
        self.init(
            courseID: course.id,
            courseTitle: course.title,
            teachingUnit: course.teachingUnit.displayName,
            courseDate: course.courseDate,
            createdAt: createdAt,
            updatedAt: createdAt,
            activity: activity
        )
    }

    /// Completion is derived from the terminal state; no duplicate persisted
    /// progress value is maintained for it.
    public var progress: Double? {
        status == .completed ? 1 : reportedProgress
    }
}
