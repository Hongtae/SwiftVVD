import XCTest
@testable import VUI

final class AnimatableAttributeCustomToCustomReplacementCompletionTests: XCTestCase {
    func testMergeTrueNilGroupsBothGenerationsAtReplacementNil() {
        assertCustomToCustomReplacement(
            label: "merge true nil",
            replacementShouldMerge: true,
            oldLogicalAt: nil,
            replacementLogicalAt: nil,
            oldNilAt: 0.90,
            replacementNilAt: 0.55,
            expectedEventsAfterLogicalSamples: [],
            expectedFinalEvents: [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ]
        )
    }

    func testMergeTrueLogicalDrainsReplacementLogicalBeforeOldLogical() {
        assertCustomToCustomReplacement(
            label: "merge true logical",
            replacementShouldMerge: true,
            oldLogicalAt: 0.45,
            replacementLogicalAt: 0.40,
            oldNilAt: 0.95,
            replacementNilAt: 0.75,
            expectedEventsAfterLogicalSamples: [
                "replacement logical",
                "old logical",
            ],
            expectedFinalEvents: [
                "replacement logical",
                "old logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    func testMergeFalseNilGroupsBothGenerationsAtReplacementNil() {
        assertCustomToCustomReplacement(
            label: "merge false nil",
            replacementShouldMerge: false,
            oldLogicalAt: nil,
            replacementLogicalAt: nil,
            oldNilAt: 0.90,
            replacementNilAt: 0.55,
            expectedEventsAfterLogicalSamples: [],
            expectedFinalEvents: [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ]
        )
    }

    func testMergeFalseReplacementNilStopsOldSideEffectSamplingBeforeOldNil() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0.0)
        )
        let oldNilAt: TimeInterval = 1.40
        let replacementNilAt: TimeInterval = 0.45
        XCTAssertEqual(harness.currentValue().opacity, 0.0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1.0),
            transaction: completionTransaction(
                animation: Animation(
                    CustomToCustomCriteriaAnimation(
                        role: "old",
                        logicalAt: nil,
                        nilAt: oldNilAt,
                        shouldMergeResult: true,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        sampleRunningAnimationBeforeRetarget(harness)
        sampleRecorder.removeAll()

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CustomToCustomCriteriaAnimation(
                        role: "replacement",
                        logicalAt: nil,
                        nilAt: replacementNilAt,
                        shouldMergeResult: false,
                        recorder: sampleRecorder
                    )
                ),
                label: "replacement",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        activateReplacementAnimation(harness)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "replacement" })
        sampleRecorder.removeAll()

        let replacementTerminalTime = replacementActivationTime +
            replacementNilAt +
            frameInterval * 2.0
        XCTAssertLessThan(replacementTerminalTime, oldNilAt)
        harness.setTime(replacementTerminalTime)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ]
        )

        sampleRecorder.removeAll()
        harness.setTime(replacementTerminalTime + frameInterval)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
        harness.flushCompletionActions()
        XCTAssertEqual(sampleRecorder.samples.map(\.label), [])
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ]
        )
    }

    func testMergeFalseOldSideEffectSamplerUsesNonPersistingStateSnapshot() {
        let recorder = CustomRetargetFrameRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0.0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0.0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1.0),
            transaction: Transaction(animation: Animation(
                CustomToCustomFrameAnimation(
                    role: "old",
                    nilAt: 1.40,
                    shouldMergeResult: true,
                    recorder: recorder
                )
            ))
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        sampleRunningAnimationBeforeRetarget(harness)
        recorder.removeAnimationSamples()

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: Transaction(animation: Animation(
                CustomToCustomFrameAnimation(
                    role: "replacement",
                    nilAt: 1.00,
                    shouldMergeResult: false,
                    recorder: recorder
                )
            ))
        )
        harness.finalizeTransactionBody()
        activateReplacementAnimation(harness)

        let oldFrames = recorder.events
            .filter { $0.kind == "animate" && $0.role == "old" }
            .map(\.frame)
        let replacementFrames = recorder.events
            .filter { $0.kind == "animate" && $0.role == "replacement" }
            .map(\.frame)
        let shouldMergeFrame = try? XCTUnwrap(
            recorder.events.last { $0.kind == "shouldMerge" && $0.role == "replacement" }?.frame
        )
        let snapshotFrame = shouldMergeFrame ?? -1

        XCTAssertGreaterThanOrEqual(
            oldFrames.filter { $0 == snapshotFrame }.count,
            2,
            "old side-effect samples should reuse the retarget-time state snapshot"
        )
        XCTAssertTrue(
            oldFrames.contains { $0 > snapshotFrame },
            "old presentation base layer should keep advancing its persisted state"
        )
        XCTAssertEqual(
            Array(replacementFrames.prefix(3)),
            [0, 1, 2],
            "replacement animation should start from a fresh state after shouldMerge(false)"
        )
    }

    func testMergeTrueReplacementReusesPreviousStateFrame() {
        let recorder = CustomRetargetFrameRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0.0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0.0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1.0),
            transaction: Transaction(animation: Animation(
                CustomToCustomFrameAnimation(
                    role: "old",
                    nilAt: 1.40,
                    shouldMergeResult: true,
                    recorder: recorder
                )
            ))
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        sampleRunningAnimationBeforeRetarget(harness)
        recorder.removeAnimationSamples()

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: Transaction(animation: Animation(
                CustomToCustomFrameAnimation(
                    role: "replacement",
                    nilAt: 1.00,
                    shouldMergeResult: true,
                    recorder: recorder
                )
            ))
        )
        harness.finalizeTransactionBody()
        activateReplacementAnimation(harness)

        let events = recorder.events
        guard let shouldMergeFrame = events
            .last(where: { $0.kind == "shouldMerge" && $0.role == "replacement" })?
            .frame
        else {
            XCTFail("replacement shouldMerge should record the previous frame state")
            return
        }

        let replacementFrames = events
            .filter { $0.kind == "animate" && $0.role == "replacement" }
            .map(\.frame)
        let oldFrames = events
            .filter { $0.kind == "animate" && $0.role == "old" }
            .map(\.frame)
        XCTAssertGreaterThanOrEqual(
            shouldMergeFrame,
            2,
            "replacement shouldMerge should observe already-advanced state"
        )
        XCTAssertEqual(
            Array(replacementFrames.prefix(3)),
            [shouldMergeFrame, shouldMergeFrame + 1, shouldMergeFrame + 2],
            "replacement animation should continue the previous state after shouldMerge(true)"
        )
        XCTAssertGreaterThanOrEqual(
            oldFrames.filter { $0 == shouldMergeFrame }.count,
            2,
            "old side-effect samples should reuse the retarget-time state snapshot"
        )
    }

    func testMergeFalsePresentationBaseNilDoesNotFinishOldCompletionBeforeReplacementNil() {
        let completionRecorder = AnimationCompletionRecorder()
        let frameRecorder = CustomRetargetFrameGateRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0.0)
        )
        let replacementNilAt: TimeInterval = 1.00
        XCTAssertEqual(harness.currentValue().opacity, 0.0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1.0),
            transaction: completionTransaction(
                animation: Animation(
                    CustomToCustomFrameGateAnimation(
                        role: "old",
                        nilFrame: 4,
                        shouldMergeResult: true,
                        recorder: frameRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        sampleRunningAnimationBeforeRetarget(harness)
        frameRecorder.removeAll()

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CustomToCustomCriteriaAnimation(
                        role: "replacement",
                        logicalAt: nil,
                        nilAt: replacementNilAt,
                        shouldMergeResult: false,
                        recorder: sampleRecorder
                    )
                ),
                label: "replacement",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        activateReplacementAnimation(harness)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        for offset in [0.15, 0.30, 0.45, 0.60] {
            harness.setTime(replacementActivationTime + offset)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, [])
        }

        XCTAssertTrue(
            frameRecorder.events.contains { $0.role == "old" && $0.returnedNil },
            "old presentation base should hit its frame-gated nil before replacement nil"
        )

        harness.setTime(replacementActivationTime + replacementNilAt + frameInterval * 2.0)
        XCTAssertEqual(harness.currentValue().opacity, -0.5, accuracy: 0.001)
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "replacement removed",
                "replacement logical",
                "old logical",
            ]
        )
    }

    func testMergeFalseLogicalDrainsOldLogicalBeforeReplacementLogical() {
        assertCustomToCustomReplacement(
            label: "merge false logical",
            replacementShouldMerge: false,
            oldLogicalAt: 0.45,
            replacementLogicalAt: 0.40,
            oldNilAt: 0.95,
            replacementNilAt: 0.75,
            expectedEventsAfterLogicalSamples: [
                "old logical",
                "replacement logical",
            ],
            expectedFinalEvents: [
                "old logical",
                "replacement logical",
                "old removed",
                "replacement removed",
            ]
        )
    }

    private let retargetTime: TimeInterval = 0.20
    private let frameInterval: TimeInterval = 1.0 / 60.0
    private var replacementActivationTime: TimeInterval {
        retargetTime + frameInterval
    }
    private var mergedRouteBeginTime: TimeInterval {
        retargetTime - frameInterval * 2.0
    }

    private func assertCustomToCustomReplacement(
        label: String,
        replacementShouldMerge: Bool,
        oldLogicalAt: TimeInterval?,
        replacementLogicalAt: TimeInterval?,
        oldNilAt: TimeInterval,
        replacementNilAt: TimeInterval,
        expectedEventsAfterLogicalSamples: [String],
        expectedFinalEvents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0.0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0.0, accuracy: 0.000_001, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 1.0),
            transaction: completionTransaction(
                animation: Animation(
                    CustomToCustomCriteriaAnimation(
                        role: "old",
                        logicalAt: oldLogicalAt,
                        nilAt: oldNilAt,
                        shouldMergeResult: true,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)

        sampleRunningAnimationBeforeRetarget(harness)
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)
        sampleRecorder.removeAll()

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CustomToCustomCriteriaAnimation(
                        role: "replacement",
                        logicalAt: replacementLogicalAt,
                        nilAt: replacementNilAt,
                        shouldMergeResult: replacementShouldMerge,
                        recorder: sampleRecorder
                    )
                ),
                label: "replacement",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        activateReplacementAnimation(harness)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0, label, file: file, line: line)

        if oldLogicalAt != nil || replacementLogicalAt != nil {
            let firstLogicalTime = logicalSampleTime(
                replacementShouldMerge: replacementShouldMerge,
                oldLogicalAt: oldLogicalAt,
                replacementLogicalAt: replacementLogicalAt
            )
            harness.setTime(firstLogicalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()

            let secondLogicalTime = secondLogicalSampleTime(
                replacementShouldMerge: replacementShouldMerge,
                oldLogicalAt: oldLogicalAt,
                replacementLogicalAt: replacementLogicalAt
            )
            harness.setTime(secondLogicalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
        }
        XCTAssertEqual(
            completionRecorder.events,
            expectedEventsAfterLogicalSamples,
            label,
            file: file,
            line: line
        )

        harness.setTime(
            finalSampleTime(
                replacementShouldMerge: replacementShouldMerge,
                oldNilAt: oldNilAt,
                replacementNilAt: replacementNilAt
            )
        )
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, expectedFinalEvents, label, file: file, line: line)
    }

    private func sampleRunningAnimationBeforeRetarget(
        _ harness: AnimatableAttributeHarness
    ) {
        harness.setTime(retargetTime / 2.0)
        _ = harness.currentValue()
        harness.setTime(retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
    }

    private func activateReplacementAnimation(
        _ harness: AnimatableAttributeHarness
    ) {
        harness.setTime(replacementActivationTime)
        _ = harness.currentValue()
        harness.setTime(replacementActivationTime + frameInterval)
        _ = harness.currentValue()
        harness.setTime(replacementActivationTime + frameInterval * 2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
    }

    private func logicalSampleTime(
        replacementShouldMerge: Bool,
        oldLogicalAt: TimeInterval?,
        replacementLogicalAt: TimeInterval?
    ) -> TimeInterval {
        let oldTime = oldLogicalAt.map { mergedRouteBeginTime + $0 + frameInterval } ?? .infinity
        let replacementTime = replacementLogicalAt.map {
            (replacementShouldMerge ? mergedRouteBeginTime + $0 : replacementActivationTime + $0) +
                frameInterval
        } ?? .infinity
        return min(oldTime, replacementTime)
    }

    private func secondLogicalSampleTime(
        replacementShouldMerge: Bool,
        oldLogicalAt: TimeInterval?,
        replacementLogicalAt: TimeInterval?
    ) -> TimeInterval {
        let oldTime = oldLogicalAt.map { mergedRouteBeginTime + $0 + frameInterval } ?? -.infinity
        let replacementTime = replacementLogicalAt.map {
            (replacementShouldMerge ? mergedRouteBeginTime + $0 : replacementActivationTime + $0) +
                frameInterval
        } ?? -.infinity
        return max(oldTime, replacementTime)
    }

    private func finalSampleTime(
        replacementShouldMerge: Bool,
        oldNilAt: TimeInterval,
        replacementNilAt: TimeInterval
    ) -> TimeInterval {
        let replacementTime =
            (replacementShouldMerge ? mergedRouteBeginTime + replacementNilAt : replacementActivationTime + replacementNilAt) +
            frameInterval
        if replacementShouldMerge {
            return replacementTime
        }
        return max(replacementTime, oldNilAt + frameInterval)
    }
}

private struct CustomToCustomCriteriaAnimation: CustomAnimation {
    var role: String
    var logicalAt: TimeInterval?
    var nilAt: TimeInterval
    var shouldMergeResult: Bool
    var recorder: CustomRetargetSampleRecorder

    static func == (
        lhs: CustomToCustomCriteriaAnimation,
        rhs: CustomToCustomCriteriaAnimation
    ) -> Bool {
        lhs.role == rhs.role &&
            lhs.logicalAt == rhs.logicalAt &&
            lhs.nilAt == rhs.nilAt &&
            lhs.shouldMergeResult == rhs.shouldMergeResult
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(role)
        hasher.combine(logicalAt)
        hasher.combine(nilAt)
        hasher.combine(shouldMergeResult)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        if let logicalAt, time >= logicalAt {
            context.isLogicallyComplete = true
        }
        recorder.recordSample(label: role, time: time, input: doubleValue(value))
        guard time < nilAt else {
            return nil
        }
        var output = value
        output.scale(by: max(time / nilAt, 0))
        return output
    }

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        _ = previous
        _ = value
        _ = time
        _ = context
        recorder.recordShouldMerge()
        return shouldMergeResult
    }

    private func doubleValue<Value>(_ value: Value) -> Double where Value: VectorArithmetic {
        (value as? Double) ?? value.magnitudeSquared.squareRoot()
    }
}

private struct CustomToCustomFrameKey: AnimationStateKey {
    static let defaultValue = 0
}

private struct CustomToCustomFrameGateKey: AnimationStateKey {
    static let defaultValue = 0
}

private final class CustomRetargetFrameRecorder: @unchecked Sendable {
    struct Event: Equatable {
        var kind: String
        var role: String
        var frame: Int
    }

    private let lock = NSLock()
    private var storage: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(kind: String, role: String, frame: Int) {
        lock.lock()
        storage.append(Event(kind: kind, role: role, frame: frame))
        lock.unlock()
    }

    func removeAnimationSamples() {
        lock.lock()
        storage.removeAll { $0.kind == "animate" }
        lock.unlock()
    }
}

private final class CustomRetargetFrameGateRecorder: @unchecked Sendable {
    struct Event: Equatable {
        var role: String
        var frame: Int
        var returnedNil: Bool
    }

    private let lock = NSLock()
    private var storage: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(role: String, frame: Int, returnedNil: Bool) {
        lock.lock()
        storage.append(Event(role: role, frame: frame, returnedNil: returnedNil))
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

private struct CustomToCustomFrameAnimation: CustomAnimation {
    var role: String
    var nilAt: TimeInterval
    var shouldMergeResult: Bool
    var recorder: CustomRetargetFrameRecorder

    static func == (
        lhs: CustomToCustomFrameAnimation,
        rhs: CustomToCustomFrameAnimation
    ) -> Bool {
        lhs.role == rhs.role &&
            lhs.nilAt == rhs.nilAt &&
            lhs.shouldMergeResult == rhs.shouldMergeResult
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(role)
        hasher.combine(nilAt)
        hasher.combine(shouldMergeResult)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        let frame = context.state[CustomToCustomFrameKey.self]
        recorder.record(kind: "animate", role: role, frame: frame)
        context.state[CustomToCustomFrameKey.self] = frame + 1
        guard time < nilAt else {
            context.isLogicallyComplete = true
            return nil
        }

        var output = value
        output.scale(by: max(time / nilAt, 0))
        return output
    }

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        _ = previous
        _ = value
        _ = time
        recorder.record(
            kind: "shouldMerge",
            role: role,
            frame: context.state[CustomToCustomFrameKey.self]
        )
        return shouldMergeResult
    }
}

private struct CustomToCustomFrameGateAnimation: CustomAnimation {
    var role: String
    var nilFrame: Int
    var shouldMergeResult: Bool
    var recorder: CustomRetargetFrameGateRecorder

    static func == (
        lhs: CustomToCustomFrameGateAnimation,
        rhs: CustomToCustomFrameGateAnimation
    ) -> Bool {
        lhs.role == rhs.role &&
            lhs.nilFrame == rhs.nilFrame &&
            lhs.shouldMergeResult == rhs.shouldMergeResult
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(role)
        hasher.combine(nilFrame)
        hasher.combine(shouldMergeResult)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        _ = time
        let frame = context.state[CustomToCustomFrameGateKey.self]
        let reachedNil = frame >= nilFrame
        recorder.record(role: role, frame: frame, returnedNil: reachedNil)
        context.state[CustomToCustomFrameGateKey.self] = frame + 1
        guard !reachedNil else {
            context.isLogicallyComplete = true
            return nil
        }

        var output = value
        output.scale(by: 0.5)
        return output
    }

    nonisolated func shouldMerge<Value>(
        previous: Animation,
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Bool where Value: VectorArithmetic {
        _ = previous
        _ = value
        _ = time
        _ = context
        return shouldMergeResult
    }
}
