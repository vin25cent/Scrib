import Foundation

public struct TimestampedTerm: Equatable, Codable, Sendable {
    public var term: String
    public var seconds: Double

    public init(term: String, seconds: Double) {
        self.term = term
        self.seconds = max(seconds, 0)
    }
}

public struct TranscriptAccuracyMetrics: Equatable, Codable, Sendable {
    public var strictWordErrorRate: Double
    public var relaxedWordErrorRate: Double
    public var characterErrorRate: Double
    public var criticalTermRecall: Double
    public var meanTimestampErrorSeconds: Double?
    public var referenceWordCount: Int

    public init(
        strictWordErrorRate: Double,
        relaxedWordErrorRate: Double,
        characterErrorRate: Double,
        criticalTermRecall: Double,
        meanTimestampErrorSeconds: Double?,
        referenceWordCount: Int
    ) {
        self.strictWordErrorRate = strictWordErrorRate
        self.relaxedWordErrorRate = relaxedWordErrorRate
        self.characterErrorRate = characterErrorRate
        self.criticalTermRecall = criticalTermRecall
        self.meanTimestampErrorSeconds = meanTimestampErrorSeconds
        self.referenceWordCount = referenceWordCount
    }
}

public struct TranscriptionResourceMetrics: Equatable, Codable, Sendable {
    public var audioDurationSeconds: Double
    public var processingDurationSeconds: Double
    public var peakResidentMemoryBytes: Int64?
    public var modelSizeBytes: Int64?
    public var thermalStateBefore: ThermalCondition
    public var highestThermalState: ThermalCondition

    public init(
        audioDurationSeconds: Double,
        processingDurationSeconds: Double,
        peakResidentMemoryBytes: Int64? = nil,
        modelSizeBytes: Int64? = nil,
        thermalStateBefore: ThermalCondition = .unknown,
        highestThermalState: ThermalCondition = .unknown
    ) {
        self.audioDurationSeconds = max(audioDurationSeconds, 0)
        self.processingDurationSeconds = max(processingDurationSeconds, 0)
        self.peakResidentMemoryBytes = peakResidentMemoryBytes
        self.modelSizeBytes = modelSizeBytes
        self.thermalStateBefore = thermalStateBefore
        self.highestThermalState = highestThermalState
    }

    public var realtimeFactor: Double? {
        guard audioDurationSeconds > 0 else { return nil }
        return processingDurationSeconds / audioDurationSeconds
    }
}

public struct TranscriptionBenchmarkResult: Equatable, Codable, Sendable {
    public var engineID: String
    public var engineVersion: String
    public var modelID: String
    public var corpusItemID: String
    public var accuracy: TranscriptAccuracyMetrics
    public var resources: TranscriptionResourceMetrics

    public init(
        engineID: String,
        engineVersion: String,
        modelID: String,
        corpusItemID: String,
        accuracy: TranscriptAccuracyMetrics,
        resources: TranscriptionResourceMetrics
    ) {
        self.engineID = engineID
        self.engineVersion = engineVersion
        self.modelID = modelID
        self.corpusItemID = corpusItemID
        self.accuracy = accuracy
        self.resources = resources
    }
}

public struct TranscriptionBenchmarkCase: Equatable, Codable, Sendable {
    public var id: String
    public var audioID: String
    public var audioDurationSeconds: Double
    public var referenceTranscript: String
    public var criticalTerms: [String]
    public var referenceTimestamps: [TimestampedTerm]

    public init(
        id: String,
        audioID: String,
        audioDurationSeconds: Double,
        referenceTranscript: String,
        criticalTerms: [String] = [],
        referenceTimestamps: [TimestampedTerm] = []
    ) {
        self.id = id
        self.audioID = audioID
        self.audioDurationSeconds = max(audioDurationSeconds, 0)
        self.referenceTranscript = referenceTranscript
        self.criticalTerms = criticalTerms
        self.referenceTimestamps = referenceTimestamps
    }
}

public struct BenchmarkAdapterOutput: Equatable, Codable, Sendable {
    public var transcript: String
    public var timestamps: [TimestampedTerm]
    public var processingDurationSeconds: Double
    public var peakResidentMemoryBytes: Int64?
    public var modelSizeBytes: Int64?
    public var highestThermalState: ThermalCondition
    public var machine: TranscriptionMachineInformation?

    public init(
        transcript: String,
        timestamps: [TimestampedTerm] = [],
        processingDurationSeconds: Double,
        peakResidentMemoryBytes: Int64? = nil,
        modelSizeBytes: Int64? = nil,
        highestThermalState: ThermalCondition = .unknown,
        machine: TranscriptionMachineInformation? = nil
    ) {
        self.transcript = transcript
        self.timestamps = timestamps
        self.processingDurationSeconds = max(processingDurationSeconds, 0)
        self.peakResidentMemoryBytes = peakResidentMemoryBytes
        self.modelSizeBytes = modelSizeBytes
        self.highestThermalState = highestThermalState
        self.machine = machine
    }
}

public struct TranscriptionBenchmarkFailure: Equatable, Codable, Sendable {
    public var engineID: String
    public var corpusItemID: String
    public var message: String

    public init(engineID: String, corpusItemID: String, message: String) {
        self.engineID = engineID
        self.corpusItemID = corpusItemID
        self.message = message
    }
}

public struct TranscriptionBenchmarkRun: Equatable, Codable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var machine: TranscriptionMachineInformation?
    public var results: [TranscriptionBenchmarkResult]
    public var failures: [TranscriptionBenchmarkFailure]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        machine: TranscriptionMachineInformation? = nil,
        results: [TranscriptionBenchmarkResult],
        failures: [TranscriptionBenchmarkFailure]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.machine = machine
        self.results = results
        self.failures = failures
    }
}
