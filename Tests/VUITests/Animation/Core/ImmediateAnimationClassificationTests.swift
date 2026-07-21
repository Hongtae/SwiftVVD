import XCTest
@testable import VUI

final class ImmediateAnimationClassificationTests: XCTestCase {
    private struct TrapOnAnimateCustomAnimation: CustomAnimation {
        func animate<Value>(
            value: Value,
            time: TimeInterval,
            context: inout AnimationContext<Value>
        ) -> Value? where Value: VectorArithmetic {
            XCTFail("source-defined retarget activation classification must not sample CustomAnimation.animate")
            return nil
        }
    }

    func testZeroAndNegativeDurationReplacementsCompleteImmediately() {
        let replacements: [Animation] = [
            .linear(duration: 0),
            .linear(duration: -0.2),
            .timingCurve(.circularEaseInOut, duration: -0.2),
            .interpolatingSpring(duration: 0, bounce: 0.15, initialVelocity: 0),
            .interpolatingSpring(duration: -0.2, bounce: 0.15, initialVelocity: 0),
        ]

        for replacement in replacements {
            XCTAssertTrue(replacement.box.isImmediatelyComplete)
            XCTAssertEqual(replacement.box.noRegisteredCompletionDelay(), 0)
            XCTAssertTrue(replacement.box.finishesRetargetCompletionAtActivation)

            var context = AnimationContext<Double>()
            XCTAssertNil(
                replacement.animate(value: 1.0, time: 0, context: &context)
            )
            XCTAssertTrue(context.isLogicallyComplete)
        }
    }

    func testNonPositiveSpeedRemainsInfiniteRatherThanImmediate() throws {
        let replacement = Animation.linear(duration: 0.4).speed(-1)

        XCTAssertFalse(replacement.box.isImmediatelyComplete)
        XCTAssertFalse(replacement.box.duration.isFinite)
        XCTAssertNil(replacement.box.noRegisteredCompletionDelay())
        XCTAssertFalse(replacement.box.finishesRetargetCompletionAtActivation)

        var context = AnimationContext<Double>()
        let sample = try XCTUnwrap(
            replacement.animate(value: 1.0, time: 0.2, context: &context)
        )
        XCTAssertEqual(sample, 0, accuracy: 0.000_001)
        XCTAssertFalse(context.isLogicallyComplete)
    }

    func testSourceDefinedCustomDoesNotUseRetargetActivationFastPath() {
        let replacement = Animation(TrapOnAnimateCustomAnimation())

        XCTAssertTrue(replacement.box.preservesRetargetedCompletionDeadlines)
        XCTAssertFalse(replacement.box.finishesRetargetCompletionAtActivation)
    }
}