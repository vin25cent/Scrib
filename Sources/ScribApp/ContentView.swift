import ScribApplication
import ScribDomain
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                brandHeader
                List(selection: $model.selectedSection) {
                    Section("COURS") {
                        navigationRow(.newCourse)
                        navigationRow(.segments)
                        navigationRow(.localTranscription)
                        navigationRow(.queue)
                    }
                    Section("CONTENU") {
                        navigationRow(.transcript)
                        navigationRow(.supports)
                        navigationRow(.privacy)
                    }
                    Section("APPLICATION") {
                        navigationRow(.settings)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .tint(ScribDesign.accent)
                storageSummary
            }
            .background(ScribDesign.sidebar)
            .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 300)
        } detail: {
            VStack(spacing: 0) {
                switch model.selectedSection ?? .newCourse {
                case .newCourse:
                    NewCourseView(model: model)
                case .segments:
                    SegmentsView(model: model)
                case .localTranscription:
                    LocalTranscriptionView(model: model)
                case .queue:
                    ProcessingTrackingView(model: model)
                case .transcript:
                    TranscriptEditorView(model: model)
                case .supports:
                    SupportDocumentsView(model: model)
                case .privacy:
                    PrivacyReviewView(model: model)
                case .settings:
                    TeacherSettingsView(model: model)
                }
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
            await model.prepareProcessingTracking()
        }
        .tint(ScribDesign.accent)
    }

    private func navigationRow(_ section: RecordingViewModel.Section) -> some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 20)
            Text(section.rawValue)
                .font(.body.weight(section == model.selectedSection ? .semibold : .regular))
            Spacer()
            if section == .queue, model.trackingSummary.attentionCount > 0 {
                Text("\(model.trackingSummary.attentionCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(ScribDesign.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ScribDesign.accent.opacity(0.1), in: Capsule())
            }
        }
        .padding(.vertical, 5)
        .tag(section)
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Text("S")
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: [ScribDesign.accent, Color(red: 0.43, green: 0.52, blue: 1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 11)
                )
            Text("Scrib")
                .font(.title2.weight(.bold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var storageSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Stockage local", systemImage: "internaldrive")
                Spacer()
                Circle()
                    .fill(ScribDesign.success)
                    .frame(width: 7, height: 7)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let capacity = model.lastAvailableCapacity {
                Text("\(model.formatBytes(capacity)) disponibles")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Vérifié au premier enregistrement")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        .padding(14)
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
            .padding(.horizontal, 44)
            .padding(.vertical, 36)
            .frame(maxWidth: 1_180, alignment: .leading)
        }
        .background(ScribDesign.canvas)
        .navigationTitle("Nouveau cours")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nouveau cours")
                    .font(.system(size: 34, weight: .semibold))
                Text("Renseignez les informations avant de lancer l’enregistrement.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(ScribDesign.success)
                    .frame(width: 8, height: 8)
                Text(model.snapshot.activeInputName)
                    .lineLimit(1)
            }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(ScribDesign.accent.opacity(0.08), in: Capsule())
                .foregroundStyle(ScribDesign.accentDark)
        }
    }

    private var courseForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScribSectionHeading(
                "Informations du cours",
                subtitle: "Tous les champs sont obligatoires.",
                icon: "book.closed.fill"
            )

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
            .controlSize(.large)

            HStack {
                Label(
                    "Environ \(model.formatBytes(model.estimatedAudioSize)) avec marge de sécurité",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(ScribDesign.success)
                Spacer()
                Label("Sauvegarde toutes les 10 minutes", systemImage: "arrow.clockwise")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .scribCard(padding: 24)
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
        HStack(spacing: 18) {
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
        .padding(4)
        .scribCard(padding: 18)
    }

    private var statusIcon: some View {
        Image(systemName: model.recordingWorkflowState == .error ? "exclamationmark.triangle.fill" : model.isStartingRecording || model.isStoppingRecording ? "hourglass.circle" : model.isRecording ? "record.circle.fill" : model.isPaused ? "pause.circle.fill" : "waveform.circle")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(model.isRecording ? .red : ScribDesign.accent)
            .frame(width: 48, height: 48)
            .background(
                (model.isRecording ? Color.red : ScribDesign.accent).opacity(0.09),
                in: Circle()
            )
    }

    private var statusTitle: String {
        if model.recordingWorkflowState == .error { return "Erreur d’enregistrement" }
        if model.isStartingRecording { return "Démarrage de l’enregistrement…" }
        if model.isStoppingRecording { return "Finalisation de l’enregistrement…" }
        if model.isRecording { return "Enregistrement — \(model.formattedElapsed)" }
        if model.isPaused { return "En pause — \(model.formattedElapsed)" }
        if model.snapshot.state == .finished { return "Enregistrement terminé" }
        return "Prêt à enregistrer"
    }

    private var statusSubtitle: String {
        if model.recordingWorkflowState == .error {
            return model.errorMessage ?? "L’enregistrement nécessite votre attention."
        }
        if model.isStartingRecording {
            return "Vérification du stockage et de l’autorisation microphone."
        }
        if model.isStoppingRecording {
            return "Finalisation du segment et sécurisation du manifeste."
        }
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
        if model.isStartingRecording {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Button("Annuler") { model.stop() }
            }
        } else if model.isStoppingRecording {
            ProgressView()
                .controlSize(.small)
        } else if model.isRecording {
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
                .padding(.horizontal, 4)
                .disabled(!model.canStart)
        }
    }
}

private struct SegmentsView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScribPageHeader(
                title: "Segments audio",
                subtitle: "Chaque partie finalisée reste disponible localement.",
                icon: "waveform"
            )
            if model.snapshot.segments.isEmpty {
                PlaceholderView(
                    title: "Aucun segment",
                    message: "Les segments finalisés apparaîtront ici après une pause ou à la fin du cours.",
                    systemImage: "waveform"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.snapshot.segments) { segment in
                    HStack(spacing: 14) {
                        Image(systemName: "waveform")
                            .foregroundStyle(ScribDesign.accent)
                            .frame(width: 38, height: 38)
                            .background(ScribDesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Segment \(segment.sequence)")
                                .font(.headline)
                            Text(segment.fileURL.lastPathComponent)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("\(Int(segment.duration)) s · \(model.formatBytes(segment.byteCount))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ScribDesign.success)
                    }
                    .padding(.vertical, 7)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(ScribDesign.canvas)
        .navigationTitle("Segments")
    }
}


private struct ProcessingTrackingView: View {
    @ObservedObject var model: RecordingViewModel

    var body: some View {
        VStack(spacing: 0) {
            dashboardHeader
            if model.processingJobs.isEmpty {
                PlaceholderView(
                    title: "Aucune activité à suivre",
                    message: "Les enregistrements et transcriptions locales réellement exécutés par Scrib apparaîtront ici.",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                HSplitView {
                    courseList
                        .frame(minWidth: 330, idealWidth: 390, maxWidth: 470)
                    courseDetail
                        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(ScribDesign.canvas)
        .navigationTitle("Suivi des cours")
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Suivi des cours")
                        .font(.title2.weight(.semibold))
                    Text("Ce suivi reflète les activités réellement exécutées ; il ne lance aucun traitement.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.reloadProcessingTracking() }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
            }

            HStack(spacing: 12) {
                metricCard("Total", value: model.trackingSummary.totalCount, icon: "books.vertical", color: ScribDesign.accent)
                metricCard("En cours", value: model.trackingSummary.activeCount, icon: "clock.fill", color: ScribDesign.accentDark)
                metricCard("Suspendus", value: model.trackingSummary.suspendedCount, icon: "pause.circle.fill", color: .orange)
                metricCard("Erreurs", value: model.trackingSummary.failedCount, icon: "exclamationmark.triangle.fill", color: .red)
                metricCard("Terminés", value: model.trackingSummary.completedCount, icon: "checkmark.circle.fill", color: .green)
            }

            Picker("Filtre", selection: $model.trackingFilter) {
                ForEach(CourseTrackingFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
        }
        .padding(20)
        .background(ScribDesign.canvas)
    }

    private func metricCard(_ title: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(ScribDesign.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(ScribDesign.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var courseList: some View {
        if model.filteredProcessingJobs.isEmpty {
            PlaceholderView(
                title: "Aucun résultat",
                message: "Aucun cours ne correspond à ce filtre.",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        } else {
            List(selection: $model.selectedProcessingJobID) {
                ForEach(model.filteredProcessingJobs) { job in
                    CourseTrackingRow(job: job)
                        .tag(job.id)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var courseDetail: some View {
        if let job = model.selectedProcessingJob {
            CourseTrackingDetail(
                job: job,
                refresh: { Task { await model.reloadProcessingTracking() } },
                openInTranscription: model.openSelectedCourseInLocalTranscription)
        } else {
            PlaceholderView(
                title: "Sélectionnez un cours",
                message: "Le détail de l’activité suivie apparaîtra ici.",
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }

}

private struct CourseTrackingRow: View {
    let job: ProcessingJob

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text(job.courseTitle.isEmpty ? "Cours sans titre" : job.courseTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text(job.teachingUnit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let progress = job.progress {
                    ProgressView(value: progress)
                        .tint(statusColor)
                }
                HStack {
                    Text("\(job.activity.displayName) · \(job.status.displayName)")
                    Spacer()
                    if let progress = job.progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(job.courseDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
    }

    private var statusIcon: String {
        switch job.status {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .suspended: "pause.circle.fill"
        case .processing: "gearshape.2.fill"
        case .pending: "clock.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: .green
        case .failed: .red
        case .suspended: .orange
        default: .blue
        }
    }
}

private struct CourseTrackingDetail: View {
    let job: ProcessingJob
    let refresh: () -> Void
    let openInTranscription: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailHeader
                progressCard
                if job.suspensionReason != nil || job.lastError != nil {
                    attentionCard
                }
                informationCard
            }
            .padding(28)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .background(ScribDesign.canvas)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(job.courseTitle.isEmpty ? "Cours sans titre" : job.courseTitle)
                        .font(.largeTitle.weight(.semibold))
                    Text(job.teachingUnit)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    statusBadge
                    Button("Ouvrir dans Transcription locale", action: openInTranscription)
                        .buttonStyle(.borderedProminent)
                }
            }
            HStack(spacing: 18) {
                Label(job.courseDate.formatted(date: .long, time: .omitted), systemImage: "calendar")
                Label("Mis à jour \(job.updatedAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusBadge: some View {
        Text(job.status.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScribSectionHeading("Activité suivie", icon: "chart.bar.fill")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(job.activity.displayName)
                        .font(.headline)
                    Spacer()
                    if let progress = job.progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.headline.monospacedDigit())
                    }
                }
                if let progress = job.progress {
                    ProgressView(value: progress)
                        .tint(statusColor)
                }
                HStack {
                    Text(progressDescription)
                    Spacer()
                    Button("Actualiser", action: refresh)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .scribCard()
    }

    private var attentionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScribSectionHeading("Attention requise", icon: "exclamationmark.triangle.fill")
            VStack(alignment: .leading, spacing: 10) {
                if let reason = job.suspensionReason {
                    Label(reason, systemImage: "pause.circle.fill")
                        .foregroundStyle(.orange)
                }
                if let error = job.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scribCard()
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScribSectionHeading("Informations", icon: "info.circle.fill")
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                infoRow("Créé", value: job.createdAt.formatted(date: .abbreviated, time: .shortened))
                infoRow("Dernière mise à jour", value: job.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .scribCard()
    }

    private func infoRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private var progressDescription: String {
        switch job.status {
        case .pending: "Activité demandée"
        case .processing: "Activité en cours"
        case .suspended: "Activité suspendue"
        case .completed: "Activité terminée"
        case .failed: "L’activité a échoué"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: .green
        case .failed: .red
        case .suspended: .orange
        default: .blue
        }
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
