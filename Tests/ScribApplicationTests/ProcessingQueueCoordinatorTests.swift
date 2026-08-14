import Foundation
import Testing
@testable import ScribApplication
@testable import ScribDomain

private actor SuccessfulStepExecutor: PipelineStepExecuting {
    private(set) var calls: [(ProcessingStage, CourseID)] = []

    func execute(
        stage: ProcessingStage,
        courseID: CourseID
    ) async throws -> ProcessingStepResult {
        calls.append((stage, courseID))
        return ProcessingStepResult(outputFingerprint: "\(stage.rawValue)-ok")
    }

    func callCount() -> Int { calls.count }
}

private actor SlowStepExecutor: PipelineStepExecuting {
    private(set) var started = false

    func execute(
        stage: ProcessingStage,
        courseID: CourseID
    ) async throws -> ProcessingStepResult {
        started = true
        try await Task.sleep(for: .seconds(30))
        return ProcessingStepResult()
    }

    func hasStarted() -> Bool { started }
}

private func queueCourse(title: String) -> Course {
    let teacher = Teacher(name: "Dr Martin", recordingAuthorizationConfirmedAt: Date())
    return Course(
        semester: .semester1,
        teachingUnit: TeachingUnitCatalog.units(for: .semester1)[2],
        title: title,
        teacher: teacher,
        expectedDuration: .twoHours
    )
}

private var runnableConditions: SystemConditionSnapshot {
    SystemConditionSnapshot(
        isOnExternalPower: true,
        isNetworkAvailable: true
    )
}

@Test func duplicateCourseIsOnlyQueuedOnce() async throws {
    let repository = InMemoryProcessingJobRepository()
    let coordinator = ProcessingQueueCoordinator(
        repository: repository,
        conditions: FixedSystemConditionMonitor(snapshot: runnableConditions),
        executor: SuccessfulStepExecutor()
    )
    let course = queueCourse(title: "Biologie")

    let first = try await coordinator.enqueue(course: course)
    let second = try await coordinator.enqueue(course: course)

    #expect(first.id == second.id)
    #expect(await repository.jobs().count == 1)
}

@Test func queueCompletesEveryStageInFIFOOrder() async throws {
    let repository = InMemoryProcessingJobRepository()
    let executor = SuccessfulStepExecutor()
    let coordinator = ProcessingQueueCoordinator(
        repository: repository,
        conditions: FixedSystemConditionMonitor(snapshot: runnableConditions),
        executor: executor
    )
    let firstCourse = queueCourse(title: "Premier cours")
    let secondCourse = queueCourse(title: "Deuxième cours")
    _ = try await coordinator.enqueue(course: firstCourse)
    _ = try await coordinator.enqueue(course: secondCourse)

    _ = try await coordinator.processUntilBlockedOrEmpty()
    let jobs = await repository.jobs()
    let calls = await executor.calls

    #expect(jobs.allSatisfy { $0.status == .completed })
    #expect(jobs.allSatisfy { $0.checkpoints.count == ProcessingStage.allCases.count })
    #expect(calls.count == ProcessingStage.allCases.count * 2)
    #expect(calls.prefix(ProcessingStage.allCases.count).allSatisfy { $0.1 == firstCourse.id })
}

@Test func batteryAndNetworkBlockProcessing() async throws {
    let repository = InMemoryProcessingJobRepository()
    let executor = SuccessfulStepExecutor()
    let conditions = SystemConditionSnapshot(
        isOnExternalPower: false,
        isNetworkAvailable: false
    )
    let coordinator = ProcessingQueueCoordinator(
        repository: repository,
        conditions: FixedSystemConditionMonitor(snapshot: conditions),
        executor: executor
    )
    _ = try await coordinator.enqueue(course: queueCourse(title: "Cours bloqué"))

    let result = try await coordinator.processNext()

    #expect(result == .blocked([.batteryPower, .networkUnavailable]))
    #expect(await executor.callCount() == 0)
}

@Test func newRecordingPreemptsActiveProcessing() async throws {
    let repository = InMemoryProcessingJobRepository()
    let executor = SlowStepExecutor()
    let coordinator = ProcessingQueueCoordinator(
        repository: repository,
        conditions: FixedSystemConditionMonitor(snapshot: runnableConditions),
        executor: executor
    )
    let job = try await coordinator.enqueue(course: queueCourse(title: "Cours long"))

    let processing = Task { try await coordinator.processNext() }
    while !(await executor.hasStarted()) {
        await Task.yield()
    }
    await coordinator.recordingDidStart()
    let result = try await processing.value
    let persisted = await repository.job(id: job.id)

    #expect(result == .suspended(job.id))
    #expect(persisted?.status == .suspended)
    #expect(persisted?.suspensionReasons == [.recordingActive])
}

@Test func interruptedProcessingIsRecoveredAsSuspended() async throws {
    var interrupted = ProcessingJob(
        courseID: CourseID(),
        courseTitle: "Cours interrompu",
        status: .processing,
        stage: .transcribing
    )
    interrupted.progress = 0.4
    let repository = InMemoryProcessingJobRepository(jobs: [interrupted])
    let coordinator = ProcessingQueueCoordinator(
        repository: repository,
        conditions: FixedSystemConditionMonitor(snapshot: runnableConditions),
        executor: SuccessfulStepExecutor()
    )

    try await coordinator.recoverInterruptedJobs()
    let recovered = await repository.job(id: interrupted.id)

    #expect(recovered?.status == .suspended)
    #expect(recovered?.stage == .transcribing)
    #expect(recovered?.progress == 0.4)
}

@Test func thirtyHourQueueCompletesWithoutDuplicates() async throws {
    let repository = InMemoryProcessingJobRepository()
    let executor = SuccessfulStepExecutor()
    let coordinator = ProcessingQueueCoordinator(
        repository: repository,
        conditions: FixedSystemConditionMonitor(snapshot: runnableConditions),
        executor: executor
    )

    for index in 1...30 {
        let teacher = Teacher(
            name: "Enseignant \(index)",
            recordingAuthorizationConfirmedAt: Date()
        )
        let course = Course(
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1)[0],
            title: "Cours \(index)",
            teacher: teacher,
            expectedDuration: .oneHour
        )
        _ = try await coordinator.enqueue(course: course)
        _ = try await coordinator.enqueue(course: course)
    }

    _ = try await coordinator.processUntilBlockedOrEmpty(maximumSteps: 250)
    let jobs = await repository.jobs()

    #expect(jobs.count == 30)
    #expect(jobs.allSatisfy { $0.status == .completed })
    #expect(Set(jobs.map(\.courseID)).count == 30)
    #expect(await executor.callCount() == 30 * ProcessingStage.allCases.count)
}
