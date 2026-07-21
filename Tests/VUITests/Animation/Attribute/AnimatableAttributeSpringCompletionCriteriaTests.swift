import XCTest
@testable import VUI

final class AnimatableAttributeSpringCompletionCriteriaTests: XCTestCase {
    func testResidualCompletionCriteriaSplitLogicalFromRemovedFinalization() {
        assertResidualCompletionCriteriaSplit(
            animation: .default,
            label: "default"
        )
        assertResidualCompletionCriteriaSplit(
            animation: .spring(
                response: 0.35,
                dampingFraction: 0.70,
                blendDuration: 0
            ),
            label: "fluid spring"
        )
        assertResidualCompletionCriteriaSplit(
            animation: .interpolatingSpring(
                mass: 1.0,
                stiffness: 50.0,
                damping: 5.0,
                initialVelocity: 0.0
            ),
            label: "direct spring"
        )
    }

    private func assertResidualCompletionCriteriaSplit(
        animation: Animation,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, file: file, line: line)
        let logicalDuration = animation.box.duration
        let presentationDuration = animation.box.presentationDuration(
            for: Double(1)
        )
        XCTAssertGreaterThan(
            presentationDuration,
            logicalDuration,
            "\(label) should have a separate final presentation boundary",
            file: file,
            line: line
        )

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
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(logicalDuration / 2)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        let splitSampleTime = (logicalDuration + presentationDuration) / 2
        harness.setTime(splitSampleTime)
        let logicalBoundaryValue = harness.currentValue().opacity
        harness.flushCompletionActions()
        XCTAssertGreaterThan(logicalBoundaryValue, 0, file: file, line: line)
        XCTAssertLessThan(logicalBoundaryValue, 1, file: file, line: line)
        XCTAssertEqual(recorder.events, ["\(label) logical"], file: file, line: line)

        var removedBoundaryValue: Double?
        var sampleTime = splitSampleTime + animation.box.defaultDisplayFrameInterval
        let finalSampleTime = splitSampleTime + presentationDuration + 1.0
        while sampleTime <= finalSampleTime {
            harness.setTime(sampleTime)
            let value = harness.currentValue().opacity
            harness.flushCompletionActions()
            if recorder.events.contains("\(label) removed") {
                removedBoundaryValue = value
                break
            }
            XCTAssertEqual(recorder.events, ["\(label) logical"], file: file, line: line)
            sampleTime += animation.box.defaultDisplayFrameInterval
        }
        guard let finalValue = removedBoundaryValue else {
            XCTFail("\(label) removed completion did not drain", file: file, line: line)
            return
        }
        XCTAssertEqual(finalValue, 1, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(
            recorder.events,
            [
                "\(label) logical",
                "\(label) removed",
            ],
            file: file,
            line: line
        )
    }
}
