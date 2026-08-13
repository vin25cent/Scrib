import Foundation

public struct CourseID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct Course: Identifiable, Equatable, Codable, Sendable {
    public let id: CourseID
    public var semester: String
    public var teachingUnit: String
    public var title: String
    public var teacher: String
    public var expectedDuration: TimeInterval
    public var createdAt: Date

    public init(
        id: CourseID = CourseID(),
        semester: String,
        teachingUnit: String,
        title: String,
        teacher: String,
        expectedDuration: TimeInterval,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.semester = semester
        self.teachingUnit = teachingUnit
        self.title = title
        self.teacher = teacher
        self.expectedDuration = expectedDuration
        self.createdAt = createdAt
    }

    public var isReadyToRecord: Bool {
        !semester.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !teachingUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !teacher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && expectedDuration > 0
    }
}
