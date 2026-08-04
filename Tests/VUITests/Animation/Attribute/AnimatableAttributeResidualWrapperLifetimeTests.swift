import XCTest
@testable import VUI

final class AnimatableAttributeResidualWrapperLifetimeTests: XCTestCase {
    func testDelayAndPositiveSpeedWrappersOverResidualSpringsSplitCriteria() {
        assertResidualWrapperCompletionSplit(
            animation: Self.fluidSpring.delay(0.20),
            label: "fluid delay"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.fluidSpring.speed(4.0),
            label: "fluid speed"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.directSpring.delay(0.20),
            label: "spring delay"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.directSpring.speed(4.0),
            label: "spring speed"
        )
    }

    func testNegativeDelayWrappersOverResidualSpringsClampLogicalBeforeRemoved() {
        assertResidualWrapperCompletionSplit(
            animation: Self.fluidSpring.delay(-0.50),
            label: "fluid negative delay"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.directSpring.delay(-1.00),
            label: "spring negative delay"
        )
    }

    func testFiniteRepeatWrappersOverResidualSpringsKeepLogicalBeforeRemoved() {
        assertResidualWrapperCompletionSplit(
            animation: Self.fluidSpring.repeatCount(2, autoreverses: false),
            label: "fluid repeat no autoreverse"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.fluidSpring.repeatCount(2, autoreverses: true),
            label: "fluid repeat autoreverse"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.directSpring.repeatCount(2, autoreverses: false),
            label: "spring repeat no autoreverse"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.directSpring.repeatCount(2, autoreverses: true),
            label: "spring repeat autoreverse"
        )
    }

    func testFiniteRepeatCountEdgesOverResidualSpringsKeepLogicalBeforeRemoved() {
        assertResidualWrapperCompletionSplit(
            animation: Self.fluidSpring.repeatCount(0, autoreverses: false),
            label: "fluid repeat zero"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.fluidSpring.repeatCount(3, autoreverses: false),
            label: "fluid repeat three no autoreverse"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.fluidSpring.repeatCount(3, autoreverses: true),
            label: "fluid repeat three autoreverse"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.fluidSpring.repeatCount(-2, autoreverses: true),
            label: "fluid negative repeat"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.directSpring.repeatCount(0, autoreverses: false),
            label: "spring repeat zero"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.directSpring.repeatCount(3, autoreverses: false),
            label: "spring repeat three"
        )
        assertResidualWrapperCompletionSplit(
            animation: Self.directSpring.repeatCount(-2, autoreverses: false),
            label: "spring negative repeat"
        )
    }

    func testNestedDelayRepeatWrappersOverResidualAnimationsPreserveWrapperOrder() {
        assertNestedDelayRepeatWrapperOrder(
            delayThenRepeat: Self.fluidSpring.delay(0.20).repeatCount(2, autoreverses: false),
            repeatThenDelay: Self.fluidSpring.repeatCount(2, autoreverses: false).delay(0.20),
            delay: 0.20,
            label: "fluid nested delay repeat"
        )
        assertNestedDelayRepeatWrapperOrder(
            delayThenRepeat: Self.directSpring.delay(0.20).repeatCount(2, autoreverses: false),
            repeatThenDelay: Self.directSpring.repeatCount(2, autoreverses: false).delay(0.20),
            delay: 0.20,
            label: "spring nested delay repeat"
        )
        assertNestedDelayRepeatWrapperOrder(
            delayThenRepeat: Animation.default.delay(0.20).repeatCount(2, autoreverses: false),
            repeatThenDelay: Animation.default.repeatCount(2, autoreverses: false).delay(0.20),
            delay: 0.20,
            label: "default nested delay repeat"
        )
    }

    func testDefaultWrappersKeepResidualLogicalBeforeRemoved() {
        assertResidualWrapperCompletionSplit(
            animation: Animation.default.delay(0.20),
            label: "default delay"
        )
        assertResidualWrapperCompletionSplit(
            animation: Animation.default.speed(2.0),
            label: "default speed"
        )
        assertResidualWrapperCompletionSplit(
            animation: Animation.default.repeatCount(2, autoreverses: false),
            label: "default repeat"
        )
    }

    private func assertNestedDelayRepeatWrapperOrder(
        delayThenRepeat: Animation,
        repeatThenDelay: Animation,
        delay: Double,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let delayThenRepeatLogical = delayThenRepeat.box.duration
        let repeatThenDelayLogical = repeatThenDelay.box.duration
        let delayThenRepeatPresentation = delayThenRepeat.box.terminalSamplingHorizon(for: Double(1))
        let repeatThenDelayPresentation = repeatThenDelay.box.terminalSamplingHorizon(for: Double(1))

        XCTAssertEqual(
            delayThenRepeatLogical - repeatThenDelayLogical,
            delay,
            accuracy: 0.000_001,
            "\(label) should repeat an inner delay but apply an outer delay once",
            file: file,
            line: line
        )
        XCTAssertEqual(
            delayThenRepeatPresentation - repeatThenDelayPresentation,
            delay,
            accuracy: delayThenRepeat.box.defaultDisplayFrameInterval,
            "\(label) should repeat an inner delay but apply an outer delay once",
            file: file,
            line: line
        )

        assertResidualWrapperCompletionSplit(
            animation: delayThenRepeat,
            label: "\(label) delay then repeat",
            file: file,
            line: line
        )
        assertResidualWrapperCompletionSplit(
            animation: repeatThenDelay,
            label: "\(label) repeat then delay",
            file: file,
            line: line
        )
    }

    private func assertResidualWrapperCompletionSplit(
        animation: Animation,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let logicalDuration = animation.box.duration
        let terminalSamplingHorizon = animation.box.terminalSamplingHorizon(for: Double(1))
        let frame = animation.box.defaultDisplayFrameInterval

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        XCTAssertGreaterThan(
            terminalSamplingHorizon,
            logicalDuration + frame,
            "\(label) should keep a separate residual presentation boundary",
            file: file,
            line: line
        )

        let logicalEvent = "\(label) logical"
        let removedEvent = "\(label) removed"

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: animation,
                label: label,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        let didFireImmediateLogical = recorder.events == [logicalEvent]
        if logicalDuration <= frame {
            XCTAssertEqual(recorder.events, [logicalEvent], file: file, line: line)
        }

        let logicalSampleTime: Double
        if didFireImmediateLogical {
            logicalSampleTime = 0
        } else {
            var observedLogicalTime: Double?
            var sampleTime = frame
            let logicalSearchEnd = terminalSamplingHorizon + 1.0
            while sampleTime <= logicalSearchEnd {
                harness.advanceTime(to: sampleTime)
                _ = harness.currentValue()
                harness.flushCompletionActions()
                if recorder.events == [logicalEvent] {
                    observedLogicalTime = sampleTime
                    break
                }
                if recorder.events.contains(removedEvent) {
                    break
                }
                sampleTime += frame
            }
            guard let observedLogicalTime else {
                XCTFail(
                    "\(label) did not expose a logical-only sample; " +
                        "duration=\(logicalDuration), presentation=\(terminalSamplingHorizon), " +
                        "frame=\(frame), events=\(recorder.events)",
                    file: file,
                    line: line
                )
                return
            }
            logicalSampleTime = observedLogicalTime
        }

        var removedBoundaryValue: Double?
        var sampleTime = logicalSampleTime + frame
        let lastSampleTime = terminalSamplingHorizon + 2.0
        while sampleTime <= lastSampleTime {
            harness.advanceTime(to: sampleTime)
            let value = harness.currentValue().opacity
            harness.flushCompletionActions()
            if recorder.events.contains(removedEvent) {
                removedBoundaryValue = value
                break
            }
            XCTAssertEqual(recorder.events, [logicalEvent], file: file, line: line)
            sampleTime += frame
        }

        guard let finalValue = removedBoundaryValue else {
            XCTFail("\(label) removed completion did not drain", file: file, line: line)
            return
        }
        XCTAssertEqual(finalValue, 1, accuracy: 0.015, file: file, line: line)
        XCTAssertEqual(
            recorder.events,
            [
                logicalEvent,
                removedEvent,
            ],
            file: file,
            line: line
        )
    }

    private static var fluidSpring: Animation {
        .spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
    }

    private static var directSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 100.0,
            damping: 10.0,
            initialVelocity: 0.0
        )
    }
}
