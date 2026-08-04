import XCTest
@testable import VUI

final class AnimationFluidSpringRetargetBlendTests: XCTestCase {
    func testFluidSpringMergeRecordsPreviousResponseDeltaForBlend() {
        var context = AnimationContext<Double>()
        let previous = Animation.spring(
            response: 0.30,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
        let replacement = Animation.spring(
            response: 0.80,
            dampingFraction: 0.70,
            blendDuration: 0.30
        )

        XCTAssertTrue(
            replacement.shouldMerge(
                previous: previous,
                value: 1.0,
                time: 0.12,
                context: &context
            )
        )

        let state = context.state[SpringState<Double>.self]
        XCTAssertEqual(state.blendStart, 0.12, accuracy: 0.000_001)
        XCTAssertEqual(state.blendInterval, -0.50, accuracy: 0.000_001)
        XCTAssertEqual(
            effectiveResponse(response: 0.80, blendDuration: 0.30, time: 0.12, state: state),
            0.30,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            effectiveResponse(response: 0.80, blendDuration: 0.30, time: 0.27, state: state),
            0.55,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            effectiveResponse(response: 0.80, blendDuration: 0.30, time: 0.42, state: state),
            0.80,
            accuracy: 0.000_001
        )
    }

    func testSameResponseFluidSpringMergeDoesNotCreateResponseBlend() {
        var context = AnimationContext<Double>()
        let previous = Animation.spring(
            response: 0.30,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
        let replacement = Animation.spring(
            response: 0.30,
            dampingFraction: 0.70,
            blendDuration: 0.30
        )

        XCTAssertTrue(
            replacement.shouldMerge(
                previous: previous,
                value: 1.0,
                time: 0.12,
                context: &context
            )
        )

        let state = context.state[SpringState<Double>.self]
        XCTAssertEqual(state.blendStart, 0, accuracy: 0.000_001)
        XCTAssertEqual(state.blendInterval, 0, accuracy: 0.000_001)
        XCTAssertEqual(
            effectiveResponse(response: 0.30, blendDuration: 0.30, time: 0.27, state: state),
            0.30,
            accuracy: 0.000_001
        )
    }

    func testReverseFluidSpringResponseBlendStartsFromPreviousSlowResponse() {
        var context = AnimationContext<Double>()
        let previous = Animation.spring(
            response: 0.80,
            dampingFraction: 0.70,
            blendDuration: 0.0
        )
        let replacement = Animation.spring(
            response: 0.30,
            dampingFraction: 0.70,
            blendDuration: 0.30
        )

        XCTAssertTrue(
            replacement.shouldMerge(
                previous: previous,
                value: 1.0,
                time: 0.20,
                context: &context
            )
        )

        let state = context.state[SpringState<Double>.self]
        XCTAssertEqual(state.blendStart, 0.20, accuracy: 0.000_001)
        XCTAssertEqual(state.blendInterval, 0.50, accuracy: 0.000_001)
        XCTAssertEqual(
            effectiveResponse(response: 0.30, blendDuration: 0.30, time: 0.20, state: state),
            0.80,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            effectiveResponse(response: 0.30, blendDuration: 0.30, time: 0.35, state: state),
            0.55,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            effectiveResponse(response: 0.30, blendDuration: 0.30, time: 0.50, state: state),
            0.30,
            accuracy: 0.000_001
        )
    }

    private func effectiveResponse(
        response: TimeInterval,
        blendDuration: TimeInterval,
        time: TimeInterval,
        state: SpringState<Double>
    ) -> TimeInterval {
        blendedFluidSpringResponse(
            response: response,
            blendDuration: blendDuration,
            time: time,
            state: state
        )
    }
}
