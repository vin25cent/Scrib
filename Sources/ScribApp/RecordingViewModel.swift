import AppKit
import Combine
import Foundation
import ScribApplication
import ScribDomain
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RecordingViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case newCourse = "Nouveau cours"
        case segments = "Segments"
        case localTranscription = "Transcription locale"
        case queue = "Suivi des cours"
        case transcript = "Transcription"
        case supports = "Documents enseignant"
        case privacy = "Confidentialité"
        case demonstration = "Démonstration"
        case settings = "Réglages"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .newCourse: "plus.circle"
            case .segments: "rectangle.split.2x1"
            case .localTranscription: "waveform.badge.magnifyingglass"
            case .queue: "clock.arrow.circlepath"
            case .transcript: "text.alignleft"
            case .supports: "doc.badge.plus"
            case .privacy: "hand.raised.fill"
            case .demonstration: "sparkles.rectangle.stack"
            case .settings: "gearshape"
            }
        }
    }

    @Published var selectedSection: Section? = .newCourse
    @Published var selectedSemester: Semester = .semester1 {
        didSet {
            guard selectedTeachingUnit.semester != selectedSemester else { return }
            selectedTeachingUnit = teachingUnits.first!
        }
    }
    @Published var selectedTeachingUnit: TeachingUnit = TeachingUnitCatalog.units(
        for: .semester1
    ).first!
    @Published var title = ""
    @Published var teacherName = ""
    @Published var expectedDuration: ExpectedDuration = .twoHours
    @Published private(set) var savedTeachers: [Teacher] = []
    @Published private(set) var snapshot = AudioRecorderSnapshot()
    @Published private(set) var currentCourse: Course?
    @Published private(set) var capturedSegments: [RecordingSegment] = []
    @Published private(set) var lastAvailableCapacity: Int64?
    @Published private(set) var lowSoundWarning = false
    @Published private(set) var processingJobs: [ProcessingJob] = []
    @Published var trackingFilter: CourseTrackingFilter = .all {
        didSet { selectFirstVisibleJobIfNeeded() }
    }
    @Published var selectedProcessingJobID: ProcessingJobID?
    @Published var transcriptDraft: TranscriptDraft?
    @Published var transcriptSearch = ""
    @Published var transcriptFilter: TranscriptPassageFilter = .all
    @Published var selectedLocalTranscriptionModel: LocalTranscriptionModelID = .tinyMultilingual
    @Published private(set) var localModelStatus = TranscriptionModelStatus(
        modelID: .tinyMultilingual,
        availability: .notDownloaded
    )
    @Published private(set) var localTranscriptionProgress = LocalTranscriptionProgress(stage: .idle)
    @Published private(set) var lastLocalTranscriptionResult: LocalTranscriptionResult?
    @Published private(set) var isDownloadingTranscriptionModel = false
    @Published private(set) var isLocalTranscriptionRunning = false
    @Published private(set) var supportDocuments: [SupportDocument] = []
    @Published private(set) var privacyReview: PrivacyReview?
    @Published private(set) var isDemoMode = false
    @Published private(set) var selectedDemoAudioURL: URL?
    @Published private(set) var demonstrationPipelineResult: DemonstrationPipelineResult?
    @Published private(set) var isDemonstrationPipelineRunning = false
    @Published private(set) var aiPreferences: AIGenerationPreferences
    @Published var aiAPIKeyDraft = ""
    @Published private(set) var aiHasStoredKey = false
    @Published private(set) var aiGenerationRuns: [AIGenerationRun] = []
    @Published private(set) var aiLastRun: AIGenerationRun?
    @Published private(set) var isAIGenerationRunning = false
    @Published var workspaceNotice: String?
    @Published private(set) var systemConditions = SystemConditionSnapshot(
        isOnExternalPower: false,
        isNetworkAvailable: false,
        thermalCondition: .unknown
    )
    @Published var authorizationRequested = false
    @Published var errorMessage: String?
    @Published var quitWarningRequested = false

    private let recorder: any AudioRecording
    private let fileStore: any CourseFileStoring
    private let teacherStore: any TeacherAuthorizationStoring
    private let queueCoordinator: ProcessingQueueCoordinator
    private let demonstrationPipeline: any DemonstrationPipelineRunning
    private let supportImporter: any SupportDocumentImporting
    private let aiOrchestrator: StructuredGenerationOrchestrator
    private let aiSecretStore: any AISecretStoring
    private let aiPreferencesStore: any AIGenerationPreferencesStoring
    private let transcriptionCoordinator: LocalTranscriptionCoordinator
    private let readinessValidator = RecordingReadinessValidator()
    private let trackingPresenter = CourseTrackingPresenter()
    private let transcriptService = TranscriptWorkspaceService()
    private let privacyDetector = PatientIdentifierDetector()
    private let privacyGate = CloudPrivacyGate()
    private let demonstrationFactory = DemonstrationWorkspaceFactory()
    private var pendingTeacher: Teacher?
    private var pollingTask: Task<Void, Never>?
    private var queuePollingTask: Task<Void, Never>?
    private var lowSoundStartedAt: Date?
    private var systemActivity: NSObjectProtocol?
    private var modelDownloadTask: Task<Void, Never>?
    private var localTranscriptionTask: Task<Void, Never>?
    private var realTranscriptDraft: TranscriptDraft?

    init(
        recorder: any AudioRecording,
        fileStore: any CourseFileStoring,
        teacherStore: any TeacherAuthorizationStoring,
        queueCoordinator: ProcessingQueueCoordinator,
        demonstrationPipeline: any DemonstrationPipelineRunning,
        supportImporter: any SupportDocumentImporting,
        aiOrchestrator: StructuredGenerationOrchestrator,
        aiSecretStore: any AISecretStoring,
        aiPreferencesStore: any AIGenerationPreferencesStoring,
        transcriptionCoordinator: LocalTranscriptionCoordinator,
        startupWarning: String? = nil
    ) {
        self.recorder = recorder
        self.fileStore = fileStore
        self.teacherStore = teacherStore
        self.queueCoordinator = queueCoordinator
        self.demonstrationPipeline = demonstrationPipeline
        self.supportImporter = supportImporter
        self.aiOrchestrator = aiOrchestrator
        self.aiSecretStore = aiSecretStore
        self.aiPreferencesStore = aiPreferencesStore
        self.transcriptionCoordinator = transcriptionCoordinator
        var loadedAIPreferences = aiPreferencesStore.load()
        if AIModelCatalog.profile(id: loadedAIPreferences.selectedModelProfileID) == nil {
            loadedAIPreferences.selectedModelProfileID = AIModelCatalog.profiles[0].id
        }
        self.aiPreferences = loadedAIPreferences
        self.savedTeachers = teacherStore.teachers()
        self.supportDocuments = supportImporter.documents()
        self.errorMessage = startupWarning
        Task { await refreshAIState() }
        Task {
            await refreshLocalModelStatus()
            await restoreLatestLocalTranscription()
        }
    }

    var teachingUnits: [TeachingUnit] {
        TeachingUnitCatalog.units(for: selectedSemester)
    }

    var isRecording: Bool { snapshot.state == .recording }
    var isPaused: Bool { snapshot.state == .paused }
    var hasActiveSession: Bool { isRecording || isPaused }

    var canStart: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !teacherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasActiveSession
    }

    var estimatedAudioSize: Int64 {
        AudioStoragePolicy.requiredBytes(for: expectedDuration)
    }

    var trackingSummary: CourseTrackingSummary {
        trackingPresenter.summary(for: processingJobs)
    }

    var filteredProcessingJobs: [ProcessingJob] {
        trackingPresenter.jobs(processingJobs, matching: trackingFilter)
    }

    var selectedProcessingJob: ProcessingJob? {
        guard let selectedProcessingJobID else { return filteredProcessingJobs.first }
        return processingJobs.first { $0.id == selectedProcessingJobID }
    }

    var filteredTranscriptPassages: [TranscriptPassage] {
        guard let transcriptDraft else { return [] }
        return transcriptService.passages(
            in: transcriptDraft,
            matching: transcriptSearch,
            filter: transcriptFilter
        )
    }

    var localTranscriptionModels: [TranscriptionModelDescriptor] {
        LocalTranscriptionModelCatalog.alphaModels
    }

    var selectedLocalTranscriptionModelDescriptor: TranscriptionModelDescriptor {
        LocalTranscriptionModelCatalog.descriptor(for: selectedLocalTranscriptionModel)
            ?? LocalTranscriptionModelCatalog.alphaModels[0]
    }

    var localAudioDuration: TimeInterval {
        capturedSegments.reduce(0) { $0 + $1.duration }
    }

    var canStartLocalTranscription: Bool {
        currentCourse != nil
            && !capturedSegments.isEmpty
            && localModelStatus.availability == .available
            && !isLocalTranscriptionRunning
            && !isDownloadingTranscriptionModel
    }

    var privacyFindings: [PrivacyFinding] {
        guard transcriptDraft != nil else { return [] }
        return privacyDetector.scan(privacyContent)
    }

    var transcriptFingerprint: String? {
        guard transcriptDraft != nil else { return nil }
        return transcriptService.stableFingerprint(privacyContent)
    }

    var cloudTransmissionDecision: CloudTransmissionDecision? {
        guard transcriptDraft != nil, let transcriptFingerprint else { return nil }
        return privacyGate.evaluate(
            text: privacyContent,
            contentFingerprint: transcriptFingerprint,
            review: privacyReview
        )
    }

    var isPrivacyApproved: Bool {
        switch cloudTransmissionDecision {
        case .allowedNoIdentifiers, .allowedAfterManualReview: true
        default: false
        }
    }

    var aiModelProfiles: [AIModelProfile] { AIModelCatalog.profiles }

    var selectedAIModelProfile: AIModelProfile {
        AIModelCatalog.profile(id: aiPreferences.selectedModelProfileID)
            ?? AIModelCatalog.profiles[0]
    }

    var aiSpentUSD: Double {
        aiGenerationRuns.filter { !$0.usage.isSimulated }
            .map(\.usage.estimatedCostUSD)
            .reduce(0, +)
    }

    var aiBudgetRemainingUSD: Double {
        max(aiPreferences.trialBudgetUSD - aiSpentUSD, 0)
    }

    var aiCanRunTrial: Bool {
        isDemoMode && isPrivacyApproved && !isAIGenerationRunning
            && (!selectedAIModelProfile.isLive
                || (aiPreferences.liveRequestsEnabled && aiHasStoredKey))
    }

    private var privacyContent: String {
        let transcript = transcriptDraft?.plainText ?? ""
        let supports = supportDocuments.compactMap(\.extraction?.plainText)
            .joined(separator: "\n")
        return transcript + "\n" + supports
    }

    func trackingTimeline(for job: ProcessingJob) -> [CourseTrackingStageItem] {
        trackingPresenter.timeline(for: job)
    }

    func transcriptTextBinding(for passageID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.transcriptDraft?.passages.first(where: { $0.id == passageID })?.text ?? ""
            },
            set: { [weak self] newValue in
                self?.updateTranscriptPassage(id: passageID, text: newValue)
            }
        )
    }

    func updateTranscriptPassage(id: UUID, text: String) {
        guard let transcriptDraft else { return }
        self.transcriptDraft = transcriptService.updating(
            transcriptDraft,
            passageID: id,
            text: text
        )
        privacyReview = nil
    }

    func toggleTranscriptFlag(_ flag: TranscriptPassageFlag, passageID: UUID) {
        guard let transcriptDraft else { return }
        self.transcriptDraft = transcriptService.toggling(
            flag,
            in: transcriptDraft,
            passageID: passageID
        )
        privacyReview = nil
    }

    func saveTranscript() {
        guard var transcriptDraft else { return }
        transcriptDraft.updatedAt = Date()
        self.transcriptDraft = transcriptDraft
        persistRealTranscriptIfNeeded(transcriptDraft)
        workspaceNotice = transcriptDraft.isDemonstration
            ? "Modification conservée pour cette session de démonstration."
            : "Transcription enregistrée localement."
    }

    private func persistRealTranscriptIfNeeded(_ draft: TranscriptDraft) {
        guard !draft.isDemonstration else { return }
        realTranscriptDraft = draft
        Task {
            do {
                try await transcriptionCoordinator.saveEditedDraft(draft)
            } catch {
                errorMessage = "La modification n’a pas pu être enregistrée : \(error.localizedDescription)"
            }
        }
    }

    func selectLocalTranscriptionModel(_ modelID: LocalTranscriptionModelID) {
        guard LocalTranscriptionModelCatalog.descriptor(for: modelID)?.isEnabledInAlpha == true else { return }
        selectedLocalTranscriptionModel = modelID
        localModelStatus = .init(modelID: modelID, availability: .notDownloaded)
        Task { await refreshLocalModelStatus() }
    }

    func refreshLocalModelStatus() async {
        localModelStatus = await transcriptionCoordinator.modelStatus(for: selectedLocalTranscriptionModel)
    }

    func downloadSelectedTranscriptionModel() {
        guard !isDownloadingTranscriptionModel else { return }
        isDownloadingTranscriptionModel = true
        let modelID = selectedLocalTranscriptionModel
        modelDownloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await transcriptionCoordinator.downloadModel(modelID) { [weak self] status in
                    Task { @MainActor [weak self] in
                        guard self?.selectedLocalTranscriptionModel == status.modelID else { return }
                        self?.localModelStatus = status
                    }
                }
                guard !Task.isCancelled else { return }
                localModelStatus = status
                workspaceNotice = "Le modèle \(selectedLocalTranscriptionModelDescriptor.displayName) est disponible hors ligne."
            } catch is CancellationError {
                await refreshLocalModelStatus()
            } catch {
                localModelStatus = .init(
                    modelID: modelID,
                    availability: .failed,
                    errorMessage: error.localizedDescription
                )
                errorMessage = error.localizedDescription
            }
            isDownloadingTranscriptionModel = false
            modelDownloadTask = nil
        }
    }

    func cancelModelDownload() {
        modelDownloadTask?.cancel()
        modelDownloadTask = nil
        isDownloadingTranscriptionModel = false
    }

    func startLocalTranscription() {
        guard let course = currentCourse, canStartLocalTranscription else { return }
        let segments = capturedSegments
        let modelID = selectedLocalTranscriptionModel
        isLocalTranscriptionRunning = true
        localTranscriptionProgress = .init(
            stage: .checkingModel,
            fractionCompleted: 0,
            totalSegmentCount: segments.count
        )
        localTranscriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stored = try await transcriptionCoordinator.transcribe(
                    course: course,
                    segments: segments,
                    modelID: modelID
                ) { [weak self] update in
                    Task { @MainActor [weak self] in self?.localTranscriptionProgress = update }
                }
                guard !Task.isCancelled else { return }
                lastLocalTranscriptionResult = stored.result
                realTranscriptDraft = stored.draft
                if !isDemoMode { transcriptDraft = stored.draft }
                workspaceNotice = "Transcription brute terminée et enregistrée localement."
            } catch is CancellationError {
                localTranscriptionProgress.stage = .cancelled
                localTranscriptionProgress.message = "Transcription annulée proprement."
            } catch {
                localTranscriptionProgress.stage = .failed
                localTranscriptionProgress.message = error.localizedDescription
                errorMessage = "La transcription locale a échoué : \(error.localizedDescription)"
            }
            isLocalTranscriptionRunning = false
            localTranscriptionTask = nil
        }
    }

    func cancelLocalTranscription() {
        localTranscriptionTask?.cancel()
        localTranscriptionProgress.stage = .cancelled
        localTranscriptionProgress.message = "Annulation en cours…"
    }

    func openRawTranscriptInEditor() {
        guard realTranscriptDraft != nil else { return }
        if isDemoMode { deactivateDemonstrationMode() }
        transcriptDraft = realTranscriptDraft
        selectedSection = .transcript
    }

    func requestDocumentRegeneration() {
        workspaceNotice = "La correction est prête. La régénération sera ajoutée à la file sans retranscrire l’audio."
    }

    func selectAIModel(_ id: String) {
        guard AIModelCatalog.profile(id: id) != nil else { return }
        aiPreferences.selectedModelProfileID = id
        persistAIPreferences()
        aiAPIKeyDraft = ""
        Task { await refreshAIKeyStatus() }
    }

    func setAITrialBudget(_ value: Double) {
        aiPreferences.trialBudgetUSD = min(max(value, 0), 100)
        persistAIPreferences()
    }

    func setAILiveRequestsEnabled(_ enabled: Bool) {
        aiPreferences.liveRequestsEnabled = enabled
        persistAIPreferences()
    }

    func saveAIAPIKey() {
        let key = aiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedAIModelProfile.isLive else { return }
        guard key.count >= 20 else {
            errorMessage = "La clé API semble incomplète."
            return
        }
        let provider = selectedAIModelProfile.provider
        Task { @MainActor in
            do {
                try await aiSecretStore.saveSecret(key, for: provider)
                aiAPIKeyDraft = ""
                aiHasStoredKey = true
                workspaceNotice = "Clé enregistrée dans le Trousseau macOS. Aucun appel n’a été effectué."
            } catch {
                errorMessage = "La clé n’a pas pu être enregistrée : \(error.localizedDescription)"
            }
        }
    }

    func deleteAIAPIKey() {
        let provider = selectedAIModelProfile.provider
        guard provider != .simulated else { return }
        Task { @MainActor in
            do {
                try await aiSecretStore.deleteSecret(for: provider)
                aiHasStoredKey = false
                aiAPIKeyDraft = ""
                aiPreferences.liveRequestsEnabled = false
                persistAIPreferences()
                workspaceNotice = "La clé API a été supprimée du Trousseau."
            } catch {
                errorMessage = "La clé n’a pas pu être supprimée : \(error.localizedDescription)"
            }
        }
    }

    func runAIModelTrial() {
        guard !isAIGenerationRunning else { return }
        guard let transcriptDraft, transcriptDraft.isDemonstration else {
            activateDemonstrationMode()
            workspaceNotice = "Données fictives chargées. Vérifiez maintenant la confidentialité avant l’essai."
            selectedSection = .privacy
            return
        }
        guard isPrivacyApproved else {
            workspaceNotice = "L’essai attend la validation de confidentialité de cette version."
            selectedSection = .privacy
            return
        }
        let teacher = Teacher(
            name: "Enseignant Démo",
            recordingAuthorizationConfirmedAt: Date()
        )
        let unit = TeachingUnitCatalog.units(for: .semester1).first { $0.code == "2.11" }!
        let course = Course(
            id: transcriptDraft.courseID,
            semester: .semester1,
            teachingUnit: unit,
            title: transcriptDraft.courseTitle,
            teacher: teacher,
            expectedDuration: .oneHour
        )
        let request = AIGenerationRequest(
            course: course,
            transcript: transcriptDraft,
            supportExtractions: supportDocuments.compactMap(\.extraction),
            privacyReview: privacyReview,
            modelProfile: selectedAIModelProfile,
            preferences: aiPreferences
        )
        isAIGenerationRunning = true
        workspaceNotice = selectedAIModelProfile.isLive
            ? "Essai API en cours…"
            : "Simulation structurée en cours…"
        Task { @MainActor in
            defer { isAIGenerationRunning = false }
            do {
                let run = try await aiOrchestrator.run(request)
                aiLastRun = run
                aiGenerationRuns = try await aiOrchestrator.runs()
                workspaceNotice = "Essai validé : deux documents structurés, coût estimé \(formatUSDCost(run.usage.estimatedCostUSD))."
            } catch {
                errorMessage = "L’essai IA a échoué : \(error.localizedDescription)"
            }
        }
    }

    func formatUSDCost(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0...4)))
    }

    func jumpToAudio(at seconds: TimeInterval) {
        workspaceNotice = isDemoMode
            ? "Aperçu audio simulé à \(formatTimestamp(seconds)). Aucun fichier audio n’est utilisé."
            : "Position audio sélectionnée : \(formatTimestamp(seconds))."
    }

    func approvePrivacyReview() {
        guard let transcriptFingerprint, !privacyFindings.isEmpty else { return }
        privacyReview = PrivacyReview(
            contentFingerprint: transcriptFingerprint,
            decision: .approved
        )
        workspaceNotice = "Vérification enregistrée pour cette version exacte de la transcription."
    }

    func rejectPrivacyReview() {
        guard let transcriptFingerprint else { return }
        privacyReview = PrivacyReview(
            contentFingerprint: transcriptFingerprint,
            decision: .rejected
        )
        selectedSection = .transcript
    }

    func importTeacherDocument() {
        let panel = NSOpenPanel()
        panel.title = "Importer un document fourni par l’enseignant"
        panel.message = "Le fichier sera copié dans le stockage local de Scrib."
        panel.prompt = "Importer"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            "doc", "docx", "pdf", "ppt", "pptx", "xls", "xlsx",
            "png", "jpg", "jpeg", "heic", "tiff"
        ].compactMap { UTType(filenameExtension: $0) }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = try supportImporter.importDocument(from: url)
            supportDocuments = supportImporter.documents()
                + supportDocuments.filter(\.isDemonstration)
            workspaceNotice = "\(document.originalFileName) a été copié dans Scrib."
        } catch {
            errorMessage = "Le document n’a pas pu être importé : \(error.localizedDescription)"
        }
    }

    func deleteSupportDocument(_ document: SupportDocument) {
        do {
            if !document.isDemonstration {
                try supportImporter.deleteDocument(id: document.id)
            }
            supportDocuments.removeAll { $0.id == document.id }
        } catch {
            errorMessage = "Le document n’a pas pu être supprimé : \(error.localizedDescription)"
        }
    }

    func openSupportDocument(_ document: SupportDocument) {
        guard let localURL = document.localURL else {
            workspaceNotice = "Le document fictif n’ouvre aucun fichier réel."
            return
        }
        NSWorkspace.shared.open(localURL)
    }

    func selectDemonstrationAudio() {
        let panel = NSOpenPanel()
        panel.title = "Choisir l’audio public de démonstration"
        panel.message = "Sélectionnez vaccination.wav ou medicaments.wav téléchargé par le script Scrib."
        panel.prompt = "Utiliser cet audio"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.wav, .audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedDemoAudioURL = url
        demonstrationPipelineResult = nil
        workspaceNotice = "Audio sélectionné : \(url.lastPathComponent)"
    }

    func runDemonstrationPipeline() {
        guard !isDemonstrationPipelineRunning else { return }
        guard let transcriptDraft, transcriptDraft.isDemonstration else {
            errorMessage = "Activez d’abord le mode démonstration."
            return
        }
        guard let selectedDemoAudioURL else {
            selectDemonstrationAudio()
            return
        }

        let teacher = Teacher(
            name: "Enseignant Démo",
            recordingAuthorizationConfirmedAt: Date()
        )
        let unit = TeachingUnitCatalog.units(for: .semester1).first { $0.code == "2.11" }!
        let course = Course(
            id: transcriptDraft.courseID,
            semester: .semester1,
            teachingUnit: unit,
            title: transcriptDraft.courseTitle,
            teacher: teacher,
            expectedDuration: .oneHour
        )
        let audioMetadata = demonstrationAudioMetadata(for: selectedDemoAudioURL)
        let request = DemonstrationPipelineRequest(
            course: course,
            audioURL: selectedDemoAudioURL,
            audioAttribution: audioMetadata.attribution,
            audioLandingURL: audioMetadata.landingURL,
            transcript: transcriptDraft,
            privacyReview: privacyReview,
            supportExtractions: supportDocuments.compactMap(\.extraction)
        )

        isDemonstrationPipelineRunning = true
        workspaceNotice = "Pipeline local en cours…"
        Task { @MainActor in
            defer { isDemonstrationPipelineRunning = false }
            do {
                demonstrationPipelineResult = try await demonstrationPipeline.run(request)
                await reloadQueue()
                workspaceNotice = "Pipeline terminé : supports extraits et deux documents Word prêts."
            } catch let issue as DemonstrationPipelineError {
                await reloadQueue()
                switch issue {
                case .privacyApprovalRequired:
                    workspaceNotice = "Pipeline suspendu : vérifiez les alertes de confidentialité."
                    selectedSection = .privacy
                case .missingArtifact:
                    errorMessage = issue.localizedDescription
                }
            } catch {
                await reloadQueue()
                errorMessage = "Le pipeline de démonstration a échoué : \(error.localizedDescription)"
            }
        }
    }

    func revealDemonstrationArtifact(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func activateDemonstrationMode() {
        if transcriptDraft?.isDemonstration == false { realTranscriptDraft = transcriptDraft }
        isDemoMode = true
        transcriptDraft = demonstrationFactory.transcript()
        privacyReview = nil
        if !supportDocuments.contains(where: \.isDemonstration) {
            supportDocuments.insert(demonstrationFactory.supportDocument(), at: 0)
        }
        transcriptSearch = ""
        transcriptFilter = .all
        workspaceNotice = "Démonstration locale chargée : aucune donnée réelle et aucun appel réseau."
        selectedSection = .transcript
    }

    func deactivateDemonstrationMode() {
        let demonstrationCourseID = transcriptDraft?.isDemonstration == true
            ? transcriptDraft?.courseID
            : nil
        isDemoMode = false
        if transcriptDraft?.isDemonstration == true {
            transcriptDraft = realTranscriptDraft
        }
        supportDocuments.removeAll(where: \.isDemonstration)
        privacyReview = nil
        selectedDemoAudioURL = nil
        demonstrationPipelineResult = nil
        workspaceNotice = "Données de démonstration retirées."
        selectedSection = .demonstration
        if let demonstrationCourseID {
            Task { @MainActor in
                try? await demonstrationPipeline.reset(courseID: demonstrationCourseID)
                await reloadQueue()
            }
        }
    }

    func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func demonstrationAudioMetadata(for url: URL) -> (attribution: String, landingURL: URL?) {
        let normalized = url.lastPathComponent.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        if normalized.contains("medicament") {
            return (
                "CRSN — Régularité des prises de médicaments — CC BY-SA 4.0",
                URL(string: "https://commons.wikimedia.org/wiki/File:Fran%C3%A7ais_-_R%C3%A9gularit%C3%A9_des_prises_de_m%C3%A9dicaments.wav")
            )
        }
        if normalized.contains("vaccination") {
            return (
                "CRSN — Les avantages de la vaccination — CC BY-SA 4.0",
                URL(string: "https://commons.wikimedia.org/wiki/File:Fran%C3%A7ais_-_les_avantages_de_la_vaccination.wav")
            )
        }
        return ("Audio local choisi par l’utilisateur — démonstration", nil)
    }

    var menuBarSystemImage: String {
        if isRecording { return "record.circle.fill" }
        if isPaused { return "pause.circle.fill" }
        return "waveform"
    }

    var menuBarStatus: String {
        if isRecording { return "Enregistrement — \(formattedElapsed)" }
        if isPaused { return "En pause — \(formattedElapsed)" }
        return "Scrib est prêt"
    }

    var formattedElapsed: String {
        let seconds = Int(snapshot.elapsed.rounded(.down))
        return String(
            format: "%02d:%02d:%02d",
            seconds / 3_600,
            (seconds % 3_600) / 60,
            seconds % 60
        )
    }

    func chooseTeacher(_ teacher: Teacher) {
        teacherName = teacher.name
    }

    func startTapped() {
        let trimmedName = teacherName.trimmingCharacters(in: .whitespacesAndNewlines)
        let teacher = teacherStore.teacher(named: trimmedName) ?? Teacher(name: trimmedName)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !teacher.name.isEmpty else {
            errorMessage = "Le titre du cours et l’enseignant sont obligatoires."
            return
        }

        if !teacher.hasRecordingAuthorization {
            pendingTeacher = teacher
            authorizationRequested = true
            return
        }

        Task { await beginRecording(with: teacher) }
    }

    func prepareQueue() async {
        do {
            try await queueCoordinator.recoverInterruptedJobs()
            await reloadQueue()
            startQueuePolling()
        } catch {
            errorMessage = "La file d’attente n’a pas pu être restaurée : \(error.localizedDescription)"
        }
    }

    func reloadQueue() async {
        do {
            processingJobs = try await queueCoordinator.jobs()
            systemConditions = await queueCoordinator.currentConditions()
            selectFirstVisibleJobIfNeeded()
        } catch {
            errorMessage = "La file d’attente n’a pas pu être lue : \(error.localizedDescription)"
        }
    }

    func retry(_ job: ProcessingJob) {
        if isDemoMode, transcriptDraft?.courseID == job.courseID {
            selectedSection = .demonstration
            runDemonstrationPipeline()
            return
        }
        Task {
            do {
                try await queueCoordinator.retry(jobID: job.id)
                await reloadQueue()
            } catch {
                errorMessage = "Le cours n’a pas pu être relancé : \(error.localizedDescription)"
            }
        }
    }

    func selectProcessingJob(_ id: ProcessingJobID?) {
        selectedProcessingJobID = id
    }

    private func selectFirstVisibleJobIfNeeded() {
        let visible = filteredProcessingJobs
        guard !visible.isEmpty else {
            selectedProcessingJobID = nil
            return
        }
        if let selectedProcessingJobID, visible.contains(where: { $0.id == selectedProcessingJobID }) {
            return
        }
        selectedProcessingJobID = visible.first?.id
    }

    func confirmAuthorizationAndStart() {
        guard var teacher = pendingTeacher else { return }
        teacher.confirmRecordingAuthorization()
        do {
            try teacherStore.save(teacher)
            savedTeachers = teacherStore.teachers()
            pendingTeacher = nil
            authorizationRequested = false
            Task { await beginRecording(with: teacher) }
        } catch {
            errorMessage = "L’autorisation n’a pas pu être mémorisée : \(error.localizedDescription)"
        }
    }

    func cancelAuthorization() {
        pendingTeacher = nil
        authorizationRequested = false
    }

    func pause() {
        do {
            try recorder.pause()
            updateSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resume() {
        do {
            try recorder.resume()
            updateSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        do {
            capturedSegments = try recorder.stop().sorted { $0.sequence < $1.sequence }
            updateSnapshot()
            stopPolling()
            endSystemActivity()
            selectedSection = .localTranscription
            let capturedCourse = currentCourse
            Task {
                await queueCoordinator.recordingDidStop()
                if let capturedCourse {
                    do {
                        _ = try await queueCoordinator.enqueue(course: capturedCourse)
                    } catch {
                        errorMessage = "Le cours n’a pas pu être ajouté à la file : \(error.localizedDescription)"
                    }
                }
                await reloadQueue()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentQuitWarning() {
        quitWarningRequested = true
    }

    func confirmQuitAndStop() {
        if hasActiveSession {
            stop()
        }
        NSApplication.shared.terminate(nil)
    }

    private func beginRecording(with teacher: Teacher) async {
        let course = Course(
            semester: selectedSemester,
            teachingUnit: selectedTeachingUnit,
            title: title,
            teacher: teacher,
            expectedDuration: expectedDuration
        )

        do {
            let directory = try fileStore.recordingDirectory(for: course)
            let available = try fileStore.availableCapacity(for: directory)
            lastAvailableCapacity = available
            try readinessValidator.validate(
                course: course,
                teacher: teacher,
                availableCapacity: available
            )

            guard await recorder.requestPermission() else {
                errorMessage = "L’accès au microphone est refusé. Autorisez Scrib dans Réglages Système > Confidentialité et sécurité > Microphone."
                return
            }

            await queueCoordinator.recordingDidStart()
            do {
                try recorder.start(courseID: course.id, directory: directory)
            } catch {
                await queueCoordinator.recordingDidStop()
                throw error
            }
            currentCourse = course
            capturedSegments = []
            localTranscriptionProgress = .init(stage: .idle)
            lastLocalTranscriptionResult = nil
            updateSnapshot()
            beginSystemActivity()
            startPolling()
        } catch let issue as RecordingReadinessIssue {
            errorMessage = message(for: issue)
        } catch {
            errorMessage = "Impossible de démarrer l’enregistrement : \(error.localizedDescription)"
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updateSnapshot()
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        lowSoundStartedAt = nil
        lowSoundWarning = false
    }

    private func startQueuePolling() {
        queuePollingTask?.cancel()
        queuePollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.reloadQueue()
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
            }
        }
    }

    private func updateSnapshot() {
        snapshot = recorder.snapshot()
        updateLowSoundWarning()
        if snapshot.state == .failed {
            stopPolling()
            endSystemActivity()
            Task { await queueCoordinator.recordingDidStop() }
            errorMessage = snapshot.incidentMessage ?? "L’enregistrement audio s’est interrompu."
        }
    }

    private func updateLowSoundWarning() {
        guard snapshot.state == .recording else {
            lowSoundStartedAt = nil
            lowSoundWarning = false
            return
        }

        if snapshot.averagePowerDecibels < -55 {
            lowSoundStartedAt = lowSoundStartedAt ?? Date()
            lowSoundWarning = Date().timeIntervalSince(lowSoundStartedAt!) >= 5
        } else {
            lowSoundStartedAt = nil
            lowSoundWarning = false
        }
    }

    private func beginSystemActivity() {
        guard systemActivity == nil else { return }
        systemActivity = ProcessInfo.processInfo.beginActivity(
            options: [
                .userInitiated,
                .idleSystemSleepDisabled,
                .idleDisplaySleepDisabled,
                .suddenTerminationDisabled
            ],
            reason: "Enregistrement d’un cours dans Scrib"
        )
    }

    private func endSystemActivity() {
        guard let systemActivity else { return }
        ProcessInfo.processInfo.endActivity(systemActivity)
        self.systemActivity = nil
    }

    private func restoreLatestLocalTranscription() async {
        do {
            guard let stored = try await transcriptionCoordinator.latestTranscription() else { return }
            currentCourse = stored.course
            capturedSegments = stored.recordingSegments
            lastLocalTranscriptionResult = stored.result
            realTranscriptDraft = stored.draft
            if !isDemoMode { transcriptDraft = stored.draft }
            snapshot = AudioRecorderSnapshot(
                state: .finished,
                elapsed: stored.recordingSegments.reduce(0) { $0 + $1.duration },
                segments: stored.recordingSegments
            )
        } catch {
            errorMessage = "La dernière transcription locale n’a pas pu être restaurée : \(error.localizedDescription)"
        }
    }

    private func refreshAIState() async {
        do {
            aiGenerationRuns = try await aiOrchestrator.runs()
            aiLastRun = aiGenerationRuns.first
            await refreshAIKeyStatus()
        } catch {
            errorMessage = "Les réglages IA n’ont pas pu être chargés : \(error.localizedDescription)"
        }
    }

    private func refreshAIKeyStatus() async {
        let provider = selectedAIModelProfile.provider
        guard provider != .simulated else {
            aiHasStoredKey = false
            return
        }
        do {
            aiHasStoredKey = try await aiSecretStore.hasSecret(for: provider)
        } catch {
            aiHasStoredKey = false
            errorMessage = "Le Trousseau macOS n’a pas pu être consulté : \(error.localizedDescription)"
        }
    }

    private func persistAIPreferences() {
        do {
            try aiPreferencesStore.save(aiPreferences)
        } catch {
            errorMessage = "Les réglages IA n’ont pas pu être enregistrés : \(error.localizedDescription)"
        }
    }

    private func message(for issue: RecordingReadinessIssue) -> String {
        switch issue {
        case .incompleteCourse:
            "Les informations du cours sont incomplètes."
        case .teacherAuthorizationRequired:
            "L’autorisation d’enregistrer cet enseignant doit être confirmée."
        case let .insufficientStorage(required, available):
            "Espace insuffisant : \(formatBytes(available)) disponibles, \(formatBytes(required)) nécessaires."
        }
    }

    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
