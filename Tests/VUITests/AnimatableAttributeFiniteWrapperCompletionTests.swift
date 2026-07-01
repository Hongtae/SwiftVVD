import XCTest
@testable import VUI

final class AnimatableAttributeFiniteWrapperCompletionTests: XCTestCase {
    func testFiniteWrappersDrainRemovedBeforeLogicalAtOneBoundary() {
        assertFiniteWrapperCompletionBoundary(
            animation: Animation.linear(duration: 0.30).delay(0.20),
            label: "positive delay",
            preBoundaryTime: 0.35,
            boundaryTime: 0.70
        )
        assertFiniteWrapperCompletionBoundary(
            animation: Animation.linear(duration: 0.30).delay(-0.10),
            label: "negative delay",
            preBoundaryTime: 0.08,
            boundaryTime: 0.45
        )
        assertFiniteWrapperCompletionBoundary(
            animation: Animation.linear(duration: 0.30).speed(2),
            label: "positive speed",
            preBoundaryTime: 0.05,
            boundaryTime: 0.35
        )
        assertFiniteWrapperCompletionBoundary(
            animation: Animation.linear(duration: 0.20).repeatCount(2, autoreverses: false),
            label: "finite repeat",
            preBoundaryTime: 0.25,
            boundaryTime: 0.60
        )
        assertFiniteWrapperCompletionBoundary(
            animation: Animation.linear(duration: 0.30).repeatCount(0, autoreverses: false),
            label: "zero repeat",
            preBoundaryTime: 0.10,
            boundaryTime: 0.45
        )
        assertFiniteWrapperCompletionBoundary(
            animation: Animation.linear(duration: 0.30).repeatCount(-2, autoreverses: true),
            label: "negative repeat",
            preBoundaryTime: 0.10,
            boundaryTime: 0.45
        )
    }

    private func assertFiniteWrapperCompletionBoundary(
        animation: Animation,
        label: String,
        preBoundaryTime: Double,
        boundaryTime: Double,
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
                animation: animation,
                label: label,
                recorder: recorder
            )
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(preBoundaryTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, [], file: file, line: line)

        harness.setTime(boundaryTime)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "\(label) removed",
                "\(label) logical",
            ],
            file: file,
            line: line
        )

        harness.setTime(boundaryTime + 0.50)
        _ = harness.currentValue()
        harness.flushCompletionActions()
        XCTAssertEqual(
            recorder.events,
            [
                "\(label) removed",
                "\(label) logical",
            ],
            file: file,
            line: line
        )
    }
}
