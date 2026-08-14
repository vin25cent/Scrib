import SwiftUI

struct AITrialSettingsCard: View {
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
        Picker("Modèle", selection: selectedModelBinding) {
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
                value: trialBudgetBinding,
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
            trialActionControl
        }
    }

    @ViewBuilder
    private var trialActionControl: some View {
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

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { model.aiPreferences.selectedModelProfileID },
            set: { model.selectAIModel($0) }
        )
    }

    private var trialBudgetBinding: Binding<Double> {
        Binding(
            get: { model.aiPreferences.trialBudgetUSD },
            set: { model.setAITrialBudget($0) }
        )
    }

    private var trialStatus: String {
        if !model.isDemoMode { return "Charge d’abord le jeu fictif hors ligne." }
        if !model.isPrivacyApproved { return "La revue locale doit être approuvée avant tout adaptateur." }
        if model.selectedAIModelProfile.isLive && !model.aiHasStoredKey { return "Ajoute une clé API pour ce fournisseur." }
        if model.selectedAIModelProfile.isLive && !model.aiPreferences.liveRequestsEnabled { return "Active explicitement les appels payants." }
        return "Prêt : le JSON sera validé avant tout rendu Word."
    }
}
