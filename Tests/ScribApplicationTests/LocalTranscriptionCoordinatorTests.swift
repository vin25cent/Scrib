import Foundation
import Testing
import ScribDomain
@testable import ScribApplication

private actor FakeLocalEngine: TranscriptionEngine {
    nonisolated let descriptor = TranscriptionEngineDescriptor(id: "fake", displayName: "Fake", version: "1")
    var shouldWait = false
    var didUnload = false
    private let suppliedPassages: [RecognizedTranscriptionPassage]?
    private var lastRequest: LocalTranscriptionRequest?

    init(passages: [RecognizedTranscriptionPassage]? = nil) {
        suppliedPassages = passages
    }

    func setShouldWait(_ value: Bool) { shouldWait = value }
    func unloaded() -> Bool { didUnload }
    func receivedRequest() -> LocalTranscriptionRequest? { lastRequest }

    func transcribe(
        _ request: LocalTranscriptionRequest,
        progress: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> LocalTranscriptionResult {
        lastRequest = request
        if shouldWait {
            try await Task.sleep(for: .seconds(10))
        }
        try Task.checkCancellation()
        let first = request.segments[0]
        let second = request.segments.count > 1 ? request.segments[1] : first
        progress(.init(stage: .transcribing, fractionCompleted: 0.5))
        return .init(
            courseID: request.course.id,
            engine: descriptor,
            modelID: request.modelID,
            languageCode: request.languageCode,
            passages: suppliedPassages ?? [
                .init(
                    sourceSegmentID: second.id,
                    startTime: 10,
                    endTime: 12,
                    text: "est vivante. Elle respire.",
                    words: [
                        .init(text: "est", startTime: 10, endTime: 10.2),
                        .init(text: "vivante.", startTime: 10.2, endTime: 10.5),
                        .init(text: "Elle", startTime: 10.5, endTime: 10.8),
                        .init(text: "respire.", startTime: 10.8, endTime: 12)
                    ]
                ),
                .init(
                    sourceSegmentID: first.id,
                    startTime: 0,
                    endTime: 10,
                    text: "La cellule est vivante.",
                    words: [
                        .init(text: "La", startTime: 0, endTime: 0.2),
                        .init(text: "cellule", startTime: 0.2, endTime: 0.5),
                        .init(text: "est", startTime: 9.5, endTime: 9.7),
                        .init(text: "vivante.", startTime: 9.7, endTime: 10)
                    ]
                )
            ],
            metrics: .init(audioDurationSeconds: 20, processingDurationSeconds: 2)
        )
    }

    func unload() async { didUnload = true }
}

private struct FixedModelManager: TranscriptionModelManaging {
    var availability: TranscriptionModelAvailability
    var availableModels: [TranscriptionModelDescriptor] { LocalTranscriptionModelCatalog.alphaModels }

    func status(for modelID: LocalTranscriptionModelID) async -> TranscriptionModelStatus {
        .init(modelID: modelID, availability: availability)
    }

    func download(
        _ modelID: LocalTranscriptionModelID,
        progress: @escaping @Sendable (TranscriptionModelStatus) -> Void
    ) async throws -> TranscriptionModelStatus {
        let status = TranscriptionModelStatus(modelID: modelID, availability: .available)
        progress(status)
        return status
    }
}

private enum FakeTranscriptionFailure: Error { case failed }

private actor FailingLocalEngine: TranscriptionEngine {
    nonisolated let descriptor = TranscriptionEngineDescriptor(
        id: "failing", displayName: "Failing", version: "1")

    func transcribe(
        _ request: LocalTranscriptionRequest,
        progress: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> LocalTranscriptionResult {
        throw FakeTranscriptionFailure.failed
    }

    func unload() async {}
}

struct LocalTranscriptionCoordinatorTests {
    @Test func ordersSegmentsRemovesBoundaryDuplicateAndPersistsDraft() async throws {
        let course = makeCourse()
        let segments = makeSegments(courseID: course.id)
        let engine = FakeLocalEngine()
        let store = InMemoryLocalTranscriptionStore()
        let coordinator = LocalTranscriptionCoordinator(
            engine: engine,
            modelManager: FixedModelManager(availability: .available),
            store: store
        )

        let stored = try await coordinator.transcribe(
            course: course,
            segments: Array(segments.reversed()),
            modelID: .tinyMultilingual,
            progress: { _ in }
        )

        #expect(stored.recordingSegments.map(\.sequence) == [1, 2])
        #expect(stored.result.passages.map(\.text) == ["La cellule est vivante.", "est vivante. Elle respire."])
        #expect(stored.draft.passages.map(\.text) == ["La cellule est vivante.", "Elle respire."])
        #expect(stored.draft.passages.map(\.startTime) == [0, 10.5])
        #expect(stored.transformations?.contains { $0.kind == .boundaryDeduplication } == true)
        #expect(stored.draft.transcriptionEngine?.id == "fake")
        #expect(try await coordinator.latestTranscription()?.draft == stored.draft)
    }

    @Test func preservesUnalignedBoundaryTextWhenWordTimestampsAreMissing() async throws {
        let course = makeCourse()
        let segments = makeSegments(courseID: course.id)
        let passages = [
            RecognizedTranscriptionPassage(
                sourceSegmentID: segments[0].id, startTime: 0, endTime: 10,
                text: "La cellule est vivante."
            ),
            RecognizedTranscriptionPassage(
                sourceSegmentID: segments[1].id, startTime: 10, endTime: 12,
                text: "est vivante. Elle respire."
            )
        ]
        let coordinator = LocalTranscriptionCoordinator(
            engine: FakeLocalEngine(passages: passages),
            modelManager: FixedModelManager(availability: .available),
            store: InMemoryLocalTranscriptionStore()
        )

        let stored = try await coordinator.transcribe(
            course: course, segments: segments, modelID: .smallMultilingual, progress: { _ in }
        )

        #expect(stored.result.passages == passages)
        #expect(stored.draft.passages.map(\.text) == passages.map(\.text))
        #expect(stored.transformations?.contains { $0.kind == .boundaryDeduplication } == false)
    }

    @Test func sendsBoundedCourseContextAndSeparatedGlossariesToEngine() async throws {
        let course = makeCourse()
        let segments = makeSegments(courseID: course.id)
        let engine = FakeLocalEngine(passages: [])
        let coordinator = LocalTranscriptionCoordinator(
            engine: engine,
            modelManager: FixedModelManager(availability: .available),
            store: InMemoryLocalTranscriptionStore()
        )

        _ = try await coordinator.transcribe(
            course: course,
            segments: segments,
            modelID: .smallMultilingual,
            globalGlossary: ["IFSI", "mg"],
            courseGlossary: ["naloxone", "MEOPA"],
            progress: { _ in }
        )

        let context = await engine.receivedRequest()?.context
        #expect(context?.prompt.contains("Cellule") == true)
        #expect(context?.prompt.contains("naloxone") == true)
        #expect(context?.glossary.globalTerms == ["IFSI", "mg"])
        #expect(context?.glossary.courseTerms == ["naloxone", "MEOPA"])
        #expect((context?.prompt.count ?? 0) <= LocalTranscriptionContextBuilder.maximumPromptCharacters)
    }

    @Test func marksLowConfidenceDoseWithoutChangingIt() async throws {
        let course = makeCourse()
        let segment = makeSegments(courseID: course.id)[0]
        let passage = RecognizedTranscriptionPassage(
            sourceSegmentID: segment.id,
            startTime: 42,
            endTime: 45,
            text: "paracétamol 500 mg toutes les 6 heures",
            confidence: 0.40
        )
        let coordinator = LocalTranscriptionCoordinator(
            engine: FakeLocalEngine(passages: [passage]),
            modelManager: FixedModelManager(availability: .available),
            store: InMemoryLocalTranscriptionStore()
        )

        let stored = try await coordinator.transcribe(
            course: course, segments: [segment], modelID: .smallMultilingual, progress: { _ in }
        )

        #expect(stored.draft.passages[0].text == passage.text)
        #expect(stored.draft.passages[0].startTime == 42)
        #expect(stored.draft.passages[0].flags == [.uncertainty, .criticalNumber])
    }

    @Test func presentsNormalizedWhisperTextWithoutChangingRawTextOrTimestamps() async throws {
        let course = makeCourse()
        let segment = makeSegments(courseID: course.id)[0]
        let rawText = "<|startoftranscript|><|fr|><|transcribe|><|0.00|>Le cœur reste irrigué.<|endoftext|>"
        let rawPassage = RecognizedTranscriptionPassage(
            sourceSegmentID: segment.id,
            startTime: 1.25,
            endTime: 4.75,
            text: rawText
        )
        let coordinator = LocalTranscriptionCoordinator(
            engine: FakeLocalEngine(passages: [rawPassage]),
            modelManager: FixedModelManager(availability: .available),
            store: InMemoryLocalTranscriptionStore()
        )

        let stored = try await coordinator.transcribe(
            course: course,
            segments: [segment],
            modelID: .tinyMultilingual,
            progress: { _ in }
        )

        #expect(stored.result.passages[0].text == rawText)
        #expect(stored.result.passages[0].startTime == 1.25)
        #expect(stored.result.passages[0].endTime == 4.75)
        #expect(stored.draft.passages[0].text == "Le cœur reste irrigué.")
        #expect(stored.draft.passages[0].startTime == 1.25)
        #expect(stored.draft.passages[0].endTime == 4.75)
    }

    @Test func missingModelFailsBeforeCallingEngine() async {
        let course = makeCourse()
        let coordinator = LocalTranscriptionCoordinator(
            engine: FakeLocalEngine(),
            modelManager: FixedModelManager(availability: .notDownloaded),
            store: InMemoryLocalTranscriptionStore()
        )
        do {
            _ = try await coordinator.transcribe(
                course: course,
                segments: makeSegments(courseID: course.id),
                modelID: .tinyMultilingual,
                progress: { _ in }
            )
            Issue.record("Une erreur de modèle absent était attendue")
        } catch let error as LocalTranscriptionError {
            #expect(error == .modelUnavailable(.tinyMultilingual))
        } catch {
            Issue.record("Erreur inattendue : \(error)")
        }
    }

    @Test func changingFromSmallToMediumUsesTheRequestedModel() async throws {
        let course = makeCourse()
        let segments = makeSegments(courseID: course.id)
        let engine = FakeLocalEngine(passages: [])
        let coordinator = LocalTranscriptionCoordinator(
            engine: engine,
            modelManager: FixedModelManager(availability: .available),
            store: InMemoryLocalTranscriptionStore()
        )

        let stored = try await coordinator.transcribe(
            course: course,
            segments: segments,
            modelID: .mediumMultilingual,
            progress: { _ in }
        )

        #expect(stored.result.modelID == .mediumMultilingual)
        #expect(await engine.receivedRequest()?.modelID == .mediumMultilingual)
    }

    @Test func cancellationPropagatesAndUnloadsEngine() async throws {
        let course = makeCourse()
        let engine = FakeLocalEngine()
        await engine.setShouldWait(true)
        let coordinator = LocalTranscriptionCoordinator(
            engine: engine,
            modelManager: FixedModelManager(availability: .available),
            store: InMemoryLocalTranscriptionStore()
        )
        let task = Task {
            try await coordinator.transcribe(
                course: course,
                segments: makeSegments(courseID: course.id),
                modelID: .tinyMultilingual,
                progress: { _ in }
            )
        }
        await Task.yield()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("La tâche devait être annulée")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Erreur inattendue : \(error)")
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await engine.unloaded())
    }

    @Test func retranscriptionKeepsOldUntilExplicitReplacementThenPromotesCandidate() async throws {
        let course = makeCourse()
        let segments = makeSegments(courseID: course.id)
        let engine = FakeLocalEngine(passages: [])
        let store = InMemoryLocalTranscriptionStore()
        let coordinator = LocalTranscriptionCoordinator(
            engine: engine,
            modelManager: FixedModelManager(availability: .available),
            store: store)
        let old = try await coordinator.transcribe(
            course: course, segments: segments, modelID: .smallMultilingual,
            progress: { _ in })

        let completion = try await coordinator.retranscribe(
            course: course,
            segments: Array(segments.reversed()),
            modelID: .mediumMultilingual,
            supportDocuments: [.init(
                documentID: UUID(), sourceFileName: "support.pdf",
                textElements: [.init(
                    kind: .paragraph, text: "Naloxone Naloxone antidote opioïde", order: 0)])],
            progress: { _ in })

        guard case let .replacementPending(candidate) = completion else {
            Issue.record("La retranscription devait attendre une confirmation")
            return
        }
        #expect(await store.transcription(for: course.id) == old)
        #expect(candidate.recordingSegments.map(\.sequence) == [1, 2])
        #expect(candidate.result.courseID == course.id)
        #expect(candidate.result.modelID == .mediumMultilingual)
        #expect(await engine.receivedRequest()?.context?.prompt.contains("Naloxone") == true)
        #expect(await engine.receivedRequest()?.course.id == course.id)

        let promoted = try await coordinator.confirmReplacement(for: course.id)
        #expect(promoted == candidate)
        #expect(await store.transcription(for: course.id) == candidate)
    }

    @Test func keepingOldAfterSuccessfulRetranscriptionDiscardsOnlyCandidate() async throws {
        let course = makeCourse()
        let segments = [makeSegments(courseID: course.id)[0]]
        let store = InMemoryLocalTranscriptionStore()
        let coordinator = LocalTranscriptionCoordinator(
            engine: FakeLocalEngine(passages: []),
            modelManager: FixedModelManager(availability: .available),
            store: store)
        let old = try await coordinator.transcribe(
            course: course, segments: segments, modelID: .smallMultilingual,
            progress: { _ in })
        _ = try await coordinator.retranscribe(
            course: course, segments: segments, modelID: .mediumMultilingual,
            progress: { _ in })

        try await coordinator.keepExistingTranscription(for: course.id)

        #expect(await store.transcription(for: course.id) == old)
        #expect(await store.replacementCandidate(for: course.id) == nil)
    }

    @Test func whisperFailureDuringRetranscriptionLeavesOldTranscriptionUntouched() async throws {
        let course = makeCourse()
        let segments = makeSegments(courseID: course.id)
        let store = InMemoryLocalTranscriptionStore()
        let initial = LocalTranscriptionCoordinator(
            engine: FakeLocalEngine(passages: []),
            modelManager: FixedModelManager(availability: .available),
            store: store)
        let old = try await initial.transcribe(
            course: course, segments: segments, modelID: .smallMultilingual,
            progress: { _ in })
        let failing = LocalTranscriptionCoordinator(
            engine: FailingLocalEngine(),
            modelManager: FixedModelManager(availability: .available),
            store: store)

        do {
            _ = try await failing.retranscribe(
                course: course, segments: segments, modelID: .mediumMultilingual,
                progress: { _ in })
            Issue.record("Une erreur moteur était attendue")
        } catch is FakeTranscriptionFailure {
            // Expected.
        }

        #expect(await store.transcription(for: course.id) == old)
        #expect(await store.replacementCandidate(for: course.id) == nil)
    }

    @Test func cancellationDuringRetranscriptionLeavesOldTranscriptionUntouched() async throws {
        let course = makeCourse()
        let segments = makeSegments(courseID: course.id)
        let store = InMemoryLocalTranscriptionStore()
        let initial = LocalTranscriptionCoordinator(
            engine: FakeLocalEngine(passages: []),
            modelManager: FixedModelManager(availability: .available),
            store: store)
        let old = try await initial.transcribe(
            course: course, segments: segments, modelID: .smallMultilingual,
            progress: { _ in })
        let waitingEngine = FakeLocalEngine(passages: [])
        await waitingEngine.setShouldWait(true)
        let coordinator = LocalTranscriptionCoordinator(
            engine: waitingEngine,
            modelManager: FixedModelManager(availability: .available),
            store: store)
        let task = Task {
            try await coordinator.retranscribe(
                course: course, segments: segments, modelID: .mediumMultilingual,
                progress: { _ in })
        }
        await Task.yield()
        task.cancel()

        do { _ = try await task.value } catch is CancellationError {} catch {
            Issue.record("Erreur inattendue : \(error)")
        }
        #expect(await store.transcription(for: course.id) == old)
        #expect(await store.replacementCandidate(for: course.id) == nil)
    }

    private func makeCourse() -> Course {
        Course(
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1)[0],
            title: "Cellule",
            teacher: Teacher(name: "Dr Test", recordingAuthorizationConfirmedAt: Date()),
            expectedDuration: .oneHour
        )
    }

    private func makeSegments(courseID: CourseID) -> [RecordingSegment] {
        let start = Date(timeIntervalSince1970: 0)
        return [
            .init(courseID: courseID, sequence: 1, fileURL: URL(fileURLWithPath: "/audio/1.m4a"), startedAt: start, endedAt: start.addingTimeInterval(10), byteCount: 1),
            .init(courseID: courseID, sequence: 2, fileURL: URL(fileURLWithPath: "/audio/2.m4a"), startedAt: start, endedAt: start.addingTimeInterval(10), byteCount: 1)
        ]
    }
}
