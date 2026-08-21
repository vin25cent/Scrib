import Foundation
import ScribDomain

/// Stores status updates emitted by existing workflows. It is not an executor,
/// scheduler, or state machine for an end-to-end pipeline.
public actor ProcessingActivityTracker {
    private let repository: any ProcessingJobRepository

    public init(repository: any ProcessingJobRepository) {
        self.repository = repository
    }

    @discardableResult
    public func start(
        course: Course,
        activity: ProcessingActivity,
        at date: Date = Date()
    ) async throws -> ProcessingJob {
        var job = try await repository.jobs().first(where: { $0.courseID == course.id })
            ?? ProcessingJob(course: course, activity: activity, createdAt: date)
        job.courseTitle = course.title
        job.teachingUnit = course.teachingUnit.displayName
        job.courseDate = course.courseDate
        job.activity = activity
        job.status = .pending
        job.reportedProgress = nil
        job.suspensionReason = nil
        job.lastError = nil
        job.updatedAt = date
        try await repository.save(job)
        return job
    }

    public func markRunning(
        courseID: CourseID,
        activity: ProcessingActivity,
        progress: Double? = nil,
        at date: Date = Date()
    ) async throws {
        try await update(courseID: courseID, activity: activity, at: date) { job in
            job.status = .processing
            job.reportedProgress = progress.map { min(max($0, 0), 1) }
            job.suspensionReason = nil
            job.lastError = nil
        }
    }

    public func updateProgress(
        courseID: CourseID,
        activity: ProcessingActivity,
        progress: Double,
        at date: Date = Date()
    ) async throws {
        try await update(courseID: courseID, activity: activity, at: date) { job in
            job.status = .processing
            job.reportedProgress = min(max(progress, 0), 1)
        }
    }

    public func complete(
        courseID: CourseID,
        activity: ProcessingActivity,
        at date: Date = Date()
    ) async throws {
        try await update(courseID: courseID, activity: activity, at: date) { job in
            job.status = .completed
            job.reportedProgress = nil
            job.suspensionReason = nil
            job.lastError = nil
        }
    }

    public func suspend(
        courseID: CourseID,
        activity: ProcessingActivity,
        reason: String,
        at date: Date = Date()
    ) async throws {
        try await update(courseID: courseID, activity: activity, at: date) { job in
            job.status = .suspended
            job.suspensionReason = reason
        }
    }

    public func fail(
        courseID: CourseID,
        activity: ProcessingActivity,
        error: String,
        at date: Date = Date()
    ) async throws {
        try await update(courseID: courseID, activity: activity, at: date) { job in
            job.status = .failed
            job.lastError = error
            job.suspensionReason = nil
        }
    }

    /// Activity cannot survive a process stop. Mark stale live records honestly
    /// instead of claiming the operation will be resumed automatically.
    public func recoverInterruptedActivities(at date: Date = Date()) async throws {
        for var job in try await repository.jobs() where job.status == .pending || job.status == .processing {
            job.status = .suspended
            job.suspensionReason = "Activité interrompue à la fermeture de Scrib."
            job.updatedAt = date
            try await repository.save(job)
        }
    }

    public func jobs() async throws -> [ProcessingJob] {
        try await repository.jobs()
    }

    private func update(
        courseID: CourseID,
        activity: ProcessingActivity,
        at date: Date,
        change: (inout ProcessingJob) -> Void
    ) async throws {
        guard var job = try await repository.jobs().first(where: {
            $0.courseID == courseID && $0.activity == activity
        }), job.updatedAt <= date else { return }
        change(&job)
        job.updatedAt = date
        try await repository.save(job)
    }
}
