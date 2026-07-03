import XCTest
@testable import VUI

final class CustomAnimationVelocityRoutingTests: XCTestCase {
    func testDirectFluidSpringMergeSeedsStateFromOldVelocityAndOutput() {
        let recorder = DetailedVelocityRecorder()
        let previous = Animation(
            DetailedVelocityAnimation(
                recorder: recorder,
                outputScale: 0.25,
                velocityScale: 3.0
            )
        )
        var context = AnimationContext<Double>()
        context.state[DetailedVelocityFrameKey.self] = 11

        let merged = Animation
            .spring(response: 0.4, dampingFraction: 0.8)
            .shouldMerge(previous: previous, value: 2.0, time: 0.25, context: &context)

        XCTAssertTrue(merged)
        XCTAssertEqual(
            recorder.events,
            [
                DetailedVelocityEvent(kind: "velocity", value: 2.0, time: 0.25, frame: 11, logical: false),
                DetailedVelocityEvent(kind: "animate", value: 2.0, time: 0.25, frame: 11, logical: false),
            ]
        )

        let springState = context.state[SpringState<Double>.self]
        XCTAssertTrue(springState.isInitialized)
        XCTAssertEqual(springState.position, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(springState.velocity, 6.0, accuracy: 0.000_001)
        XCTAssertEqual(springState.time, 0.25, accuracy: 0.000_001)
    }

    func testDirectDefaultAndFluidSpringReplacementsCallOldVelocityBeforeAnimate() {
        XCTAssertEqual(
            eventsWhenMerging(
                replacement: .default,
                previous: recordingAnimation(),
                value: 1.0
            ),
            ["velocity:old", "animate:old"]
        )

        XCTAssertEqual(
            eventsWhenMerging(
                replacement: .spring(response: 0.4, dampingFraction: 0.8),
                previous: recordingAnimation(),
                value: 1.0
            ),
            ["velocity:old", "animate:old"]
        )
    }

    func testDirectFluidSpringAliasReplacementsCallOldVelocityBeforeAnimate() {
        let aliases: [Animation] = [
            .spring(duration: 0.4, bounce: 0.2),
            .spring(Spring(duration: 0.4, bounce: 0.1)),
            .spring,
            .spring(),
            .interactiveSpring(response: 0.2, dampingFraction: 0.7),
            .interactiveSpring(duration: 0.2, extraBounce: 0.1),
            .interactiveSpring,
            .interactiveSpring(),
            .smooth(duration: 0.4, extraBounce: 0.1),
            .snappy(duration: 0.4, extraBounce: 0.1),
            .bouncy(duration: 0.4, extraBounce: 0.1),
        ]

        for alias in aliases {
            XCTAssertEqual(
                eventsWhenMerging(
                    replacement: alias,
                    previous: recordingAnimation(),
                    value: 1.0
                ),
                ["velocity:old", "animate:old"]
            )
        }
    }

    func testDirectFluidSpringAliasReplacementsCallVectorVelocityBeforeAnimate() {
        let value = AnimatablePair(1.0, -0.5)
        let aliases: [Animation] = [
            .default,
            .spring(response: 0.4, dampingFraction: 0.8),
            .spring(duration: 0.4, bounce: 0.2),
            .spring(Spring(duration: 0.4, bounce: 0.1)),
            .spring,
            .spring(),
            .interactiveSpring(response: 0.2, dampingFraction: 0.7),
            .interactiveSpring(duration: 0.2, extraBounce: 0.1),
            .interactiveSpring,
            .interactiveSpring(),
            .smooth(duration: 0.4, extraBounce: 0.1),
            .snappy(duration: 0.4, extraBounce: 0.1),
            .bouncy(duration: 0.4, extraBounce: 0.1),
        ]

        for alias in aliases {
            XCTAssertEqual(
                eventsWhenMerging(
                    replacement: alias,
                    previous: recordingAnimation(),
                    value: value
                ),
                ["velocity:old", "animate:old"]
            )
        }
    }

    func testSpringFiniteAndWrappedReplacementsDoNotCallOldVelocity() {
        XCTAssertTrue(
            eventsWhenMerging(
                replacement: .interpolatingSpring(mass: 1, stiffness: 100, damping: 10),
                previous: recordingAnimation(),
                value: 1.0
            ).isEmpty
        )

        XCTAssertTrue(
            eventsWhenMerging(
                replacement: .linear(duration: 0.4),
                previous: recordingAnimation(),
                value: 1.0
            ).isEmpty
        )

        XCTAssertTrue(
            eventsWhenMerging(
                replacement: .spring(response: 0.4, dampingFraction: 0.8).delay(0.1),
                previous: recordingAnimation(),
                value: 1.0
            ).isEmpty
        )
    }

    func testWrappedFluidSpringAliasesDoNotCallOldVelocity() {
        let replacements: [Animation] = [
            .default.delay(0.1),
            .spring(response: 0.4, dampingFraction: 0.8).delay(0.1),
            .spring().speed(2.0),
            Animation.spring.delay(0.1),
            Animation.spring().repeatForever(autoreverses: false),
            Animation.interactiveSpring.speed(0.0),
            Animation.interactiveSpring().delay(0.1).speed(2.0),
            .interactiveSpring().repeatCount(2, autoreverses: false),
            .smooth(duration: 0.4, extraBounce: 0.1).delay(0.0),
            .snappy(duration: 0.4, extraBounce: 0.1).speed(-1.0),
            .bouncy(duration: 0.4, extraBounce: 0.1).repeatForever(autoreverses: false),
        ]

        for replacement in replacements {
            XCTAssertTrue(
                eventsWhenMerging(
                    replacement: replacement,
                    previous: recordingAnimation(),
                    value: 1.0
                ).isEmpty
            )
            XCTAssertTrue(
                eventsWhenMerging(
                    replacement: replacement,
                    previous: recordingAnimation(),
                    value: AnimatablePair(1.0, -0.5)
                ).isEmpty
            )
        }
    }

    func testFiniteWrappersDoNotCallSourceDefinedVelocityInEitherDirection() {
        let wrappers: [(String, Animation)] = [
            (
                "p1p2Delay",
                Animation.timingCurve(0.18, 0.07, 0.82, 0.96, duration: 0.4).delay(0.1)
            ),
            ("easeInSpeed", Animation.easeIn(duration: 0.4).speed(2.0)),
            ("easeOutRepeat", Animation.easeOut(duration: 0.4).repeatCount(2, autoreverses: false)),
            (
                "cubicDelay",
                Animation.timingCurve(
                    .bezier(
                        startControlPoint: UnitPoint(x: 0.18, y: 0.07),
                        endControlPoint: UnitPoint(x: 0.82, y: 0.96)
                    ),
                    duration: 0.4
                ).delay(0.1)
            ),
            (
                "circularEaseInSpeed",
                Animation.timingCurve(.circularEaseIn, duration: 0.4).speed(2.0)
            ),
            (
                "circularEaseOutRepeat",
                Animation.timingCurve(.circularEaseOut, duration: 0.4).repeatCount(
                    2,
                    autoreverses: false
                )
            ),
        ]

        for (label, wrapper) in wrappers {
            XCTAssertTrue(
                eventsWhenMerging(
                    replacement: wrapper,
                    previous: recordingAnimation(),
                    value: 1.0
                ).isEmpty,
                label
            )
            XCTAssertTrue(
                eventsWhenMerging(
                    replacement: wrapper,
                    previous: recordingAnimation(),
                    value: AnimatablePair(1.0, -0.5)
                ).isEmpty,
                label
            )

            let scalarRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: recordingAnimation(id: "replacement", recorder: scalarRecorder),
                previous: wrapper,
                value: 1.0
            )
            XCTAssertEqual(scalarRecorder.events, ["shouldMerge:replacement"], label)

            let vectorRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: recordingAnimation(id: "replacement", recorder: vectorRecorder),
                previous: wrapper,
                value: AnimatablePair(1.0, -0.5)
            )
            XCTAssertEqual(vectorRecorder.events, ["shouldMerge:replacement"], label)
        }
    }

    func testDirectSpringAndFiniteAliasesDoNotCallOldVelocity() {
        let replacements = directSpringAnimations() + directFiniteAnimations()

        for (label, replacement) in replacements {
            XCTAssertTrue(
                eventsWhenMerging(
                    replacement: replacement,
                    previous: recordingAnimation(),
                    value: 1.0
                ).isEmpty,
                label
            )
            XCTAssertTrue(
                eventsWhenMerging(
                    replacement: replacement,
                    previous: recordingAnimation(),
                    value: AnimatablePair(1.0, -0.5)
                ).isEmpty,
                label
            )
        }
    }

    func testSourceDefinedReplacementShouldMergeDoesNotCallReplacementVelocity() {
        let recorder = AnimationVelocityRecorder()
        let replacement = Animation(RecordingVelocityAnimation(id: "replacement", recorder: recorder))
        _ = eventsWhenMerging(
            replacement: replacement,
            previous: .spring(response: 0.4, dampingFraction: 0.8),
            value: 1.0
        )

        XCTAssertEqual(recorder.events, ["shouldMerge:replacement"])
    }

    func testReverseDirectSpringAliasesDoNotCallReplacementVelocity() {
        for (label, previous) in directSpringAnimations() {
            let scalarRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: recordingAnimation(id: "replacement", recorder: scalarRecorder),
                previous: previous,
                value: 1.0
            )
            XCTAssertEqual(scalarRecorder.events, ["shouldMerge:replacement"], label)

            let vectorRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: recordingAnimation(id: "replacement", recorder: vectorRecorder),
                previous: previous,
                value: AnimatablePair(1.0, -0.5)
            )
            XCTAssertEqual(vectorRecorder.events, ["shouldMerge:replacement"], label)
        }
    }

    func testReverseDirectFiniteAliasesDoNotCallReplacementVelocity() {
        for (label, previous) in directFiniteAnimations() {
            let scalarRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: recordingAnimation(id: "replacement", recorder: scalarRecorder),
                previous: previous,
                value: 1.0
            )
            XCTAssertEqual(scalarRecorder.events, ["shouldMerge:replacement"], label)

            let vectorRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: recordingAnimation(id: "replacement", recorder: vectorRecorder),
                previous: previous,
                value: AnimatablePair(1.0, -0.5)
            )
            XCTAssertEqual(vectorRecorder.events, ["shouldMerge:replacement"], label)
        }
    }

    func testContinuousTrackedSourceDefinedTransactionsDoNotCallVelocity() {
        let recorder = AnimationVelocityRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)
        var oldTransaction = Transaction(animation: recordingAnimation(id: "old", recorder: recorder))
        oldTransaction.isContinuous = true
        oldTransaction.tracksVelocity = true
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: oldTransaction
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.setTime(0.25)
        _ = harness.currentValue()

        var replacementTransaction = Transaction(
            animation: recordingAnimation(id: "replacement", recorder: recorder)
        )
        replacementTransaction.isContinuous = true
        replacementTransaction.tracksVelocity = true
        harness.setSource(
            _OpacityEffect(opacity: 0.5),
            transaction: replacementTransaction
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.35)
        _ = harness.currentValue()

        let events = recorder.events
        XCTAssertFalse(events.contains { $0.hasPrefix("velocity:") }, "\(events)")
        XCTAssertTrue(events.contains("animate:old"), "\(events)")
        XCTAssertTrue(events.contains("shouldMerge:replacement"), "\(events)")
        XCTAssertTrue(events.contains("animate:replacement"), "\(events)")
    }

    func testContinuousTrackedSourceCustomToDirectSpringDoesNotCallVelocity() {
        let recorder = AnimationVelocityRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0)

        var oldTransaction = Transaction(animation: recordingAnimation(id: "old", recorder: recorder))
        oldTransaction.isContinuous = true
        oldTransaction.tracksVelocity = true
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: oldTransaction
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.setTime(0.25)
        _ = harness.currentValue()

        var springTransaction = Transaction(
            animation: .interpolatingSpring(mass: 1.0, stiffness: 80.0, damping: 12.0)
        )
        springTransaction.isContinuous = true
        springTransaction.tracksVelocity = true
        harness.setSource(
            _OpacityEffect(opacity: 0.5),
            transaction: springTransaction
        )
        harness.finalizeTransactionBody()
        harness.setTime(0.35)
        _ = harness.currentValue()

        let events = recorder.events
        XCTAssertFalse(events.contains { $0.hasPrefix("velocity:") }, "\(events)")
        XCTAssertTrue(events.contains("animate:old"), "\(events)")
    }

    func testNoExplicitVelocityTrackingRetargetsDoNotCallSourceDefinedVelocity() {
        let customToTrackedRecorder = AnimationVelocityRecorder()
        let customToTrackedHarness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 1)
        )
        XCTAssertEqual(customToTrackedHarness.currentValue().opacity, 1)
        customToTrackedHarness.setSource(
            _OpacityEffect(opacity: 0.1),
            animation: recordingAnimation(id: "old", recorder: customToTrackedRecorder)
        )
        customToTrackedHarness.finalizeTransactionBody()
        _ = customToTrackedHarness.currentValue()
        customToTrackedHarness.setTime(0.25)
        _ = customToTrackedHarness.currentValue()

        var trackedTransaction = Transaction()
        trackedTransaction.tracksVelocity = true
        customToTrackedHarness.setSource(
            _OpacityEffect(opacity: 0.85),
            transaction: trackedTransaction
        )
        customToTrackedHarness.finalizeTransactionBody()
        customToTrackedHarness.setTime(0.35)
        _ = customToTrackedHarness.currentValue()

        XCTAssertFalse(
            customToTrackedRecorder.events.contains { $0.hasPrefix("velocity:") },
            "\(customToTrackedRecorder.events)"
        )
        XCTAssertTrue(
            customToTrackedRecorder.events.contains("animate:old"),
            "\(customToTrackedRecorder.events)"
        )

        let trackedToCustomRecorder = AnimationVelocityRecorder()
        let trackedToCustomHarness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 1)
        )
        XCTAssertEqual(trackedToCustomHarness.currentValue().opacity, 1)
        var firstTrackedTransaction = Transaction()
        firstTrackedTransaction.tracksVelocity = true
        trackedToCustomHarness.setSource(
            _OpacityEffect(opacity: 0.2),
            transaction: firstTrackedTransaction
        )
        trackedToCustomHarness.finalizeTransactionBody()
        _ = trackedToCustomHarness.currentValue()
        trackedToCustomHarness.setTime(0.25)
        _ = trackedToCustomHarness.currentValue()

        trackedToCustomHarness.setSource(
            _OpacityEffect(opacity: 0.8),
            animation: recordingAnimation(id: "replacement", recorder: trackedToCustomRecorder)
        )
        trackedToCustomHarness.finalizeTransactionBody()
        trackedToCustomHarness.setTime(0.35)
        _ = trackedToCustomHarness.currentValue()

        XCTAssertFalse(
            trackedToCustomRecorder.events.contains { $0.hasPrefix("velocity:") },
            "\(trackedToCustomRecorder.events)"
        )
        XCTAssertFalse(
            trackedToCustomRecorder.events.contains("shouldMerge:replacement"),
            "\(trackedToCustomRecorder.events)"
        )
        XCTAssertTrue(
            trackedToCustomRecorder.events.contains("animate:replacement"),
            "\(trackedToCustomRecorder.events)"
        )
    }

    func testSourceDefinedCustomWrappersDoNotCallVelocityInEitherDirection() {
        let wrappers: [(String, (Animation) -> Animation)] = [
            ("delay", { $0.delay(0.10) }),
            ("speed", { $0.speed(2.0) }),
            ("repeat", { $0.repeatCount(2, autoreverses: false) }),
        ]

        for (label, wrapper) in wrappers {
            let oldScalarRecorder = AnimationVelocityRecorder()
            let replacementScalarRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: wrapper(recordingAnimation(id: "replacement", recorder: replacementScalarRecorder)),
                previous: recordingAnimation(id: "old", recorder: oldScalarRecorder),
                value: 1.0
            )
            XCTAssertEqual(oldScalarRecorder.events, [], label)
            XCTAssertEqual(replacementScalarRecorder.events, [], label)

            let oldVectorRecorder = AnimationVelocityRecorder()
            let replacementVectorRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: wrapper(recordingAnimation(id: "replacement", recorder: replacementVectorRecorder)),
                previous: recordingAnimation(id: "old", recorder: oldVectorRecorder),
                value: AnimatablePair(1.0, -0.5)
            )
            XCTAssertEqual(oldVectorRecorder.events, [], label)
            XCTAssertEqual(replacementVectorRecorder.events, [], label)

            let previousWrapperScalarRecorder = AnimationVelocityRecorder()
            let directReplacementScalarRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: recordingAnimation(id: "replacement", recorder: directReplacementScalarRecorder),
                previous: wrapper(recordingAnimation(id: "old", recorder: previousWrapperScalarRecorder)),
                value: 1.0
            )
            XCTAssertEqual(previousWrapperScalarRecorder.events, [], label)
            XCTAssertEqual(directReplacementScalarRecorder.events, ["shouldMerge:replacement"], label)

            let previousWrapperVectorRecorder = AnimationVelocityRecorder()
            let directReplacementVectorRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: recordingAnimation(id: "replacement", recorder: directReplacementVectorRecorder),
                previous: wrapper(recordingAnimation(id: "old", recorder: previousWrapperVectorRecorder)),
                value: AnimatablePair(1.0, -0.5)
            )
            XCTAssertEqual(previousWrapperVectorRecorder.events, [], label)
            XCTAssertEqual(directReplacementVectorRecorder.events, ["shouldMerge:replacement"], label)
        }
    }

    func testSourceDefinedCustomWrappersDoNotCallVelocityThroughAnimatableAttribute() {
        let wrappers: [(String, (Animation) -> Animation)] = [
            ("delay", { $0.delay(0.10) }),
            ("speed", { $0.speed(2.0) }),
            ("repeat", { $0.repeatCount(2, autoreverses: false) }),
        ]

        for (label, wrapper) in wrappers {
            assertScalarSourceDefinedCustomWrapperDoesNotCallVelocity(
                label: label,
                wrapper: wrapper
            )
            assertVectorSourceDefinedCustomWrapperDoesNotCallVelocity(
                label: label,
                wrapper: wrapper
            )
        }
    }

    func testReverseDirectFluidSpringAliasesDoNotCallReplacementVelocity() {
        let previousAnimations: [Animation] = [
            .default,
            .spring(response: 0.4, dampingFraction: 0.8),
            .spring(duration: 0.4, bounce: 0.2),
            .spring(Spring(duration: 0.4, bounce: 0.1)),
            .spring,
            .spring(),
            .interactiveSpring(response: 0.2, dampingFraction: 0.7),
            .interactiveSpring(duration: 0.2, extraBounce: 0.1),
            .interactiveSpring,
            .interactiveSpring(),
            .smooth(duration: 0.4, extraBounce: 0.1),
            .snappy(duration: 0.4, extraBounce: 0.1),
            .bouncy(duration: 0.4, extraBounce: 0.1),
        ]

        for previous in previousAnimations {
            let scalarRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: recordingAnimation(id: "replacement", recorder: scalarRecorder),
                previous: previous,
                value: 1.0
            )
            XCTAssertEqual(scalarRecorder.events, ["shouldMerge:replacement"])

            let vectorRecorder = AnimationVelocityRecorder()
            _ = eventsWhenMerging(
                replacement: recordingAnimation(id: "replacement", recorder: vectorRecorder),
                previous: previous,
                value: AnimatablePair(1.0, -0.5)
            )
            XCTAssertEqual(vectorRecorder.events, ["shouldMerge:replacement"])
        }
    }

    func testHiddenCombinedSourceChildrenDoNotCallVelocityForDirectDefaultAndFluidSpringAliases() {
        let replacements: [Animation] = [
            .default,
            .spring(response: 0.4, dampingFraction: 0.8),
            .spring(duration: 0.4, bounce: 0.2),
            .spring(Spring(duration: 0.4, bounce: 0.1)),
            .spring,
            .spring(),
            .interactiveSpring(response: 0.2, dampingFraction: 0.7),
            .interactiveSpring(duration: 0.2, extraBounce: 0.1),
            .interactiveSpring,
            .interactiveSpring(),
            .smooth(duration: 0.4, extraBounce: 0.1),
            .snappy(duration: 0.4, extraBounce: 0.1),
            .bouncy(duration: 0.4, extraBounce: 0.1),
        ]

        for replacement in replacements {
            let recorder = AnimationVelocityRecorder()
            let previous = combinedRecordingAnimation(recorder: recorder)
            var context = AnimationContext(state: previous.state)

            _ = replacement.shouldMerge(
                previous: previous.animation,
                value: 1.0,
                time: 0.55,
                context: &context
            )

            XCTAssertEqual(recorder.events, ["animate:old", "animate:second"])
        }
    }

    private func recordingAnimation(
        id: String = "old",
        recorder: AnimationVelocityRecorder = AnimationVelocityRecorder()
    ) -> Animation {
        Animation(
            RecordingVelocityAnimation(
                id: id,
                recorder: recorder
            )
        )
    }

    private func combinedRecordingAnimation(
        recorder: AnimationVelocityRecorder
    ) -> (animation: Animation, state: AnimationState<Double>) {
        var animation = recordingAnimation(id: "old", recorder: recorder)
        var state = AnimationState<Double>()
        combineAnimation(
            into: &animation,
            state: &state,
            value: 0.35,
            elapsed: 0.25,
            newAnimation: recordingAnimation(id: "second", recorder: recorder),
            newValue: -0.15
        )
        return (animation, state)
    }

    private func assertScalarSourceDefinedCustomWrapperDoesNotCallVelocity(
        label: String,
        wrapper: (Animation) -> Animation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let customToWrapperOldRecorder = AnimationVelocityRecorder()
        let customToWrapperReplacementRecorder = AnimationVelocityRecorder()
        let customToWrapperHarness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        driveSourceDefinedWrapperRetarget(
            harness: customToWrapperHarness,
            oldAnimation: recordingAnimation(id: "old", recorder: customToWrapperOldRecorder),
            replacementAnimation: wrapper(
                recordingAnimation(id: "replacement", recorder: customToWrapperReplacementRecorder)
            ),
            oldValue: _OpacityEffect(opacity: 1),
            replacementValue: _OpacityEffect(opacity: 0.25)
        )
        assertNoVelocityAndAnimationSampling(
            oldEvents: customToWrapperOldRecorder.events,
            replacementEvents: customToWrapperReplacementRecorder.events,
            label: "\(label) scalar custom-to-wrapper",
            file: file,
            line: line
        )

        let wrapperToCustomOldRecorder = AnimationVelocityRecorder()
        let wrapperToCustomReplacementRecorder = AnimationVelocityRecorder()
        let wrapperToCustomHarness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        driveSourceDefinedWrapperRetarget(
            harness: wrapperToCustomHarness,
            oldAnimation: wrapper(recordingAnimation(id: "old", recorder: wrapperToCustomOldRecorder)),
            replacementAnimation: recordingAnimation(
                id: "replacement",
                recorder: wrapperToCustomReplacementRecorder
            ),
            oldValue: _OpacityEffect(opacity: 1),
            replacementValue: _OpacityEffect(opacity: 0.25)
        )
        assertNoVelocityAndAnimationSampling(
            oldEvents: wrapperToCustomOldRecorder.events,
            replacementEvents: wrapperToCustomReplacementRecorder.events,
            label: "\(label) scalar wrapper-to-custom",
            file: file,
            line: line
        )
    }

    private func assertVectorSourceDefinedCustomWrapperDoesNotCallVelocity(
        label: String,
        wrapper: (Animation) -> Animation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let customToWrapperOldRecorder = AnimationVelocityRecorder()
        let customToWrapperReplacementRecorder = AnimationVelocityRecorder()
        let customToWrapperHarness = GenericAnimatableAttributeHarness(
            initialValue: VelocityPairPayload(x: 0, y: 0)
        )
        driveSourceDefinedWrapperRetarget(
            harness: customToWrapperHarness,
            oldAnimation: recordingAnimation(id: "old", recorder: customToWrapperOldRecorder),
            replacementAnimation: wrapper(
                recordingAnimation(id: "replacement", recorder: customToWrapperReplacementRecorder)
            ),
            oldValue: VelocityPairPayload(x: 1, y: -0.5),
            replacementValue: VelocityPairPayload(x: 0.25, y: 0.75)
        )
        assertNoVelocityAndAnimationSampling(
            oldEvents: customToWrapperOldRecorder.events,
            replacementEvents: customToWrapperReplacementRecorder.events,
            label: "\(label) vector custom-to-wrapper",
            file: file,
            line: line
        )

        let wrapperToCustomOldRecorder = AnimationVelocityRecorder()
        let wrapperToCustomReplacementRecorder = AnimationVelocityRecorder()
        let wrapperToCustomHarness = GenericAnimatableAttributeHarness(
            initialValue: VelocityPairPayload(x: 0, y: 0)
        )
        driveSourceDefinedWrapperRetarget(
            harness: wrapperToCustomHarness,
            oldAnimation: wrapper(recordingAnimation(id: "old", recorder: wrapperToCustomOldRecorder)),
            replacementAnimation: recordingAnimation(
                id: "replacement",
                recorder: wrapperToCustomReplacementRecorder
            ),
            oldValue: VelocityPairPayload(x: 1, y: -0.5),
            replacementValue: VelocityPairPayload(x: 0.25, y: 0.75)
        )
        assertNoVelocityAndAnimationSampling(
            oldEvents: wrapperToCustomOldRecorder.events,
            replacementEvents: wrapperToCustomReplacementRecorder.events,
            label: "\(label) vector wrapper-to-custom",
            file: file,
            line: line
        )
    }

    private func driveSourceDefinedWrapperRetarget<Value>(
        harness: GenericAnimatableAttributeHarness<Value>,
        oldAnimation: Animation,
        replacementAnimation: Animation,
        oldValue: Value,
        replacementValue: Value
    ) where Value: Animatable {
        harness.setSource(
            oldValue,
            transaction: trackedVelocityTransaction(animation: oldAnimation)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.setTime(0.25)
        _ = harness.currentValue()
        harness.setTime(0.35)
        _ = harness.currentValue()

        harness.setSource(
            replacementValue,
            transaction: trackedVelocityTransaction(animation: replacementAnimation)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.setTime(0.55)
        _ = harness.currentValue()
        harness.setTime(0.65)
        _ = harness.currentValue()
    }

    private func driveSourceDefinedWrapperRetarget(
        harness: AnimatableAttributeHarness,
        oldAnimation: Animation,
        replacementAnimation: Animation,
        oldValue: _OpacityEffect,
        replacementValue: _OpacityEffect
    ) {
        harness.setSource(
            oldValue,
            transaction: trackedVelocityTransaction(animation: oldAnimation)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.setTime(0.25)
        _ = harness.currentValue()
        harness.setTime(0.35)
        _ = harness.currentValue()

        harness.setSource(
            replacementValue,
            transaction: trackedVelocityTransaction(animation: replacementAnimation)
        )
        harness.finalizeTransactionBody()
        _ = harness.currentValue()
        harness.setTime(0.55)
        _ = harness.currentValue()
        harness.setTime(0.65)
        _ = harness.currentValue()
    }

    private func trackedVelocityTransaction(animation: Animation) -> Transaction {
        var transaction = Transaction(animation: animation)
        transaction.isContinuous = true
        transaction.tracksVelocity = true
        return transaction
    }

    private func assertNoVelocityAndAnimationSampling(
        oldEvents: [String],
        replacementEvents: [String],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let allEvents = oldEvents + replacementEvents
        XCTAssertFalse(
            allEvents.contains { $0.hasPrefix("velocity:") },
            "\(label): \(allEvents)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            replacementEvents.contains("animate:replacement"),
            "\(label): \(replacementEvents)",
            file: file,
            line: line
        )
    }

    private func directSpringAnimations() -> [(String, Animation)] {
        [
            (
                "mass",
                .interpolatingSpring(
                    mass: 1.2,
                    stiffness: 90.0,
                    damping: 12.0,
                    initialVelocity: 0.3
                )
            ),
            (
                "springValue",
                .interpolatingSpring(
                    Spring(mass: 1.2, stiffness: 90.0, damping: 12.0),
                    initialVelocity: 0.3
                )
            ),
            (
                "durationBounce",
                .interpolatingSpring(duration: 0.4, bounce: 0.2, initialVelocity: 0.1)
            ),
            ("defaultProperty", .interpolatingSpring),
        ]
    }

    private func directFiniteAnimations() -> [(String, Animation)] {
        [
            ("linear", .linear(duration: 0.4)),
            ("p1p2", .timingCurve(0.18, 0.07, 0.82, 0.96, duration: 0.4)),
            (
                "cubicUnitCurve",
                .timingCurve(
                    .bezier(
                        startControlPoint: UnitPoint(x: 0.18, y: 0.07),
                        endControlPoint: UnitPoint(x: 0.82, y: 0.96)
                    ),
                    duration: 0.4
                )
            ),
            ("circularEaseIn", .timingCurve(.circularEaseIn, duration: 0.4)),
            ("circularEaseOut", .timingCurve(.circularEaseOut, duration: 0.4)),
            ("circularEaseInOut", .timingCurve(.circularEaseInOut, duration: 0.4)),
            ("easeInOut", .easeInOut(duration: 0.4)),
            ("easeIn", .easeIn(duration: 0.4)),
            ("easeOut", .easeOut(duration: 0.4)),
        ]
    }

    private func eventsWhenMerging<Value>(
        replacement: Animation,
        previous: Animation,
        value: Value,
        time: TimeInterval = 0.25
    ) -> [String] where Value: VectorArithmetic {
        let recorder = (previous.base as? RecordingVelocityAnimation)?.recorder
        var context = AnimationContext<Value>()
        _ = replacement.shouldMerge(
            previous: previous,
            value: value,
            time: time,
            context: &context
        )
        return recorder?.events ?? []
    }
}

private struct VelocityPairPayload: Animatable {
    var x: Double
    var y: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(x, y) }
        set {
            x = newValue.first
            y = newValue.second
        }
    }
}

private struct DetailedVelocityEvent: Equatable {
    var kind: String
    var value: Double
    var time: TimeInterval
    var frame: Int
    var logical: Bool
}

private final class DetailedVelocityRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DetailedVelocityEvent] = []

    var events: [DetailedVelocityEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ event: DetailedVelocityEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}

private struct DetailedVelocityFrameKey: AnimationStateKey {
    static let defaultValue = 0
}

private struct DetailedVelocityAnimation: CustomAnimation {
    var recorder: DetailedVelocityRecorder
    var outputScale: Double
    var velocityScale: Double

    static func == (lhs: DetailedVelocityAnimation, rhs: DetailedVelocityAnimation) -> Bool {
        lhs.recorder === rhs.recorder &&
            lhs.outputScale == rhs.outputScale &&
            lhs.velocityScale == rhs.velocityScale
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(recorder))
        hasher.combine(outputScale)
        hasher.combine(velocityScale)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        record(kind: "animate", value: value, time: time, context: context)
        context.state[DetailedVelocityFrameKey.self] += 1
        var output = value
        output.scale(by: outputScale)
        return output
    }

    nonisolated func velocity<Value>(
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        record(kind: "velocity", value: value, time: time, context: context)
        var output = value
        output.scale(by: velocityScale)
        return output
    }

    private func record<Value>(
        kind: String,
        value: Value,
        time: TimeInterval,
        context: AnimationContext<Value>
    ) where Value: VectorArithmetic {
        guard let doubleValue = value as? Double else {
            return
        }
        recorder.record(
            DetailedVelocityEvent(
                kind: kind,
                value: doubleValue,
                time: time,
                frame: context.state[DetailedVelocityFrameKey.self],
                logical: context.isLogicallyComplete
            )
        )
    }
}
