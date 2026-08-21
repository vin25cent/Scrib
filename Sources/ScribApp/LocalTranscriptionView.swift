import AppKit
import Foundation
import ScribDomain
import SwiftUI
import UniformTypeIdentifiers

struct LocalTranscriptionView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScribPageHeader(
                    title: "Transcription locale",
                    subtitle: "Small est la baseline recommandée. Medium reste un candidat qualité à confirmer par benchmark sur votre Mac.",
                    icon: "waveform.badge.magnifyingglass"
                )
                if model.activeCourseID != nil {
                    ActiveTranscriptionCourseCard(model: model)
                }
                LocalTranscriptionEngineCard()
                LocalTranscriptionModelCard(model: model)
                LocalTranscriptionAudioCard(model: model)
                if model.hasPendingTranscriptionReplacement {
                    PendingTranscriptionReplacementCard(model: model)
                }
                if let result = model.lastLocalTranscriptionResult {
                    LocalTranscriptionResultCard(model: model, result: result)
                }
                LocalTranscriptionPrivacyNote()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 34)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(ScribDesign.canvas)
        .navigationTitle("Transcription locale")
        .overlay(alignment: .bottomTrailing) { WorkspaceNotice(model: model) }
        .task { await model.refreshLocalModelStatus() }
    }
}

private struct ActiveTranscriptionCourseCard: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.title2)
                .foregroundStyle(ScribDesign.accent)
                .frame(width: 48, height: 48)
                .background(ScribDesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.activeCourseTitle ?? "Cours sélectionné")
                    .font(.headline)
                if let unit = model.activeCourseTeachingUnit, !unit.isEmpty {
                    Text(unit).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if let teacher = model.activeCourseTeacherName, !teacher.isEmpty {
                        Label(teacher, systemImage: "person.fill")
                    }
                    if let date = model.activeCourseDate {
                        Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoadingActiveCourse {
                ProgressView().controlSize(.small)
                Text("Chargement…").font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Cours actif", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ScribDesign.success)
            }
        }
        .scribCard()
    }
}

private struct LocalTranscriptionEngineCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "cpu.fill")
                .font(.title2)
                .foregroundStyle(ScribDesign.accent)
                .frame(width: 48, height: 48)
                .background(ScribDesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text("Moteur : WhisperKit 1.0.0")
                    .font(.headline)
                Text("Calcul natif Core ML sur le Mac, sans clé API, serveur, Python, Homebrew ni envoi cloud.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("LOCAL-FIRST")
                .font(.caption2.bold())
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1), in: Capsule())
        }
        .scribCard()
    }
}

private struct LocalTranscriptionModelCard: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScribSectionHeading(
                "Modèle local",
                subtitle: "Le téléchargement ne commence que lorsque vous le demandez.",
                icon: "square.and.arrow.down"
            )
            modelPicker
            modelStatus
            downloadProgress
        }
        .scribCard()
    }

    private var modelPicker: some View {
        Picker(
            "Modèle",
            selection: Binding(
                get: { model.selectedLocalTranscriptionModel },
                set: { model.selectLocalTranscriptionModel($0) }
            )
        ) {
            ForEach(model.localTranscriptionModels) { descriptor in
                Text(descriptor.displayName).tag(descriptor.id)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.isDownloadingTranscriptionModel || model.isLocalTranscriptionRunning)
    }

    private var modelStatus: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(statusTitle).font(.headline)
                Text(model.selectedLocalTranscriptionModelDescriptor.intendedUse)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sizeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let error = model.localModelStatus.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            modelAction
        }
    }

    @ViewBuilder
    private var modelAction: some View {
        switch model.localModelStatus.availability {
        case .available:
            Label("Disponible", systemImage: "checkmark.circle.fill")
                .foregroundStyle(ScribDesign.success)
        case .downloading:
            Button("Annuler") { model.cancelModelDownload() }
                .buttonStyle(.bordered)
        case .notDownloaded, .failed:
            Button("Télécharger") { model.downloadSelectedTranscriptionModel() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var downloadProgress: some View {
        if model.isDownloadingTranscriptionModel {
            ProgressView(value: model.localModelStatus.progress ?? 0)
            Text(progressText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
        switch model.localModelStatus.availability {
        case .notDownloaded: "Non téléchargé"
        case .downloading: "Téléchargement en cours"
        case .available: "Modèle disponible hors ligne"
        case .failed: "Erreur de modèle"
        }
    }

    private var statusIcon: String {
        switch model.localModelStatus.availability {
        case .notDownloaded: "icloud.and.arrow.down"
        case .downloading: "arrow.down.circle"
        case .available: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch model.localModelStatus.availability {
        case .available: ScribDesign.success
        case .failed: .red
        default: ScribDesign.accent
        }
    }

    private var sizeText: String {
        if let installed = model.localModelStatus.installedSizeBytes {
            return "Taille installée : \(model.formatBytes(installed))"
        }
        if let estimated = model.selectedLocalTranscriptionModelDescriptor.estimatedDownloadBytes {
            return "Téléchargement estimé : \(model.formatBytes(estimated))"
        }
        return "La taille exacte sera affichée après téléchargement."
    }

    private var progressText: String {
        let percent = Int((model.localModelStatus.progress ?? 0) * 100)
        return "\(percent) % — une connexion Internet est requise uniquement pour cette étape."
    }
}

private struct LocalTranscriptionAudioCard: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScribSectionHeading(
                "Audio du cours",
                subtitle: "Les segments sont traités dans leur ordre, un par un, en français.",
                icon: "waveform"
            )
            metrics
            progress
            actions
        }
        .scribCard()
    }

    private var metrics: some View {
        HStack(spacing: 24) {
            LocalTranscriptionMetric(title: "Segments", value: "\(model.capturedSegments.count)")
            LocalTranscriptionMetric(title: "Durée audio", value: model.formatTimestamp(model.localAudioDuration))
            LocalTranscriptionMetric(title: "État", value: stateTitle)
            Spacer()
        }
    }

    @ViewBuilder
    private var progress: some View {
        if model.isLocalTranscriptionRunning || model.localTranscriptionProgress.stage == .cancelled {
            ProgressView(value: model.localTranscriptionProgress.fractionCompleted ?? 0)
            HStack {
                Text(model.localTranscriptionProgress.message ?? stateTitle)
                Spacer()
                Text(model.formatTimestamp(model.localTranscriptionProgress.elapsedSeconds))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            if model.isLocalTranscriptionRunning {
                Button("Annuler la transcription", role: .destructive) {
                    model.cancelLocalTranscription()
                }
                .buttonStyle(.bordered)
            } else {
                Button(model.lastLocalTranscriptionResult == nil
                    ? "Transcrire localement"
                    : "Retranscrire l’audio") {
                    if model.lastLocalTranscriptionResult == nil {
                        model.startLocalTranscription()
                    } else {
                        model.retranscribeAudio()
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.lastLocalTranscriptionResult == nil
                        ? !model.canStartLocalTranscription
                        : !model.canRetranscribeAudio)
                if model.lastLocalTranscriptionResult != nil {
                    Text("Utiliser les enregistrements existants")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            availabilityHint
        }
    }

    @ViewBuilder
    private var availabilityHint: some View {
        if model.capturedSegments.isEmpty {
            Text(model.activeCourseCameFromTracking
                ? "Aucun enregistrement n’est disponible pour ce cours."
                : (model.lastLocalTranscriptionResult == nil
                    ? "Enregistrez puis arrêtez un cours pour activer la transcription."
                    : "Aucun enregistrement existant n’est disponible pour ce cours."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let issue = model.existingAudioIssues.first {
            Text(issue.localizedDescription)
                .font(.caption)
                .foregroundStyle(.red)
        } else if model.localModelStatus.availability != .available {
            Text("Téléchargez d’abord le modèle sélectionné.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stateTitle: String {
        switch model.localTranscriptionProgress.stage {
        case .idle: "Prêt"
        case .checkingModel: "Vérification"
        case .loadingModel: "Chargement"
        case .convertingAudio: "Préparation audio"
        case .transcribing: "Transcription"
        case .assembling: "Assemblage"
        case .saving: "Enregistrement"
        case .completed: "Terminé"
        case .cancelled: "Annulé"
        case .failed: "Erreur"
        }
    }
}

private struct PendingTranscriptionReplacementCard: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScribSectionHeading(
                "Nouvelle transcription prête",
                subtitle: "L’ancienne transcription est toujours conservée sur disque.",
                icon: "arrow.triangle.2.circlepath"
            )
            Text("Choisissez la version à conserver. Aucun remplacement n’a lieu avant votre confirmation.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Conserver l’ancienne") { model.keepExistingTranscription() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Remplacer l’ancienne transcription") {
                    model.confirmTranscriptionReplacement()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .scribCard()
    }
}

private struct LocalTranscriptionResultCard: View {
    @ObservedObject var model: RecordingViewModel
    let result: LocalTranscriptionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScribSectionHeading(
                "Dernier résultat brut",
                subtitle: "Persisté localement avant toute génération de cours.",
                icon: "checkmark.seal.fill"
            )
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)],
                alignment: .leading,
                spacing: 14
            ) {
                LocalTranscriptionMetric(title: "Modèle", value: result.modelVariant ?? result.modelID.rawValue)
                LocalTranscriptionMetric(
                    title: "Traitement",
                    value: model.formatTimestamp(result.metrics.processingDurationSeconds)
                )
                LocalTranscriptionMetric(
                    title: "Audio",
                    value: model.formatTimestamp(result.metrics.audioDurationSeconds)
                )
                LocalTranscriptionMetric(title: "Facteur temps réel", value: realtimeFactorText)
                LocalTranscriptionMetric(title: "Passages", value: "\(result.passages.count)")
                let reviewCount = result.passages.filter {
                    !TranscriptionReviewPolicy.reasons(for: $0).isEmpty
                }.count
                if reviewCount > 0 {
                    LocalTranscriptionMetric(title: "À vérifier", value: "\(reviewCount)")
                }
                if let memory = result.metrics.peakResidentMemoryBytes {
                    LocalTranscriptionMetric(title: "Mémoire max approx.", value: model.formatBytes(memory))
                }
            }
            if let settings = result.decodingSettings {
                Text("Décodage : français, température \(settings.temperature, format: .number), timestamps mot, VAD, \(settings.initialPromptUsed ? "contexte actif" : "sans contexte")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !result.userFacingPlainText.isEmpty {
                Text(result.userFacingPlainText)
                    .font(.body)
                    .lineLimit(5)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ScribDesign.canvas.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            }
            Button("Ouvrir dans l’éditeur de transcription") {
                model.openRawTranscriptInEditor()
            }
            .buttonStyle(.borderedProminent)
            LocalTranscriptionExportMenu(model: model)
        }
        .scribCard()
    }

    private var realtimeFactorText: String {
        guard let value = result.metrics.realtimeFactor else { return "Non mesuré" }
        return String(format: "%.2f×", value)
    }

}

struct LocalTranscriptionExportMenu: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        Menu("Exporter la transcription") {
            Button("Format texte (.txt)") {
                export(.plainText)
            }
            Button("Format JSON (.json)") {
                export(.json)
            }
        }
        .menuStyle(.borderedButton)
        .disabled(model.localTranscriptionForExport == nil)
    }

    private func export(_ format: ExportFormat) {
        guard let transcription = model.localTranscriptionForExport else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeFileName(transcription.course.title)) - transcription.\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let data: Data
            switch format {
            case .plainText:
                data = Data(LocalTranscriptionExport.plainText(from: transcription).utf8)
            case .json:
                data = try LocalTranscriptionExport.jsonData(from: transcription)
            }
            try data.write(to: destination, options: .atomic)
            model.workspaceNotice = "Transcription exportée dans \(destination.lastPathComponent)."
        } catch {
            model.errorMessage = "L’export de la transcription a échoué : \(error.localizedDescription)"
        }
    }

    private func safeFileName(_ title: String) -> String {
        title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "-")
    }

    private enum ExportFormat {
        case plainText
        case json

        var fileExtension: String {
            switch self {
            case .plainText: "txt"
            case .json: "json"
            }
        }

        var contentType: UTType {
            switch self {
            case .plainText: .plainText
            case .json: .json
            }
        }
    }
}

private struct LocalTranscriptionPrivacyNote: View {
    var body: some View {
        Label(
            "Cette étape ne déclenche aucun appel IA cloud. La diarisation et la correction LLM sont volontairement absentes.",
            systemImage: "lock.shield.fill"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

private struct LocalTranscriptionMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }
}
