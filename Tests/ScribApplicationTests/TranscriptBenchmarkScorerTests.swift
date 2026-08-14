import Testing
import ScribApplication
import ScribDomain

struct TranscriptBenchmarkScorerTests {
    private let scorer = TranscriptBenchmarkScorer()

    @Test func identicalTranscriptHasPerfectScores() {
        let metrics = scorer.score(
            reference: "Le nœud atrio-ventriculaire conduit le signal.",
            hypothesis: "Le nœud atrio-ventriculaire conduit le signal.",
            criticalTerms: ["nœud atrio-ventriculaire"]
        )

        #expect(metrics.strictWordErrorRate == 0)
        #expect(metrics.relaxedWordErrorRate == 0)
        #expect(metrics.characterErrorRate == 0)
        #expect(metrics.criticalTermRecall == 1)
    }

    @Test func strictAndRelaxedScoresExposeAccentDifferences() {
        let metrics = scorer.score(
            reference: "La thérapeutique est étudiée.",
            hypothesis: "La therapeutique est etudiee."
        )

        #expect(metrics.strictWordErrorRate > 0)
        #expect(metrics.relaxedWordErrorRate == 0)
    }

    @Test func wordErrorRateCountsSubstitutionInsertionAndDeletion() {
        let metrics = scorer.score(
            reference: "un deux trois quatre",
            hypothesis: "un autre trois quatre cinq"
        )

        #expect(metrics.strictWordErrorRate == 0.5)
    }

    @Test func criticalTermRecallSupportsMultiwordTerms() {
        let metrics = scorer.score(
            reference: "Exemple de cours.",
            hypothesis: "Le faisceau de His conduit ensuite le signal.",
            criticalTerms: ["faisceau de His", "nœud sinusal"]
        )

        #expect(metrics.criticalTermRecall == 0.5)
    }

    @Test func timestampMetricUsesNearestMatchingOccurrence() {
        let metrics = scorer.score(
            reference: "fracture du fémur",
            hypothesis: "fracture du fémur",
            referenceTimestamps: [TimestampedTerm(term: "fracture", seconds: 120)],
            hypothesisTimestamps: [
                TimestampedTerm(term: "fracture", seconds: 15),
                TimestampedTerm(term: "fracture", seconds: 123.5)
            ]
        )

        #expect(metrics.meanTimestampErrorSeconds == 3.5)
    }

    @Test func resourceMetricsExposeRealtimeFactor() {
        let metrics = TranscriptionResourceMetrics(
            audioDurationSeconds: 600,
            processingDurationSeconds: 300
        )

        #expect(metrics.realtimeFactor == 0.5)
    }

    @Test func timestampOccurrencesAreNotReused() {
        let metrics = scorer.score(
            reference: "fracture puis fracture",
            hypothesis: "fracture puis fracture",
            referenceTimestamps: [
                TimestampedTerm(term: "fracture", seconds: 10),
                TimestampedTerm(term: "fracture", seconds: 100)
            ],
            hypothesisTimestamps: [
                TimestampedTerm(term: "fracture", seconds: 12),
                TimestampedTerm(term: "fracture", seconds: 94)
            ]
        )

        #expect(metrics.meanTimestampErrorSeconds == 4)
    }
}
