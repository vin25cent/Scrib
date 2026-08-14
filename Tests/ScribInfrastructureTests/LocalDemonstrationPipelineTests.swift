import Foundation
import ScribApplication
import ScribDomain
import Testing
@testable import ScribInfrastructure

struct LocalDemonstrationPipelineTests {
    @Test func privacyReviewThenCompletesEveryStageAndRendersDocuments() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrib-demo-pipeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let audioURL = temporary.appendingPathComponent("source.wav")
        try Data("RIFF-demo-audio-fixture".utf8).write(to: audioURL)
        let transcript = DemonstrationWorkspaceFactory().transcript()
        let teacher = Teacher(
            name: "Enseignant Démo",
            recordingAuthorizationConfirmedAt: Date(timeIntervalSince1970: 1)
        )
        let course = Course(
            id: transcript.courseID,
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1).first { $0.code == "2.1" }!,
            title: transcript.courseTitle,
            teacher: teacher,
            expectedDuration: .oneHour,
            courseDate: Date(timeIntervalSince1970: 2),
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let repository = InMemoryProcessingJobRepository()
        let pipeline = LocalDemonstrationPipeline(
            repository: repository,
            rootDirectory: temporary.appendingPathComponent("workspace")
        )
        var request = DemonstrationPipelineRequest(
            course: course,
            audioURL: audioURL,
            audioAttribution: "CRSN — CC BY-SA 4.0",
            audioLandingURL: URL(string: "https://commons.wikimedia.org/")!,
            transcript: transcript,
            supportExtractions: [
                DemonstrationWorkspaceFactory().supportDocument().extraction!
            ]
        )

        do {
            _ = try await pipeline.run(request)
            Issue.record("La confidentialité aurait dû bloquer la première exécution.")
        } catch let error as DemonstrationPipelineError {
            guard case let .privacyApprovalRequired(findings) = error else {
                Issue.record("Erreur inattendue : \(error)")
                return
            }
            #expect(!findings.isEmpty)
        }

        let blockedJob = try #require(await repository.jobs().first)
        #expect(blockedJob.status == .needsAttention)
        #expect(blockedJob.checkpoints.map(\.stage) == [
            .preparing, .normalizingAudio, .transcribing
        ])

        let privacyContent = transcript.plainText
            + "\n"
            + request.supportExtractions.map(\.plainText).joined(separator: "\n")
        let fingerprint = TranscriptWorkspaceService().stableFingerprint(privacyContent)
        request.privacyReview = PrivacyReview(
            contentFingerprint: fingerprint,
            decision: .approved,
            reviewedAt: Date(timeIntervalSince1970: 3)
        )
        let result = try await pipeline.run(request)

        #expect(result.job.status == .completed)
        #expect(Set(result.job.checkpoints.map(\.stage)) == Set(ProcessingStage.allCases))
        #expect(FileManager.default.fileExists(atPath: result.localAudioURL.path))
        #expect(FileManager.default.fileExists(atPath: result.transcriptURL.path))
        #expect(FileManager.default.fileExists(atPath: result.fullCourseURL.path))
        #expect(FileManager.default.fileExists(atPath: result.revisionSheetURL.path))
        #expect(FileManager.default.fileExists(atPath: result.manifestURL.path))
        #expect(FileManager.default.fileExists(atPath: result.supportContextURL.path))
        let supportContext = try Data(contentsOf: result.supportContextURL)
        #expect(String(decoding: supportContext, as: UTF8.self).contains("Support-enseignant-demo.docx"))
        #expect((try Data(contentsOf: result.fullCourseURL)).starts(with: [0x50, 0x4B]))
        #expect((try Data(contentsOf: result.revisionSheetURL)).starts(with: [0x50, 0x4B]))

        try await pipeline.reset(courseID: course.id)
        #expect(await repository.jobs().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: result.workspaceURL.path))
    }
}
