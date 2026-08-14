import Foundation
import ScribDomain

public enum CourseTrackingFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case attention
    case completed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: "Tous"
        case .active: "En cours"
        case .attention: "À vérifier"
        case .completed: "Terminés"
        }
    }
}

public enum CourseTrackingStageState: Equatable, Sendable {
    case completed(Date)
    case current
    case blocked
    case pending
}

public struct CourseTrackingStageItem: Equatable, Sendable {
    public var stage: ProcessingStage
    public var state: CourseTrackingStageState

    public init(stage: ProcessingStage, state: CourseTrackingStageState) {
        self.stage = stage
        self.state = state
    }
}

public struct CourseTrackingSummary: Equatable, Sendable {
    public var totalCount: Int
    public var activeCount: Int
    public var attentionCount: Int
    public var completedCount: Int

    public init(totalCount: Int, activeCount: Int, attentionCount: Int, completedCount: Int) {
        self.totalCount = totalCount
        self.activeCount = activeCount
        self.attentionCount = attentionCount
        self.completedCount = completedCount
    }
}

public struct CourseTrackingPresenter: Sendable {
    public init() {}

    public func summary(for jobs: [ProcessingJob]) -> CourseTrackingSummary {
        CourseTrackingSummary(
            totalCount: jobs.count,
            activeCount: jobs.filter(isActive).count,
            attentionCount: jobs.filter { $0.status == .needsAttention }.count,
            completedCount: jobs.filter { $0.status == .completed }.count
        )
    }

    public func jobs(_ jobs: [ProcessingJob], matching filter: CourseTrackingFilter) -> [ProcessingJob] {
        jobs.filter { job in
            switch filter {
            case .all: true
            case .active: isActive(job)
            case .attention: job.status == .needsAttention
            case .completed: job.status == .completed
            }
        }.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    public func timeline(for job: ProcessingJob) -> [CourseTrackingStageItem] {
        let checkpoints = job.checkpoints.reduce(into: [ProcessingStage: Date]()) { result, checkpoint in
            result[checkpoint.stage] = checkpoint.completedAt
        }
        let nextStage = job.nextStage
        return ProcessingStage.allCases.map { stage in
            let state: CourseTrackingStageState
            if let completedAt = checkpoints[stage] {
                state = .completed(completedAt)
            } else if stage == nextStage || stage == job.stage {
                state = job.status == .needsAttention || job.status == .suspended ? .blocked : .current
            } else {
                state = .pending
            }
            return CourseTrackingStageItem(stage: stage, state: state)
        }
    }

    private func isActive(_ job: ProcessingJob) -> Bool {
        job.status != .completed && job.status != .needsAttention
    }
}
