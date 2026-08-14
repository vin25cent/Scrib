import ScribApplication
import ScribDomain
import SwiftUI

struct TeacherSettingsView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScribPageHeader(
                title: "Réglages",
                subtitle: "Configurez l’IA, le budget d’essai et les autorisations d’enregistrement.",
                icon: "gearshape.fill"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AITrialSettingsCard(model: model)
                    TeacherPermissionsSettingsCard(model: model)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .frame(maxWidth: 980)
            }
        }
        .background(ScribDesign.canvas)
        .navigationTitle("Réglages")
        .overlay(alignment: .bottomTrailing) { WorkspaceNotice(model: model) }
    }
}

private struct AITrialSettingsCard: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScribSectionHeading(
                "Intelligence artificielle",
                subtitle: "Simulation gratuite ou essais réels strictement plafonnés.",
                icon: "sparkles"
            )
            modelPicker
            trialMetrics
            budgetField
            if model.selectedAIModelProfile.isLive {
                Divider()
                APIKeySettings(model: model)
            }
            Divider()
            trialAction
            if let run = model.aiLastRun {
                LastTrialSummary(model: model, run: run)
            }
            if !model.aiGenerationRuns.isEmpty {
                Divider()
                TrialComparisonList(model: model)
            }
        }
        .scribCard()
    }

    private var modelPicker: some View {
        Picker(
            "Modèle",
            selection: Binding(
                get: { model.aiPreferences.selectedModelProfileID },
                set: model.selectAIModel
            )
        ) {
            ForEach(model.aiModelProfiles) { profile in
                Text(profile.displayName).tag(profile.id)
            }
        }
    }

    private var trialMetrics: some View {
        HStack(spacing: 14) {
            TrialMetric(title: "Dépensé", value: model.formatUSDCost(model.aiSpentUSD), icon: "dollarsign.circle")
            TrialMetric(title: "Reste", value: model.formatUSDCost(model.aiBudgetRemainingUSD), icon: "gauge.with.dots.needle.33percent")
            TrialMetric(title: "Essais", value: "\(model.aiGenerationRuns.count)", icon: "checklist")
        }
    }

    private var budgetField: some View {
        HStack {
            Text("Plafond total des essais (USD)")
            Spacer()
            TextField(
                "10",
                value: Binding(
                    get: { model.aiPreferences.trialBudgetUSD },
                    set: model.setAITrialBudget
                ),
                format: .number.precision(.fractionLength(0...2))
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
        }
    }

    private var trialAction: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Banc d’essai sur données fictives").font(.headline)
                Text(trialStatus).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isAIGenerationRunning {
                ProgressView().controlSize(.small)
            } else if !model.isDemoMode {
                Button("Charger la démonstration") { model.runAIModelTrial() }
                    .buttonStyle(.bordered)
            } else if !model.isPrivacyApproved {
                Button("Vérifier la confidentialité") { model.selectedSection = .privacy }
                    .buttonStyle(.bordered)
            } else {
                Button("Tester ce modèle") { model.runAIModelTrial() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.aiCanRunTrial)
            }
        }
    }

    private var trialStatus: String {
        if !model.isDemoMode { return "Charge d’abord le jeu fictif hors ligne." }
        if !model.isPrivacyApproved { return "La revue locale doit être approuvée avant tout adaptateur." }
        if model.selectedAIModelProfile.isLive && !model.aiHasStoredKey { return "Ajoute une clé API pour ce fournisseur." }
        if model.selectedAIModelProfile.isLive && !model.aiPreferences.liveRequestsEnabled { return "Active explicitement les appels payants." }
        return "Prêt : le JSON sera validé avant tout rendu Word."
    }
}

private struct APIKeySettings: View {
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

private struct TrialMetric: View {
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

private struct LastTrialSummary: View {
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

private struct TrialComparisonList: View {
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

private struct TeacherPermissionsSettingsCard: View {
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
