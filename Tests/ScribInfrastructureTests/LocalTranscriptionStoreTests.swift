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
        let transformation = TranscriptTransformation(
            passageID: passage.id,
            kind: .whisperControlTokenRemoval,
            originalText: "<|fr|>Texte brut",
            resultingText: "Texte brut",
            originalStartTime: 0,
            resultingStartTime: 0
        )
        try await store.save(.init(
            course: course,
            recordingSegments: [segment],
            result: result,
            draft: draft,
            transformations: [transformation]
        ))
        draft.passages[0].text = "Texte corrigé"
        try await store.updateDraft(draft)

        let reopened = try LocalTranscriptionStore(rootDirectory: root)
        let restored = try await reopened.latest()
        #expect(restored?.result.plainText == "Texte brut")
        #expect(restored?.draft.passages[0].text == "Texte corrigé")
        #expect(restored?.recordingSegments[0].sequence == 1)
        #expect(restored?.transformations == [transformation])
    }

    @Test func replacementCandidateNeverOverwritesOldUntilPromoted() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let course = Course(
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1)[0],
            title: "Pharmacologie des antalgiques",
            teacher: Teacher(name: "Dr Test", recordingAuthorizationConfirmedAt: Date()),
            expectedDuration: .oneHour
        )
        let old = makeStored(course: course, text: "Ancienne", model: .smallMultilingual)
        let candidate = makeStored(course: course, text: "Nouvelle", model: .mediumMultilingual)
        let store = try LocalTranscriptionStore(rootDirectory: root)
        try await store.save(old)

        try await store.saveReplacementCandidate(candidate)
        #expect(try await store.transcription(for: course.id)?.result.plainText == "Ancienne")
        #expect(try await store.replacementCandidate(for: course.id)?.result.plainText == "Nouvelle")

        let promoted = try await store.promoteReplacementCandidate(for: course.id)
        #expect(promoted.result.plainText == "Nouvelle")
        #expect(promoted.result.modelID == .mediumMultilingual)
        #expect(try await store.transcription(for: course.id)?.result.plainText == "Nouvelle")
        #expect(try await store.replacementCandidate(for: course.id) == nil)
    }

    @Test func discardingCandidateKeepsOldTranscription() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let course = Course(
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1)[0],
            title: "Conservation",
            teacher: Teacher(name: "Dr Test", recordingAuthorizationConfirmedAt: Date()),
            expectedDuration: .oneHour
        )
        let old = makeStored(course: course, text: "Ancienne", model: .smallMultilingual)
        let store = try LocalTranscriptionStore(rootDirectory: root)
        try await store.save(old)
        try await store.saveReplacementCandidate(
            makeStored(course: course, text: "Nouvelle", model: .mediumMultilingual))

        try await store.discardReplacementCandidate(for: course.id)

        #expect(try await store.transcription(for: course.id)?.result.plainText == "Ancienne")
        #expect(try await store.replacementCandidate(for: course.id) == nil)
    }

    private func makeStored(
        course: Course, text: String, model: LocalTranscriptionModelID
    ) -> StoredLocalTranscription {
        let start = Date(timeIntervalSince1970: 0)
        let segment = RecordingSegment(
            courseID: course.id, sequence: 1,
            fileURL: URL(fileURLWithPath: "/audio/segment.m4a"),
            startedAt: start, endedAt: start.addingTimeInterval(5), byteCount: 1)
        let passage = RecognizedTranscriptionPassage(
            sourceSegmentID: segment.id, startTime: 0, endTime: 5, text: text)
        return StoredLocalTranscription(
            course: course,
            recordingSegments: [segment],
            result: .init(
                courseID: course.id,
                engine: .init(id: "test", displayName: "Test", version: "1"),
                modelID: model,
                languageCode: "fr",
                passages: [passage],
                metrics: .init(audioDurationSeconds: 5, processingDurationSeconds: 1)),
            draft: .init(
                courseID: course.id, courseTitle: course.title,
                teachingUnit: course.teachingUnit.displayName,
                passages: [.init(
                    id: passage.id, speaker: "Voix", startTime: 0, endTime: 5, text: text)])
        )
    }
}
