import SwiftUI

struct AITrialSettingsCard: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScribSectionHeading(
                "Intelligence artificielle",
                subtitle: "Modèles, budget et accès aux fournisseurs configurés localement.",
                icon: "sparkles"
            )
            modelPicker
            budgetField
            if model.selectedAIModelProfile.isLive {
                Divider()
                APIKeySettings(model: model)
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

}
