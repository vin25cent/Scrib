import Testing
@testable import ScribDomain

@Test func systemConditionsReportEveryBlockingReason() {
    let snapshot = SystemConditionSnapshot(
        isOnExternalPower: false,
        isNetworkAvailable: false,
        thermalCondition: .serious,
        memoryCondition: .warning,
        isRecordingActive: true
    )

    #expect(
        snapshot.blockers == [
            .recordingActive,
            .batteryPower,
            .networkUnavailable,
            .thermalPressure,
            .memoryPressure
        ]
    )
    #expect(!snapshot.canRunHeavyProcessing)
}
