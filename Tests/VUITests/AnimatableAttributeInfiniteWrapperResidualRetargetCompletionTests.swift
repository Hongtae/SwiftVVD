import XCTest
@testable import VUI

final class AnimatableAttributeInfiniteWrapperResidualRetargetCompletionTests: XCTestCase {
    func testRepeatForeverOldRecordsWaitForFluidSpringFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            oldLabel: "repeatForever",
            replacementAnimation: .spring(
                response: 0.35,
                dampingFraction: 0.70,
                blendDuration: 0
            ),
            replacementLabel: "fluid"
        )
    }

    func testRepeatForeverOldRecordsWaitForDirectSpringFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            oldLabel: "repeatForever",
            replacementAnimation: .interpolatingSpring(
                mass: 1.0,
                stiffness: 100.0,
                damping: 10.0,
                initialVelocity: 0.0
            ),
            replacementLabel: "spring"
        )
    }

    func testRepeatForeverOldRecordsWaitForDefaultFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            oldLabel: "repeatForever",
            replacementAnimation: .default,
            replacementLabel: "default"
        )
    }

    func testRepeatForeverOldRecordsWaitForSnappyAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            oldLabel: "repeatForever",
            replacementAnimation: Self.snappyAlias,
            replacementLabel: "snappy"
        )
    }

    func testRepeatForeverOldRecordsWaitForSpringPropertyAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            oldLabel: "repeatForever",
            replacementAnimation: Self.springPropertyAlias,
            replacementLabel: "springProperty"
        )
    }

    func testRepeatForeverOldRecordsWaitForSpringNoArgumentAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            oldLabel: "repeatForever",
            replacementAnimation: Self.springNoArgumentAlias,
            replacementLabel: "springNoArg"
        )
    }

    func testRepeatForeverOldRecordsWaitForSpringDurationAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnapBySamplingFrames(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            oldLabel: "repeatForever",
            replacementAnimation: Self.springDurationAlias,
            replacementLabel: "springDuration"
        )
    }

    func testRepeatForeverOldRecordsWaitForSpringValueAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnapBySamplingFrames(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            oldLabel: "repeatForever",
            replacementAnimation: Self.springValueAlias,
            replacementLabel: "springValue"
        )
    }

    func testRepeatForeverOldRecordsWaitForInteractiveSpringPropertyAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            oldLabel: "repeatForever",
            replacementAnimation: Self.interactiveSpringPropertyAlias,
            replacementLabel: "interactiveSpringProperty"
        )
    }

    func testRepeatForeverOldRecordsWaitForInteractiveSpringNoArgumentAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.20)
                .repeatForever(autoreverses: false),
            oldLabel: "repeatForever",
            replacementAnimation: Self.interactiveSpringNoArgumentAlias,
            replacementLabel: "interactiveSpringNoArg"
        )
    }

    func testSpeedZeroOldRecordsWaitForFluidSpringFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "speedZero",
            replacementAnimation: .spring(
                response: 0.35,
                dampingFraction: 0.70,
                blendDuration: 0
            ),
            replacementLabel: "fluid"
        )
    }

    func testSpeedZeroOldRecordsWaitForDirectSpringFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "speedZero",
            replacementAnimation: .interpolatingSpring(
                mass: 1.0,
                stiffness: 100.0,
                damping: 10.0,
                initialVelocity: 0.0
            ),
            replacementLabel: "spring"
        )
    }

    func testSpeedZeroOldRecordsWaitForDefaultFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "speedZero",
            replacementAnimation: .default,
            replacementLabel: "default"
        )
    }

    func testSpeedZeroOldRecordsWaitForSnappyAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "speedZero",
            replacementAnimation: Self.snappyAlias,
            replacementLabel: "snappy"
        )
    }

    func testSpeedZeroOldRecordsWaitForSpringPropertyAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "speedZero",
            replacementAnimation: Self.springPropertyAlias,
            replacementLabel: "springProperty"
        )
    }

    func testSpeedZeroOldRecordsWaitForSpringNoArgumentAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "speedZero",
            replacementAnimation: Self.springNoArgumentAlias,
            replacementLabel: "springNoArg"
        )
    }

    func testSpeedZeroOldRecordsGroupWithSpringDurationAliasFinalSnap() {
        assertInfiniteOldRecordsGroupAtResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "speedZero",
            replacementAnimation: Self.springDurationAlias,
            replacementLabel: "springDuration"
        )
    }

    func testSpeedZeroOldRecordsGroupWithSpringValueAliasFinalSnap() {
        assertInfiniteOldRecordsGroupAtResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "speedZero",
            replacementAnimation: Self.springValueAlias,
            replacementLabel: "springValue"
        )
    }

    func testSpeedZeroOldRecordsWaitForInteractiveSpringPropertyAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "speedZero",
            replacementAnimation: Self.interactiveSpringPropertyAlias,
            replacementLabel: "interactiveSpringProperty"
        )
    }

    func testSpeedZeroOldRecordsWaitForInteractiveSpringNoArgumentAliasFinalSnap() {
        assertInfiniteOldRecordsMoveToResidualFinalSnap(
            oldAnimation: Animation.linear(duration: 0.40).speed(0),
            oldLabel: "speedZero",
            replacementAnimation: Self.interactiveSpringNoArgumentAlias,
            replacementLabel: "interactiveSpringNoArg"
        )
    }

    private func assertInfiniteOldRecordsMoveToResidualFinalSnap(
        oldAnimation: Animation,
        oldLabel: String,
        replacementAnimation: Animation,
        replacementLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: oldLabel,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        let replacementStart = 0.45
        harness.setTime(replacementStart)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: replacementAnimation,
                label: replacementLabel,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        let logicalBoundary = replacementStart + replacementAnimation.box.duration +
            replacementAnimation.box.defaultDisplayFrameInterval
        harness.setTime(logicalBoundary)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["\(replacementLabel) logical"], file: file, line: line)

        var finalValue: Double?
        var sampleTime = logicalBoundary + replacementAnimation.box.defaultDisplayFrameInterval
        let finalSampleTime = replacementStart + max(
            replacementAnimation.box.presentationDuration(for: Double(2.0)),
            replacementAnimation.box.presentationDuration
        ) + 2.0
        while sampleTime <= finalSampleTime {
            harness.setTime(sampleTime)
            let value = harness.currentValue().opacity
            harness.flushCompletionActions()
            if recorder.events.count == 4 {
                finalValue = value
                break
            }
            XCTAssertEqual(recorder.events, ["\(replacementLabel) logical"], file: file, line: line)
            sampleTime += replacementAnimation.box.defaultDisplayFrameInterval
        }

        guard let snappedValue = finalValue else {
            XCTFail("\(oldLabel) -> \(replacementLabel) did not finish residual finalization", file: file, line: line)
            return
        }
        XCTAssertEqual(snappedValue, -0.5, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(
            recorder.events,
            [
                "\(replacementLabel) logical",
                "\(oldLabel) removed",
                "\(replacementLabel) removed",
                "\(oldLabel) logical",
            ],
            file: file,
            line: line
        )
    }

    private func assertInfiniteOldRecordsMoveToResidualFinalSnapBySamplingFrames(
        oldAnimation: Animation,
        oldLabel: String,
        replacementAnimation: Animation,
        replacementLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: oldLabel,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        let replacementStart = 0.45
        harness.setTime(replacementStart)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: replacementAnimation,
                label: replacementLabel,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        var finalValue: Double?
        var sampleTime = replacementStart + replacementAnimation.box.defaultDisplayFrameInterval
        let finalSampleTime = replacementStart + max(
            replacementAnimation.box.presentationDuration(for: Double(2.0)),
            replacementAnimation.box.presentationDuration
        ) + 2.0
        while sampleTime <= finalSampleTime {
            harness.setTime(sampleTime)
            let value = harness.currentValue().opacity
            harness.flushCompletionActions()
            if recorder.events.count == 4 {
                finalValue = value
                break
            }
            if recorder.events.isEmpty {
                sampleTime += replacementAnimation.box.defaultDisplayFrameInterval
                continue
            }
            XCTAssertEqual(recorder.events, ["\(replacementLabel) logical"], file: file, line: line)
            sampleTime += replacementAnimation.box.defaultDisplayFrameInterval
        }

        guard let snappedValue = finalValue else {
            XCTFail("\(oldLabel) -> \(replacementLabel) did not finish residual finalization", file: file, line: line)
            return
        }
        XCTAssertEqual(snappedValue, -0.5, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(
            recorder.events,
            [
                "\(replacementLabel) logical",
                "\(oldLabel) removed",
                "\(replacementLabel) removed",
                "\(oldLabel) logical",
            ],
            file: file,
            line: line
        )
    }

    private func assertInfiniteOldRecordsGroupAtResidualFinalSnap(
        oldAnimation: Animation,
        oldLabel: String,
        replacementAnimation: Animation,
        replacementLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: completionTransaction(
                animation: oldAnimation,
                label: oldLabel,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        let replacementStart = 0.45
        harness.setTime(replacementStart)
        _ = harness.currentValue()
        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: completionTransaction(
                animation: replacementAnimation,
                label: replacementLabel,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        var finalValue: Double?
        var sampleTime = replacementStart + replacementAnimation.box.defaultDisplayFrameInterval
        let finalSampleTime = replacementStart + max(
            replacementAnimation.box.presentationDuration(for: Double(2.0)),
            replacementAnimation.box.presentationDuration
        ) + 2.0
        while sampleTime <= finalSampleTime {
            harness.setTime(sampleTime)
            let value = harness.currentValue().opacity
            harness.flushCompletionActions()
            if recorder.events.count == 4 {
                finalValue = value
                break
            }
            XCTAssertEqual(recorder.events, [], file: file, line: line)
            sampleTime += replacementAnimation.box.defaultDisplayFrameInterval
        }

        guard let snappedValue = finalValue else {
            XCTFail("\(oldLabel) -> \(replacementLabel) did not finish same-boundary residual finalization", file: file, line: line)
            return
        }
        XCTAssertEqual(snappedValue, -0.5, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(
            recorder.events,
            [
                "\(oldLabel) removed",
                "\(replacementLabel) removed",
                "\(replacementLabel) logical",
                "\(oldLabel) logical",
            ],
            file: file,
            line: line
        )
    }

    private static var snappyAlias: Animation {
        .snappy(duration: 0.35, extraBounce: 0.0)
    }

    private static var springPropertyAlias: Animation {
        .spring
    }

    private static var springNoArgumentAlias: Animation {
        .spring()
    }

    private static var springDurationAlias: Animation {
        .spring(duration: 0.50, bounce: 0.20, blendDuration: 0.0)
    }

    private static var springValueAlias: Animation {
        .spring(Spring(duration: 0.50, bounce: 0.20), blendDuration: 0.0)
    }

    private static var interactiveSpringPropertyAlias: Animation {
        .interactiveSpring
    }

    private static var interactiveSpringNoArgumentAlias: Animation {
        .interactiveSpring()
    }
}
