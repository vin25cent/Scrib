import Foundation
import Testing
@testable import ScribApplication

@Test func doubleStartTapCreatesOnlyOneStartOperation() {
    var gate = RecordingStartGate()

    let first = gate.beginStart()
    let second = gate.beginStart()

    #expect(first != nil)
    #expect(second == nil)
    #expect(gate.state == .starting)
}

@Test func startDuringStartCannotReplaceTheActiveStartID() throws {
    var gate = RecordingStartGate()
    let firstResult = gate.beginStart()
    let first = try #require(firstResult)

    let overlapping = gate.beginStart()
    #expect(overlapping == nil)
    #expect(gate.startID == first)
    let started = gate.recordingDidStart(id: first)
    #expect(started)
    #expect(gate.state == .recording)
}

@Test func stopDuringStartCancelsOnlyThePendingStart() throws {
    var gate = RecordingStartGate()
    let startResult = gate.beginStart()
    let cancelledID = try #require(startResult)

    let cancelled = gate.cancelStart()
    #expect(cancelled == cancelledID)
    #expect(gate.state == .idle)
    let lateStart = gate.recordingDidStart(id: cancelledID)
    let restarted = gate.beginStart()
    #expect(!lateStart)
    #expect(restarted != nil)
}

@Test func finalizedRecordingReturnsTheWorkflowToAnIdleState() throws {
    var gate = RecordingStartGate()
    let startResult = gate.beginStart()
    let start = try #require(startResult)
    let started = gate.recordingDidStart(id: start)
    let didBeginStop = gate.beginStop()
    #expect(started)
    #expect(didBeginStop)

    gate.stopDidFinish()

    #expect(gate.state == .idle)
    #expect(gate.startID == nil)
}

@Test func transcriptionCancellationInvalidatesItsLateCompletion() throws {
    var generation = LatestOperationGeneration()
    let cancelled = generation.begin()

    #expect(generation.cancelCurrent() == cancelled)
    #expect(!generation.accepts(cancelled))
    let lateFinish = generation.finish(cancelled)
    #expect(!lateFinish)
}

@Test func newTranscriptionAfterCancellationHasAnIndependentGeneration() {
    var generation = LatestOperationGeneration()
    let old = generation.begin()
    _ = generation.cancelCurrent()
    let current = generation.begin()

    #expect(!generation.accepts(old))
    #expect(generation.accepts(current))
}

@Test func oldAndOutOfOrderProgressCallbacksAreRejected() {
    var generation = LatestOperationGeneration()
    var progress = OrderedProgressGate()
    let old = generation.begin()
    progress.begin(operationID: old)
    let current = generation.begin()
    progress.begin(operationID: current)

    #expect(!generation.accepts(old))
    #expect(generation.accepts(current))
    let newest = progress.accept(operationID: current, sequence: 2)
    let outOfOrder = progress.accept(operationID: current, sequence: 1)
    let oldOperation = progress.accept(operationID: old, sequence: 99)
    #expect(newest)
    #expect(!outOfOrder)
    #expect(!oldOperation)
}

@Test func cancelledModelDownloadCanBeRelaunchedWithoutLateOverwrite() {
    var generation = LatestOperationGeneration()
    var progress = OrderedProgressGate()
    let cancelled = generation.begin()
    progress.begin(operationID: cancelled)
    progress.invalidate(operationID: cancelled)
    _ = generation.cancelCurrent()

    let relaunched = generation.begin()
    progress.begin(operationID: relaunched)

    #expect(!generation.accepts(cancelled))
    let lateCancelledProgress = progress.accept(operationID: cancelled, sequence: 10)
    #expect(generation.accepts(relaunched))
    let relaunchedProgress = progress.accept(operationID: relaunched, sequence: 1)
    #expect(!lateCancelledProgress)
    #expect(relaunchedProgress)
}
