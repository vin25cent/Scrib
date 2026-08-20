import Foundation
import Testing
@testable import ScribDomain

struct LocalTranscriptionExportTests {
    @Test func plainTextExportsSegmentsTimestampsFrenchTextAndMetadata() {
        let transcription = makeTranscription(
            passages: [
                .init(sourceSegmentID: UUID(), startTime: 0, endTime: 4, text: "Bonjour, l’éthique médicale."),
                .init(sourceSegmentID: UUID(), startTime: 12.9, endTime: 15, text: "Deuxième segment : cœur et réanimation.")
            ],
            audioDurationSeconds: 65
        )

        #expect(
            LocalTranscriptionExport.plainText(from: transcription) == """
            Cours : Cœur et éthique
            UE : UE 2.1 — Biologie fondamentale
            Date : 2026-08-20
            Modèle : tiny
            Durée : 00:01:05

            [00:00:00] Bonjour, l’éthique médicale.
            [00:00:12] Deuxième segment : cœur et réanimation.
            """
        )
    }

    @Test func plainTextDoesNotTransformPassageTextAndOmitsUnavailableMetadata() {
        let exactText = "Texte\nexact — sans correction !"
        let transcription = makeTranscription(
            teachingUnit: .init(semester: .semester1, code: "", title: ""),
            passages: [.init(sourceSegmentID: UUID(), startTime: 3_661.5, endTime: 3_662, text: exactText)],
            audioDurationSeconds: 0
        )

        let exported = LocalTranscriptionExport.plainText(from: transcription)

        #expect(!exported.contains("UE :"))
        #expect(!exported.contains("Durée :"))
        #expect(exported.hasSuffix("[01:01:01] \(exactText)"))
    }

    @Test func jsonExportIsValidAndRetainsRawTranscriptionData() throws {
        let word = RecognizedTranscriptionWord(
            text: "Bonjour",
            startTime: 0,
            endTime: 0.5,
            probability: 0.92
        )
        let passage = RecognizedTranscriptionPassage(
            sourceSegmentID: UUID(),
            startTime: 0,
            endTime: 1,
            text: "Bonjour",
            confidence: 0.81,
            words: [word]
        )
        let transcription = makeTranscription(passages: [passage], audioDurationSeconds: 42)

        let data = try LocalTranscriptionExport.jsonData(from: transcription)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StoredLocalTranscription.self, from: data)

        #expect(decoded.course.title == transcription.course.title)
        #expect(decoded.result.modelID == .tinyMultilingual)
        #expect(decoded.result.passages[0].text == "Bonjour")
        #expect(decoded.result.passages[0].words[0].probability == 0.92)
        #expect(decoded.result.metrics.audioDurationSeconds == 42)
    }

    private func makeTranscription(
        teachingUnit: TeachingUnit = .init(semester: .semester1, code: "2.1", title: "Biologie fondamentale"),
        passages: [RecognizedTranscriptionPassage],
        audioDurationSeconds: Double
    ) -> StoredLocalTranscription {
        let course = Course(
            semester: .semester1,
            teachingUnit: teachingUnit,
            title: "Cœur et éthique",
            teacher: .init(name: "Mme Martin"),
            expectedDuration: .oneHour,
            courseDate: Date(timeIntervalSince1970: 1_787_184_000)
        )
        let result = LocalTranscriptionResult(
            courseID: course.id,
            engine: .init(id: "whisperkit", displayName: "WhisperKit", version: "1.0.0"),
            modelID: .tinyMultilingual,
            languageCode: "fr",
            passages: passages,
            metrics: .init(audioDurationSeconds: audioDurationSeconds, processingDurationSeconds: 3),
            completedAt: Date(timeIntervalSince1970: 1_787_011_260)
        )
        let draft = TranscriptDraft(
            courseID: course.id,
            courseTitle: course.title,
            teachingUnit: course.teachingUnit.displayName
        )
        return .init(course: course, recordingSegments: [], result: result, draft: draft)
    }
}
