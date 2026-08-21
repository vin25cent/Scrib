import Foundation
import Testing
@testable import ScribApplication
@testable import ScribDomain

private func trackedCourse(title: String = "Biologie") -> Course {
    Course(
        semester: .semester1,
        teachingUnit: TeachingUnitCatalog.units(for: .semester1)[2],
        title: title,
        teacher: Teacher(name: "Dr Martin", recordingAuthorizationConfirmedAt: Date()),
        expectedDuration: .twoHours
    )
}

@Test func trackerFollowsOnlyTheActivityExplicitlyStarted() async throws {
    let repository = InMemoryProcessingJobRepository()
    let tracker = ProcessingActivityTracker(repository: repository)
    let course = trackedCourse()

    _ = try await tracker.start(course: course, activity: .localTranscription)
    try await tracker.markRunning(courseID: course.id, activity: .localTranscription, progress: 0.4)
    try await tracker.complete(courseID: course.id, activity: .localTranscription)

    let job = try #require(await repository.jobs().first)
    #expect(job.activity == .localTranscription)
    #expect(job.status == .completed)
    #expect(job.progress == 1)
    #expect(job.reportedProgress == nil)
}

@Test func trackerRecordsAnInterruptedLiveActivityAsSuspended() async throws {
    let repository = InMemoryProcessingJobRepository()
    let tracker = ProcessingActivityTracker(repository: repository)
    let course = trackedCourse()

    _ = try await tracker.start(course: course, activity: .recording)
    try await tracker.markRunning(courseID: course.id, activity: .recording)
    try await tracker.recoverInterruptedActivities()

    let job = try #require(await repository.jobs().first)
    #expect(job.status == .suspended)
    #expect(job.suspensionReason == "Activité interrompue à la fermeture de Scrib.")
}

@Test func aLateProgressUpdateCannotReviveACompletedActivity() async throws {
    let repository = InMemoryProcessingJobRepository()
    let tracker = ProcessingActivityTracker(repository: repository)
    let course = trackedCourse()
    let startedAt = Date(timeIntervalSince1970: 10)
    let completedAt = Date(timeIntervalSince1970: 20)

    _ = try await tracker.start(course: course, activity: .localTranscription, at: startedAt)
    try await tracker.markRunning(courseID: course.id, activity: .localTranscription, at: startedAt)
    try await tracker.complete(courseID: course.id, activity: .localTranscription, at: completedAt)
    try await tracker.updateProgress(
        courseID: course.id,
        activity: .localTranscription,
        progress: 0.7,
        at: Date(timeIntervalSince1970: 15)
    )

    let job = try #require(await repository.jobs().first)
    #expect(job.status == .completed)
    #expect(job.progress == 1)
}

@Test func startingANewConcreteActivityReusesTheCourseTrackingRecord() async throws {
    let repository = InMemoryProcessingJobRepository()
    let tracker = ProcessingActivityTracker(repository: repository)
    let course = trackedCourse()

    let recording = try await tracker.start(course: course, activity: .recording)
    let transcription = try await tracker.start(course: course, activity: .localTranscription)

    #expect(recording.id == transcription.id)
    #expect(await repository.jobs().count == 1)
    #expect((await repository.jobs().first)?.activity == .localTranscription)
}
