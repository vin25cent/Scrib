import Foundation
import Testing
import ScribDomain
@testable import ScribApplication

struct ActiveCourseWorkspaceTests {
    @Test func selectingTrackingCoursePropagatesItsCourseID() {
        let course = makeCourse(title: "Cours A")
        let job = ProcessingJob(course: course, activity: .recording)
        var selection = ActiveCourseSelection()

        selection.select(job)

        #expect(selection.courseID == course.id)
        #expect(selection.trackingJobID == job.id)
    }

    @Test func changingFromAToBReplacesTheSingleActiveCourseSelection() {
        let courseA = makeCourse(title: "Cours A")
        let courseB = makeCourse(title: "Cours B")
        let jobA = ProcessingJob(course: courseA, activity: .recording)
        let jobB = ProcessingJob(course: courseB, activity: .localTranscription)
        var selection = ActiveCourseSelection()

        selection.select(jobA)
        selection.select(jobB)

        #expect(selection.courseID == courseB.id)
        #expect(selection.trackingJobID == jobB.id)
    }

    @Test func workspaceRestoresMatchingMetadataAudioAndTranscription() throws {
        let course = makeCourse(title: "Pharmacologie")
        let segments = makeSegments(courseID: course.id)
        let session = RecoveredRecordingSession(
            manifest: RecordingSessionManifest(course: course, finalizationState: .stopped),
            recordingSegments: Array(segments.reversed()))
        let transcription = makeTranscription(course: course, segments: segments)

        let workspace = try ActiveCourseWorkspace(
            courseID: course.id,
            recordingSession: session,
            transcription: transcription)

        #expect(workspace.course == course)
        #expect(workspace.recordingSegments.map(\.sequence) == [1, 2])
        #expect(workspace.transcription?.course.id == course.id)
        #expect(workspace.transcription?.result.plainText == "Texte du cours")
        #expect(workspace.hasUsableAudio)
    }

    @Test func courseWithoutAudioRemainsSelectableButCannotRetranscribe() throws {
        let course = makeCourse(title: "Sans audio")
        let session = RecoveredRecordingSession(
            manifest: RecordingSessionManifest(course: course, finalizationState: .stopped),
            recordingSegments: [])

        let workspace = try ActiveCourseWorkspace(
            courseID: course.id, recordingSession: session, transcription: nil)

        #expect(workspace.courseID == course.id)
        #expect(workspace.recordingSegments.isEmpty)
        #expect(!workspace.hasUsableAudio)
    }

    @Test func workspaceRejectsAnyMixBetweenTwoCourseIDs() throws {
        let courseA = makeCourse(title: "Cours A")
        let courseB = makeCourse(title: "Cours B")
        let sessionA = RecoveredRecordingSession(
            manifest: RecordingSessionManifest(course: courseA, finalizationState: .stopped),
            recordingSegments: makeSegments(courseID: courseA.id))
        let transcriptionB = makeTranscription(
            course: courseB, segments: makeSegments(courseID: courseB.id))

        #expect(throws: ActiveCourseWorkspaceError.inconsistentTranscriptionCourse) {
            _ = try ActiveCourseWorkspace(
                courseID: courseA.id,
                recordingSession: sessionA,
                transcription: transcriptionB)
        }
    }

    private func makeCourse(title: String) -> Course {
        Course(
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1)[0],
            title: title,
            teacher: Teacher(name: "Dr Test", recordingAuthorizationConfirmedAt: Date()),
            expectedDuration: .oneHour)
    }

    private func makeSegments(courseID: CourseID) -> [RecordingSegment] {
        let start = Date(timeIntervalSince1970: 100)
        return [
            RecordingSegment(
                courseID: courseID, sequence: 1,
                fileURL: URL(fileURLWithPath: "/audio/segment-1.m4a"),
                startedAt: start, endedAt: start.addingTimeInterval(10), byteCount: 10),
            RecordingSegment(
                courseID: courseID, sequence: 2,
                fileURL: URL(fileURLWithPath: "/audio/segment-2.m4a"),
                startedAt: start.addingTimeInterval(10),
                endedAt: start.addingTimeInterval(20), byteCount: 10),
        ]
    }

    private func makeTranscription(
        course: Course, segments: [RecordingSegment]
    ) -> StoredLocalTranscription {
        let passage = RecognizedTranscriptionPassage(
            sourceSegmentID: segments[0].id,
            startTime: 0, endTime: 10, text: "Texte du cours")
        return StoredLocalTranscription(
            course: course,
            recordingSegments: segments,
            result: LocalTranscriptionResult(
                courseID: course.id,
                engine: .init(id: "test", displayName: "Test", version: "1"),
                modelID: .smallMultilingual,
                languageCode: "fr",
                passages: [passage],
                metrics: .init(audioDurationSeconds: 20, processingDurationSeconds: 2)),
            draft: TranscriptDraft(
                courseID: course.id,
                courseTitle: course.title,
                teachingUnit: course.teachingUnit.displayName,
                passages: [.init(
                    id: passage.id, speaker: "Voix", startTime: 0, endTime: 10,
                    text: passage.text)]))
    }
}
