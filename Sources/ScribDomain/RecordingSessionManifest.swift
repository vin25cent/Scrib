import Foundation

public enum RecordingSessionFinalizationState: String, Codable, Sendable {
    case recording
    case paused
    case stopped
    case failed

    public var isTerminal: Bool {
        switch self {
        case .stopped, .failed: true
        case .recording, .paused: false
        }
    }
}

public enum RecordingSessionSegmentState: String, Codable, Sendable {
    case recording
    case finalized
    case failed
}

/// Durable, local description of one recording session.
/// Segment paths are always relative to the manifest's parent `audio` directory.
public struct RecordingSessionManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var courseID: CourseID
    /// A course snapshot lets the UI reattach recovered audio without relying on in-memory state.
    public var course: Course
    public var sessionID: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var finalizationState: RecordingSessionFinalizationState
    public var segments: [Segment]

    public init(
        course: Course,
        sessionID: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        finalizationState: RecordingSessionFinalizationState = .recording,
        segments: [Segment] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.courseID = course.id
        self.course = course
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.finalizationState = finalizationState
        self.segments = segments.sorted { $0.sequence < $1.sequence }
    }

    public struct Segment: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var relativePath: String
        public var sequence: Int
        public var state: RecordingSessionSegmentState
        public var createdAt: Date
        public var finalizedAt: Date?
        public var durationSeconds: TimeInterval?
        public var byteCount: Int64?

        public init(
            id: UUID = UUID(),
            relativePath: String,
            sequence: Int,
            state: RecordingSessionSegmentState,
            createdAt: Date,
            finalizedAt: Date? = nil,
            durationSeconds: TimeInterval? = nil,
            byteCount: Int64? = nil
        ) {
            self.id = id
            self.relativePath = relativePath
            self.sequence = max(sequence, 1)
            self.state = state
            self.createdAt = createdAt
            self.finalizedAt = finalizedAt
            self.durationSeconds = durationSeconds.map { max($0, 0) }
            self.byteCount = byteCount.map { max($0, 0) }
        }
    }
}

public enum RecordingSessionRecoveryIssue: Equatable, Sendable {
    case malformedManifest(String)
    case malformedSegment(relativePath: String?)
    case missingAudioFile(relativePath: String)
    case incompleteSegment(relativePath: String)

    public var localizedDescription: String {
        switch self {
        case let .malformedManifest(path):
            return "Le manifeste de session est illisible : \(path)."
        case let .malformedSegment(path):
            if let path {
                return "Un segment du manifeste est incomplet : \(path)."
            }
            return "Un segment du manifeste est incomplet."
        case let .missingAudioFile(path):
            return "Le fichier audio référencé est absent : \(path)."
        case let .incompleteSegment(path):
            return "Le segment audio n'a pas été finalisé : \(path)."
        }
    }
}

public struct RecoveredRecordingSession: Equatable, Sendable {
    public var manifest: RecordingSessionManifest
    public var recordingSegments: [RecordingSegment]
    public var issues: [RecordingSessionRecoveryIssue]

    public init(
        manifest: RecordingSessionManifest,
        recordingSegments: [RecordingSegment],
        issues: [RecordingSessionRecoveryIssue] = []
    ) {
        self.manifest = manifest
        self.recordingSegments = recordingSegments.sorted { $0.sequence < $1.sequence }
        self.issues = issues
    }
}
