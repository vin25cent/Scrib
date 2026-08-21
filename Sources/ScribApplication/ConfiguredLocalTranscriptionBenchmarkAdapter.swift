import Foundation
import ScribDomain

/// Runs the exact same local engine path for Small/Medium and never downloads a model.
/// The selected model must already be present on the machine.
public actor ConfiguredLocalTranscriptionBenchmarkAdapter: TranscriptionBenchmarkAdapter {
    public nonisolated let engineID: String
    public nonisolated let engineVersion: String
    public nonisolated let modelID: String
    public nonisolated let configuration: TranscriptionBenchmarkConfiguration?

    private let engine: any TranscriptionEngine
    private let selectedModelID: LocalTranscriptionModelID
    private let useInitialContext: Bool

    public init(
        engine: any TranscriptionEngine,
        modelID: LocalTranscriptionModelID,
        useInitialContext: Bool = true
    ) {
        self.engine = engine
        self.selectedModelID = modelID
        self.useInitialContext = useInitialContext
        self.engineID = engine.descriptor.id
        self.engineVersion = engine.descriptor.version
        self.modelID = modelID.rawValue
        let variant = LocalTranscriptionModelCatalog.descriptor(for: modelID)?.whisperKitVariant
            ?? modelID.rawValue
        self.configuration = .init(
            modelVariant: variant,
            parameters: [
                "language": "fr",
                "task": "transcribe",
                "temperature": "0.0",
                "temperatureIncrementOnFallback": "0.2",
                "temperatureFallbackCount": "5",
                "sampleLength": "224",
                "topK": "5",
                "skipSpecialTokens": "true",
                "wordTimestamps": "true",
                "chunkingStrategy": "vad",
                "concurrentWorkerCount": "1",
                "compressionRatioThreshold": "2.4",
                "logProbabilityThreshold": "-1.0",
                "noSpeechThreshold": "0.6",
                "initialContext": useInitialContext ? "course-and-critical-terms" : "disabled"
            ]
        )
    }

    public func transcribe(_ benchmarkCase: TranscriptionBenchmarkCase) async throws -> BenchmarkAdapterOutput {
        let courseID = CourseID()
        let course = Course(
            id: courseID,
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1)[0],
            title: benchmarkCase.id,
            teacher: Teacher(name: "Corpus local", recordingAuthorizationConfirmedAt: Date()),
            expectedDuration: .oneHour
        )
        let audioURL = Self.fileURL(from: benchmarkCase.audioID)
        let start = Date(timeIntervalSince1970: 0)
        let segment = RecordingSegment(
            courseID: courseID,
            sequence: 1,
            fileURL: audioURL,
            startedAt: start,
            endedAt: start.addingTimeInterval(benchmarkCase.audioDurationSeconds),
            byteCount: 0
        )
        let context = useInitialContext
            ? LocalTranscriptionContextBuilder.build(
                course: course,
                courseGlossary: benchmarkCase.criticalTerms
            )
            : nil

        do {
            let result = try await engine.transcribe(
                .init(
                    course: course,
                    segments: [segment],
                    modelID: selectedModelID,
                    languageCode: "fr",
                    context: context
                ),
                progress: { _ in }
            )
            await engine.unload()
            return .init(
                transcript: result.userFacingPlainText,
                timestamps: Self.timestamps(
                    for: benchmarkCase.referenceTimestamps.map(\.term),
                    in: result
                ),
                processingDurationSeconds: result.metrics.processingDurationSeconds,
                peakResidentMemoryBytes: result.metrics.peakResidentMemoryBytes,
                modelSizeBytes: result.metrics.modelSizeBytes,
                highestThermalState: result.metrics.highestThermalState,
                machine: result.metrics.machine,
                passageCount: result.passages.count
            )
        } catch {
            await engine.unload()
            throw error
        }
    }

    private static func fileURL(from identifier: String) -> URL {
        if let parsed = URL(string: identifier), parsed.isFileURL { return parsed }
        return URL(fileURLWithPath: identifier)
    }

    private static func timestamps(
        for terms: [String],
        in result: LocalTranscriptionResult
    ) -> [TimestampedTerm] {
        let words = result.passages.flatMap(\.words)
        let normalizedWords = words.map { normalize($0.text) }
        var output: [TimestampedTerm] = []
        for term in Set(terms) {
            let termWords = term.split(whereSeparator: { $0.isWhitespace }).map { normalize(String($0)) }
            guard !termWords.isEmpty, termWords.count <= words.count else { continue }
            for start in 0...(words.count - termWords.count)
            where Array(normalizedWords[start..<(start + termWords.count)]) == termWords {
                output.append(.init(term: term, seconds: words[start].startTime))
            }
        }
        return output
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines))
    }
}
