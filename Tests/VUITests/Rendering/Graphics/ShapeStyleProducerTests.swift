import Foundation
import XCTest
@testable import VUI

final class ShapeStyleProducerTests: XCTestCase {
    private let shadow = ShadowStyle.drop(color: Color(.sRGBLinear, red: 0, green: 0.6, blue: 0.2, opacity: 0.7), radius: 2, x: 4, y: 3)

    func testShadowPreparationAndPrimaryRequestDoNotEvaluateTheBase() {
        // ASSERTIONS shapeStyleShadowProducer27Observed
        let calls = ProducerCalls()
        let style = ObservedProducerStyle(calls: calls).shadow(shadow)
        var shape = _ShapeStyle_Shape(operation: .prepareText(level: 2), result: .bool(false), environment: .init())
        style._apply(to: &shape)
        guard case .preparedText(.foregroundKeyColor) = shape.result else { return XCTFail() }
        XCTAssertEqual(calls.count, 0)
        shape.operation = .primaryStyle
        shape.result = .bool(false)
        style._apply(to: &shape)
        guard case .bool(false) = shape.result else { return XCTFail("Primary requests must preserve the result") }
        XCTAssertEqual(calls.count, 0)
        for operation: _ShapeStyle_Shape.Operation in [.fallbackColor(level: 2), .modifyBackground(level: 2), .multiLevel] {
            shape.operation = operation
            style._apply(to: &shape)
            guard case .bool(true) = shape.result else { return XCTFail("Request must reach the base") }
        }
        XCTAssertEqual(calls.count, 3)
        var type = _ShapeStyle_ShapeType()
        _ShadowShapeStyle<ObservedProducerStyle>._apply(to: &type)
        guard case .bool(true) = type.result else { return XCTFail("Type requests must reach the base type") }
    }

    func testShadowAppendsIndependentEffectsOnlyToMatchingPackEntries() throws {
        // ASSERTIONS shapeStyleShadowProducer27Observed
        var base = _ShapeStyle_Pack.Style(.color(Color.red.resolveHDR(in: .init())))
        base.opacity = 0.25
        base._blend = .multiply
        let original = _ShapeStyle_Pack(styles: [(.init(.foreground, 0), base),
            (.init(.background, 0), base), (.init(.background, 2), base), (.init(.background, 5), base)])
        var shape = _ShapeStyle_Shape(operation: .resolveStyle(name: .background, levels: 2..<5),
            result: .pack(original), environment: .init())
        EmptyProducerStyle().shadow(shadow)._apply(to: &shape)
        guard case let .pack(pack) = shape.result else { return XCTFail() }
        XCTAssertEqual(pack.styles.map { $0.style.effects.count }, [0, 0, 1, 0])
        XCTAssertEqual(pack.styles.map { $0.style.opacity }, [0.25, 0.25, 0.25, 0.25])
        XCTAssertEqual(pack.styles.map { $0.style._blend }, [.multiply, .multiply, .multiply, .multiply])
        XCTAssertEqual(pack.styles[2].style.effects[0], .init(kind: .shadow(shadow.resolve(in: .init())), opacity: 1, _blend: nil))
        XCTAssertTrue(original.styles.allSatisfy { $0.style.effects.isEmpty })
        shape = .init(operation: .resolveStyle(name: .foreground, levels: 2..<2), environment: .init())
        EmptyProducerStyle().shadow(shadow)._apply(to: &shape)
        guard case let .pack(empty) = shape.result else { return XCTFail("An empty resolution must publish an empty pack") }
        XCTAssertTrue(empty.styles.isEmpty)
    }

    func testPublicShadowChainsPreserveOrderAndOuterOpacity() throws {
        // ASSERTIONS shapeStyleShadowProducer27Observed
        // ASSERTIONS shapeStyleOpacityProducer27Observed
        let color = AnyShapeStyle(Color.red)
        let before = try resolved(color.opacity(0.4).shadow(shadow))
        let after = try resolved(color.shadow(shadow).opacity(0.4))
        XCTAssertEqual(before.opacity, 0.4)
        XCTAssertEqual(after.opacity, 0.4)
        XCTAssertEqual(before.effects[0].opacity, 1)
        XCTAssertEqual(after.effects[0].opacity, 0.4)
        XCTAssertEqual(before.effects[0].kind, after.effects[0].kind)
        let inner = ShadowStyle.inner(color: .blue, radius: 5, x: -2, y: 1)
        let chain = try resolved(color.shadow(shadow).opacity(0.4).shadow(inner))
        XCTAssertEqual(chain.effects.map(\.opacity), [0.4, 1])
        XCTAssertEqual(chain.effects.map(\.kind), [.shadow(shadow.resolve(in: .init())), .shadow(inner.resolve(in: .init()))])
        let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        let painted = try resolved(gradient.shadow(shadow))
        guard case .paint = painted.fill else { return XCTFail("A shadow must preserve the base paint") }
        XCTAssertEqual(painted.effects.count, 1)
    }

    func testImplicitCopyRetainsTheSelectedForegroundOrBackgroundStyle() throws {
        // ASSERTIONS shapeStyleImplicitCopy27Observed
        var environment = EnvironmentValues()
        environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(Color.green))
        environment.backgroundStyle = AnyShapeStyle(Color.blue)
        let implicit = AnyShapeStyle.shadow(shadow)
        let foreground = implicit.copyStyle(in: environment)
        let background = implicit.copyStyle(name: .background, in: environment)
        let override = implicit.copyStyle(in: environment, foregroundStyle: AnyShapeStyle(Color.red))
        environment.foregroundStyleLevels = .init(primary: AnyShapeStyle(Color.yellow))
        environment.backgroundStyle = AnyShapeStyle(Color.black)
        XCTAssertEqual(try resolved(foreground, in: environment).fill, .color(Color.green.resolveHDR(in: environment)))
        XCTAssertEqual(try resolved(background, in: environment).fill, .color(Color.blue.resolveHDR(in: environment)))
        XCTAssertEqual(try resolved(override, in: environment).fill, .color(Color.red.resolveHDR(in: environment)))
        XCTAssertEqual(try resolved(foreground, in: environment).effects.count, 1)
        let opacity = AnyShapeStyle.opacity(0.4).copyStyle(in: environment)
        XCTAssertEqual(try resolved(opacity, in: environment).opacity, 0.4)
    }

    func testImplicitTypeQueriesPreserveTheExistingResult() {
        // ASSERTIONS shapeStyleImplicitCopy27Observed
        for result: _ShapeStyle_ShapeType.Result in [.none, .bool(false), .bool(true)] {
            var type = _ShapeStyle_ShapeType(result: result)
            _ImplicitShapeStyle._apply(to: &type)
            _ShadowShapeStyle<_ImplicitShapeStyle>._apply(to: &type)
            _OpacityShapeStyle<_ImplicitShapeStyle>._apply(to: &type)
            switch (result, type.result) {
            case (.none, .none), (.bool(false), .bool(false)), (.bool(true), .bool(true)):
                break
            default:
                XCTFail("Implicit type queries must preserve the supplied result")
            }
        }
    }

    func testShadowFallbackPreservesBaseColorAndUnmodifiedGeometry() throws {
        // ASSERTIONS shapeStyleShadowProducer27Observed
        var shape = _ShapeStyle_Shape(operation: .fallbackColor(level: 0), environment: .init())
        Color.red.shadow(shadow)._apply(to: &shape)
        guard case let .color(color) = shape.result else { return XCTFail() }
        XCTAssertEqual(color.resolveHDR(in: .init()), Color.red.resolveHDR(in: .init()))
        let hdr = Color.ResolvedHDR(Color.blue.resolve(in: .init()), headroom: 3)
        let raw = ShadowStyle.drop(color: Color(hdr), radius: -2, x: -4, y: 7).midpoint(0.25)
        let style = try resolved(Color.red.shadow(raw))
        guard case let .shadow(value) = style.effects[0].kind else { return XCTFail() }
        XCTAssertEqual(value.color.headroom, 3)
        XCTAssertEqual(value.radius, -2)
        XCTAssertEqual(value.offset, CGSize(width: -4, height: 7))
        XCTAssertEqual(value.midpoint, 0.25)
    }

    func testOpacityPreparationUsesKeyColorUnlessItIsAnIdentity() {
        // ASSERTIONS shapeStyleOpacityProducer27Observed
        for opacity: Float in [0, 0.4, 1, 2] {
            var shape = _ShapeStyle_Shape(operation: .prepareText(level: 0), environment: .init())
            _OpacityShapeStyle(style: AnyShapeStyle(Color.red), opacity: opacity)._apply(to: &shape)
            if opacity == 1 {
                guard case .preparedText(.foregroundColor) = shape.result else { return XCTFail("Identity must preserve the base preparation") }
            } else {
                guard case .preparedText(.foregroundKeyColor) = shape.result else { return XCTFail("Nonidentity opacity requires styled rendering") }
            }
        }
    }

    func testOpacityScalesExistingEffectsOnlyInTheRequestedStyleRange() throws {
        // ASSERTIONS shapeStyleOpacityProducer27Observed
        var style = _ShapeStyle_Pack.Style(.color(Color.red.resolveHDR(in: .init())))
        style.opacity = 0.8
        style.effects = [.init(kind: .shadow(ShadowStyle.drop(radius: 2).resolve(in: .init())), opacity: 0.6, _blend: nil)]
        let pack = _ShapeStyle_Pack(styles: [(.init(.foreground, 0), style),
            (.init(.background, 0), style), (.init(.background, 2), style), (.init(.background, 5), style)])
        var shape = _ShapeStyle_Shape(operation: .resolveStyle(name: .background, levels: 2..<5),
            result: .pack(pack), environment: .init())
        _OpacityShapeStyle(style: EmptyProducerStyle(), opacity: 0.5)._apply(to: &shape)
        guard case let .pack(result) = shape.result else { return XCTFail("Missing style pack") }
        XCTAssertEqual(result.styles.map { $0.style.opacity }, [0.8, 0.8, 0.4, 0.8])
        XCTAssertEqual(result.styles.map { $0.style.effects[0].opacity }, [0.6, 0.6, 0.3, 0.6])
        XCTAssertEqual(result.styles.map { $0.style.fill }, pack.styles.map { $0.style.fill })
    }

    private func resolved<S: ShapeStyle>(_ style: S, in environment: EnvironmentValues = .init()) throws -> _ShapeStyle_Pack.Style {
        var shape = _ShapeStyle_Shape(operation: .resolveStyle(name: .foreground, levels: 0..<1), environment: environment)
        style._apply(to: &shape)
        guard case let .pack(pack) = shape.result else { throw NSError(domain: "Missing pack", code: 1) }
        return try XCTUnwrap(pack.styles.first?.style)
    }
}

private struct EmptyProducerStyle: ShapeStyle {
    func _apply(to shape: inout _ShapeStyle_Shape) {}
    static func _apply(to type: inout _ShapeStyle_ShapeType) {}
}

private final class ProducerCalls: @unchecked Sendable { var count = 0 }
private struct ObservedProducerStyle: ShapeStyle {
    let calls: ProducerCalls
    func _apply(to shape: inout _ShapeStyle_Shape) { calls.count += 1; shape.result = .bool(true) }
    static func _apply(to type: inout _ShapeStyle_ShapeType) { type.result = .bool(true) }
}
