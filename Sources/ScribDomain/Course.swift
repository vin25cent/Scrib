import Foundation

public struct CourseID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum Semester: Int, CaseIterable, Codable, Identifiable, Sendable {
    case semester1 = 1
    case semester2
    case semester3
    case semester4
    case semester5
    case semester6

    public var id: Int { rawValue }
    public var displayName: String { "Semestre \(rawValue)" }
}

public enum ExpectedDuration: Int, CaseIterable, Codable, Identifiable, Sendable {
    case oneHour = 3_600
    case twoHours = 7_200
    case fourHours = 14_400
    case fullDay = 28_800

    public var id: Int { rawValue }
    public var timeInterval: TimeInterval { TimeInterval(rawValue) }

    public var displayName: String {
        switch self {
        case .oneHour: "1 heure"
        case .twoHours: "2 heures"
        case .fourHours: "4 heures"
        case .fullDay: "Journée"
        }
    }
}

public struct TeacherID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct Teacher: Identifiable, Equatable, Codable, Sendable {
    public let id: TeacherID
    public var name: String
    public var recordingAuthorizationConfirmedAt: Date?

    public init(
        id: TeacherID = TeacherID(),
        name: String,
        recordingAuthorizationConfirmedAt: Date? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.recordingAuthorizationConfirmedAt = recordingAuthorizationConfirmedAt
    }

    public var hasRecordingAuthorization: Bool {
        recordingAuthorizationConfirmedAt != nil
    }

    public var normalizedName: String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func confirmRecordingAuthorization(at date: Date = Date()) {
        recordingAuthorizationConfirmedAt = date
    }
}

public struct Course: Identifiable, Equatable, Codable, Sendable {
    public let id: CourseID
    public var semester: Semester
    public var teachingUnit: TeachingUnit
    public var title: String
    public var teacherID: TeacherID
    public var teacherName: String
    public var expectedDuration: ExpectedDuration
    public var courseDate: Date
    public var createdAt: Date

    public init(
        id: CourseID = CourseID(),
        semester: Semester,
        teachingUnit: TeachingUnit,
        title: String,
        teacher: Teacher,
        expectedDuration: ExpectedDuration,
        courseDate: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.semester = semester
        self.teachingUnit = teachingUnit
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.teacherID = teacher.id
        self.teacherName = teacher.name
        self.expectedDuration = expectedDuration
        self.courseDate = courseDate
        self.createdAt = createdAt
    }

    public var isReadyToRecord: Bool {
        teachingUnit.semester == semester
            && !title.isEmpty
            && !teacherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
