import ScribApplication
import ScribDomain
import SwiftUI

struct APIKeySettings: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    model.aiHasStoredKey ? "Clé présente dans le Trousseau" : "Aucune clé enregistrée",
                    systemImage: model.aiHasStoredKey ? "key.fill" : "key"
                )
                .foregroundStyle(model.aiHasStoredKey ? ScribDesign.success : .secondary)
                Spacer()
                if model.aiHasStoredKey {
                    Button("Supprimer", role: .destructive) { model.deleteAIAPIKey() }
                }
            }
            SecureField("Coller une nouvelle clé API", text: $model.aiAPIKeyDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Enregistrer dans le Trousseau") { model.saveAIAPIKey() }
                    .disabled(model.aiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Toggle(
                    "Autoriser les appels payants",
                    isOn: Binding(
                        get: { model.aiPreferences.liveRequestsEnabled },
                        set: model.setAILiveRequestsEnabled
                    )
                )
                .toggleStyle(.switch)
                .disabled(!model.aiHasStoredKey)
            }
            Text("La clé ne quitte pas le Trousseau, sauf pour authentifier une requête vers api.openai.com. Aucun appel n’est lancé automatiquement.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct TrialMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(ScribDesign.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ScribDesign.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct LastTrialSummary: View {
    @ObservedObject var model: RecordingViewModel
    let run: AIGenerationRun

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(ScribDesign.success)
            VStack(alignment: .leading, spacing: 3) {
                Text("Dernier essai validé — \(run.modelProfile.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text("\(run.usage.inputTokens) jetons entrants · \(run.usage.outputTokens) sortants · \(model.formatUSDCost(run.usage.estimatedCostUSD))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(ScribDesign.success.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TrialComparisonList: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        Text("Comparatif des essais").font(.headline)
        ForEach(Array(model.aiGenerationRuns.prefix(8))) { run in
            HStack(spacing: 12) {
                Image(systemName: run.usage.isSimulated ? "desktopcomputer" : "cloud.fill")
                    .foregroundStyle(ScribDesign.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.modelProfile.displayName).font(.subheadline.weight(.semibold))
                    Text("\(run.sectionCount) sections · \(run.blockCount) blocs · \(run.durationMilliseconds) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(model.formatUSDCost(run.usage.estimatedCostUSD)).font(.subheadline.weight(.semibold))
                    Text(run.completedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if run.id != model.aiGenerationRuns.prefix(8).last?.id { Divider() }
        }
    }
}

struct TeacherPermissionsSettingsCard: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScribSectionHeading(
                "Enseignants",
                subtitle: "Autorisations d’enregistrement mémorisées localement.",
                icon: "person.crop.circle.badge.checkmark"
            )
            if model.savedTeachers.isEmpty {
                Text("Aucun enseignant enregistré pour le moment.").foregroundStyle(.secondary)
            } else {
                ForEach(model.savedTeachers) { teacher in
                    HStack(spacing: 14) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(ScribDesign.accent)
                            .frame(width: 38, height: 38)
                            .background(ScribDesign.accent.opacity(0.09), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(teacher.name).font(.headline)
                            if let date = teacher.recordingAuthorizationConfirmedAt {
                                Text("Autorisation confirmée le \(date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Label("Autorisé", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ScribDesign.success)
                    }
                    if teacher.id != model.savedTeachers.last?.id { Divider() }
                }
            }
        }
        .scribCard()
    }
}
