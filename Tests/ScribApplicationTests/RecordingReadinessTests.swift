import Foundation
import Testing
@testable import ScribApplication
@testable import ScribDomain

private func courseAndTeacher(authorized: Bool = true) -> (Course, Teacher) {
    let teacher = Teacher(
        name: "Dr Martin",
        recordingAuthorizationConfirmedAt: authorized ? Date() : nil
    )
    let course = Course(
        semester: .semester1,
        teachingUnit: TeachingUnitCatalog.units(for: .semester1)[2],
        title: "Biologie fondamentale",
        teacher: teacher,
        expectedDuration: .twoHours
    )
    return (course, teacher)
}

@Test func authorizedCourseWithEnoughSpaceIsReady() throws {
    let (course, teacher) = courseAndTeacher()
    let required = AudioStoragePolicy.requiredBytes(for: course.expectedDuration)

    try RecordingReadinessValidator().validate(
        course: course,
        teacher: teacher,
        availableCapacity: required
    )
}

@Test func firstCourseRequiresTeacherAuthorization() {
    let (course, teacher) = courseAndTeacher(authorized: false)

    #expect(throws: RecordingReadinessIssue.teacherAuthorizationRequired) {
        try RecordingReadinessValidator().validate(
            course: course,
            teacher: teacher,
            availableCapacity: Int64.max
        )
    }
}

@Test func insufficientStorageReportsRequiredAndAvailableBytes() {
    let (course, teacher) = courseAndTeacher()
    let required = AudioStoragePolicy.requiredBytes(for: course.expectedDuration)

    #expect(
        throws: RecordingReadinessIssue.insufficientStorage(
            required: required,
            available: required - 1
        )
    ) {
        try RecordingReadinessValidator().validate(
            course: course,
            teacher: teacher,
            availableCapacity: required - 1
        )
    }
}
