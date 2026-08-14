import Foundation
import ScribDomain

public protocol TranscriptionBenchmarkAdapter: Sendable {
    var engineID: String { get }
    var engineVersion: String { get }
    var modelID: String { get }
    func transcribe(_ benchmarkCase: TranscriptionBenchmarkCase) throws -> BenchmarkAdapterOutput
}

public struct TranscriptionBenchmarkRunner: Sendable {
    private let scorer: TranscriptBenchmarkScorer

    public init(scorer: TranscriptBenchmarkScorer = .init()) { self.scorer = scorer }

    public func run(
        cases: [TranscriptionBenchmarkCase],
        adapters: [any TranscriptionBenchmarkAdapter],
        thermalStateBefore: ThermalCondition = .unknown
    ) -> TranscriptionBenchmarkRun {
        var results: [TranscriptionBenchmarkResult] = []
        var failures: [TranscriptionBenchmarkFailure] = []
        for adapter in adapters {
            for item in cases {
                do {
                    let output = try adapter.transcribe(item)
                    results.append(.init(
                        engineID: adapter.engineID,
                        engineVersion: adapter.engineVersion,
                        modelID: adapter.modelID,
                        corpusItemID: item.id,
                        accuracy: scorer.score(
                            reference: item.referenceTranscript,
                            hypothesis: output.transcript,
                            criticalTerms: item.criticalTerms,
                            referenceTimestamps: item.referenceTimestamps,
                            hypothesisTimestamps: output.timestamps
                        ),
                        resources: .init(
                            audioDurationSeconds: item.audioDurationSeconds,
                            processingDurationSeconds: output.processingDurationSeconds,
                            peakResidentMemoryBytes: output.peakResidentMemoryBytes,
                            modelSizeBytes: output.modelSizeBytes,
                            thermalStateBefore: thermalStateBefore,
                            highestThermalState: output.highestThermalState
                        )
                    ))
                } catch {
                    failures.append(.init(engineID: adapter.engineID, corpusItemID: item.id, message: String(describing: error)))
                }
            }
        }
        return .init(results: results, failures: failures)
    }
}

public struct SimulatedTranscriptionAdapter: TranscriptionBenchmarkAdapter {
    public var engineID: String
    public var engineVersion: String
    public var modelID: String
    public var outputsByAudioID: [String: BenchmarkAdapterOutput]

    public init(engineID: String, engineVersion: String, modelID: String, outputsByAudioID: [String: BenchmarkAdapterOutput]) {
        self.engineID = engineID
        self.engineVersion = engineVersion
        self.modelID = modelID
        self.outputsByAudioID = outputsByAudioID
    }

    public func transcribe(_ benchmarkCase: TranscriptionBenchmarkCase) throws -> BenchmarkAdapterOutput {
        guard let output = outputsByAudioID[benchmarkCase.audioID] else { throw MissingSimulationOutput(audioID: benchmarkCase.audioID) }
        return output
    }
}

public struct MissingSimulationOutput: Error, Equatable, Sendable {
    public var audioID: String
    public init(audioID: String) { self.audioID = audioID }
}
