#if os(macOS)
@preconcurrency import AVFoundation
import Foundation
import ScribApplication
import ScribDomain

public enum AVFoundationAudioRecorderError: LocalizedError {
    case alreadyActive
    case notRecording
    case cannotStart

    public var errorDescription: String? {
        switch self {
        case .alreadyActive:
            "Un enregistrement est déjà actif."
        case .notRecording:
            "Aucun enregistrement n’est actif."
        case .cannotStart:
            "Le microphone n’a pas pu démarrer l’enregistrement."
        }
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
    private var recorder: AVAudioRecorder?
    private var courseID: CourseID?
    private var directory: URL?
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
            permissionProvider: AVCaptureDeviceMicrophonePermissionProvider()
        )
    }

    init(
        fileManager: FileManager,
        permissionProvider: any MicrophonePermissionProviding
    ) {
        self.fileManager = fileManager
        self.permissionProvider = permissionProvider
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

    public func start(courseID: CourseID, directory: URL) throws {
        guard state != .recording && state != .paused else {
            throw AVFoundationAudioRecorderError.alreadyActive
        }

        self.courseID = courseID
        self.directory = directory
        segments = []
        incidentMessage = nil
        try startNewSegment()
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
        try startNewSegment()
    }

    public func stop() throws -> [RecordingSegment] {
        switch state {
        case .recording:
            try finishCurrentSegment(nextState: .finished)
        case .paused:
            state = .finished
            rolloverTask?.cancel()
            rolloverTask = nil
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
        guard let courseID, let directory else {
            throw AVFoundationAudioRecorderError.cannotStart
        }

        let sequence = segments.count + 1
        let fileURL = directory.appendingPathComponent(
            String(format: "segment-%04d.m4a", sequence)
        )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: Int(AudioStoragePolicy.targetBitRate),
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let newRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        newRecorder.isMeteringEnabled = true
        guard newRecorder.prepareToRecord(), newRecorder.record() else {
            throw AVFoundationAudioRecorderError.cannotStart
        }

        recorder = newRecorder
        segmentStartedAt = Date()
        state = .recording
        activeInputName = AVCaptureDevice.default(for: .audio)?.localizedName
            ?? "Microphone système"
        scheduleRollover()

        _ = courseID
    }

    private func finishCurrentSegment(nextState: AudioRecorderState) throws {
        guard let recorder, let courseID, let segmentStartedAt else {
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
        segments.append(
            RecordingSegment(
                courseID: courseID,
                sequence: segments.count + 1,
                fileURL: recorder.url,
                startedAt: segmentStartedAt,
                endedAt: endedAt,
                byteCount: byteCount
            )
        )

        self.recorder = nil
        self.segmentStartedAt = nil
        state = nextState
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
