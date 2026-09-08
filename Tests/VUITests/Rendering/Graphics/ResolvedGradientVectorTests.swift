import XCTest
@testable import VUI

final class ResolvedGradientVectorTests: XCTestCase {
    private let curveA = BezierTimingFunction<Float>(p1x: 0.1, p1y: 0.2, p2x: 0.7, p2y: 0.8)
    private let curveB = BezierTimingFunction<Float>(p1x: 0.3, p1y: 0.4, p2x: 0.5, p2y: 0.6)

    private func gradient(_ locations: [CGFloat] = [0, 1],
                          curve: BezierTimingFunction<Float>? = nil,
                          space: ResolvedGradient.ColorSpace = .linear,
                          headroom: Float? = nil) -> ResolvedGradient {
        let colors = [Color.Resolved(colorSpace: .sRGBLinear, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.5),
                      Color.Resolved(colorSpace: .sRGBLinear, red: 1, green: 0.25, blue: 0)]
        return ResolvedGradient(stops: locations.enumerated().map {
            .init(color: colors[$0.offset % 2], location: $0.element, interpolation: curve)
        }, colorSpace: space, headroom: headroom)
    }

    private func field(_ value: Any, _ name: String) -> Any {
        Mirror(reflecting: value).children.first { $0.label == name }!.value
    }

    private func colors(_ vector: ResolvedGradientVector) -> [[Float]] {
        Mirror(reflecting: field(vector, "stops")).children.map {
            let color = field($0.value, "color") as! ResolvedGradient.ColorSpace.InterpolatableColor
            return [color.r, color.g, color.b, color.a]
        }
    }

    private func buffer(_ vector: ResolvedGradientVector) -> UInt {
        func address<C: Collection>(_ array: C) -> UInt {
            array.withContiguousStorageIfAvailable { UInt(bitPattern: $0.baseAddress) }!
        }
        return _openExistential(field(vector, "stops") as! any Collection, do: address)
    }

    private func decoded(_ vector: ResolvedGradientVector) -> ResolvedGradient {
        var result = gradient()
        result.animatableData = vector
        return result
    }

    private func assertComponents(_ actual: [Float], _ expected: [Float],
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actual, expected) in zip(actual, expected) {
            XCTAssertEqual(actual, expected, accuracy: 0.000002, file: file, line: line)
        }
    }

    func testColorSpacesPremultiplyAndPreserveExtendedComponents() {
        let input = Color.Resolved(colorSpace: .sRGBLinear, red: 2, green: -1, blue: 0.5, opacity: -0.5)
        let cases: [(ResolvedGradient.ColorSpace, [Float])] = [
            (.device, [-0.676628, 0.5, -0.36767846, -0.5]),
            (.linear, [-1, 0.5, -0.25, -0.5]),
            (.perceptual, [-0.3397841, 0.29395014, -0.29713732, -0.5])
        ]
        for (space, expected) in cases {
            let vector = space.convertIn(input)
            assertComponents([vector.r, vector.g, vector.b, vector.a], expected)
            let roundTrip = space.convertOut(vector)
            assertComponents([roundTrip.linearRed, roundTrip.linearGreen, roundTrip.linearBlue, roundTrip.opacity], [2, -1, 0.5, -0.5])
        }
        let color = gradient().stops[0].color
        let vector = ResolvedGradient.ColorSpace.perceptual.convertIn(color)
        let data = color.animatableData
        assertComponents([data.first, data.second.first, data.second.second.first, data.second.second.second],
                         [vector.r * 128, vector.g * 128, vector.b * 128, vector.a * 128])
    }

    func testZeroAlphaConversionDoesNotDiscardColor() {
        let cases: [(ResolvedGradient.ColorSpace, [Float], [Float])] = [
            (.device, [0.26854935, 0.36767846, 0.4404125], [0.05862074, 0.11133158, 0.16297266]),
            (.linear, [0.125, 0.25, 0.375], [0.125, 0.25, 0.375]),
            (.perceptual, [0.3713894, 0.389814, 0.42985642], [0.031250026, 0.062499993, 0.09375])
        ]
        for (space, input, expected) in cases {
            let output = space.convertOut(.init(r: input[0], g: input[1], b: input[2], a: 0))
            assertComponents([output.linearRed, output.linearGreen, output.linearBlue], expected)
            XCTAssertEqual(output.opacity, 0)
        }
    }

    func testSetterPreservesMetadataAndReusesUniqueStorage() {
        let original = gradient([0, 1], curve: curveA, space: .device, headroom: 8)
        let incoming = gradient([0.75], curve: curveB, space: .perceptual, headroom: 2).animatableData
        var copy = original
        let originalAddress = original.stops.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
        copy.animatableData = incoming
        let detachedAddress = copy.stops.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
        XCTAssertNotEqual(originalAddress, detachedAddress)
        XCTAssertEqual(copy.colorSpace, .device)
        XCTAssertEqual(copy.headroom, 8)
        XCTAssertEqual(copy.stops.map(\.location), [0.75])
        XCTAssertEqual(copy.stops[0].interpolation, curveB)
        copy.animatableData = incoming
        XCTAssertEqual(copy.stops.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }, detachedAddress)
        copy.animatableData = .zero
        XCTAssertTrue(copy.stops.isEmpty)
        XCTAssertEqual(copy.stops.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }, detachedAddress)
        XCTAssertEqual(copy.colorSpace, .device)
        XCTAssertEqual(copy.headroom, 8)
        withExtendedLifetime(original) { XCTAssertEqual(original.stops.map(\.location), [0, 1]) }
    }

    func testEmptyAdditionSharesAndMutationDetaches() {
        let original = gradient(curve: curveA, headroom: 4).animatableData
        var adopted = ResolvedGradientVector.zero + original
        XCTAssertEqual(buffer(adopted), buffer(original))
        XCTAssertEqual(adopted, original)
        adopted.scale(by: 0.5)
        XCTAssertNotEqual(buffer(adopted), buffer(original))
        XCTAssertEqual(decoded(adopted).stops.map(\.interpolation), [curveA, curveA])
        assertComponents(colors(original)[0], [0.125, 0.25, 0.375, 0.5])
        assertComponents(colors(adopted)[0], [0.0625, 0.125, 0.1875, 0.25])
        let negated = ResolvedGradientVector.zero - original
        XCTAssertTrue(decoded(negated).stops.allSatisfy { $0.interpolation == nil })
        XCTAssertEqual(negated.headroom, 4)
        let address = buffer(adopted)
        adopted += .zero
        XCTAssertEqual(buffer(adopted), address)
        XCTAssertEqual(adopted.magnitudeSquared, 0.6328125)
        XCTAssertEqual(original.magnitudeSquared, 2.53125)
    }

    func testSameGridCurveSubtractionScalesTheReceiver() {
        let a = gradient(curve: curveA).animatableData
        let b = gradient(curve: curveB).animatableData
        let difference = a - b
        assertComponents(colors(difference)[0], [0, 0, 0, 0])
        let curve = decoded(difference).stops[0].interpolation!
        assertComponents([curve.p1x, curve.p1y, curve.p2x, curve.p2y], [0.2, 0.2, -0.2, -0.2])
        let nilCurve = gradient().animatableData
        let mixed = decoded(nilCurve - a).stops[0].interpolation!
        assertComponents([mixed.p1x, mixed.p1y, mixed.p2x, mixed.p2y], [0.1, 0.2, -0.3, -0.2])
        XCTAssertTrue(decoded(nilCurve + nilCurve).stops.allSatisfy { $0.interpolation == nil })
    }

    func testDifferentGridsMergeColorsAndKeepOnlyReceiverCurves() {
        let merged = gradient(curve: curveA).animatableData + gradient([0.25, 0.75], curve: curveB).animatableData
        XCTAssertEqual(decoded(merged).stops.map(\.location), [0, 0.25, 0.75, 1])
        XCTAssertEqual(decoded(merged).stops.map(\.interpolation), [curveA, nil, nil, curveA])
        let expected: [[Float]] = [[0.25, 0.5, 0.75, 1], [0.46875, 0.5, 0.65625, 1.125],
                                   [1.78125, 0.5, 0.09375, 1.875], [2, 0.5, 0, 2]]
        for (actual, expected) in zip(colors(merged), expected) { assertComponents(actual, expected) }
    }

    func testDuplicateLocationsAreConsumedInOrderWithoutSorting() {
        let merged = gradient([0, 0, 1], curve: curveA).animatableData - gradient([0, 1, 1], curve: curveB).animatableData
        XCTAssertEqual(decoded(merged).stops.map(\.location), [0, 0, 1, 1])
        XCTAssertEqual(decoded(merged).stops.map(\.interpolation), [curveA, curveA, curveA, nil])
        let expected: [[Float]] = [[0, 0, 0, 0], [0.875, 0, -0.375, 0.5], [-0.875, 0, 0.375, -0.5], [0, 0, 0, 0]]
        for (actual, expected) in zip(colors(merged), expected) { assertComponents(actual, expected) }
        let unsorted = gradient([0.2, 0.8]).animatableData + gradient([0.8, 0.2]).animatableData
        XCTAssertEqual(decoded(unsorted).stops.map(\.location), [0.2, 0.8, 0.2])
    }

    func testNonemptyArithmeticUsesRightColorSpaceAndLeftHeadroom() {
        let lhs = gradient(space: .linear, headroom: 8).animatableData
        let rhs = gradient(space: .device, headroom: 2).animatableData
        let sum = lhs + rhs
        XCTAssertEqual(sum.colorSpace, .device)
        XCTAssertEqual(sum.headroom, 8)
        assertComponents(colors(sum)[0], [0.5370987, 0.7353569, 0.880825, 1])
        var converted = lhs
        let originalAddress = buffer(converted)
        converted.setColorSpace(.linear)
        XCTAssertEqual(buffer(converted), originalAddress)
        converted.setColorSpace(.perceptual)
        XCTAssertNotEqual(buffer(converted), originalAddress)
        XCTAssertEqual(converted.headroom, 8)
        XCTAssertNotEqual(converted, lhs)
        withExtendedLifetime(lhs) {}
    }

    func testUnitAndAbsolutePaintCoordinateWeightsAndMetadata() {
        var unit = LinearGradient._Paint(gradient: gradient(headroom: 8), startPoint: .init(x: 0.25, y: 0.5),
                                         endPoint: .init(x: 0.75, y: 1), allowedDynamicRange: .high)
        var absolute = LinearGradient.AbsolutePaint(gradient: unit.gradient, startPoint: CGPoint(x: 32, y: 64),
                                                    endPoint: CGPoint(x: 96, y: 128), allowedDynamicRange: .high)
        XCTAssertEqual(unit.animatableData, absolute.animatableData)
        unit.animatableData = unit.animatableData.scaled(by: 0.5)
        absolute.animatableData = absolute.animatableData.scaled(by: 0.5)
        XCTAssertEqual(unit.startPoint, UnitPoint(x: 0.125, y: 0.25))
        XCTAssertEqual(absolute.startPoint, CGPoint(x: 16, y: 32))
        XCTAssertEqual(unit.gradient.stops[0].color.opacity, 0.25)
        XCTAssertEqual(unit.gradient.headroom, 8)
        XCTAssertEqual(unit.allowedDynamicRange, .high)
        XCTAssertEqual(absolute.allowedDynamicRange, .high)
    }

    func testPackAnimatesUnitPaintAndPreservesAbsolutePaintIdentity() throws {
        for bounds in [nil, CGRect(x: 2, y: 4, width: 8, height: 16)] {
            var shape = _ShapeStyle_Shape(operation: .resolveStyle(name: .foreground, levels: 0..<1),
                                         environment: EnvironmentValues(), bounds: bounds)
            LinearGradient(colors: [.white, .black], startPoint: .zero, endPoint: .bottomTrailing)._apply(to: &shape)
            guard case var .pack(pack) = shape.result,
                  case let .paint(original) = pack.styles[0].style.fill else { return XCTFail("Missing paint.") }
            let originalFill = pack.styles[0].style.fill.animatableData
            pack.animatableData = pack.animatableData.scaled(by: 0.5)
            guard case let .paint(updated) = pack.styles[0].style.fill else { return XCTFail("Missing updated paint.") }
            if bounds == nil {
                guard case .linearGradient = originalFill else { return XCTFail("Missing gradient data.") }
                XCTAssertFalse(original === updated)
                let paint = try XCTUnwrap(updated as? _AnyResolvedPaint<LinearGradient._Paint>).paint
                XCTAssertEqual(paint.endPoint, UnitPoint(x: 0.5, y: 0.5))
                XCTAssertEqual(paint.gradient.stops[0].color.opacity, 0.5)
                var fill = _ShapeStyle_Pack.Fill.paint(original)
                fill.animatableData = .zero
                XCTAssertEqual(fill, .paint(original))
            } else {
                XCTAssertEqual(originalFill, .zero)
                XCTAssertTrue(original === updated)
            }
        }
    }

    func testShapeStyleResolverSamplesGradientCoordinatesAndColor() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(),
                             rendererHost: rendererHost, requestedOutputs: [])
        rendererHost.storage = host
        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let phase = graph.makeInput(value: _GraphInputs.Phase())
                let time = graph.makeInput(value: Time.zero)
                let transaction = graph.makeInput(value: Transaction())
                let style = graph.makeInput(value: LinearGradient(colors: [.black, .black], startPoint: .zero, endPoint: .bottomTrailing))
                let environment = graph.makeInput(value: EnvironmentValues())
                let output = graph.makeStatefulRule(ShapeStyleResolver(
                    style: OptionalAttribute(style), environment: environment, role: .fill, animationsDisabled: false,
                    helper: AnimatableAttributeHelper(_phase: phase, _time: time, _transaction: transaction)))
                func paint() throws -> LinearGradient._Paint {
                    guard case let .paint(paint) = output.value.styles.first?.style.fill else {
                        throw NSError(domain: "MissingPaint", code: 1)
                    }
                    return try XCTUnwrap(paint as? _AnyResolvedPaint<LinearGradient._Paint>).paint
                }
                XCTAssertEqual(try paint().startPoint.x, 0)
                transaction.setValue(Transaction(animation: .linear(duration: 1)))
                style.setValue(LinearGradient(colors: [.white, .white], startPoint: .init(x: 0.5, y: 0.5), endPoint: .bottomTrailing))
                _ = output.value
                for seconds in [0.25, 0.5, 0.75] { time.setValue(Time(seconds: seconds)); _ = output.value }
                let sample = try paint()
                XCTAssertGreaterThan(sample.startPoint.x, 0)
                XCTAssertLessThan(sample.startPoint.x, 0.5)
                XCTAssertGreaterThan(sample.gradient.stops[0].color.linearRed, 0)
                XCTAssertLessThan(sample.gradient.stops[0].color.linearRed, 1)
                time.setValue(Time(seconds: 3))
                XCTAssertEqual(try paint().startPoint.x, 0.5, accuracy: 0.0001)
                XCTAssertEqual(try paint().gradient.stops[0].color.linearRed, 1, accuracy: 0.000002)
            }
        }
    }
}
