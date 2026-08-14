import Testing
import ScribDomain
@testable import ScribApplication

struct TranscriptionBenchmarkRunnerTests {
    @Test func comparesSimulatedAdaptersWithoutAudioOrPaidModels() {
        let item = TranscriptionBenchmarkCase(
            id: "ue21-noise",
            audioID: "synthetic://ue21-noise",
            audioDurationSeconds: 120,
            referenceTranscript: "La membrane plasmique protège la cellule.",
            criticalTerms: ["membrane plasmique"],
            referenceTimestamps: [.init(term: "membrane plasmique", seconds: 12)]
        )
        let exact = SimulatedTranscriptionAdapter(engineID: "sim-exact", engineVersion: "1", modelID: "fixture", outputsByAudioID: [item.audioID: .init(transcript: item.referenceTranscript, timestamps: [.init(term: "membrane plasmique", seconds: 12.5)], processingDurationSeconds: 30, peakResidentMemoryBytes: 900_000_000)])
        let degraded = SimulatedTranscriptionAdapter(engineID: "sim-degraded", engineVersion: "1", modelID: "fixture", outputsByAudioID: [item.audioID: .init(transcript: "La membrane protège cellule.", processingDurationSeconds: 150)])

        let run = TranscriptionBenchmarkRunner().run(cases: [item], adapters: [exact, degraded])
        #expect(run.failures.isEmpty)
        #expect(run.results.count == 2)
        #expect(run.results[0].accuracy.strictWordErrorRate == 0)
        #expect(run.results[0].resources.realtimeFactor == 0.25)
        #expect(run.results[1].accuracy.strictWordErrorRate > 0)
        #expect(run.results[1].resources.realtimeFactor == 1.25)
    }

    @Test func missingSimulationIsReportedWithoutStoppingOtherCases() {
        let present = TranscriptionBenchmarkCase(id: "a", audioID: "a", audioDurationSeconds: 1, referenceTranscript: "a")
        let missing = TranscriptionBenchmarkCase(id: "b", audioID: "b", audioDurationSeconds: 1, referenceTranscript: "b")
        let adapter = SimulatedTranscriptionAdapter(engineID: "sim", engineVersion: "1", modelID: "fixture", outputsByAudioID: ["a": .init(transcript: "a", processingDurationSeconds: 1)])
        let run = TranscriptionBenchmarkRunner().run(cases: [present, missing], adapters: [adapter])
        #expect(run.results.count == 1)
        #expect(run.failures.count == 1)
        #expect(run.failures[0].corpusItemID == "b")
    }
}
