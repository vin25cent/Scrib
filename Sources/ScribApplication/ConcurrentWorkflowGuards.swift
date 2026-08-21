import Foundation

public enum RecordingWorkflowState: String, Equatable, Sendable {
    case idle
    case starting
    case recording
    case paused
    case stopping
    case error
}

/// Small MainActor-owned gate used to reject overlapping recording commands.
public struct RecordingStartGate: Sendable {
    public private(set) var state: RecordingWorkflowState = .idle
    public private(set) var startID: UUID?

    public init() {}

    public mutating func beginStart() -> UUID? {
        guard state == .idle || state == .error else { return nil }
        let id = UUID()
        startID = id
        state = .starting
        return id
    }

    @discardableResult
    public mutating func recordingDidStart(id: UUID) -> Bool {
        guard state == .starting, startID == id else { return false }
        startID = nil
        state = .recording
        return true
    }

    @discardableResult
    public mutating func recordingStartDidFail(id: UUID) -> Bool {
        guard state == .starting, startID == id else { return false }
        startID = nil
        state = .error
        return true
    }

    public mutating func cancelStart() -> UUID? {
        guard state == .starting, let startID else { return nil }
        self.startID = nil
        state = .idle
        return startID
    }

    @discardableResult
    public mutating func pause() -> Bool {
        guard state == .recording else { return false }
        state = .paused
        return true
    }

    @discardableResult
    public mutating func resume() -> Bool {
        guard state == .paused else { return false }
        state = .recording
        return true
    }

    @discardableResult
    public mutating func beginStop() -> Bool {
        guard state == .recording || state == .paused else { return false }
        state = .stopping
        return true
    }

    public mutating func stopDidFinish() {
        startID = nil
        state = .idle
    }

    public mutating func stopDidFail() {
        startID = nil
        state = .error
    }
}

/// Identifies the latest instance of one cancellable workflow.
/// It owns no task and performs no scheduling.
public struct LatestOperationGeneration: Sendable {
    public private(set) var currentID: UUID?

    public init() {}

    public mutating func begin() -> UUID {
        let id = UUID()
        currentID = id
        return id
    }

    @discardableResult
    public mutating func cancelCurrent() -> UUID? {
        defer { currentID = nil }
        return currentID
    }

    public func accepts(_ id: UUID) -> Bool {
        currentID == id
    }

    @discardableResult
    public mutating func finish(_ id: UUID) -> Bool {
        guard currentID == id else { return false }
        currentID = nil
        return true
    }
}

/// Gives callbacks a stable invocation order before they hop back to MainActor.
public final class WorkflowProgressSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    public init() {}

    public func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

public struct OrderedProgressGate: Sendable {
    private var operationID: UUID?
    private var lastAppliedSequence = 0

    public init() {}

    public mutating func begin(operationID: UUID) {
        self.operationID = operationID
        lastAppliedSequence = 0
    }

    @discardableResult
    public mutating func accept(operationID: UUID, sequence: Int) -> Bool {
        guard self.operationID == operationID, sequence > lastAppliedSequence else {
            return false
        }
        lastAppliedSequence = sequence
        return true
    }

    public mutating func invalidate(operationID: UUID) {
        guard self.operationID == operationID else { return }
        self.operationID = nil
        lastAppliedSequence = 0
    }
}
