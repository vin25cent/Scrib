import SwiftUI

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
