import Foundation
import XCTest
@testable import VUI

final class EffectAnimationTests: XCTestCase {
    func testCodableEffectAnimationUsesLeafEnvelopeAndRoundTrips() throws {
        let value = CodableEffectAnimation(
            base: DisplayList.OpacityAnimation(
                from: _OpacityEffect(opacity: 1),
                to: _OpacityEffect(opacity: 0.5),
                animation: .default
            )
        )
        let data = try ProtobufEncoder.encoding(value)

        XCTAssertEqual(
            data,
            Data([
                0x22, 0x0d,
                0x0a, 0x00,
                0x12, 0x05, 0x0d, 0x00, 0x00, 0x00, 0x3f,
                0x1a, 0x02, 0x3a, 0x00,
            ])
        )

        var decoder = ProtobufDecoder(data)
        let decoded = try CodableEffectAnimation(from: &decoder)
        let animation = try XCTUnwrap(decoded.base as? DisplayList.OpacityAnimation)
        XCTAssertEqual(animation.from, _OpacityEffect(opacity: 1))
        XCTAssertEqual(animation.to, _OpacityEffect(opacity: 0.5))
        XCTAssertEqual(animation.animation, .default)
        XCTAssertEqual(decoded.size, .zero)
    }

    func testCodableEffectAnimationUsesSizeFieldFive() throws {
        // ASSERTIONS displayListEffectAnimationProtobufObserved
        // ASSERTIONS canvasProtobufCGFloatPrecisionObserved
        let value = CodableEffectAnimation(
            base: DisplayList.OffsetAnimation(
                from: _OffsetEffect(offset: .zero),
                to: _OffsetEffect(offset: CGSize(width: 10, height: 20)),
                animation: .default
            ),
            size: CGSize(width: 100, height: 200)
        )
        let data = try ProtobufEncoder.encoding(value)

        XCTAssertEqual(data.first, 0x0a)
        XCTAssertEqual(
            Data(data.suffix(12)),
            Data([
                0x2a, 0x0a,
                0x0d, 0x00, 0x00, 0xc8, 0x42,
                0x15, 0x00, 0x00, 0x48, 0x43,
            ])
        )
        var decoder = ProtobufDecoder(data)
        let decoded = try CodableEffectAnimation(from: &decoder)
        let animation = try XCTUnwrap(decoded.base as? DisplayList.OffsetAnimation)
        XCTAssertEqual(animation.from.offset, .zero)
        XCTAssertEqual(animation.to.offset, CGSize(width: 10, height: 20))
        XCTAssertEqual(decoded.size, CGSize(width: 100, height: 200))
    }

    func testEffectAnimationLeafRequiresFromToAndAnimation() {
        for data in [
            Data(),
            Data([0x0a, 0x00]),
            Data([0x0a, 0x00, 0x12, 0x00]),
        ] {
            var decoder = ProtobufDecoder(data)
            XCTAssertThrowsError(
                try DisplayList.OpacityAnimation(from: &decoder),
                "payload: \(data as NSData)"
            )
        }
    }

    func testCodableEffectAnimationRequiresLeaf() {
        var decoder = ProtobufDecoder(Data([0x2a, 0x00]))
        XCTAssertThrowsError(try CodableEffectAnimation(from: &decoder))
    }

    func testOpacityAnimatorStartsFromSourceAndFinishesAtTarget() {
        let animation = DisplayList.OpacityAnimation(
            from: _OpacityEffect(opacity: 0.25),
            to: _OpacityEffect(opacity: 0.75),
            animation: .linear(duration: 0)
        )
        var animator = animation.makeAnimator()

        let initial = animator.evaluate(animation, at: .zero, size: .zero)
        XCTAssertEqual(opacity(from: initial.effect), 0.25)
        XCTAssertFalse(initial.finished)

        let final = animator.evaluate(
            animation,
            at: Time(seconds: 1),
            size: .zero
        )
        XCTAssertEqual(opacity(from: final.effect), 0.75)
        XCTAssertTrue(final.finished)
    }

    func testEffectAnimatorTypeMismatchReturnsIdentityAndFinishes() {
        let offset = DisplayList.OffsetAnimation(
            from: _OffsetEffect(offset: .zero),
            to: _OffsetEffect(offset: CGSize(width: 10, height: 20)),
            animation: .default
        )
        let opacity = DisplayList.OpacityAnimation(
            from: _OpacityEffect(opacity: 0),
            to: _OpacityEffect(opacity: 1),
            animation: .default
        )
        var animator = offset.makeAnimator()

        let result = animator.evaluate(opacity, at: .zero, size: .zero)
        guard case .identity = result.effect else {
            return XCTFail("expected identity effect")
        }
        XCTAssertTrue(result.finished)
    }

    func testGeometryAnimatorProjectsEffectAndRejectsNoninvertibleTransform() {
        let offset = DisplayList.OffsetAnimation(
            from: _OffsetEffect(offset: CGSize(width: 3, height: 4)),
            to: _OffsetEffect(offset: CGSize(width: 8, height: 9)),
            animation: .default
        )
        var offsetAnimator = offset.makeAnimator()
        let offsetResult = offsetAnimator.evaluate(
            offset,
            at: .zero,
            size: CGSize(width: 100, height: 100)
        )
        guard case let .transform(transform) = offsetResult.effect else {
            return XCTFail("expected transform effect")
        }
        XCTAssertEqual(transform.m31, 3)
        XCTAssertEqual(transform.m32, 4)

        let scale = DisplayList.ScaleAnimation(
            from: _ScaleEffect(scale: .zero),
            to: _ScaleEffect(scale: CGSize(width: 1, height: 1)),
            animation: .default
        )
        var scaleAnimator = scale.makeAnimator()
        let scaleResult = scaleAnimator.evaluate(
            scale,
            at: .zero,
            size: CGSize(width: 100, height: 100)
        )
        guard case .identity = scaleResult.effect else {
            return XCTFail("expected identity for a noninvertible transform")
        }
    }

    private func opacity(from effect: DisplayList.Effect) -> Float? {
        guard case let .opacity(value) = effect else { return nil }
        return value
    }
}
