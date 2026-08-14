import Foundation

public enum CourseDocumentKind: String, Codable, CaseIterable, Sendable {
    case fullCourse
    case revisionSheet
}

public struct CourseDocumentMetadata: Equatable, Codable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public enum CourseDocumentCalloutKind: String, Codable, Sendable {
    case information
    case uncertainty
    case medicalImportance
    case scientificUpdate
}

public struct CourseDocumentSource: Equatable, Codable, Sendable {
    public var id: String
    public var authority: String
    public var title: String
    public var url: URL
    public var verifiedAt: Date

    public init(
        id: String = "",
        authority: String,
        title: String,
        url: URL,
        verifiedAt: Date
    ) {
        self.id = id
        self.authority = authority
        self.title = title
        self.url = url
        self.verifiedAt = verifiedAt
    }
}

public struct CourseDocumentTable: Equatable, Codable, Sendable {
    public var caption: String?
    public var headers: [String]
    public var rows: [[String]]
    public var columnWidthWeights: [Int]

    public init(
        caption: String? = nil,
        headers: [String],
        rows: [[String]],
        columnWidthWeights: [Int] = []
    ) {
        self.caption = caption
        self.headers = headers
        self.rows = rows
        self.columnWidthWeights = columnWidthWeights
    }
}

public struct CourseDocumentFigure: Equatable, Codable, Sendable {
    public var assetID: String
    public var caption: String
    public var altText: String
    public var widthPoints: Double

    public init(assetID: String, caption: String, altText: String, widthPoints: Double = 360) {
        self.assetID = assetID
        self.caption = caption
        self.altText = altText
        self.widthPoints = widthPoints
    }
}

public enum CourseDocumentImageFormat: String, Codable, Sendable {
    case png
    case jpeg

    public var fileExtension: String { self == .png ? "png" : "jpg" }
    public var contentType: String { self == .png ? "image/png" : "image/jpeg" }
}

public struct CourseDocumentImageAsset: Equatable, Codable, Sendable {
    public var id: String
    public var format: CourseDocumentImageFormat
    public var widthPixels: Int
    public var heightPixels: Int
    public var data: Data

    public init(
        id: String,
        format: CourseDocumentImageFormat,
        widthPixels: Int,
        heightPixels: Int,
        data: Data
    ) {
        self.id = id
        self.format = format
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.data = data
    }
}

public enum CourseDocumentBlock: Equatable, Codable, Sendable {
    case paragraph(String)
    case bullets([String])
    case table(CourseDocumentTable)
    case figure(CourseDocumentFigure)
    case callout(kind: CourseDocumentCalloutKind, title: String, body: String, audioTimestamp: TimeInterval?)
}

public struct CourseDocumentSection: Equatable, Codable, Sendable {
    public var title: String
    public var blocks: [CourseDocumentBlock]

    public init(title: String, blocks: [CourseDocumentBlock]) {
        self.title = title
        self.blocks = blocks
    }
}

public struct CourseDocument: Equatable, Codable, Sendable {
    public var kind: CourseDocumentKind
    public var title: String
    public var subtitle: String
    public var metadata: [CourseDocumentMetadata]
    public var sections: [CourseDocumentSection]
    public var sources: [CourseDocumentSource]
    public var imageAssets: [CourseDocumentImageAsset]
    public var generatedAt: Date

    public init(
        kind: CourseDocumentKind,
        title: String,
        subtitle: String,
        metadata: [CourseDocumentMetadata],
        sections: [CourseDocumentSection],
        sources: [CourseDocumentSource] = [],
        imageAssets: [CourseDocumentImageAsset] = [],
        generatedAt: Date = Date()
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.sections = sections
        self.sources = sources
        self.imageAssets = imageAssets
        self.generatedAt = generatedAt
    }
}
