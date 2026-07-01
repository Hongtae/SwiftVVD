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
}
