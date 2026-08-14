import Foundation
import ScribDomain

public enum TranscriptPassageFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case uncertainty
    case medicalImportance

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: "Tout"
        case .uncertainty: "Incertains"
        case .medicalImportance: "Importants"
        }
    }
}

public struct TranscriptWorkspaceService: Sendable {
    public init() {}

    public func passages(
        in draft: TranscriptDraft,
        matching search: String,
        filter: TranscriptPassageFilter
    ) -> [TranscriptPassage] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft.passages.filter { passage in
            let matchesFilter = switch filter {
            case .all: true
            case .uncertainty: passage.flags.contains(.uncertainty)
            case .medicalImportance: passage.flags.contains(.medicalImportance)
            }
            let matchesSearch = query.isEmpty
                || passage.text.localizedCaseInsensitiveContains(query)
                || passage.speaker.localizedCaseInsensitiveContains(query)
            return matchesFilter && matchesSearch
        }
    }

    public func updating(
        _ draft: TranscriptDraft,
        passageID: UUID,
        text: String,
        at date: Date = Date()
    ) -> TranscriptDraft {
        var copy = draft
        guard let index = copy.passages.firstIndex(where: { $0.id == passageID }) else { return draft }
        copy.passages[index].text = text
        copy.version += 1
        copy.updatedAt = date
        return copy
    }

    public func toggling(
        _ flag: TranscriptPassageFlag,
        in draft: TranscriptDraft,
        passageID: UUID,
        at date: Date = Date()
    ) -> TranscriptDraft {
        var copy = draft
        guard let index = copy.passages.firstIndex(where: { $0.id == passageID }) else { return draft }
        if copy.passages[index].flags.contains(flag) {
            copy.passages[index].flags.remove(flag)
        } else {
            copy.passages[index].flags.insert(flag)
        }
        copy.version += 1
        copy.updatedAt = date
        return copy
    }

    public func contentFingerprint(for draft: TranscriptDraft) -> String {
        stableFingerprint(draft.plainText)
    }

    public func stableFingerprint(_ text: String) -> String {
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_11
        for byte in text.utf8 {
            first ^= UInt64(byte)
            first &*= 1_099_511_628_211
            second ^= UInt64(byte) &+ 0x9d
            second &*= 1_099_511_628_211
        }
        return String(format: "%016llx%016llx", first, second)
    }
}

public enum SupportImportIssue: Error, Equatable, LocalizedError {
    case unsupportedExtension(String)
    case generatedDocument
    case fileTooLarge(maximumBytes: Int64)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedExtension(value): "Le format .\(value) n’est pas pris en charge."
        case .generatedDocument: "Ce fichier ressemble à un document déjà généré par Scrib."
        case let .fileTooLarge(maximumBytes):
            "Le support dépasse la limite de \(ByteCountFormatter.string(fromByteCount: maximumBytes, countStyle: .file))."
        }
    }
}

public struct SupportImportValidator: Sendable {
    public let maximumBytes: Int64

    public init(maximumBytes: Int64 = 100 * 1_024 * 1_024) {
        self.maximumBytes = maximumBytes
    }

    public func validate(fileName: String, byteCount: Int64) throws -> SupportDocumentKind {
        let normalizedName = fileName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if normalizedName.hasPrefix("cours complet") || normalizedName.hasPrefix("fiche de revision") {
            throw SupportImportIssue.generatedDocument
        }
        guard byteCount <= maximumBytes else {
            throw SupportImportIssue.fileTooLarge(maximumBytes: maximumBytes)
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "doc", "docx": return .word
        case "pdf": return .pdf
        case "ppt", "pptx": return .presentation
        case "xls", "xlsx": return .spreadsheet
        case "png", "jpg", "jpeg", "heic", "tiff": return .image
        default: throw SupportImportIssue.unsupportedExtension(ext.isEmpty ? "inconnu" : ext)
        }
    }
}

public struct DemonstrationWorkspaceFactory: Sendable {
    public init() {}

    public func transcript() -> TranscriptDraft {
        TranscriptDraft(
            courseTitle: "Pipeline médical — démonstration",
            teachingUnit: "UE 2.11 — Pharmacologie et thérapeutiques",
            passages: [
                TranscriptPassage(
                    speaker: "Enseignant",
                    startTime: 2,
                    text: "Cette transcription est un contenu fictif utilisé pour vérifier le pipeline local de Scrib."
                ),
                TranscriptPassage(
                    speaker: "Enseignant",
                    startTime: 7,
                    text: "La régularité des prises et la vérification de la prescription sont présentées comme des points importants.",
                    flags: [.medicalImportance]
                ),
                TranscriptPassage(
                    speaker: "Étudiant 1",
                    startTime: 13,
                    text: "Comment retrouver rapidement une information signalée pendant la réécoute ?"
                ),
                TranscriptPassage(
                    speaker: "Enseignant",
                    startTime: 18,
                    text: "Le terme entendu à cet instant doit être confirmé avant la génération définitive.",
                    flags: [.uncertainty]
                ),
                TranscriptPassage(
                    speaker: "Enseignant",
                    startTime: 23,
                    text: "Exemple fictif pour tester la confidentialité : patient DEMO, courriel demo.patient@example.invalid."
                )
            ],
            isDemonstration: true
        )
    }

    public func supportDocument() -> SupportDocument {
        let id = UUID()
        let extraction = SupportDocumentExtraction(
            documentID: id,
            sourceFileName: "Support-enseignant-demo.docx",
            title: "Repères de pharmacologie",
            textElements: [
                .init(kind: .heading, text: "Sécurisation de l’administration", level: 1, order: 0),
                .init(kind: .listItem, text: "Vérifier la prescription et l’identité.", order: 1),
                .init(kind: .listItem, text: "Tracer l’administration et surveiller les effets.", order: 2)
            ],
            tables: [
                .init(order: 3, rows: [
                    ["Étape", "Point de vigilance"],
                    ["Avant", "Prescription et contre-indications"],
                    ["Après", "Traçabilité et surveillance"]
                ])
            ]
        )
        return SupportDocument(
            id: id,
            originalFileName: "Support-enseignant-demo.docx",
            localURL: nil,
            kind: .word,
            byteCount: 428_000,
            isDemonstration: true,
            extraction: extraction
        )
    }
}

@MainActor
public final class InMemorySupportDocumentStore: SupportDocumentImporting {
    private let validator: SupportImportValidator
    private let extractor: (any SupportDocumentExtracting)?
    private var storedDocuments: [SupportDocument] = []

    public init(
        validator: SupportImportValidator = .init(),
        extractor: (any SupportDocumentExtracting)? = nil
    ) {
        self.validator = validator
        self.extractor = extractor
    }

    public func documents() -> [SupportDocument] {
        storedDocuments.sorted { $0.importedAt > $1.importedAt }
    }

    public func importDocument(from sourceURL: URL) throws -> SupportDocument {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        let kind = try validator.validate(fileName: sourceURL.lastPathComponent, byteCount: byteCount)
        var document = SupportDocument(
            originalFileName: sourceURL.lastPathComponent,
            localURL: sourceURL,
            kind: kind,
            byteCount: byteCount
        )
        if let extractor, kind == .word || kind == .pdf {
            do {
                document.extraction = try extractor.extract(
                    documentID: document.id,
                    fileName: document.originalFileName,
                    kind: kind,
                    from: sourceURL
                )
            } catch {
                document.extractionFailure = error.localizedDescription
            }
        }
        storedDocuments.append(document)
        return document
    }

    public func deleteDocument(id: UUID) throws {
        storedDocuments.removeAll { $0.id == id }
    }
}
