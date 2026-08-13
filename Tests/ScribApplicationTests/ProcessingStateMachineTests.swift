import Testing
@testable import ScribApplication
@testable import ScribDomain

@Test func courseCanReachTheQueue() throws {
    let machine = ProcessingStateMachine()
    var job = ProcessingJob(courseID: CourseID())

    job = try machine.transition(job, to: .recording)
    job = try machine.transition(job, to: .captured)
    job = try machine.transition(job, to: .queued)

    #expect(job.status == .queued)
}

@Test func completedCourseCannotRestartSilently() {
    let machine = ProcessingStateMachine()
    let job = ProcessingJob(courseID: CourseID(), status: .completed, progress: 1)

    #expect(throws: ProcessingTransitionError.self) {
        try machine.transition(job, to: .processing)
    }
}
