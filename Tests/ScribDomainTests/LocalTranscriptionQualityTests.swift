import Foundation
import Testing
@testable import ScribDomain

struct LocalTranscriptionQualityTests {
    @Test func baselineSmallDecodingSettingsAreExplicitAndStable() {
        let settings = LocalTranscriptionDecodingSettings(
            languageCode: "fr",
            initialPromptUsed: true,
            promptTokenCount: 24
        )

        #expect(settings.temperature == 0)
        #expect(settings.temperatureIncrementOnFallback == 0.2)
        #expect(settings.temperatureFallbackCount == 5)
        #expect(settings.sampleLength == 224)
        #expect(settings.topK == 5)
        #expect(settings.wordTimestamps)
        #expect(settings.skipSpecialTokens)
        #expect(settings.chunkingStrategy == "vad")
        #expect(settings.concurrentWorkerCount == 1)
        #expect(settings.compressionRatioThreshold == 2.4)
        #expect(settings.logProbabilityThreshold == -1)
        #expect(settings.noSpeechThreshold == 0.6)
        #expect(settings.promptTokenCount == 24)
    }

    @Test func glossaryDeduplicatesTermsButKeepsGlobalAndCourseScopes() {
        let glossary = TranscriptionGlossary(
            globalTerms: ["IFSI", "mg", "IFSI"],
            courseTerms: ["naloxone", "MEOPA", "naloxone", "mg"]
        )

        #expect(glossary.globalTerms == ["IFSI", "mg"])
        #expect(glossary.courseTerms == ["naloxone", "MEOPA"])
    }

    @Test func detectsRepresentativeDosesAndDurationsWithoutCorrectingText() {
        let examples = [
            "500 mg", "1 g", "4 g par jour", "150 mg/kg", "6 heures",
            "3 à 4 prises", "28 jours"
        ]

        for example in examples {
            #expect(MedicalNumericExpressionDetector.containsCriticalExpression(in: example))
        }
        #expect(!MedicalNumericExpressionDetector.containsCriticalExpression(in: "vingt-huit jours"))
    }

    @Test func supportExtractionReturnsSmallDeterministicCandidateList() {
        let extraction = SupportDocumentExtraction(
            documentID: UUID(),
            sourceFileName: "antalgiques.pdf",
            textElements: [
                .init(kind: .heading, text: "NALOXONE et MEOPA", order: 0),
                .init(kind: .paragraph, text: "La naloxone antagonise les opioïdes. Naloxone et MEOPA.", order: 1)
            ]
        )

        let terms = SupportGlossaryCandidateExtractor.candidates(from: [extraction], maximumCount: 3)

        #expect(terms.contains { $0.caseInsensitiveCompare("naloxone") == .orderedSame })
        #expect(terms.contains("MEOPA"))
        #expect(terms.count <= 3)
    }
}
