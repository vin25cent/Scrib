import Foundation
import ScribDomain
import Testing
@testable import ScribApplication

struct CourseWorkspaceServiceTests {
    @Test func filtersAndUpdatesTranscriptPassages() {
        let uncertain = TranscriptPassage(speaker: "Enseignant", startTime: 12, text: "Terme incertain", flags: [.uncertainty])
        let important = TranscriptPassage(speaker: "Enseignant", startTime: 20, text: "Valeur importante", flags: [.medicalImportance])
        let draft = TranscriptDraft(courseTitle: "Cours", teachingUnit: "UE 2.1", passages: [uncertain, important])
        let service = TranscriptWorkspaceService()

        #expect(service.passages(in: draft, matching: "", filter: .uncertainty) == [uncertain])
        let updated = service.updating(draft, passageID: uncertain.id, text: "Texte corrigé")
        #expect(updated.passages[0].text == "Texte corrigé")
        #expect(updated.version == 2)
        #expect(service.contentFingerprint(for: updated) != service.contentFingerprint(for: draft))
    }

    @Test func togglesFlagsWithoutTouchingOtherPassages() {
        let passage = TranscriptPassage(speaker: "Enseignant", startTime: 0, text: "Texte")
        let draft = TranscriptDraft(courseTitle: "Cours", teachingUnit: "UE", passages: [passage])
        let service = TranscriptWorkspaceService()

        let flagged = service.toggling(.medicalImportance, in: draft, passageID: passage.id)
        #expect(flagged.passages[0].flags == [.medicalImportance])
        let cleared = service.toggling(.medicalImportance, in: flagged, passageID: passage.id)
        #expect(cleared.passages[0].flags.isEmpty)
    }

    @Test func supportValidatorRejectsOutputsAndAcceptsTeacherDocuments() throws {
        let validator = SupportImportValidator(maximumBytes: 1_000)
        #expect(try validator.validate(fileName: "Support enseignant.docx", byteCount: 900) == .word)
        #expect(throws: SupportImportIssue.generatedDocument) {
            try validator.validate(fileName: "Cours complet - biologie.docx", byteCount: 900)
        }
        #expect(throws: SupportImportIssue.fileTooLarge(maximumBytes: 1_000)) {
            try validator.validate(fileName: "Support.pdf", byteCount: 1_001)
        }
    }

    @Test func demonstrationDataIsExplicitAndTriggersPrivacyReview() {
        let draft = DemonstrationWorkspaceFactory().transcript()
        let findings = PatientIdentifierDetector().scan(draft.plainText)
        #expect(draft.isDemonstration)
        #expect(draft.passages.contains { $0.flags.contains(.uncertainty) })
        #expect(draft.passages.contains { $0.flags.contains(.medicalImportance) })
        #expect(!findings.isEmpty)
    }
}
