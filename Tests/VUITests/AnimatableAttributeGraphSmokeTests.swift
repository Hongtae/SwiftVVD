import XCTest
@testable import VUI
final class AnimatableAttributeGraphSmokeTests: XCTestCase {
    func testMakeAnimatableInstallsStatefulRule() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            animation: .linear(duration: 1)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.6)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0)
        harness.setTime(4.0)
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
    }

    func testAnimatorStatePendingFirstSecondPhaseSkipsMiddleSample() {
        let sampleRecorder = AnimationCompletionRecorder()
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        let transaction = completionTransaction(
            animation: Animation(
                RecordingUnitAnimation(
                    label: "phase",
                    duration: 1,
                    recorder: sampleRecorder
                )
            ),
            label: "phase",
            recorder: completionRecorder
        )
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        XCTAssertEqual(sampleRecorder.events, ["phase animate"])

        harness.setTime(0.5)
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        XCTAssertEqual(sampleRecorder.events, ["phase animate"])

        harness.setTime(0.6)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0)
        XCTAssertEqual(sampleRecorder.events, ["phase animate", "phase animate"])
    }

    func testAnimatorStateNextUpdateUsesTransactionFrameIntervalAndReason() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA11
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA11])
    }

    func testAnimatorStateRetargetRefreshesNextUpdateFrameIntervalAndReason() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        var initialTransaction = Transaction(animation: .linear(duration: 1))
        initialTransaction.animationFrameInterval = 1.0 / 30.0
        initialTransaction.animationReason = 0xA11
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: initialTransaction
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let runningValue = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(runningValue, 0)
        XCTAssertLessThan(runningValue, 1)

        harness.resetNextUpdate()
        var retargetTransaction = Transaction(animation: .linear(duration: 1))
        retargetTransaction.animationFrameInterval = 1.0 / 120.0
        retargetTransaction.animationReason = 0xB22
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: retargetTransaction
        )
        _ = harness.currentValue()

        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 120.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xB22])
    }

    func testNoChangeAnimatedTransactionSkipsRetargetRegistrationAndContinuesActiveSampling() {
        let listener = CountingAnimationListener()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            animation: .linear(duration: 1)
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let runningValue = harness.currentValue().opacity
        XCTAssertGreaterThan(runningValue, 0)
        XCTAssertLessThan(runningValue, 1)

        var sameTargetTransaction = Transaction(animation: .linear(duration: 1))
        sameTargetTransaction.animationListener = listener
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: sameTargetTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
        harness.setTime(2.0)
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
    }

    func testActiveNoChangePayloadContinuesExistingSchedulingWithoutRetargetRegistration() {
        let listener = CountingAnimationListener()
        let harness = GenericAnimatableAttributeHarness(
            initialValue: NonAnimatablePayload(id: 1, animatableData: 0)
        )
        XCTAssertEqual(harness.currentValue().animatableData, 0, accuracy: 0.000_001)

        var initialTransaction = Transaction(animation: .linear(duration: 1))
        initialTransaction.animationFrameInterval = 1.0 / 30.0
        initialTransaction.animationReason = 0xC11
        harness.setSource(
            NonAnimatablePayload(id: 2, animatableData: 1),
            transaction: initialTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().animatableData, 0, accuracy: 0.000_001)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let runningValue = harness.currentValue().animatableData
        XCTAssertGreaterThan(runningValue, 0)
        XCTAssertLessThan(runningValue, 1)

        harness.resetNextUpdate()
        var sameTargetTransaction = Transaction(animation: .linear(duration: 1))
        sameTargetTransaction.animationFrameInterval = 1.0 / 120.0
        sameTargetTransaction.animationReason = 0xC22
        sameTargetTransaction.animationListener = listener
        harness.setSource(
            NonAnimatablePayload(id: 3, animatableData: 1),
            transaction: sameTargetTransaction
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.7)
        _ = harness.currentValue()

        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xC11])
    }

    func testInactiveNoChangeRetainsCachedStatefulOutput() {
        let listener = CountingAnimationListener()
        let harness = GenericAnimatableAttributeHarness(
            initialValue: NonAnimatablePayload(id: 1, animatableData: 0.25)
        )
        XCTAssertEqual(harness.currentValue().id, 1)

        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = listener
        harness.setSource(
            NonAnimatablePayload(id: 2, animatableData: 0.25),
            transaction: transaction
        )

        let output = harness.currentValue()
        XCTAssertEqual(output.id, 1)
        XCTAssertEqual(output.animatableData, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(listener.addedCount, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(listener.removedCount, 0)
    }

    func testMakeAnimatableFrameInstallsCachedFrameLane() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: CGPoint(x: 1, y: 2),
            initialSize: ViewSize(width: 10, height: 20)
        )
        let cache = harness.cachedAnimatedFrame()
        XCTAssertEqual(cache.position.identifier, harness.rawPositionID)
        XCTAssertEqual(cache.size.identifier, harness.rawSizeID)
        XCTAssertEqual(cache.time.identifier, harness.timeID)
        XCTAssertEqual(cache.transaction.identifier, harness.transactionID)
        XCTAssertEqual(cache.viewPhase.identifier, harness.phaseID)
        XCTAssertEqual(cache.animatedFrame.identifier, harness.frameID)
        XCTAssertEqual(cache._animatedPosition?.identifier, harness.animatedPositionID)
        XCTAssertEqual(cache._animatedSize?.identifier, harness.animatedSizeID)
        XCTAssertNil(cache._animatedCGSize)
        let frame = harness.currentFrame()
        XCTAssertEqual(frame.origin.x, 1, accuracy: 0.000_001)
        XCTAssertEqual(frame.origin.y, 2, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.width, 10, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.height, 20, accuracy: 0.000_001)
    }
    func testAnimatableFrameAttributeAnimatesPositionAndSizeTogether() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        XCTAssertEqual(harness.currentPosition().x, 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.currentSize().width, 10, accuracy: 0.000_001)
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: Transaction(animation: .linear(duration: 1))
        )
        XCTAssertEqual(harness.currentPosition().x, 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.currentSize().width, 10, accuracy: 0.000_001)
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        let midFrame = harness.currentFrame()
        XCTAssertGreaterThan(midFrame.origin.x, 0)
        XCTAssertLessThan(midFrame.origin.x, 100)
        XCTAssertGreaterThan(midFrame.size.width, 10)
        XCTAssertLessThan(midFrame.size.width, 50)
        harness.setTime(4.0)
        let finalFrame = harness.currentFrame()
        XCTAssertEqual(finalFrame.origin.x, 100, accuracy: 0.000_001)
        XCTAssertEqual(finalFrame.origin.y, 40, accuracy: 0.000_001)
        XCTAssertEqual(finalFrame.size.width, 50, accuracy: 0.000_001)
        XCTAssertEqual(finalFrame.size.height, 60, accuracy: 0.000_001)
        XCTAssertEqual(harness.currentPosition().x, 100, accuracy: 0.000_001)
        XCTAssertEqual(harness.currentSize().width, 50, accuracy: 0.000_001)
    }

    func testAnimatableFrameAttributeNextUpdateUsesTransactionFrameIntervalAndReason() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)

        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xF11
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: transaction
        )

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xF11])
    }

    func testAnimatableFrameAttributeRetargetRefreshesNextUpdateFrameIntervalAndReason() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)

        var initialTransaction = Transaction(animation: .linear(duration: 1))
        initialTransaction.animationFrameInterval = 1.0 / 30.0
        initialTransaction.animationReason = 0xF11
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: initialTransaction
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        let runningFrame = harness.currentFrame()
        XCTAssertGreaterThanOrEqual(runningFrame.origin.x, 0)
        XCTAssertLessThan(runningFrame.origin.x, 100)

        harness.resetNextUpdate()
        var retargetTransaction = Transaction(animation: .linear(duration: 1))
        retargetTransaction.animationFrameInterval = 1.0 / 120.0
        retargetTransaction.animationReason = 0xF22
        harness.setFrame(
            position: CGPoint(x: 200, y: 80),
            size: ViewSize(width: 70, height: 90),
            transaction: retargetTransaction
        )
        _ = harness.currentFrame()

        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 120.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xF22])
    }

    func testAnimatableFrameAttributeNoChangeAnimatedTransactionSkipsListenerRegistration() {
        let listener = CountingAnimationListener()
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        _ = harness.currentFrame()
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: Transaction(animation: .linear(duration: 1))
        )
        _ = harness.currentFrame()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        let runningFrame = harness.currentFrame()
        XCTAssertGreaterThan(runningFrame.origin.x, 0)
        XCTAssertLessThan(runningFrame.origin.x, 100)

        var sameTargetTransaction = Transaction(animation: .linear(duration: 1))
        sameTargetTransaction.animationListener = listener
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: sameTargetTransaction
        )
        _ = harness.currentFrame()
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)

        harness.setTime(2.0)
        let finalFrame = harness.currentFrame()
        XCTAssertEqual(finalFrame.origin.x, 100, accuracy: 0.000_001)
        XCTAssertEqual(finalFrame.size.width, 50, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
    }

    func testAnimatableFrameAttributeSplitRawListenersDrainLogicalBeforeRemoved() {
        let recorder = AnimationCompletionRecorder()
        let removedListener = RecordingAnimationListener(
            label: "removed",
            recorder: recorder
        )
        let logicalListener = RecordingAnimationListener(
            label: "logical",
            recorder: recorder
        )
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        let sampleRecorder = CustomRetargetSampleRecorder()
        var transaction = Transaction(
            animation: Animation(
                RetargetBoundaryRecordingAnimation(
                    label: "frame",
                    logicalAt: 0.05,
                    nilAt: 1,
                    recorder: sampleRecorder
                )
            )
        )
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: transaction
        )
        _ = harness.currentFrame()
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ]
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.7)
        _ = harness.currentFrame()
        XCTAssertEqual(recorder.events, [])
        harness.setTime(0.8)
        _ = harness.currentFrame()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["logical removed"])

        harness.setTime(2.0)
        _ = harness.currentFrame()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ]
        )
    }
    func testAnimatableFrameAttributePhaseResetRemovesRawListenersInCriteriaOrder() {
        let recorder = AnimationCompletionRecorder()
        let removedListener = RecordingAnimationListener(
            label: "removed",
            recorder: recorder
        )
        let logicalListener = RecordingAnimationListener(
            label: "logical",
            recorder: recorder
        )
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: transaction
        )
        _ = harness.currentFrame()
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ]
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.bumpPhaseResetSeed()
        _ = harness.currentFrame()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
    }
    func testAnimatableFrameAttributeNoAnimationRetargetRemovesRawListenersInCriteriaOrder() {
        let recorder = AnimationCompletionRecorder()
        let removedListener = RecordingAnimationListener(
            label: "removed",
            recorder: recorder
        )
        let logicalListener = RecordingAnimationListener(
            label: "logical",
            recorder: recorder
        )
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: transaction
        )
        _ = harness.currentFrame()
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ]
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setFrame(
            position: CGPoint(x: 25, y: 15),
            size: ViewSize(width: 30, height: 35),
            transaction: Transaction(animation: nil)
        )
        let frame = harness.currentFrame()
        XCTAssertEqual(frame.origin.x, 25, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.width, 30, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
    }

    func testAnimatableFrameAttributeVFDNoAnimationRetargetRemovesRawListenersInCriteriaOrder() {
        let recorder = AnimationCompletionRecorder()
        let removedListener = RecordingAnimationListener(
            label: "removed",
            recorder: recorder
        )
        let logicalListener = RecordingAnimationListener(
            label: "logical",
            recorder: recorder
        )
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            supportsVFD: true
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        harness.setFrame(
            position: CGPoint(x: 1_000, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: transaction
        )
        _ = harness.currentFrame()
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ]
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        _ = harness.currentFrame()
        harness.setFrame(
            position: CGPoint(x: 25, y: 15),
            size: ViewSize(width: 30, height: 35),
            transaction: Transaction(animation: nil)
        )
        let frame = harness.currentFrame()
        XCTAssertEqual(frame.origin.x, 25, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.width, 30, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
    }

    func testAnimatableFrameAttributeVFDNextUpdateUsesTransactionFrameIntervalAndReason() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            supportsVFD: true
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)

        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xF31
        harness.setFrame(
            position: CGPoint(x: 10, y: 4),
            size: ViewSize(width: 12, height: 22),
            transaction: transaction
        )

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xF31])
    }

    func testAnimatableFrameAttributeVFDRetargetRefreshesNextUpdateFrameIntervalAndReason() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            supportsVFD: true
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)

        var initialTransaction = Transaction(animation: .linear(duration: 1))
        initialTransaction.animationFrameInterval = 1.0 / 30.0
        initialTransaction.animationReason = 0xF31
        harness.setFrame(
            position: CGPoint(x: 10, y: 4),
            size: ViewSize(width: 12, height: 22),
            transaction: initialTransaction
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        let runningFrame = harness.currentFrame()
        XCTAssertGreaterThanOrEqual(runningFrame.origin.x, 0)
        XCTAssertLessThan(runningFrame.origin.x, 10)

        harness.resetNextUpdate()
        var retargetTransaction = Transaction(animation: .linear(duration: 1))
        retargetTransaction.animationFrameInterval = 1.0 / 120.0
        retargetTransaction.animationReason = 0xF42
        harness.setFrame(
            position: CGPoint(x: 20, y: 8),
            size: ViewSize(width: 14, height: 24),
            transaction: retargetTransaction
        )
        _ = harness.currentFrame()

        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 120.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xF42])
    }

    func testAnimatableFrameAttributeVFDSchedulesHighFrameRateForFastFrameMotion() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            supportsVFD: true
        )
        _ = harness.currentFrame()
        harness.setFrame(
            position: CGPoint(x: 1_000, y: 0),
            size: ViewSize(width: 10, height: 20),
            transaction: Transaction(animation: .linear(duration: 1))
        )
        _ = harness.currentFrame()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        _ = harness.currentFrame()
        harness.setTime(0.7)
        _ = harness.currentFrame()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 120.0, accuracy: 0.000_001)
    }
    func testSharedTransactionCompletionWaitsForAllAnimatableAttributes() {
        let recorder = AnimationCompletionRecorder()
        let harness = DualAnimatableAttributeHarness(
            firstInitialValue: _OpacityEffect(opacity: 0),
            secondInitialValue: _OpacityEffect(opacity: 0)
        )
        let transaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "shared",
            recorder: recorder
        )
        XCTAssertEqual(harness.currentFirstValue().opacity, 0)
        XCTAssertEqual(harness.currentSecondValue().opacity, 0)
        harness.setFirst(_OpacityEffect(opacity: 1), transaction: transaction)
        harness.setSecond(_OpacityEffect(opacity: 1), transaction: transaction)
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentFirstValue().opacity, 0)
        XCTAssertEqual(harness.currentSecondValue().opacity, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setFirstTime(0.5)
        XCTAssertEqual(harness.currentFirstValue().opacity, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setFirstTime(1.6)
        let runningFirst = harness.currentFirstValue().opacity
        XCTAssertGreaterThan(runningFirst, 0)
        XCTAssertLessThan(runningFirst, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setFirstTime(2.7)
        XCTAssertEqual(harness.currentFirstValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setSecondTime(0.5)
        XCTAssertEqual(harness.currentSecondValue().opacity, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setSecondTime(1.6)
        let runningSecond = harness.currentSecondValue().opacity
        XCTAssertGreaterThan(runningSecond, 0)
        XCTAssertLessThan(runningSecond, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "shared removed",
                "shared logical",
            ]
        )
        harness.setSecondTime(2.7)
        XCTAssertEqual(harness.currentSecondValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "shared removed",
                "shared logical",
            ]
        )
    }

    func testSharedTransactionSplitCriteriaWaitsForSlowestNodePerCriteria() {
        let recorder = AnimationCompletionRecorder()
        let harness = DualAnimatableAttributeHarness(
            firstInitialValue: _OpacityEffect(opacity: 0),
            secondInitialValue: _OpacityEffect(opacity: 0)
        )
        let transaction = completionTransaction(
            animation: Animation.linear(duration: 1).logicallyComplete(after: 0.05),
            label: "shared",
            recorder: recorder
        )
        XCTAssertEqual(harness.currentFirstValue().opacity, 0)
        XCTAssertEqual(harness.currentSecondValue().opacity, 0)
        harness.setFirst(_OpacityEffect(opacity: 1), transaction: transaction)
        harness.setSecond(_OpacityEffect(opacity: 1), transaction: transaction)
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentFirstValue().opacity, 0)
        XCTAssertEqual(harness.currentSecondValue().opacity, 0)
        XCTAssertEqual(recorder.events, [])

        harness.setFirstTime(0.5)
        _ = harness.currentFirstValue()
        harness.setFirstTime(0.6)
        _ = harness.currentFirstValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSecondTime(0.5)
        _ = harness.currentSecondValue()
        harness.setSecondTime(0.6)
        _ = harness.currentSecondValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["shared logical"])

        harness.setFirstTime(5.0)
        _ = harness.currentFirstValue()
        harness.setFirstTime(5.1)
        _ = harness.currentFirstValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["shared logical"])

        harness.setSecondTime(5.0)
        _ = harness.currentSecondValue()
        harness.setSecondTime(5.1)
        _ = harness.currentSecondValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "shared logical",
                "shared removed",
            ]
        )
    }

    func testRegisteredTokenCompletionEntriesPreserveCriteriaGroupOrder() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("logical1")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("removed1")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("logical2")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("removed2")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("logical3")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("removed3")
        }

        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(_OpacityEffect(opacity: 1), transaction: transaction)
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed1",
                "removed2",
                "removed3",
                "logical1",
                "logical2",
                "logical3",
            ]
        )
    }

    func testRegisteredTokenSplitCriteriaEntriesPreserveBoundaryOrder() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(
            animation: Animation.linear(duration: 1).logicallyComplete(after: 0.05)
        )
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("logical1")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("logical2")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("removed1")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            recorder.record("removed2")
        }

        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(_OpacityEffect(opacity: 1), transaction: transaction)
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical1",
                "logical2",
            ]
        )

        harness.setTime(5.0)
        _ = harness.currentValue()
        harness.setTime(5.1)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical1",
                "logical2",
                "removed1",
                "removed2",
            ]
        )
    }

    func testSharedTransactionListenerRegistersForAllAnimatableAttributes() {
        let listener = CountingAnimationListener()
        let harness = DualAnimatableAttributeHarness(
            firstInitialValue: _OpacityEffect(opacity: 0),
            secondInitialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = listener
        XCTAssertEqual(harness.currentFirstValue().opacity, 0)
        XCTAssertEqual(harness.currentSecondValue().opacity, 0)
        harness.setFirst(_OpacityEffect(opacity: 1), transaction: transaction)
        harness.setSecond(_OpacityEffect(opacity: 1), transaction: transaction)
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentFirstValue().opacity, 0)
        XCTAssertEqual(harness.currentSecondValue().opacity, 0)
        XCTAssertEqual(listener.addedCount, 2)
        XCTAssertEqual(listener.removedCount, 0)
        harness.setFirstTime(0.5)
        _ = harness.currentFirstValue()
        harness.setFirstTime(1.6)
        _ = harness.currentFirstValue()
        harness.setFirstTime(2.7)
        XCTAssertEqual(harness.currentFirstValue().opacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(listener.removedCount, 1)
        harness.setSecondTime(0.5)
        _ = harness.currentSecondValue()
        harness.setSecondTime(1.6)
        _ = harness.currentSecondValue()
        harness.setSecondTime(2.7)
        XCTAssertEqual(harness.currentSecondValue().opacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(listener.removedCount, 2)
    }
    func testPhaseResetDrainsActiveCompletionRecords() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        let transaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "old",
            recorder: recorder
        )
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.bumpPhaseResetSeed()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "old logical",
            ]
        )
    }
    func testPhaseResetRemovesRawActiveListeners() {
        let listener = CountingAnimationListener()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = listener
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        XCTAssertEqual(listener.addedCount, 1)
        XCTAssertEqual(listener.removedCount, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.bumpPhaseResetSeed()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(listener.removedCount, 1)
    }
    func testPhaseResetRemovesRawMixedListenersInCriteriaOrder() {
        let recorder = AnimationCompletionRecorder()
        let removedListener = RecordingAnimationListener(
            label: "removed",
            recorder: recorder
        )
        let logicalListener = RecordingAnimationListener(
            label: "logical",
            recorder: recorder
        )
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.bumpPhaseResetSeed()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
    }
    func testNodeRemovalDrainsActiveCompletionRecords() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: .linear(duration: 1),
                label: "old",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "old logical",
            ]
        )
    }
    func testNodeRemovalRemovesRawActiveListeners() {
        let listener = CountingAnimationListener()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = listener
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        XCTAssertEqual(listener.addedCount, 1)
        XCTAssertEqual(listener.removedCount, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(listener.removedCount, 1)
    }
    func testNodeRemovalRemovesRawMixedListenersInCriteriaOrder() {
        let recorder = AnimationCompletionRecorder()
        let removedListener = RecordingAnimationListener(
            label: "removed",
            recorder: recorder
        )
        let logicalListener = RecordingAnimationListener(
            label: "logical",
            recorder: recorder
        )
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
    }
    func testActiveAnimationCompletionRemovesRawMixedListenersInCriteriaOrder() {
        let recorder = AnimationCompletionRecorder()
        let removedListener = RecordingAnimationListener(
            label: "removed",
            recorder: recorder
        )
        let logicalListener = RecordingAnimationListener(
            label: "logical",
            recorder: recorder
        )
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setTime(1.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
        harness.setTime(2.7)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
    }
    func testAnimatableAttributeSplitRawListenersDrainLogicalBeforeRemoved() {
        let recorder = AnimationCompletionRecorder()
        let removedListener = RecordingAnimationListener(
            label: "removed",
            recorder: recorder
        )
        let logicalListener = RecordingAnimationListener(
            label: "logical",
            recorder: recorder
        )
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let sampleRecorder = CustomRetargetSampleRecorder()
        var transaction = Transaction(
            animation: Animation(
                RetargetBoundaryRecordingAnimation(
                    label: "generic",
                    logicalAt: 0.05,
                    nilAt: 1,
                    recorder: sampleRecorder
                )
            )
        )
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ]
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.7)
        _ = harness.currentValue()
        XCTAssertEqual(recorder.events, [])
        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["logical removed"])

        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ]
        )

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ]
        )
    }

    func testAnimatorStateForkListenersPruneCompletedNonPrefixFork() {
        let recorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        func logicalTransaction(
            label: String,
            logicalAt: TimeInterval
        ) -> Transaction {
            var transaction = Transaction(
                animation: Animation(
                    RetargetBoundaryRecordingAnimation(
                        label: label,
                        logicalAt: logicalAt,
                        nilAt: 10,
                        recorder: sampleRecorder
                    )
                )
            )
            transaction.animationListener = RecordingAnimationListener(
                label: "\(label) removed",
                recorder: recorder
            )
            transaction.animationLogicalListener = RecordingAnimationListener(
                label: "\(label) logical",
                recorder: recorder
            )
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old", logicalAt: 0.8)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed added",
                "old logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle", logicalAt: 0.35)
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle removed added",
                "middle logical added",
            ]
        )
        recorder.removeAll()

        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active", logicalAt: 10)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "active removed added",
                "active logical added",
            ]
        )
        recorder.removeAll()

        sampleRecorder.removeAll()
        harness.setTime(1.2)
        _ = harness.currentValue()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        let sampledBeforePrune = sampleRecorder.samples.map(\.label)
        XCTAssertTrue(sampledBeforePrune.contains("middle"))
        XCTAssertTrue(sampledBeforePrune.contains("active"))
        XCTAssertEqual(recorder.events, ["middle logical removed"])

        sampleRecorder.removeAll()
        harness.setTime(6.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        let sampledAfterPrune = sampleRecorder.samples.map(\.label)
        XCTAssertTrue(sampledAfterPrune.contains("old"))
        XCTAssertTrue(sampledAfterPrune.contains("middle"))
        XCTAssertTrue(sampledAfterPrune.contains("active"))
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical removed",
                "old logical removed",
            ]
        )

        harness.setTime(7.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical removed",
                "old logical removed",
            ]
        )
    }

    func testFiniteRetargetRemovesRawMixedListenersInGenerationOrder() {
        let recorder = AnimationCompletionRecorder()
        let oldRemovedListener = RecordingAnimationListener(
            label: "old removed",
            recorder: recorder
        )
        let oldLogicalListener = RecordingAnimationListener(
            label: "old logical",
            recorder: recorder
        )
        let replacementRemovedListener = RecordingAnimationListener(
            label: "replacement removed",
            recorder: recorder
        )
        let replacementLogicalListener = RecordingAnimationListener(
            label: "replacement logical",
            recorder: recorder
        )
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var oldTransaction = Transaction(animation: .linear(duration: 4))
        oldTransaction.animationListener = oldRemovedListener
        oldTransaction.animationLogicalListener = oldLogicalListener
        var replacementTransaction = Transaction(animation: .linear(duration: 1))
        replacementTransaction.animationListener = replacementRemovedListener
        replacementTransaction.animationLogicalListener = replacementLogicalListener
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: oldTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        XCTAssertEqual(
            recorder.events,
            [
                "old removed added",
                "old logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: replacementTransaction
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed added",
                "replacement logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(1.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed removed",
                "replacement removed removed",
                "replacement logical removed",
                "old logical removed",
            ]
        )
    }

    func testFiniteWrapperRetargetMovesMixedCriteriaToReplacementBoundary() {
        let cases: [(
            label: String,
            oldAnimation: Animation,
            replacementAnimation: Animation,
            retargetTime: Double,
            beforeBoundary: Double,
            finalTime: Double
        )] = [
            (
                "delayToSpeed",
                .linear(duration: 0.50).delay(0.30),
                .linear(duration: 0.30).speed(2.0),
                0.20,
                0.30,
                0.70
            ),
            (
                "speedToRepeat",
                .linear(duration: 0.80).speed(0.5),
                .linear(duration: 0.20).repeatCount(2, autoreverses: false),
                0.25,
                0.50,
                1.00
            ),
            (
                "repeatToDelay",
                .linear(duration: 0.25).repeatCount(3, autoreverses: false),
                .linear(duration: 0.20).delay(0.20),
                0.20,
                0.45,
                1.00
            ),
            (
                "linearToDelay",
                .linear(duration: 0.90),
                .linear(duration: 0.20).delay(0.20),
                0.20,
                0.45,
                1.00
            ),
        ]

        for testCase in cases {
            let recorder = AnimationCompletionRecorder()
            let harness = AnimatableAttributeHarness(
                initialValue: _OpacityEffect(opacity: 0)
            )
            XCTAssertEqual(harness.currentValue().opacity, 0, testCase.label)

            harness.setSource(
                _OpacityEffect(opacity: 1),
                transaction: completionTransaction(
                    animation: testCase.oldAnimation,
                    label: "old",
                    recorder: recorder
                )
            )
            harness.finalizeTransactionBody()
            XCTAssertEqual(harness.currentValue().opacity, 0, testCase.label)
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, [], testCase.label)

            harness.setTime(testCase.retargetTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, [], testCase.label)

            harness.setSource(
                _OpacityEffect(opacity: 2),
                transaction: completionTransaction(
                    animation: testCase.replacementAnimation,
                    label: "replacement",
                    recorder: recorder
                )
            )
            harness.finalizeTransactionBody()
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, [], testCase.label)

            harness.setTime(testCase.beforeBoundary)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, [], testCase.label)

            harness.setTime(testCase.finalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                recorder.events,
                [
                    "old removed",
                    "replacement removed",
                    "replacement logical",
                    "old logical",
                ],
                testCase.label
            )

            harness.flushCompletionActions()
            XCTAssertEqual(
                recorder.events,
                [
                    "old removed",
                    "replacement removed",
                    "replacement logical",
                    "old logical",
                ],
                testCase.label
            )
        }
    }

    func testCircularUnitCurveRetargetUsesFiniteNonResidualBoundary() {
        let cases: [(
            label: String,
            oldAnimation: Animation,
            replacementAnimation: Animation
        )] = [
            (
                "circularToLinear",
                .timingCurve(.circularEaseInOut, duration: 0.90),
                .linear(duration: 0.15)
            ),
            (
                "linearToCircular",
                .linear(duration: 0.90),
                .timingCurve(.circularEaseInOut, duration: 0.15)
            ),
            (
                "circularToCircular",
                .timingCurve(.circularEaseInOut, duration: 0.90),
                .timingCurve(.circularEaseInOut, duration: 0.15)
            ),
        ]

        for testCase in cases {
            let recorder = AnimationCompletionRecorder()
            let harness = AnimatableAttributeHarness(
                initialValue: _OpacityEffect(opacity: 0)
            )
            XCTAssertEqual(harness.currentValue().opacity, 0, testCase.label)

            harness.setSource(
                _OpacityEffect(opacity: 1),
                transaction: completionTransaction(
                    animation: testCase.oldAnimation,
                    label: "old",
                    recorder: recorder
                )
            )
            harness.finalizeTransactionBody()
            XCTAssertEqual(harness.currentValue().opacity, 0, testCase.label)
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, [], testCase.label)

            harness.setTime(0.25)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, [], testCase.label)

            harness.setSource(
                _OpacityEffect(opacity: 2),
                transaction: completionTransaction(
                    animation: testCase.replacementAnimation,
                    label: "replacement",
                    recorder: recorder
                )
            )
            harness.finalizeTransactionBody()
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, [], testCase.label)

            harness.setTime(0.35)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, [], testCase.label)

            harness.setTime(0.70)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                recorder.events,
                [
                    "old removed",
                    "replacement removed",
                    "replacement logical",
                    "old logical",
                ],
                testCase.label
            )
        }
    }

    func testPhaseResetAfterFiniteRetargetRemovesRawMixedListenersOnce() {
        let recorder = AnimationCompletionRecorder()
        let oldRemovedListener = RecordingAnimationListener(
            label: "old removed",
            recorder: recorder
        )
        let oldLogicalListener = RecordingAnimationListener(
            label: "old logical",
            recorder: recorder
        )
        let replacementRemovedListener = RecordingAnimationListener(
            label: "replacement removed",
            recorder: recorder
        )
        let replacementLogicalListener = RecordingAnimationListener(
            label: "replacement logical",
            recorder: recorder
        )
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var oldTransaction = Transaction(animation: .linear(duration: 4))
        oldTransaction.animationListener = oldRemovedListener
        oldTransaction.animationLogicalListener = oldLogicalListener
        var replacementTransaction = Transaction(animation: .linear(duration: 1))
        replacementTransaction.animationListener = replacementRemovedListener
        replacementTransaction.animationLogicalListener = replacementLogicalListener
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: oldTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        XCTAssertEqual(
            recorder.events,
            [
                "old removed added",
                "old logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: replacementTransaction
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed added",
                "replacement logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(1.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.bumpPhaseResetSeed()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed removed",
                "replacement removed removed",
                "replacement logical removed",
                "old logical removed",
            ]
        )
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed removed",
                "replacement removed removed",
                "replacement logical removed",
                "old logical removed",
            ]
        )
    }
    func testNodeRemovalAfterFiniteRetargetRemovesRawMixedListenersOnce() {
        let recorder = AnimationCompletionRecorder()
        let oldRemovedListener = RecordingAnimationListener(
            label: "old removed",
            recorder: recorder
        )
        let oldLogicalListener = RecordingAnimationListener(
            label: "old logical",
            recorder: recorder
        )
        let replacementRemovedListener = RecordingAnimationListener(
            label: "replacement removed",
            recorder: recorder
        )
        let replacementLogicalListener = RecordingAnimationListener(
            label: "replacement logical",
            recorder: recorder
        )
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var oldTransaction = Transaction(animation: .linear(duration: 4))
        oldTransaction.animationListener = oldRemovedListener
        oldTransaction.animationLogicalListener = oldLogicalListener
        var replacementTransaction = Transaction(animation: .linear(duration: 1))
        replacementTransaction.animationListener = replacementRemovedListener
        replacementTransaction.animationLogicalListener = replacementLogicalListener
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: oldTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        XCTAssertEqual(
            recorder.events,
            [
                "old removed added",
                "old logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: replacementTransaction
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed added",
                "replacement logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(1.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed removed",
                "replacement removed removed",
                "replacement logical removed",
                "old logical removed",
            ]
        )
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed removed",
                "replacement removed removed",
                "replacement logical removed",
                "old logical removed",
            ]
        )
    }
    func testZeroDurationRetargetRemovesRawMixedListenersInGenerationOrder() {
        let recorder = AnimationCompletionRecorder()
        let oldRemovedListener = RecordingAnimationListener(
            label: "old removed",
            recorder: recorder
        )
        let oldLogicalListener = RecordingAnimationListener(
            label: "old logical",
            recorder: recorder
        )
        let replacementRemovedListener = RecordingAnimationListener(
            label: "replacement removed",
            recorder: recorder
        )
        let replacementLogicalListener = RecordingAnimationListener(
            label: "replacement logical",
            recorder: recorder
        )
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var oldTransaction = Transaction(animation: .linear(duration: 1))
        oldTransaction.animationListener = oldRemovedListener
        oldTransaction.animationLogicalListener = oldLogicalListener
        var zeroTransaction = Transaction(animation: .linear(duration: 0))
        zeroTransaction.animationListener = replacementRemovedListener
        zeroTransaction.animationLogicalListener = replacementLogicalListener
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: oldTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        XCTAssertEqual(
            recorder.events,
            [
                "old removed added",
                "old logical added",
            ]
        )
        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: zeroTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001)
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed added",
                "replacement logical added",
                "old removed removed",
                "replacement removed removed",
                "replacement logical removed",
                "old logical removed",
            ]
        )
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed added",
                "replacement logical added",
                "old removed removed",
                "replacement removed removed",
                "replacement logical removed",
                "old logical removed",
            ]
        )
    }
    func testZeroDurationRetargetFinishesOldAndReplacementRecordsInGroupedOrder() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        let oldTransaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "old",
            recorder: recorder
        )
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: oldTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setTime(0.5)
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.6)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        let zeroTransaction = completionTransaction(
            animation: .linear(duration: 0),
            label: "zero",
            recorder: recorder
        )
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: zeroTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "zero removed",
                "zero logical",
                "old logical",
            ]
        )
    }
    func testZeroDurationRetargetSamplesDiscardedAnimationBeforeCompletions() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        let oldTransaction = completionTransaction(
            animation: Animation(
                RecordingUnitAnimation(
                    label: "old",
                    duration: 1,
                    recorder: recorder
                )
            ),
            label: "old",
            recorder: recorder
        )
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: oldTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.6)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0)
        harness.flushCompletionActions()
        recorder.removeAll()
        let zeroTransaction = completionTransaction(
            animation: .linear(duration: 0),
            label: "zero",
            recorder: recorder
        )
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: zeroTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old animate",
                "old removed",
                "zero removed",
                "zero logical",
                "old logical",
            ]
        )
    }
    func testZeroDurationRetargetSnapsBeforeCallbacksForSampledBuiltInClasses() {
        assertZeroDurationRetargetSnapAndOrder(
            oldAnimation: .linear(duration: 1),
            replacementAnimation: .linear(duration: 0)
        )
        assertZeroDurationRetargetSnapAndOrder(
            oldAnimation: .spring(response: 0.35, dampingFraction: 0.70),
            replacementAnimation: .linear(duration: 0)
        )
        assertZeroDurationRetargetSnapAndOrder(
            oldAnimation: .linear(duration: 1),
            replacementAnimation: .linear(duration: 0.20).delay(-0.20)
        )
    }
    func testNoAnimationRetargetPreservesResidualAnimationAndOldCompletionDeadline() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(UnitLinearAnimation(duration: 4)),
                label: "old",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let beforeRetarget = harness.currentValue().opacity
        XCTAssertGreaterThan(beforeRetarget, 0)
        XCTAssertLessThan(beforeRetarget, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: Transaction(animation: nil)
        )
        harness.finalizeTransactionBody()
        let afterRetarget = harness.currentValue().opacity
        XCTAssertGreaterThan(afterRetarget, beforeRetarget)
        XCTAssertLessThan(afterRetarget, 2)
        XCTAssertEqual(recorder.events, [])
        harness.setTime(5.0)
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001)
        XCTAssertEqual(recorder.events, [])
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "old logical",
            ]
        )
    }
    func testScopedTransactionActiveSetupPreservesResidualAnimationAndCompletionDeadline() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        let oldTransaction = completionTransaction(
            animation: Animation(UnitLinearAnimation(duration: 4)),
            label: "old",
            recorder: recorder
        )
        withTransaction(oldTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 1))
        }
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let beforeRetarget = harness.currentValue().opacity
        XCTAssertGreaterThan(beforeRetarget, 0)
        XCTAssertLessThan(beforeRetarget, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        withTransaction(Transaction(animation: nil)) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 2))
        }
        let afterRetarget = harness.currentValue().opacity
        XCTAssertGreaterThan(afterRetarget, beforeRetarget)
        XCTAssertLessThan(afterRetarget, 2)
        XCTAssertEqual(recorder.events, [])
        harness.setTime(5.0)
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001)
        XCTAssertEqual(recorder.events, [])
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "old logical",
            ]
        )
    }

    func testThrowingRegisteredTransactionsWaitForAnimationBoundary() {
        enum ProbeError: Error {
            case expected
        }

        let animationRecorder = AnimationCompletionRecorder()
        let animationHarness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(animationHarness.currentValue().opacity, 0)
        do {
            try withAnimation(
                .linear(duration: 1),
                completionCriteria: .logicallyComplete
            ) {
                animationRecorder.record("withAnimation body")
                animationHarness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 1))
                throw ProbeError.expected
            } completion: {
                animationRecorder.record("withAnimation completion")
            }
            XCTFail("throwing withAnimation returned normally")
        } catch ProbeError.expected {
            animationRecorder.record("withAnimation catch")
        } catch {
            XCTFail("unexpected withAnimation error: \(error)")
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        animationHarness.flushCompletionActions()
        XCTAssertEqual(
            animationRecorder.events,
            [
                "withAnimation body",
                "withAnimation catch",
            ]
        )
        XCTAssertEqual(animationHarness.currentValue().opacity, 0, accuracy: 0.000_001)
        animationHarness.setTime(0.5)
        _ = animationHarness.currentValue()
        animationHarness.setTime(0.6)
        let animationMidValue = animationHarness.currentValue().opacity
        XCTAssertGreaterThan(animationMidValue, 0)
        XCTAssertLessThan(animationMidValue, 1)
        animationHarness.flushCompletionActions()
        XCTAssertEqual(
            animationRecorder.events,
            [
                "withAnimation body",
                "withAnimation catch",
            ]
        )
        animationHarness.setTime(3.0)
        XCTAssertEqual(animationHarness.currentValue().opacity, 1, accuracy: 0.000_001)
        animationHarness.flushCompletionActions()
        XCTAssertEqual(
            animationRecorder.events,
            [
                "withAnimation body",
                "withAnimation catch",
                "withAnimation completion",
            ]
        )

        let transactionRecorder = AnimationCompletionRecorder()
        let transactionHarness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(transactionHarness.currentValue().opacity, 0)
        let transaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "withTransaction",
            recorder: transactionRecorder
        )
        do {
            try withTransaction(transaction) {
                transactionRecorder.record("withTransaction body")
                transactionHarness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 1))
                throw ProbeError.expected
            }
            XCTFail("throwing withTransaction returned normally")
        } catch ProbeError.expected {
            transactionRecorder.record("withTransaction catch")
        } catch {
            XCTFail("unexpected withTransaction error: \(error)")
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        transactionHarness.flushCompletionActions()
        XCTAssertEqual(
            transactionRecorder.events,
            [
                "withTransaction body",
                "withTransaction catch",
            ]
        )
        XCTAssertEqual(transactionHarness.currentValue().opacity, 0, accuracy: 0.000_001)
        transactionHarness.setTime(0.5)
        _ = transactionHarness.currentValue()
        transactionHarness.setTime(0.6)
        let transactionMidValue = transactionHarness.currentValue().opacity
        XCTAssertGreaterThan(transactionMidValue, 0)
        XCTAssertLessThan(transactionMidValue, 1)
        transactionHarness.flushCompletionActions()
        XCTAssertEqual(
            transactionRecorder.events,
            [
                "withTransaction body",
                "withTransaction catch",
            ]
        )
        transactionHarness.setTime(3.0)
        XCTAssertEqual(transactionHarness.currentValue().opacity, 1, accuracy: 0.000_001)
        transactionHarness.flushCompletionActions()
        XCTAssertEqual(
            transactionRecorder.events,
            [
                "withTransaction body",
                "withTransaction catch",
                "withTransaction removed",
                "withTransaction logical",
            ]
        )
    }

    func testCustomNoAnimationRetargetKeepsOldSamplerAndCompletionBoundaries() throws {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        let oldAnimation = Animation(
            RetargetBoundaryRecordingAnimation(
                label: "old",
                logicalAt: 1.0,
                nilAt: 4.0,
                recorder: sampleRecorder
            )
        )
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let beforeRetarget = harness.currentValue().opacity
        XCTAssertGreaterThan(beforeRetarget, 0)
        XCTAssertLessThan(beforeRetarget, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])
        sampleRecorder.removeAll()
        let nilTransaction = completionTransaction(
            animation: nil,
            label: "nil",
            recorder: completionRecorder
        )
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 2))
        }
        let afterRetarget = harness.currentValue().opacity
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertGreaterThan(afterRetarget, beforeRetarget)
        XCTAssertLessThan(afterRetarget, 2)
        XCTAssertEqual(sampleRecorder.shouldMergeCount, 0)
        let firstSample = try XCTUnwrap(sampleRecorder.samples.first)
        XCTAssertEqual(firstSample.input, 1, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(firstSample.time, 0)
        XCTAssertLessThan(firstSample.time, 1.0)
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
            ]
        )
        completionRecorder.removeAll()
        harness.setTime(1.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["old logical"])
        completionRecorder.removeAll()
        harness.setTime(5.0)
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001)
        XCTAssertEqual(completionRecorder.events, [])
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["old removed"])
    }
    func testCombinedCustomNoAnimationRetargetKeepsResidualChildrenAndNilFallback() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 2.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let oldRunning = harness.currentValue().opacity
        XCTAssertGreaterThan(oldRunning, 0)
        XCTAssertLessThan(oldRunning, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 2.6,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        let combinedRunning = harness.currentValue().opacity
        XCTAssertLessThan(combinedRunning, 1)
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])
        sampleRecorder.removeAll()
        let nilTransaction = completionTransaction(
            animation: nil,
            label: "nil",
            recorder: completionRecorder
        )
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 0.75))
        }
        let afterNil = harness.currentValue().opacity
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertGreaterThan(afterNil, 0.75)
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
            ]
        )
    }
    func testCombinedCustomDelayNoAnimationRetargetKeepsResidualChildrenAndNilFallback() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 2.2,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 2.6,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        let shouldMergeAfterSecond = sampleRecorder.shouldMergeCount
        harness.setSource(
            _OpacityEffect(opacity: -1.1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 2.4,
                        recorder: sampleRecorder
                    )
                ).delay(0.2),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.25)
        _ = harness.currentValue()
        XCTAssertEqual(sampleRecorder.shouldMergeCount, shouldMergeAfterSecond)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])
        sampleRecorder.removeAll()
        let nilTransaction = completionTransaction(
            animation: nil,
            label: "nil",
            recorder: completionRecorder
        )
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 0.75))
        }
        let afterNil = harness.currentValue().opacity
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertGreaterThan(afterNil, 0.75)
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
            ]
        )
    }
    func testCombinedCustomNoAnimationMiddleNilKeepsRemovedRecordsUntilTerminalSourceNil() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 2.20,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.75,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        harness.setSource(
            _OpacityEffect(opacity: -1.1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 2.40,
                        recorder: sampleRecorder
                    )
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 1)
        sampleRecorder.removeAll()
        let nilTransaction = completionTransaction(
            animation: nil,
            label: "nil",
            recorder: completionRecorder
        )
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 0.75))
        }
        let afterNil = harness.currentValue().opacity
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertGreaterThan(afterNil, 0.75)
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
            ]
        )
        harness.setTime(1.9)
        let afterSecondNil = harness.currentValue().opacity
        harness.flushCompletionActions()
        XCTAssertGreaterThan(afterSecondNil, 0.75)
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
                "second logical",
            ]
        )
        harness.setTime(2.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
                "second logical",
                "old logical",
            ]
        )
        harness.setTime(3.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
                "second logical",
                "old logical",
                "old removed",
                "second removed",
                "third removed",
                "third logical",
            ]
        )
    }
    func testCombinedCustomDelayNoAnimationMiddleNilDoesNotForwardSourceShouldMerge() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 2.20,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.75,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        let shouldMergeAfterSecond = sampleRecorder.shouldMergeCount
        harness.setSource(
            _OpacityEffect(opacity: -1.1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 2.40,
                        recorder: sampleRecorder
                    )
                ).delay(0.22),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertEqual(sampleRecorder.shouldMergeCount, shouldMergeAfterSecond)
        sampleRecorder.removeAll()
        let nilTransaction = completionTransaction(
            animation: nil,
            label: "nil",
            recorder: completionRecorder
        )
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 0.75))
        }
        let afterNil = harness.currentValue().opacity
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertGreaterThan(afterNil, 0.75)
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
            ]
        )
        harness.setTime(1.7)
        let afterSecondNil = harness.currentValue().opacity
        harness.flushCompletionActions()
        XCTAssertGreaterThan(afterSecondNil, 0.75)
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
                "second logical",
            ]
        )
        harness.setTime(2.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
                "second logical",
                "old logical",
            ]
        )
        harness.setTime(3.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "nil removed",
                "nil logical",
                "second logical",
                "old logical",
                "old removed",
                "second removed",
                "third removed",
                "third logical",
            ]
        )
    }
    func testCombinedCustomInfiniteRetargetKeepsResidualChildrenAndPendingRemoval() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 2.2,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 2.6,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.30).repeatForever(autoreverses: false),
                label: "infinite",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.2)
        _ = harness.currentValue()
        harness.setTime(1.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("infinite ") })
    }

    func testCombinedCustomInfiniteSecondNilDrainsLogicalOnlyAndKeepsRemovalPending() {
        let setup = makeCombinedTwoChildHarness(
            oldDuration: 2.20,
            secondDuration: 0.75
        )
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder
        let harness = setup.harness
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.30).repeatForever(autoreverses: false),
                label: "infinite",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertEqual(completionRecorder.events, [])
        harness.setTime(1.7)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])
        harness.setTime(2.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old logical",
            ]
        )
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("infinite ") })
    }

    func testCombinedCustomInfiniteMiddleNilDrainsLogicalOnlyAndKeepsRemovalPending() {
        let setup = makeCombinedMiddleNilHarness()
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder
        let harness = setup.harness
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.30).repeatForever(autoreverses: false),
                label: "infinite",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertEqual(completionRecorder.events, [])
        harness.setTime(1.7)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])
        harness.setTime(2.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old logical",
            ]
        )
        harness.setTime(3.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old logical",
                "third logical",
            ]
        )
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("infinite ") })
    }

    func testCombinedCustomInfiniteDelayedThirdMiddleNilDrainsLogicalOnlyAndKeepsRemovalPending() {
        let setup = makeCombinedMiddleNilHarness(
            wrapThirdAnimation: { $0.delay(0.22) },
            expectsThirdShouldMerge: false
        )
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder
        let harness = setup.harness
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.30).repeatForever(autoreverses: false),
                label: "infinite",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertEqual(completionRecorder.events, [])
        harness.setTime(1.7)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])
        harness.setTime(2.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old logical",
            ]
        )
        harness.setTime(3.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old logical",
                "third logical",
            ]
        )
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("infinite ") })
    }

    func testCombinedCustomResidualRepeatForeverDrainsReplacementLogicalOnly() {
        let cases: [(label: String, animation: Animation)] = [
            ("defaultRepeat", Animation.default.repeatForever(autoreverses: false)),
            (
                "fluidRepeat",
                Animation.spring(
                    response: 0.45,
                    dampingFraction: 0.82,
                    blendDuration: 0.0
                ).repeatForever(autoreverses: false)
            ),
            (
                "springRepeat",
                Animation.interpolatingSpring(
                    mass: 1.0,
                    stiffness: 100.0,
                    damping: 10.0
                ).repeatForever(autoreverses: false)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["\(testCase.label) logical"], testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
        }
    }

    func testCombinedCustomResidualRepeatForeverWrappersDrainReplacementLogicalOnly() {
        let defaultBase = Animation.default
        let fluidBase = Animation.spring(
            response: 0.45,
            dampingFraction: 0.82,
            blendDuration: 0.0
        )
        let springBase = Animation.interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0
        )
        let cases: [(label: String, animation: Animation)] = [
            (
                "defaultDelayRepeat",
                defaultBase.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "defaultRepeatDelay",
                defaultBase.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "fluidDelayRepeat",
                fluidBase.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "fluidRepeatDelay",
                fluidBase.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "springDelayRepeat",
                springBase.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "springRepeatDelay",
                springBase.repeatForever(autoreverses: false).delay(0.20)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.6)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["\(testCase.label) logical"], testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
        }
    }

    func testCombinedCustomResidualNonPositiveSpeedKeepsReplacementPending() {
        let defaultBase = Animation.default
        let fluidBase = Animation.spring(
            response: 0.45,
            dampingFraction: 0.82,
            blendDuration: 0.0
        )
        let springBase = Animation.interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0
        )
        let cases: [(label: String, animation: Animation)] = [
            ("defaultSpeedZero", defaultBase.speed(0.0)),
            ("defaultSpeedNegative", defaultBase.speed(-1.0)),
            ("fluidSpeedZero", fluidBase.speed(0.0)),
            ("fluidSpeedNegative", fluidBase.speed(-1.0)),
            ("springSpeedZero", springBase.speed(0.0)),
            ("springSpeedNegative", springBase.speed(-1.0)),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.6)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
        }
    }

    func testCombinedCustomFluidSpringAliasRepeatForeverDrainsReplacementLogicalOnly() {
        let cases: [(label: String, animation: Animation)] = [
            (
                "springDurationRepeat",
                Animation.spring(
                    duration: 0.48,
                    bounce: 0.0,
                    blendDuration: 0.0
                ).repeatForever(autoreverses: false)
            ),
            (
                "springValueRepeat",
                Animation.spring(
                    Spring(duration: 0.48, bounce: 0.0),
                    blendDuration: 0.0
                ).repeatForever(autoreverses: false)
            ),
            (
                "interactiveResponseRepeat",
                Animation.interactiveSpring(
                    response: 0.30,
                    dampingFraction: 0.82,
                    blendDuration: 0.0
                ).repeatForever(autoreverses: false)
            ),
            (
                "interactiveDurationRepeat",
                Animation.interactiveSpring(
                    duration: 0.30,
                    extraBounce: 0.0,
                    blendDuration: 0.0
                ).repeatForever(autoreverses: false)
            ),
            ("smoothRepeat", Animation.smooth.repeatForever(autoreverses: false)),
            ("snappyRepeat", Animation.snappy.repeatForever(autoreverses: false)),
            ("bouncyRepeat", Animation.bouncy.repeatForever(autoreverses: false)),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.6)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["\(testCase.label) logical"], testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
        }
    }

    func testCombinedCustomFluidSpringAliasNestedRepeatForeverDrainsReplacementLogicalOnly() {
        let springDuration = Animation.spring(
            duration: 0.48,
            bounce: 0.0,
            blendDuration: 0.0
        )
        let springValue = Animation.spring(
            Spring(duration: 0.48, bounce: 0.0),
            blendDuration: 0.0
        )
        let interactiveResponse = Animation.interactiveSpring(
            response: 0.30,
            dampingFraction: 0.82,
            blendDuration: 0.0
        )
        let interactiveDuration = Animation.interactiveSpring(
            duration: 0.30,
            extraBounce: 0.0,
            blendDuration: 0.0
        )
        let cases: [(label: String, animation: Animation)] = [
            (
                "springDurationDelayRepeat",
                springDuration.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "springValueDelayRepeat",
                springValue.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "interactiveResponseDelayRepeat",
                interactiveResponse.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "interactiveDurationDelayRepeat",
                interactiveDuration.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "smoothDelayRepeat",
                Animation.smooth.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "snappyDelayRepeat",
                Animation.snappy.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "bouncyDelayRepeat",
                Animation.bouncy.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "springDurationRepeatDelay",
                springDuration.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "springValueRepeatDelay",
                springValue.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "interactiveResponseRepeatDelay",
                interactiveResponse.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "interactiveDurationRepeatDelay",
                interactiveDuration.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "smoothRepeatDelay",
                Animation.smooth.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "snappyRepeatDelay",
                Animation.snappy.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "bouncyRepeatDelay",
                Animation.bouncy.repeatForever(autoreverses: false).delay(0.20)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["\(testCase.label) logical"], testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
        }
    }

    func testCombinedCustomFluidSpringAliasNonPositiveSpeedKeepsReplacementPending() {
        let springDuration = Animation.spring(
            duration: 0.48,
            bounce: 0.0,
            blendDuration: 0.0
        )
        let springValue = Animation.spring(
            Spring(duration: 0.48, bounce: 0.0),
            blendDuration: 0.0
        )
        let interactiveResponse = Animation.interactiveSpring(
            response: 0.30,
            dampingFraction: 0.82,
            blendDuration: 0.0
        )
        let interactiveDuration = Animation.interactiveSpring(
            duration: 0.30,
            extraBounce: 0.0,
            blendDuration: 0.0
        )
        let cases: [(label: String, animation: Animation)] = [
            ("springDurationSpeedZero", springDuration.speed(0.0)),
            ("springValueSpeedZero", springValue.speed(0.0)),
            ("interactiveResponseSpeedZero", interactiveResponse.speed(0.0)),
            ("interactiveDurationSpeedZero", interactiveDuration.speed(0.0)),
            ("smoothSpeedZero", Animation.smooth.speed(0.0)),
            ("snappySpeedZero", Animation.snappy.speed(0.0)),
            ("bouncySpeedZero", Animation.bouncy.speed(0.0)),
            ("springDurationSpeedNegative", springDuration.speed(-1.0)),
            ("springValueSpeedNegative", springValue.speed(-1.0)),
            ("interactiveResponseSpeedNegative", interactiveResponse.speed(-1.0)),
            ("interactiveDurationSpeedNegative", interactiveDuration.speed(-1.0)),
            ("smoothSpeedNegative", Animation.smooth.speed(-1.0)),
            ("snappySpeedNegative", Animation.snappy.speed(-1.0)),
            ("bouncySpeedNegative", Animation.bouncy.speed(-1.0)),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
        }
    }

    func testCombinedCustomFluidSpringAliasFiniteWrappersKeepResidualOwnership() {
        let springValue = Animation.spring(
            Spring(duration: 0.48, bounce: 0.0),
            blendDuration: 0.0
        )
        let interactiveDuration = Animation.interactiveSpring(
            duration: 0.30,
            extraBounce: 0.0,
            blendDuration: 0.0
        )
        let oldSourceNilBeforeRemovedCases: [(label: String, animation: Animation)] = [
            ("interactiveDurationSpeed", interactiveDuration.speed(0.5)),
        ]

        for testCase in oldSourceNilBeforeRemovedCases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: 3.2,
                secondDuration: 3.2
            )
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(8.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                ],
                testCase.label
            )
        }

        let variableCases: [(label: String, animation: Animation)] = [
            ("springValueDelay", springValue.delay(0.20)),
            ("snappyRepeat", Animation.snappy.repeatCount(2, autoreverses: false)),
        ]

        for testCase in variableCases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: 3.2,
                secondDuration: 3.2
            )
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(8.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            let oldSourceNilBeforeRemovedOrder = [
                "\(testCase.label) logical",
                "old logical",
                "second logical",
                "old removed",
                "second removed",
                "\(testCase.label) removed",
            ]
            let sameBoundaryOrder = [
                "old removed",
                "second removed",
                "\(testCase.label) removed",
                "\(testCase.label) logical",
                "old logical",
                "second logical",
            ]
            XCTAssertTrue(
                [oldSourceNilBeforeRemovedOrder, sameBoundaryOrder].contains(completionRecorder.events),
                "\(testCase.label) events \(completionRecorder.events)"
            )
        }
    }

    func testCombinedCustomSpringAnimationAliasRepeatForeverDrainsReplacementLogicalOnly() {
        let cases: [(label: String, animation: Animation)] = [
            (
                "springAnimationValueRepeat",
                Animation.interpolatingSpring(
                    Spring(duration: 0.48, bounce: 0.0),
                    initialVelocity: 0.0
                ).repeatForever(autoreverses: false)
            ),
            (
                "springAnimationDurationRepeat",
                Animation.interpolatingSpring(
                    duration: 0.48,
                    bounce: 0.0,
                    initialVelocity: 0.0
                ).repeatForever(autoreverses: false)
            ),
            (
                "springAnimationDefaultRepeat",
                Animation.interpolatingSpring.repeatForever(autoreverses: false)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.6)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["\(testCase.label) logical"], testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
        }
    }

    func testCombinedCustomSpringAnimationAliasNestedRepeatForeverDrainsReplacementLogicalOnly() {
        let springValue = Animation.interpolatingSpring(
            Spring(duration: 0.48, bounce: 0.0),
            initialVelocity: 0.0
        )
        let springDuration = Animation.interpolatingSpring(
            duration: 0.48,
            bounce: 0.0,
            initialVelocity: 0.0
        )
        let cases: [(label: String, animation: Animation)] = [
            (
                "springAnimationValueDelayRepeat",
                springValue.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "springAnimationValueRepeatDelay",
                springValue.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "springAnimationDurationDelayRepeat",
                springDuration.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "springAnimationDurationRepeatDelay",
                springDuration.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "springAnimationDefaultDelayRepeat",
                Animation.interpolatingSpring.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "springAnimationDefaultRepeatDelay",
                Animation.interpolatingSpring.repeatForever(autoreverses: false).delay(0.20)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["\(testCase.label) logical"], testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
        }
    }

    func testCombinedCustomSpringAnimationAliasNonPositiveSpeedKeepsReplacementPending() {
        let springValue = Animation.interpolatingSpring(
            Spring(duration: 0.48, bounce: 0.0),
            initialVelocity: 0.0
        )
        let springDuration = Animation.interpolatingSpring(
            duration: 0.48,
            bounce: 0.0,
            initialVelocity: 0.0
        )
        let cases: [(label: String, animation: Animation)] = [
            ("springAnimationValueSpeedZero", springValue.speed(0.0)),
            ("springAnimationValueSpeedNegative", springValue.speed(-1.0)),
            ("springAnimationDurationSpeedZero", springDuration.speed(0.0)),
            ("springAnimationDurationSpeedNegative", springDuration.speed(-1.0)),
            ("springAnimationDefaultSpeedZero", Animation.interpolatingSpring.speed(0.0)),
            ("springAnimationDefaultSpeedNegative", Animation.interpolatingSpring.speed(-1.0)),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
        }
    }

    func testCombinedCustomFluidSpringPropertyAliasRepeatForeverDrainsReplacementLogicalOnly() {
        let cases: [(label: String, animation: Animation)] = [
            ("springPropertyRepeat", Animation.spring.repeatForever(autoreverses: false)),
            (
                "interactivePropertyRepeat",
                Animation.interactiveSpring.repeatForever(autoreverses: false)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.6)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["\(testCase.label) logical"], testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
        }
    }

    func testCombinedCustomInteractiveRepeatForeverLogicalOrderingVariants() {
        let cases: [(
            label: String,
            animation: Animation,
            oldDuration: TimeInterval,
            secondDuration: TimeInterval,
            checkpoints: [(time: TimeInterval, expected: [String])]
        )] = [
            (
                "interactivePropertyRepeat",
                Animation.interactiveSpring.repeatForever(autoreverses: false),
                3.0,
                3.4,
                [
                    (
                        2.6,
                        ["interactivePropertyRepeat logical"]
                    ),
                    (
                        3.8,
                        [
                            "interactivePropertyRepeat logical",
                            "old logical",
                        ]
                    ),
                    (
                        4.6,
                        [
                            "interactivePropertyRepeat logical",
                            "old logical",
                            "second logical",
                        ]
                    ),
                ]
            ),
            (
                "interactiveResponseRepeat",
                Animation.interactiveSpring(
                    response: 0.30,
                    dampingFraction: 0.82,
                    blendDuration: 0.0
                ).repeatForever(autoreverses: false),
                0.95,
                3.4,
                [
                    (
                        2.0,
                        [
                            "old logical",
                            "interactiveResponseRepeat logical",
                        ]
                    ),
                    (
                        4.6,
                        [
                            "old logical",
                            "interactiveResponseRepeat logical",
                            "second logical",
                        ]
                    ),
                ]
            ),
            (
                "interactiveDurationRepeat",
                Animation.interactiveSpring(
                    duration: 0.30,
                    extraBounce: 0.0,
                    blendDuration: 0.0
                ).repeatForever(autoreverses: false),
                3.0,
                3.4,
                [
                    (
                        2.6,
                        ["interactiveDurationRepeat logical"]
                    ),
                    (
                        3.8,
                        [
                            "interactiveDurationRepeat logical",
                            "old logical",
                        ]
                    ),
                    (
                        4.6,
                        [
                            "interactiveDurationRepeat logical",
                            "old logical",
                            "second logical",
                        ]
                    ),
                ]
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: testCase.oldDuration,
                secondDuration: testCase.secondDuration
            )
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            for checkpoint in testCase.checkpoints {
                harness.setTime(checkpoint.time)
                _ = harness.currentValue()
                harness.flushCompletionActions()
                XCTAssertEqual(completionRecorder.events, checkpoint.expected, testCase.label)
            }
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
        }
    }

    func testCombinedCustomFluidSpringPropertyAliasNestedRepeatForeverDrainsReplacementLogicalOnly() {
        let cases: [(label: String, animation: Animation)] = [
            (
                "springPropertyDelayRepeat",
                Animation.spring.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "springPropertyRepeatDelay",
                Animation.spring.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "springNoArgDelayRepeat",
                Animation.spring().delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "springNoArgRepeatDelay",
                Animation.spring().repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "interactivePropertyDelayRepeat",
                Animation.interactiveSpring.delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "interactivePropertyRepeatDelay",
                Animation.interactiveSpring.repeatForever(autoreverses: false).delay(0.20)
            ),
            (
                "interactiveNoArgDelayRepeat",
                Animation.interactiveSpring().delay(0.20).repeatForever(autoreverses: false)
            ),
            (
                "interactiveNoArgRepeatDelay",
                Animation.interactiveSpring().repeatForever(autoreverses: false).delay(0.20)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["\(testCase.label) logical"], testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
        }
    }

    func testCombinedCustomFluidSpringPropertyAliasFiniteRepeatWrappersKeepResidualOwnership() {
        let sourceNilCases: [(label: String, animation: Animation)] = [
            ("springPropertyRepeat", Animation.spring.repeatCount(2, autoreverses: false)),
            ("springNoArgRepeat", Animation.spring().repeatCount(2, autoreverses: false)),
        ]

        for testCase in sourceNilCases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: 3.2,
                secondDuration: 3.2
            )
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(
                completionRecorder.events,
                [],
                testCase.label
            )
            harness.setTime(4.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
            harness.setTime(8.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                ],
                testCase.label
            )
        }

        let residualFirstCases: [(label: String, animation: Animation)] = [
            (
                "interactivePropertyRepeat",
                Animation.interactiveSpring.repeatCount(2, autoreverses: false)
            ),
        ]

        for testCase in residualFirstCases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomFluidSpringNoArgAliasFiniteWrappersKeepResidualOwnership() {
        let variableSourceNilCases: [(label: String, animation: Animation)] = [
            ("springPropertyDelay", Animation.spring.delay(0.20)),
        ]

        for testCase in variableSourceNilCases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: 3.2,
                secondDuration: 3.2
            )
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(8.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            let oldSourceNilBeforeRemovedOrder = [
                "\(testCase.label) logical",
                "old logical",
                "second logical",
                "old removed",
                "second removed",
                "\(testCase.label) removed",
            ]
            let sameBoundaryOrder = [
                "old removed",
                "second removed",
                "\(testCase.label) removed",
                "\(testCase.label) logical",
                "old logical",
                "second logical",
            ]
            XCTAssertTrue(
                [oldSourceNilBeforeRemovedOrder, sameBoundaryOrder].contains(completionRecorder.events),
                "\(testCase.label) events \(completionRecorder.events)"
            )
        }

        let sourceNilCases: [(label: String, animation: Animation)] = [
            ("springNoArgSpeed", Animation.spring().speed(0.5)),
        ]

        for testCase in sourceNilCases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: 3.2,
                secondDuration: 3.2
            )
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(8.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                ],
                testCase.label
            )
        }

        let residualFirstCases: [(label: String, animation: Animation)] = [
            ("interactiveNoArgDelay", Animation.interactiveSpring().delay(0.20)),
        ]

        for testCase in residualFirstCases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(8.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomDefaultAndFluidRepeatEdgesKeepResidualOwnership() {
        let finalEvents: (String) -> [String] = { label in
            [
                "\(label) logical",
                "old logical",
                "second logical",
                "old removed",
                "second removed",
                "\(label) removed",
            ]
        }
        let sourceNilCases: [(
            label: String,
            animation: Animation,
            expectedAfterSourceNilSample: [String],
            finalTime: TimeInterval
        )] = [
            (
                "defaultRepeatZero",
                Animation.default.repeatCount(0, autoreverses: false),
                finalEvents("defaultRepeatZero"),
                4.2
            ),
            (
                "fluidRepeatZero",
                Animation.spring(response: 0.4, dampingFraction: 0.8)
                    .repeatCount(0, autoreverses: false),
                finalEvents("fluidRepeatZero"),
                4.2
            ),
            (
                "defaultRepeatAuto",
                Animation.default.repeatCount(2, autoreverses: true),
                [
                    "defaultRepeatAuto logical",
                    "old logical",
                    "second logical",
                ],
                8.0
            ),
            (
                "fluidRepeatAuto",
                Animation.spring(response: 0.4, dampingFraction: 0.8)
                    .repeatCount(2, autoreverses: true),
                finalEvents("fluidRepeatAuto"),
                4.2
            ),
        ]

        for testCase in sourceNilCases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: 3.2,
                secondDuration: 3.2
            )
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(4.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                testCase.expectedAfterSourceNilSample,
                testCase.label
            )
            if testCase.finalTime > 4.2 {
                harness.setTime(testCase.finalTime)
                _ = harness.currentValue()
                harness.flushCompletionActions()
                XCTAssertEqual(
                    completionRecorder.events,
                    finalEvents(testCase.label),
                    testCase.label
                )
            }
        }
    }

    func testCombinedCustomFluidSpringPropertyAliasDelayEdgeWrappersKeepResidualOwnership() {
        let sourceNilCases: [(label: String, animation: Animation)] = [
            ("springPropertyDelayZero", Animation.spring.delay(0.0)),
        ]

        for testCase in sourceNilCases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: 3.2,
                secondDuration: 3.2
            )
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(
                completionRecorder.events,
                [],
                testCase.label
            )
            harness.setTime(4.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                ],
                testCase.label
            )
        }

        let residualFirstCases: [(label: String, animation: Animation)] = [
            ("springNoArgDelayNegative", Animation.spring().delay(-0.20)),
            ("interactivePropertyDelayZero", Animation.interactiveSpring.delay(0.0)),
            ("interactiveNoArgDelayNegative", Animation.interactiveSpring().delay(-0.20)),
        ]

        for testCase in residualFirstCases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            if completionRecorder.events.isEmpty {
                harness.setTime(2.8)
                _ = harness.currentValue()
                harness.flushCompletionActions()
            }
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomResidualBaseDelayEdgesKeepFamilyOrdering() {
        let residualFirstCases: [(label: String, animation: Animation, finalTime: TimeInterval)] = [
            ("defaultDelayNegative", Animation.default.delay(-0.20), 2.0),
            (
                "fluidDelayNegative",
                Animation.spring(response: 0.35, dampingFraction: 0.70).delay(-0.50),
                3.0
            ),
            (
                "springDelayNegative",
                Animation.interpolatingSpring(
                    mass: 1.0,
                    stiffness: 75.0,
                    damping: 9.0,
                    initialVelocity: 0.0
                ).delay(-0.20),
                5.2
            ),
            (
                "springDelayZero",
                Animation.interpolatingSpring(
                    mass: 1.0,
                    stiffness: 75.0,
                    damping: 9.0,
                    initialVelocity: 0.0
                ).delay(0.0),
                5.2
            ),
        ]

        for testCase in residualFirstCases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.1)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(testCase.finalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }

        let oldSourceLogicalBeforeRemovedCases: [(label: String, animation: Animation)] = [
            ("defaultDelayZero", Animation.default.delay(0.0)),
            ("fluidDelayZero", Animation.spring(response: 0.35, dampingFraction: 0.70).delay(0.0)),
        ]

        for testCase in oldSourceLogicalBeforeRemovedCases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: 3.2,
                secondDuration: 3.2
            )
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(4.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomFluidSpringPropertyAliasNonPositiveSpeedKeepsReplacementPending() {
        let cases: [(label: String, animation: Animation)] = [
            ("springNoArgSpeedZero", Animation.spring().speed(0.0)),
            ("springPropertySpeedZero", Animation.spring.speed(0.0)),
            ("springPropertySpeedNegative", Animation.spring.speed(-1.0)),
            ("springNoArgSpeedNegative", Animation.spring().speed(-1.0)),
            ("interactivePropertySpeedZero", Animation.interactiveSpring.speed(0.0)),
            ("interactivePropertySpeedNegative", Animation.interactiveSpring.speed(-1.0)),
            ("interactiveNoArgSpeedZero", Animation.interactiveSpring().speed(0.0)),
            ("interactiveNoArgSpeedNegative", Animation.interactiveSpring().speed(-1.0)),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
        }
    }

    func testCombinedCustomFiniteRetargetKeepsResidualChildrenUntilBoundary() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 2.2,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 2.6,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.30),
                label: "finite",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("finite ") })
        harness.setTime(1.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "second removed",
                "finite removed",
                "finite logical",
                "old logical",
                "second logical",
            ]
        )
    }

    func testCombinedCustomDirectFiniteVariantsKeepGroupedBoundaryOrder() {
        let cubicUnitCurve = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.42, y: 0),
            endControlPoint: UnitPoint(x: 0.58, y: 1)
        )
        let cases: [(label: String, animation: Animation)] = [
            ("linear", .linear(duration: 0.30)),
            (
                "p1p2",
                .timingCurve(0.18, 0.07, 0.82, 0.96, duration: 0.30)
            ),
            ("easeInOut", .easeInOut(duration: 0.30)),
            ("easeIn", .easeIn(duration: 0.30)),
            ("easeOut", .easeOut(duration: 0.30)),
            ("circularIn", .timingCurve(.circularEaseIn, duration: 0.30)),
            ("circularOut", .timingCurve(.circularEaseOut, duration: 0.30)),
            ("circularInOut", .timingCurve(.circularEaseInOut, duration: 0.30)),
            ("cubic", .timingCurve(cubicUnitCurve, duration: 0.30)),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let harness = setup.harness
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder

            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.2)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("\(testCase.label) ") }, testCase.label)

            harness.setTime(1.6)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomZeroDurationRetargetFinishesImmediateGroup() {
        let cases: [(label: String, animation: Animation)] = [
            ("zero", .linear(duration: 0)),
            ("negativeLinear", .linear(duration: -0.20)),
            ("negativeCircular", .timingCurve(.circularEaseInOut, duration: -0.20)),
            (
                "interpolatingZero",
                .interpolatingSpring(duration: 0, bounce: 0.15, initialVelocity: 0)
            ),
            (
                "interpolatingNegative",
                .interpolatingSpring(duration: -0.20, bounce: 0.15, initialVelocity: 0)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let harness = setup.harness
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            XCTAssertEqual(harness.currentValue().opacity, 0.75, accuracy: 0.000_001, testCase.label)
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomZeroDurationSecondNilKeepsLogicalInImmediateGroup() {
        let cases: [(label: String, animation: Animation)] = [
            ("zero", .linear(duration: 0)),
            ("negativeLinear", .linear(duration: -0.20)),
            ("negativeCircular", .timingCurve(.circularEaseInOut, duration: -0.20)),
            (
                "interpolatingZero",
                .interpolatingSpring(duration: 0, bounce: 0.15, initialVelocity: 0)
            ),
            (
                "interpolatingNegative",
                .interpolatingSpring(duration: -0.20, bounce: 0.15, initialVelocity: 0)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: 10.0,
                secondDuration: 0.30
            )
            let harness = setup.harness
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(1.3)
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            XCTAssertEqual(harness.currentValue().opacity, 0.75, accuracy: 0.000_001, testCase.label)
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomVelocityTrackingRetargetFinishesImmediateGroup() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 3.2,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 3.2,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        let trackedTransaction = velocityTrackingCompletionTransaction(
            label: "tracked",
            recorder: completionRecorder
        )
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: trackedTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0.75, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "second removed",
                "tracked removed",
                "tracked logical",
                "old logical",
                "second logical",
            ]
        )
    }

    func testVelocityTrackingCompletionDoesNotWaitForHiddenSamplerWindow() {
        let completionRecorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: velocityTrackingCompletionTransaction(
                label: "tracked",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        let sampledValue = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(sampledValue, 0)
        XCTAssertLessThanOrEqual(sampledValue, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "tracked removed",
                "tracked logical",
            ]
        )

        completionRecorder.removeAll()
        harness.setTime(0.5)
        let laterValue = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(laterValue, 0)
        XCTAssertLessThanOrEqual(laterValue, 1)
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, [])
    }

    func testCombinedCustomVelocityTrackingSecondNilDrainsLogicalBeforeImmediateGroup() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.30,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        XCTAssertEqual(completionRecorder.events, [])
        sampleRecorder.removeAll()
        harness.setTime(1.3)
        let trackedTransaction = velocityTrackingCompletionTransaction(
            label: "tracked",
            recorder: completionRecorder
        )
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: trackedTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0.75, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "tracked removed",
                "tracked logical",
                "old logical",
            ]
        )
    }

    func testCombinedCustomVelocityTrackingMiddleNilDrainsLogicalBeforeImmediateGroup() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.30,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        XCTAssertEqual(completionRecorder.events, [])
        sampleRecorder.removeAll()
        harness.setTime(1.3)
        let trackedTransaction = velocityTrackingCompletionTransaction(
            label: "tracked",
            recorder: completionRecorder
        )
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: trackedTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0.75, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "tracked removed",
                "tracked logical",
                "old logical",
            ]
        )
    }
    func testCombinedCustomFiniteMiddleNilKeepsRemovedRecordsUntilBoundary() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.45,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1.25),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 1)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.30),
                label: "finite",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("finite ") })
        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])
        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "third removed",
                "finite removed",
                "finite logical",
                "old logical",
                "third logical",
            ]
        )
    }

    func testCombinedCustomFiniteSecondNilDrainsLogicalBeforeBoundary() {
        let setup = makeCombinedTwoChildHarness(secondDuration: 0.45)
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.82),
                label: "finite",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("finite ") })

        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])

        harness.setTime(2.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "finite removed",
                "finite logical",
                "old logical",
            ]
        )
    }

    func testCombinedCustomDirectFiniteNonLinearMiddleNilKeepsRemovedRecordsUntilBoundary() {
        let cases: [(label: String, animation: Animation)] = [
            (
                "p1p2",
                .timingCurve(0.18, 0.07, 0.82, 0.96, duration: 0.82)
            ),
            (
                "circular",
                .timingCurve(.circularEaseInOut, duration: 0.82)
            ),
            (
                "easeOut",
                .easeOut(duration: 0.82)
            ),
        ]
        for testCase in cases {
            let setup = makeCombinedMiddleNilHarness(
                oldDuration: 10.0,
                secondDuration: 0.45,
                thirdDuration: 10.0
            )
            let harness = setup.harness
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder

            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.4)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("\(testCase.label) ") }, testCase.label)

            harness.setTime(1.5)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["second logical"], testCase.label)

            harness.setTime(2.5)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "second logical",
                    "old removed",
                    "second removed",
                    "third removed",
                    "\(testCase.label) removed",
                    "\(testCase.label) logical",
                    "old logical",
                    "third logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomFiniteDelaySecondNilDrainsLogicalBeforeWrapperBoundary() {
        let setup = makeCombinedTwoChildHarness(secondDuration: 0.45)
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.30).delay(0.20),
                label: "wrapper",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("wrapper ") })

        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])

        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "wrapper removed",
                "wrapper logical",
                "old logical",
            ]
        )
    }

    func testCombinedCustomFiniteWrapperVariantsKeepGroupedBoundaryOrder() {
        let cubicUnitCurve = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.42, y: 0),
            endControlPoint: UnitPoint(x: 0.58, y: 1)
        )
        let cases: [(label: String, animation: Animation)] = [
            (
                "p1p2Delay",
                .timingCurve(0.18, 0.07, 0.82, 0.96, duration: 0.30).delay(0.20)
            ),
            (
                "p1p2Speed",
                .timingCurve(0.18, 0.07, 0.82, 0.96, duration: 0.90).speed(2.0)
            ),
            (
                "p1p2Repeat",
                .timingCurve(0.18, 0.07, 0.82, 0.96, duration: 0.22).repeatCount(2, autoreverses: false)
            ),
            (
                "namedDelay",
                .easeInOut(duration: 0.30).delay(0.20)
            ),
            (
                "namedSpeed",
                .easeIn(duration: 0.90).speed(2.0)
            ),
            (
                "namedRepeat",
                .easeOut(duration: 0.22).repeatCount(2, autoreverses: false)
            ),
            (
                "circularInDelay",
                .timingCurve(.circularEaseIn, duration: 0.30).delay(0.20)
            ),
            (
                "circularOutSpeed",
                .timingCurve(.circularEaseOut, duration: 0.90).speed(2.0)
            ),
            (
                "circularInOutRepeat",
                .timingCurve(.circularEaseInOut, duration: 0.22).repeatCount(2, autoreverses: false)
            ),
            (
                "cubicDelay",
                .timingCurve(cubicUnitCurve, duration: 0.30).delay(0.20)
            ),
            (
                "cubicSpeed",
                .timingCurve(cubicUnitCurve, duration: 0.90).speed(2.0)
            ),
            (
                "cubicRepeat",
                .timingCurve(cubicUnitCurve, duration: 0.22).repeatCount(2, autoreverses: false)
            ),
        ]
        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let harness = setup.harness
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder

            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.4)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("\(testCase.label) ") }, testCase.label)

            harness.setTime(2.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomLogicalCompletionWrapperDrainsReplacementLogicalBeforeGroupedBoundary() {
        let setup = makeCombinedTwoChildHarness()
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.82).logicallyComplete(after: 0.25),
                label: "logicalWrapper",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertEqual(completionRecorder.events, [])

        harness.setTime(1.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["logicalWrapper logical"])

        harness.setTime(2.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "logicalWrapper logical",
                "old removed",
                "second removed",
                "logicalWrapper removed",
                "old logical",
                "second logical",
            ]
        )
    }

    func testCombinedCustomDefaultLogicalCompletionWrapperDrainsSourceLogicalBeforeRemovedBoundary() {
        let setup = makeCombinedTwoChildHarness()
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.default.logicallyComplete(after: 0.25),
                label: "defaultLogicalWrapper",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertEqual(completionRecorder.events, ["defaultLogicalWrapper logical"])

        harness.setTime(3.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "defaultLogicalWrapper logical",
                "old logical",
                "second logical",
                "old removed",
                "second removed",
                "defaultLogicalWrapper removed",
            ]
        )
    }

    func testCombinedCustomFiniteRepeatSecondNilDrainsLogicalBeforeFinalRepeatBoundary() {
        let setup = makeCombinedTwoChildHarness(secondDuration: 0.45)
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.22).repeatCount(2, autoreverses: false),
                label: "repeat",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("repeat ") })

        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])

        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "repeat removed",
                "repeat logical",
                "old logical",
            ]
        )
    }

    func testCombinedCustomFiniteDelayMiddleNilKeepsRemovedRecordsUntilWrapperBoundary() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.45,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1.25),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 1)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.30).delay(0.20),
                label: "wrapper",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("wrapper ") })
        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])
        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "third removed",
                "wrapper removed",
                "wrapper logical",
                "old logical",
                "third logical",
            ]
        )
    }
    func testCombinedCustomFiniteSpeedMiddleNilKeepsRemovedRecordsUntilWrapperBoundary() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.45,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1.25),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 1)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.90).speed(2.0),
                label: "speed",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("speed ") })
        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])
        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "third removed",
                "speed removed",
                "speed logical",
                "old logical",
                "third logical",
            ]
        )
    }
    func testCombinedCustomFiniteRepeatMiddleNilKeepsRemovedRecordsUntilFinalRepeatBoundary() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.45,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1.25),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 1)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.22).repeatCount(2, autoreverses: false),
                label: "repeat",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("repeat ") })
        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])
        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "third removed",
                "repeat removed",
                "repeat logical",
                "old logical",
                "third logical",
            ]
        )
    }

    func testCombinedCustomSourceCustomSecondNilKeepsRemovedRecordsUntilReplacementNil() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.45,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 1.35,
                        recorder: sampleRecorder
                    )
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("third ") })
        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])
        harness.setTime(2.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "third removed",
                "third logical",
                "old logical",
            ]
        )
    }

    func testCombinedCustomSourceCustomMiddleNilKeepsRemovedRecordsUntilReplacementNil() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.45,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 1)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: -1.1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "fourth",
                        duration: 1.35,
                        recorder: sampleRecorder
                    )
                ),
                label: "fourth",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "fourth" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("fourth ") })
        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])
        harness.setTime(2.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "third removed",
                "fourth removed",
                "fourth logical",
                "old logical",
                "third logical",
            ]
        )
    }
    func testCombinedCustomSourceCustomDelayMiddleNilDoesNotForwardReplacementShouldMerge() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.45,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 1)
        let shouldMergeBeforeFourth = sampleRecorder.shouldMergeCount
        harness.setSource(
            _OpacityEffect(opacity: -1.1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "fourth",
                        duration: 1.20,
                        recorder: sampleRecorder
                    )
                ).delay(0.22),
                label: "fourth",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(sampleRecorder.shouldMergeCount, shouldMergeBeforeFourth)
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "fourth" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("fourth ") })
        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])
        harness.setTime(3.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "old removed",
                "second removed",
                "third removed",
                "fourth removed",
                "fourth logical",
                "old logical",
                "third logical",
            ]
        )
    }
    func testCombinedCustomSourceCustomFiniteWrappersKeepCompletionOwnership() {
        let cases: [
            (
                label: String,
                wrap: (Animation) -> Animation,
                finalTime: TimeInterval
            )
        ] = [
            (
                "thirdDelay",
                { $0.delay(0.25) },
                3.00
            ),
            (
                "thirdSpeed",
                { $0.speed(2) },
                2.50
            ),
            (
                "thirdRepeat",
                { $0.repeatCount(2, autoreverses: false) },
                4.00
            ),
        ]

        for testCase in cases {
            assertCombinedSourceCustomWrapperFinalization(
                label: testCase.label,
                wrap: testCase.wrap,
                finalTime: testCase.finalTime
            )
        }
    }

    func testCombinedCustomSourceCustomNestedWrappersKeepCompletionOwnership() {
        let cases: [
            (
                label: String,
                wrap: (Animation) -> Animation,
                finalTime: TimeInterval
            )
        ] = [
            (
                "thirdRepeatAutoreverse",
                { $0.repeatCount(2, autoreverses: true) },
                4.50
            ),
            (
                "thirdDelayRepeat",
                { $0.delay(0.25).repeatCount(2, autoreverses: false) },
                4.50
            ),
            (
                "thirdRepeatDelay",
                { $0.repeatCount(2, autoreverses: false).delay(0.25) },
                4.20
            ),
            (
                "thirdSpeedRepeat",
                { $0.speed(2).repeatCount(2, autoreverses: false) },
                3.00
            ),
            (
                "thirdRepeatSpeed",
                { $0.repeatCount(2, autoreverses: false).speed(2) },
                3.00
            ),
            (
                "thirdDelaySpeed",
                { $0.delay(0.25).speed(2) },
                2.50
            ),
            (
                "thirdSpeedDelay",
                { $0.speed(2).delay(0.25) },
                3.00
            ),
        ]

        for testCase in cases {
            assertCombinedSourceCustomWrapperFinalization(
                label: testCase.label,
                wrap: testCase.wrap,
                finalTime: testCase.finalTime
            )
        }
    }

    func testCombinedCustomSourceCustomTripleNestedWrappersKeepCompletionOwnership() {
        let cases: [
            (
                label: String,
                wrap: (Animation) -> Animation,
                finalTime: TimeInterval
            )
        ] = [
            (
                "thirdDelayRepeatSpeed",
                { $0.delay(0.25).repeatCount(2, autoreverses: false).speed(2) },
                5.40
            ),
            (
                "thirdRepeatDelaySpeed",
                { $0.repeatCount(2, autoreverses: false).delay(0.25).speed(2) },
                5.40
            ),
            (
                "thirdSpeedDelayRepeat",
                { $0.speed(2).delay(0.25).repeatCount(2, autoreverses: false) },
                5.40
            ),
        ]

        for testCase in cases {
            assertCombinedSourceCustomWrapperFinalization(
                label: testCase.label,
                wrap: testCase.wrap,
                finalTime: testCase.finalTime
            )
        }
    }

    func testCombinedCustomSourceCustomInfiniteWrappersKeepRemovalPending() {
        let cases: [
            (
                label: String,
                wrap: (Animation) -> Animation,
                expectedEvents: [String]
            )
        ] = [
            (
                "thirdSpeedZero",
                { $0.speed(0) },
                []
            ),
            (
                "thirdSpeedNegative",
                { $0.speed(-1) },
                []
            ),
            (
                "thirdRepeatForever",
                { $0.repeatForever(autoreverses: false) },
                ["third logical"]
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let harness = setup.harness
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let shouldMergeBeforeThird = sampleRecorder.shouldMergeCount
            let thirdAnimation = Animation(
                RetargetBoundaryRecordingAnimation(
                    label: "third",
                    logicalAt: 0.45,
                    nilAt: 0.75,
                    recorder: sampleRecorder
                )
            )
            harness.setSource(
                _OpacityEffect(opacity: 1.25),
                transaction: completionTransaction(
                    animation: testCase.wrap(thirdAnimation),
                    label: "third",
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.1)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(sampleRecorder.shouldMergeCount, shouldMergeBeforeThird, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(2.4)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, testCase.expectedEvents, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
        }
    }
    func testCombinedCustomFiniteDelayRetargetKeepsResidualChildrenUntilWrapperBoundary() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 2.2,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 2.6,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.30).delay(0.20),
                label: "wrapper",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("wrapper ") })
        harness.setTime(1.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "second removed",
                "wrapper removed",
                "wrapper logical",
                "old logical",
                "second logical",
            ]
        )
    }
    func testCombinedCustomFiniteRepeatRetargetKeepsResidualChildrenUntilFinalRepeatBoundary() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 2.2,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 2.6,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.linear(duration: 0.22).repeatCount(2, autoreverses: false),
                label: "repeat",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertFalse(completionRecorder.events.contains { $0.hasPrefix("repeat ") })
        harness.setTime(1.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "second removed",
                "repeat removed",
                "repeat logical",
                "old logical",
                "second logical",
            ]
        )
    }
    func testCombinedCustomDefaultRetargetKeepsResidualChildrenUntilFinalization() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: .default,
                label: "residual",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertEqual(completionRecorder.events, ["residual logical"])
        harness.setTime(3.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "residual logical",
                "old removed",
                "second removed",
                "residual removed",
                "old logical",
                "second logical",
            ]
        )
    }

    func testCombinedCustomDefaultSecondNilDrainsLogicalBeforeResidualLogical() {
        let setup = makeCombinedTwoChildHarness(secondDuration: 0.45)
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: .default,
                label: "residual",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertEqual(completionRecorder.events, [])

        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])

        harness.setTime(1.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "residual logical",
            ]
        )

        harness.setTime(3.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "residual logical",
                "old removed",
                "second removed",
                "residual removed",
                "old logical",
            ]
        )
    }

    func testCombinedCustomDefaultMiddleNilKeepsRemovedRecordsUntilFinalization() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.45,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1.25),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 1)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: .default,
                label: "residual",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        XCTAssertEqual(completionRecorder.events, [])
        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
            ]
        )
        harness.setTime(1.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "residual logical",
            ]
        )
        harness.setTime(3.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "residual logical",
                "old removed",
                "second removed",
                "third removed",
                "residual removed",
                "old logical",
                "third logical",
            ]
        )
    }

    func testCombinedCustomSpringAnimationSecondNilDrainsLogicalBeforeFinalization() {
        let setup = makeCombinedTwoChildHarness(secondDuration: 0.45)
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.interpolatingSpring(
                    Spring(duration: 0.50, bounce: 0.20),
                    initialVelocity: 0.0
                ),
                label: "spring",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })

        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])

        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "spring logical",
            ]
        )

        harness.setTime(3.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "spring logical",
                "old removed",
                "second removed",
                "spring removed",
                "old logical",
            ]
        )
    }

    func testCombinedCustomSpringAnimationMiddleNilKeepsRemovedRecordsUntilFinalization() {
        let setup = makeCombinedMiddleNilHarness()
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.interpolatingSpring(
                    Spring(duration: 0.50, bounce: 0.20),
                    initialVelocity: 0.0
                ),
                label: "spring",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })

        harness.setTime(1.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])

        harness.setTime(2.2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "spring logical",
                "old removed",
                "second removed",
                "third removed",
                "spring removed",
                "old logical",
                "third logical",
            ]
        )
    }

    func testCombinedCustomFluidSpringSecondNilDrainsLogicalBeforeFinalization() {
        let setup = makeCombinedTwoChildHarness(secondDuration: 0.45)
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: .spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0),
                label: "fluid",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })

        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["second logical"])

        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "fluid logical",
                "old removed",
                "second removed",
                "fluid removed",
                "old logical",
            ]
        )
    }

    func testCombinedCustomFluidSpringAliasSecondNilCompletionOrdering() {
        let secondNilRows: [(label: String, animation: Animation, finalTime: TimeInterval)] = [
            ("springDuration", .spring(duration: 0.50, bounce: 0.20), 3.0),
            ("springNoArg", .spring(), 3.0),
        ]

        for row in secondNilRows {
            let setup = makeCombinedTwoChildHarness(secondDuration: 0.45)
            let harness = setup.harness
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder

            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: row.animation,
                    label: row.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, row.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, row.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, row.label)
            XCTAssertEqual(completionRecorder.events, [], row.label)

            harness.setTime(1.5)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["second logical"], row.label)

            harness.setTime(row.finalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            let residualBeforeRemovedOrder = [
                "second logical",
                "\(row.label) logical",
                "old removed",
                "second removed",
                "\(row.label) removed",
                "old logical",
            ]
            let residualSameBoundaryOrder = [
                "second logical",
                "old removed",
                "second removed",
                "\(row.label) removed",
                "\(row.label) logical",
                "old logical",
            ]
            XCTAssertTrue(
                [residualBeforeRemovedOrder, residualSameBoundaryOrder].contains(completionRecorder.events),
                "\(row.label) events \(completionRecorder.events)"
            )
        }

        let residualFirstRows: [(label: String, animation: Animation)] = [
            (
                "interactiveDuration",
                .interactiveSpring(duration: 0.50, extraBounce: 0.20, blendDuration: 0)
            ),
            ("interactiveNoArg", .interactiveSpring()),
        ]

        for row in residualFirstRows {
            let setup = makeCombinedTwoChildHarness()
            let harness = setup.harness
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder

            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: row.animation,
                    label: row.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, row.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, row.label)
            XCTAssertEqual(completionRecorder.events, ["\(row.label) logical"], row.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, row.label)
            XCTAssertFalse(completionRecorder.events.contains("second logical"), row.label)

            harness.setTime(3.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(row.label) logical",
                    "old removed",
                    "second removed",
                    "\(row.label) removed",
                    "old logical",
                    "second logical",
                ],
                row.label
            )
        }
    }

    func testCombinedCustomFluidSpringAliasMiddleNilCompletionOrdering() {
        let sourceNilRows: [(label: String, animation: Animation)] = [
            ("springDuration", .spring(duration: 0.50, bounce: 0.20)),
            ("springNoArg", .spring()),
        ]

        for row in sourceNilRows {
            let setup = makeCombinedMiddleNilHarness(
                oldDuration: 3.2,
                secondDuration: 0.75,
                thirdDuration: 3.2
            )
            let harness = setup.harness
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder

            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: row.animation,
                    label: row.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, row.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, row.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" }, row.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, row.label)

            harness.setTime(1.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()

            harness.setTime(3.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "second logical",
                    "\(row.label) logical",
                    "old removed",
                    "second removed",
                    "third removed",
                    "\(row.label) removed",
                    "old logical",
                    "third logical",
                ],
                row.label
            )
        }

        let residualFirstRows: [(label: String, animation: Animation)] = [
            (
                "interactiveDuration",
                .interactiveSpring(duration: 0.50, extraBounce: 0.20, blendDuration: 0)
            ),
            ("interactiveNoArg", .interactiveSpring()),
        ]

        for row in residualFirstRows {
            let setup = makeCombinedMiddleNilHarness(
                oldDuration: 3.2,
                secondDuration: 0.75,
                thirdDuration: 3.2
            )
            let harness = setup.harness
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder

            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: row.animation,
                    label: row.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, row.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, row.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" }, row.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, row.label)

            harness.setTime(1.5)
            _ = harness.currentValue()
            harness.flushCompletionActions()

            harness.setTime(3.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(row.label) logical",
                    "old removed",
                    "second removed",
                    "third removed",
                    "\(row.label) removed",
                    "old logical",
                    "second logical",
                    "third logical",
                ],
                row.label
            )
        }
    }

    func testCombinedCustomFluidSpringMiddleNilKeepsRemovedRecordsUntilFinalization() {
        let setup = makeCombinedMiddleNilHarness()
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder

        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: .spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0),
                label: "fluid",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })

        harness.setTime(1.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "fluid logical",
            ]
        )

        harness.setTime(2.2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "fluid logical",
                "old removed",
                "second removed",
                "third removed",
                "fluid removed",
                "old logical",
                "third logical",
            ]
        )
    }

    func testCombinedCustomDefaultDelayMiddleNilDrainsSourceLogicalBeforeRemovedFinalization() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 2.2,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 0.45,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1.25),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "third",
                        duration: 1.2,
                        recorder: sampleRecorder
                    )
                ),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 1)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.default.delay(0.20),
                label: "residual",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        harness.setTime(1.5)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
            ]
        )
        harness.setTime(2.4)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "residual logical",
                "old logical",
                "third logical",
                "old removed",
                "second removed",
                "third removed",
                "residual removed",
            ]
        )
        harness.setTime(2.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "second logical",
                "residual logical",
                "old logical",
                "third logical",
                "old removed",
                "second removed",
                "third removed",
                "residual removed",
            ]
        )
    }
    func testCombinedCustomFluidSpringRetargetKeepsResidualChildrenUntilFinalization() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: .spring(response: 0.35, dampingFraction: 0.70),
                label: "fluid",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        harness.setTime(3.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "fluid logical",
                "old removed",
                "second removed",
                "fluid removed",
                "old logical",
                "second logical",
            ]
        )
    }
    func testCombinedCustomDurationSpringRetargetKeepsResidualChildrenUntilFinalization() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: .spring(duration: 0.50, bounce: 0.20),
                label: "duration",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertTrue(completionRecorder.events.isEmpty)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(completionRecorder.events.isEmpty)
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(completionRecorder.events.isEmpty)
        harness.setTime(1.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "second removed",
                "duration removed",
                "duration logical",
                "old logical",
                "second logical",
            ]
        )
    }
    func testCombinedCustomSpringValueRetargetKeepsResidualChildrenUntilFinalization() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: .spring(Spring(duration: 0.50, bounce: 0.20), blendDuration: 0),
                label: "value",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertTrue(completionRecorder.events.isEmpty)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(completionRecorder.events.isEmpty)
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertTrue(completionRecorder.events.isEmpty)
        harness.setTime(1.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "second removed",
                "value removed",
                "value logical",
                "old logical",
                "second logical",
            ]
        )
    }
    func testCombinedCustomSpringPropertyRetargetKeepsResidualChildrenUntilFinalization() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: Animation.spring,
                label: "property",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        harness.setTime(3.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "property logical",
                "old removed",
                "second removed",
                "property removed",
                "old logical",
                "second logical",
            ]
        )
    }
    func testCombinedCustomSpringAnimationAliasWrappersKeepResidualChildrenUntilFinalization() {
        let springValue = Animation.interpolatingSpring(
            Spring(duration: 0.50, bounce: 0.20),
            initialVelocity: 0.0
        )
        let springDuration = Animation.interpolatingSpring(
            duration: 0.50,
            bounce: 0.20,
            initialVelocity: 0.0
        )
        let cases: [(label: String, animation: Animation, finalTime: TimeInterval)] = [
            (
                "springAliasValueDelay",
                springValue.delay(0.20),
                6.0
            ),
            (
                "springAliasDurationSpeed",
                springDuration.speed(0.5),
                7.0
            ),
            (
                "springAliasDefaultRepeat",
                Animation.interpolatingSpring.repeatCount(2, autoreverses: false),
                6.0
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(testCase.finalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomSpringAnimationAliasRepeatEdgesKeepResidualChildrenUntilFinalization() {
        let springValue = Animation.interpolatingSpring(
            Spring(duration: 0.50, bounce: 0.20),
            initialVelocity: 0.0
        )
        let springDuration = Animation.interpolatingSpring(
            duration: 0.50,
            bounce: 0.20,
            initialVelocity: 0.0
        )
        let cases: [(label: String, animation: Animation, logicalTime: TimeInterval, finalTime: TimeInterval)] = [
            (
                "springAliasValueRepeatZero",
                springValue.repeatCount(0, autoreverses: false),
                2.0,
                3.2
            ),
            (
                "springAliasDurationRepeatNegative",
                springDuration.repeatCount(-2, autoreverses: false),
                2.0,
                3.2
            ),
            (
                "springAliasDefaultRepeatAuto",
                Animation.interpolatingSpring.repeatCount(2, autoreverses: true),
                2.2,
                6.0
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            harness.setTime(testCase.logicalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["\(testCase.label) logical"], testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(testCase.finalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomResidualNestedDelayRepeatWrappersKeepResidualOwnership() {
        let defaultBase = Animation.default
        let fluidBase = Animation.spring(response: 0.35, dampingFraction: 0.70)
        let springBase = Animation.interpolatingSpring(
            mass: 1.0,
            stiffness: 75.0,
            damping: 9.0,
            initialVelocity: 0.0
        )
        let cases: [(label: String, animation: Animation)] = [
            (
                "defaultDelayRepeat",
                defaultBase.delay(0.20).repeatCount(2, autoreverses: false)
            ),
            (
                "defaultRepeatDelay",
                defaultBase.repeatCount(2, autoreverses: false).delay(0.20)
            ),
            (
                "fluidDelayRepeat",
                fluidBase.delay(0.20).repeatCount(2, autoreverses: false)
            ),
            (
                "fluidRepeatDelay",
                fluidBase.repeatCount(2, autoreverses: false).delay(0.20)
            ),
            (
                "springDelayRepeat",
                springBase.delay(0.20).repeatCount(2, autoreverses: false)
            ),
            (
                "springRepeatDelay",
                springBase.repeatCount(2, autoreverses: false).delay(0.20)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness(
                oldDuration: 3.2,
                secondDuration: 3.2
            )
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(10.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old logical",
                    "second logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomResidualNestedSpeedRepeatWrappersKeepResidualOwnership() {
        let fluidBase = Animation.spring(response: 0.35, dampingFraction: 0.70)
        let springBase = Animation.interpolatingSpring(
            mass: 1.0,
            stiffness: 75.0,
            damping: 9.0,
            initialVelocity: 0.0
        )
        let cases: [(label: String, animation: Animation, finalTime: TimeInterval)] = [
            (
                "fluidSpeedRepeat",
                fluidBase.speed(2.0).repeatCount(2, autoreverses: false),
                5.6
            ),
            (
                "fluidRepeatSpeed",
                fluidBase.repeatCount(2, autoreverses: false).speed(2.0),
                5.6
            ),
            (
                "springSpeedRepeat",
                springBase.speed(2.0).repeatCount(2, autoreverses: false),
                6.4
            ),
            (
                "springRepeatSpeed",
                springBase.repeatCount(2, autoreverses: false).speed(2.0),
                6.4
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(testCase.finalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomDefaultNestedSpeedRepeatWrappersKeepVariableResidualOwnership() {
        let defaultBase = Animation.default
        let cases: [(label: String, animation: Animation)] = [
            (
                "defaultSpeedRepeat",
                defaultBase.speed(2.0).repeatCount(2, autoreverses: false)
            ),
            (
                "defaultRepeatSpeed",
                defaultBase.repeatCount(2, autoreverses: false).speed(2.0)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(10.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            let residualFirstOrder = [
                "\(testCase.label) logical",
                "old removed",
                "second removed",
                "\(testCase.label) removed",
                "old logical",
                "second logical",
            ]
            let oldSourceNilBeforeRemovedOrder = [
                "\(testCase.label) logical",
                "old logical",
                "second logical",
                "old removed",
                "second removed",
                "\(testCase.label) removed",
            ]
            XCTAssertTrue(
                [residualFirstOrder, oldSourceNilBeforeRemovedOrder].contains(completionRecorder.events),
                "\(testCase.label) events \(completionRecorder.events)"
            )
        }
    }

    func testCombinedCustomResidualNestedDelaySpeedWrappersKeepResidualOwnership() {
        let defaultBase = Animation.default
        let fluidBase = Animation.spring(response: 0.35, dampingFraction: 0.70)
        let springBase = Animation.interpolatingSpring(
            mass: 1.0,
            stiffness: 75.0,
            damping: 9.0,
            initialVelocity: 0.0
        )
        let cases: [(label: String, animation: Animation)] = [
            (
                "defaultDelaySpeed",
                defaultBase.delay(0.20).speed(2.0)
            ),
            (
                "defaultSpeedDelay",
                defaultBase.speed(2.0).delay(0.20)
            ),
            (
                "fluidDelaySpeed",
                fluidBase.delay(0.20).speed(2.0)
            ),
            (
                "fluidSpeedDelay",
                fluidBase.speed(2.0).delay(0.20)
            ),
            (
                "springDelaySpeed",
                springBase.delay(0.20).speed(2.0)
            ),
            (
                "springSpeedDelay",
                springBase.speed(2.0).delay(0.20)
            ),
        ]

        for testCase in cases {
            let setup = makeCombinedTwoChildHarness()
            let completionRecorder = setup.completionRecorder
            let sampleRecorder = setup.sampleRecorder
            let harness = setup.harness
            harness.setSource(
                _OpacityEffect(opacity: 0.75),
                transaction: completionTransaction(
                    animation: testCase.animation,
                    label: testCase.label,
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            harness.setTime(10.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                [
                    "\(testCase.label) logical",
                    "old removed",
                    "second removed",
                    "\(testCase.label) removed",
                    "old logical",
                    "second logical",
                ],
                testCase.label
            )
        }
    }

    func testCombinedCustomSpringRetargetKeepsResidualChildrenUntilFinalization() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: 10.0,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        sampleRecorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: completionTransaction(
                animation: .interpolatingSpring(mass: 1.0, stiffness: 100.0, damping: 10.0),
                label: "spring",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" })
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" })
        XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") })
        harness.setTime(2.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["spring logical"])
        harness.setTime(3.0)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "spring logical",
                "old removed",
                "second removed",
                "spring removed",
                "old logical",
                "second logical",
            ]
        )
    }
    func testNoAnimationRetargetTransactionCompletionFallsBackImmediately() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(UnitLinearAnimation(duration: 4)),
                label: "old",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        XCTAssertGreaterThan(harness.currentValue().opacity, 0)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        let nilTransaction = completionTransaction(
            animation: nil,
            label: "nil",
            recorder: recorder
        )
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: 2))
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "nil removed",
                "nil logical",
            ]
        )
        recorder.removeAll()
    }

    private func makeCombinedMiddleNilHarness(
        wrapThirdAnimation: (Animation) -> Animation = { $0 },
        expectsThirdShouldMerge: Bool = true,
        oldDuration: TimeInterval = 2.20,
        secondDuration: TimeInterval = 0.75,
        thirdDuration: TimeInterval = 2.40,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (
        harness: AnimatableAttributeHarness,
        completionRecorder: AnimationCompletionRecorder,
        sampleRecorder: CustomRetargetSampleRecorder
    ) {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: oldDuration,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, file: file, line: line)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: secondDuration,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0, file: file, line: line)
        let shouldMergeAfterSecond = sampleRecorder.shouldMergeCount
        let thirdAnimation = wrapThirdAnimation(
            Animation(
                CombinedNilRetargetRecordingAnimation(
                    label: "third",
                    duration: thirdDuration,
                    recorder: sampleRecorder
                )
            )
        )
        harness.setSource(
            _OpacityEffect(opacity: 1.25),
            transaction: completionTransaction(
                animation: thirdAnimation,
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        if expectsThirdShouldMerge {
            XCTAssertGreaterThan(
                sampleRecorder.shouldMergeCount,
                shouldMergeAfterSecond,
                file: file,
                line: line
            )
        } else {
            XCTAssertEqual(
                sampleRecorder.shouldMergeCount,
                shouldMergeAfterSecond,
                file: file,
                line: line
            )
        }
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)
        sampleRecorder.removeAll()
        return (harness, completionRecorder, sampleRecorder)
    }

    private func assertCombinedSourceCustomWrapperFinalization(
        label: String,
        wrap: (Animation) -> Animation,
        finalTime: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let setup = makeCombinedTwoChildHarness(file: file, line: line)
        let harness = setup.harness
        let completionRecorder = setup.completionRecorder
        let sampleRecorder = setup.sampleRecorder
        let shouldMergeBeforeThird = sampleRecorder.shouldMergeCount
        let thirdAnimation = Animation(
            RetargetBoundaryRecordingAnimation(
                label: "third",
                logicalAt: 0.45,
                nilAt: 0.75,
                recorder: sampleRecorder
            )
        )
        harness.setSource(
            _OpacityEffect(opacity: 1.25),
            transaction: completionTransaction(
                animation: wrap(thirdAnimation),
                label: "third",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(sampleRecorder.shouldMergeCount, shouldMergeBeforeThird, label, file: file, line: line)
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, label, file: file, line: line)
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, label, file: file, line: line)
        XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "third" }, label, file: file, line: line)
        XCTAssertEqual(completionRecorder.events, [], label, file: file, line: line)
        var sampleTime = 1.3
        while sampleTime < finalTime {
            harness.setTime(sampleTime)
            _ = harness.currentValue()
            sampleTime += 0.2
        }
        harness.setTime(finalTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "third logical",
                "old removed",
                "second removed",
                "third removed",
                "old logical",
                "second logical",
            ],
            label,
            file: file,
            line: line
        )
    }

    private func makeCombinedTwoChildHarness(
        oldDuration: TimeInterval = 10.0,
        secondDuration: TimeInterval = 10.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (
        harness: AnimatableAttributeHarness,
        completionRecorder: AnimationCompletionRecorder,
        sampleRecorder: CustomRetargetSampleRecorder
    ) {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "old",
                        duration: oldDuration,
                        recorder: sampleRecorder
                    )
                ),
                label: "old",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, file: file, line: line)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: Animation(
                    CombinedNilRetargetRecordingAnimation(
                        label: "second",
                        duration: secondDuration,
                        recorder: sampleRecorder
                    )
                ),
                label: "second",
                recorder: completionRecorder
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0, file: file, line: line)
        XCTAssertEqual(completionRecorder.events, [], file: file, line: line)
        sampleRecorder.removeAll()
        return (harness, completionRecorder, sampleRecorder)
    }

    private func assertZeroDurationRetargetSnapAndOrder(
        oldAnimation: Animation,
        replacementAnimation: Animation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(
            harness.currentValue().opacity,
            0,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: "old",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(
            harness.currentValue().opacity,
            0,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        harness.setTime(0.1)
        _ = harness.currentValue()
        harness.setTime(0.2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [],
            "old animation callbacks should still be pending before the zero retarget",
            file: file,
            line: line
        )
        recorder.removeAll()
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: completionTransaction(
                animation: replacementAnimation,
                label: "zero",
                recorder: recorder
            )
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(
            harness.currentValue().opacity,
            2,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            recorder.events,
            [],
            "zero retarget callbacks should not fire before the target snap is observable",
            file: file,
            line: line
        )
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "zero removed",
                "zero logical",
                "old logical",
            ],
            file: file,
            line: line
        )
    }
}

private struct NonAnimatablePayload: Animatable, Equatable {
    var id: Int
    var animatableData: Double
}
