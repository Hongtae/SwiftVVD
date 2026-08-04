import XCTest
@testable import VUI

final class AnimationLogicalCompletionSurfaceTests: XCTestCase {
    func testLogicalCompletionWrapperPreservesBaseFunctionAndTiming() {
        let base = Animation.timingCurve(0.2, 0.1, 0.8, 0.9, duration: 1.0)
        let split = base.logicallyComplete(after: 0.25)

        XCTAssertEqual(split.box.duration, base.box.duration)
        XCTAssertEqual(split.box.terminalSamplingHorizon, base.box.terminalSamplingHorizon)
        XCTAssertAnimationFunctionEquivalent(split.function, base.function)
    }

    func testLogicalCompletionWrapperUpdatesContextAtItsOwnBoundary() throws {
        let base = Animation.linear(duration: 1.0)
        let split = base.logicallyComplete(after: 0.25)
        var context = AnimationContext<Double>()

        _ = try XCTUnwrap(
            split.animate(value: 1, time: 0.20, context: &context)
        )
        XCTAssertFalse(context.isLogicallyComplete)

        _ = try XCTUnwrap(
            split.animate(value: 1, time: 0.30, context: &context)
        )
        XCTAssertTrue(context.isLogicallyComplete)
    }

    func testLongLogicalCompletionDrainsAtBaseTerminalBoundary() {
        let recorder = AnimationCompletionRecorder()
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        let transaction = completionTransaction(
            animation: Animation.linear(duration: 0.8).logicallyComplete(after: 1.2),
            label: "late",
            recorder: recorder
        )

        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: transaction
        )
        harness.finalizeTransactionBody()
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001)
        harness.setTime(0.4)
        _ = harness.currentValue()
        harness.setTime(0.5)
        let runningValue = harness.currentValue().opacity
        XCTAssertGreaterThan(runningValue, 0)
        XCTAssertLessThan(runningValue, 1)
        harness.setTime(1.3)

        XCTAssertEqual(harness.currentValue().opacity, 1, accuracy: 0.000_001)
        harness.flushCompletionActions()
        XCTAssertEqual(recorder.events, ["late removed", "late logical"])
    }

    func testLogicalCompletionEqualityHashAndNestedStorage() throws {
        let earlyA = Animation.linear(duration: 1.0).logicallyComplete(after: 0.25)
        let earlyB = Animation.linear(duration: 1.0).logicallyComplete(after: 0.25)
        let late = Animation.linear(duration: 1.0).logicallyComplete(after: 0.75)
        let zero = Animation.linear(duration: 1.0).logicallyComplete(after: 0)
        let negative = Animation.linear(duration: 1.0).logicallyComplete(after: -0.25)
        let nested = earlyA.logicallyComplete(after: 0.5)

        XCTAssertEqual(earlyA, earlyB)
        XCTAssertEqual(earlyA.hashValue, earlyB.hashValue)
        XCTAssertNotEqual(earlyA, late)
        XCTAssertNotEqual(zero, negative)
        XCTAssertNotEqual(earlyA, nested)

        let outer = try XCTUnwrap(nested.box as? LogicalCompletionAnimationBox)
        XCTAssertEqual(outer.logicalDuration, 0.5)
        let inner = try XCTUnwrap(outer.base as? LogicalCompletionAnimationBox)
        XCTAssertEqual(inner.logicalDuration, 0.25)
        XCTAssertTrue(inner.base is BezierAnimationBox)
    }
}

private func XCTAssertAnimationFunctionEquivalent(
    _ lhs: Animation.Function,
    _ rhs: Animation.Function,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch (lhs, rhs) {
    case let (.linear(lhsDuration), .linear(rhsDuration)):
        XCTAssertEqual(lhsDuration, rhsDuration, file: file, line: line)
    case let (.circularEaseIn(lhsDuration), .circularEaseIn(rhsDuration)):
        XCTAssertEqual(lhsDuration, rhsDuration, file: file, line: line)
    case let (.circularEaseOut(lhsDuration), .circularEaseOut(rhsDuration)):
        XCTAssertEqual(lhsDuration, rhsDuration, file: file, line: line)
    case let (.circularEaseInOut(lhsDuration), .circularEaseInOut(rhsDuration)):
        XCTAssertEqual(lhsDuration, rhsDuration, file: file, line: line)
    case let (.bezier(lhsDuration, lhsStart, lhsEnd), .bezier(rhsDuration, rhsStart, rhsEnd)):
        XCTAssertEqual(lhsDuration, rhsDuration, file: file, line: line)
        XCTAssertEqual(lhsStart, rhsStart, file: file, line: line)
        XCTAssertEqual(lhsEnd, rhsEnd, file: file, line: line)
    case let (.spring(lhsDuration, lhsBounce, lhsMass, lhsStiffness, lhsDamping),
              .spring(rhsDuration, rhsBounce, rhsMass, rhsStiffness, rhsDamping)):
        XCTAssertEqual(lhsDuration, rhsDuration, file: file, line: line)
        XCTAssertEqual(lhsBounce, rhsBounce, file: file, line: line)
        XCTAssertEqual(lhsMass, rhsMass, file: file, line: line)
        XCTAssertEqual(lhsStiffness, rhsStiffness, file: file, line: line)
        XCTAssertEqual(lhsDamping, rhsDamping, file: file, line: line)
    case let (.delay(lhsDelay, lhsBase), .delay(rhsDelay, rhsBase)):
        XCTAssertEqual(lhsDelay, rhsDelay, file: file, line: line)
        XCTAssertAnimationFunctionEquivalent(lhsBase, rhsBase, file: file, line: line)
    case let (.speed(lhsSpeed, lhsBase), .speed(rhsSpeed, rhsBase)):
        XCTAssertEqual(lhsSpeed, rhsSpeed, file: file, line: line)
        XCTAssertAnimationFunctionEquivalent(lhsBase, rhsBase, file: file, line: line)
    case let (.repeat(lhsCount, lhsAutoreverses, lhsBase), .repeat(rhsCount, rhsAutoreverses, rhsBase)):
        XCTAssertEqual(lhsCount, rhsCount, file: file, line: line)
        XCTAssertEqual(lhsAutoreverses, rhsAutoreverses, file: file, line: line)
        XCTAssertAnimationFunctionEquivalent(lhsBase, rhsBase, file: file, line: line)
    default:
        XCTFail("Animation functions differ: \(lhs) vs \(rhs)", file: file, line: line)
    }
}
