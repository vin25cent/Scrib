import Foundation
import ScribDomain

public protocol TranscriptionBenchmarkAdapter: Sendable {
    var engineID: String { get }
    var engineVersion: String { get }
    var modelID: String { get }
    func transcribe(_ benchmarkCase: TranscriptionBenchmarkCase) async throws -> BenchmarkAdapterOutput
}

public struct TranscriptionBenchmarkRunner: Sendable {
    private let scorer: TranscriptBenchmarkScorer

    public init(scorer: TranscriptBenchmarkScorer = .init()) { self.scorer = scorer }

    public func run(
        cases: [TranscriptionBenchmarkCase],
        adapters: [any TranscriptionBenchmarkAdapter],
        thermalStateBefore: ThermalCondition = .unknown,
        machine: TranscriptionMachineInformation? = nil
    ) async -> TranscriptionBenchmarkRun {
        var results: [TranscriptionBenchmarkResult] = []
        var failures: [TranscriptionBenchmarkFailure] = []
        var resolvedMachine = machine
        for adapter in adapters {
            for item in cases {
                do {
                    let output = try await adapter.transcribe(item)
                    if resolvedMachine == nil { resolvedMachine = output.machine }
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
        return .init(machine: resolvedMachine, results: results, failures: failures)
    }

    public func encodedReport(_ run: TranscriptionBenchmarkRun) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(run)
    }

    public func writeReport(_ run: TranscriptionBenchmarkRun, to destination: URL) throws {
        try encodedReport(run).write(to: destination, options: .atomic)
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
