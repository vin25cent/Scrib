import Foundation
import ScribDomain

public actor LocalTranscriptionBenchmarkAdapter: TranscriptionBenchmarkAdapter {
    public nonisolated let engineID: String
    public nonisolated let engineVersion: String
    public nonisolated let modelID: String

    private let engine: any TranscriptionEngine
    private let selectedModelID: LocalTranscriptionModelID

    public init(engine: any TranscriptionEngine, modelID: LocalTranscriptionModelID) {
        self.engine = engine
        self.selectedModelID = modelID
        self.engineID = engine.descriptor.id
        self.engineVersion = engine.descriptor.version
        self.modelID = modelID.rawValue
    }

    public func transcribe(_ benchmarkCase: TranscriptionBenchmarkCase) async throws -> BenchmarkAdapterOutput {
        let courseID = CourseID()
        let teacher = Teacher(name: "Corpus de benchmark", recordingAuthorizationConfirmedAt: Date())
        let course = Course(
            id: courseID,
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1)[0],
            title: benchmarkCase.id,
            teacher: teacher,
            expectedDuration: .oneHour
        )
        let audioURL: URL
        if let parsed = URL(string: benchmarkCase.audioID), parsed.isFileURL {
            audioURL = parsed
        } else {
            audioURL = URL(fileURLWithPath: benchmarkCase.audioID)
        }
        let startedAt = Date(timeIntervalSince1970: 0)
        let recordingSegment = RecordingSegment(
            courseID: courseID,
            sequence: 1,
            fileURL: audioURL,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(benchmarkCase.audioDurationSeconds),
            byteCount: 0
        )
        do {
            let result = try await engine.transcribe(
                .init(course: course, segments: [recordingSegment], modelID: selectedModelID, languageCode: "fr"),
                progress: { _ in }
            )
            await engine.unload()
            return BenchmarkAdapterOutput(
                transcript: result.plainText,
                timestamps: timestamps(for: benchmarkCase.referenceTimestamps.map(\.term), in: result),
                processingDurationSeconds: result.metrics.processingDurationSeconds,
                peakResidentMemoryBytes: result.metrics.peakResidentMemoryBytes,
                modelSizeBytes: result.metrics.modelSizeBytes,
                highestThermalState: result.metrics.highestThermalState,
                machine: result.metrics.machine
            )
        } catch {
            await engine.unload()
            throw error
        }
    }

    private func timestamps(
        for terms: [String],
        in result: LocalTranscriptionResult
    ) -> [TimestampedTerm] {
        let words = result.passages.flatMap(\.words)
        let normalizedWords = words.map { normalize($0.text) }
        var output: [TimestampedTerm] = []
        for term in Set(terms) {
            let termWords = term.split(whereSeparator: { $0.isWhitespace }).map { normalize(String($0)) }
            guard !termWords.isEmpty, termWords.count <= words.count else { continue }
            for start in 0...(words.count - termWords.count) {
                if Array(normalizedWords[start..<(start + termWords.count)]) == termWords {
                    output.append(.init(term: term, seconds: words[start].startTime))
                }
            }
        }
        return output
    }

    private func normalize(_ value: String) -> String {
        value.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines))
    }
}
