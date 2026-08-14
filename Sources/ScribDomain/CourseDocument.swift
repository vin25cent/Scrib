import Foundation

public enum CourseDocumentKind: String, Codable, Sendable {
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
    public var authority: String
    public var title: String
    public var url: URL
    public var verifiedAt: Date

    public init(authority: String, title: String, url: URL, verifiedAt: Date) {
        self.authority = authority
        self.title = title
        self.url = url
        self.verifiedAt = verifiedAt
    }
}

public enum CourseDocumentBlock: Equatable, Codable, Sendable {
    case paragraph(String)
    case bullets([String])
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
    public var generatedAt: Date

    public init(
        kind: CourseDocumentKind,
        title: String,
        subtitle: String,
        metadata: [CourseDocumentMetadata],
        sections: [CourseDocumentSection],
        sources: [CourseDocumentSource] = [],
        generatedAt: Date = Date()
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.sections = sections
        self.sources = sources
        self.generatedAt = generatedAt
    }
}
