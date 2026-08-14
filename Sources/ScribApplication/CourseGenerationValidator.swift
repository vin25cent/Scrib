import Foundation
import ScribDomain

public struct CourseGenerationValidationIssue: Equatable, Sendable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public enum CourseGenerationDecodingError: Error, Sendable {
    case payloadTooLarge(actualBytes: Int, maximumBytes: Int)
    case malformedJSON(String)
    case invalid([CourseGenerationValidationIssue])
}

public struct CourseGenerationValidationPolicy: Equatable, Sendable {
    public var allowedSourceDomains: Set<String>
    public var maximumPayloadBytes: Int
    public var maximumSectionsPerDocument: Int
    public var maximumBlocksPerSection: Int
    public var maximumTableRows: Int

    public init(
        allowedSourceDomains: Set<String> = [
            "has-sante.fr", "sante.gouv.fr", "ansm.sante.fr", "who.int",
            "ema.europa.eu", "nice.org.uk", "cdc.gov"
        ],
        maximumPayloadBytes: Int = 5_000_000,
        maximumSectionsPerDocument: Int = 80,
        maximumBlocksPerSection: Int = 200,
        maximumTableRows: Int = 100
    ) {
        self.allowedSourceDomains = allowedSourceDomains
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumSectionsPerDocument = maximumSectionsPerDocument
        self.maximumBlocksPerSection = maximumBlocksPerSection
        self.maximumTableRows = maximumTableRows
    }
}

public struct CourseGenerationValidator: Sendable {
    public let policy: CourseGenerationValidationPolicy

    public init(policy: CourseGenerationValidationPolicy = .init()) {
        self.policy = policy
    }

    public func decodeAndValidate(
        _ data: Data,
        expectedCourseID: CourseID? = nil
    ) throws -> CourseGenerationEnvelope {
        guard data.count <= policy.maximumPayloadBytes else {
            throw CourseGenerationDecodingError.payloadTooLarge(
                actualBytes: data.count,
                maximumBytes: policy.maximumPayloadBytes
            )
        }
        do {
            let object = try JSONDecoder().decode(StrictJSONValue.self, from: data)
            let shapeIssues = validateJSONShape(object)
            guard shapeIssues.isEmpty else { throw CourseGenerationDecodingError.invalid(shapeIssues) }
        } catch let error as CourseGenerationDecodingError {
            throw error
        } catch {
            throw CourseGenerationDecodingError.malformedJSON(String(describing: error))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: CourseGenerationEnvelope
        do {
            envelope = try decoder.decode(CourseGenerationEnvelope.self, from: data)
        } catch {
            throw CourseGenerationDecodingError.malformedJSON(String(describing: error))
        }
        let issues = validate(envelope, expectedCourseID: expectedCourseID)
        guard issues.isEmpty else { throw CourseGenerationDecodingError.invalid(issues) }
        return envelope
    }

    private func validateJSONShape(_ rootValue: StrictJSONValue) -> [CourseGenerationValidationIssue] {
        var issues: [CourseGenerationValidationIssue] = []
        func object(_ value: StrictJSONValue?, allowed: Set<String>, path: String) -> [String: StrictJSONValue]? {
            guard case let .object(dictionary) = value else { return nil }
            for key in dictionary.keys where !allowed.contains(key) {
                issues.append(.init(path: path.isEmpty ? key : "\(path).\(key)", message: "Propriété JSON inconnue"))
            }
            return dictionary
        }
        func array(_ value: StrictJSONValue?) -> [StrictJSONValue] { if case let .array(values) = value { return values }; return [] }
        guard let root = object(rootValue, allowed: ["schemaVersion", "courseID", "documents", "sources"], path: "") else { return [.init(path: "$", message: "Objet JSON attendu")] }
        for (sourceIndex, value) in array(root["sources"]).enumerated() {
            _ = object(value, allowed: ["id", "authority", "title", "canonicalURL", "verifiedAt"], path: "sources[\(sourceIndex)]")
        }
        for (documentIndex, value) in array(root["documents"]).enumerated() {
            guard let document = object(value, allowed: ["kind", "title", "subtitle", "metadata", "sections"], path: "documents[\(documentIndex)]") else { continue }
            for (metadataIndex, metadata) in array(document["metadata"]).enumerated() {
                _ = object(metadata, allowed: ["label", "value"], path: "documents[\(documentIndex)].metadata[\(metadataIndex)]")
            }
            for (sectionIndex, sectionValue) in array(document["sections"]).enumerated() {
                guard let section = object(sectionValue, allowed: ["title", "blocks"], path: "documents[\(documentIndex)].sections[\(sectionIndex)]") else { continue }
                for (blockIndex, blockValue) in array(section["blocks"]).enumerated() {
                    let blockPath = "documents[\(documentIndex)].sections[\(sectionIndex)].blocks[\(blockIndex)]"
                    guard let block = object(blockValue, allowed: ["type", "text", "items", "table", "callout", "figure", "sourceIDs"], path: blockPath) else { continue }
                    if let table = block["table"] { _ = object(table, allowed: ["caption", "headers", "rows", "columnWidthWeights"], path: "\(blockPath).table") }
                    if let callout = block["callout"] { _ = object(callout, allowed: ["kind", "title", "body", "audioTimestampSeconds"], path: "\(blockPath).callout") }
                    if let figure = block["figure"] { _ = object(figure, allowed: ["assetID", "caption", "altText", "widthPoints"], path: "\(blockPath).figure") }
                }
            }
        }
        return issues
    }

    public func validate(
        _ envelope: CourseGenerationEnvelope,
        expectedCourseID: CourseID? = nil
    ) -> [CourseGenerationValidationIssue] {
        var issues: [CourseGenerationValidationIssue] = []
        if envelope.schemaVersion != "1.0" {
            issues.append(.init(path: "schemaVersion", message: "Version attendue : 1.0"))
        }
        if let expectedCourseID, envelope.courseID != expectedCourseID.rawValue {
            issues.append(.init(path: "courseID", message: "Le cours ne correspond pas à la requête"))
        }

        let kinds = envelope.documents.map(\.kind)
        if envelope.documents.count != 2 || Set(kinds) != Set(CourseDocumentKind.allCases) {
            issues.append(.init(
                path: "documents",
                message: "Un cours complet et une fiche de révision sont obligatoires"
            ))
        }

        let sourceIDs = envelope.sources.map(\.id)
        if Set(sourceIDs).count != sourceIDs.count {
            issues.append(.init(path: "sources", message: "Les identifiants de source doivent être uniques"))
        }
        let knownSourceIDs = Set(sourceIDs)
        for (index, source) in envelope.sources.enumerated() {
            validateSource(source, path: "sources[\(index)]", issues: &issues)
        }

        for (documentIndex, document) in envelope.documents.enumerated() {
            let base = "documents[\(documentIndex)]"
            requireText(document.title, path: "\(base).title", maximum: 300, issues: &issues)
            requireText(document.subtitle, path: "\(base).subtitle", maximum: 500, issues: &issues)
            if document.sections.isEmpty || document.sections.count > policy.maximumSectionsPerDocument {
                issues.append(.init(path: "\(base).sections", message: "Nombre de sections invalide"))
            }
            for (sectionIndex, section) in document.sections.enumerated() {
                let sectionPath = "\(base).sections[\(sectionIndex)]"
                requireText(section.title, path: "\(sectionPath).title", maximum: 300, issues: &issues)
                if section.blocks.isEmpty || section.blocks.count > policy.maximumBlocksPerSection {
                    issues.append(.init(path: "\(sectionPath).blocks", message: "Nombre de blocs invalide"))
                }
                for (blockIndex, block) in section.blocks.enumerated() {
                    validateBlock(
                        block,
                        path: "\(sectionPath).blocks[\(blockIndex)]",
                        knownSourceIDs: knownSourceIDs,
                        issues: &issues
                    )
                }
            }
        }
        return issues
    }

    public func makeDocuments(
        from envelope: CourseGenerationEnvelope,
        imageAssets: [CourseDocumentImageAsset] = [],
        generatedAt: Date = Date()
    ) throws -> [CourseDocument] {
        let issues = validate(envelope)
        guard issues.isEmpty else { throw CourseGenerationDecodingError.invalid(issues) }
        let sources = envelope.sources.compactMap { source -> CourseDocumentSource? in
            guard let url = URL(string: source.canonicalURL) else { return nil }
            return CourseDocumentSource(
                id: source.id,
                authority: source.authority,
                title: source.title,
                url: url,
                verifiedAt: source.verifiedAt
            )
        }
        return envelope.documents.map { generated in
            CourseDocument(
                kind: generated.kind,
                title: generated.title,
                subtitle: generated.subtitle,
                metadata: generated.metadata,
                sections: generated.sections.map { section in
                    CourseDocumentSection(
                        title: section.title,
                        blocks: section.blocks.compactMap(convertBlock)
                    )
                },
                sources: sources,
                imageAssets: imageAssets,
                generatedAt: generatedAt
            )
        }
    }

    private func convertBlock(_ block: GeneratedCourseBlock) -> CourseDocumentBlock? {
        switch block.type {
        case .paragraph:
            return block.text.map(CourseDocumentBlock.paragraph)
        case .bullets:
            return block.items.map(CourseDocumentBlock.bullets)
        case .table:
            return block.table.map {
                .table(.init(
                    caption: $0.caption,
                    headers: $0.headers,
                    rows: $0.rows,
                    columnWidthWeights: $0.columnWidthWeights ?? []
                ))
            }
        case .callout:
            return block.callout.map {
                .callout(
                    kind: $0.kind,
                    title: $0.title,
                    body: $0.body,
                    audioTimestamp: $0.audioTimestampSeconds
                )
            }
        case .figure:
            return block.figure.map {
                .figure(.init(
                    assetID: $0.assetID,
                    caption: $0.caption,
                    altText: $0.altText,
                    widthPoints: $0.widthPoints ?? 360
                ))
            }
        }
    }

    private func validateSource(
        _ source: GeneratedCourseSource,
        path: String,
        issues: inout [CourseGenerationValidationIssue]
    ) {
        requireIdentifier(source.id, path: "\(path).id", issues: &issues)
        requireText(source.authority, path: "\(path).authority", maximum: 300, issues: &issues)
        requireText(source.title, path: "\(path).title", maximum: 500, issues: &issues)
        guard let components = URLComponents(string: source.canonicalURL),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              policy.allowedSourceDomains.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else {
            issues.append(.init(path: "\(path).canonicalURL", message: "Domaine HTTPS non autorisé"))
            return
        }
    }

    private func validateBlock(
        _ block: GeneratedCourseBlock,
        path: String,
        knownSourceIDs: Set<String>,
        issues: inout [CourseGenerationValidationIssue]
    ) {
        for sourceID in block.sourceIDs where !knownSourceIDs.contains(sourceID) {
            issues.append(.init(path: "\(path).sourceIDs", message: "Source inconnue : \(sourceID)"))
        }
        switch block.type {
        case .paragraph:
            if block.items != nil || block.table != nil || block.callout != nil || block.figure != nil {
                issues.append(.init(path: path, message: "Bloc paragraph ambigu"))
            }
            requireText(block.text, path: "\(path).text", maximum: 20_000, issues: &issues)
        case .bullets:
            if block.text != nil || block.table != nil || block.callout != nil || block.figure != nil {
                issues.append(.init(path: path, message: "Bloc bullets ambigu"))
            }
            guard let items = block.items, !items.isEmpty, items.count <= 100 else {
                issues.append(.init(path: "\(path).items", message: "Liste vide ou trop longue"))
                return
            }
            for (index, item) in items.enumerated() {
                requireText(item, path: "\(path).items[\(index)]", maximum: 2_000, issues: &issues)
            }
        case .table:
            if block.text != nil || block.items != nil || block.callout != nil || block.figure != nil {
                issues.append(.init(path: path, message: "Bloc table ambigu"))
            }
            guard let table = block.table else {
                issues.append(.init(path: "\(path).table", message: "Tableau manquant")); return
            }
            if table.headers.isEmpty || table.headers.count > 6 || table.rows.count > policy.maximumTableRows {
                issues.append(.init(path: "\(path).table", message: "Dimensions de tableau invalides"))
            }
            for row in table.rows where row.count != table.headers.count {
                issues.append(.init(path: "\(path).table.rows", message: "Toutes les lignes doivent avoir le même nombre de colonnes"))
            }
            if let weights = table.columnWidthWeights,
               (weights.count != table.headers.count || weights.contains(where: { $0 <= 0 })) {
                issues.append(.init(path: "\(path).table.columnWidthWeights", message: "Largeurs de colonnes invalides"))
            }
        case .callout:
            if block.text != nil || block.items != nil || block.table != nil || block.figure != nil {
                issues.append(.init(path: path, message: "Bloc callout ambigu"))
            }
            guard let callout = block.callout else {
                issues.append(.init(path: "\(path).callout", message: "Encadré manquant")); return
            }
            requireText(callout.title, path: "\(path).callout.title", maximum: 300, issues: &issues)
            requireText(callout.body, path: "\(path).callout.body", maximum: 10_000, issues: &issues)
            if callout.kind == .uncertainty || callout.kind == .medicalImportance {
                if callout.audioTimestampSeconds == nil || callout.audioTimestampSeconds! < 0 {
                    issues.append(.init(path: "\(path).callout.audioTimestampSeconds", message: "Horodatage audio obligatoire"))
                }
            }
        case .figure:
            if block.text != nil || block.items != nil || block.table != nil || block.callout != nil {
                issues.append(.init(path: path, message: "Bloc figure ambigu"))
            }
            guard let figure = block.figure else {
                issues.append(.init(path: "\(path).figure", message: "Figure manquante")); return
            }
            requireIdentifier(figure.assetID, path: "\(path).figure.assetID", issues: &issues)
            requireText(figure.caption, path: "\(path).figure.caption", maximum: 1_000, issues: &issues)
            requireText(figure.altText, path: "\(path).figure.altText", maximum: 1_000, issues: &issues)
            if let width = figure.widthPoints, !(72...468).contains(width) {
                issues.append(.init(path: "\(path).figure.widthPoints", message: "Largeur de figure invalide"))
            }
        }
    }

    private func requireText(
        _ value: String?,
        path: String,
        maximum: Int,
        issues: inout [CourseGenerationValidationIssue]
    ) {
        guard let value else {
            issues.append(.init(path: path, message: "Valeur obligatoire")); return
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > maximum {
            issues.append(.init(path: path, message: "Texte vide ou trop long"))
        }
    }

    private func requireIdentifier(
        _ value: String,
        path: String,
        issues: inout [CourseGenerationValidationIssue]
    ) {
        let allowed = value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
        if value.isEmpty || value.count > 80 || !allowed {
            issues.append(.init(path: path, message: "Identifiant invalide"))
        }
    }
}

private struct StrictJSONKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private indirect enum StrictJSONValue: Decodable {
    case object([String: StrictJSONValue])
    case array([StrictJSONValue])
    case scalar

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: StrictJSONKey.self) {
            var values: [String: StrictJSONValue] = [:]
            for key in container.allKeys { values[key.stringValue] = try container.decode(StrictJSONValue.self, forKey: key) }
            self = .object(values)
        } else if var container = try? decoder.unkeyedContainer() {
            var values: [StrictJSONValue] = []
            while !container.isAtEnd { values.append(try container.decode(StrictJSONValue.self)) }
            self = .array(values)
        } else {
            self = .scalar
        }
    }
}
