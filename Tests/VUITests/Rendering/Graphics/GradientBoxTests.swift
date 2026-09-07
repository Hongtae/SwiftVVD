import XCTest
@testable import VUI

final class GradientBoxTests: XCTestCase {
    private let color = Color(.sRGBLinear, red: 0.25, green: 0.5, blue: 0.75)

    func testTypeQueriesPreserveTheirInput() {
        let queries: [(inout _ShapeStyle_ShapeType) -> Void] = [
            Gradient._apply(to:), AnyGradient._apply(to:), LinearGradient._apply(to:), _AnyLinearGradient._apply(to:)
        ]
        for query in queries {
            for initial: _ShapeStyle_ShapeType.Result in [.none, .bool(false), .bool(true)] {
                var type = _ShapeStyle_ShapeType(result: initial)
                query(&type)
                switch (initial, type.result) {
                case (.none, .none), (.bool(false), .bool(false)), (.bool(true), .bool(true)): break
                default: XCTFail("Gradient type queries must preserve their input.")
                }
            }
        }
    }

    func testOnlyHDRPaintUsesTheEffectiveDynamicRange() {
        for range: Image.DynamicRange in [.standard, .constrainedHigh, .high] {
            var environment = EnvironmentValues()
            environment.allowedDynamicRange = range
            for headroom: Float in [0.5, 1, 2] {
                let gradient = Gradient(colors: [Color(Color.ResolvedHDR(color.resolve(in: environment), headroom: headroom))])
                let direct = LinearGradient(gradient: gradient, startPoint: .top, endPoint: .bottom).resolvePaint(in: environment)
                let erased = _AnyLinearGradient(gradient: AnyGradient(gradient), startPoint: .top, endPoint: .bottom).resolvePaint(in: environment)
                XCTAssertEqual(direct.allowedDynamicRange, headroom > 1 ? range : .standard)
                XCTAssertEqual(erased.allowedDynamicRange, direct.allowedDynamicRange)
            }
        }
    }

    func testProviderValueEqualityWrappingAndStopArrayOwnership() throws {
        var gradient = Gradient(colors: [color, .white])
        let boxed = AnyGradient(gradient)
        let equal = AnyGradient(gradient)
        XCTAssertFalse(boxed.provider === equal.provider)
        XCTAssertEqual(boxed, equal)
        XCTAssertEqual(Set([boxed, equal]).count, 1)
        XCTAssertEqual(Mirror(reflecting: boxed.provider).children.map(\.label), ["base"])
        let superclass = try XCTUnwrap(Mirror(reflecting: boxed.provider).superclassMirror)
        XCTAssertTrue(superclass.children.isEmpty)
        XCTAssertTrue(superclass.superclassMirror!.children.isEmpty)
        let device = boxed.colorSpace(.device)
        XCTAssertEqual(device, boxed.colorSpace(.device))
        XCTAssertNotEqual(device, device.colorSpace(.device))
        XCTAssertNotEqual(device, gradient.colorSpace(.device))
        let wrapper = try XCTUnwrap(device.provider as? GradientBox<ColorSpaceGradientProvider>)
        guard case let .anyGradient(base) = wrapper.base.base else { return XCTFail("Wrapper must retain the erased base.") }
        XCTAssertTrue(base.provider === boxed.provider)
        gradient.stops[0].color = .black
        XCTAssertEqual(boxed.resolve(in: EnvironmentValues()).stops[0].color, color.resolve(in: EnvironmentValues()))
    }

    func testResolutionPreservesStopOrderInterpolationAndMaximumHeadroom() {
        let gradient = Gradient(stops: [
            .init(color: Color(Color.ResolvedHDR(color.resolve(in: EnvironmentValues()), headroom: 4)), location: 3),
            .init(color: color, location: -2),
            .init(color: Color(Color.ResolvedHDR(color.resolve(in: EnvironmentValues()), headroom: 2)), location: -2)
        ])
        let resolved = gradient.resolve(in: EnvironmentValues())
        XCTAssertEqual(resolved.stops.map(\.location), [3, -2, -2])
        XCTAssertTrue(resolved.stops.allSatisfy { $0.interpolation == nil })
        XCTAssertEqual(resolved.headroom, 4)
        XCTAssertEqual(resolved.colorSpace, .perceptual)
        let device = gradient.colorSpace(.perceptual).colorSpace(.device).resolve(in: EnvironmentValues())
        XCTAssertEqual(device.stops, resolved.stops)
        XCTAssertEqual(device.headroom, resolved.headroom)
        XCTAssertEqual(device.colorSpace, .device)
        XCTAssertNil(Gradient(stops: []).resolve(in: EnvironmentValues()).headroom)
    }

    func testDirectAndErasedFallbackAndEmptyResultPreservation() {
        let gradient = Gradient(colors: [color, .white])
        for level in [-1, 0, 2] {
            var shape = _ShapeStyle_Shape(operation: .fallbackColor(level: level),
                                         result: .bool(true), environment: EnvironmentValues())
            gradient._apply(to: &shape)
            guard case let .color(result) = shape.result else { return XCTFail("Direct fallback must use the first stop.") }
            XCTAssertTrue(result.provider === color.provider)
            for style in [AnyShapeStyle(AnyGradient(gradient)), AnyShapeStyle(Gradient(stops: [])),
                          AnyShapeStyle(AnyGradient(Gradient(stops: [])))] {
                shape.result = .bool(true)
                style._apply(to: &shape)
                guard case .bool(true) = shape.result else { return XCTFail("Missing fallback must preserve the result.") }
            }
        }
    }

    func testPaintApplicationRetainsUnitOrAbsoluteGeometryAndOnlyOneLevel() throws {
        let gradient = Gradient(colors: [color, .white])
        for style in [AnyShapeStyle(gradient), AnyShapeStyle(AnyGradient(gradient))] {
            for bounds in [nil, CGRect(x: 6, y: 8, width: 20, height: 12),
                           CGRect(x: 6, y: 8, width: -20, height: -12)] as [CGRect?] {
                var shape = _ShapeStyle_Shape(operation: .resolveStyle(name: .foreground, levels: 0..<1),
                                             environment: EnvironmentValues(), bounds: bounds)
                Color.white._apply(to: &shape)
                shape.operation = .resolveStyle(name: .foreground, levels: 2..<5)
                style._apply(to: &shape)
                guard case let .pack(pack) = shape.result else { return XCTFail("Expected a paint pack.") }
                XCTAssertEqual(pack.styles.map { $0.key._level }, [0, 2])
                XCTAssertEqual(pack.styles[1].style.opacity, 0.25)
                guard case let .paint(paint) = pack.styles[1].style.fill else { return XCTFail("Expected retained typed paint.") }
                if bounds == nil {
                    let value = try XCTUnwrap(paint as? _AnyResolvedPaint<LinearGradient._Paint>).paint
                    XCTAssertEqual(value.startPoint, .top)
                    XCTAssertEqual(value.endPoint, .bottom)
                    XCTAssertEqual(value.gradient.stops[0].color.opacity, 1)
                } else {
                    let value = try XCTUnwrap(paint as? _AnyResolvedPaint<LinearGradient.AbsolutePaint>).paint
                    XCTAssertEqual(value.startPoint, CGPoint(x: bounds!.size.width > 0 ? 16 : -4, y: 8))
                    XCTAssertEqual(value.endPoint, CGPoint(x: bounds!.size.width > 0 ? 16 : -4,
                                                           y: bounds!.size.height > 0 ? 20 : -4))
                }
            }
        }
    }

    func testTaggedCodingPreservesNestedProviderKindsAndRejectsUnknownTag() throws {
        let gradient = Gradient(colors: [color, .white])
        let values = [AnyGradient(gradient), AnyGradient(gradient).colorSpace(.device),
                      gradient.colorSpace(.device), AnyGradient(gradient).colorSpace(.device).colorSpace(.perceptual)]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for value in values {
            let data = try encoder.encode(ProxyCodable(value))
            let decoded = try JSONDecoder().decode(ProxyCodable<AnyGradient>.self, from: data).wrappedValue
            XCTAssertEqual(decoded, value)
            XCTAssertEqual(try encoder.encode(ProxyCodable(decoded)), data)
        }
        let direct = try encoder.encode(ProxyCodable(gradient.colorSpace(.device)))
        let erased = try encoder.encode(ProxyCodable(AnyGradient(gradient).colorSpace(.device)))
        XCTAssertTrue(String(decoding: direct, as: UTF8.self).contains("\"base\":{\"gradient\""))
        XCTAssertTrue(String(decoding: erased, as: UTF8.self).contains("\"base\":{\"anyGradient\""))
        XCTAssertEqual(String(decoding: try encoder.encode(ProxyCodable(Gradient(stops: []))), as: UTF8.self), "{\"stops\":[]}")
        XCTAssertThrowsError(try JSONDecoder().decode(ProxyCodable<AnyGradient>.self,
            from: Data("{\"tag\":{\"unknown\":{}},\"value\":{}}".utf8)))
    }

    func testDisplayListRecordsTypedPaintAfterErasure() throws {
        var list = DisplayList()
        let style = AnyShapeStyle(AnyGradient(Gradient(colors: [color, .white])).colorSpace(.device))
        list.appendShapeItem(path: Path(CGRect(x: 0, y: 0, width: 20, height: 12)),
                             role: .fill, style: style, environment: EnvironmentValues())
        guard case let .shape(_, .some(.paint(paint)), _, _, _) = list.items.first?.command else {
            return XCTFail("Recording must keep the resolved paint.")
        }
        let value = try XCTUnwrap(paint as? _AnyResolvedPaint<LinearGradient._Paint>).paint
        XCTAssertEqual(value.gradient.colorSpace, .device)
        XCTAssertEqual(value.gradient.stops.count, 2)
    }
}
