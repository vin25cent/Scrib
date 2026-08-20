import Foundation
import Testing
@testable import ScribDomain

@Test func completeCourseIsReadyToRecord() {
    let teacher = Teacher(name: "Dr Martin", recordingAuthorizationConfirmedAt: Date())
    let course = Course(
        semester: .semester1,
        teachingUnit: TeachingUnitCatalog.units(for: .semester1)[2],
        title: "La cellule et les tissus",
        teacher: teacher,
        expectedDuration: .twoHours
    )

    #expect(course.isReadyToRecord)
}

@Test func incompleteCourseIsNotReadyToRecord() {
    let teacher = Teacher(name: "Dr Martin", recordingAuthorizationConfirmedAt: Date())
    let course = Course(
        semester: .semester1,
        teachingUnit: TeachingUnitCatalog.units(for: .semester1)[2],
        title: " ",
        teacher: teacher,
        expectedDuration: .twoHours
    )

    #expect(!course.isReadyToRecord)
}

@Test func teacherNameMatchingIgnoresCaseAndAccents() {
    let first = Teacher(name: "  Élodie Martin ")
    let second = Teacher(name: "elodie martin")

    #expect(first.normalizedName == second.normalizedName)
}

@Test func storageEstimateIncludesSafetyMargin() {
    let rawTwoHourPayload = AudioStoragePolicy.targetBitRate / 8 * 7_200

    #expect(AudioStoragePolicy.requiredBytes(for: .twoHours) > rawTwoHourPayload)
}

@Test func captureProfileUsesStandardMonoAACSettings() {
    #expect(AudioStoragePolicy.captureSampleRate == 48_000)
    #expect(AudioStoragePolicy.captureChannelCount == 1)
    #expect(AudioStoragePolicy.targetBitRate == 64_000)
}
