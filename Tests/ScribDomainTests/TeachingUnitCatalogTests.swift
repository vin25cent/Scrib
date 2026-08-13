import Testing
@testable import ScribDomain

@Test func catalogContainsAllSixSemesters() {
    for semester in Semester.allCases {
        #expect(!TeachingUnitCatalog.units(for: semester).isEmpty)
    }
}

@Test func semesterFourKeepsRequestedDuplicatesWithUniqueIdentifiers() {
    let semesterFour = TeachingUnitCatalog.units(for: .semester4)
    let emergencyUnits = semesterFour.filter { $0.code == "4.3" }
    let englishUnits = semesterFour.filter { $0.code == "6.2" }

    #expect(emergencyUnits.count == 2)
    #expect(englishUnits.count == 2)
    #expect(Set(emergencyUnits.map(\.id)).count == 2)
    #expect(Set(englishUnits.map(\.id)).count == 2)
}
