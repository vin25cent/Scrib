import ScribApplication
import ScribDomain
import SwiftUI

struct TranscriptEditorView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.transcriptDraft == nil {
                WorkspaceEmptyState(
                    title: "Aucune transcription disponible",
                    message: "Une transcription apparaîtra ici après le traitement local d’un cours.",
                    systemImage: "text.alignleft"
                )
            } else {
                toolbar
                transcriptContent
            }
        }
        .background(ScribDesign.canvas)
        .navigationTitle("Transcription")
        .overlay(alignment: .bottomTrailing) {
            WorkspaceNotice(model: model)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.transcriptDraft?.courseTitle ?? "Éditeur de transcription")
                    .font(.system(size: 28, weight: .semibold))
                Text(model.transcriptDraft?.teachingUnit ?? "Corrigez le texte localement avant de générer les documents.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let draft = model.transcriptDraft {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Version \(draft.version)")
                        .font(.caption.weight(.semibold))
                    Text("Modifiée à \(draft.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("Enregistrer") { model.saveTranscript() }
                    .buttonStyle(.bordered)
                Button("Régénérer les documents") { model.requestDocumentRegeneration() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Rechercher dans la transcription", text: $model.transcriptSearch)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(ScribDesign.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(ScribDesign.border) }
            .frame(maxWidth: 360)

            Picker("Afficher", selection: $model.transcriptFilter) {
                ForEach(TranscriptPassageFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 330)

            Spacer()
            if let draft = model.transcriptDraft {
                Label("\(draft.passages.count) passages", systemImage: "text.quote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LocalTranscriptionExportMenu(model: model)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 18)
    }

    private var transcriptContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if model.filteredTranscriptPassages.isEmpty {
                    ContentUnavailableView.search(text: model.transcriptSearch)
                        .padding(.top, 80)
                } else {
                    ForEach(model.filteredTranscriptPassages) { passage in
                        TranscriptPassageEditor(
                            passage: passage,
                            text: model.transcriptTextBinding(for: passage.id),
                            toggleFlag: { model.toggleTranscriptFlag($0, passageID: passage.id) },
                            playAudio: { model.jumpToAudio(at: $0) },
                            formatTimestamp: model.formatTimestamp
                        )
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .frame(maxWidth: 920)
        }
    }
}

private struct TranscriptPassageEditor: View {
    let passage: TranscriptPassage
    @Binding var text: String
    let toggleFlag: (TranscriptPassageFlag) -> Void
    let playAudio: (TimeInterval) -> Void
    let formatTimestamp: (TimeInterval) -> String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 7) {
                Image(systemName: passage.speaker.localizedCaseInsensitiveContains("enseignant") ? "person.fill" : "person.2.fill")
                    .foregroundStyle(ScribDesign.accent)
                    .frame(width: 38, height: 38)
                    .background(ScribDesign.accent.opacity(0.09), in: Circle())
                Button {
                    playAudio(passage.startTime)
                } label: {
                    Label(formatTimestamp(passage.startTime), systemImage: "play.fill")
                }
                .buttonStyle(.plain)
                .font(.caption.monospacedDigit())
                .foregroundStyle(ScribDesign.accent)
                .help("Retrouver ce passage dans l’audio local")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(passage.speaker)
                        .font(.headline)
                    Spacer()
                    ForEach(TranscriptPassageFlag.allCases, id: \.self) { flag in
                        flagButton(flag)
                    }
                }
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 58)
                    .padding(9)
                    .background(flagBackground, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(flagBorder) }
            }
        }
        .scribCard(padding: 18)
    }

    private func flagButton(_ flag: TranscriptPassageFlag) -> some View {
        let active = passage.flags.contains(flag)
        let color: Color = flag == .uncertainty ? .orange : .red
        return Button {
            toggleFlag(flag)
        } label: {
            Label(flag.displayName, systemImage: active ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(active ? color : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(active ? color.opacity(0.09) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var flagBackground: Color {
        if passage.flags.contains(.medicalImportance) { return .red.opacity(0.045) }
        if passage.flags.contains(.uncertainty) { return .orange.opacity(0.055) }
        return ScribDesign.canvas.opacity(0.6)
    }

    private var flagBorder: Color {
        if passage.flags.contains(.medicalImportance) { return .red.opacity(0.28) }
        if passage.flags.contains(.uncertainty) { return .orange.opacity(0.32) }
        return ScribDesign.border
    }
}

struct SupportDocumentsView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.supportDocuments.isEmpty {
                WorkspaceEmptyState(
                    title: "Aucun document enseignant",
                    message: "Importez le support fourni avant ou après le cours. Scrib conserve une copie locale.",
                    systemImage: "doc.badge.plus",
                    actionTitle: "Importer un document",
                    action: model.importTeacherDocument
                )
            } else {
                documentList
            }
        }
        .background(ScribDesign.canvas)
        .navigationTitle("Documents enseignant")
        .overlay(alignment: .bottomTrailing) { WorkspaceNotice(model: model) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Documents de l’enseignant")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Supports utilisés pour le vocabulaire, le plan et les illustrations du cours.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.importTeacherDocument()
                } label: {
                    Label("Importer", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            HStack(spacing: 8) {
                formatChip("Word", icon: "doc.text")
                formatChip("PDF", icon: "doc.richtext")
                formatChip("PowerPoint", icon: "rectangle.on.rectangle")
                formatChip("Tableur", icon: "tablecells")
                formatChip("Image", icon: "photo")
                Spacer()
                Label("Copie locale · 100 Mo maximum", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
    }

    private var documentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(model.supportDocuments) { document in
                    HStack(spacing: 16) {
                        Image(systemName: documentIcon(document.kind))
                            .font(.title2)
                            .foregroundStyle(ScribDesign.accent)
                            .frame(width: 48, height: 48)
                            .background(ScribDesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(document.originalFileName)
                                .font(.headline)
                            Text("Importé le \(document.importedAt.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: document.byteCount, countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            extractionStatus(for: document)
                        }
                        Spacer()
                        Button("Ouvrir") { model.openSupportDocument(document) }
                            .disabled(document.localURL == nil)
                        Button(role: .destructive) {
                            model.deleteSupportDocument(document)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Supprimer la copie locale")
                    }
                    .scribCard(padding: 18)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .frame(maxWidth: 920)
        }
    }

    private func formatChip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(ScribDesign.surface, in: Capsule())
            .overlay { Capsule().stroke(ScribDesign.border) }
    }

    @ViewBuilder
    private func extractionStatus(for document: SupportDocument) -> some View {
        if let extraction = document.extraction {
            let itemCount = extraction.textElements.count
            let details = [
                itemCount > 0 ? "\(itemCount) élément(s)" : nil,
                !extraction.tables.isEmpty ? "\(extraction.tables.count) tableau(x)" : nil,
                !extraction.pages.isEmpty ? "\(extraction.pages.count) page(s)" : nil,
                extraction.imageCount > 0 ? "\(extraction.imageCount) image(s)" : nil
            ].compactMap { $0 }.joined(separator: " · ")
            Label(
                details.isEmpty ? "Extraction terminée" : "Extrait : \(details)",
                systemImage: extraction.warnings.isEmpty
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(extraction.warnings.isEmpty ? ScribDesign.success : .orange)
            if let warning = extraction.warnings.first {
                Text(warning.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let failure = document.extractionFailure {
            Label(failure, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Label(
                "Copie locale conservée · extraction non requise",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(ScribDesign.success)
        }
    }

    private func documentIcon(_ kind: SupportDocumentKind) -> String {
        switch kind {
        case .word: "doc.text.fill"
        case .pdf: "doc.richtext.fill"
        case .presentation: "rectangle.on.rectangle.angled"
        case .spreadsheet: "tablecells.fill"
        case .image: "photo.fill"
        }
    }
}

struct PrivacyReviewView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.transcriptDraft == nil {
                WorkspaceEmptyState(
                    title: "Aucun texte à vérifier",
                    message: "La vérification locale sera disponible dès qu’une transcription aura été produite.",
                    systemImage: "hand.raised.fill"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        privacyStatusCard
                        if !model.privacyFindings.isEmpty {
                            findingsCard
                            decisionCard
                        }
                        explanationCard
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 900, alignment: .leading)
                }
            }
        }
        .background(ScribDesign.canvas)
        .navigationTitle("Confidentialité")
        .overlay(alignment: .bottomTrailing) { WorkspaceNotice(model: model) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Vérification de confidentialité")
                    .font(.system(size: 28, weight: .semibold))
                Text("Scrib analyse la transcription localement avant tout envoi de texte.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("Analyse locale", systemImage: "lock.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ScribDesign.success)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(ScribDesign.success.opacity(0.09), in: Capsule())
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
    }

    private var privacyStatusCard: some View {
        let safe = model.privacyFindings.isEmpty
        let approved = model.isPrivacyApproved
        let color: Color = approved ? ScribDesign.success : .orange
        return HStack(spacing: 16) {
            Image(systemName: approved ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 28))
                .foregroundStyle(color)
                .frame(width: 52, height: 52)
                .background(color.opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle(safe: safe, approved: approved))
                    .font(.title3.weight(.semibold))
                Text(statusMessage(safe: safe, approved: approved))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(approved ? "AUTORISÉ" : "BLOQUÉ")
                .font(.caption.bold())
                .foregroundStyle(color)
        }
        .scribCard()
    }

    private var findingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScribSectionHeading(
                "Éléments potentiellement identifiants",
                subtitle: "Les valeurs détectées restent masquées dans cet écran.",
                icon: "eye.slash.fill"
            )
            ForEach(model.privacyFindings) { finding in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: categoryIcon(finding.category))
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(categoryName(finding.category))
                            .font(.headline)
                        Text(finding.redactedPreview)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(12)
                .background(.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .scribCard()
    }

    private var decisionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Décision manuelle")
                .font(.headline)
            Text("Vérifie la transcription avant d’autoriser cette version exacte. La moindre correction annulera automatiquement l’autorisation.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Corriger la transcription") { model.rejectPrivacyReview() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("J’ai vérifié, autoriser cette version") { model.approvePrivacyReview() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isPrivacyApproved)
            }
        }
        .scribCard()
    }

    private var explanationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(ScribDesign.accent)
            Text("Ce contrôle réduit le risque mais ne garantit pas qu’aucune donnée sensible ne soit présente. L’audio ne quitte jamais le Mac et les aperçus détectés ne sont pas inscrits dans les journaux.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(ScribDesign.mutedSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusTitle(safe: Bool, approved: Bool) -> String {
        if safe { return "Aucun identifiant détecté" }
        if approved { return "Vérification manuelle enregistrée" }
        return "Envoi de texte bloqué"
    }

    private func statusMessage(safe: Bool, approved: Bool) -> String {
        if safe { return "Cette version peut poursuivre le traitement."
        }
        if approved { return "L’autorisation est liée à l’empreinte exacte de cette version."
        }
        return "Une intervention est nécessaire avant tout traitement cloud."
    }

    private func categoryName(_ category: PrivacyFindingCategory) -> String {
        switch category {
        case .emailAddress: "Adresse électronique"
        case .phoneNumber: "Numéro de téléphone"
        case .frenchSocialSecurityNumber: "Numéro de sécurité sociale"
        case .birthDate: "Date de naissance"
        case .postalAddress: "Adresse postale"
        case .patientName: "Nom de patient"
        case .medicalRecordIdentifier: "Identifiant de dossier médical"
        }
    }

    private func categoryIcon(_ category: PrivacyFindingCategory) -> String {
        switch category {
        case .emailAddress: "envelope.fill"
        case .phoneNumber: "phone.fill"
        case .frenchSocialSecurityNumber: "person.text.rectangle.fill"
        case .birthDate: "calendar"
        case .postalAddress: "house.fill"
        case .patientName: "person.fill.questionmark"
        case .medicalRecordIdentifier: "folder.badge.person.crop"
        }
    }
}


private struct WorkspaceEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        title: String,
        message: String,
        systemImage: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(ScribDesign.accent)
                .frame(width: 76, height: 76)
                .background(ScribDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct WorkspaceNotice: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        if let notice = model.workspaceNotice {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ScribDesign.success)
                Text(notice)
                    .font(.caption)
                Button {
                    model.workspaceNotice = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThickMaterial, in: Capsule())
            .overlay { Capsule().stroke(ScribDesign.border) }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            .padding(22)
        }
    }
}
