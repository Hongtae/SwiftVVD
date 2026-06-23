import XCTest
@testable import VUI

final class AnimatableAttributeTerminalCompletionTests: XCTestCase {
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

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.setTime(1.6)
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

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let sampledOpacity = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(sampledOpacity, 0)
        XCTAssertLessThan(sampledOpacity, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active logical"])

        completionRecorder.removeAll()
        harness.setTime(5.0)
        _ = harness.currentValue()
        harness.setTime(5.1)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])

        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])
    }

    func testPhaseResetAfterLogicalDrainFinishesOnlyRemainingRemoved() {
        let completionRecorder = AnimationCompletionRecorder()
        let harness = makeStartedLogicalSplitHarness(recorder: completionRecorder)

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active logical"])

        completionRecorder.removeAll()
        harness.bumpPhaseResetSeed()
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])

        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])
    }

    func testPhaseResetBeforeLogicalDrainFinishesRemovedBeforeLogicalOnce() {
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

        harness.setTime(0.2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.bumpPhaseResetSeed()
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
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
        let harness = makeStartedLogicalSplitHarness(recorder: completionRecorder)

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active logical"])

        completionRecorder.removeAll()
        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])

        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])
    }

    func testNodeRemovalBeforeLogicalDrainFinishesRemovedBeforeLogicalOnce() {
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

        harness.setTime(0.2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])

        harness.invalidateAnimatableSubgraph()
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

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
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

        harness.setTime(5.0)
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])

        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["active removed"])
    }

    func testNoAnimationRetargetBeforeLogicalDrainFinishesRemovedBeforeLogicalOnce() {
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

        harness.setTime(0.2)
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

        harness.setTime(5.0)
        _ = harness.currentValue()
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

    private func makeStartedLogicalSplitHarness(
        recorder completionRecorder: AnimationCompletionRecorder
    ) -> AnimatableAttributeHarness {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 1).logicallyComplete(after: 0.05),
                label: "active",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(completionRecorder.events, [])
        return harness
    }
}
