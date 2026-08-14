import Foundation

public enum TranscriptPassageFlag: String, Codable, CaseIterable, Hashable, Sendable {
    case uncertainty
    case medicalImportance

    public var displayName: String {
        switch self {
        case .uncertainty: "Passage incertain"
        case .medicalImportance: "Information médicale importante"
        }
    }
}

public struct TranscriptPassage: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var speaker: String
    public var startTime: TimeInterval
    public var text: String
    public var flags: Set<TranscriptPassageFlag>

    public init(
        id: UUID = UUID(),
        speaker: String,
        startTime: TimeInterval,
        text: String,
        flags: Set<TranscriptPassageFlag> = []
    ) {
        self.id = id
        self.speaker = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        self.startTime = max(startTime, 0)
        self.text = text
        self.flags = flags
    }
}

public struct TranscriptDraft: Equatable, Codable, Sendable {
    public var courseID: CourseID
    public var courseTitle: String
    public var teachingUnit: String
    public var passages: [TranscriptPassage]
    public var version: Int
    public var updatedAt: Date
    public var isDemonstration: Bool

    public init(
        courseID: CourseID = CourseID(),
        courseTitle: String,
        teachingUnit: String,
        passages: [TranscriptPassage] = [],
        version: Int = 1,
        updatedAt: Date = Date(),
        isDemonstration: Bool = false
    ) {
        self.courseID = courseID
        self.courseTitle = courseTitle
        self.teachingUnit = teachingUnit
        self.passages = passages
        self.version = max(version, 1)
        self.updatedAt = updatedAt
        self.isDemonstration = isDemonstration
    }

    public var plainText: String {
        passages.map { "\($0.speaker) : \($0.text)" }.joined(separator: "\n\n")
    }
}

public enum SupportDocumentKind: String, Codable, CaseIterable, Sendable {
    case word
    case pdf
    case presentation
    case spreadsheet
    case image
}

public struct SupportDocument: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var originalFileName: String
    public var localURL: URL?
    public var kind: SupportDocumentKind
    public var byteCount: Int64
    public var importedAt: Date
    public var isDemonstration: Bool

    public init(
        id: UUID = UUID(),
        originalFileName: String,
        localURL: URL?,
        kind: SupportDocumentKind,
        byteCount: Int64,
        importedAt: Date = Date(),
        isDemonstration: Bool = false
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.localURL = localURL
        self.kind = kind
        self.byteCount = max(byteCount, 0)
        self.importedAt = importedAt
        self.isDemonstration = isDemonstration
    }
}
