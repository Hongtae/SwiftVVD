import XCTest
@testable import VUI

final class DefaultCombiningAnimationTests: XCTestCase {
    func testCombineAnimationUsesReplacementNewValueAsAccumulatedTarget() throws {
        var animation = Animation(UnitLinearAnimation(duration: 1.0))
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(UnitLinearAnimation(duration: 1.0)),
            newValue: 5.0
        )

        var context = AnimationContext(state: state)
        let sample = try XCTUnwrap(
            animation.animate(value: 15.0, time: 0.75, context: &context)
        )

        XCTAssertEqual(sample, 11.25, accuracy: 0.000_001)
    }

    func testCompletedChildKeepsAccumulatedContribution() throws {
        var animation = Animation(UnitLinearAnimation(duration: 0.2))
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(UnitLinearAnimation(duration: 1.0)),
            newValue: 5.0
        )

        var context = AnimationContext(state: state)
        let sample = try XCTUnwrap(
            animation.animate(value: 15.0, time: 0.5, context: &context)
        )

        XCTAssertEqual(sample, 11.25, accuracy: 0.000_001)
    }

    func testLastChildNilTerminatesCombinedAnimation() {
        var animation = Animation(UnitLinearAnimation(duration: 0.2))
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(UnitLinearAnimation(duration: 1.0)),
            newValue: 5.0
        )

        var context = AnimationContext(state: state)

        XCTAssertNil(animation.animate(value: 15.0, time: 1.25, context: &context))
        XCTAssertTrue(context.isLogicallyComplete)
    }
}