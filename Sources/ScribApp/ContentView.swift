import ScribDomain
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedSection) {
                Section("Cours") {
                    navigationRow(.newCourse)
                    navigationRow(.segments)
                    navigationRow(.queue)
                }
                Section("Application") {
                    navigationRow(.settings)
                }
            }
            .navigationTitle("Scrib")
            .safeAreaInset(edge: .bottom) {
                storageSummary
            }
        } detail: {
            switch model.selectedSection ?? .newCourse {
            case .newCourse:
                NewCourseView(model: model)
            case .segments:
                SegmentsView(model: model)
            case .queue:
                ProcessingQueueView(model: model)
            case .settings:
                TeacherSettingsView(model: model)
            }
        }
        .alert("Autorisation d’enregistrer", isPresented: $model.authorizationRequested) {
            Button("Annuler", role: .cancel) { model.cancelAuthorization() }
            Button("Je confirme") { model.confirmAuthorizationAndStart() }
        } message: {
            Text("Confirmez que vous disposez de l’autorisation d’enregistrer un cours de cet enseignant. Cette confirmation ne sera plus demandée pour les prochains cours associés au même nom.")
        }
        .alert(
            "Scrib ne peut pas continuer",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Erreur inconnue")
        }
        .alert("Un enregistrement est actif", isPresented: $model.quitWarningRequested) {
            Button("Continuer l’enregistrement", role: .cancel) {}
            Button("Terminer et quitter", role: .destructive) {
                model.confirmQuitAndStop()
            }
        } message: {
            Text("Quitter maintenant finalisera le segment courant avant de fermer Scrib.")
        }
        .task {
            await model.prepareQueue()
        }
    }

    private func navigationRow(_ section: RecordingViewModel.Section) -> some View {
        Label(section.rawValue, systemImage: section.systemImage)
            .tag(section)
    }

    private var storageSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("Stockage local")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let capacity = model.lastAvailableCapacity {
                Text("\(model.formatBytes(capacity)) disponibles")
                    .font(.headline)
            } else {
                Text("Vérifié au démarrage")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(.bar)
    }
}

private struct NewCourseView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                courseForm
                RecordingControlCard(model: model)
            }
            .padding(36)
            .frame(maxWidth: 1_100, alignment: .leading)
        }
        .navigationTitle("Nouveau cours")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nouveau cours")
                    .font(.largeTitle)
                Text("Renseignez les informations avant de lancer l’enregistrement.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(model.snapshot.activeInputName, systemImage: "mic.fill")
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.blue.opacity(0.1), in: Capsule())
                .foregroundStyle(.blue)
        }
    }

    private var courseForm: some View {
        GroupBox("Informations du cours") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 18) {
                GridRow {
                    field("Semestre") {
                        Picker("Semestre", selection: $model.selectedSemester) {
                            ForEach(Semester.allCases) { semester in
                                Text(semester.displayName).tag(semester)
                            }
                        }
                        .labelsHidden()
                    }
                    field("Unité d’enseignement") {
                        Picker("Unité d’enseignement", selection: $model.selectedTeachingUnit) {
                            ForEach(model.teachingUnits) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .labelsHidden()
                    }
                }

                GridRow {
                    field("Titre du cours") {
                        TextField("La cellule et les tissus", text: $model.title)
                    }
                    .gridCellColumns(2)
                }

                GridRow {
                    field("Enseignant") {
                        HStack {
                            TextField("Nom de l’enseignant", text: $model.teacherName)
                            if !model.savedTeachers.isEmpty {
                                Menu {
                                    ForEach(model.savedTeachers) { teacher in
                                        Button(teacher.name) { model.chooseTeacher(teacher) }
                                    }
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                    }
                    field("Durée prévue") {
                        Picker("Durée prévue", selection: $model.expectedDuration) {
                            ForEach(ExpectedDuration.allCases) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .pickerStyle(.menu)
            .padding(.top, 12)

            HStack {
                Label(
                    "Environ \(model.formatBytes(model.estimatedAudioSize)) avec marge de sécurité",
                    systemImage: "internaldrive"
                )
                Spacer()
                Text("Segments récupérables toutes les 10 minutes")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 16)
        }
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RecordingControlCard: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        GroupBox {
            HStack(spacing: 20) {
                statusIcon
                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if model.hasActiveSession {
                        ProgressView(value: model.snapshot.normalizedLevel)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 300)
                        if model.lowSoundWarning {
                            Label("Niveau sonore très faible", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let incident = model.snapshot.incidentMessage {
                        Text(incident)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                controls
            }
            .padding(8)
        }
    }

    private var statusIcon: some View {
        Image(systemName: model.isRecording ? "record.circle.fill" : model.isPaused ? "pause.circle.fill" : "waveform.circle")
            .font(.system(size: 32))
            .foregroundStyle(model.isRecording ? .red : .blue)
    }

    private var statusTitle: String {
        if model.isRecording { return "Enregistrement — \(model.formattedElapsed)" }
        if model.isPaused { return "En pause — \(model.formattedElapsed)" }
        if model.snapshot.state == .finished { return "Enregistrement terminé" }
        return "Prêt à enregistrer"
    }

    private var statusSubtitle: String {
        if model.hasActiveSession {
            return "\(model.snapshot.segments.count) segment(s) finalisé(s)"
        }
        if model.snapshot.state == .finished {
            return "Les segments sont conservés localement."
        }
        return "Le microphone, l’espace disque et l’autorisation seront vérifiés."
    }

    @ViewBuilder
    private var controls: some View {
        if model.isRecording {
            HStack {
                Button("Pause") { model.pause() }
                Button("Terminer", role: .destructive) { model.stop() }
            }
        } else if model.isPaused {
            HStack {
                Button("Reprendre") { model.resume() }
                    .buttonStyle(.borderedProminent)
                Button("Terminer", role: .destructive) { model.stop() }
            }
        } else {
            Button("Démarrer l’enregistrement") { model.startTapped() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canStart)
        }
    }
}

private struct SegmentsView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        Group {
            if model.snapshot.segments.isEmpty {
                PlaceholderView(
                    title: "Aucun segment",
                    message: "Les segments finalisés apparaîtront ici après une pause ou à la fin du cours.",
                    systemImage: "waveform"
                )
            } else {
                List(model.snapshot.segments) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Segment \(segment.sequence)")
                            .font(.headline)
                        Text(segment.fileURL.lastPathComponent)
                            .foregroundStyle(.secondary)
                        Text("\(Int(segment.duration)) s · \(model.formatBytes(segment.byteCount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Segments")
    }
}

private struct TeacherSettingsView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        Group {
            if model.savedTeachers.isEmpty {
                PlaceholderView(
                    title: "Aucun enseignant enregistré",
                    message: "Un enseignant apparaîtra ici après la première confirmation d’autorisation.",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
            } else {
                List(model.savedTeachers) { teacher in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(teacher.name).font(.headline)
                        if let date = teacher.recordingAuthorizationConfirmedAt {
                            Text("Autorisation confirmée le \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Réglages")
    }
}

private struct ProcessingQueueView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(spacing: 0) {
            conditionBar
            if model.processingJobs.isEmpty {
                PlaceholderView(
                    title: "File vide",
                    message: "Les cours terminés apparaîtront ici et reprendront au dernier checkpoint valide.",
                    systemImage: "checkmark.circle"
                )
            } else {
                List(model.processingJobs) { job in
                    HStack(spacing: 16) {
                        statusIcon(for: job)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(job.courseTitle.isEmpty ? "Cours sans titre" : job.courseTitle)
                                .font(.headline)
                            Text(job.teachingUnit)
                                .foregroundStyle(.secondary)
                            ProgressView(value: job.progress)
                                .frame(maxWidth: 320)
                            HStack {
                                Text(job.status.displayName)
                                if let stage = job.stage {
                                    Text("· \(stage.displayName)")
                                }
                                if !job.suspensionReasons.isEmpty {
                                    Text("· \(job.suspensionReasons.map(\.displayName).joined(separator: ", "))")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let error = job.lastError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        if job.status == .needsAttention {
                            Button("Relancer") { model.retry(job) }
                        }
                    }
                    .padding(.vertical, 7)
                }
            }
        }
        .navigationTitle("File d’attente")
    }

    private var conditionBar: some View {
        HStack(spacing: 18) {
            conditionLabel(
                model.systemConditions.isOnExternalPower,
                ready: "Secteur",
                blocked: "Batterie",
                icon: "powerplug"
            )
            conditionLabel(
                model.systemConditions.isNetworkAvailable,
                ready: "Internet",
                blocked: "Hors ligne",
                icon: "network"
            )
            conditionLabel(
                model.systemConditions.thermalCondition == .nominal
                    || model.systemConditions.thermalCondition == .fair,
                ready: "Température normale",
                blocked: "Température élevée",
                icon: "thermometer.medium"
            )
            conditionLabel(
                model.systemConditions.memoryCondition == .normal,
                ready: "Mémoire disponible",
                blocked: "Pression mémoire",
                icon: "memorychip"
            )
            Spacer()
            if !model.systemConditions.canRunHeavyProcessing {
                Text("Traitement suspendu")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text("Prêt pour les futurs moteurs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func conditionLabel(
        _ isReady: Bool,
        ready: String,
        blocked: String,
        icon: String
    ) -> some View {
        Label(isReady ? ready : blocked, systemImage: icon)
            .font(.caption)
            .foregroundStyle(isReady ? .green : .orange)
    }

    private func statusIcon(for job: ProcessingJob) -> some View {
        let icon: String
        let color: Color
        switch job.status {
        case .completed:
            icon = "checkmark.circle.fill"
            color = .green
        case .needsAttention:
            icon = "exclamationmark.triangle.fill"
            color = .red
        case .suspended:
            icon = "pause.circle.fill"
            color = .orange
        default:
            icon = "clock.fill"
            color = .blue
        }
        return Image(systemName: icon)
            .font(.title2)
            .foregroundStyle(color)
    }
}

private struct PlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(message)
        )
    }
}
