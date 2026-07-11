import Foundation
import XCTest
@testable import VUI

final class ShadowStyleTests: XCTestCase {
    func testResolvedHDRPreservesOptionalHeadroomAndColorAnimation() throws {
        let base = Color.Resolved(
            colorSpace: .sRGBLinear,
            red: 0.1,
            green: 0.2,
            blue: 0.3,
            opacity: 0.4
        )
        var resolved = Color.ResolvedHDR(base)

        XCTAssertNil(resolved.headroom)
        XCTAssertEqual(resolved.linearRed, 0.1)
        XCTAssertEqual(resolved.linearGreen, 0.2)
        XCTAssertEqual(resolved.linearBlue, 0.3)
        XCTAssertEqual(resolved.opacity, 0.4)
        XCTAssertEqual(resolved.description, "#597C9566")

        resolved.headroom = 2
        XCTAssertEqual(resolved.description, "#597C9566^2.0")
        var data = resolved.animatableData
        data.red = 0.5
        data.green = 0.6
        data.blue = 0.7
        data.opacity = 0.8
        resolved.animatableData = data

        XCTAssertEqual(resolved.linearRed, 0.5)
        XCTAssertEqual(resolved.linearGreen, 0.6)
        XCTAssertEqual(resolved.linearBlue, 0.7)
        XCTAssertEqual(resolved.opacity, 0.8)
        XCTAssertEqual(resolved.headroom, 2)

        let encoded = try JSONEncoder().encode(resolved)
        let encodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual((encodedObject["color"] as? [Double])?.count, 4)
        XCTAssertEqual(encodedObject["headroom"] as? Double, 2)
        let decoded = try JSONDecoder().decode(Color.ResolvedHDR.self, from: encoded)
        XCTAssertEqual(decoded.linearRed, resolved.linearRed, accuracy: 0.000_001)
        XCTAssertEqual(decoded.linearGreen, resolved.linearGreen, accuracy: 0.000_001)
        XCTAssertEqual(decoded.linearBlue, resolved.linearBlue, accuracy: 0.000_001)
        XCTAssertEqual(decoded.opacity, resolved.opacity, accuracy: 0.000_001)
        XCTAssertEqual(decoded.headroom, resolved.headroom)

        var nilHeadroom = decoded
        nilHeadroom.headroom = nil
        XCTAssertNil(nilHeadroom.headroom)
        XCTAssertEqual(nilHeadroom, Color.ResolvedHDR(nilHeadroom.base))
        let nilObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(nilHeadroom)) as? [String: Any]
        )
        XCTAssertNil(nilObject["headroom"])
    }

    func testShadowStyleFactoriesAndKindBitsMatchObservedSurface() throws {
        XCTAssertEqual(ShadowStyle.Kind.drop.rawValue, 0)
        XCTAssertEqual(ShadowStyle.Kind.inner.rawValue, 0x01)
        XCTAssertEqual(ShadowStyle.Kind.only.rawValue, 0x02)
        XCTAssertEqual(ShadowStyle.Kind.nonOpaque.rawValue, 0x04)
        XCTAssertEqual(ShadowStyle.Kind.ignoresFill.rawValue, 0x08)
        XCTAssertEqual(ShadowStyle.Kind.requiresKnockout.rawValue, 0x10)

        let drop = ShadowStyle.drop(color: .red, radius: 4, x: 2, y: -1)
        guard case let .custom(kind, color, radius, offset) = drop.storage else {
            return XCTFail("expected custom drop shadow storage")
        }
        XCTAssertEqual(kind, .drop)
        XCTAssertEqual(color, .red)
        XCTAssertEqual(radius, 4)
        XCTAssertEqual(offset, CGSize(width: 2, height: -1))
        XCTAssertEqual(drop.midpoint, 0.5)

        let inner = ShadowStyle.inner(radius: 6)
        let resolvedInner = inner.resolve(in: EnvironmentValues())
        XCTAssertEqual(resolvedInner.kind, .inner)
        XCTAssertEqual(resolvedInner.radius, 6)
        XCTAssertEqual(resolvedInner.offset, .zero)
        XCTAssertEqual(resolvedInner.midpoint, 0.5)
        XCTAssertEqual(resolvedInner.color.opacity, 0.55, accuracy: 0.000_001)

        let adjusted = drop.ignoresFill(true, knockout: true).midpoint(0.25)
        let resolvedAdjusted = adjusted.resolve(in: EnvironmentValues())
        XCTAssertTrue(resolvedAdjusted.kind.contains(.ignoresFill))
        XCTAssertTrue(resolvedAdjusted.kind.contains(.requiresKnockout))
        XCTAssertEqual(resolvedAdjusted.midpoint, 0.25)
    }

    func testResolvedShadowAnimationKeepsHeadroomMidpointAndKind() {
        var shadow = ResolvedShadowStyle(
            color: Color.ResolvedHDR(
                Color.Resolved(
                    colorSpace: .sRGBLinear,
                    red: 0.1,
                    green: 0.2,
                    blue: 0.3,
                    opacity: 0.4
                ),
                headroom: 3
            ),
            radius: 2,
            offset: CGSize(width: 3, height: 4),
            midpoint: 0.25,
            kind: [.inner, .only]
        )
        let target = ResolvedShadowStyle(
            color: Color.ResolvedHDR(
                Color.Resolved(
                    colorSpace: .sRGBLinear,
                    red: 0.6,
                    green: 0.7,
                    blue: 0.8,
                    opacity: 0.9
                ),
                headroom: 8
            ),
            radius: 9,
            offset: CGSize(width: 10, height: 11),
            midpoint: 0.75,
            kind: .drop
        )

        shadow.animatableData = target.animatableData

        XCTAssertEqual(shadow.color.base, target.color.base)
        XCTAssertEqual(shadow.radius, target.radius)
        XCTAssertEqual(shadow.offset, target.offset)
        XCTAssertEqual(shadow.color.headroom, 3)
        XCTAssertEqual(shadow.midpoint, 0.25)
        XCTAssertEqual(shadow.kind, [.inner, .only])
    }

    func testViewAndTextShadowPathsShareResolvedCarrier() {
        let resolvedModifier = _ShadowEffect(
            color: .blue,
            radius: 5,
            offset: CGSize(width: 1, height: 2)
        ).resolve(in: EnvironmentValues())

        XCTAssertEqual(resolvedModifier.style.color.base, Color.blue.resolve(in: EnvironmentValues()))
        XCTAssertEqual(resolvedModifier.style.radius, 5)
        XCTAssertEqual(resolvedModifier.style.offset, CGSize(width: 1, height: 2))
        XCTAssertEqual(resolvedModifier.style.midpoint, 0.5)
        XCTAssertEqual(resolvedModifier.style.kind, .drop)

        let effect = _ShapeStyle_Pack.Effect(
            kind: .shadow(resolvedModifier.style),
            opacity: 0.75,
            _blend: .multiply
        )
        XCTAssertEqual(effect.kind, .shadow(resolvedModifier.style))
        XCTAssertEqual(effect.opacity, 0.75)
        XCTAssertEqual(effect._blend, .multiply)
        XCTAssertEqual(
            _ShapeStyle_Pack.Effect(kind: .none, opacity: 1, _blend: nil).kind,
            .none
        )
    }
}
