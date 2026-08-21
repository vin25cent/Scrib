#if os(macOS)
@preconcurrency import AVFoundation
import Foundation
import OSLog
import ScribApplication
import ScribDomain

public enum AVFoundationAudioRecorderError: LocalizedError {
    case alreadyActive
    case notRecording
    case cannotStart(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyActive:
            "Un enregistrement est déjà actif."
        case .notRecording:
            "Aucun enregistrement n’est actif."
        case .cannotStart(let details):
            "Le microphone n’a pas pu démarrer l’enregistrement : \(details)"
        }
    }
}

private func audioErrorDetails(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(type(of: error)); domaine=\(nsError.domain); code=\(nsError.code); description=\(nsError.localizedDescription)"
}

private let audioRecordingLogger = Logger(
    subsystem: "com.vin25cent.scrib",
    category: "AudioRecording"
)

private func logAudioRecording(_ message: String) {
    audioRecordingLogger.notice("[Scrib][AudioRecording] \(message, privacy: .public)")
}

private func logAudioRecordingError(_ message: String) {
    audioRecordingLogger.error("[Scrib][AudioRecording] \(message, privacy: .public)")
}

private final class AudioRecorderDelegate: NSObject, AVAudioRecorderDelegate {
    private let didFail: @Sendable (String, URL) -> Void

    init(didFail: @escaping @Sendable (String, URL) -> Void) {
        self.didFail = didFail
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let details = error.map(audioErrorDetails)
            ?? "AVAudioRecorderDelegate a signalé une erreur d’encodage sans NSError."
        let fileURL = recorder.url

        logAudioRecordingError("Erreur d’encodage; url=\(fileURL.path); \(details)")
        didFail(details, fileURL)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }

        let fileURL = recorder.url
        let details = "AVAudioRecorderDelegate a terminé l’enregistrement avec successfully=false."
        logAudioRecordingError("Enregistrement interrompu; url=\(fileURL.path); \(details)")
        didFail(details, fileURL)
    }
}

protocol MicrophonePermissionProviding: Sendable {
    func authorizationStatus() -> AVAuthorizationStatus
    func requestAccess(completionHandler: @escaping @Sendable (Bool) -> Void)
}

private struct AVCaptureDeviceMicrophonePermissionProvider: MicrophonePermissionProviding {
    func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestAccess(completionHandler: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completionHandler)
    }
}

@MainActor
public final class AVFoundationAudioRecorder: NSObject, AudioRecording {
    public static let segmentDuration: TimeInterval = 10 * 60

    private let fileManager: FileManager
    private let permissionProvider: any MicrophonePermissionProviding
    private let sessionStore: (any RecordingSessionStoring)?
    private lazy var recorderDelegate = AudioRecorderDelegate { [weak self] details, fileURL in
        Task { @MainActor [weak self] in
            self?.handleRecorderFailure(details: details, fileURL: fileURL)
        }
    }
    private var recorder: AVAudioRecorder?
    private var courseID: CourseID?
    private var directory: URL?
    private var sessionID: UUID?
    private var activeRelativePath: String?
    private var segmentStartedAt: Date?
    private var segments: [RecordingSegment] = []
    private var state: AudioRecorderState = .idle
    private var activeInputName = "Microphone système"
    private var incidentMessage: String?
    private var rolloverTask: Task<Void, Never>?
    private var disconnectionObserver: NSObjectProtocol?

    public convenience init(fileManager: FileManager = .default) {
        self.init(
            fileManager: fileManager,
            permissionProvider: AVCaptureDeviceMicrophonePermissionProvider(),
            sessionStore: try? LocalRecordingSessionStore(fileManager: fileManager)
        )
    }

    public convenience init(sessionStore: any RecordingSessionStoring, fileManager: FileManager = .default) {
        self.init(
            fileManager: fileManager,
            permissionProvider: AVCaptureDeviceMicrophonePermissionProvider(),
            sessionStore: sessionStore
        )
    }

    init(
        fileManager: FileManager,
        permissionProvider: any MicrophonePermissionProviding,
        sessionStore: (any RecordingSessionStoring)? = nil
    ) {
        self.fileManager = fileManager
        self.permissionProvider = permissionProvider
        self.sessionStore = sessionStore
        super.init()
        observeDeviceDisconnections()
    }

    public func requestPermission() async -> Bool {
        switch permissionProvider.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await Self.requestAccess(using: permissionProvider)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private nonisolated static func requestAccess(
        using provider: any MicrophonePermissionProviding
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            provider.requestAccess { @Sendable granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public func start(course: Course, directory: URL) throws {
        guard state != .recording && state != .paused else {
            throw AVFoundationAudioRecorderError.alreadyActive
        }
        guard let sessionStore else {
            throw AVFoundationAudioRecorderError.cannotStart(
                "Le stockage du manifeste de session est indisponible."
            )
        }

        let manifest = try sessionStore.createSession(course: course, directory: directory)
        self.courseID = course.id
        self.directory = directory
        self.sessionID = manifest.sessionID
        segments = []
        incidentMessage = nil
        do {
            try startNewSegment()
        } catch {
            markActiveSegmentFailed()
            state = .failed
            throw error
        }
    }

    public func pause() throws {
        guard state == .recording else {
            throw AVFoundationAudioRecorderError.notRecording
        }
        try finishCurrentSegment(nextState: .paused)
    }

    public func resume() throws {
        guard state == .paused else {
            throw AVFoundationAudioRecorderError.notRecording
        }
        do {
            try startNewSegment()
        } catch {
            markActiveSegmentFailed()
            state = .failed
            throw error
        }
    }

    public func stop() throws -> [RecordingSegment] {
        switch state {
        case .recording:
            try finishCurrentSegment(nextState: .finished)
        case .paused:
            rolloverTask?.cancel()
            rolloverTask = nil
            try finishSessionManifest()
            state = .finished
        case .idle, .finished, .failed:
            throw AVFoundationAudioRecorderError.notRecording
        }
        return segments
    }

    public func snapshot() -> AudioRecorderSnapshot {
        recorder?.updateMeters()
        let currentElapsed = recorder?.currentTime ?? 0
        let completedElapsed = segments.reduce(0) { $0 + $1.duration }
        let power = recorder?.averagePower(forChannel: 0) ?? -80

        return AudioRecorderSnapshot(
            state: state,
            elapsed: completedElapsed + currentElapsed,
            averagePowerDecibels: power,
            segments: segments,
            activeInputName: activeInputName,
            incidentMessage: incidentMessage
        )
    }

    private func startNewSegment() throws {
        guard let courseID, let directory, let sessionID, let sessionStore else {
            throw AVFoundationAudioRecorderError.cannotStart(
                "La configuration de destination est indisponible."
            )
        }

        let sequence = segments.count + 1
        let relativePath = String(format: "segment-%04d.m4a", sequence)
        let fileURL = directory.appendingPathComponent(relativePath)
        guard fileURL.pathExtension.lowercased() == "m4a" else {
            throw AVFoundationAudioRecorderError.cannotStart(
                "L’extension de destination ne correspond pas au conteneur AAC/MPEG-4 attendu."
            )
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: AudioStoragePolicy.captureSampleRate,
            AVNumberOfChannelsKey: AudioStoragePolicy.captureChannelCount,
            AVEncoderBitRateKey: Int(AudioStoragePolicy.targetBitRate)
        ]

        let persistedSegment = try sessionStore.beginSegment(
            sessionID: sessionID,
            in: directory,
            relativePath: relativePath,
            sequence: sequence,
            startedAt: Date()
        )
        activeRelativePath = persistedSegment.relativePath

        try prepareDestinationDirectory(directory, fileURL: fileURL)
        let inputDevice = AVCaptureDevice.default(for: .audio)
        logStartAttempt(
            fileURL: fileURL,
            directory: directory,
            inputDevice: inputDevice,
            settings: settings
        )

        let newRecorder: AVAudioRecorder
        do {
            newRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        } catch {
            markActiveSegmentFailed()
            let details = audioErrorDetails(error)
            logAudioRecordingError("Création AVAudioRecorder échouée; url=\(fileURL.path); \(details)")
            throw AVFoundationAudioRecorderError.cannotStart(details)
        }
        logAudioRecording("AVAudioRecorder initialisation=success; url=\(fileURL.path); format=\(newRecorder.format); settings=\(newRecorder.settings)")

        newRecorder.delegate = recorderDelegate
        newRecorder.isMeteringEnabled = true
        let prepared = newRecorder.prepareToRecord()
        logAudioRecording("prepareToRecord=\(prepared); url=\(fileURL.path); format=\(newRecorder.format)")
        guard prepared else {
            markActiveSegmentFailed()
            throw AVFoundationAudioRecorderError.cannotStart(
                "AVAudioRecorder.prepareToRecord() a retourné false."
            )
        }

        recorder = newRecorder
        let recordingStarted = newRecorder.record()
        logAudioRecording("record=\(recordingStarted); isRecording=\(newRecorder.isRecording); url=\(fileURL.path)")
        guard recordingStarted else {
            recorder = nil
            markActiveSegmentFailed()
            throw AVFoundationAudioRecorderError.cannotStart(
                "AVAudioRecorder.record() a retourné false."
            )
        }

        segmentStartedAt = persistedSegment.createdAt
        state = .recording
        activeInputName = inputDevice?.localizedName
            ?? "Microphone système"
        scheduleRollover()

        _ = courseID
    }

    private func prepareDestinationDirectory(_ directory: URL, fileURL: URL) throws {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            let details = audioErrorDetails(error)
            logAudioRecordingError("Création du dossier échouée; url=\(fileURL.path); \(details)")
            throw AVFoundationAudioRecorderError.cannotStart(details)
        }

        var isDirectory = ObjCBool(false)
        let directoryExists = fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        )
        let directoryIsWritable = fileManager.isWritableFile(atPath: directory.path)
        logAudioRecording("Destination; url=\(fileURL.path); parentExists=\(directoryExists); parentIsDirectory=\(isDirectory.boolValue); parentWritable=\(directoryIsWritable)")

        guard directoryExists, isDirectory.boolValue else {
            throw AVFoundationAudioRecorderError.cannotStart(
                "Le dossier parent de destination est introuvable."
            )
        }
        guard directoryIsWritable else {
            throw AVFoundationAudioRecorderError.cannotStart(
                "Le dossier parent de destination n’est pas accessible en écriture."
            )
        }
    }

    private func logStartAttempt(
        fileURL: URL,
        directory: URL,
        inputDevice: AVCaptureDevice?,
        settings: [String: Any]
    ) {
        let availableInputs = AVCaptureDevice.devices(for: .audio)
            .map(\.localizedName)
            .joined(separator: ", ")
        logAudioRecording("Démarrage; url=\(fileURL.path); parent=\(directory.path); extension=\(fileURL.pathExtension); format=MPEG4AAC; sampleRate=\(settings[AVSampleRateKey] ?? "inconnu")Hz; channels=\(settings[AVNumberOfChannelsKey] ?? "inconnu"); bitRate=\(settings[AVEncoderBitRateKey] ?? "inconnu")bps; encoderQuality=non configurée; input=\(inputDevice?.localizedName ?? "aucune"); availableInputs=\(availableInputs.isEmpty ? "aucune" : availableInputs)")
    }

    private func handleRecorderFailure(details: String, fileURL: URL) {
        guard recorder?.url == fileURL else { return }

        rolloverTask?.cancel()
        rolloverTask = nil
        markActiveSegmentFailed(fileURL: fileURL)
        state = .failed
        incidentMessage = "L’enregistrement audio a échoué : \(details)"
    }

    private func finishCurrentSegment(nextState: AudioRecorderState) throws {
        guard let recorder, let courseID, let directory, let sessionID, let sessionStore, let segmentStartedAt else {
            throw AVFoundationAudioRecorderError.notRecording
        }

        rolloverTask?.cancel()
        rolloverTask = nil
        recorder.stop()
        let endedAt = Date()
        let attributes = try? fileManager.attributesOfItem(
            atPath: recorder.url.path
        )
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let segment = RecordingSegment(
            courseID: courseID,
            sequence: segments.count + 1,
            fileURL: recorder.url,
            startedAt: segmentStartedAt,
            endedAt: endedAt,
            byteCount: byteCount
        )

        do {
            try sessionStore.finalizeSegment(
                sessionID: sessionID,
                in: directory,
                segment: segment,
                nextSessionState: nextState == .finished ? .stopped : .paused
            )
        } catch {
            self.recorder = nil
            self.segmentStartedAt = nil
            self.activeRelativePath = nil
            state = .failed
            incidentMessage = "Le segment audio a été arrêté, mais son manifeste n'a pas pu être enregistré : \(error.localizedDescription)"
            throw error
        }

        segments.append(segment)

        self.recorder = nil
        self.segmentStartedAt = nil
        self.activeRelativePath = nil
        state = nextState
    }

    private func finishSessionManifest() throws {
        guard let sessionID, let directory, let sessionStore else {
            throw AVFoundationAudioRecorderError.notRecording
        }
        try sessionStore.finishSession(sessionID: sessionID, in: directory)
    }

    private func markActiveSegmentFailed(fileURL: URL? = nil) {
        guard let sessionID, let directory, let sessionStore, let activeRelativePath else { return }
        let url = fileURL ?? directory.appendingPathComponent(activeRelativePath)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        try? sessionStore.failActiveSegment(
            sessionID: sessionID,
            in: directory,
            relativePath: activeRelativePath,
            endedAt: Date(),
            byteCount: byteCount
        )
        self.activeRelativePath = nil
    }

    private func scheduleRollover() {
        rolloverTask?.cancel()
        rolloverTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.segmentDuration))
                guard let self, !Task.isCancelled, self.state == .recording else {
                    return
                }
                try self.finishCurrentSegment(nextState: .paused)
                try self.startNewSegment()
            } catch is CancellationError {
                return
            } catch {
                self?.state = .failed
                self?.incidentMessage = error.localizedDescription
            }
        }
    }

    private func observeDeviceDisconnections() {
        disconnectionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let disconnectedName = (notification.object as? AVCaptureDevice)?.localizedName
            Task { @MainActor [weak self] in
                self?.handleDeviceDisconnection(named: disconnectedName)
            }
        }
    }

    private func handleDeviceDisconnection(named disconnectedName: String?) {
        guard state == .recording,
              disconnectedName == nil || disconnectedName == activeInputName else {
            return
        }

        do {
            try finishCurrentSegment(nextState: .paused)
            activeInputName = AVCaptureDevice.default(for: .audio)?.localizedName
                ?? "Microphone interne"
            incidentMessage = "Microphone déconnecté. Bascule vers \(activeInputName)."
            try startNewSegment()
        } catch {
            state = .failed
            incidentMessage = "Le microphone a été déconnecté : \(error.localizedDescription)"
        }
    }
}
#endif
