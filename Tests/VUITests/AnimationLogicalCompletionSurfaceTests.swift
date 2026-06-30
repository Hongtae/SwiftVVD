import XCTest
@testable import VUI

final class AnimationLogicalCompletionSurfaceTests: XCTestCase {
    func testLogicalCompletionWrapperPreservesBaseFunctionAndTiming() {
        let base = Animation.timingCurve(0.2, 0.1, 0.8, 0.9, duration: 1.0)
        let split = base.logicallyComplete(after: 0.25)

        XCTAssertEqual(split.box.duration, base.box.duration)
        XCTAssertEqual(split.box.presentationDuration, base.box.presentationDuration)
        XCTAssertEqual(split.box.noRegisteredCompletionDelay(), base.box.noRegisteredCompletionDelay())
        XCTAssertEqual(
            split.box.noRegisteredCompletionDelay(for: .removed),
            base.box.noRegisteredCompletionDelay(for: .removed)
        )
        XCTAssertEqual(
            split.box.registeredCompletionDelay(for: .removed),
            base.box.registeredCompletionDelay(for: .removed)
        )
        XCTAssertAnimationFunctionEquivalent(split.function, base.function)
    }

    func testLogicalCompletionWrapperOwnsOnlyLogicalDeadline() {
        let base = Animation.linear(duration: 1.0)
        let split = base.logicallyComplete(after: 0.25)
        let immediateLogical = base.logicallyComplete(after: -0.25)

        XCTAssertEqual(split.box.noRegisteredCompletionDelay(for: .logicallyComplete), 0.25)
        XCTAssertEqual(split.box.registeredCompletionDelay(for: .logicallyComplete), 0.25)
        XCTAssertEqual(immediateLogical.box.noRegisteredCompletionDelay(for: .logicallyComplete), 0)
        XCTAssertEqual(immediateLogical.box.registeredCompletionDelay(for: .logicallyComplete), 0)
        XCTAssertEqual(
            split.box.noRegisteredCompletionDelay(for: .removed),
            base.box.noRegisteredCompletionDelay(for: .removed)
        )
        XCTAssertEqual(
            split.box.registeredCompletionDelay(for: .removed),
            base.box.registeredCompletionDelay(for: .removed)
        )
    }

    func testLogicalCompletionEqualityHashAndNestedStorage() throws {
        let earlyA = Animation.linear(duration: 1.0).logicallyComplete(after: 0.25)
        let earlyB = Animation.linear(duration: 1.0).logicallyComplete(after: 0.25)
        let late = Animation.linear(duration: 1.0).logicallyComplete(after: 0.75)
        let nested = earlyA.logicallyComplete(after: 0.5)

        XCTAssertEqual(earlyA, earlyB)
        XCTAssertEqual(earlyA.hashValue, earlyB.hashValue)
        XCTAssertNotEqual(earlyA, late)
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
