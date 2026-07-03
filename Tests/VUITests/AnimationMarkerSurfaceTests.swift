import XCTest
@testable import VUI

final class AnimationMarkerSurfaceTests: XCTestCase {
    func testAnimationCompletionCriteriaValueSurface() {
        XCTAssertEqual(MemoryLayout<AnimationCompletionCriteria>.size, 1)
        XCTAssertEqual(MemoryLayout<AnimationCompletionCriteria>.stride, 1)
        XCTAssertEqual(MemoryLayout<AnimationCompletionCriteria>.alignment, 1)

        let logical = AnimationCompletionCriteria.logicallyComplete
        let removed = AnimationCompletionCriteria.removed

        XCTAssertNotEqual(logical, removed)
        XCTAssertEqual(Set([logical, removed]).count, 2)

        XCTAssertEqual(Mirror(reflecting: logical).children.first?.label, "storage")
        XCTAssertEqual(Mirror(reflecting: logical).children.first?.value as? UInt8, 0)
        XCTAssertEqual(Mirror(reflecting: removed).children.first?.label, "storage")
        XCTAssertEqual(Mirror(reflecting: removed).children.first?.value as? UInt8, 1)
    }

    func testTransitionPhaseValueSurface() {
        XCTAssertEqual(TransitionPhase.willAppear.value, -1)
        XCTAssertEqual(TransitionPhase.identity.value, 0)
        XCTAssertEqual(TransitionPhase.didDisappear.value, 1)

        XCTAssertFalse(TransitionPhase.willAppear.isIdentity)
        XCTAssertTrue(TransitionPhase.identity.isIdentity)
        XCTAssertFalse(TransitionPhase.didDisappear.isIdentity)
    }

    func testSourceVisibleMarkerConformersKeepExpectedValueSurface() {
        var modifier = MarkerAnimatableModifier(amount: 0.5)
        XCTAssertEqual(Mirror(reflecting: modifier).children.first?.label, "amount")
        XCTAssertEqual(modifier.animatableData, 0.5)
        modifier.animatableData = 0.75
        XCTAssertEqual(modifier.amount, 0.75)

        var effect = MarkerGeometryEffect(offset: 12)
        XCTAssertTrue(MarkerGeometryEffect._affectsLayout)
        XCTAssertEqual(Mirror(reflecting: effect).children.first?.label, "offset")
        XCTAssertEqual(effect.animatableData, 12)
        effect.animatableData = 18
        XCTAssertEqual(effect.offset, 18)

        let transform = effect.effectValue(size: CGSize(width: 100, height: 40))
        XCTAssertEqual(transform.m31, 18, accuracy: 0.000_001)
        XCTAssertEqual(transform.m32, 0, accuracy: 0.000_001)
    }

    func testTransitionDefaultPropertiesSurface() {
        XCTAssertTrue(MarkerTransition.properties.hasMotion)
        XCTAssertEqual(MemoryLayout<MarkerTransition>.size, 0)
        XCTAssertEqual(MemoryLayout<MarkerTransition>.stride, 1)
        XCTAssertEqual(Mirror(reflecting: MarkerTransition()).children.count, 0)
    }
}

private struct MarkerAnimatableModifier: ViewModifier, Animatable {
    var amount: Double

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> Content {
        content
    }
}

private struct MarkerGeometryEffect: GeometryEffect {
    var offset: CGFloat

    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        _ = size
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

private struct MarkerTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> Content {
        _ = phase
        return content
    }
}
