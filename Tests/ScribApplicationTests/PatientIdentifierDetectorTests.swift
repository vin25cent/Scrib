import Foundation
import Testing
import ScribDomain
@testable import ScribApplication

struct PatientIdentifierDetectorTests {
    @Test func detectsSyntheticPatientIdentifiersAndNeverLeaksMatchesInPreview() {
        let text = "Madame Élodie Test, née le 12/03/1990, 12 rue des Lilas. Tél 06 12 34 56 78, test.patient@example.fr, IPP: AB-12345. NIR 2 90 03 75 123 456 78."
        let findings = PatientIdentifierDetector().scan(text)
        let categories = Set(findings.map(\.category))
        #expect(categories.contains(.patientName))
        #expect(categories.contains(.birthDate))
        #expect(categories.contains(.postalAddress))
        #expect(categories.contains(.phoneNumber))
        #expect(categories.contains(.emailAddress))
        #expect(categories.contains(.medicalRecordIdentifier))
        #expect(categories.contains(.frenchSocialSecurityNumber))
        for finding in findings {
            let match = (text as NSString).substring(with: NSRange(location: finding.utf16Location, length: finding.utf16Length))
            #expect(!finding.redactedPreview.contains(match))
            #expect(finding.redactedPreview.contains("[MASQUÉ]"))
        }
    }

    @Test func ordinaryCourseTextPassesWithoutReview() {
        #expect(CloudPrivacyGate().evaluate(text: "Le cœur comporte quatre cavités.", contentFingerprint: "v1", review: nil) == .allowedNoIdentifiers)
    }

    @Test func cloudGateRequiresMatchingExplicitApproval() {
        let text = "Contact patient.test@example.fr"
        let gate = CloudPrivacyGate()
        #expect(gate.evaluate(text: text, contentFingerprint: "v2", review: nil).isBlocked)
        let stale = PrivacyReview(contentFingerprint: "v1", decision: .approved, reviewedAt: Date())
        #expect(gate.evaluate(text: text, contentFingerprint: "v2", review: stale).isBlocked)
        let approval = PrivacyReview(contentFingerprint: "v2", decision: .approved, reviewedAt: Date())
        #expect(gate.evaluate(text: text, contentFingerprint: "v2", review: approval) == .allowedAfterManualReview)
    }
}

private extension CloudTransmissionDecision {
    var isBlocked: Bool { if case .blocked = self { return true }; return false }
}
