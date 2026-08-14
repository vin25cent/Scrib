import ScribApplication
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
            dashboardHeader
            if model.processingJobs.isEmpty {
                PlaceholderView(
                    title: "Aucun cours à suivre",
                    message: "Les cours terminés apparaîtront ici avec leur progression et leur dernier checkpoint valide.",
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
        .navigationTitle("Suivi des cours")
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Suivi des cours")
                        .font(.title2.weight(.semibold))
                    Text("Visualisez chaque traitement depuis l’enregistrement jusqu’aux documents finaux.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.reloadQueue() }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
            }

            HStack(spacing: 12) {
                metricCard("Total", value: model.trackingSummary.totalCount, icon: "books.vertical", color: .blue)
                metricCard("En cours", value: model.trackingSummary.activeCount, icon: "clock.fill", color: .indigo)
                metricCard("À vérifier", value: model.trackingSummary.attentionCount, icon: "exclamationmark.triangle.fill", color: .orange)
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
        .background(Color(nsColor: .windowBackgroundColor))
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
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
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
                timeline: model.trackingTimeline(for: job),
                retry: { model.retry(job) },
                refresh: { Task { await model.reloadQueue() } }
            )
        } else {
            PlaceholderView(
                title: "Sélectionnez un cours",
                message: "Le détail de son traitement apparaîtra ici.",
                systemImage: "doc.text.magnifyingglass"
            )
        }
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
                Text("Conditions réunies")
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
                ProgressView(value: job.progress)
                    .tint(statusColor)
                HStack {
                    Text(job.status.displayName)
                    Spacer()
                    Text(job.progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
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
        case .needsAttention: "exclamationmark.triangle.fill"
        case .suspended: "pause.circle.fill"
        case .processing: "gearshape.2.fill"
        case .recording: "record.circle.fill"
        default: "clock.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: .green
        case .needsAttention: .red
        case .suspended: .orange
        case .recording: .red
        default: .blue
        }
    }
}

private struct CourseTrackingDetail: View {
    let job: ProcessingJob
    let timeline: [CourseTrackingStageItem]
    let retry: () -> Void
    let refresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailHeader
                progressCard
                if !job.suspensionReasons.isEmpty || job.lastError != nil {
                    attentionCard
                }
                timelineCard
                informationCard
            }
            .padding(28)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
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
                statusBadge
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
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(job.stage?.displayName ?? progressDescription)
                        .font(.headline)
                    Spacer()
                    Text(job.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.headline.monospacedDigit())
                }
                ProgressView(value: job.progress)
                    .tint(statusColor)
                HStack {
                    Text(progressDescription)
                    Spacer()
                    Button("Actualiser", action: refresh)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(8)
        } label: {
            Label("Progression globale", systemImage: "chart.bar.fill")
                .font(.headline)
        }
    }

    private var attentionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(job.suspensionReasons, id: \.self) { reason in
                    Label(reason.displayName, systemImage: "pause.circle.fill")
                        .foregroundStyle(.orange)
                }
                if let error = job.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if job.status == .needsAttention || job.status == .suspended {
                    Button("Relancer le traitement", action: retry)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Attention requise", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
        }
    }

    private var timelineCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(timeline.indices, id: \.self) { index in
                    StageTimelineRow(item: timeline[index], isLast: index == timeline.count - 1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        } label: {
            Label("Étapes du traitement", systemImage: "list.bullet.clipboard")
                .font(.headline)
        }
    }

    private var informationCard: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                infoRow("Créé", value: job.createdAt.formatted(date: .abbreviated, time: .shortened))
                infoRow("Tentatives", value: "\(job.attemptCount)")
                infoRow("Checkpoints", value: "\(job.checkpoints.count) sur \(ProcessingStage.allCases.count)")
                if let nextAttemptAt = job.nextAttemptAt {
                    infoRow("Prochaine tentative", value: nextAttemptAt.formatted(date: .omitted, time: .shortened))
                }
            }
            .padding(8)
        } label: {
            Label("Informations", systemImage: "info.circle")
                .font(.headline)
        }
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
        case .completed: "Traitement terminé"
        case .needsAttention: "Une intervention est nécessaire"
        case .suspended: "Traitement suspendu"
        case .queued: "En attente de traitement"
        case .processing: "Traitement en cours"
        default: job.status.displayName
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: .green
        case .needsAttention: .red
        case .suspended: .orange
        case .recording: .red
        default: .blue
        }
    }
}

private struct StageTimelineRow: View {
    let item: CourseTrackingStageItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: 2, height: 34)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.stage.displayName)
                    .font(.headline)
                Text(stateDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 3)
            Spacer()
        }
    }

    private var icon: String {
        switch item.state {
        case .completed: "checkmark"
        case .current: "arrow.right"
        case .blocked: "pause.fill"
        case .pending: "circle"
        }
    }

    private var color: Color {
        switch item.state {
        case .completed: .green
        case .current: .blue
        case .blocked: .orange
        case .pending: .secondary
        }
    }

    private var lineColor: Color {
        if case .completed = item.state { return .green.opacity(0.45) }
        return .secondary.opacity(0.2)
    }

    private var stateDescription: String {
        switch item.state {
        case let .completed(date): "Terminé le \(date.formatted(date: .abbreviated, time: .shortened))"
        case .current: "Étape actuelle"
        case .blocked: "En attente de reprise"
        case .pending: "À venir"
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
