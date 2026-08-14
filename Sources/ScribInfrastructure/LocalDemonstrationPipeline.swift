import Foundation
import ScribApplication
import ScribDomain

public actor LocalDemonstrationPipeline: DemonstrationPipelineRunning {
    private let repository: any ProcessingJobRepository
    private let renderer: any StructuredDocumentRendering
    private let rootDirectory: URL
    private let transcriptService = TranscriptWorkspaceService()
    private let privacyGate = CloudPrivacyGate()
    private let documentFactory = DemonstrationDocumentFactory()
    private let fileManager: FileManager

    public init(
        repository: any ProcessingJobRepository,
        renderer: any StructuredDocumentRendering = OOXMLDocumentRenderer(),
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.repository = repository
        self.renderer = renderer
        self.rootDirectory = rootDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Scrib/Demonstration", isDirectory: true)
        self.fileManager = fileManager
    }

    public func run(
        _ request: DemonstrationPipelineRequest
    ) async throws -> DemonstrationPipelineResult {
        let workspace = workspaceURL(for: request.course.id)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        var job = try await existingJob(courseID: request.course.id) ?? ProcessingJob(course: request.course)
        job.status = .processing
        job.lastError = nil
        job.suspensionReasons = []
        job.updatedAt = Date()
        try await repository.save(job)

        do {
            for stage in ProcessingStage.allCases where !job.checkpoints.contains(where: { $0.stage == stage }) {
                job.stage = stage
                job.status = .processing
                job.updatedAt = Date()
                try await repository.save(job)
                let fingerprint = try execute(stage, request: request, workspace: workspace)
                job.completeStage(stage, outputFingerprint: fingerprint)
                job.status = job.nextStage == nil ? .completed : .processing
                try await repository.save(job)
            }
            job.status = .completed
            job.progress = 1
            job.stage = .publishing
            job.updatedAt = Date()
            try await repository.save(job)
            let result = try result(for: job, workspace: workspace)
            try encode(result, to: result.manifestURL)
            return result
        } catch {
            job.status = .needsAttention
            job.lastError = error.localizedDescription
            job.updatedAt = Date()
            try await repository.save(job)
            throw error
        }
    }

    public func reset(courseID: CourseID) async throws {
        let workspace = workspaceURL(for: courseID)
        let expectedParent = rootDirectory.standardizedFileURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        let actualParent = workspace.deletingLastPathComponent().standardizedFileURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        guard actualParent.caseInsensitiveCompare(expectedParent) == .orderedSame else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        if fileManager.fileExists(atPath: workspace.path) {
            try fileManager.removeItem(at: workspace)
        }
        if let job = try await existingJob(courseID: courseID) {
            try await repository.delete(id: job.id)
        }
    }

    private func execute(
        _ stage: ProcessingStage,
        request: DemonstrationPipelineRequest,
        workspace: URL
    ) throws -> String {
        switch stage {
        case .preparing:
            return try prepareAudio(request: request, workspace: workspace)
        case .normalizingAudio:
            return try recordPassthroughNormalization(workspace: workspace)
        case .transcribing:
            let url = transcriptURL(workspace)
            try encode(request.transcript, to: url)
            return transcriptService.contentFingerprint(for: request.transcript)
        case .analyzing:
            try validatePrivacy(request)
            try encode(request.supportExtractions, to: supportContextURL(workspace))
            let documents = documentFactory.documents(for: request)
            try encode(documents.0, to: fullCourseModelURL(workspace))
            try encode(documents.1, to: revisionModelURL(workspace))
            return transcriptService.stableFingerprint(
                request.transcript.plainText
                    + request.audioAttribution
                    + request.supportExtractions.map(\.plainText).joined(separator: "\n")
            )
        case .rendering:
            let fullCourse = try decode(CourseDocument.self, from: fullCourseModelURL(workspace))
            let revision = try decode(CourseDocument.self, from: revisionModelURL(workspace))
            try renderer.render(fullCourse, to: renderedFullCourseURL(workspace))
            try renderer.render(revision, to: renderedRevisionURL(workspace))
            return try artifactFingerprint([
                renderedFullCourseURL(workspace), renderedRevisionURL(workspace)
            ])
        case .publishing:
            try publish(renderedFullCourseURL(workspace), to: publishedFullCourseURL(workspace))
            try publish(renderedRevisionURL(workspace), to: publishedRevisionURL(workspace))
            return try artifactFingerprint([
                publishedFullCourseURL(workspace), publishedRevisionURL(workspace)
            ])
        }
    }

    private func prepareAudio(
        request: DemonstrationPipelineRequest,
        workspace: URL
    ) throws -> String {
        let inputDirectory = workspace.appendingPathComponent("input", isDirectory: true)
        try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        let destination = localAudioURL(workspace, source: request.audioURL)
        if !fileManager.fileExists(atPath: destination.path) {
            #if os(macOS)
            let didAccess = request.audioURL.startAccessingSecurityScopedResource()
            defer { if didAccess { request.audioURL.stopAccessingSecurityScopedResource() } }
            #endif
            try fileManager.copyItem(at: request.audioURL, to: destination)
        }
        let values = try destination.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0 else {
            throw DemonstrationPipelineError.missingArtifact("audio")
        }
        return transcriptService.stableFingerprint("\(destination.lastPathComponent):\(size)")
    }

    private func recordPassthroughNormalization(workspace: URL) throws -> String {
        let marker = workspace.appendingPathComponent("audio-normalization.json")
        let payload = [
            "mode": "passthrough-demonstration",
            "description": "Aucun filtre audio n’est appliqué avant le benchmark sur le Mac cible."
        ]
        try encode(payload, to: marker)
        return transcriptService.stableFingerprint(payload.values.sorted().joined())
    }

    private func validatePrivacy(_ request: DemonstrationPipelineRequest) throws {
        let content = request.transcript.plainText
            + "\n"
            + request.supportExtractions.map(\.plainText).joined(separator: "\n")
        let fingerprint = transcriptService.stableFingerprint(content)
        switch privacyGate.evaluate(
            text: content,
            contentFingerprint: fingerprint,
            review: request.privacyReview
        ) {
        case .allowedNoIdentifiers, .allowedAfterManualReview:
            return
        case let .blocked(findings):
            throw DemonstrationPipelineError.privacyApprovalRequired(findings)
        }
    }

    private func publish(_ source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            throw DemonstrationPipelineError.missingArtifact(source.lastPathComponent)
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contentsOf: source).write(to: destination, options: .atomic)
    }

    private func result(
        for job: ProcessingJob,
        workspace: URL
    ) throws -> DemonstrationPipelineResult {
        let audioDirectory = workspace.appendingPathComponent("input", isDirectory: true)
        guard let audio = try fileManager.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: nil
        ).first else {
            throw DemonstrationPipelineError.missingArtifact("audio")
        }
        let result = DemonstrationPipelineResult(
            job: job,
            workspaceURL: workspace,
            localAudioURL: audio,
            transcriptURL: transcriptURL(workspace),
            fullCourseURL: publishedFullCourseURL(workspace),
            revisionSheetURL: publishedRevisionURL(workspace),
            manifestURL: workspace.appendingPathComponent("artifacts.json"),
            supportContextURL: supportContextURL(workspace)
        )
        for url in [
            result.transcriptURL,
            result.supportContextURL,
            result.fullCourseURL,
            result.revisionSheetURL
        ]
        where !fileManager.fileExists(atPath: url.path) {
            throw DemonstrationPipelineError.missingArtifact(url.lastPathComponent)
        }
        return result
    }

    private func existingJob(courseID: CourseID) async throws -> ProcessingJob? {
        try await repository.jobs().first { $0.courseID == courseID }
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard fileManager.fileExists(atPath: url.path) else {
            throw DemonstrationPipelineError.missingArtifact(url.lastPathComponent)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func artifactFingerprint(_ urls: [URL]) throws -> String {
        let description = try urls.map { url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return "\(url.lastPathComponent):\(size)"
        }.joined(separator: "|")
        return transcriptService.stableFingerprint(description)
    }

    private func workspaceURL(for courseID: CourseID) -> URL {
        rootDirectory.appendingPathComponent(courseID.rawValue.uuidString, isDirectory: true)
    }

    private func localAudioURL(_ workspace: URL, source: URL) -> URL {
        workspace.appendingPathComponent("input", isDirectory: true)
            .appendingPathComponent("source.\(source.pathExtension.lowercased())")
    }

    private func transcriptURL(_ workspace: URL) -> URL {
        workspace.appendingPathComponent("transcript/transcript-demo.json")
    }

    private func fullCourseModelURL(_ workspace: URL) -> URL {
        workspace.appendingPathComponent("structured/course-model.json")
    }

    private func revisionModelURL(_ workspace: URL) -> URL {
        workspace.appendingPathComponent("structured/revision-model.json")
    }

    private func supportContextURL(_ workspace: URL) -> URL {
        workspace.appendingPathComponent("structured/support-context.json")
    }

    private func renderedFullCourseURL(_ workspace: URL) -> URL {
        workspace.appendingPathComponent("output/Cours-complet-demo.docx")
    }

    private func renderedRevisionURL(_ workspace: URL) -> URL {
        workspace.appendingPathComponent("output/Fiche-revision-demo.docx")
    }

    private func publishedFullCourseURL(_ workspace: URL) -> URL {
        workspace.appendingPathComponent("published/Cours-complet-demo.docx")
    }

    private func publishedRevisionURL(_ workspace: URL) -> URL {
        workspace.appendingPathComponent("published/Fiche-revision-demo.docx")
    }
}
