#if os(macOS)
import Foundation
import Testing
@testable import ScribDomain
@testable import ScribInfrastructure

@Test func swiftDataTrackingRoundTripsActivityAndState() async throws {
    let repository = try SwiftDataProcessingJobRepository(inMemory: true)
    let job = ProcessingJob(
        courseID: CourseID(),
        courseTitle: "Pharmacologie",
        teachingUnit: "UE 2.11 — Pharmacologie et thérapeutiques",
        activity: .localTranscription,
        status: .suspended,
        reportedProgress: 0.3,
        suspensionReason: "Transcription annulée",
        lastError: "Connexion interrompue",
    )

    try await repository.save(job)
    let restored = try await repository.job(id: job.id)

    #expect(restored == job)
    #expect(try await repository.jobs().count == 1)

    try await repository.delete(id: job.id)
    #expect(try await repository.jobs().isEmpty)
}
#endif
