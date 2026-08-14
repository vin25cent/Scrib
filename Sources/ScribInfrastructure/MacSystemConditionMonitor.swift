#if os(macOS)
import Foundation
import IOKit.ps
import Network
import ScribApplication
import ScribDomain

public final class MacSystemConditionMonitor: SystemConditionsMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "app.scrib.system-conditions")
    private let memorySource: DispatchSourceMemoryPressure
    private var networkAvailable = false
    private var memoryCondition: MemoryCondition = .normal

    public init() {
        memorySource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: monitorQueue
        )

        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.lock.withLock {
                self?.networkAvailable = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: monitorQueue)

        memorySource.setEventHandler { [weak self] in
            guard let self else { return }
            let data = self.memorySource.data
            self.lock.withLock {
                if data.contains(.critical) {
                    self.memoryCondition = .critical
                } else if data.contains(.warning) {
                    self.memoryCondition = .warning
                } else {
                    self.memoryCondition = .normal
                }
            }
        }
        memorySource.resume()
    }

    public func currentSnapshot() async -> SystemConditionSnapshot {
        let state = lock.withLock { (networkAvailable, memoryCondition) }
        return SystemConditionSnapshot(
            isOnExternalPower: Self.isOnExternalPower(),
            isNetworkAvailable: state.0,
            thermalCondition: Self.thermalCondition(),
            memoryCondition: state.1
        )
    }

    private static func isOnExternalPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            return false
        }
        return powerType as String == kIOPSACPowerValue as String
    }

    private static func thermalCondition() -> ThermalCondition {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }
}
#endif
