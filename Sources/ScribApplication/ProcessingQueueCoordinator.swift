import Foundation
import ScribDomain

public enum ProcessingQueueResult: Equatable, Sendable {
    case empty
    case busy
    case blocked([ProcessingBlocker])
    case stageCompleted(jobID: ProcessingJobID, stage: ProcessingStage)
    case jobCompleted(ProcessingJobID)
    case suspended(ProcessingJobID)
    case needsAttention(ProcessingJobID)
}

public actor ProcessingQueueCoordinator {
    private let repository: any ProcessingJobRepository
    private let conditions: any SystemConditionsMonitoring
    private let executor: any PipelineStepExecuting
    private let notifications: any ProcessingNotificationSending
    private let maximumAutomaticAttempts: Int
    private var recordingActive = false
    private var activeJobID: ProcessingJobID?
    private var activeStepTask: Task<ProcessingStepResult, Error>?

    public init(
        repository: any ProcessingJobRepository,
        conditions: any SystemConditionsMonitoring,
        executor: any PipelineStepExecuting,
        notifications: any ProcessingNotificationSending = NullProcessingNotificationSender(),
        maximumAutomaticAttempts: Int = 3
    ) {
        self.repository = repository
        self.conditions = conditions
        self.executor = executor
        self.notifications = notifications
        self.maximumAutomaticAttempts = max(maximumAutomaticAttempts, 1)
    }

    @discardableResult
    public func enqueue(course: Course) async throws -> ProcessingJob {
        if let existing = try await repository.jobs().first(where: {
            $0.courseID == course.id && $0.status != .completed
        }) {
            return existing
        }

        let job = ProcessingJob(course: course)
        try await repository.save(job)
        return job
    }

    public func jobs() async throws -> [ProcessingJob] {
        try await repository.jobs()
    }

    public func currentConditions() async -> SystemConditionSnapshot {
        var snapshot = await conditions.currentSnapshot()
        snapshot.isRecordingActive = recordingActive
        return snapshot
    }

    public func recoverInterruptedJobs() async throws {
        for var job in try await repository.jobs() where job.status == .processing {
            job.status = .suspended
            job.lastError = "Traitement interrompu lors de la précédente exécution."
            job.updatedAt = Date()
            try await repository.save(job)
        }
    }

    public func recordingDidStart() async {
        recordingActive = true
        activeStepTask?.cancel()

        guard let activeJobID,
              var job = try? await repository.job(id: activeJobID) else {
            return
        }
        job.status = .suspended
        job.suspensionReasons = [.recordingActive]
        job.updatedAt = Date()
        try? await repository.save(job)
    }

    public func recordingDidStop() {
        recordingActive = false
    }

    public func retry(jobID: ProcessingJobID) async throws {
        guard var job = try await repository.job(id: jobID) else { return }
        job.status = .queued
        job.attemptCount = 0
        job.nextAttemptAt = nil
        job.lastError = nil
        job.suspensionReasons = []
        job.updatedAt = Date()
        try await repository.save(job)
    }

    public func processNext(now: Date = Date()) async throws -> ProcessingQueueResult {
        guard activeStepTask == nil else { return .busy }

        let conditionSnapshot = await currentConditions()
        guard conditionSnapshot.canRunHeavyProcessing else {
            return .blocked(conditionSnapshot.blockers)
        }

        guard var job = try await repository.jobs().first(where: { candidate in
            guard candidate.status == .queued || candidate.status == .suspended else {
                return false
            }
            return candidate.nextAttemptAt.map { $0 <= now } ?? true
        }) else {
            return .empty
        }

        if job.status == .suspended {
            job.status = .queued
        }
        let stage = job.nextStage
        guard let stage else {
            job.status = .completed
            job.progress = 1
            job.updatedAt = now
            try await repository.save(job)
            await notifications.processingDidComplete(job: job)
            return .jobCompleted(job.id)
        }

        job.status = .processing
        job.stage = stage
        job.suspensionReasons = []
        job.updatedAt = now
        try await repository.save(job)
        activeJobID = job.id

        let executingCourseID = job.courseID
        let task = Task {
            try await executor.execute(stage: stage, courseID: executingCourseID)
        }
        activeStepTask = task

        do {
            let result = try await task.value
            activeStepTask = nil
            activeJobID = nil

            guard !recordingActive else {
                job.status = .suspended
                job.suspensionReasons = [.recordingActive]
                job.updatedAt = Date()
                try await repository.save(job)
                return .suspended(job.id)
            }

            job.completeStage(
                stage,
                outputFingerprint: result.outputFingerprint,
                at: Date()
            )
            job.attemptCount = 0
            job.nextAttemptAt = nil
            job.lastError = nil
            job.suspensionReasons = []

            if job.nextStage == nil {
                job.status = .completed
                job.progress = 1
                try await repository.save(job)
                await notifications.processingDidComplete(job: job)
                return .jobCompleted(job.id)
            }

            job.status = .queued
            try await repository.save(job)
            return .stageCompleted(jobID: job.id, stage: stage)
        } catch is CancellationError {
            activeStepTask = nil
            activeJobID = nil
            job.status = .suspended
            job.suspensionReasons = recordingActive ? [.recordingActive] : []
            job.updatedAt = Date()
            try await repository.save(job)
            return .suspended(job.id)
        } catch {
            activeStepTask = nil
            activeJobID = nil
            job.attemptCount += 1
            job.lastError = error.localizedDescription
            job.updatedAt = Date()

            if job.attemptCount >= maximumAutomaticAttempts {
                job.status = .needsAttention
                job.nextAttemptAt = nil
                try await repository.save(job)
                await notifications.processingNeedsAttention(job: job)
                return .needsAttention(job.id)
            }

            job.status = .suspended
            job.nextAttemptAt = now.addingTimeInterval(backoffDelay(for: job.attemptCount))
            try await repository.save(job)
            return .suspended(job.id)
        }
    }

    public func processUntilBlockedOrEmpty(
        maximumSteps: Int = 100
    ) async throws -> ProcessingQueueResult {
        var latest: ProcessingQueueResult = .empty
        for _ in 0..<max(maximumSteps, 1) {
            latest = try await processNext()
            switch latest {
            case .stageCompleted, .jobCompleted:
                continue
            case .empty, .busy, .blocked, .suspended, .needsAttention:
                return latest
            }
        }
        return latest
    }

    private func backoffDelay(for attempt: Int) -> TimeInterval {
        min(pow(2, Double(max(attempt - 1, 0))) * 60, 30 * 60)
    }
}
