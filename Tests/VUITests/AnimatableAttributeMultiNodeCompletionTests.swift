import XCTest
@testable import VUI

final class AnimatableAttributeMultiNodeCompletionTests: XCTestCase {
    func testSharedObserverWithChildInjectedAnimationsWaitsForSlowestNode() {
        let recorder = AnimationCompletionRecorder()
        let harness = DualAnimatableAttributeHarness(
            firstInitialValue: _OpacityEffect(opacity: 0),
            secondInitialValue: _OpacityEffect(opacity: 0)
        )
        let (fastTransaction, slowTransaction) = sharedCompletionTransactions(
            firstAnimation: .linear(duration: 0.20),
            secondAnimation: .linear(duration: 0.50),
            recorder: recorder
        )

        start(
            harness,
            firstTransaction: fastTransaction,
            secondTransaction: slowTransaction
        )

        harness.setTime(0.30)
        _ = harness.currentFirstValue()
        _ = harness.currentSecondValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.65)
        _ = harness.currentFirstValue()
        _ = harness.currentSecondValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "shared removed",
                "shared logical",
            ]
        )
    }

    func testSharedObserverWithChildInjectedSplitCriteriaWaitsPerCriteria() {
        let recorder = AnimationCompletionRecorder()
        let harness = DualAnimatableAttributeHarness(
            firstInitialValue: _OpacityEffect(opacity: 0),
            secondInitialValue: _OpacityEffect(opacity: 0)
        )
        let fluidAnimation = Animation.spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
        let (fastTransaction, fluidTransaction) = sharedCompletionTransactions(
            firstAnimation: .linear(duration: 0.20),
            secondAnimation: fluidAnimation,
            recorder: recorder
        )

        start(
            harness,
            firstTransaction: fastTransaction,
            secondTransaction: fluidTransaction
        )

        let frameInterval = fluidAnimation.box.defaultDisplayFrameInterval
        var sampleTime = frameInterval
        var didObserveFastSnap = false
        while sampleTime <= fluidAnimation.box.duration + 0.50,
              recorder.events.isEmpty {
            harness.setTime(sampleTime)
            let firstValue = harness.currentFirstValue()
            _ = harness.currentSecondValue()
            if firstValue.opacity == 1.0 {
                didObserveFastSnap = true
            }
            harness.flushCompletionActions()
            sampleTime += frameInterval
        }
        XCTAssertTrue(didObserveFastSnap)
        XCTAssertEqual(recorder.events, ["shared logical"])

        var didObserveFluidSnap = false
        let finalSampleTime = fluidAnimation.box.presentationDuration(for: Double(1.0)) + 1.0
        while sampleTime <= finalSampleTime && recorder.events == ["shared logical"] {
            harness.setTime(sampleTime)
            _ = harness.currentFirstValue()
            let secondValue = harness.currentSecondValue()
            if secondValue.opacity == 1.0 {
                didObserveFluidSnap = true
            }
            harness.flushCompletionActions()
            sampleTime += frameInterval
        }
        XCTAssertTrue(didObserveFluidSnap)
        XCTAssertEqual(
            recorder.events,
            [
                "shared logical",
                "shared removed",
            ]
        )
    }

    func testSharedObserverWithNilAndFastChildWaitsForRegisteredFastToken() {
        let recorder = AnimationCompletionRecorder()
        let harness = DualAnimatableAttributeHarness(
            firstInitialValue: _OpacityEffect(opacity: 0),
            secondInitialValue: _OpacityEffect(opacity: 0)
        )
        let (nilTransaction, fastTransaction) = sharedCompletionTransactions(
            parentAnimation: .linear(duration: 0.80),
            firstAnimation: nil,
            secondAnimation: .linear(duration: 0.20),
            recorder: recorder
        )

        start(
            harness,
            firstTransaction: nilTransaction,
            secondTransaction: fastTransaction,
            expectedFirstAfterStart: 1
        )

        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.30)
        _ = harness.currentFirstValue()
        _ = harness.currentSecondValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "shared removed",
                "shared logical",
            ]
        )
    }

    func testSharedObserverWithParentAnimationAndChildOverrideWaitsForParentNode() {
        let recorder = AnimationCompletionRecorder()
        let harness = DualAnimatableAttributeHarness(
            firstInitialValue: _OpacityEffect(opacity: 0),
            secondInitialValue: _OpacityEffect(opacity: 0)
        )
        let parent = sharedCompletionTransaction(
            animation: .linear(duration: 0.80),
            recorder: recorder
        )
        var childOverride = parent
        childOverride.animation = .linear(duration: 0.20)

        start(
            harness,
            firstTransaction: childOverride,
            secondTransaction: parent
        )

        harness.setTime(0.30)
        _ = harness.currentFirstValue()
        _ = harness.currentSecondValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.95)
        _ = harness.currentFirstValue()
        _ = harness.currentSecondValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "shared removed",
                "shared logical",
            ]
        )
    }

    func testSharedObserverWithDisabledParentKeepsParentTimingOwner() {
        let recorder = AnimationCompletionRecorder()
        let harness = DualAnimatableAttributeHarness(
            firstInitialValue: _OpacityEffect(opacity: 0),
            secondInitialValue: _OpacityEffect(opacity: 0)
        )
        var parent = sharedCompletionTransaction(
            animation: .linear(duration: 0.80),
            recorder: recorder
        )
        parent.disablesAnimations = true
        var child = parent
        child.animation = .linear(duration: 0.20)

        start(
            harness,
            firstTransaction: child,
            secondTransaction: parent
        )

        harness.setTime(0.30)
        _ = harness.currentFirstValue()
        _ = harness.currentSecondValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.95)
        _ = harness.currentFirstValue()
        _ = harness.currentSecondValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "shared removed",
                "shared logical",
            ]
        )
    }

    private func start(
        _ harness: DualAnimatableAttributeHarness,
        firstTransaction: Transaction,
        secondTransaction: Transaction,
        expectedFirstAfterStart: Double = 0,
        expectedSecondAfterStart: Double = 0
    ) {
        XCTAssertEqual(harness.currentFirstValue().opacity, 0)
        XCTAssertEqual(harness.currentSecondValue().opacity, 0)
        harness.setFirst(_OpacityEffect(opacity: 1), transaction: firstTransaction)
        harness.setSecond(_OpacityEffect(opacity: 1), transaction: secondTransaction)
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentFirstValue().opacity, expectedFirstAfterStart)
        XCTAssertEqual(harness.currentSecondValue().opacity, expectedSecondAfterStart)
        harness.flushCompletionActions()
    }

    private func sharedCompletionTransactions(
        parentAnimation: Animation? = nil,
        firstAnimation: Animation?,
        secondAnimation: Animation?,
        recorder: AnimationCompletionRecorder
    ) -> (Transaction, Transaction) {
        let parent = sharedCompletionTransaction(
            animation: parentAnimation,
            recorder: recorder
        )
        var first = parent
        first.animation = firstAnimation
        var second = parent
        second.animation = secondAnimation
        return (first, second)
    }

    private func sharedCompletionTransaction(
        animation: Animation?,
        recorder: AnimationCompletionRecorder
    ) -> Transaction {
        completionTransaction(
            animation: animation,
            label: "shared",
            recorder: recorder
        )
    }
}
