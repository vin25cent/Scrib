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
    public var endTime: TimeInterval?
    public var text: String
    public var flags: Set<TranscriptPassageFlag>
    public var sourceRecordingSegmentID: UUID?
    public var confidence: Double?

    public init(
        id: UUID = UUID(),
        speaker: String,
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        text: String,
        flags: Set<TranscriptPassageFlag> = [],
        sourceRecordingSegmentID: UUID? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.speaker = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStartTime = max(startTime, 0)
        self.startTime = normalizedStartTime
        self.endTime = endTime.map { max($0, normalizedStartTime) }
        self.text = text
        self.flags = flags
        self.sourceRecordingSegmentID = sourceRecordingSegmentID
        self.confidence = confidence.map { min(max($0, 0), 1) }
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
    public var transcriptionEngine: TranscriptionEngineDescriptor?
    public var transcriptionModelID: LocalTranscriptionModelID?
    public var rawTranscriptionCompletedAt: Date?

    public init(
        courseID: CourseID = CourseID(),
        courseTitle: String,
        teachingUnit: String,
        passages: [TranscriptPassage] = [],
        version: Int = 1,
        updatedAt: Date = Date(),
        isDemonstration: Bool = false,
        transcriptionEngine: TranscriptionEngineDescriptor? = nil,
        transcriptionModelID: LocalTranscriptionModelID? = nil,
        rawTranscriptionCompletedAt: Date? = nil
    ) {
        self.courseID = courseID
        self.courseTitle = courseTitle
        self.teachingUnit = teachingUnit
        self.passages = passages
        self.version = max(version, 1)
        self.updatedAt = updatedAt
        self.isDemonstration = isDemonstration
        self.transcriptionEngine = transcriptionEngine
        self.transcriptionModelID = transcriptionModelID
        self.rawTranscriptionCompletedAt = rawTranscriptionCompletedAt
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

public enum SupportTextElementKind: String, Codable, Sendable {
    case heading
    case paragraph
    case listItem
}

public struct SupportTextElement: Equatable, Codable, Sendable {
    public var kind: SupportTextElementKind
    public var text: String
    public var level: Int?
    public var order: Int

    public init(kind: SupportTextElementKind, text: String, level: Int? = nil, order: Int) {
        self.kind = kind
        self.text = text
        self.level = level
        self.order = order
    }
}

public struct SupportExtractedTable: Equatable, Codable, Sendable {
    public var order: Int
    public var rows: [[String]]

    public init(order: Int, rows: [[String]]) {
        self.order = order
        self.rows = rows
    }
}

public struct SupportExtractedPage: Equatable, Codable, Sendable {
    public var number: Int
    public var text: String
    public var hasExtractableText: Bool

    public init(number: Int, text: String, hasExtractableText: Bool) {
        self.number = number
        self.text = text
        self.hasExtractableText = hasExtractableText
    }
}

public enum SupportExtractionWarning: Equatable, Codable, Sendable {
    case scannedOrEmptyPage(Int)
    case noExtractableText
    case imagesRequireReview(Int)

    public var displayName: String {
        switch self {
        case let .scannedOrEmptyPage(page):
            "Page \(page) sans texte extractible (scan possible)."
        case .noExtractableText:
            "Aucun texte extractible n’a été trouvé."
        case let .imagesRequireReview(count):
            "\(count) image(s) conservée(s) comme repères, sans analyse automatique."
        }
    }
}

public struct SupportDocumentExtraction: Equatable, Codable, Sendable {
    public var documentID: UUID
    public var sourceFileName: String
    public var title: String?
    public var extractedAt: Date
    public var textElements: [SupportTextElement]
    public var tables: [SupportExtractedTable]
    public var pages: [SupportExtractedPage]
    public var imageCount: Int
    public var warnings: [SupportExtractionWarning]

    public init(
        documentID: UUID,
        sourceFileName: String,
        title: String? = nil,
        extractedAt: Date = Date(),
        textElements: [SupportTextElement] = [],
        tables: [SupportExtractedTable] = [],
        pages: [SupportExtractedPage] = [],
        imageCount: Int = 0,
        warnings: [SupportExtractionWarning] = []
    ) {
        self.documentID = documentID
        self.sourceFileName = sourceFileName
        self.title = title
        self.extractedAt = extractedAt
        self.textElements = textElements
        self.tables = tables
        self.pages = pages
        self.imageCount = max(imageCount, 0)
        self.warnings = warnings
    }

    public var plainText: String {
        let structuredText = textElements.sorted { $0.order < $1.order }.map(\.text)
        let pageText = pages.sorted { $0.number < $1.number }.map(\.text)
        let tableText = tables.sorted { $0.order < $1.order }
            .flatMap(\.rows)
            .flatMap { $0 }
        return (structuredText + pageText + tableText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

public struct SupportDocument: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var originalFileName: String
    public var localURL: URL?
    public var kind: SupportDocumentKind
    public var byteCount: Int64
    public var importedAt: Date
    public var isDemonstration: Bool
    public var extraction: SupportDocumentExtraction?
    public var extractionFailure: String?

    public init(
        id: UUID = UUID(),
        originalFileName: String,
        localURL: URL?,
        kind: SupportDocumentKind,
        byteCount: Int64,
        importedAt: Date = Date(),
        isDemonstration: Bool = false,
        extraction: SupportDocumentExtraction? = nil,
        extractionFailure: String? = nil
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.localURL = localURL
        self.kind = kind
        self.byteCount = max(byteCount, 0)
        self.importedAt = importedAt
        self.isDemonstration = isDemonstration
        self.extraction = extraction
        self.extractionFailure = extractionFailure
    }
}
