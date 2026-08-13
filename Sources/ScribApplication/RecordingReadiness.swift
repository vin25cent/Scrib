import Foundation
import ScribDomain

public enum RecordingReadinessIssue: Error, Equatable, Sendable {
    case incompleteCourse
    case teacherAuthorizationRequired
    case insufficientStorage(required: Int64, available: Int64)
}

public struct RecordingReadinessValidator: Sendable {
    public init() {}

    public func validate(
        course: Course,
        teacher: Teacher,
        availableCapacity: Int64
    ) throws {
        guard course.isReadyToRecord else {
            throw RecordingReadinessIssue.incompleteCourse
        }
        guard teacher.hasRecordingAuthorization else {
            throw RecordingReadinessIssue.teacherAuthorizationRequired
        }

        let required = AudioStoragePolicy.requiredBytes(for: course.expectedDuration)
        guard availableCapacity >= required else {
            throw RecordingReadinessIssue.insufficientStorage(
                required: required,
                available: max(availableCapacity, 0)
            )
        }
    }
}
