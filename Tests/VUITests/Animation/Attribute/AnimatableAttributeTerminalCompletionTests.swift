import XCTest
@testable import VUI

private final class TerminalOwnedAnimationBox: AnimationBoxBase, @unchecked Sendable {
    override var duration: TimeInterval {
        1
    }

    override func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        if time >= 2 {
            return nil
        }
        if time >= duration {
            context.isLogicallyComplete = true
        }
        var output = value
        output.scale(by: max(time / duration, 0))
        return output
    }
}

final class AnimatableAttributeTerminalCompletionTests: XCTestCase {
    func testFreshLogicalActivationUsesAnimateTerminal() {
        let box = TerminalOwnedAnimationBox()
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        var transaction = Transaction(animation: Animation(box: box))
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            completionRecorder.record("logical")
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        XCTAssertEqual(completionRecorder.events, [])
    }

    func testRetargetAfterLogicalDrainUsesAnimateTerminal() {
        let box = TerminalOwnedAnimationBox()
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        var firstTransaction = Transaction(animation: Animation(box: box))
        firstTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            completionRecorder.record("first logical")
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: firstTransaction
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.advanceTime(to: 1.1)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["first logical"])

        var replacementTransaction = Transaction(animation: Animation(box: box))
        replacementTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            completionRecorder.record("replacement logical")
        }
        harness.setSource(
            _OpacityEffect(opacity: 0.25),
            transaction: replacementTransaction
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        XCTAssertEqual(completionRecorder.events, ["first logical"])
    }

    func testFiniteActiveCompletionDrainsSameBoundaryRemovedBeforeLogicalOnce() {
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: .linear(duration: 1),
                label: "terminal",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(completionRecorder.events, [])

        harness.advanceTime(to: 0.5)
        _ = harness.currentValue()
        harness.advanceTime(to: 0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.advanceTime(to: 1.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "terminal removed",
                "terminal logical",
            ]
        )

        harness.advanceTime(to: 2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "terminal removed",
                "terminal logical",
            ]
        )

        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "terminal removed",
                "terminal logical",
            ]
        )
    }

    func testRemovedDeadlineFinishesAfterEarlierLogicalDrain() {
        let completionRecorder = AnimationCompletionRecorder()
        let harness = makeStartedLogicalSplitHarness(recorder: completionRecorder)

        harness.advanceTime(to: 0.5)
        _ = harness.currentValue()
        harness.advanceTime(to: 0.6)
        let sampledOpacity = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(sampledOpacity, 0)
        XCTAssertLessThan(sampledOpacity, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active logical"])

        completionRecorder.removeAll()
        harness.advanceTime(to: 5.0)
        _ = harness.currentValue()
        harness.advanceTime(to: 5.1)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])

        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])
    }

    func testPhaseResetAfterLogicalDrainFinishesOnlyRemainingRemoved() {
        let completionRecorder = AnimationCompletionRecorder()
        let reason: UInt32 = 0xCD2
        let harness = makeStartedLogicalSplitHarness(
            recorder: completionRecorder,
            frameInterval: 1.0 / 30.0,
            reason: reason
        )

        harness.advanceTime(to: 0.5)
        _ = harness.currentValue()
        harness.advanceTime(to: 0.6)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [reason])
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active logical"])

        completionRecorder.removeAll()
        harness.resetNextUpdate()
        harness.bumpPhaseResetSeed()
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])

        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])
    }

    func testPhaseResetBeforeLogicalDrainFinishesRemovedBeforeLogicalOnce() {
        let completionRecorder = AnimationCompletionRecorder()
        let reason: UInt32 = 0xCD4
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        var transaction = completionTransaction(
            animation: Animation.linear(duration: 1).logicallyComplete(after: 0.8),
            label: "active",
            recorder: completionRecorder
        )
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = reason
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(completionRecorder.events, [])

        harness.advanceTime(to: 0.2)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [reason])
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.resetNextUpdate()
        harness.bumpPhaseResetSeed()
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "active removed",
                "active logical",
            ]
        )

        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "active removed",
                "active logical",
            ]
        )
    }

    func testNodeRemovalAfterLogicalDrainFinishesOnlyRemainingRemoved() {
        let completionRecorder = AnimationCompletionRecorder()
        let reason: UInt32 = 0xCD3
        let harness = makeStartedLogicalSplitHarness(
            recorder: completionRecorder,
            frameInterval: 1.0 / 30.0,
            reason: reason
        )

        harness.advanceTime(to: 0.5)
        _ = harness.currentValue()
        harness.advanceTime(to: 0.6)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [reason])
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active logical"])

        completionRecorder.removeAll()
        harness.resetNextUpdate()
        harness.invalidateAnimatableSubgraph()
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])

        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])
    }

    func testNodeRemovalBeforeLogicalDrainFinishesRemovedBeforeLogicalOnce() {
        let completionRecorder = AnimationCompletionRecorder()
        let reason: UInt32 = 0xCD5
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        var transaction = completionTransaction(
            animation: Animation.linear(duration: 1).logicallyComplete(after: 0.8),
            label: "active",
            recorder: completionRecorder
        )
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = reason
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(completionRecorder.events, [])

        harness.advanceTime(to: 0.2)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [reason])
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.resetNextUpdate()
        harness.invalidateAnimatableSubgraph()
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "active removed",
                "active logical",
            ]
        )

        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "active removed",
                "active logical",
            ]
        )
    }

    func testNoAnimationRetargetAfterLogicalDrainFinishesOnlyRemainingRemoved() {
        let completionRecorder = AnimationCompletionRecorder()
        let harness = makeStartedLogicalSplitHarness(recorder: completionRecorder)

        harness.advanceTime(to: 0.5)
        _ = harness.currentValue()
        harness.advanceTime(to: 0.6)
        let beforeRetarget = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(beforeRetarget, 0)
        XCTAssertLessThan(beforeRetarget, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active logical"])

        completionRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: Transaction(animation: nil)
        )
        harness.finalizeTransactionBody()
        let afterRetarget = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(afterRetarget, beforeRetarget)
        XCTAssertLessThan(afterRetarget, 2)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.advanceTime(to: 5.0)
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])

        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])
    }

    func testNoAnimationRetargetBeforeLogicalDrainKeepsSplitLogicalBeforeRemoved() {
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 1).logicallyComplete(after: 0.8),
                label: "active",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(completionRecorder.events, [])

        harness.advanceTime(to: 0.4)
        _ = harness.currentValue()
        harness.advanceTime(to: 0.6)
        let beforeRetarget = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(beforeRetarget, 0)
        XCTAssertLessThan(beforeRetarget, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: Transaction(animation: nil)
        )
        harness.finalizeTransactionBody()
        let afterRetarget = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(afterRetarget, beforeRetarget)
        XCTAssertLessThan(afterRetarget, 2)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.advanceTime(to: 1.25)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "active logical",
                "active removed",
            ]
        )

        completionRecorder.removeAll()
        harness.advanceTime(to: 2.05)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])
    }

    func testNoAnimationRetargetOwnCompletionFallsBackWhileOldRecordsStayPending() {
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 1).logicallyComplete(after: 0.8),
                label: "active",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(completionRecorder.events, [])

        harness.advanceTime(to: 0.4)
        _ = harness.currentValue()
        harness.advanceTime(to: 0.6)
        let beforeRetarget = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(beforeRetarget, 0)
        XCTAssertLessThan(beforeRetarget, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        let nilTransaction = completionTransaction(
            animation: nil,
            label: "nil",
            recorder: completionRecorder
        )
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 2))
        }
        let afterRetarget = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(afterRetarget, beforeRetarget)
        XCTAssertLessThan(afterRetarget, 2)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
            ]
        )

        completionRecorder.removeAll()
        harness.advanceTime(to: 1.25)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "active logical",
                "active removed",
            ]
        )

        completionRecorder.removeAll()
        harness.advanceTime(to: 2.05)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])
    }

    func testNoAnimationRetargetPreservesSampledResidualFamilyUntilTerminalOutput() {
        assertNoAnimationRetargetPreservesTerminalOutputBeforeCallbacks(
            label: "fluid",
            animation: .spring(response: 0.35, dampingFraction: 0.70, blendDuration: 0)
        )
        assertNoAnimationRetargetPreservesTerminalOutputBeforeCallbacks(
            label: "spring",
            animation: .interpolatingSpring(
                mass: 1.0,
                stiffness: 50,
                damping: 5,
                initialVelocity: 0
            )
        )
        assertNoAnimationRetargetPreservesTerminalOutputBeforeCallbacks(
            label: "default",
            animation: .default
        )
        assertNoAnimationRetargetPreservesTerminalOutputBeforeCallbacks(
            label: "wrapped fluid",
            animation: Animation
                .spring(response: 0.35, dampingFraction: 0.70, blendDuration: 0)
                .delay(0.20)
        )
    }

    private func makeStartedLogicalSplitHarness(
        recorder completionRecorder: AnimationCompletionRecorder,
        frameInterval: Double? = nil,
        reason: UInt32? = nil
    ) -> AnimatableAttributeHarness {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        var transaction = completionTransaction(
            animation: Animation.linear(duration: 1).logicallyComplete(after: 0.05),
            label: "active",
            recorder: completionRecorder
        )
        if let frameInterval {
            transaction.animationFrameInterval = frameInterval
        }
        if let reason {
            transaction.animationReason = reason
        }
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(completionRecorder.events, [])
        return harness
    }

    private func assertNoAnimationRetargetPreservesTerminalOutputBeforeCallbacks(
        label: String,
        animation: Animation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: animation,
                label: label,
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)

        harness.advanceTime(to: 0.05)
        _ = harness.currentValue()
        harness.advanceTime(to: 0.12)
        let beforeRetarget = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(beforeRetarget, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(beforeRetarget, 1, file: file, line: line)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: Transaction(animation: nil)
        )
        harness.finalizeTransactionBody()
        let afterRetarget = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(afterRetarget, beforeRetarget, file: file, line: line)
        XCTAssertLessThan(afterRetarget, 2, file: file, line: line)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)

        harness.advanceTime(to: 5.0)
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001, file: file, line: line)
        harness.flushCompletionActions()
        XCTAssertEqual(
            Set(completionRecorder.events),
            Set(["\(label) removed", "\(label) logical"]),
            file: file,
            line: line
        )
    }
}
