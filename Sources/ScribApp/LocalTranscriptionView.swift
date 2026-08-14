import Foundation
import ScribDomain
import SwiftUI

struct LocalTranscriptionView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScribPageHeader(
                    title: "Transcription locale expérimentale",
                    subtitle: "WhisperKit est intégré pour le benchmark alpha. Il ne constitue pas encore le choix définitif de Scrib.",
                    icon: "waveform.badge.magnifyingglass"
                )
                LocalTranscriptionEngineCard()
                LocalTranscriptionModelCard(model: model)
                LocalTranscriptionAudioCard(model: model)
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
            Text("ALPHA / BENCHMARK")
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
                Button("Transcrire localement") { model.startLocalTranscription() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canStartLocalTranscription)
            }
            Spacer()
            availabilityHint
        }
    }

    @ViewBuilder
    private var availabilityHint: some View {
        if model.capturedSegments.isEmpty {
            Text("Enregistrez puis arrêtez un cours pour activer la transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            HStack(spacing: 24) {
                LocalTranscriptionMetric(title: "Modèle", value: result.modelID.rawValue)
                LocalTranscriptionMetric(
                    title: "Traitement",
                    value: model.formatTimestamp(result.metrics.processingDurationSeconds)
                )
                LocalTranscriptionMetric(title: "Facteur temps réel", value: realtimeFactorText)
                LocalTranscriptionMetric(title: "Passages", value: "\(result.passages.count)")
                Spacer()
            }
            if !result.plainText.isEmpty {
                Text(result.plainText)
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
        }
        .scribCard()
    }

    private var realtimeFactorText: String {
        guard let value = result.metrics.realtimeFactor else { return "Non mesuré" }
        return String(format: "%.2f×", value)
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
