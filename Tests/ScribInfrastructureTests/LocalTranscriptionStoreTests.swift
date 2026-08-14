import Foundation
import Testing
import ScribDomain
@testable import ScribInfrastructure

struct LocalTranscriptionStoreTests {
    @Test func completedTranscriptAndEditsSurviveStoreReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let course = Course(
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1)[0],
            title: "Persistance",
            teacher: Teacher(name: "Test", recordingAuthorizationConfirmedAt: Date()),
            expectedDuration: .oneHour
        )
        let start = Date(timeIntervalSince1970: 0)
        let segment = RecordingSegment(
            courseID: course.id,
            sequence: 1,
            fileURL: root.appendingPathComponent("audio.m4a"),
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            byteCount: 12
        )
        let passage = RecognizedTranscriptionPassage(
            sourceSegmentID: segment.id,
            startTime: 0,
            endTime: 2,
            text: "Texte brut"
        )
        let result = LocalTranscriptionResult(
            courseID: course.id,
            engine: .init(id: "whisperkit", displayName: "WhisperKit", version: "1.0.0"),
            modelID: .tinyMultilingual,
            languageCode: "fr",
            passages: [passage],
            metrics: .init(audioDurationSeconds: 60, processingDurationSeconds: 4)
        )
        var draft = TranscriptDraft(
            courseID: course.id,
            courseTitle: course.title,
            teachingUnit: course.teachingUnit.displayName,
            passages: [.init(id: passage.id, speaker: "Voix", startTime: 0, endTime: 2, text: passage.text)]
        )
        let store = try LocalTranscriptionStore(rootDirectory: root)
        try await store.save(.init(course: course, recordingSegments: [segment], result: result, draft: draft))
        draft.passages[0].text = "Texte corrigé"
        try await store.updateDraft(draft)

        let reopened = try LocalTranscriptionStore(rootDirectory: root)
        let restored = try await reopened.latest()
        #expect(restored?.result.plainText == "Texte brut")
        #expect(restored?.draft.passages[0].text == "Texte corrigé")
        #expect(restored?.recordingSegments[0].sequence == 1)
    }
}
