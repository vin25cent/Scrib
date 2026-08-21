import Foundation
import ScribDomain

public enum LocalTranscriptionError: LocalizedError, Equatable, Sendable {
    case noAudioSegments
    case inconsistentCourse
    case modelUnavailable(LocalTranscriptionModelID)
    case modelDisabled(LocalTranscriptionModelID)

    public var errorDescription: String? {
        switch self {
        case .noAudioSegments:
            "Aucun segment audio finalisé n’est disponible pour ce cours."
        case .inconsistentCourse:
            "Les segments audio ne correspondent pas tous au cours sélectionné."
        case let .modelUnavailable(modelID):
            "Le modèle \(modelID.rawValue) n’est pas encore téléchargé."
        case let .modelDisabled(modelID):
            "Le modèle \(modelID.rawValue) est préparé pour un benchmark ultérieur, mais désactivé dans cette alpha."
        }
    }
}

public struct TranscriptBoundaryDeduplicator: Sendable {
    public init() {}

    public func deduplicating(
        _ passages: [RecognizedTranscriptionPassage],
        maximumOverlapWords: Int = 12
    ) -> [RecognizedTranscriptionPassage] {
        let ordered = passages.sorted { lhs, rhs in
            lhs.startTime == rhs.startTime ? lhs.id.uuidString < rhs.id.uuidString : lhs.startTime < rhs.startTime
        }
        guard !ordered.isEmpty else { return [] }

        var result: [RecognizedTranscriptionPassage] = []
        for var passage in ordered where !passage.text.isEmpty {
            guard let previous = result.last,
                  previous.sourceSegmentID != passage.sourceSegmentID else {
                result.append(passage)
                continue
            }

            let previousWords = words(in: previous.text)
            let currentWords = words(in: passage.text)
            let upperBound = min(maximumOverlapWords, previousWords.count, currentWords.count)
            var overlap = 0
            if upperBound > 0 {
                for count in stride(from: upperBound, through: 1, by: -1) {
                    let suffix = previousWords.suffix(count).map(normalized)
                    let prefix = currentWords.prefix(count).map(normalized)
                    if suffix == prefix {
                        overlap = count
                        break
                    }
                }
            }

            guard overlap > 0 else {
                result.append(passage)
                continue
            }
            let remaining = currentWords.dropFirst(overlap).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                passage.text = remaining
                result.append(passage)
            }
        }
        return result
    }

    private func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private func normalized(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }
}

public actor LocalTranscriptionCoordinator {
    private let engine: any TranscriptionEngine
    private let modelManager: any TranscriptionModelManaging
    private let store: any LocalTranscriptionStoring
    private let deduplicator: TranscriptBoundaryDeduplicator

    public init(
        engine: any TranscriptionEngine,
        modelManager: any TranscriptionModelManaging,
        store: any LocalTranscriptionStoring,
        deduplicator: TranscriptBoundaryDeduplicator = .init()
    ) {
        self.engine = engine
        self.modelManager = modelManager
        self.store = store
        self.deduplicator = deduplicator
    }

    public var availableModels: [TranscriptionModelDescriptor] {
        modelManager.availableModels
    }

    public func modelStatus(for modelID: LocalTranscriptionModelID) async -> TranscriptionModelStatus {
        await modelManager.status(for: modelID)
    }

    public func downloadModel(
        _ modelID: LocalTranscriptionModelID,
        progress: @escaping @Sendable (TranscriptionModelStatus) -> Void
    ) async throws -> TranscriptionModelStatus {
        guard LocalTranscriptionModelCatalog.descriptor(for: modelID)?.isEnabledInAlpha == true else {
            throw LocalTranscriptionError.modelDisabled(modelID)
        }
        return try await modelManager.download(modelID, progress: progress)
    }

    public func transcribe(
        course: Course,
        segments: [RecordingSegment],
        modelID: LocalTranscriptionModelID,
        progress: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> StoredLocalTranscription {
        guard LocalTranscriptionModelCatalog.descriptor(for: modelID)?.isEnabledInAlpha == true else {
            throw LocalTranscriptionError.modelDisabled(modelID)
        }
        let orderedSegments = segments.sorted { $0.sequence < $1.sequence }
        guard !orderedSegments.isEmpty else { throw LocalTranscriptionError.noAudioSegments }
        guard orderedSegments.allSatisfy({ $0.courseID == course.id }) else {
            throw LocalTranscriptionError.inconsistentCourse
        }
        guard await modelManager.status(for: modelID).availability == .available else {
            throw LocalTranscriptionError.modelUnavailable(modelID)
        }

        let request = LocalTranscriptionRequest(
            course: course,
            segments: orderedSegments,
            modelID: modelID,
            languageCode: "fr"
        )
        do {
            var result = try await engine.transcribe(request, progress: progress)
            try Task.checkCancellation()
            progress(.init(
                stage: .assembling,
                fractionCompleted: 0.96,
                completedSegmentCount: orderedSegments.count,
                totalSegmentCount: orderedSegments.count,
                elapsedSeconds: result.metrics.processingDurationSeconds
            ))
            result.passages = deduplicator.deduplicating(result.passages)

            let draft = TranscriptDraft(
                courseID: course.id,
                courseTitle: course.title,
                teachingUnit: course.teachingUnit.displayName,
                passages: result.passages.map {
                    TranscriptPassage(
                        id: $0.id,
                        speaker: "Voix non attribuée",
                        startTime: $0.startTime,
                        endTime: $0.endTime,
                        text: $0.text,
                        sourceRecordingSegmentID: $0.sourceSegmentID,
                        confidence: $0.confidence
                    )
                },
                transcriptionEngine: result.engine,
                transcriptionModelID: result.modelID,
                rawTranscriptionCompletedAt: result.completedAt
            )
            let stored = StoredLocalTranscription(
                course: course,
                recordingSegments: orderedSegments,
                result: result,
                draft: draft
            )
            progress(.init(
                stage: .saving,
                fractionCompleted: 0.99,
                completedSegmentCount: orderedSegments.count,
                totalSegmentCount: orderedSegments.count,
                elapsedSeconds: result.metrics.processingDurationSeconds
            ))
            try await store.save(stored)
            progress(.init(
                stage: .completed,
                fractionCompleted: 1,
                completedSegmentCount: orderedSegments.count,
                totalSegmentCount: orderedSegments.count,
                elapsedSeconds: result.metrics.processingDurationSeconds
            ))
            await engine.unload()
            return stored
        } catch {
            await engine.unload()
            throw error
        }
    }

    public func saveEditedDraft(_ draft: TranscriptDraft) async throws {
        try await store.updateDraft(draft)
    }

    public func latestTranscription() async throws -> StoredLocalTranscription? {
        try await store.latest()
    }
}
