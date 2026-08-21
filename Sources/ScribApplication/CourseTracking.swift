import Foundation
import ScribDomain

public enum CourseTrackingFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case suspended
    case failed
    case completed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: "Tous"
        case .active: "En cours"
        case .suspended: "Suspendus"
        case .failed: "Erreurs"
        case .completed: "Terminés"
        }
    }
}

public struct CourseTrackingSummary: Equatable, Sendable {
    public var totalCount: Int
    public var activeCount: Int
    public var suspendedCount: Int
    public var failedCount: Int
    public var completedCount: Int

    public init(totalCount: Int, activeCount: Int, suspendedCount: Int, failedCount: Int, completedCount: Int) {
        self.totalCount = totalCount
        self.activeCount = activeCount
        self.suspendedCount = suspendedCount
        self.failedCount = failedCount
        self.completedCount = completedCount
    }
}

public struct CourseTrackingPresenter: Sendable {
    public init() {}

    public func summary(for jobs: [ProcessingJob]) -> CourseTrackingSummary {
        CourseTrackingSummary(
            totalCount: jobs.count,
            activeCount: jobs.filter(isActive).count,
            suspendedCount: jobs.filter { $0.status == .suspended }.count,
            failedCount: jobs.filter { $0.status == .failed }.count,
            completedCount: jobs.filter { $0.status == .completed }.count
        )
    }

    public func jobs(_ jobs: [ProcessingJob], matching filter: CourseTrackingFilter) -> [ProcessingJob] {
        jobs.filter { job in
            switch filter {
            case .all: true
            case .active: isActive(job)
            case .suspended: job.status == .suspended
            case .failed: job.status == .failed
            case .completed: job.status == .completed
            }
        }.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func isActive(_ job: ProcessingJob) -> Bool {
        job.status == .pending || job.status == .processing
    }
}
