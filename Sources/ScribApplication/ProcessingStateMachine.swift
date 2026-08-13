import ScribDomain

public enum ProcessingTransitionError: Error, Equatable {
    case invalidTransition(from: CourseStatus, to: CourseStatus)
}

public struct ProcessingStateMachine: Sendable {
    public init() {}

    public func transition(_ job: ProcessingJob, to newStatus: CourseStatus) throws -> ProcessingJob {
        guard Self.allowedTransitions[job.status, default: []].contains(newStatus) else {
            throw ProcessingTransitionError.invalidTransition(from: job.status, to: newStatus)
        }

        var updated = job
        updated.status = newStatus

        if newStatus == .processing, updated.stage == nil {
            updated.stage = .preparing
        }
        if newStatus == .completed {
            updated.progress = 1
            updated.stage = .publishing
        }

        return updated
    }

    private static let allowedTransitions: [CourseStatus: Set<CourseStatus>] = [
        .draft: [.recording],
        .recording: [.captured],
        .captured: [.queued],
        .queued: [.processing],
        .processing: [.suspended, .needsAttention, .completed],
        .suspended: [.queued],
        .needsAttention: [.queued],
        .completed: []
    ]
}
