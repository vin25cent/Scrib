import Foundation

public enum GeneratedBlockType: String, Codable, Sendable {
    case paragraph
    case bullets
    case table
    case callout
    case figure
}

public struct GeneratedCourseSource: Equatable, Codable, Sendable {
    public var id: String
    public var authority: String
    public var title: String
    public var canonicalURL: String
    public var verifiedAt: Date

    public init(id: String, authority: String, title: String, canonicalURL: String, verifiedAt: Date) {
        self.id = id
        self.authority = authority
        self.title = title
        self.canonicalURL = canonicalURL
        self.verifiedAt = verifiedAt
    }
}

public struct GeneratedCourseTable: Equatable, Codable, Sendable {
    public var caption: String?
    public var headers: [String]
    public var rows: [[String]]
    public var columnWidthWeights: [Int]?

    public init(
        caption: String? = nil,
        headers: [String],
        rows: [[String]],
        columnWidthWeights: [Int]? = nil
    ) {
        self.caption = caption
        self.headers = headers
        self.rows = rows
        self.columnWidthWeights = columnWidthWeights
    }
}

public struct GeneratedCourseCallout: Equatable, Codable, Sendable {
    public var kind: CourseDocumentCalloutKind
    public var title: String
    public var body: String
    public var audioTimestampSeconds: Double?

    public init(
        kind: CourseDocumentCalloutKind,
        title: String,
        body: String,
        audioTimestampSeconds: Double? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.audioTimestampSeconds = audioTimestampSeconds
    }
}

public struct GeneratedCourseFigure: Equatable, Codable, Sendable {
    public var assetID: String
    public var caption: String
    public var altText: String
    public var widthPoints: Double?

    public init(assetID: String, caption: String, altText: String, widthPoints: Double? = nil) {
        self.assetID = assetID
        self.caption = caption
        self.altText = altText
        self.widthPoints = widthPoints
    }
}

public struct GeneratedCourseBlock: Equatable, Codable, Sendable {
    public var type: GeneratedBlockType
    public var text: String?
    public var items: [String]?
    public var table: GeneratedCourseTable?
    public var callout: GeneratedCourseCallout?
    public var figure: GeneratedCourseFigure?
    public var sourceIDs: [String]

    public init(
        type: GeneratedBlockType,
        text: String? = nil,
        items: [String]? = nil,
        table: GeneratedCourseTable? = nil,
        callout: GeneratedCourseCallout? = nil,
        figure: GeneratedCourseFigure? = nil,
        sourceIDs: [String] = []
    ) {
        self.type = type
        self.text = text
        self.items = items
        self.table = table
        self.callout = callout
        self.figure = figure
        self.sourceIDs = sourceIDs
    }
}

public struct GeneratedCourseSection: Equatable, Codable, Sendable {
    public var title: String
    public var blocks: [GeneratedCourseBlock]

    public init(title: String, blocks: [GeneratedCourseBlock]) {
        self.title = title
        self.blocks = blocks
    }
}

public struct GeneratedCourseDocument: Equatable, Codable, Sendable {
    public var kind: CourseDocumentKind
    public var title: String
    public var subtitle: String
    public var metadata: [CourseDocumentMetadata]
    public var sections: [GeneratedCourseSection]

    public init(
        kind: CourseDocumentKind,
        title: String,
        subtitle: String,
        metadata: [CourseDocumentMetadata],
        sections: [GeneratedCourseSection]
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.sections = sections
    }
}

public struct CourseGenerationEnvelope: Equatable, Codable, Sendable {
    public var schemaVersion: String
    public var courseID: UUID
    public var documents: [GeneratedCourseDocument]
    public var sources: [GeneratedCourseSource]

    public init(
        schemaVersion: String = "1.0",
        courseID: CourseID,
        documents: [GeneratedCourseDocument],
        sources: [GeneratedCourseSource] = []
    ) {
        self.schemaVersion = schemaVersion
        self.courseID = courseID.rawValue
        self.documents = documents
        self.sources = sources
    }

    public init(
        schemaVersion: String = "1.0",
        courseID: UUID,
        documents: [GeneratedCourseDocument],
        sources: [GeneratedCourseSource] = []
    ) {
        self.schemaVersion = schemaVersion
        self.courseID = courseID
        self.documents = documents
        self.sources = sources
    }
}
