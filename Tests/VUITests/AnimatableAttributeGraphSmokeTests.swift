import XCTest
@testable import VUI
final class AnimatableAGGraphSmokeTests: XCTestCase {
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

    func testAnimatorStateQuantizedEarlyGateReusesPreviousSample() {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA61

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        _ = harness.currentValue()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let sampled = harness.currentValue().opacity
        XCTAssertGreaterThan(sampled, 0)

        harness.setTime(0.61)
        XCTAssertEqual(harness.currentValue().opacity, sampled, accuracy: 0.000_001)

        harness.setTime(0.66)
        XCTAssertGreaterThan(harness.currentValue().opacity, sampled)
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

    func testAnimatableAttributeTerminalSampleDoesNotScheduleNextUpdate() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        var transaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "finite",
            recorder: recorder
        )
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA33
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let runningValue = harness.currentValue().opacity
        XCTAssertGreaterThan(runningValue, 0)
        XCTAssertLessThan(runningValue, 1)
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)

        harness.resetNextUpdate()
        harness.setTime(4.0)
        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
        XCTAssertEqual(recorder.events, [])

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "finite removed",
                "finite logical",
            ]
        )
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
        var initialTransaction = Transaction(animation: .linear(duration: 1))
        initialTransaction.animationFrameInterval = 1.0 / 30.0
        initialTransaction.animationReason = 0xB31
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: initialTransaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let runningValue = harness.currentValue().opacity
        XCTAssertGreaterThan(runningValue, 0)
        XCTAssertLessThan(runningValue, 1)

        harness.resetNextUpdate()
        var sameTargetTransaction = Transaction(animation: .linear(duration: 1))
        sameTargetTransaction.animationListener = listener
        sameTargetTransaction.animationFrameInterval = 1.0 / 120.0
        sameTargetTransaction.animationReason = 0xB32
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: sameTargetTransaction
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.7)
        _ = harness.currentValue()
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xB31])

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

    func testActiveNoChangePayloadCompletionTransactionDoesNotAttachRecords() {
        let recorder = AnimationCompletionRecorder()
        let harness = GenericAnimatableAttributeHarness(
            initialValue: NonAnimatablePayload(id: 1, animatableData: 0)
        )
        XCTAssertEqual(harness.currentValue().animatableData, 0, accuracy: 0.000_001)

        var initialTransaction = Transaction(animation: .linear(duration: 1))
        initialTransaction.animationFrameInterval = 1.0 / 30.0
        initialTransaction.animationReason = 0xC33
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
        let sameTargetTransaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "same",
            recorder: recorder
        )
        harness.setSource(
            NonAnimatablePayload(id: 3, animatableData: 1),
            transaction: sameTargetTransaction
        )
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        harness.setTime(0.7)
        _ = harness.currentValue()

        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xC33])

        harness.setTime(2.0)
        XCTAssertEqual(harness.currentValue().animatableData, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
    }

    func testInactiveNoChangeRetainsCachedStatefulOutput() {
        let listener = CountingAnimationListener()
        let recorder = AnimationCompletionRecorder()
        let harness = GenericAnimatableAttributeHarness(
            initialValue: NonAnimatablePayload(id: 1, animatableData: 0.25)
        )
        XCTAssertEqual(harness.currentValue().id, 1)
        harness.resetNextUpdate()

        var transaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "same",
            recorder: recorder
        )
        transaction.animationListener = listener
        transaction.animationFrameInterval = 1.0 / 120.0
        transaction.animationReason = 0xC44
        harness.setSource(
            NonAnimatablePayload(id: 2, animatableData: 0.25),
            transaction: transaction
        )
        harness.finalizeTransactionBody()

        let output = harness.currentValue()
        XCTAssertEqual(output.id, 1)
        XCTAssertEqual(output.animatableData, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
        harness.flushCompletionActions()
        XCTAssertEqual(listener.removedCount, 0)
        XCTAssertEqual(recorder.events, [])
    }

    func testAnimatableAttributeViewSizeAnimatesPayloadButKeepsTargetProposal() {
        let initialProposal = ProposedViewSize(width: 80, height: 34)
        let targetProposal = ProposedViewSize(width: 160, height: 34)
        let harness = GenericAnimatableAttributeHarness(
            initialValue: ViewSize(width: 80, height: 34, proposal: initialProposal)
        )
        XCTAssertEqual(harness.currentValue().proposal, initialProposal)

        harness.setSource(
            ViewSize(width: 160, height: 34, proposal: targetProposal),
            transaction: Transaction(animation: .linear(duration: 1))
        )

        let activationSize = harness.currentValue()
        XCTAssertEqual(activationSize.width, 80, accuracy: 0.000_001)
        XCTAssertEqual(activationSize.height, 34, accuracy: 0.000_001)
        XCTAssertEqual(activationSize.proposal, targetProposal)

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        let midSize = harness.currentValue()
        XCTAssertGreaterThan(midSize.width, 80)
        XCTAssertLessThan(midSize.width, 160)
        XCTAssertEqual(midSize.height, 34, accuracy: 0.000_001)
        XCTAssertEqual(midSize.proposal, targetProposal)

        harness.setTime(2.0)
        let finalSize = harness.currentValue()
        XCTAssertEqual(finalSize.width, 160, accuracy: 0.000_001)
        XCTAssertEqual(finalSize.height, 34, accuracy: 0.000_001)
        XCTAssertEqual(finalSize.proposal, targetProposal)
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

    func testAnimatableFrameAttributeAnimatesSizePayloadButKeepsTargetProposal() {
        assertFrameAttributeAnimatesSizePayloadButKeepsTargetProposal(
            supportsVFD: false
        )
    }

    func testAnimatableFrameAttributeVFDAnimatesSizePayloadButKeepsTargetProposal() {
        assertFrameAttributeAnimatesSizePayloadButKeepsTargetProposal(
            supportsVFD: true
        )
    }

    private func assertFrameAttributeAnimatesSizePayloadButKeepsTargetProposal(
        supportsVFD: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let initialProposal = ProposedViewSize(width: 80, height: 34)
        let targetProposal = ProposedViewSize(width: 160, height: 34)
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 80, height: 34, proposal: initialProposal),
            supportsVFD: supportsVFD
        )
        XCTAssertEqual(harness.currentSize().proposal, initialProposal, file: file, line: line)

        harness.setFrame(
            position: .zero,
            size: ViewSize(width: 160, height: 34, proposal: targetProposal),
            transaction: Transaction(animation: .linear(duration: 1))
        )

        let activationSize = harness.currentSize()
        XCTAssertEqual(activationSize.width, 80, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(activationSize.height, 34, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(activationSize.proposal, targetProposal, file: file, line: line)

        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        let midSize = harness.currentSize()
        XCTAssertGreaterThan(midSize.width, 80, file: file, line: line)
        XCTAssertLessThan(midSize.width, 160, file: file, line: line)
        XCTAssertEqual(midSize.height, 34, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(midSize.proposal, targetProposal, file: file, line: line)

        harness.setTime(2.0)
        let finalSize = harness.currentSize()
        XCTAssertEqual(finalSize.width, 160, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(finalSize.height, 34, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(finalSize.proposal, targetProposal, file: file, line: line)
    }

    func testAnimatableFrameAttributeTerminalSampleDoesNotScheduleNextUpdate() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)

        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xF61
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: transaction
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        _ = harness.currentFrame()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)

        harness.resetNextUpdate()
        harness.setTime(4.0)
        let finalFrame = harness.currentFrame()
        XCTAssertEqual(finalFrame.origin.x, 100, accuracy: 0.000_001)
        XCTAssertEqual(finalFrame.size.width, 50, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }

    func testAnimatableFrameAttributeAnimationsDisabledSkipsAnimatedActivation() {
        let listener = CountingAnimationListener()
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            animationsDisabled: true
        )
        _ = harness.currentFrame()

        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = listener
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xFD1
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: transaction
        )

        let frame = harness.currentFrame()
        XCTAssertEqual(frame.origin.x, 100, accuracy: 0.000_001)
        XCTAssertEqual(frame.origin.y, 40, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.width, 50, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.height, 60, accuracy: 0.000_001)
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])

        harness.setTime(0.5)
        let laterFrame = harness.currentFrame()
        XCTAssertEqual(laterFrame.origin.x, 100, accuracy: 0.000_001)
        XCTAssertEqual(laterFrame.size.width, 50, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(listener.removedCount, 0)
    }

    func testAnimatableFrameAttributeInitialTransactionDisablesAnimationsDoesNotDisableFrameRule() {
        let listener = CountingAnimationListener()
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.disablesAnimations = true
        transaction.animationListener = listener
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xFD3
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            initialTransaction: transaction
        )
        _ = harness.currentFrame()

        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: transaction
        )

        let frame = harness.currentFrame()
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.width, 10, accuracy: 0.000_001)
        XCTAssertEqual(listener.addedCount, 1)
        XCTAssertEqual(listener.removedCount, 0)
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xFD3])
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
        var initialTransaction = Transaction(animation: .linear(duration: 1))
        initialTransaction.animationFrameInterval = 1.0 / 30.0
        initialTransaction.animationReason = 0xF39
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: initialTransaction
        )
        _ = harness.currentFrame()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        let runningFrame = harness.currentFrame()
        XCTAssertGreaterThan(runningFrame.origin.x, 0)
        XCTAssertLessThan(runningFrame.origin.x, 100)

        harness.resetNextUpdate()
        var sameTargetTransaction = Transaction(animation: .linear(duration: 1))
        sameTargetTransaction.animationListener = listener
        sameTargetTransaction.animationFrameInterval = 1.0 / 120.0
        sameTargetTransaction.animationReason = 0xF3A
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: sameTargetTransaction
        )
        _ = harness.currentFrame()
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xF39])

        harness.setTime(2.0)
        let finalFrame = harness.currentFrame()
        XCTAssertEqual(finalFrame.origin.x, 100, accuracy: 0.000_001)
        XCTAssertEqual(finalFrame.size.width, 50, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
    }

    func testAnimatableFrameAttributeNoChangeCompletionTransactionDoesNotAttachRecords() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        _ = harness.currentFrame()

        var initialTransaction = Transaction(animation: .linear(duration: 1))
        initialTransaction.animationFrameInterval = 1.0 / 30.0
        initialTransaction.animationReason = 0xF41
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: initialTransaction
        )
        _ = harness.currentFrame()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        let runningFrame = harness.currentFrame()
        XCTAssertGreaterThan(runningFrame.origin.x, 0)
        XCTAssertLessThan(runningFrame.origin.x, 100)

        harness.resetNextUpdate()
        var sameTargetTransaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "same",
            recorder: recorder
        )
        sameTargetTransaction.animationFrameInterval = 1.0 / 120.0
        sameTargetTransaction.animationReason = 0xF42
        harness.setFrame(
            position: CGPoint(x: 100, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: sameTargetTransaction
        )
        _ = harness.currentFrame()
        harness.flushCompletionActions()

        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xF41])

        harness.setTime(2.0)
        let finalFrame = harness.currentFrame()
        XCTAssertEqual(finalFrame.origin.x, 100, accuracy: 0.000_001)
        XCTAssertEqual(finalFrame.size.width, 50, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
    }

    func testAnimatableFrameAttributeVFDNoChangeAnimatedTransactionSkipsListenerRegistration() {
        let listener = CountingAnimationListener()
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            supportsVFD: true
        )
        _ = harness.currentFrame()

        var initialTransaction = Transaction(animation: .linear(duration: 1))
        initialTransaction.animationFrameInterval = 1.0 / 30.0
        initialTransaction.animationReason = 0xF51
        harness.setFrame(
            position: CGPoint(x: 1_000, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: initialTransaction
        )
        _ = harness.currentFrame()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        let runningFrame = harness.currentFrame()
        XCTAssertGreaterThan(runningFrame.origin.x, 0)
        XCTAssertLessThan(runningFrame.origin.x, 1_000)

        harness.resetNextUpdate()
        var sameTargetTransaction = Transaction(animation: .linear(duration: 1))
        sameTargetTransaction.animationListener = listener
        sameTargetTransaction.animationFrameInterval = 1.0 / 120.0
        sameTargetTransaction.animationReason = 0xF52
        harness.setFrame(
            position: CGPoint(x: 1_000, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: sameTargetTransaction
        )
        _ = harness.currentFrame()

        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
        XCTAssertTrue(harness.nextUpdateReasons().contains(0xF51))
        XCTAssertFalse(harness.nextUpdateReasons().contains(0xF52))

        harness.setTime(2.0)
        let finalFrame = harness.currentFrame()
        XCTAssertEqual(finalFrame.origin.x, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(finalFrame.size.width, 50, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
    }

    func testAnimatableFrameAttributeVFDNoChangeCompletionTransactionDoesNotAttachRecords() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            supportsVFD: true
        )
        _ = harness.currentFrame()

        var initialTransaction = Transaction(animation: .linear(duration: 1))
        initialTransaction.animationFrameInterval = 1.0 / 30.0
        initialTransaction.animationReason = 0xF53
        harness.setFrame(
            position: CGPoint(x: 1_000, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: initialTransaction
        )
        _ = harness.currentFrame()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        let runningFrame = harness.currentFrame()
        XCTAssertGreaterThan(runningFrame.origin.x, 0)
        XCTAssertLessThan(runningFrame.origin.x, 1_000)

        harness.resetNextUpdate()
        var sameTargetTransaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "same",
            recorder: recorder
        )
        sameTargetTransaction.animationFrameInterval = 1.0 / 120.0
        sameTargetTransaction.animationReason = 0xF54
        harness.setFrame(
            position: CGPoint(x: 1_000, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: sameTargetTransaction
        )
        _ = harness.currentFrame()
        harness.flushCompletionActions()

        XCTAssertEqual(recorder.events, [])
        XCTAssertTrue(harness.nextUpdateReasons().contains(0xF53))
        XCTAssertFalse(harness.nextUpdateReasons().contains(0xF54))

        harness.setTime(2.0)
        let finalFrame = harness.currentFrame()
        XCTAssertEqual(finalFrame.origin.x, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(finalFrame.size.width, 50, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
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

    func testAnimatableFrameAttributeVFDSplitRawListenersDrainLogicalBeforeRemoved() {
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xF75

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
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0)

        harness.resetNextUpdate()
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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
    }

    func testAnimatableFrameAttributeVFDPhaseResetRemovesRawListenersInCriteriaOrder() {
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xF76

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
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0)

        harness.resetNextUpdate()
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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
    }

    func testAnimatableFrameAttributePhaseResetAfterLogicalDrainFinishesOnlyRemainingRemoved() {
        assertFrameAttributePhaseResetAfterLogicalDrainFinishesOnlyRemainingRemoved(
            supportsVFD: false,
            animationReason: 0xF71
        )
    }

    func testAnimatableFrameAttributeVFDPhaseResetAfterLogicalDrainFinishesOnlyRemainingRemoved() {
        assertFrameAttributePhaseResetAfterLogicalDrainFinishesOnlyRemainingRemoved(
            supportsVFD: true,
            animationReason: 0xF72
        )
    }

    private func assertFrameAttributePhaseResetAfterLogicalDrainFinishesOnlyRemainingRemoved(
        supportsVFD: Bool,
        animationReason: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
            supportsVFD: supportsVFD
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = animationReason

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001, file: file, line: line)
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
            ],
            file: file,
            line: line
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.7)
        _ = harness.currentFrame()
        harness.setTime(0.8)
        _ = harness.currentFrame()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["logical removed"], file: file, line: line)
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0, file: file, line: line)

        harness.resetNextUpdate()
        harness.bumpPhaseResetSeed()
        _ = harness.currentFrame()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ],
            file: file,
            line: line
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [], file: file, line: line)

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ],
            file: file,
            line: line
        )
    }

    func testAnimatableFrameAttributePhaseResetDrainsRawActiveListenersBeforeForkListeners() {
        assertFrameAttributeDrainsRawActiveListenersBeforeForkListeners(
            supportsVFD: false,
            invalidatesSubgraph: false,
            oldReason: 0xFA1,
            replacementReason: 0xFA2
        )
    }

    func testAnimatableFrameAttributeVFDPhaseResetDrainsRawActiveListenersBeforeForkListeners() {
        assertFrameAttributeDrainsRawActiveListenersBeforeForkListeners(
            supportsVFD: true,
            invalidatesSubgraph: false,
            oldReason: 0xFA3,
            replacementReason: 0xFA4
        )
    }

    func testAnimatableFrameAttributeNodeRemovalDrainsRawActiveListenersBeforeForkListeners() {
        assertFrameAttributeDrainsRawActiveListenersBeforeForkListeners(
            supportsVFD: false,
            invalidatesSubgraph: true,
            oldReason: 0xFA5,
            replacementReason: 0xFA6
        )
    }

    func testAnimatableFrameAttributeVFDNodeRemovalDrainsRawActiveListenersBeforeForkListeners() {
        assertFrameAttributeDrainsRawActiveListenersBeforeForkListeners(
            supportsVFD: true,
            invalidatesSubgraph: true,
            oldReason: 0xFA7,
            replacementReason: 0xFA8
        )
    }

    func testAnimatableFrameAttributeTripleRetargetPhaseResetDrainsRawActiveListenersBeforeForkListeners() {
        assertFrameAttributeDrainsRawActiveListenersBeforeForkListeners(
            supportsVFD: false,
            invalidatesSubgraph: false,
            oldReason: 0xFB1,
            middleReason: 0xFB2,
            replacementReason: 0xFB3
        )
    }

    func testAnimatableFrameAttributeVFDTripleRetargetPhaseResetDrainsRawActiveListenersBeforeForkListeners() {
        assertFrameAttributeDrainsRawActiveListenersBeforeForkListeners(
            supportsVFD: true,
            invalidatesSubgraph: false,
            oldReason: 0xFB4,
            middleReason: 0xFB5,
            replacementReason: 0xFB6
        )
    }

    func testAnimatableFrameAttributeTripleRetargetNodeRemovalDrainsRawActiveListenersBeforeForkListeners() {
        assertFrameAttributeDrainsRawActiveListenersBeforeForkListeners(
            supportsVFD: false,
            invalidatesSubgraph: true,
            oldReason: 0xFB7,
            middleReason: 0xFB8,
            replacementReason: 0xFB9
        )
    }

    func testAnimatableFrameAttributeVFDTripleRetargetNodeRemovalDrainsRawActiveListenersBeforeForkListeners() {
        assertFrameAttributeDrainsRawActiveListenersBeforeForkListeners(
            supportsVFD: true,
            invalidatesSubgraph: true,
            oldReason: 0xFBA,
            middleReason: 0xFBB,
            replacementReason: 0xFBC
        )
    }

    private func assertFrameAttributeDrainsRawActiveListenersBeforeForkListeners(
        supportsVFD: Bool,
        invalidatesSubgraph: Bool,
        oldReason: UInt32,
        middleReason: UInt32? = nil,
        replacementReason: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            supportsVFD: supportsVFD
        )

        var oldTransaction = Transaction(animation: .linear(duration: 10))
        oldTransaction.animationListener = RecordingAnimationListener(
            label: "old removed",
            recorder: recorder
        )
        oldTransaction.animationLogicalListener = RecordingAnimationListener(
            label: "old logical",
            recorder: recorder
        )
        oldTransaction.animationFrameInterval = 1.0 / 30.0
        oldTransaction.animationReason = oldReason

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setFrame(
            position: CGPoint(x: 1_000, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: oldTransaction
        )
        _ = harness.currentFrame()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed added",
                "old logical added",
            ],
            file: file,
            line: line
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentFrame()

        if let middleReason {
            var middleTransaction = Transaction(animation: .linear(duration: 10))
            middleTransaction.animationListener = RecordingAnimationListener(
                label: "middle removed",
                recorder: recorder
            )
            middleTransaction.animationLogicalListener = RecordingAnimationListener(
                label: "middle logical",
                recorder: recorder
            )
            middleTransaction.animationFrameInterval = 1.0 / 90.0
            middleTransaction.animationReason = middleReason
            harness.setFrame(
                position: CGPoint(x: 1_500, y: 60),
                size: ViewSize(width: 65, height: 75),
                transaction: middleTransaction
            )
            _ = harness.currentFrame()
            XCTAssertEqual(
                recorder.events,
                [
                    "middle removed added",
                    "middle logical added",
                ],
                file: file,
                line: line
            )

            recorder.removeAll()
            harness.setTime(0.9)
            _ = harness.currentFrame()
        }

        var replacementTransaction = Transaction(animation: .linear(duration: 10))
        replacementTransaction.animationListener = RecordingAnimationListener(
            label: "replacement removed",
            recorder: recorder
        )
        replacementTransaction.animationLogicalListener = RecordingAnimationListener(
            label: "replacement logical",
            recorder: recorder
        )
        replacementTransaction.animationFrameInterval = 1.0 / 120.0
        replacementTransaction.animationReason = replacementReason
        harness.setFrame(
            position: CGPoint(x: 2_000, y: 80),
            size: ViewSize(width: 80, height: 90),
            transaction: replacementTransaction
        )
        _ = harness.currentFrame()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed added",
                "replacement logical added",
            ],
            file: file,
            line: line
        )

        recorder.removeAll()
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0, file: file, line: line)
        harness.resetNextUpdate()
        if invalidatesSubgraph {
            harness.invalidateAnimatableSubgraph()
        } else {
            harness.bumpPhaseResetSeed()
            _ = harness.currentFrame()
        }
        harness.flushCompletionActions()
        let expectedRemovalEvents: [String]
        if middleReason == nil {
            expectedRemovalEvents = [
                "old removed removed",
                "replacement removed removed",
                "replacement logical removed",
                "old logical removed",
            ]
        } else {
            expectedRemovalEvents = [
                "old removed removed",
                "middle removed removed",
                "replacement removed removed",
                "replacement logical removed",
                "old logical removed",
                "middle logical removed",
            ]
        }
        XCTAssertEqual(
            recorder.events,
            expectedRemovalEvents,
            file: file,
            line: line
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [], file: file, line: line)
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xF85

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
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0)

        harness.resetNextUpdate()
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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])

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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xF86

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
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0)

        harness.resetNextUpdate()
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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
    }

    func testAnimatableFrameAttributeNoAnimationRetargetAfterLogicalDrainFinishesOnlyRemainingRemoved() {
        assertFrameAttributeNoAnimationRetargetAfterLogicalDrainFinishesOnlyRemainingRemoved(
            supportsVFD: false,
            animationReason: 0xF81
        )
    }

    func testAnimatableFrameAttributeVFDNoAnimationRetargetAfterLogicalDrainFinishesOnlyRemainingRemoved() {
        assertFrameAttributeNoAnimationRetargetAfterLogicalDrainFinishesOnlyRemainingRemoved(
            supportsVFD: true,
            animationReason: 0xF82
        )
    }

    private func assertFrameAttributeNoAnimationRetargetAfterLogicalDrainFinishesOnlyRemainingRemoved(
        supportsVFD: Bool,
        animationReason: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
            supportsVFD: supportsVFD
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = animationReason

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001, file: file, line: line)
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
            ],
            file: file,
            line: line
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.7)
        _ = harness.currentFrame()
        harness.setTime(0.8)
        _ = harness.currentFrame()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["logical removed"], file: file, line: line)
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0, file: file, line: line)

        harness.resetNextUpdate()
        harness.setFrame(
            position: CGPoint(x: 25, y: 15),
            size: ViewSize(width: 30, height: 35),
            transaction: Transaction(animation: nil)
        )
        let frame = harness.currentFrame()
        XCTAssertEqual(frame.origin.x, 25, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(frame.origin.y, 15, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(frame.size.width, 30, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(frame.size.height, 35, accuracy: 0.000_001, file: file, line: line)
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ],
            file: file,
            line: line
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [], file: file, line: line)

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ],
            file: file,
            line: line
        )
    }

    func testAnimatableFrameAttributeNodeRemovalAfterLogicalDrainFinishesOnlyRemainingRemoved() {
        assertFrameAttributeNodeRemovalAfterLogicalDrainFinishesOnlyRemainingRemoved(
            supportsVFD: false,
            animationReason: 0xF91
        )
    }

    func testAnimatableFrameAttributeVFDNodeRemovalAfterLogicalDrainFinishesOnlyRemainingRemoved() {
        assertFrameAttributeNodeRemovalAfterLogicalDrainFinishesOnlyRemainingRemoved(
            supportsVFD: true,
            animationReason: 0xF92
        )
    }

    private func assertFrameAttributeNodeRemovalAfterLogicalDrainFinishesOnlyRemainingRemoved(
        supportsVFD: Bool,
        animationReason: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
            supportsVFD: supportsVFD
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = animationReason

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001, file: file, line: line)
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
            ],
            file: file,
            line: line
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.7)
        _ = harness.currentFrame()
        harness.setTime(0.8)
        _ = harness.currentFrame()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["logical removed"], file: file, line: line)
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0, file: file, line: line)

        harness.resetNextUpdate()
        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ],
            file: file,
            line: line
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [], file: file, line: line)

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ],
            file: file,
            line: line
        )
    }

    func testAnimatableFrameAttributeNodeRemovalBeforeLogicalDrainsRemovedBeforeLogicalOnce() {
        assertFrameAttributeNodeRemovalBeforeLogicalDrainsRemovedBeforeLogicalOnce(
            supportsVFD: false,
            animationReason: 0xF93
        )
    }

    func testAnimatableFrameAttributeVFDNodeRemovalBeforeLogicalDrainsRemovedBeforeLogicalOnce() {
        assertFrameAttributeNodeRemovalBeforeLogicalDrainsRemovedBeforeLogicalOnce(
            supportsVFD: true,
            animationReason: 0xF94
        )
    }

    private func assertFrameAttributeNodeRemovalBeforeLogicalDrainsRemovedBeforeLogicalOnce(
        supportsVFD: Bool,
        animationReason: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
            supportsVFD: supportsVFD
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = animationReason

        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001, file: file, line: line)
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
            ],
            file: file,
            line: line
        )

        recorder.removeAll()
        harness.resetNextUpdate()
        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ],
            file: file,
            line: line
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [], file: file, line: line)

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ],
            file: file,
            line: line
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

    func testAnimatableFrameAttributeVFDTerminalSampleDoesNotScheduleNextUpdate() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            supportsVFD: true
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)

        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xF62
        harness.setFrame(
            position: CGPoint(x: 1_000, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: transaction
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        _ = harness.currentFrame()
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0)

        harness.resetNextUpdate()
        harness.setTime(4.0)
        let finalFrame = harness.currentFrame()
        XCTAssertEqual(finalFrame.origin.x, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(finalFrame.size.width, 50, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }

    func testAnimatableFrameAttributeVFDAnimationsDisabledSkipsAnimatedActivation() {
        let listener = CountingAnimationListener()
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            supportsVFD: true,
            animationsDisabled: true
        )
        _ = harness.currentFrame()

        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = listener
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xFD2
        harness.setFrame(
            position: CGPoint(x: 1_000, y: 40),
            size: ViewSize(width: 50, height: 60),
            transaction: transaction
        )

        let frame = harness.currentFrame()
        XCTAssertEqual(frame.origin.x, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(frame.origin.y, 40, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.width, 50, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.height, 60, accuracy: 0.000_001)
        XCTAssertEqual(listener.addedCount, 0)
        XCTAssertEqual(listener.removedCount, 0)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])

        harness.setTime(0.5)
        let laterFrame = harness.currentFrame()
        XCTAssertEqual(laterFrame.origin.x, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(laterFrame.size.width, 50, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(listener.removedCount, 0)
    }

    func testAnimatableFrameAttributeVFDInitialTransactionDisablesAnimationsDoesNotDisableFrameRule() {
        let listener = CountingAnimationListener()
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.disablesAnimations = true
        transaction.animationListener = listener
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xFD4
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            initialTransaction: transaction,
            supportsVFD: true
        )
        _ = harness.currentFrame()

        harness.setFrame(
            position: CGPoint(x: 10, y: 4),
            size: ViewSize(width: 12, height: 22),
            transaction: transaction
        )

        let frame = harness.currentFrame()
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.width, 10, accuracy: 0.000_001)
        XCTAssertEqual(listener.addedCount, 1)
        XCTAssertEqual(listener.removedCount, 0)
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xFD4])
    }

    func testAnimatableFrameAttributeVFDSchedulesHighFrameRateForFastFrameMotion() {
        let highFrameRateReason: UInt32 = 2_555_904
        let animationReason: UInt32 = 0xF71
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20),
            supportsVFD: true
        )
        _ = harness.currentFrame()
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = animationReason
        harness.setFrame(
            position: CGPoint(x: 1_000, y: 0),
            size: ViewSize(width: 10, height: 20),
            transaction: transaction
        )
        _ = harness.currentFrame()
        harness.setTime(0.5)
        _ = harness.currentFrame()
        harness.setTime(0.6)
        _ = harness.currentFrame()
        harness.resetNextUpdate()
        harness.setTime(0.7)
        _ = harness.currentFrame()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 120.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [animationReason, highFrameRateReason])
    }

    func testSharedTransactionCompletionWaitsForAllAnimatableAttributes() {
        let recorder = AnimationCompletionRecorder()
        let harness = DualAnimatableAttributeHarness(
            firstInitialValue: _OpacityEffect(opacity: 0),
            secondInitialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "shared",
            recorder: recorder
        )
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA48
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA48])
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.resetNextUpdate()
        harness.setFirstTime(2.7)
        XCTAssertEqual(harness.currentFirstValue().opacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA48])
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "shared removed",
                "shared logical",
            ]
        )
        harness.resetNextUpdate()
        harness.setSecondTime(2.7)
        XCTAssertEqual(harness.currentSecondValue().opacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
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
        var transaction = completionTransaction(
            animation: Animation.linear(duration: 1).logicallyComplete(after: 0.05),
            label: "shared",
            recorder: recorder
        )
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA4A
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA4A])
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.resetNextUpdate()

        harness.setSecondTime(0.5)
        _ = harness.currentSecondValue()
        harness.setSecondTime(0.6)
        _ = harness.currentSecondValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA4A])
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["shared logical"])
        harness.resetNextUpdate()

        harness.setFirstTime(5.0)
        _ = harness.currentFirstValue()
        harness.setFirstTime(5.1)
        _ = harness.currentFirstValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["shared logical"])
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
        harness.resetNextUpdate()

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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }

    func testRegisteredTokenCompletionEntriesPreserveCriteriaGroupOrder() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA4B
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

        harness.resetNextUpdate()
        harness.setTime(0.5)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA4B])
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.resetNextUpdate()

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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA4B])
        harness.resetNextUpdate()

        harness.setTime(4.0)
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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }

    func testRegisteredTokenSplitCriteriaEntriesPreserveBoundaryOrder() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(
            animation: Animation.linear(duration: 1).logicallyComplete(after: 0.05)
        )
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA4C
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

        harness.resetNextUpdate()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA4C])
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical1",
                "logical2",
            ]
        )
        harness.resetNextUpdate()

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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }

    func testSharedTransactionListenerRegistersForAllAnimatableAttributes() {
        let listener = CountingAnimationListener()
        let harness = DualAnimatableAttributeHarness(
            firstInitialValue: _OpacityEffect(opacity: 0),
            secondInitialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = listener
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA49
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA49])
        harness.resetNextUpdate()
        harness.setFirstTime(2.7)
        XCTAssertEqual(harness.currentFirstValue().opacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(listener.removedCount, 1)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
        harness.setSecondTime(0.5)
        _ = harness.currentSecondValue()
        harness.setSecondTime(1.6)
        _ = harness.currentSecondValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA49])
        harness.resetNextUpdate()
        harness.setSecondTime(2.7)
        XCTAssertEqual(harness.currentSecondValue().opacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(listener.removedCount, 2)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }
    func testPhaseResetDrainsActiveCompletionRecords() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        var transaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "old",
            recorder: recorder
        )
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA43
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA43])
        harness.resetNextUpdate()
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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }
    func testPhaseResetRemovesRawActiveListeners() {
        let listener = CountingAnimationListener()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = listener
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA44
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA44])
        harness.resetNextUpdate()
        harness.bumpPhaseResetSeed()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(listener.removedCount, 1)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA41
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA41])
        harness.resetNextUpdate()
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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }
    func testPhaseResetDrainsRawActiveListenersBeforeForkListeners() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )

        var oldTransaction = Transaction(animation: .linear(duration: 10))
        oldTransaction.animationListener = RecordingAnimationListener(
            label: "old removed",
            recorder: recorder
        )
        oldTransaction.animationLogicalListener = RecordingAnimationListener(
            label: "old logical",
            recorder: recorder
        )
        oldTransaction.animationFrameInterval = 1.0 / 30.0
        oldTransaction.animationReason = 0xA4F

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

        var replacementTransaction = Transaction(animation: .linear(duration: 10))
        replacementTransaction.animationListener = RecordingAnimationListener(
            label: "replacement removed",
            recorder: recorder
        )
        replacementTransaction.animationLogicalListener = RecordingAnimationListener(
            label: "replacement logical",
            recorder: recorder
        )
        replacementTransaction.animationFrameInterval = 1.0 / 30.0
        replacementTransaction.animationReason = 0xA50
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: replacementTransaction
        )
        _ = harness.currentValue()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed added",
                "replacement logical added",
            ]
        )

        recorder.removeAll()
        harness.resetNextUpdate()
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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }
    func testNodeRemovalDrainsActiveCompletionRecords() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        var transaction = completionTransaction(
            animation: .linear(duration: 1),
            label: "old",
            recorder: recorder
        )
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA45
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA45])
        harness.resetNextUpdate()
        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "old logical",
            ]
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }
    func testNodeRemovalRemovesRawActiveListeners() {
        let listener = CountingAnimationListener()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.animationListener = listener
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA46
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA46])
        harness.resetNextUpdate()
        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(listener.removedCount, 1)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA42
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA42])
        harness.resetNextUpdate()
        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ]
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }
    func testNodeRemovalDrainsRawActiveListenersBeforeForkListeners() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )

        var oldTransaction = Transaction(animation: .linear(duration: 10))
        oldTransaction.animationListener = RecordingAnimationListener(
            label: "old removed",
            recorder: recorder
        )
        oldTransaction.animationLogicalListener = RecordingAnimationListener(
            label: "old logical",
            recorder: recorder
        )
        oldTransaction.animationFrameInterval = 1.0 / 30.0
        oldTransaction.animationReason = 0xA4D

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

        var replacementTransaction = Transaction(animation: .linear(duration: 10))
        replacementTransaction.animationListener = RecordingAnimationListener(
            label: "replacement removed",
            recorder: recorder
        )
        replacementTransaction.animationLogicalListener = RecordingAnimationListener(
            label: "replacement logical",
            recorder: recorder
        )
        replacementTransaction.animationFrameInterval = 1.0 / 30.0
        replacementTransaction.animationReason = 0xA4E
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: replacementTransaction
        )
        _ = harness.currentValue()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement removed added",
                "replacement logical added",
            ]
        )

        recorder.removeAll()
        harness.resetNextUpdate()
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
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA47
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA47])
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.resetNextUpdate()
        harness.setTime(1.6)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
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

        harness.setTime(3.0)
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

    func testAnimatableAttributePhaseResetAfterLogicalDrainFinishesOnlyRemainingRawRemoved() {
        assertAnimatableAttributeRawListenerTeardownAfterLogicalDrain(
            invalidatesSubgraph: false,
            animationReason: 0xA61
        )
    }

    func testAnimatableAttributeNodeRemovalAfterLogicalDrainFinishesOnlyRemainingRawRemoved() {
        assertAnimatableAttributeRawListenerTeardownAfterLogicalDrain(
            invalidatesSubgraph: true,
            animationReason: 0xA62
        )
    }

    func testAnimatableAttributePhaseResetBeforeLogicalDrainRemovesRawListenersInCriteriaOrder() {
        assertAnimatableAttributeRawListenerTeardownBeforeLogicalDrain(
            invalidatesSubgraph: false,
            animationReason: 0xA63
        )
    }

    func testAnimatableAttributeNodeRemovalBeforeLogicalDrainRemovesRawListenersInCriteriaOrder() {
        assertAnimatableAttributeRawListenerTeardownBeforeLogicalDrain(
            invalidatesSubgraph: true,
            animationReason: 0xA64
        )
    }

    func testAnimatableAttributeNoAnimationRetargetAfterLogicalDrainKeepsRemainingRawRemoved() {
        assertAnimatableAttributeRawListenerNoAnimationRetargetAfterLogicalDrain(
            animationReason: 0xA65
        )
    }

    func testAnimatableAttributeNoAnimationRetargetBeforeLogicalDrainKeepsRawListenerDeadlines() {
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
                    logicalAt: 0.8,
                    nilAt: 1,
                    recorder: sampleRecorder
                )
            )
        )
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = 0xA66

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
        harness.setTime(0.2)
        let beforeRetarget = harness.currentValue().opacity
        harness.flushCompletionActions()
        XCTAssertGreaterThanOrEqual(beforeRetarget, 0)
        XCTAssertLessThan(beforeRetarget, 1)
        XCTAssertEqual(recorder.events, [])
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA66])

        harness.resetNextUpdate()
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: Transaction(animation: nil)
        )
        harness.finalizeTransactionBody()
        let afterRetarget = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(afterRetarget, beforeRetarget)
        XCTAssertLessThan(afterRetarget, 2)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.resetNextUpdate()
        harness.setTime(1.1)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA66])
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.resetNextUpdate()
        harness.setTime(1.3)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA66])
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.resetNextUpdate()
        harness.setTime(1.9)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA66])
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["logical removed"])

        harness.resetNextUpdate()
        harness.setTime(5.0)
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
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

    private func assertAnimatableAttributeRawListenerTeardownAfterLogicalDrain(
        invalidatesSubgraph: Bool,
        animationReason: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = animationReason

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ],
            file: file,
            line: line
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["logical removed"], file: file, line: line)
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [animationReason], file: file, line: line)

        recorder.removeAll()
        harness.resetNextUpdate()
        if invalidatesSubgraph {
            harness.invalidateAnimatableSubgraph()
        } else {
            harness.bumpPhaseResetSeed()
            _ = harness.currentValue()
        }
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["removed removed"], file: file, line: line)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [], file: file, line: line)

        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["removed removed"], file: file, line: line)
    }

    private func assertAnimatableAttributeRawListenerTeardownBeforeLogicalDrain(
        invalidatesSubgraph: Bool,
        animationReason: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
                    logicalAt: 0.8,
                    nilAt: 1,
                    recorder: sampleRecorder
                )
            )
        )
        transaction.animationListener = removedListener
        transaction.animationLogicalListener = logicalListener
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = animationReason

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ],
            file: file,
            line: line
        )

        recorder.removeAll()
        harness.setTime(0.2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [animationReason], file: file, line: line)

        harness.resetNextUpdate()
        if invalidatesSubgraph {
            harness.invalidateAnimatableSubgraph()
        } else {
            harness.bumpPhaseResetSeed()
            XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001, file: file, line: line)
        }
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ],
            file: file,
            line: line
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [], file: file, line: line)

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "removed removed",
                "logical removed",
            ],
            file: file,
            line: line
        )
    }

    private func assertAnimatableAttributeRawListenerNoAnimationRetargetAfterLogicalDrain(
        animationReason: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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
        transaction.animationFrameInterval = 1.0 / 30.0
        transaction.animationReason = animationReason

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(
            recorder.events,
            [
                "removed added",
                "logical added",
            ],
            file: file,
            line: line
        )

        recorder.removeAll()
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.8)
        let beforeRetarget = harness.currentValue().opacity
        harness.flushCompletionActions()
        XCTAssertGreaterThanOrEqual(beforeRetarget, 0, file: file, line: line)
        XCTAssertLessThan(beforeRetarget, 1, file: file, line: line)
        XCTAssertEqual(recorder.events, ["logical removed"], file: file, line: line)
        XCTAssertGreaterThan(harness.nextUpdateInterval(), 0, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [animationReason], file: file, line: line)

        harness.resetNextUpdate()
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: Transaction(animation: nil)
        )
        harness.finalizeTransactionBody()
        let afterRetarget = harness.currentValue().opacity
        XCTAssertGreaterThanOrEqual(afterRetarget, beforeRetarget, file: file, line: line)
        XCTAssertLessThan(afterRetarget, 2, file: file, line: line)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["logical removed"], file: file, line: line)

        harness.resetNextUpdate()
        harness.setTime(0.9)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [animationReason], file: file, line: line)

        harness.resetNextUpdate()
        harness.setTime(5.0)
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(harness.nextUpdateReasons(), [], file: file, line: line)
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ],
            file: file,
            line: line
        )

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "logical removed",
                "removed removed",
            ],
            file: file,
            line: line
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

    func testFiniteBuiltInRetargetPrunesCompletedNonPrefixFork() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        func logicalTransaction(
            label: String,
            duration: TimeInterval
        ) -> Transaction {
            var transaction = Transaction(animation: .linear(duration: duration))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old", duration: 2.40)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle", duration: 0.70)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active", duration: 8.00)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.7)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["middle logical"])

        harness.setTime(3.1)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ]
        )

        harness.setTime(3.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ]
        )
    }

    func testFixedFiniteBuiltInRetargetPreservesPrefixForkLogicalOrder() {
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .linear,
            middleRetargetTime: 0.10,
            activeRetargetTime: 0.24,
            finalSampleTime: 0.90
        )
    }

    func testExplicitDefaultDurationFiniteBuiltInRetargetPreservesPrefixForkLogicalOrder() {
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .linear(duration: 0.35),
            middleRetargetTime: 0.10,
            activeRetargetTime: 0.24,
            finalSampleTime: 0.90
        )
    }

    func testDefaultBuiltInRetargetPreservesPrefixForkLogicalOrder() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        func logicalTransaction(label: String) -> Transaction {
            var transaction = Transaction(animation: .default)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old")
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.20)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle")
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.40)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active")
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.62)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["old logical"])

        harness.setTime(0.84)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            Array(recorder.events.prefix(2)),
            [
                "old logical",
                "middle logical",
            ]
        )

        harness.setTime(1.08)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old logical",
                "middle logical",
                "active logical",
            ]
        )
    }

    func testFluidSpringDefaultAliasBuiltInRetargetPreservesPrefixForkLogicalOrder() {
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .spring,
            middleRetargetTime: 0.20,
            activeRetargetTime: 0.40,
            finalSampleTime: 1.20
        )
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .spring(),
            middleRetargetTime: 0.20,
            activeRetargetTime: 0.40,
            finalSampleTime: 1.20
        )
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .interactiveSpring,
            middleRetargetTime: 0.06,
            activeRetargetTime: 0.12,
            finalSampleTime: 0.70
        )
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .interactiveSpring(),
            middleRetargetTime: 0.06,
            activeRetargetTime: 0.12,
            finalSampleTime: 0.70
        )
    }

    private func assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
        animation: Animation,
        middleRetargetTime: TimeInterval,
        activeRetargetTime: TimeInterval,
        finalSampleTime: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        func logicalTransaction(label: String) -> Transaction {
            var transaction = Transaction(animation: animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old")
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(middleRetargetTime)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle")
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(activeRetargetTime)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active")
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(finalSampleTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old logical",
                "middle logical",
                "active logical",
            ],
            file: file,
            line: line
        )
    }

    func testUnitCurveBuiltInRetargetPrunesCompletedNonPrefixFork() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        func logicalTransaction(
            label: String,
            duration: TimeInterval
        ) -> Transaction {
            var transaction = Transaction(
                animation: .timingCurve(.circularEaseInOut, duration: duration)
            )
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old", duration: 2.40)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle", duration: 0.70)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active", duration: 8.00)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.7)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["middle logical"])

        harness.setTime(3.1)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ]
        )

        harness.setTime(3.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ]
        )
    }

    func testFixedBezierBuiltInRetargetPreservesPrefixForkLogicalOrder() {
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .easeInOut,
            middleRetargetTime: 0.10,
            activeRetargetTime: 0.24,
            finalSampleTime: 0.90
        )
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .easeIn,
            middleRetargetTime: 0.10,
            activeRetargetTime: 0.24,
            finalSampleTime: 0.90
        )
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .easeOut,
            middleRetargetTime: 0.10,
            activeRetargetTime: 0.24,
            finalSampleTime: 0.90
        )
    }

    func testExplicitDefaultDurationBezierBuiltInRetargetPreservesPrefixForkLogicalOrder() {
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .easeInOut(duration: 0.35),
            middleRetargetTime: 0.10,
            activeRetargetTime: 0.24,
            finalSampleTime: 0.90
        )
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .easeIn(duration: 0.35),
            middleRetargetTime: 0.10,
            activeRetargetTime: 0.24,
            finalSampleTime: 0.90
        )
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .easeOut(duration: 0.35),
            middleRetargetTime: 0.10,
            activeRetargetTime: 0.24,
            finalSampleTime: 0.90
        )
        assertFixedDurationBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .timingCurve(0.25, 0.10, 0.25, 1.0, duration: 0.35),
            middleRetargetTime: 0.10,
            activeRetargetTime: 0.24,
            finalSampleTime: 0.90
        )
    }

    func testBezierBuiltInRetargetPrunesCompletedNonPrefixFork() {
        assertBezierBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { .easeInOut(duration: $0) }
        )
        assertBezierBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { .easeIn(duration: $0) }
        )
        assertBezierBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { .easeOut(duration: $0) }
        )
        assertBezierBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: {
                .timingCurve(0.25, 0.10, 0.25, 1.0, duration: $0)
            }
        )
    }

    private func assertBezierBuiltInRetargetPrunesCompletedNonPrefixFork(
        animation: (TimeInterval) -> Animation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        func logicalTransaction(
            label: String,
            duration: TimeInterval
        ) -> Transaction {
            var transaction = Transaction(animation: animation(duration))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old", duration: 2.40)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle", duration: 0.70)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active", duration: 8.00)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(1.7)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["middle logical"], file: file, line: line)

        harness.setTime(3.1)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ],
            file: file,
            line: line
        )

        harness.setTime(3.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ],
            file: file,
            line: line
        )
    }

    func testResidualBuiltInRetargetPrunesCompletedNonPrefixFork() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        func logicalTransaction(
            label: String,
            response: TimeInterval
        ) -> Transaction {
            var transaction = Transaction(
                animation: .spring(
                    response: response,
                    dampingFraction: 0.70,
                    blendDuration: 0.0
                )
            )
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old", response: 2.40)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle", response: 0.70)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active", response: 8.00)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.20)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.35)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["middle logical"])

        harness.setTime(2.55)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ]
        )

        harness.setTime(3.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ]
        )
    }

    func testFluidSpringAliasBuiltInRetargetPrunesCompletedNonPrefixFork() {
        assertFluidSpringAliasBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { .spring(duration: $0, bounce: 0.20, blendDuration: 0.0) }
        )
        assertFluidSpringAliasBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { .smooth(duration: $0, extraBounce: 0.05) }
        )
        assertFluidSpringAliasBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { .snappy(duration: $0, extraBounce: 0.05) }
        )
        assertFluidSpringAliasBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { .bouncy(duration: $0, extraBounce: 0.05) }
        )
        assertFluidSpringAliasBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { .interactiveSpring(duration: $0, extraBounce: 0.0, blendDuration: 0.25) }
        )
    }

    private func assertFluidSpringAliasBuiltInRetargetPrunesCompletedNonPrefixFork(
        animation: (TimeInterval) -> Animation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        func logicalTransaction(
            label: String,
            duration: TimeInterval
        ) -> Transaction {
            var transaction = Transaction(animation: animation(duration))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old", duration: 2.40)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle", duration: 0.70)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active", duration: 8.00)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(1.7)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["middle logical"], file: file, line: line)

        harness.setTime(3.1)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ],
            file: file,
            line: line
        )

        harness.setTime(3.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ],
            file: file,
            line: line
        )
    }

    func testDirectSpringBuiltInRetargetPrunesCompletedNonPrefixFork() {
        assertDirectSpringBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { duration in
                .interpolatingSpring(
                    Spring(response: duration, dampingRatio: 0.70),
                    initialVelocity: 0.0
                )
            }
        )
        assertDirectSpringBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { duration in
                let stiffness = pow(2 * Double.pi / duration, 2)
                let damping = 2 * 0.70 * sqrt(stiffness)
                return .interpolatingSpring(
                    mass: 1.0,
                    stiffness: stiffness,
                    damping: damping,
                    initialVelocity: 0.0
                )
            }
        )
        assertDirectSpringBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { duration in
                .interpolatingSpring(
                    duration: duration,
                    bounce: 0.20,
                    initialVelocity: 0.0
                )
            }
        )
    }

    private func assertDirectSpringBuiltInRetargetPrunesCompletedNonPrefixFork(
        animation: (TimeInterval) -> Animation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        func logicalTransaction(
            label: String,
            duration: TimeInterval
        ) -> Transaction {
            var transaction = Transaction(animation: animation(duration))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old", duration: 2.40)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle", duration: 0.70)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active", duration: 8.00)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(1.20)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(1.35)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["middle logical"], file: file, line: line)

        harness.setTime(2.55)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ],
            file: file,
            line: line
        )

        harness.setTime(3.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ],
            file: file,
            line: line
        )
    }

    func testDefaultDirectSpringAliasBuiltInRetargetPreservesPrefixForkLogicalOrder() {
        assertDefaultDirectSpringAliasBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .interpolatingSpring()
        )
        assertDefaultDirectSpringAliasBuiltInRetargetPreservesPrefixForkLogicalOrder(
            animation: .interpolatingSpring
        )
    }

    private func assertDefaultDirectSpringAliasBuiltInRetargetPreservesPrefixForkLogicalOrder(
        animation: Animation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        func logicalTransaction(label: String) -> Transaction {
            var transaction = Transaction(animation: animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old")
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.20)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle")
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.40)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active")
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.62)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["old logical"], file: file, line: line)

        harness.setTime(0.84)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            Array(recorder.events.prefix(2)),
            [
                "old logical",
                "middle logical",
            ],
            file: file,
            line: line
        )

        harness.setTime(1.08)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old logical",
                "middle logical",
                "active logical",
            ],
            file: file,
            line: line
        )
    }

    func testLogicalCompletionBuiltInRetargetPrunesCompletedNonPrefixFork() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        func logicalTransaction(
            label: String,
            logicalDuration: TimeInterval
        ) -> Transaction {
            var transaction = Transaction(
                animation: Animation.linear(duration: 8.00)
                    .logicallyComplete(after: logicalDuration)
            )
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old", logicalDuration: 2.40)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle", logicalDuration: 0.70)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalTransaction(label: "active", logicalDuration: 8.00)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.20)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.35)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["middle logical"])

        harness.setTime(2.55)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ]
        )

        harness.setTime(3.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "middle logical",
                "old logical",
            ]
        )
    }

    func testFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork() {
        assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { totalDuration in
                Animation.linear(duration: totalDuration - 0.20).delay(0.20)
            }
        )
        assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { totalDuration in
                Animation.linear(duration: totalDuration * 2.0).speed(2.0)
            }
        )
        assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { totalDuration in
                Animation.linear(duration: totalDuration / 2.0)
                    .repeatCount(2, autoreverses: false)
            },
            expectedOrder: .middleActiveOld
        )
        assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { totalDuration in
                Animation.linear(duration: totalDuration / 2.0 - 0.10)
                    .delay(0.10)
                    .repeatCount(2, autoreverses: false)
            },
            expectedOrder: .middleActiveOld
        )
        assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { totalDuration in
                Animation.linear(duration: (totalDuration - 0.20) / 2.0)
                    .repeatCount(2, autoreverses: false)
                    .delay(0.20)
            },
            expectedOrder: .activeOldMiddle
        )
        assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { totalDuration in
                Animation.linear(duration: totalDuration)
                    .speed(2.0)
                    .repeatCount(2, autoreverses: false)
            },
            expectedOrder: .middleActiveOld
        )
        assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { totalDuration in
                Animation.linear(duration: totalDuration / 4.0)
                    .repeatCount(2, autoreverses: false)
                    .speed(0.5)
            },
            expectedOrder: .middleActiveOld
        )
        assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { totalDuration in
                Animation.linear(duration: totalDuration / 2.0)
                    .repeatCount(2, autoreverses: false)
            },
            activeAnimation: { totalDuration in
                Animation.linear(duration: totalDuration)
            },
            expectedOrder: .middleActiveOld
        )
        assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { totalDuration in
                Animation.linear(duration: totalDuration / 2.0)
                    .repeatCount(2, autoreverses: false)
            },
            activeAnimation: { totalDuration in
                Animation.easeInOut(duration: totalDuration)
            },
            expectedOrder: .middleActiveOld
        )
        assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
            animation: { totalDuration in
                Animation.linear(duration: totalDuration / 2.0)
                    .repeatCount(2, autoreverses: false)
            },
            activeAnimation: { totalDuration in
                Animation.timingCurve(.circularEaseInOut, duration: totalDuration)
            },
            expectedOrder: .middleActiveOld
        )
    }

    private enum FiniteWrapperForkCompletionOrder {
        case middleOld
        case middleActiveOld
        case activeOldMiddle
    }

    private func assertFiniteWrapperBuiltInRetargetPrunesCompletedNonPrefixFork(
        animation: (TimeInterval) -> Animation,
        activeAnimation: ((TimeInterval) -> Animation)? = nil,
        expectedOrder: FiniteWrapperForkCompletionOrder = .middleOld,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        func logicalTransaction(
            label: String,
            duration: TimeInterval
        ) -> Transaction {
            var transaction = Transaction(animation: animation(duration))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old", duration: 2.40)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalTransaction(label: "middle", duration: 0.70)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: {
                let selectedAnimation: Animation
                if let activeAnimation {
                    selectedAnimation = activeAnimation(8.00)
                } else {
                    selectedAnimation = animation(8.00)
                }
                var transaction = Transaction(
                    animation: selectedAnimation
                )
                transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                    recorder.record("active logical")
                }
                return transaction
            }()
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(1.7)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        if expectedOrder == .activeOldMiddle {
            XCTAssertEqual(recorder.events, [], file: file, line: line)
        } else {
            XCTAssertEqual(recorder.events, ["middle logical"], file: file, line: line)
        }

        harness.setTime(3.1)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        if expectedOrder == .activeOldMiddle {
            XCTAssertEqual(recorder.events, [], file: file, line: line)
        } else if expectedOrder == .middleActiveOld {
            XCTAssertEqual(recorder.events, ["middle logical"], file: file, line: line)
        } else {
            XCTAssertEqual(
                recorder.events,
                [
                    "middle logical",
                    "old logical",
                ],
                file: file,
                line: line
            )
        }

        harness.setTime(3.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        if expectedOrder == .activeOldMiddle {
            XCTAssertEqual(recorder.events, [], file: file, line: line)
        } else if expectedOrder == .middleActiveOld {
            XCTAssertEqual(recorder.events, ["middle logical"], file: file, line: line)
        } else {
            XCTAssertEqual(
                recorder.events,
                [
                    "middle logical",
                    "old logical",
                ],
                file: file,
                line: line
            )
        }

        guard expectedOrder == .middleActiveOld || expectedOrder == .activeOldMiddle else { return }

        harness.setTime(9.2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        switch expectedOrder {
        case .middleOld:
            XCTFail("unexpected finite wrapper expected order", file: file, line: line)
        case .middleActiveOld:
            XCTAssertEqual(
                recorder.events,
                [
                    "middle logical",
                    "active logical",
                    "old logical",
                ],
                file: file,
                line: line
            )
        case .activeOldMiddle:
            XCTAssertEqual(
                recorder.events,
                [
                    "active logical",
                    "old logical",
                    "middle logical",
                ],
                file: file,
                line: line
            )
        }
    }

    func testInfiniteWrapperBuiltInRetargetGroupsLogicalAtFiniteReplacementBoundary() {
        assertInfiniteWrapperBuiltInRetargetGroupsLogicalAtFiniteReplacementBoundary(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false)
        )
        assertInfiniteWrapperBuiltInRetargetGroupsLogicalAtFiniteReplacementBoundary(
            oldAnimation: Animation.linear(duration: 0.40).speed(0.0)
        )
    }

    private func assertInfiniteWrapperBuiltInRetargetGroupsLogicalAtFiniteReplacementBoundary(
        oldAnimation: Animation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let replacementAnimation = Animation.linear(duration: 0.30)
        let retargetTime = 0.45
        let replacementTarget = -0.5
        let frame = replacementAnimation.box.defaultDisplayFrameInterval

        func logicalTransaction(
            label: String,
            animation: Animation
        ) -> Transaction {
            var transaction = Transaction(animation: animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                recorder.record("\(label) logical")
            }
            return transaction
        }

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalTransaction(label: "old", animation: oldAnimation)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(retargetTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: replacementTarget),
            transaction: logicalTransaction(label: "replacement", animation: replacementAnimation)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        let replacementBoundary = retargetTime + replacementAnimation.box.duration
        harness.setTime(replacementBoundary - frame)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(replacementBoundary + frame)
        XCTAssertEqual(harness.currentValue().opacity, replacementTarget, accuracy: 0.000_001, file: file, line: line)
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement logical",
                "old logical",
            ],
            file: file,
            line: line
        )

        harness.setTime(replacementBoundary + 0.50)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "replacement logical",
                "old logical",
            ],
            file: file,
            line: line
        )
    }

    func testNodeRemovalWithForkedCompletionRecordsDrainsActiveBeforeForkLogical() {
        let recorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        func transaction(label: String, reason: UInt32) -> Transaction {
            var transaction = completionTransaction(
                animation: Animation(
                    RetargetBoundaryRecordingAnimation(
                        label: label,
                        logicalAt: 20,
                        nilAt: 20,
                        recorder: sampleRecorder
                    )
                ),
                label: label,
                recorder: recorder
            )
            transaction.animationFrameInterval = 1.0 / 30.0
            transaction.animationReason = reason
            return transaction
        }

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction(label: "old", reason: 0xA59)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: transaction(label: "middle", reason: 0xA5A)
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.8)
        _ = harness.currentValue()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: transaction(label: "active", reason: 0xA5B)
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.2)
        _ = harness.currentValue()
        harness.setTime(1.3)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA59, 0xA5A, 0xA5B])
        harness.resetNextUpdate()

        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "middle removed",
                "active removed",
                "active logical",
                "old logical",
                "middle logical",
            ]
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])

        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "old removed",
                "middle removed",
                "active removed",
                "active logical",
                "old logical",
                "middle logical",
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
        let nilListener = CountingAnimationListener()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        var oldTransaction = completionTransaction(
            animation: Animation(UnitLinearAnimation(duration: 4)),
            label: "old",
            recorder: recorder
        )
        oldTransaction.animationFrameInterval = 1.0 / 30.0
        oldTransaction.animationReason = 0xC51
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: oldTransaction
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
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xC51])

        harness.resetNextUpdate()
        var nilTransaction = Transaction(animation: nil)
        nilTransaction.animationListener = nilListener
        nilTransaction.animationFrameInterval = 1.0 / 120.0
        nilTransaction.animationReason = 0xC52
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: nilTransaction
        )
        harness.finalizeTransactionBody()
        let afterRetarget = harness.currentValue().opacity
        XCTAssertGreaterThan(afterRetarget, beforeRetarget)
        XCTAssertLessThan(afterRetarget, 2)
        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(nilListener.addedCount, 0)
        XCTAssertEqual(nilListener.removedCount, 0)

        harness.resetNextUpdate()
        harness.setTime(0.7)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xC51])

        harness.resetNextUpdate()
        harness.setTime(5.0)
        XCTAssertEqual(harness.currentValue().opacity, 2, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
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

    func testRetargetForkLogicalCompletionCanDrainNewerForkBeforeOlderFork() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        func forkTransaction(
            label: String,
            logicalAt: TimeInterval,
            reason: UInt32
        ) -> Transaction {
            var transaction = completionTransaction(
                animation: Animation(
                    RetargetBoundaryRecordingAnimation(
                        label: label,
                        logicalAt: logicalAt,
                        nilAt: 20.0,
                        recorder: sampleRecorder
                    )
                ),
                label: label,
                recorder: completionRecorder
            )
            transaction.animationFrameInterval = 1.0 / 30.0
            transaction.animationReason = reason
            return transaction
        }
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: forkTransaction(label: "old", logicalAt: 2.10, reason: 0xA4D)
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: forkTransaction(label: "middle", logicalAt: 1.35, reason: 0xA4E)
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        let shouldMergeAfterMiddle = sampleRecorder.shouldMergeCount
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: forkTransaction(label: "active", logicalAt: 10.0, reason: 0xA4F)
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, shouldMergeAfterMiddle)
        XCTAssertEqual(completionRecorder.events, [])
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA4D, 0xA4E, 0xA4F])
        harness.resetNextUpdate()

        harness.setTime(2.05)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA4F])
        harness.flushCompletionActions()
        XCTAssertEqual(completionRecorder.events, ["middle logical"])
        harness.resetNextUpdate()

        harness.setTime(2.80)
        _ = harness.currentValue()
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA4F])
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "middle logical",
                "old logical",
            ]
        )
        XCTAssertFalse(completionRecorder.events.contains("active logical"))
    }

    func testRetargetForkRemovalDrainsActiveLogicalBeforeForkedLogicalListeners() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        func forkTransaction(label: String, reason: UInt32) -> Transaction {
            var transaction = completionTransaction(
                animation: Animation(
                    RetargetBoundaryRecordingAnimation(
                        label: label,
                        logicalAt: 10.0,
                        nilAt: 20.0,
                        recorder: sampleRecorder
                    )
                ),
                label: label,
                recorder: completionRecorder
            )
            transaction.animationFrameInterval = 1.0 / 30.0
            transaction.animationReason = reason
            return transaction
        }
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: forkTransaction(label: "old", reason: 0xA50)
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: forkTransaction(label: "middle", reason: 0xA51)
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        let shouldMergeAfterMiddle = sampleRecorder.shouldMergeCount
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: forkTransaction(label: "active", reason: 0xA52)
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, shouldMergeAfterMiddle)
        XCTAssertEqual(completionRecorder.events, [])
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA50, 0xA51, 0xA52])
        harness.resetNextUpdate()

        harness.invalidateAnimatableSubgraph()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "middle removed",
                "active removed",
                "active logical",
                "old logical",
                "middle logical",
            ]
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }

    func testRetargetForkPhaseResetDrainsActiveLogicalBeforeForkedLogicalListeners() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        func forkTransaction(label: String, reason: UInt32) -> Transaction {
            var transaction = completionTransaction(
                animation: Animation(
                    RetargetBoundaryRecordingAnimation(
                        label: label,
                        logicalAt: 10.0,
                        nilAt: 20.0,
                        recorder: sampleRecorder
                    )
                ),
                label: label,
                recorder: completionRecorder
            )
            transaction.animationFrameInterval = 1.0 / 30.0
            transaction.animationReason = reason
            return transaction
        }
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: forkTransaction(label: "old", reason: 0xA53)
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setTime(0.5)
        _ = harness.currentValue()
        harness.setTime(0.6)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: forkTransaction(label: "middle", reason: 0xA54)
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        let shouldMergeAfterMiddle = sampleRecorder.shouldMergeCount
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: forkTransaction(label: "active", reason: 0xA55)
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.1)
        _ = harness.currentValue()
        harness.setTime(1.2)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, shouldMergeAfterMiddle)
        XCTAssertEqual(completionRecorder.events, [])
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA53, 0xA54, 0xA55])
        harness.resetNextUpdate()

        harness.bumpPhaseResetSeed()
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "middle removed",
                "active removed",
                "active logical",
                "old logical",
                "middle logical",
            ]
        )
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])
    }

    func testRetargetForkActiveTerminalDrainsActiveLogicalBeforeForkedLogicalListeners() {
        let completionRecorder = AnimationCompletionRecorder()
        let sampleRecorder = CustomRetargetSampleRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        func forkTransaction(
            label: String,
            logicalAt: TimeInterval,
            nilAt: TimeInterval,
            reason: UInt32
        ) -> Transaction {
            var transaction = completionTransaction(
                animation: Animation(
                    RetargetBoundaryRecordingAnimation(
                        label: label,
                        logicalAt: logicalAt,
                        nilAt: nilAt,
                        recorder: sampleRecorder
                    )
                ),
                label: label,
                recorder: completionRecorder
            )
            transaction.animationFrameInterval = 1.0 / 30.0
            transaction.animationReason = reason
            return transaction
        }
        XCTAssertEqual(harness.currentValue().opacity, 0)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: forkTransaction(
                label: "old",
                logicalAt: 10.0,
                nilAt: 20.0,
                reason: 0xA56
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
            transaction: forkTransaction(
                label: "middle",
                logicalAt: 10.0,
                nilAt: 20.0,
                reason: 0xA57
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.9)
        _ = harness.currentValue()
        harness.setTime(1.0)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0)
        let shouldMergeAfterMiddle = sampleRecorder.shouldMergeCount
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: forkTransaction(
                label: "active",
                logicalAt: 10.0,
                nilAt: 1.05,
                reason: 0xA58
            )
        )
        harness.finalizeTransactionBody()
        harness.setTime(1.5)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, shouldMergeAfterMiddle)
        XCTAssertEqual(completionRecorder.events, [])
        XCTAssertEqual(harness.nextUpdateInterval(), 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [0xA56, 0xA57, 0xA58])
        harness.resetNextUpdate()

        harness.setTime(2.1)
        _ = harness.currentValue()
        XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, shouldMergeAfterMiddle)
        XCTAssertEqual(completionRecorder.events, [])
        XCTAssertEqual(harness.nextUpdateInterval(), 0, accuracy: 0.000_001)
        XCTAssertEqual(harness.nextUpdateReasons(), [])

        harness.flushCompletionActions()
        XCTAssertEqual(
            completionRecorder.events,
            [
                "old removed",
                "middle removed",
                "active removed",
                "active logical",
                "old logical",
                "middle logical",
            ]
        )
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

    func testCombinedCustomInteractiveNestedRepeatForeverKeepsSourceLogicalAndPendingRemoved() throws {
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
        let cases: [(
            label: String,
            animation: Animation,
            allowsSecondReplacementBoundaryTie: Bool
        )] = [
            (
                "interactivePropertyDelayRepeat",
                Animation.interactiveSpring.delay(0.20).repeatForever(autoreverses: false),
                true
            ),
            (
                "interactiveNoArgDelayRepeat",
                Animation.interactiveSpring().delay(0.20).repeatForever(autoreverses: false),
                true
            ),
            (
                "interactiveResponseDelayRepeat",
                interactiveResponse.delay(0.20).repeatForever(autoreverses: false),
                false
            ),
            (
                "interactiveDurationDelayRepeat",
                interactiveDuration.delay(0.20).repeatForever(autoreverses: false),
                true
            ),
            (
                "interactivePropertyRepeatDelay",
                Animation.interactiveSpring.repeatForever(autoreverses: false).delay(0.20),
                false
            ),
            (
                "interactiveNoArgRepeatDelay",
                Animation.interactiveSpring().repeatForever(autoreverses: false).delay(0.20),
                true
            ),
            (
                "interactiveResponseRepeatDelay",
                interactiveResponse.repeatForever(autoreverses: false).delay(0.20),
                false
            ),
            (
                "interactiveDurationRepeatDelay",
                interactiveDuration.repeatForever(autoreverses: false).delay(0.20),
                false
            ),
        ]

        for testCase in cases {
            let completionRecorder = AnimationCompletionRecorder()
            let sampleRecorder = CustomRetargetSampleRecorder()
            let harness = AnimatableAttributeHarness(
                initialValue: _OpacityEffect(opacity: 0)
            )
            XCTAssertEqual(harness.currentValue().opacity, 0, testCase.label)
            harness.setSource(
                _OpacityEffect(opacity: 1),
                transaction: completionTransaction(
                    animation: Animation(
                        CombinedBoundaryRecordingAnimation(
                            label: "old",
                            logicalAt: 1.05,
                            nilAt: 10.0,
                            recorder: sampleRecorder
                        )
                    ),
                    label: "old",
                    recorder: completionRecorder
                )
            )
            harness.finalizeTransactionBody()
            harness.setTime(0.5)
            _ = harness.currentValue()
            harness.setTime(0.6)
            _ = harness.currentValue()
            harness.setSource(
                _OpacityEffect(opacity: -0.5),
                transaction: completionTransaction(
                    animation: Animation(
                        CombinedBoundaryRecordingAnimation(
                            label: "second",
                            logicalAt: 0.50,
                            nilAt: 10.0,
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
            XCTAssertGreaterThan(sampleRecorder.shouldMergeCount, 0, testCase.label)
            XCTAssertEqual(completionRecorder.events, [], testCase.label)
            sampleRecorder.removeAll()

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
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)

            harness.setTime(2.8)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            let events = completionRecorder.events
            XCTAssertEqual(
                Set(events),
                Set(["old logical", "second logical", "\(testCase.label) logical"]),
                testCase.label
            )
            XCTAssertEqual(events.count, 3, testCase.label)
            let oldIndex = try XCTUnwrap(events.firstIndex(of: "old logical"), testCase.label)
            let secondIndex = try XCTUnwrap(events.firstIndex(of: "second logical"), testCase.label)
            let replacementIndex = try XCTUnwrap(
                events.firstIndex(of: "\(testCase.label) logical"),
                testCase.label
            )
            XCTAssertLessThan(oldIndex, replacementIndex, testCase.label)
            if !testCase.allowsSecondReplacementBoundaryTie {
                XCTAssertLessThan(secondIndex, replacementIndex, testCase.label)
            }
            XCTAssertFalse(events.contains { $0.contains("removed") }, testCase.label)
        }
    }

    func testCombinedCustomFluidSpringPropertyAliasFiniteRepeatWrappersKeepResidualOwnership() {
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
        let sourceNilBeforeFinalization: (String) -> [String] = { label in
            [
                "\(label) logical",
                "old logical",
                "second logical",
            ]
        }
        let sourceNilCases: [(
            label: String,
            animation: Animation,
            expectedAfterSourceNilSample: [String]
        )] = [
            (
                "springPropertyRepeat",
                Animation.spring.repeatCount(2, autoreverses: false),
                sourceNilBeforeFinalization("springPropertyRepeat")
            ),
            (
                "springNoArgRepeat",
                Animation.spring().repeatCount(2, autoreverses: false),
                sourceNilBeforeFinalization("springNoArgRepeat")
            ),
            (
                "interactivePropertyRepeat",
                Animation.interactiveSpring.repeatCount(2, autoreverses: false),
                finalEvents("interactivePropertyRepeat")
            ),
            (
                "interactiveNoArgRepeat",
                Animation.interactiveSpring().repeatCount(2, autoreverses: false),
                finalEvents("interactiveNoArgRepeat")
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
                testCase.expectedAfterSourceNilSample,
                testCase.label
            )
            harness.setTime(8.0)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(
                completionRecorder.events,
                finalEvents(testCase.label),
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

        let residualFirstCases: [(label: String, animation: Animation, finalTime: TimeInterval)] = [
            ("springNoArgDelayNegative", Animation.spring().delay(-0.20), 2.8),
            ("interactivePropertyDelayZero", Animation.interactiveSpring.delay(0.0), 2.8),
            ("interactiveNoArgDelayNegative", Animation.interactiveSpring().delay(-0.20), 4.2),
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

    func testCombinedCustomResidualLogicalCompletionWrappersUseBaseFinalizationClasses() {
        let springAnimation = Animation.interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0,
            initialVelocity: 0.0
        )
        let cases: [
            (
                label: String,
                animation: Animation,
                firstEvents: [String],
                logicalTime: TimeInterval,
                finalTime: TimeInterval,
                expectedEvents: [String]
            )
        ] = [
            (
                "springLogicalWrapper",
                springAnimation.logicallyComplete(after: 0.25),
                [],
                1.8,
                3.0,
                [
                    "springLogicalWrapper logical",
                    "old removed",
                    "second removed",
                    "springLogicalWrapper removed",
                    "old logical",
                    "second logical",
                ]
            ),
            (
                "springDurationAliasLogicalWrapper",
                Animation.interpolatingSpring(duration: 1.20, bounce: 0.0, initialVelocity: 0.0)
                    .logicallyComplete(after: 0.25),
                [],
                1.8,
                4.0,
                [
                    "springDurationAliasLogicalWrapper logical",
                    "old removed",
                    "second removed",
                    "springDurationAliasLogicalWrapper removed",
                    "old logical",
                    "second logical",
                ]
            ),
            (
                "springPropertyAliasLogicalWrapper",
                Animation.interpolatingSpring
                    .logicallyComplete(after: 0.25),
                [],
                1.8,
                4.0,
                [
                    "springPropertyAliasLogicalWrapper logical",
                    "old removed",
                    "second removed",
                    "springPropertyAliasLogicalWrapper removed",
                    "old logical",
                    "second logical",
                ]
            ),
            (
                "fluidLogicalWrapper",
                Animation.spring(response: 0.45, dampingFraction: 0.72, blendDuration: 0)
                    .logicallyComplete(after: 0.25),
                ["fluidLogicalWrapper logical"],
                1.8,
                4.4,
                [
                    "fluidLogicalWrapper logical",
                    "old logical",
                    "second logical",
                    "old removed",
                    "second removed",
                    "fluidLogicalWrapper removed",
                ]
            ),
            (
                "fluidDurationAliasLogicalWrapper",
                Animation.spring(duration: 0.45, bounce: 0.0, blendDuration: 0)
                    .logicallyComplete(after: 0.25),
                ["fluidDurationAliasLogicalWrapper logical"],
                1.8,
                4.8,
                [
                    "fluidDurationAliasLogicalWrapper logical",
                    "old logical",
                    "second logical",
                    "old removed",
                    "second removed",
                    "fluidDurationAliasLogicalWrapper removed",
                ]
            ),
            (
                "fluidPropertyAliasLogicalWrapper",
                Animation.spring
                    .logicallyComplete(after: 0.25),
                ["fluidPropertyAliasLogicalWrapper logical"],
                1.8,
                4.8,
                [
                    "fluidPropertyAliasLogicalWrapper logical",
                    "old logical",
                    "second logical",
                    "old removed",
                    "second removed",
                    "fluidPropertyAliasLogicalWrapper removed",
                ]
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
            harness.setTime(1.3)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "old" }, testCase.label)
            XCTAssertTrue(sampleRecorder.samples.contains { $0.label == "second" }, testCase.label)
            XCTAssertFalse(completionRecorder.events.contains { $0.contains("removed") }, testCase.label)
            XCTAssertEqual(completionRecorder.events, testCase.firstEvents, testCase.label)

            harness.setTime(testCase.logicalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, ["\(testCase.label) logical"], testCase.label)

            harness.setTime(testCase.finalTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(completionRecorder.events, testCase.expectedEvents, testCase.label)
        }
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
