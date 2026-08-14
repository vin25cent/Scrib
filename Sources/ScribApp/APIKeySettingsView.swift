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
