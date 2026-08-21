import Foundation

public enum LocalTranscriptionModelID: String, CaseIterable, Codable, Identifiable, Sendable {
    case tinyMultilingual = "tiny"
    case smallMultilingual = "small"
    case mediumMultilingual = "medium"
    case largeV3Turbo = "large-v3-turbo"

    public var id: String { rawValue }
}

public struct TranscriptionModelDescriptor: Identifiable, Equatable, Codable, Sendable {
    public var id: LocalTranscriptionModelID
    public var displayName: String
    public var whisperKitVariant: String
    public var estimatedDownloadBytes: Int64?
    public var intendedUse: String
    public var isEnabledInAlpha: Bool

    public init(
        id: LocalTranscriptionModelID,
        displayName: String,
        whisperKitVariant: String,
        estimatedDownloadBytes: Int64? = nil,
        intendedUse: String,
        isEnabledInAlpha: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.whisperKitVariant = whisperKitVariant
        self.estimatedDownloadBytes = estimatedDownloadBytes
        self.intendedUse = intendedUse
        self.isEnabledInAlpha = isEnabledInAlpha
    }
}

public enum LocalTranscriptionModelCatalog {
    public static let models: [TranscriptionModelDescriptor] = [
        .init(
            id: .tinyMultilingual,
            displayName: "Tiny — développeur",
            whisperKitVariant: "openai_whisper-tiny",
            estimatedDownloadBytes: 76_600_000,
            intendedUse: "Compatibilité et diagnostic uniquement ; déconseillé pour les cours réels",
            isEnabledInAlpha: true
        ),
        .init(
            id: .smallMultilingual,
            displayName: "Small — recommandé",
            whisperKitVariant: "openai_whisper-small",
            estimatedDownloadBytes: 486_000_000,
            intendedUse: "Baseline locale pour les cours réels en français",
            isEnabledInAlpha: true
        ),
        .init(
            id: .mediumMultilingual,
            displayName: "Medium — à évaluer",
            whisperKitVariant: "openai_whisper-medium",
            intendedUse: "Qualité potentiellement supérieure, plus lent ; à confirmer par benchmark sur ce Mac",
            isEnabledInAlpha: true
        ),
        .init(
            id: .largeV3Turbo,
            displayName: "Large-v3-Turbo",
            whisperKitVariant: "openai_whisper-large-v3-v20240930_turbo_632MB",
            intendedUse: "Benchmark ultérieur sur machine qualifiée",
            isEnabledInAlpha: false
        )
    ]

    public static var alphaModels: [TranscriptionModelDescriptor] {
        models.filter(\.isEnabledInAlpha)
    }

    /// The deliberately small model list shown to ordinary users.
    public static var userFacingModels: [TranscriptionModelDescriptor] {
        models.filter { $0.id == .smallMultilingual || $0.id == .mediumMultilingual }
    }

    public static func descriptor(for id: LocalTranscriptionModelID) -> TranscriptionModelDescriptor? {
        models.first { $0.id == id }
    }
}

public enum TranscriptionModelAvailability: String, Equatable, Codable, Sendable {
    case notDownloaded
    case downloading
    case available
    case failed
}

public struct TranscriptionModelStatus: Equatable, Codable, Sendable {
    public var modelID: LocalTranscriptionModelID
    public var availability: TranscriptionModelAvailability
    public var progress: Double?
    public var localURL: URL?
    public var installedSizeBytes: Int64?
    public var errorMessage: String?

    public init(
        modelID: LocalTranscriptionModelID,
        availability: TranscriptionModelAvailability,
        progress: Double? = nil,
        localURL: URL? = nil,
        installedSizeBytes: Int64? = nil,
        errorMessage: String? = nil
    ) {
        self.modelID = modelID
        self.availability = availability
        self.progress = progress.map { min(max($0, 0), 1) }
        self.localURL = localURL
        self.installedSizeBytes = installedSizeBytes
        self.errorMessage = errorMessage
    }
}

public enum LocalTranscriptionStage: String, Equatable, Codable, Sendable {
    case idle
    case checkingModel
    case loadingModel
    case convertingAudio
    case transcribing
    case assembling
    case saving
    case completed
    case cancelled
    case failed
}

public struct LocalTranscriptionProgress: Equatable, Codable, Sendable {
    public var stage: LocalTranscriptionStage
    public var fractionCompleted: Double?
    public var completedSegmentCount: Int
    public var totalSegmentCount: Int
    public var elapsedSeconds: Double
    public var message: String?

    public init(
        stage: LocalTranscriptionStage,
        fractionCompleted: Double? = nil,
        completedSegmentCount: Int = 0,
        totalSegmentCount: Int = 0,
        elapsedSeconds: Double = 0,
        message: String? = nil
    ) {
        self.stage = stage
        self.fractionCompleted = fractionCompleted.map { min(max($0, 0), 1) }
        self.completedSegmentCount = max(completedSegmentCount, 0)
        self.totalSegmentCount = max(totalSegmentCount, 0)
        self.elapsedSeconds = max(elapsedSeconds, 0)
        self.message = message
    }
}

public struct LocalTranscriptionRequest: Equatable, Sendable {
    public var course: Course
    public var segments: [RecordingSegment]
    public var modelID: LocalTranscriptionModelID
    public var languageCode: String
    public var context: LocalTranscriptionContext?

    public init(
        course: Course,
        segments: [RecordingSegment],
        modelID: LocalTranscriptionModelID,
        languageCode: String = "fr",
        context: LocalTranscriptionContext? = nil
    ) {
        self.course = course
        self.segments = segments.sorted { $0.sequence < $1.sequence }
        self.modelID = modelID
        self.languageCode = languageCode
        self.context = context
    }
}

public struct LocalTranscriptionDecodingSettings: Equatable, Codable, Sendable {
    public var languageCode: String
    public var task: String
    public var temperature: Double
    public var temperatureIncrementOnFallback: Double
    public var temperatureFallbackCount: Int
    public var sampleLength: Int
    public var topK: Int
    public var wordTimestamps: Bool
    public var skipSpecialTokens: Bool
    public var chunkingStrategy: String
    public var concurrentWorkerCount: Int
    public var compressionRatioThreshold: Double?
    public var logProbabilityThreshold: Double?
    public var noSpeechThreshold: Double?
    public var initialPromptUsed: Bool
    public var promptTokenCount: Int

    public init(
        languageCode: String,
        task: String = "transcribe",
        temperature: Double = 0,
        temperatureIncrementOnFallback: Double = 0.2,
        temperatureFallbackCount: Int = 5,
        sampleLength: Int = 224,
        topK: Int = 5,
        wordTimestamps: Bool = true,
        skipSpecialTokens: Bool = true,
        chunkingStrategy: String = "vad",
        concurrentWorkerCount: Int = 1,
        compressionRatioThreshold: Double? = 2.4,
        logProbabilityThreshold: Double? = -1,
        noSpeechThreshold: Double? = 0.6,
        initialPromptUsed: Bool,
        promptTokenCount: Int = 0
    ) {
        self.languageCode = languageCode
        self.task = task
        self.temperature = temperature
        self.temperatureIncrementOnFallback = temperatureIncrementOnFallback
        self.temperatureFallbackCount = temperatureFallbackCount
        self.sampleLength = sampleLength
        self.topK = topK
        self.wordTimestamps = wordTimestamps
        self.skipSpecialTokens = skipSpecialTokens
        self.chunkingStrategy = chunkingStrategy
        self.concurrentWorkerCount = concurrentWorkerCount
        self.compressionRatioThreshold = compressionRatioThreshold
        self.logProbabilityThreshold = logProbabilityThreshold
        self.noSpeechThreshold = noSpeechThreshold
        self.initialPromptUsed = initialPromptUsed
        self.promptTokenCount = max(promptTokenCount, 0)
    }
}

public struct RecognizedTranscriptionPassage: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var sourceSegmentID: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String
    public var confidence: Double?
    public var words: [RecognizedTranscriptionWord]

    public init(
        id: UUID = UUID(),
        sourceSegmentID: UUID,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        confidence: Double? = nil,
        words: [RecognizedTranscriptionWord] = []
    ) {
        self.id = id
        self.sourceSegmentID = sourceSegmentID
        let normalizedStartTime = max(startTime, 0)
        self.startTime = normalizedStartTime
        self.endTime = max(endTime, normalizedStartTime)
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.words = words.sorted { $0.startTime < $1.startTime }
    }
}

public struct RecognizedTranscriptionWord: Equatable, Codable, Sendable {
    public var text: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var probability: Double?

    public init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        probability: Double? = nil
    ) {
        self.text = text
        let normalizedStartTime = max(startTime, 0)
        self.startTime = normalizedStartTime
        self.endTime = max(endTime, normalizedStartTime)
        self.probability = probability.map { min(max($0, 0), 1) }
    }
}

public struct TranscriptionEngineDescriptor: Equatable, Codable, Sendable {
    public var id: String
    public var displayName: String
    public var version: String

    public init(id: String, displayName: String, version: String) {
        self.id = id
        self.displayName = displayName
        self.version = version
    }
}

public struct TranscriptionMachineInformation: Equatable, Codable, Sendable {
    public var hardwareModel: String
    public var processorCount: Int
    public var physicalMemoryBytes: UInt64
    public var operatingSystem: String
    public var architecture: String

    public init(
        hardwareModel: String,
        processorCount: Int,
        physicalMemoryBytes: UInt64,
        operatingSystem: String,
        architecture: String
    ) {
        self.hardwareModel = hardwareModel
        self.processorCount = processorCount
        self.physicalMemoryBytes = physicalMemoryBytes
        self.operatingSystem = operatingSystem
        self.architecture = architecture
    }
}

public struct LocalTranscriptionMetrics: Equatable, Codable, Sendable {
    public var audioDurationSeconds: Double
    public var processingDurationSeconds: Double
    public var peakResidentMemoryBytes: Int64?
    public var modelSizeBytes: Int64?
    public var thermalStateBefore: ThermalCondition
    public var highestThermalState: ThermalCondition
    public var machine: TranscriptionMachineInformation?
    public var inputSegmentCount: Int?
    public var outputPassageCount: Int?

    public init(
        audioDurationSeconds: Double,
        processingDurationSeconds: Double,
        peakResidentMemoryBytes: Int64? = nil,
        modelSizeBytes: Int64? = nil,
        thermalStateBefore: ThermalCondition = .unknown,
        highestThermalState: ThermalCondition = .unknown,
        machine: TranscriptionMachineInformation? = nil,
        inputSegmentCount: Int? = nil,
        outputPassageCount: Int? = nil
    ) {
        self.audioDurationSeconds = max(audioDurationSeconds, 0)
        self.processingDurationSeconds = max(processingDurationSeconds, 0)
        self.peakResidentMemoryBytes = peakResidentMemoryBytes
        self.modelSizeBytes = modelSizeBytes
        self.thermalStateBefore = thermalStateBefore
        self.highestThermalState = highestThermalState
        self.machine = machine
        self.inputSegmentCount = inputSegmentCount.map { max($0, 0) }
        self.outputPassageCount = outputPassageCount.map { max($0, 0) }
    }

    public var realtimeFactor: Double? {
        guard audioDurationSeconds > 0 else { return nil }
        return processingDurationSeconds / audioDurationSeconds
    }
}

public struct LocalTranscriptionResult: Equatable, Codable, Sendable {
    public var courseID: CourseID
    public var engine: TranscriptionEngineDescriptor
    public var modelID: LocalTranscriptionModelID
    public var languageCode: String
    public var passages: [RecognizedTranscriptionPassage]
    public var metrics: LocalTranscriptionMetrics
    public var completedAt: Date
    public var decodingSettings: LocalTranscriptionDecodingSettings?
    public var context: LocalTranscriptionContext?
    public var modelVariant: String?

    public init(
        courseID: CourseID,
        engine: TranscriptionEngineDescriptor,
        modelID: LocalTranscriptionModelID,
        languageCode: String,
        passages: [RecognizedTranscriptionPassage],
        metrics: LocalTranscriptionMetrics,
        completedAt: Date = Date(),
        decodingSettings: LocalTranscriptionDecodingSettings? = nil,
        context: LocalTranscriptionContext? = nil,
        modelVariant: String? = nil
    ) {
        self.courseID = courseID
        self.engine = engine
        self.modelID = modelID
        self.languageCode = languageCode
        self.passages = passages.sorted { lhs, rhs in
            lhs.startTime == rhs.startTime ? lhs.id.uuidString < rhs.id.uuidString : lhs.startTime < rhs.startTime
        }
        self.metrics = metrics
        self.completedAt = completedAt
        self.decodingSettings = decodingSettings
        self.context = context
        self.modelVariant = modelVariant
    }

    public var plainText: String {
        passages.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public var userFacingPlainText: String {
        passages.map { WhisperTranscriptTextNormalizer.normalize($0.text) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public struct StoredLocalTranscription: Equatable, Codable, Sendable {
    public var course: Course
    public var recordingSegments: [RecordingSegment]
    public var result: LocalTranscriptionResult
    public var draft: TranscriptDraft
    public var transformations: [TranscriptTransformation]?

    public init(
        course: Course,
        recordingSegments: [RecordingSegment],
        result: LocalTranscriptionResult,
        draft: TranscriptDraft,
        transformations: [TranscriptTransformation] = []
    ) {
        self.course = course
        self.recordingSegments = recordingSegments.sorted { $0.sequence < $1.sequence }
        self.result = result
        self.draft = draft
        self.transformations = transformations
    }
}
