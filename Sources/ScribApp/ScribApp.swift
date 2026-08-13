import AppKit
import SwiftUI

@main
struct ScribDesktopApp: App {
    var body: some Scene {
        WindowGroup("Scrib") {
            NewCourseView()
                .frame(minWidth: 920, minHeight: 620)
        }

        MenuBarExtra("Scrib", systemImage: "waveform") {
            Text("Scrib est prêt")
            Divider()
            Button("Quitter Scrib") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private struct NewCourseView: View {
    @State private var semester = "Semestre 1"
    @State private var teachingUnit = "UE 2.1 — Biologie fondamentale"
    @State private var title = ""
    @State private var teacher = ""
    @State private var expectedDuration = "2 heures"

    var body: some View {
        NavigationSplitView {
            List {
                Section("Cours") {
                    Label("Nouveau cours", systemImage: "plus.circle")
                    Label("Segments", systemImage: "rectangle.split.2x1")
                    Label("File d’attente", systemImage: "arrow.right")
                }
                Section("Application") {
                    Label("Réglages", systemImage: "gearshape")
                }
            }
            .navigationTitle("Scrib")
        } detail: {
            Form {
                Section("Informations du cours") {
                    TextField("Semestre", text: $semester)
                    TextField("Unité d’enseignement", text: $teachingUnit)
                    TextField("Titre du cours", text: $title)
                    TextField("Enseignant", text: $teacher)
                    TextField("Durée prévue", text: $expectedDuration)
                }

                Section {
                    Button("Démarrer l’enregistrement") {}
                        .buttonStyle(.borderedProminent)
                        .disabled(title.isEmpty || teacher.isEmpty)
                } footer: {
                    Text("Le moteur audio sera branché lors du prototype dédié.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Nouveau cours")
        }
    }
}
