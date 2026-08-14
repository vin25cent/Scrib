import Foundation
import ScribDomain

public struct DemonstrationPipelineRequest: Equatable, Sendable {
    public var course: Course
    public var audioURL: URL
    public var audioAttribution: String
    public var audioLandingURL: URL?
    public var transcript: TranscriptDraft
    public var privacyReview: PrivacyReview?
    public var supportExtractions: [SupportDocumentExtraction]

    public init(
        course: Course,
        audioURL: URL,
        audioAttribution: String,
        audioLandingURL: URL? = nil,
        transcript: TranscriptDraft,
        privacyReview: PrivacyReview? = nil,
        supportExtractions: [SupportDocumentExtraction] = []
    ) {
        self.course = course
        self.audioURL = audioURL
        self.audioAttribution = audioAttribution
        self.audioLandingURL = audioLandingURL
        self.transcript = transcript
        self.privacyReview = privacyReview
        self.supportExtractions = supportExtractions
    }
}

public struct DemonstrationPipelineResult: Equatable, Codable, Sendable {
    public var job: ProcessingJob
    public var workspaceURL: URL
    public var localAudioURL: URL
    public var transcriptURL: URL
    public var fullCourseURL: URL
    public var revisionSheetURL: URL
    public var manifestURL: URL
    public var supportContextURL: URL

    public init(
        job: ProcessingJob,
        workspaceURL: URL,
        localAudioURL: URL,
        transcriptURL: URL,
        fullCourseURL: URL,
        revisionSheetURL: URL,
        manifestURL: URL,
        supportContextURL: URL
    ) {
        self.job = job
        self.workspaceURL = workspaceURL
        self.localAudioURL = localAudioURL
        self.transcriptURL = transcriptURL
        self.fullCourseURL = fullCourseURL
        self.revisionSheetURL = revisionSheetURL
        self.manifestURL = manifestURL
        self.supportContextURL = supportContextURL
    }
}

public enum DemonstrationPipelineError: LocalizedError, Sendable {
    case privacyApprovalRequired([PrivacyFinding])
    case missingArtifact(String)

    public var errorDescription: String? {
        switch self {
        case let .privacyApprovalRequired(findings):
            "La démonstration est bloquée par \(findings.count) alerte(s) de confidentialité."
        case let .missingArtifact(name):
            "L’artefact de démonstration « \(name) » est introuvable."
        }
    }
}

public protocol DemonstrationPipelineRunning: Sendable {
    func run(_ request: DemonstrationPipelineRequest) async throws -> DemonstrationPipelineResult
    func reset(courseID: CourseID) async throws
}

public struct DemonstrationDocumentFactory: Sendable {
    public init() {}

    public func documents(for request: DemonstrationPipelineRequest) -> (CourseDocument, CourseDocument) {
        let metadata = [
            CourseDocumentMetadata(label: "Semestre", value: request.course.semester.displayName),
            CourseDocumentMetadata(label: "UE", value: request.course.teachingUnit.displayName),
            CourseDocumentMetadata(label: "Cours", value: request.course.title),
            CourseDocumentMetadata(label: "Enseignant", value: request.course.teacherName),
            CourseDocumentMetadata(
                label: "Date",
                value: request.course.courseDate.formatted(date: .abbreviated, time: .omitted)
            ),
            CourseDocumentMetadata(label: "Audio de démonstration", value: request.audioAttribution),
            CourseDocumentMetadata(
                label: "Supports enseignant",
                value: "\(request.supportExtractions.count) support(s) extrait(s) localement"
            )
        ]

        let transcriptBlocks = request.transcript.passages.map(block(for:))
        let important = request.transcript.passages.filter {
            $0.flags.contains(.medicalImportance)
        }
        let uncertain = request.transcript.passages.filter {
            $0.flags.contains(.uncertainty)
        }
        let source = request.audioLandingURL.map {
            CourseDocumentSource(
                authority: "Wikimedia Commons",
                title: request.audioAttribution,
                url: $0,
                verifiedAt: Date()
            )
        }

        let fullCourse = CourseDocument(
            kind: .fullCourse,
            title: request.course.title,
            subtitle: request.course.teachingUnit.displayName,
            metadata: metadata,
            sections: [
                CourseDocumentSection(
                    title: "Objectifs de la démonstration",
                    blocks: [.bullets([
                        "Valider le passage d’un audio local aux documents Word.",
                        "Conserver les horodatages des passages signalés.",
                        "Vérifier la barrière locale de confidentialité avant la structuration."
                    ])]
                ),
                supportSection(for: request.supportExtractions),
                CourseDocumentSection(
                    title: "Transcription structurée",
                    blocks: transcriptBlocks
                ),
                CourseDocumentSection(
                    title: "Points de vigilance",
                    blocks: vigilanceBlocks(important: important, uncertain: uncertain)
                )
            ],
            sources: source.map { [$0] } ?? [],
            generatedAt: Date()
        )

        let revisionItems = request.transcript.passages.prefix(4).map {
            "\($0.speaker) — \($0.text)"
        }
        let revisionSheet = CourseDocument(
            kind: .revisionSheet,
            title: request.course.title,
            subtitle: "Fiche de révision — \(request.course.teachingUnit.displayName)",
            metadata: metadata,
            sections: [
                CourseDocumentSection(
                    title: "À retenir",
                    blocks: [.bullets(Array(revisionItems))]
                ),
                supportRevisionSection(for: request.supportExtractions),
                CourseDocumentSection(
                    title: "À réécouter",
                    blocks: revisionCallouts(from: uncertain + important)
                ),
                CourseDocumentSection(
                    title: "Questions flash",
                    blocks: [
                        .paragraph("1. Quelle notion principale est présentée dans l’audio ?"),
                        .paragraph("2. Quels passages nécessitent une vérification ?"),
                        .paragraph("3. Quel lien existe entre le cours complet et la fiche ?")
                    ]
                )
            ],
            sources: source.map { [$0] } ?? [],
            generatedAt: Date()
        )
        return (fullCourse, revisionSheet)
    }

    private func block(for passage: TranscriptPassage) -> CourseDocumentBlock {
        if passage.flags.contains(.medicalImportance) {
            return .callout(
                kind: .medicalImportance,
                title: "Information médicale importante",
                body: passage.text,
                audioTimestamp: passage.startTime
            )
        }
        if passage.flags.contains(.uncertainty) {
            return .callout(
                kind: .uncertainty,
                title: "Passage incertain — \(passage.speaker)",
                body: passage.text,
                audioTimestamp: passage.startTime
            )
        }
        return .paragraph("\(passage.speaker) [\(timestamp(passage.startTime))] — \(passage.text)")
    }

    private func vigilanceBlocks(
        important: [TranscriptPassage],
        uncertain: [TranscriptPassage]
    ) -> [CourseDocumentBlock] {
        if important.isEmpty && uncertain.isEmpty {
            return [.paragraph("Aucun passage n’a été signalé dans cette démonstration.")]
        }
        return [
            .bullets([
                "\(important.count) information(s) médicale(s) importante(s).",
                "\(uncertain.count) passage(s) incertain(s) à réécouter."
            ])
        ]
    }

    private func revisionCallouts(from passages: [TranscriptPassage]) -> [CourseDocumentBlock] {
        guard !passages.isEmpty else {
            return [.paragraph("Aucun passage à réécouter.")]
        }
        return passages.map {
            .callout(
                kind: $0.flags.contains(.medicalImportance) ? .medicalImportance : .uncertainty,
                title: $0.flags.contains(.medicalImportance) ? "Point important" : "Terme à confirmer",
                body: $0.text,
                audioTimestamp: $0.startTime
            )
        }
    }

    private func supportSection(
        for extractions: [SupportDocumentExtraction]
    ) -> CourseDocumentSection {
        guard !extractions.isEmpty else {
            return CourseDocumentSection(
                title: "Support de l’enseignant",
                blocks: [.paragraph("Aucun support enseignant extrait n’est associé à cette démonstration.")]
            )
        }
        var blocks: [CourseDocumentBlock] = extractions.flatMap { extraction in
            let highlights = supportHighlights(from: extraction, limit: 8)
            var documentBlocks: [CourseDocumentBlock] = [
                .paragraph(
                    "\(extraction.sourceFileName) — contenu extrait localement et conservé comme provenance."
                )
            ]
            if !highlights.isEmpty { documentBlocks.append(.bullets(highlights)) }
            return documentBlocks
        }
        let tables = extractions.flatMap(\.tables).prefix(2).compactMap(courseTable(from:))
        blocks += tables.map(CourseDocumentBlock.table)
        return CourseDocumentSection(title: "Support de l’enseignant", blocks: blocks)
    }

    private func supportRevisionSection(
        for extractions: [SupportDocumentExtraction]
    ) -> CourseDocumentSection {
        let terms = extractions.flatMap { supportHighlights(from: $0, limit: 5) }
        return CourseDocumentSection(
            title: "Repères issus du support",
            blocks: terms.isEmpty
                ? [.paragraph("Aucun repère de support disponible.")]
                : [.bullets(Array(terms.prefix(10)))]
        )
    }

    private func courseTable(from extracted: SupportExtractedTable) -> CourseDocumentTable? {
        guard let headers = extracted.rows.first, !headers.isEmpty, headers.count <= 6 else { return nil }
        let rows = extracted.rows.dropFirst().filter { $0.count == headers.count }
        guard !rows.isEmpty else { return nil }
        return CourseDocumentTable(headers: headers, rows: Array(rows))
    }

    private func supportHighlights(
        from extraction: SupportDocumentExtraction,
        limit: Int
    ) -> [String] {
        var candidates = extraction.textElements
            .filter { $0.kind == .heading || $0.kind == .listItem }
            .map(\.text)
        if candidates.isEmpty {
            candidates = extraction.textElements.map(\.text)
        }
        if candidates.isEmpty {
            candidates = extraction.pages.flatMap {
                $0.text.components(separatedBy: .newlines)
            }
        }
        var seen = Set<String>()
        return candidates.filter { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return false }
            return seen.insert(normalized).inserted
        }.prefix(limit).map { $0 }
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
