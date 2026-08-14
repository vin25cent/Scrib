import Foundation
import ScribDomain

public struct PatientIdentifierDetector: Sendable {
    public init() {}

    public func scan(_ text: String) -> [PrivacyFinding] {
        let patterns: [(PrivacyFindingCategory, String, NSRegularExpression.Options)] = [
            (.emailAddress, #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, [.caseInsensitive]),
            (.phoneNumber, #"(?<!\d)(?:\+33|0)[1-9](?:[ .-]?\d{2}){4}(?!\d)"#, []),
            (.frenchSocialSecurityNumber, #"(?<!\d)[12]\s?\d{2}\s?(?:0[1-9]|1[0-2]|20)\s?\d{2}\s?\d{3}\s?\d{3}\s?\d{2}(?!\d)"#, []),
            (.birthDate, #"\b(?:né|née|naissance)\s+(?:le\s+)?\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#, [.caseInsensitive]),
            (.postalAddress, #"\b\d{1,4}\s+(?:rue|avenue|av\.?|boulevard|bd\.?|chemin|impasse|place)\s+[\p{L}][\p{L}' -]{2,}"#, [.caseInsensitive]),
            (.patientName, #"(?:^|\s)(?:patient|patiente|monsieur|madame|m\.|mme)\s+\p{Lu}[\p{L}'-]+(?:\s+\p{Lu}[\p{L}'-]+)?"#, [.caseInsensitive]),
            (.medicalRecordIdentifier, #"\b(?:IPP|NIP|dossier\s+(?:patient|médical))\s*[:#-]?\s*[A-Z0-9-]{5,}\b"#, [.caseInsensitive])
        ]

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var findings: [PrivacyFinding] = []
        for (category, pattern, options) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            for match in expression.matches(in: text, range: fullRange) {
                findings.append(
                    PrivacyFinding(
                        category: category,
                        utf16Location: match.range.location,
                        utf16Length: match.range.length,
                        redactedPreview: redactedPreview(in: text, range: match.range)
                    )
                )
            }
        }

        return findings
            .sorted {
                ($0.utf16Location, $0.category.rawValue) < ($1.utf16Location, $1.category.rawValue)
            }
            .reduce(into: []) { result, finding in
                guard !result.contains(where: {
                    $0.utf16Location == finding.utf16Location && $0.utf16Length == finding.utf16Length
                }) else { return }
                result.append(finding)
            }
    }

    private func redactedPreview(in text: String, range: NSRange) -> String {
        let nsText = text as NSString
        let prefixLocation = max(range.location - 12, 0)
        let suffixEnd = min(range.location + range.length + 12, nsText.length)
        let prefix = nsText.substring(with: NSRange(location: prefixLocation, length: range.location - prefixLocation))
        let suffixLocation = range.location + range.length
        let suffix = nsText.substring(with: NSRange(location: suffixLocation, length: suffixEnd - suffixLocation))
        return "\(prefix)[MASQUÉ]\(suffix)"
    }
}

public struct CloudPrivacyGate: Sendable {
    private let detector: PatientIdentifierDetector

    public init(detector: PatientIdentifierDetector = .init()) {
        self.detector = detector
    }

    public func evaluate(
        text: String,
        contentFingerprint: String,
        review: PrivacyReview?
    ) -> CloudTransmissionDecision {
        let findings = detector.scan(text)
        guard !findings.isEmpty else { return .allowedNoIdentifiers }
        guard let review,
              review.contentFingerprint == contentFingerprint,
              review.decision == .approved else {
            return .blocked(findings)
        }
        return .allowedAfterManualReview
    }
}
