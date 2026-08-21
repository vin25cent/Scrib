import Foundation
import Testing
import ScribDomain
@testable import ScribApplication

struct CourseTrackingTests {
    private let presenter = CourseTrackingPresenter()

    @Test func summarySeparatesActiveSuspendedFailedAndCompletedActivities() {
        let jobs = [job(status: .pending), job(status: .processing), job(status: .suspended), job(status: .failed), job(status: .completed)]
        let summary = presenter.summary(for: jobs)
        #expect(summary.totalCount == 5)
        #expect(summary.activeCount == 2)
        #expect(summary.suspendedCount == 1)
        #expect(summary.failedCount == 1)
        #expect(summary.completedCount == 1)
    }

    @Test func filtersAndSortsByMostRecentUpdate() {
        var older = job(status: .pending)
        older.updatedAt = Date(timeIntervalSince1970: 10)
        var newer = job(status: .processing)
        newer.updatedAt = Date(timeIntervalSince1970: 20)
        let completed = job(status: .completed)
        let visible = presenter.jobs([older, completed, newer], matching: .active)
        #expect(visible.map(\.id) == [newer.id, older.id])
    }

    private func job(status: ProcessingStatus) -> ProcessingJob {
        ProcessingJob(
            courseID: CourseID(),
            courseTitle: "Cours",
            teachingUnit: "UE 2.1",
            activity: .localTranscription,
            status: status
        )
    }
}
