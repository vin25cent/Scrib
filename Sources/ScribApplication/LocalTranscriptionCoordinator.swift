import Foundation
import ScribDomain

public enum LocalTranscriptionError: LocalizedError, Equatable, Sendable {
    case noAudioSegments
    case inconsistentCourse
    case modelUnavailable(LocalTranscriptionModelID)
    case modelDisabled(LocalTranscriptionModelID)
    case noPendingReplacement

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
        case .noPendingReplacement:
            "Aucune nouvelle transcription n’attend de confirmation."
        }
    }
}

public enum RetranscriptionCompletion: Equatable, Sendable {
    case saved(StoredLocalTranscription)
    case replacementPending(StoredLocalTranscription)

    public var transcription: StoredLocalTranscription {
        switch self {
        case let .saved(transcription), let .replacementPending(transcription): transcription
        }
    }
}

public struct TranscriptBoundaryDeduplicator: Sendable {
    public init() {}

    /// Removes only duplicates that can be aligned to word timestamps.
    /// Passages without word timing stay unchanged because temporal fidelity wins.
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

            guard !previous.words.isEmpty, !passage.words.isEmpty else {
                result.append(passage)
                continue
            }

            let previousWords = previous.words.map(\.text)
            let currentWords = passage.words.map(\.text)
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
            let remainingWords = Array(passage.words.dropFirst(overlap))
            let remaining = remainingWords.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                passage.text = remaining
                passage.words = remainingWords
                passage.startTime = remainingWords[0].startTime
                result.append(passage)
            }
        }
        return result
    }

    private func normalized(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }
}

public actor LocalTranscriptionCoordinator {
    private enum PersistenceMode {
        case saveImmediately
        case stageWhenReplacing
    }
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
        globalGlossary: [String] = TranscriptionGlossary.minimalMedical.globalTerms,
        courseGlossary: [String] = [],
        supportDocuments: [SupportDocumentExtraction] = [],
        progress: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> StoredLocalTranscription {
        try await performTranscription(
            course: course,
            segments: segments,
            modelID: modelID,
            globalGlossary: globalGlossary,
            courseGlossary: courseGlossary,
            supportDocuments: supportDocuments,
            persistence: .saveImmediately,
            progress: progress
        ).transcription
    }

    /// Uses the normal pipeline while keeping an existing transcription untouched
    /// until the caller explicitly promotes the completed candidate.
    public func retranscribe(
        course: Course,
        segments: [RecordingSegment],
        modelID: LocalTranscriptionModelID,
        globalGlossary: [String] = TranscriptionGlossary.minimalMedical.globalTerms,
        courseGlossary: [String] = [],
        supportDocuments: [SupportDocumentExtraction] = [],
        progress: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> RetranscriptionCompletion {
        try await performTranscription(
            course: course,
            segments: segments,
            modelID: modelID,
            globalGlossary: globalGlossary,
            courseGlossary: courseGlossary,
            supportDocuments: supportDocuments,
            persistence: .stageWhenReplacing,
            progress: progress
        )
    }

    private func performTranscription(
        course: Course,
        segments: [RecordingSegment],
        modelID: LocalTranscriptionModelID,
        globalGlossary: [String] = TranscriptionGlossary.minimalMedical.globalTerms,
        courseGlossary: [String] = [],
        supportDocuments: [SupportDocumentExtraction] = [],
        persistence: PersistenceMode,
        progress: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> RetranscriptionCompletion {
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

        let supportCandidates = SupportGlossaryCandidateExtractor.candidates(from: supportDocuments)
        let context = LocalTranscriptionContextBuilder.build(
            course: course,
            globalGlossary: globalGlossary,
            courseGlossary: courseGlossary,
            supportCandidateTerms: supportCandidates
        )
        let request = LocalTranscriptionRequest(
            course: course,
            segments: orderedSegments,
            modelID: modelID,
            languageCode: "fr",
            context: context
        )
        do {
            let result = try await engine.transcribe(request, progress: progress)
            try Task.checkCancellation()
            progress(.init(
                stage: .assembling,
                fractionCompleted: 0.96,
                completedSegmentCount: orderedSegments.count,
                totalSegmentCount: orderedSegments.count,
                elapsedSeconds: result.metrics.processingDurationSeconds
            ))
            let contextualizedPassages = deduplicator.deduplicating(result.passages)
            var transformations: [TranscriptTransformation] = []
            let rawByID = Dictionary(uniqueKeysWithValues: result.passages.map { ($0.id, $0) })

            let draft = TranscriptDraft(
                courseID: course.id,
                courseTitle: course.title,
                teachingUnit: course.teachingUnit.displayName,
                passages: contextualizedPassages.compactMap {
                    let userFacingText = WhisperTranscriptTextNormalizer.normalize($0.text)
                    guard !userFacingText.isEmpty else { return nil }
                    if let raw = rawByID[$0.id], raw.text != $0.text || raw.startTime != $0.startTime {
                        transformations.append(.init(
                            passageID: $0.id,
                            kind: .boundaryDeduplication,
                            originalText: raw.text,
                            resultingText: $0.text,
                            originalStartTime: raw.startTime,
                            resultingStartTime: $0.startTime
                        ))
                    }
                    if userFacingText != $0.text {
                        transformations.append(.init(
                            passageID: $0.id,
                            kind: .whisperControlTokenRemoval,
                            originalText: $0.text,
                            resultingText: userFacingText,
                            originalStartTime: $0.startTime,
                            resultingStartTime: $0.startTime
                        ))
                    }
                    let reviewReasons = TranscriptionReviewPolicy.reasons(for: $0)
                    let flags: Set<TranscriptPassageFlag>
                    if reviewReasons.contains(.lowConfidenceCriticalNumber) {
                        flags = [.uncertainty, .criticalNumber]
                    } else if reviewReasons.contains(.lowConfidence) {
                        flags = [.uncertainty]
                    } else {
                        flags = []
                    }
                    return TranscriptPassage(
                        id: $0.id,
                        speaker: "Voix non attribuée",
                        startTime: $0.startTime,
                        endTime: $0.endTime,
                        text: userFacingText,
                        flags: flags,
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
                draft: draft,
                transformations: transformations
            )
            progress(.init(
                stage: .saving,
                fractionCompleted: 0.99,
                completedSegmentCount: orderedSegments.count,
                totalSegmentCount: orderedSegments.count,
                elapsedSeconds: result.metrics.processingDurationSeconds
            ))
            let completion: RetranscriptionCompletion
            switch persistence {
            case .saveImmediately:
                try await store.save(stored)
                completion = .saved(stored)
            case .stageWhenReplacing:
                if try await store.transcription(for: course.id) == nil {
                    try await store.save(stored)
                    completion = .saved(stored)
                } else {
                    try await store.saveReplacementCandidate(stored)
                    completion = .replacementPending(stored)
                }
            }
            progress(.init(
                stage: .completed,
                fractionCompleted: 1,
                completedSegmentCount: orderedSegments.count,
                totalSegmentCount: orderedSegments.count,
                elapsedSeconds: result.metrics.processingDurationSeconds
            ))
            await engine.unload()
            return completion
        } catch {
            await engine.unload()
            throw error
        }
    }

    public func saveEditedDraft(_ draft: TranscriptDraft) async throws {
        try await store.updateDraft(draft)
    }

    public func confirmReplacement(for courseID: CourseID) async throws -> StoredLocalTranscription {
        try await store.promoteReplacementCandidate(for: courseID)
    }

    public func keepExistingTranscription(for courseID: CourseID) async throws {
        try await store.discardReplacementCandidate(for: courseID)
    }

    public func transcription(for courseID: CourseID) async throws -> StoredLocalTranscription? {
        try await store.transcription(for: courseID)
    }

    public func latestTranscription() async throws -> StoredLocalTranscription? {
        try await store.latest()
    }
}
