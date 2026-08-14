import Foundation
import Testing
import ScribDomain
@testable import ScribApplication

private actor FakeLocalEngine: TranscriptionEngine {
    nonisolated let descriptor = TranscriptionEngineDescriptor(id: "fake", displayName: "Fake", version: "1")
    var shouldWait = false
    var didUnload = false

    func setShouldWait(_ value: Bool) { shouldWait = value }
    func unloaded() -> Bool { didUnload }

    func transcribe(
        _ request: LocalTranscriptionRequest,
        progress: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> LocalTranscriptionResult {
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
            passages: [
                .init(sourceSegmentID: second.id, startTime: 10, endTime: 12, text: "est vivante. Elle respire."),
                .init(sourceSegmentID: first.id, startTime: 0, endTime: 10, text: "La cellule est vivante.")
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
        #expect(stored.result.passages.map(\.text) == ["La cellule est vivante.", "Elle respire."])
        #expect(stored.draft.passages.map(\.startTime) == [0, 10])
        #expect(stored.draft.transcriptionEngine?.id == "fake")
        #expect(try await coordinator.latestTranscription()?.draft == stored.draft)
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
