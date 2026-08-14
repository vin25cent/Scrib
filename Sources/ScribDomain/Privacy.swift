import Foundation

public enum PrivacyFindingCategory: String, Codable, CaseIterable, Sendable {
    case emailAddress
    case phoneNumber
    case frenchSocialSecurityNumber
    case birthDate
    case postalAddress
    case patientName
    case medicalRecordIdentifier
}

public struct PrivacyFinding: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public var category: PrivacyFindingCategory
    public var utf16Location: Int
    public var utf16Length: Int
    public var redactedPreview: String

    public init(
        id: String? = nil,
        category: PrivacyFindingCategory,
        utf16Location: Int,
        utf16Length: Int,
        redactedPreview: String
    ) {
        self.id = id ?? "\(category.rawValue):\(utf16Location):\(utf16Length)"
        self.category = category
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
        self.redactedPreview = redactedPreview
    }
}

public enum PrivacyReviewDecision: String, Codable, Sendable {
    case approved
    case rejected
}

public struct PrivacyReview: Equatable, Codable, Sendable {
    public var contentFingerprint: String
    public var decision: PrivacyReviewDecision
    public var reviewedAt: Date

    public init(contentFingerprint: String, decision: PrivacyReviewDecision, reviewedAt: Date = Date()) {
        self.contentFingerprint = contentFingerprint
        self.decision = decision
        self.reviewedAt = reviewedAt
    }
}

public enum CloudTransmissionDecision: Equatable, Sendable {
    case allowedNoIdentifiers
    case allowedAfterManualReview
    case blocked([PrivacyFinding])
}
