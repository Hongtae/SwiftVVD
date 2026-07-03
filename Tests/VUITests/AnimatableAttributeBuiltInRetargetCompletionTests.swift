import XCTest
@testable import VUI

final class AnimatableAttributeBuiltInRetargetCompletionTests: XCTestCase {
    func testRepeatedLinearRetargetKeepsLogicalDeadlinesSeparate() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 1.0),
                label: "first",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.25)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 0.8),
                label: "second",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(0.50)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 0.6),
                label: "third",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.02)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["first logical"])

        harness.setTime(1.08)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "first logical",
                "second logical",
            ]
        )

        harness.setTime(1.14)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "first logical",
                "second logical",
                "third logical",
            ]
        )
    }

    func testFiniteRetargetCanDrainNewerLogicalBeforeOlderLogicalAfterActiveRetarget() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 2.4),
                label: "old",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.65)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 0.7),
                label: "middle",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(1.05)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 8.0),
                label: "active",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.30)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.42)
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
        XCTAssertFalse(recorder.events.contains("active logical"))
    }

    func testResidualRetargetCanDrainNewerLogicalBeforeOlderLogicalAfterActiveRetarget() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .spring(
                    response: 2.40,
                    dampingFraction: 0.70,
                    blendDuration: 0.0
                ),
                label: "old",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.65)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 2),
            transaction: logicalCompletionTransaction(
                animation: .spring(
                    response: 0.70,
                    dampingFraction: 0.70,
                    blendDuration: 0.0
                ),
                label: "middle",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(1.05)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 3),
            transaction: logicalCompletionTransaction(
                animation: .spring(
                    response: 8.00,
                    dampingFraction: 0.70,
                    blendDuration: 0.0
                ),
                label: "active",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.30)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(1.42)
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
        XCTAssertFalse(recorder.events.contains("active logical"))
    }

    func testNoAnimationRetargetPreservesOldLogicalDeadline() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 1.0),
                label: "first",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.25)
        _ = harness.currentValue()
        let nilTransaction = logicalCompletionTransaction(
            animation: nil,
            label: "nil",
            recorder: recorder
        )
        withTransaction(nilTransaction) {
            harness.setSourceUsingCurrentTransaction(_OpacityEffect(opacity: -0.5))
        }
        let nilRetargetValue = harness.currentValue().opacity
        harness.finalizeTransactionBody()
        XCTAssertGreaterThanOrEqual(nilRetargetValue, -1.500_001)
        XCTAssertLessThan(nilRetargetValue, -0.5)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["nil logical"])

        harness.setTime(0.50)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: 0.75),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 0.6),
                label: "third",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(1.02)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["nil logical", "first logical"])

        harness.setTime(1.14)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "nil logical",
                "first logical",
                "third logical",
            ]
        )
    }

    func testLinearToFluidSpringSeparatesReplacementLogicalFromOldFinalization() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 1.0),
                label: "first",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.25)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: .spring(
                    response: 0.30,
                    dampingFraction: 0.70,
                    blendDuration: 0.0
                ),
                label: "spring",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(0.62)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["spring logical"])

        harness.setTime(0.82)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "spring logical",
                "first logical",
            ]
        )
    }

    func testLinearToFluidSpringOldDeadlineUsesTargetDeltaMagnitude() {
        let replacementAnimation = Animation.spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
        let retargetTime = 0.25
        let staticUnitBoundary = retargetTime +
            replacementAnimation.box.presentationDuration(for: Double(1.0))
        let smallBoundary = assertScalarLinearToFluidSpringRetarget(
            replacementAnimation: replacementAnimation,
            retargetTime: retargetTime,
            target: 0.10,
            earlySampleTime: nil,
            oldLabel: "smallOld",
            replacementLabel: "smallSpring"
        )
        XCTAssertLessThan(staticUnitBoundary + 0.03, 1.0)

        let largeBoundary = assertScalarLinearToFluidSpringRetarget(
            replacementAnimation: replacementAnimation,
            retargetTime: retargetTime,
            target: 8.25,
            earlySampleTime: (staticUnitBoundary + 1.0) / 2,
            oldLabel: "largeOld",
            replacementLabel: "largeSpring"
        )
        XCTAssertLessThan(smallBoundary + 0.10, largeBoundary)
    }

    func testLinearToFluidSpringOldDeadlineUsesVectorTargetDelta() {
        let replacementAnimation = Animation.spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
        let retargetTime = 0.25
        let smallScalarBoundary = assertScalarLinearToFluidSpringRetarget(
            replacementAnimation: replacementAnimation,
            retargetTime: retargetTime,
            target: 0.10,
            earlySampleTime: nil,
            oldLabel: "smallOld",
            replacementLabel: "smallSpring"
        )
        let smallScalarDuration = replacementAnimation.box.presentationDuration(
            for: Double(0.15)
        )

        let recorder = AnimationCompletionRecorder()
        let harness = GenericAnimatableAttributeHarness<PairAnimatablePayload>(
            initialValue: PairAnimatablePayload(x: 0, y: 0)
        )
        XCTAssertEqual(harness.currentValue(), PairAnimatablePayload(x: 0, y: 0))

        harness.setSource(
            PairAnimatablePayload(x: 1.0, y: 0.0),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 1.0),
                label: "old",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue(), PairAnimatablePayload(x: 0, y: 0))
        harness.finalizeTransactionBody()

        harness.setTime(retargetTime)
        let retargetStart = harness.currentValue()
        XCTAssertEqual(retargetStart.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(retargetStart.y, 0, accuracy: 0.000_001)

        let target = PairAnimatablePayload(x: 1.25, y: 1.0)
        harness.setSource(
            target,
            transaction: logicalCompletionTransaction(
                animation: replacementAnimation,
                label: "spring",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        var interval = target.animatableData
        interval -= retargetStart.animatableData
        let pairPresentationDuration = replacementAnimation.box.presentationDuration(for: interval)
        XCTAssertGreaterThan(pairPresentationDuration, smallScalarDuration + 0.02)

        let earlySampleTime = retargetTime +
            (smallScalarDuration + pairPresentationDuration) / 2
        harness.setTime(earlySampleTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["spring logical"])

        let oldBoundary = sampleUntilEvent(
            label: "old logical",
            recorder: recorder,
            startTime: earlySampleTime + replacementAnimation.box.defaultDisplayFrameInterval,
            endTime: retargetTime + 2.0,
            interval: replacementAnimation.box.defaultDisplayFrameInterval
        ) { time in
            harness.setTime(time)
            _ = harness.currentValue()
            harness.flushCompletionActions()
        }
        XCTAssertLessThan(smallScalarBoundary + 0.02, oldBoundary)
    }

    func testFluidSpringToLinearGroupsOldSpringWithReplacementBoundary() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: logicalCompletionTransaction(
                animation: .spring(
                    response: 0.80,
                    dampingFraction: 0.70,
                    blendDuration: 0.0
                ),
                label: "spring",
                recorder: recorder
            )
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.finalizeTransactionBody()

        harness.setTime(0.25)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 0.5),
                label: "linear",
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()

        harness.setTime(0.70)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [])

        harness.setTime(0.82)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "linear logical",
                "spring logical",
            ]
        )
    }

    private func logicalCompletionTransaction(
        animation: Animation?,
        label: String,
        recorder: AnimationCompletionRecorder
    ) -> Transaction {
        var transaction = Transaction(animation: animation)
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            recorder.record("\(label) logical")
        }
        return transaction
    }

    @discardableResult
    private func assertScalarLinearToFluidSpringRetarget(
        replacementAnimation: Animation,
        retargetTime: Double,
        target: Double,
        earlySampleTime: Double?,
        oldLabel: String,
        replacementLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Double {
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
            transaction: logicalCompletionTransaction(
                animation: .linear(duration: 1.0),
                label: oldLabel,
                recorder: recorder
            )
        )
        XCTAssertEqual(
            harness.currentValue().opacity,
            0,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        harness.finalizeTransactionBody()

        harness.setTime(retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertEqual(
            retargetStart,
            0,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        harness.setSource(
            _OpacityEffect(opacity: target),
            transaction: logicalCompletionTransaction(
                animation: replacementAnimation,
                label: replacementLabel,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        if let earlySampleTime {
            harness.setTime(earlySampleTime)
            _ = harness.currentValue()
            harness.flushCompletionActions()
            XCTAssertEqual(recorder.events, ["\(replacementLabel) logical"], file: file, line: line)
        }

        let oldBoundary = sampleUntilEvent(
            label: "\(oldLabel) logical",
            recorder: recorder,
            startTime: (earlySampleTime ?? (retargetTime + replacementAnimation.box.duration)) +
                replacementAnimation.box.defaultDisplayFrameInterval,
            endTime: retargetTime + 2.0,
            interval: replacementAnimation.box.defaultDisplayFrameInterval
        ) { time in
            harness.setTime(time)
            _ = harness.currentValue()
            harness.flushCompletionActions()
        }
        XCTAssertEqual(
            recorder.events,
            [
                "\(replacementLabel) logical",
                "\(oldLabel) logical",
            ],
            file: file,
            line: line
        )
        return oldBoundary
    }

    private func sampleUntilEvent(
        label: String,
        recorder: AnimationCompletionRecorder,
        startTime: Double,
        endTime: Double,
        interval: Double,
        sample: (Double) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Double {
        var time = startTime
        while time <= endTime {
            sample(time)
            if recorder.events.contains(label) {
                return time
            }
            time += interval
        }
        XCTFail("Missing event \(label)", file: file, line: line)
        return endTime
    }
}

private struct PairAnimatablePayload: Animatable, Equatable {
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
