import XCTest
@testable import VUI

final class AppearanceAnimationViewTests: XCTestCase {
    func testAppearanceAnimationBuildsInactiveThenActiveValues() {
        var values: [Bool] = []

        _ = EmptyView().appearanceAnimation(
            animation: .linear(duration: 1),
            strategy: .animationValue
        ) { content, active in
            values.append(active)
            return content.opacity(active ? 1 : 0)
        }

        XCTAssertEqual(values, [false, true])
    }

    func testDisplayListAnimationRecognizesSupportedModifierLeaves() {
        let animation = Animation.linear(duration: 1)

        let opacity = AppearanceAnimationView(
            content: EmptyView(),
            from: EmptyView().opacity(0.25),
            to: EmptyView().opacity(0.75),
            animation: animation,
            strategy: .withAnimation
        )
        let opacityLeaf = opacity.displayListAnimation as? DisplayList.OpacityAnimation
        XCTAssertEqual(opacityLeaf?.from.opacity, 0.25)
        XCTAssertEqual(opacityLeaf?.to.opacity, 0.75)

        let offset = AppearanceAnimationView(
            content: EmptyView(),
            from: EmptyView().offset(x: 1, y: 2),
            to: EmptyView().offset(x: 3, y: 4),
            animation: animation,
            strategy: .withAnimation
        )
        let offsetLeaf = offset.displayListAnimation as? DisplayList.OffsetAnimation
        XCTAssertEqual(offsetLeaf?.from.offset, CGSize(width: 1, height: 2))
        XCTAssertEqual(offsetLeaf?.to.offset, CGSize(width: 3, height: 4))

        let scale = AppearanceAnimationView(
            content: EmptyView(),
            from: EmptyView().scaleEffect(CGSize(width: 1, height: 2), anchor: .topLeading),
            to: EmptyView().scaleEffect(CGSize(width: 3, height: 4), anchor: .bottomTrailing),
            animation: animation,
            strategy: .animationValue
        )
        let scaleLeaf = scale.displayListAnimation as? DisplayList.ScaleAnimation
        XCTAssertEqual(scaleLeaf?.from.scale, CGSize(width: 1, height: 2))
        XCTAssertEqual(scaleLeaf?.from.anchor, .topLeading)
        XCTAssertEqual(scaleLeaf?.to.scale, CGSize(width: 3, height: 4))
        XCTAssertEqual(scaleLeaf?.to.anchor, .bottomTrailing)

        let rotation = AppearanceAnimationView(
            content: EmptyView(),
            from: EmptyView().rotationEffect(.degrees(15), anchor: .top),
            to: EmptyView().rotationEffect(.degrees(45), anchor: .bottom),
            animation: animation,
            strategy: .animationValue
        )
        let rotationLeaf = rotation.displayListAnimation as? DisplayList.RotationAnimation
        XCTAssertEqual(rotationLeaf?.from.angle, .degrees(15))
        XCTAssertEqual(rotationLeaf?.from.anchor, .top)
        XCTAssertEqual(rotationLeaf?.to.angle, .degrees(45))
        XCTAssertEqual(rotationLeaf?.to.anchor, .bottom)
    }

    func testUnsupportedModifierProducesIdentityArchiveEffect() {
        let view = AppearanceAnimationView(
            content: EmptyView(),
            from: EmptyView().blur(radius: 1),
            to: EmptyView().blur(radius: 2),
            animation: .linear(duration: 1),
            strategy: .withAnimation
        )

        XCTAssertNil(view.displayListAnimation)
        let effect = type(of: view).AnimationEffect(animation: view.displayListAnimation)
        guard case .identity = effect.effectValue(size: .zero) else {
            return XCTFail("unsupported appearance modifier should archive as identity")
        }
    }

    func testAnimationEffectCarriesLeafAndParticipatesInSurfaceMatching() {
        let first = DisplayList.OpacityAnimation(
            from: _OpacityEffect(opacity: 0),
            to: _OpacityEffect(opacity: 1),
            animation: .linear(duration: 1)
        )
        let same = DisplayList.OpacityAnimation(
            from: _OpacityEffect(opacity: 0),
            to: _OpacityEffect(opacity: 1),
            animation: .linear(duration: 1)
        )
        let different = DisplayList.OpacityAnimation(
            from: _OpacityEffect(opacity: 0.25),
            to: _OpacityEffect(opacity: 1),
            animation: .linear(duration: 1)
        )

        let effect = AppearanceAnimationView<EmptyView, EmptyView>.AnimationEffect(
            animation: first
        ).effectValue(size: .zero)
        guard case let .animation(animation) = effect else {
            return XCTFail("supported appearance animation should emit the runtime effect")
        }
        XCTAssertTrue(animation is DisplayList.OpacityAnimation)
        XCTAssertTrue(effect.hasSameSurface(as: .animation(same)))
        XCTAssertFalse(effect.hasSameSurface(as: .animation(different)))
    }
}
