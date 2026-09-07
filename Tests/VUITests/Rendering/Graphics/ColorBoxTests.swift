import XCTest
@testable import VUI

final class ColorBoxTests: XCTestCase {
    private struct AlwaysEqualProvider: ColorProvider, CodableSerializable {
        var value: Int
        var tag: Color.ProviderTag { .constant }
        static func == (lhs: Self, rhs: Self) -> Bool { true }
        func hash(into hasher: inout Hasher) { hasher.combine(0) }
        func resolve(in environment: EnvironmentValues) -> Color.Resolved {
            .init(colorSpace: .sRGBLinear, red: Float(value), green: 0, blue: 0)
        }
    }

    func testConcreteProviderDispatchAndEqualityUseProviderWitnesses() {
        let lhs = Color(ColorBox(AlwaysEqualProvider(value: 1)))
        let rhs = Color(ColorBox(AlwaysEqualProvider(value: 2)))
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        XCTAssertEqual(lhs.resolve(in: EnvironmentValues()).linearRed, 1)
        XCTAssertEqual(rhs.resolve(in: EnvironmentValues()).linearRed, 2)
        XCTAssertEqual(AnyShapeStyle(lhs).storage, AnyShapeStyle(rhs).storage)
        XCTAssertNotNil(lhs.provider.as(AlwaysEqualProvider.self))
        XCTAssertNil(lhs.provider.as(ResolvedColorProvider.self))
        let mirror = Mirror(reflecting: lhs.provider)
        XCTAssertEqual(mirror.children.map(\.label), ["base"])
        XCTAssertTrue(mirror.superclassMirror!.children.isEmpty)
        XCTAssertTrue(mirror.superclassMirror!.superclassMirror!.children.isEmpty)
    }

    func testColorConstructorsAndOpacityKeepConcreteOwnerKinds() throws {
        let constant = Color(.sRGB, red: 0.25, green: 0.5, blue: 0.75)
        XCTAssertNotNil(constant.provider as? ColorBox<ResolvedColorProvider>)
        let p3 = Color(.displayP3, red: 0.25, green: 0.5, blue: 0.75)
        XCTAssertNotNil(p3.provider as? ColorBox<Color.DisplayP3>)
        XCTAssertNotNil(Color.red.provider as? ColorBox<SystemColorType>)
        for opacity in [0.0, 1.0] {
            let wrapped = constant.opacity(opacity)
            XCTAssertFalse(wrapped.provider === constant.provider)
            let base = try XCTUnwrap(wrapped.provider.as(Color.OpacityColor.self))
            XCTAssertTrue(base.base.provider === constant.provider)
        }
        let first = constant.opacity(0.5)
        let second = first.opacity(0.25)
        XCTAssertTrue(try XCTUnwrap(second.provider.as(Color.OpacityColor.self)).base.provider === first.provider)
        XCTAssertEqual(second.resolve(in: EnvironmentValues()).opacity, 0.125)
    }

    func testControlledStyleOperationsAndSortedPackInsertion() throws {
        let color = Color(.sRGBLinear, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.625)
        var shape = _ShapeStyle_Shape(operation: .prepareText(level: 2), environment: EnvironmentValues())
        color._apply(to: &shape)
        guard case let .preparedText(.foregroundColor(prepared)) = shape.result else { return XCTFail("Expected a prepared color.") }
        XCTAssertTrue(try XCTUnwrap(prepared.provider.as(Color.OpacityColor.self)).base.provider === color.provider)
        shape.result = .none
        for (name, level): (_ShapeStyle_Name, Int) in [(.background, 2), (.foreground, 3), (.foreground, 1), (.foreground, 3)] {
            shape.operation = .resolveStyle(name: name, levels: level..<(level + 3))
            color._apply(to: &shape)
        }
        guard case let .pack(pack) = shape.result else { return XCTFail("Expected a color pack.") }
        XCTAssertEqual(pack.styles.map(\.key), [.init(.foreground, 1), .init(.foreground, 3), .init(.background, 2)])
        guard case let .color(resolved) = pack.styles[2].style.fill else { return XCTFail("Expected a resolved color fill.") }
        XCTAssertEqual(resolved.opacity, 0.15625)
        XCTAssertEqual(pack.styles[2].style.opacity, 1)
        for operation: _ShapeStyle_Shape.Operation in [.resolveStyle(name: .foreground, levels: 2..<2), .copyStyle(name: .foreground), .multiLevel, .primaryStyle, .modifyBackground(level: 2)] {
            shape.operation = operation
            shape.result = .bool(true)
            color._apply(to: &shape)
            guard case .bool(true) = shape.result else { return XCTFail("No-op requests must preserve the result.") }
        }
    }

    func testPrivateTaggedSerializationAndConstantHeadroomLoss() throws {
        let base = Color(.sRGBLinear, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.625)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ProxyCodable(base))
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       "{\"tag\":{\"constant\":{}},\"value\":{\"blue\":0.75,\"green\":0.5,\"opacity\":0.625,\"red\":0.25}}")
        for color in [base, Color(.sRGB, red: 0.25, green: 0.5, blue: 0.75),
                      Color(.displayP3, red: 0.25, green: 0.5, blue: 0.75), .red, .primary, .secondary,
                      .white, .black, .clear, base.opacity(0), base.opacity(1), base.opacity(0.5).opacity(0.25)] {
            let encoded = try encoder.encode(ProxyCodable(color))
            let decoded = try JSONDecoder().decode(ProxyCodable<Color>.self, from: encoded).wrappedValue
            XCTAssertEqual(decoded, color)
            XCTAssertEqual(try encoder.encode(ProxyCodable(decoded)), encoded)
        }
        let hdr = Color(Color.ResolvedHDR(base.resolve(in: EnvironmentValues()), headroom: 2))
        let encoded = try encoder.encode(ProxyCodable(hdr))
        XCTAssertEqual(encoded, data)
        let decoded = try JSONDecoder().decode(ProxyCodable<Color>.self, from: encoded).wrappedValue
        XCTAssertNil(decoded.resolveHDR(in: EnvironmentValues()).headroom)
        XCTAssertNotEqual(decoded, hdr)
        for json in ["{}", "{\"tag\":{\"unknown\":{}},\"value\":{}}", "{\"tag\":{\"constant\":{}}}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(ProxyCodable<Color>.self, from: Data(json.utf8)))
        }
    }

    func testRenderingComponentsAreEncodedIndependentlyOfConstructorSpace() {
        let color = Color(.sRGBLinear, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.625)
        let components = color.renderingComponents()
        XCTAssertEqual(components.colorSpace, .sRGB)
        XCTAssertEqual(components.red, 0.5370987057685852, accuracy: 0.000001)
        XCTAssertEqual(components.green, 0.7353569269180298, accuracy: 0.000001)
        XCTAssertEqual(components.blue, 0.8808249831199646, accuracy: 0.000001)
        XCTAssertEqual(components.alpha, 0.625)
        let p3 = Color(.displayP3, red: 0.25, green: 0.5, blue: 0.75).renderingComponents()
        XCTAssertEqual(p3.colorSpace, .displayP3)
        XCTAssertEqual(p3.red, 0.25)
        XCTAssertEqual(ColorMatrix.constantColor(color).r5, Float(components.red))
    }
}
