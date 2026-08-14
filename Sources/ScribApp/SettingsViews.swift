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
