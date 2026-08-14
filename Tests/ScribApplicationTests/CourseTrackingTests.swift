import Foundation
import Testing
import ScribDomain
@testable import ScribApplication

struct CourseTrackingTests {
    private let presenter = CourseTrackingPresenter()

    @Test func summarySeparatesActiveAttentionAndCompletedCourses() {
        let jobs = [job(status: .queued), job(status: .processing), job(status: .needsAttention), job(status: .completed)]
        let summary = presenter.summary(for: jobs)
        #expect(summary.totalCount == 4)
        #expect(summary.activeCount == 2)
        #expect(summary.attentionCount == 1)
        #expect(summary.completedCount == 1)
    }

    @Test func filtersAndSortsByMostRecentUpdate() {
        var older = job(status: .queued)
        older.updatedAt = Date(timeIntervalSince1970: 10)
        var newer = job(status: .suspended)
        newer.updatedAt = Date(timeIntervalSince1970: 20)
        let completed = job(status: .completed)
        let visible = presenter.jobs([older, completed, newer], matching: .active)
        #expect(visible.map(\.id) == [newer.id, older.id])
    }

    @Test func timelineShowsCompletedCurrentAndPendingStages() {
        var value = job(status: .processing)
        value.checkpoints = [
            .init(stage: .preparing, completedAt: Date(timeIntervalSince1970: 10)),
            .init(stage: .normalizingAudio, completedAt: Date(timeIntervalSince1970: 20))
        ]
        value.stage = .transcribing
        let timeline = presenter.timeline(for: value)
        #expect(timeline[0].state == .completed(Date(timeIntervalSince1970: 10)))
        #expect(timeline[1].state == .completed(Date(timeIntervalSince1970: 20)))
        #expect(timeline[2].state == .current)
        #expect(timeline[3].state == .pending)
    }

    @Test func suspendedCurrentStageIsMarkedBlocked() {
        var value = job(status: .suspended)
        value.stage = .preparing
        #expect(presenter.timeline(for: value)[0].state == .blocked)
    }

    private func job(status: CourseStatus) -> ProcessingJob {
        ProcessingJob(courseID: CourseID(), courseTitle: "Cours", teachingUnit: "UE 2.1", status: status)
    }
}
