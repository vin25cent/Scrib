#if os(macOS)
import Darwin
import Foundation
import ScribApplication
import ScribDomain
@preconcurrency import WhisperKit

public enum WhisperKitTranscriptionError: LocalizedError, Sendable {
    case modelNotInstalled(LocalTranscriptionModelID)
    case noResult(String)

    public var errorDescription: String? {
        switch self {
        case let .modelNotInstalled(modelID):
            "Le modèle \(modelID.rawValue) doit être téléchargé avant la transcription."
        case let .noResult(fileName):
            "WhisperKit n’a retourné aucun résultat pour \(fileName)."
        }
    }
}

public actor WhisperKitTranscriptionEngine: TranscriptionEngine {
    public nonisolated let descriptor = TranscriptionEngineDescriptor(
        id: "whisperkit",
        displayName: "WhisperKit",
        version: "1.0.0"
    )

    private let modelManager: any TranscriptionModelManaging
    private let mapper: WhisperKitResultMapper
    private var loadedKit: WhisperKit?

    public init(
        modelManager: any TranscriptionModelManaging,
        mapper: WhisperKitResultMapper = .init()
    ) {
        self.modelManager = modelManager
        self.mapper = mapper
    }

    public func transcribe(
        _ request: LocalTranscriptionRequest,
        progress: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> LocalTranscriptionResult {
        let startedAt = Date()
        let initialThermal = Self.thermalCondition()
        var highestThermal = initialThermal
        let modelStatus = await modelManager.status(for: request.modelID)
        guard modelStatus.availability == .available, let modelURL = modelStatus.localURL else {
            throw WhisperKitTranscriptionError.modelNotInstalled(request.modelID)
        }
        progress(.init(
            stage: .loadingModel,
            fractionCompleted: 0.02,
            totalSegmentCount: request.segments.count,
            message: "Chargement du modèle Core ML"
        ))

        let kit = try await WhisperKit(WhisperKitConfig(
            modelFolder: modelURL.path,
            tokenizerFolder: modelURL,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        ))
        loadedKit = kit
        let promptTokens: [Int]? = {
            guard let prompt = request.context?.prompt, !prompt.isEmpty, let tokenizer = kit.tokenizer else {
                return nil
            }
            let encoded = tokenizer.encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            return encoded.isEmpty ? nil : encoded
        }()
        let decodingSettings = LocalTranscriptionDecodingSettings(
            languageCode: request.languageCode,
            initialPromptUsed: promptTokens != nil,
            promptTokenCount: promptTokens?.count ?? 0
        )
        let memorySampler = Task<Int64?, Never> {
            var peak: Int64?
            while !Task.isCancelled {
                if let current = Self.currentResidentMemoryBytes() {
                    peak = max(peak ?? current, current)
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            return peak
        }

        do {
            var timelineOffset: TimeInterval = 0
            var passages: [RecognizedTranscriptionPassage] = []
            let total = request.segments.count
            for (index, recordingSegment) in request.segments.enumerated() {
                try Task.checkCancellation()
                let segmentStartFraction = 0.05 + 0.88 * Double(index) / Double(max(total, 1))
                progress(.init(
                    stage: .convertingAudio,
                    fractionCompleted: segmentStartFraction,
                    completedSegmentCount: index,
                    totalSegmentCount: total,
                    elapsedSeconds: Date().timeIntervalSince(startedAt),
                    message: "Préparation du segment \(index + 1) sur \(total)"
                ))
                let windows = max(Int(ceil(recordingSegment.duration / 30)), 1)
                let options = DecodingOptions(
                    language: request.languageCode,
                    temperature: Float(decodingSettings.temperature),
                    temperatureIncrementOnFallback: Float(decodingSettings.temperatureIncrementOnFallback),
                    temperatureFallbackCount: decodingSettings.temperatureFallbackCount,
                    sampleLength: decodingSettings.sampleLength,
                    topK: decodingSettings.topK,
                    usePrefillPrompt: true,
                    skipSpecialTokens: decodingSettings.skipSpecialTokens,
                    wordTimestamps: true,
                    promptTokens: promptTokens,
                    compressionRatioThreshold: decodingSettings.compressionRatioThreshold.map(Float.init),
                    logProbThreshold: decodingSettings.logProbabilityThreshold.map(Float.init),
                    noSpeechThreshold: decodingSettings.noSpeechThreshold.map(Float.init),
                    concurrentWorkerCount: 1,
                    chunkingStrategy: .vad
                )
                let outputs = await kit.transcribeWithResults(
                    audioPaths: [recordingSegment.fileURL.path],
                    decodeOptions: options,
                    callback: { update in
                        let local = min(Double(update.windowId + 1) / Double(windows), 0.99)
                        let fraction = 0.05 + 0.88 * (Double(index) + local) / Double(max(total, 1))
                        progress(.init(
                            stage: .transcribing,
                            fractionCompleted: fraction,
                            completedSegmentCount: index,
                            totalSegmentCount: total,
                            elapsedSeconds: Date().timeIntervalSince(startedAt),
                            message: "Transcription locale du segment \(index + 1)"
                        ))
                        return !Task.isCancelled
                    }
                )
                try Task.checkCancellation()
                guard let first = outputs.first else {
                    throw WhisperKitTranscriptionError.noResult(recordingSegment.fileURL.lastPathComponent)
                }
                let results = try first.get()
                let mappingInputs = results.flatMap { result in
                    result.segments.map { segment in
                        WhisperKitSegmentMappingInput(
                            start: Double(segment.start),
                            end: Double(segment.end),
                            text: segment.text,
                            averageLogProbability: Double(segment.avgLogprob),
                            words: (segment.words ?? []).map {
                                WhisperKitWordMappingInput(
                                    text: $0.word,
                                    start: Double($0.start),
                                    end: Double($0.end),
                                    probability: Double($0.probability)
                                )
                            }
                        )
                    }
                }
                passages.append(contentsOf: mapper.map(
                    mappingInputs,
                    sourceSegmentID: recordingSegment.id,
                    timelineOffset: timelineOffset
                ))
                timelineOffset += recordingSegment.duration
                highestThermal = Self.highest(highestThermal, Self.thermalCondition())
                kit.clearState()
            }

            memorySampler.cancel()
            let peakMemory = await memorySampler.value
            let metrics = LocalTranscriptionMetrics(
                audioDurationSeconds: request.segments.reduce(0) { $0 + $1.duration },
                processingDurationSeconds: Date().timeIntervalSince(startedAt),
                peakResidentMemoryBytes: peakMemory,
                modelSizeBytes: modelStatus.installedSizeBytes,
                thermalStateBefore: initialThermal,
                highestThermalState: highestThermal,
                machine: Self.machineInformation(),
                inputSegmentCount: request.segments.count,
                outputPassageCount: passages.count
            )
            return LocalTranscriptionResult(
                courseID: request.course.id,
                engine: descriptor,
                modelID: request.modelID,
                languageCode: request.languageCode,
                passages: passages,
                metrics: metrics,
                decodingSettings: decodingSettings,
                context: request.context,
                modelVariant: LocalTranscriptionModelCatalog.descriptor(for: request.modelID)?.whisperKitVariant
            )
        } catch {
            memorySampler.cancel()
            _ = await memorySampler.value
            await kit.unloadModels()
            loadedKit = nil
            throw error
        }
    }

    public func unload() async {
        guard let loadedKit else { return }
        await loadedKit.unloadModels()
        loadedKit.clearState()
        self.loadedKit = nil
    }

    private static func currentResidentMemoryBytes() -> Int64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int64(info.resident_size)
    }

    private static func thermalCondition() -> ThermalCondition {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }

    private static func highest(_ lhs: ThermalCondition, _ rhs: ThermalCondition) -> ThermalCondition {
        rank(lhs) >= rank(rhs) ? lhs : rhs
    }

    private static func rank(_ condition: ThermalCondition) -> Int {
        switch condition {
        case .unknown: -1
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        }
    }

    private static func machineInformation() -> TranscriptionMachineInformation {
        TranscriptionMachineInformation(
            hardwareModel: WhisperKit.deviceName(),
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: "arm64"
        )
    }
}
#endif
