import XCTest
@testable import VUI

final class AnimationFinishingDefinitionTests: XCTestCase {
    func testRotationEffectFinishingDefinitionRequiresAngleSettledAndAnchorUnchanged() {
        let context = makeAnimationContext(
            for: _RotationEffect.self,
            state: AnimationState<_RotationEffect.AnimatableData>(),
            environment: EnvironmentValues()
        )

        XCTAssertTrue(
            context.shouldFinishEarly(
                data: .init(
                    delta: _RotationEffect.AnimatableData(1.0, UnitPoint.zero.animatableData),
                    velocity: _RotationEffect.AnimatableData(0.5, UnitPoint.zero.animatableData)
                )
            )
        )

        XCTAssertFalse(
            context.shouldFinishEarly(
                data: .init(
                    delta: _RotationEffect.AnimatableData(1.28, UnitPoint.zero.animatableData),
                    velocity: _RotationEffect.AnimatableData(0.0, UnitPoint.zero.animatableData)
                )
            )
        )

        XCTAssertFalse(
            context.shouldFinishEarly(
                data: .init(
                    delta: _RotationEffect.AnimatableData(0.0, UnitPoint(x: .ulpOfOne, y: 0).animatableData),
                    velocity: _RotationEffect.AnimatableData(0.0, UnitPoint.zero.animatableData)
                )
            )
        )
    }

    func testViewFrameFinishingDefinitionUsesPixelLengthForOriginAndDoubleForSize() {
        var environment = EnvironmentValues()
        environment.defaultPixelLength = 2
        let context = makeAnimationContext(
            for: ViewFrame.self,
            state: AnimationState<ViewFrame.AnimatableData>(),
            environment: environment
        )

        XCTAssertTrue(
            context.shouldFinishEarly(
                data: .init(
                    delta: ViewFrame.AnimatableData(
                        CGPoint(x: 1.0, y: 1.0).animatableData,
                        ViewSize(width: 3.0, height: 3.0).animatableData
                    ),
                    velocity: ViewFrame.AnimatableData(
                        CGPoint(x: 1.0, y: 1.0).animatableData,
                        ViewSize(width: 2.0, height: 2.0).animatableData
                    )
                )
            )
        )

        XCTAssertFalse(
            context.shouldFinishEarly(
                data: .init(
                    delta: ViewFrame.AnimatableData(
                        CGPoint(x: 2.0, y: 0.0).animatableData,
                        ViewSize(width: 0.0, height: 0.0).animatableData
                    ),
                    velocity: .zero
                )
            )
        )

        XCTAssertFalse(
            context.shouldFinishEarly(
                data: .init(
                    delta: ViewFrame.AnimatableData(
                        CGPoint.zero.animatableData,
                        ViewSize(width: 4.0, height: 0.0).animatableData
                    ),
                    velocity: .zero
                )
            )
        )
    }
}
