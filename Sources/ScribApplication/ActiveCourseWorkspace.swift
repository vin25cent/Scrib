import Foundation
import ScribDomain

public enum ActiveCourseWorkspaceError: LocalizedError, Equatable, Sendable {
    case inconsistentRecordingCourse
    case inconsistentTranscriptionCourse
    case duplicateAudioSegment(Int)

    public var errorDescription: String? {
        switch self {
        case .inconsistentRecordingCourse:
            "Les enregistrements retrouvés ne correspondent pas au cours sélectionné."
        case .inconsistentTranscriptionCourse:
            "La transcription retrouvée ne correspond pas au cours sélectionné."
        case let .duplicateAudioSegment(sequence):
            "Le segment audio n°\(sequence) apparaît plusieurs fois pour ce cours."
        }
    }
}

/// Immutable, course-scoped payload shared by tracking and transcription screens.
/// It rejects mixed CourseIDs before any workflow mutates its displayed state.
public struct ActiveCourseWorkspace: Equatable, Sendable {
    public let courseID: CourseID
    public let course: Course?
    public let recordingSegments: [RecordingSegment]
    public let recordingIssues: [RecordingSessionRecoveryIssue]
    public let transcription: StoredLocalTranscription?

    public init(
        courseID: CourseID,
        recordingSession: RecoveredRecordingSession?,
        transcription: StoredLocalTranscription?
    ) throws {
        if let recordingSession {
            guard recordingSession.manifest.courseID == courseID,
                  recordingSession.manifest.course.id == courseID,
                  recordingSession.recordingSegments.allSatisfy({ $0.courseID == courseID }) else {
                throw ActiveCourseWorkspaceError.inconsistentRecordingCourse
            }
        }
        if let transcription {
            guard transcription.course.id == courseID,
                  transcription.result.courseID == courseID,
                  transcription.draft.courseID == courseID,
                  transcription.recordingSegments.allSatisfy({ $0.courseID == courseID }) else {
                throw ActiveCourseWorkspaceError.inconsistentTranscriptionCourse
            }
        }

        let segments = (recordingSession?.recordingSegments
            ?? transcription?.recordingSegments
            ?? []).sorted { $0.sequence < $1.sequence }
        var seenIDs = Set<UUID>()
        var seenSequences = Set<Int>()
        for segment in segments {
            guard seenIDs.insert(segment.id).inserted,
                  seenSequences.insert(segment.sequence).inserted else {
                throw ActiveCourseWorkspaceError.duplicateAudioSegment(segment.sequence)
            }
        }

        self.courseID = courseID
        course = recordingSession?.manifest.course ?? transcription?.course
        recordingSegments = segments
        recordingIssues = recordingSession?.issues ?? []
        self.transcription = transcription
    }

    public var hasUsableAudio: Bool {
        !recordingSegments.isEmpty && recordingIssues.isEmpty
    }
}

public struct ActiveCourseSelection: Equatable, Sendable {
    public private(set) var courseID: CourseID?
    public private(set) var trackingJobID: ProcessingJobID?

    public init(courseID: CourseID? = nil, trackingJobID: ProcessingJobID? = nil) {
        self.courseID = courseID
        self.trackingJobID = trackingJobID
    }

    public mutating func select(_ job: ProcessingJob) {
        courseID = job.courseID
        trackingJobID = job.id
    }

    public mutating func select(_ course: Course) {
        courseID = course.id
        trackingJobID = nil
    }
}
