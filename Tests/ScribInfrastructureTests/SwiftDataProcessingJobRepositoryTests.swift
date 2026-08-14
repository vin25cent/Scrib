#if os(macOS)
import Foundation
import Testing
@testable import ScribDomain
@testable import ScribInfrastructure

@Test func swiftDataQueueRoundTripsCheckpointsAndErrors() async throws {
    let repository = try SwiftDataProcessingJobRepository(inMemory: true)
    var job = ProcessingJob(
        courseID: CourseID(),
        courseTitle: "Pharmacologie",
        teachingUnit: "UE 2.11 — Pharmacologie et thérapeutiques",
        status: .suspended,
        stage: .transcribing,
        progress: 0.3,
        attemptCount: 2,
        nextAttemptAt: Date().addingTimeInterval(60),
        lastError: "Connexion interrompue",
        suspensionReasons: [.networkUnavailable]
    )
    job.completeStage(.preparing, outputFingerprint: "prepared")
    job.status = .suspended
    job.stage = .transcribing

    try await repository.save(job)
    let restored = try await repository.job(id: job.id)

    #expect(restored == job)
    #expect(try await repository.jobs().count == 1)

    try await repository.delete(id: job.id)
    #expect(try await repository.jobs().isEmpty)
}
#endif
