#if os(macOS)
@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import ScribInfrastructure

struct AVFoundationAudioRecorderPermissionTests {
    @Test func startFailurePreservesTechnicalDetails() {
        let error = AVFoundationAudioRecorderError.cannotStart(
            "AVAudioRecorder.record() a retourné false."
        )

        #expect(error.errorDescription?.contains("record() a retourné false") == true)
    }

    @MainActor
    @Test func authorizedPermissionReturnsTrueWithoutRequestingAccess() async {
        let provider = MockMicrophonePermissionProvider(
            status: .authorized,
            requestResult: false
        )
        let recorder = AVFoundationAudioRecorder(
            fileManager: .default,
            permissionProvider: provider
        )

        let granted = await recorder.requestPermission()

        #expect(granted)
        #expect(provider.requestCount == 0)
    }

    @MainActor
    @Test func deniedPermissionReturnsFalseWithoutRequestingAccess() async {
        let provider = MockMicrophonePermissionProvider(
            status: .denied,
            requestResult: true
        )
        let recorder = AVFoundationAudioRecorder(
            fileManager: .default,
            permissionProvider: provider
        )

        let granted = await recorder.requestPermission()

        #expect(!granted)
        #expect(provider.requestCount == 0)
    }

    @MainActor
    @Test(arguments: [true, false])
    func undeterminedPermissionReturnsBackgroundCallbackResult(granted: Bool) async {
        let provider = MockMicrophonePermissionProvider(
            status: .notDetermined,
            requestResult: granted
        )
        let recorder = AVFoundationAudioRecorder(
            fileManager: .default,
            permissionProvider: provider
        )

        let result = await recorder.requestPermission()

        #expect(result == granted)
        #expect(provider.requestCount == 1)
    }
}

private final class MockMicrophonePermissionProvider:
    MicrophonePermissionProviding,
    @unchecked Sendable
{
    private let status: AVAuthorizationStatus
    private let requestResult: Bool
    private let lock = NSLock()
    private var storedRequestCount = 0

    init(status: AVAuthorizationStatus, requestResult: Bool) {
        self.status = status
        self.requestResult = requestResult
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCount
    }

    func authorizationStatus() -> AVAuthorizationStatus {
        status
    }

    func requestAccess(completionHandler: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        storedRequestCount += 1
        lock.unlock()

        DispatchQueue.global().async { [requestResult] in
            completionHandler(requestResult)
        }
    }
}
#endif
