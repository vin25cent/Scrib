import Foundation
import Testing
@testable import ScribDomain

@Test func completeCourseIsReadyToRecord() {
    let course = Course(
        semester: "Semestre 1",
        teachingUnit: "UE 2.1",
        title: "La cellule et les tissus",
        teacher: "Dr Martin",
        expectedDuration: 2 * 60 * 60
    )

    #expect(course.isReadyToRecord)
}

@Test func incompleteCourseIsNotReadyToRecord() {
    let course = Course(
        semester: "Semestre 1",
        teachingUnit: "UE 2.1",
        title: " ",
        teacher: "Dr Martin",
        expectedDuration: 2 * 60 * 60
    )

    #expect(!course.isReadyToRecord)
}
