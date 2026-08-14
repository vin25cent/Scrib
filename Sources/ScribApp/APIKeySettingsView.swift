import Foundation
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
                .foregroundStyle(keyStatusColor)
                Spacer()
                if model.aiHasStoredKey {
                    Button("Supprimer", role: .destructive) { model.deleteAIAPIKey() }
                }
            }
            SecureField("Coller une nouvelle clé API", text: keyDraftBinding)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Enregistrer dans le Trousseau") { model.saveAIAPIKey() }
                    .disabled(isKeyDraftEmpty)
                Spacer()
                Toggle(
                    "Autoriser les appels payants",
                    isOn: paidCallsBinding
                )
                .toggleStyle(.switch)
                .disabled(!model.aiHasStoredKey)
            }
            Text("La clé ne quitte pas le Trousseau, sauf pour authentifier une requête vers api.openai.com. Aucun appel n’est lancé automatiquement.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var keyStatusColor: Color {
        model.aiHasStoredKey ? ScribDesign.success : Color.secondary
    }

    private var isKeyDraftEmpty: Bool {
        model.aiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var keyDraftBinding: Binding<String> {
        Binding(
            get: { model.aiAPIKeyDraft },
            set: { model.aiAPIKeyDraft = $0 }
        )
    }

    private var paidCallsBinding: Binding<Bool> {
        Binding(
            get: { model.aiPreferences.liveRequestsEnabled },
            set: { model.setAILiveRequestsEnabled($0) }
        )
    }
}
