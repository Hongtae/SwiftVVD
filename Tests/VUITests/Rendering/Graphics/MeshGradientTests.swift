import Foundation
import VVD
import XCTest
@testable import VUI

final class MeshGradientTests: XCTestCase {
    func testPublicCarriersAndGraphicsShadingPreserveValues() {
        let points: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0),
            SIMD2(0, 1), SIMD2(1, 1),
        ]
        let colors: [VUI.Color] = [.red, .green, .blue, .white]
        let mesh = MeshGradient(
            width: 2,
            height: 2,
            points: points,
            colors: colors,
            background: .black,
            smoothsColors: false,
            colorSpace: .perceptual
        )

        XCTAssertEqual(mesh.width, 2)
        XCTAssertEqual(mesh.height, 2)
        XCTAssertEqual(mesh.locations, MeshGradient.Locations.points(points))
        XCTAssertEqual(mesh.colors, MeshGradient.Colors.colors(colors))
        XCTAssertEqual(mesh.background, VUI.Color.black)
        XCTAssertFalse(mesh.smoothsColors)
        XCTAssertEqual(mesh.colorSpace, Gradient.ColorSpace.perceptual)
        XCTAssertNotEqual(mesh.colorSpace, Gradient.ColorSpace.device)

        let shading = GraphicsContext.Shading.meshGradient(mesh)
        guard case let .meshGradient(stored)? = shading.properties.first else {
            return XCTFail("expected mesh-gradient shading")
        }
        XCTAssertEqual(stored, mesh)

        var shape = _ShapeStyle_Shape(
            operation: .fallbackColor(level: 0),
            environment: EnvironmentValues()
        )
        mesh._apply(to: &shape)
        guard case let .meshGradient(applied)? =
            shape.resolvedShading?.properties.first
        else {
            return XCTFail("expected applied mesh-gradient shading")
        }
        XCTAssertEqual(applied, mesh)

        // ASSERTIONS meshGradientPublicSurfaceObserved
        // ASSERTIONS meshGradientFieldMetadataObserved
    }

    func testResolvedPaintAnimatableDataInterpolatesMeshPayload() throws {
        let source = MeshGradient(
            width: 2,
            height: 2,
            points: [
                SIMD2(0, 0), SIMD2(1, 0),
                SIMD2(0, 1), SIMD2(1, 1),
            ],
            colors: [.blue, .cyan, .green, .orange],
            background: .black,
            smoothsColors: true,
            colorSpace: .perceptual
        ).resolvePaint(in: EnvironmentValues())
        let target = MeshGradient(
            width: 2,
            height: 2,
            points: [
                SIMD2(0.2, 0.1), SIMD2(0.8, 0.1),
                SIMD2(0.2, 0.9), SIMD2(0.8, 0.9),
            ],
            colors: [.red, .orange, .yellow, .pink],
            background: .white,
            smoothsColors: true,
            colorSpace: .perceptual
        ).resolvePaint(in: EnvironmentValues())

        var delta = target.animatableData - source.animatableData
        delta.scale(by: 0.5)
        var midpoint = target
        midpoint.animatableData = source.animatableData + delta

        guard case let .points(points) = midpoint.locations else {
            return XCTFail("expected point locations")
        }
        XCTAssertEqual(points[0], SIMD2(0.1, 0.05))
        XCTAssertEqual(points[3], SIMD2(0.9, 0.95))
        XCTAssertEqual(
            midpoint.colors[0].linearRed,
            0.41017696,
            accuracy: 0.000_01
        )
        XCTAssertEqual(
            midpoint.colors[0].linearGreen,
            0.19103125,
            accuracy: 0.000_01
        )
        XCTAssertEqual(
            midpoint.colors[0].linearBlue,
            0.39165568,
            accuracy: 0.000_01
        )
        XCTAssertEqual(
            midpoint.background.linearRed,
            0.125,
            accuracy: 0.000_01
        )
        XCTAssertEqual(
            midpoint.background.linearGreen,
            0.125,
            accuracy: 0.000_01
        )
        XCTAssertEqual(
            midpoint.background.linearBlue,
            0.125,
            accuracy: 0.000_01
        )
        XCTAssertNil(midpoint.background.headroom)
        XCTAssertEqual(midpoint.width, target.width)
        XCTAssertEqual(midpoint.height, target.height)
        XCTAssertEqual(midpoint.flags, target.flags)

        // ASSERTIONS meshGradientResolvedPaintAnimationPathObserved
    }

    func testResolvedPaintPreservesObservedBezierVectorAndFlags() {
        func bezierPoint(_ base: Float) -> MeshGradient.BezierPoint {
            MeshGradient.BezierPoint(
                position: SIMD2(base, base + 1),
                leadingControlPoint: SIMD2(base + 2, base + 3),
                topControlPoint: SIMD2(base + 4, base + 5),
                trailingControlPoint: SIMD2(base + 6, base + 7),
                bottomControlPoint: SIMD2(base + 8, base + 9)
            )
        }

        let points = [
            bezierPoint(0),
            bezierPoint(10),
            bezierPoint(20),
            bezierPoint(30),
        ]
        func resolvedPaint(
            smoothsColors: Bool,
            colorSpace: Gradient.ColorSpace
        ) -> MeshGradient._Paint {
            MeshGradient(
                width: 2,
                height: 2,
                bezierPoints: points,
                colors: [.red, .green, .blue, .white],
                smoothsColors: smoothsColors,
                colorSpace: colorSpace
            ).resolvePaint(in: EnvironmentValues())
        }

        XCTAssertEqual(
            resolvedPaint(
                smoothsColors: false,
                colorSpace: .device
            ).flags.rawValue,
            0x00
        )
        XCTAssertEqual(
            resolvedPaint(
                smoothsColors: true,
                colorSpace: .device
            ).flags.rawValue,
            0x10
        )
        XCTAssertEqual(
            resolvedPaint(
                smoothsColors: false,
                colorSpace: .perceptual
            ).flags.rawValue,
            0x03
        )

        var paint = resolvedPaint(
            smoothsColors: true,
            colorSpace: .perceptual
        )
        XCTAssertEqual(paint.flags.rawValue, 0x13)
        XCTAssertEqual(
            Mirror(reflecting: paint).children.compactMap(\.label),
            [
                "locations",
                "colors",
                "background",
                "width",
                "height",
                "allowedDynamicRange",
                "flags",
            ]
        )
        var data = paint.animatableData
        XCTAssertEqual(
            data.first.elements,
            (0..<40).map(Float.init)
        )
        XCTAssertEqual(data.second.first.elements.count, 4)

        data.first.elements = data.first.elements.map { $0 + 100 }
        paint.animatableData = data
        guard case let .bezierPoints(updatedPoints) = paint.locations else {
            return XCTFail("expected Bezier locations")
        }
        XCTAssertEqual(updatedPoints[0], bezierPoint(100))
        XCTAssertEqual(updatedPoints[3], bezierPoint(130))

        // ASSERTIONS meshGradientResolvedPaintAnimationPathObserved
        // ASSERTIONS meshGradientHDRDynamicRangeResolutionObserved
    }

    func testResolvedPaintUsesObservedHDRDynamicRangeResolution() {
        let standardColor = VUI.Color.red
        let standard = makeSolidMesh(color: standardColor)
            .resolvePaint(in: EnvironmentValues())
        XCTAssertEqual(standard.allowedDynamicRange, .standard)

        let base = standardColor.resolve(in: EnvironmentValues())
        let hdrColor = VUI.Color(
            VUI.Color.ResolvedHDR(base, headroom: 4)
        )
        XCTAssertEqual(
            hdrColor.resolveHDR(in: EnvironmentValues()).headroom,
            4
        )

        var environment = EnvironmentValues()
        let defaultHDR = makeSolidMesh(color: hdrColor)
            .resolvePaint(in: environment)
        XCTAssertEqual(defaultHDR.allowedDynamicRange, .high)

        environment.allowedDynamicRange = .constrainedHigh
        let constrained = makeSolidMesh(color: hdrColor)
            .resolvePaint(in: environment)
        XCTAssertEqual(constrained.allowedDynamicRange, .constrainedHigh)

        environment.allowedDynamicRange = .high
        environment.maxAllowedDynamicRange = .constrainedHigh
        let capped = makeSolidMesh(color: hdrColor)
            .resolvePaint(in: environment)
        XCTAssertEqual(capped.allowedDynamicRange, .constrainedHigh)

        environment.allowedDynamicRange = .standard
        let explicitlyStandard = makeSolidMesh(color: hdrColor)
            .resolvePaint(in: environment)
        XCTAssertEqual(explicitlyStandard.allowedDynamicRange, .standard)

        let hdrBackground = MeshGradient(
            width: 2,
            height: 2,
            points: [
                SIMD2(0, 0), SIMD2(1, 0),
                SIMD2(0, 1), SIMD2(1, 1),
            ],
            colors: [.red, .red, .red, .red],
            background: hdrColor
        ).resolvePaint(in: EnvironmentValues())
        XCTAssertEqual(hdrBackground.allowedDynamicRange, .high)

        // ASSERTIONS meshGradientHDRDynamicRangeResolutionObserved
    }

    func testDirectShapeStyleResolverTracksUsedDynamicRangeValues() throws {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)

        try context.withCurrent {
            let phase = graph.makeInput(value: Phase())
            let time = graph.makeInput(value: Time.zero)
            let transaction = graph.makeInput(value: Transaction())
            let base = VUI.Color.red.resolve(in: EnvironmentValues())
            let hdrColor = VUI.Color(
                VUI.Color.ResolvedHDR(base, headroom: 4)
            )
            let mesh = graph.makeInput(value: makeSolidMesh(color: hdrColor))
            var environment = EnvironmentValues()
            environment.allowedDynamicRange = .high
            let environmentInput = graph.makeInput(value: environment)
            let tracker = _PropertyListTracker()
            let output = graph.makeStatefulRule(
                DirectShapeStyleResolver(
                    style: OptionalAttribute(mesh),
                    environment: environmentInput,
                    role: .fill,
                    animationsDisabled: false,
                    helper: AnimatableAttributeHelper(
                        _phase: phase,
                        _time: time,
                        _transaction: transaction
                    ),
                    tracker: tracker
                )
            )

            func dynamicRange(
                _ pack: _ShapeStyle_Pack
            ) throws -> VUI.Image.DynamicRange {
                guard case let .paint(paint) = pack.styles.first?.style.fill,
                      let paint = paint as? _AnyResolvedPaint<MeshGradient._Paint> else {
                    throw ShapeStyleResolverTestError.missingMeshPaint
                }
                return paint.paint.allowedDynamicRange
            }

            XCTAssertEqual(try dynamicRange(output.value), .high)
            XCTAssertEqual(output.value.styles.count, 1)

            var standardEnvironment = environment
            standardEnvironment.allowedDynamicRange = .standard
            XCTAssertTrue(
                tracker.hasDifferentUsedValues(standardEnvironment._plist)
            )
            environmentInput.setValue(standardEnvironment)
            XCTAssertEqual(try dynamicRange(output.value), .standard)

            let standardTracker = _PropertyListTracker()
            let standardMesh = graph.makeInput(
                value: makeSolidMesh(color: .red)
            )
            let standardOutput = graph.makeStatefulRule(
                DirectShapeStyleResolver(
                    style: OptionalAttribute(standardMesh),
                    environment: environmentInput,
                    role: .fill,
                    animationsDisabled: false,
                    helper: AnimatableAttributeHelper(
                        _phase: phase,
                        _time: time,
                        _transaction: transaction
                    ),
                    tracker: standardTracker
                )
            )
            XCTAssertEqual(try dynamicRange(standardOutput.value), .standard)

            var unusedRangeChange = standardEnvironment
            unusedRangeChange.allowedDynamicRange = .constrainedHigh
            XCTAssertFalse(
                standardTracker.hasDifferentUsedValues(
                    unusedRangeChange._plist
                )
            )

            // ASSERTIONS shapeStyleResolverTrackedEnvironmentObserved
            // ASSERTIONS shapeStylePackSingleFillOpacityNoopObserved
        }
    }

    func testDirectShapeStyleResolverKeepsSamplingAfterPlainActiveTargetChange() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let phase = graph.makeInput(value: Phase())
                let time = graph.makeInput(value: Time.zero)
                let transaction = graph.makeInput(value: Transaction())
                let mesh = graph.makeInput(value: makeShiftedMesh(offset: 0))
                let environment = graph.makeInput(value: EnvironmentValues())
                let output = graph.makeStatefulRule(
                    DirectShapeStyleResolver(
                        style: OptionalAttribute(mesh),
                        environment: environment,
                        role: .fill,
                        animationsDisabled: false,
                        helper: AnimatableAttributeHelper(
                            _phase: phase,
                            _time: time,
                            _transaction: transaction
                        )
                    )
                )

                func firstPointX(_ pack: _ShapeStyle_Pack) throws -> Float {
                    guard case let .paint(paint) = pack.styles.first?.style.fill,
                          let paint = paint as? _AnyResolvedPaint<MeshGradient._Paint>,
                          case let .points(points) = paint.paint.locations,
                          let first = points.first else {
                        throw ShapeStyleResolverTestError.missingMeshPaint
                    }
                    return first.x
                }

                XCTAssertEqual(try firstPointX(output.value), 0, accuracy: 0.000_001)

                transaction.setValue(
                    Transaction(animation: .linear(duration: 1))
                )
                mesh.setValue(makeShiftedMesh(offset: 0.4))
                _ = output.value

                time.setValue(Time(seconds: 0.25))
                _ = output.value
                time.setValue(Time(seconds: 0.5))
                _ = output.value
                time.setValue(Time(seconds: 0.75))
                let animatedSample = try firstPointX(output.value)
                XCTAssertGreaterThan(animatedSample, 0)
                XCTAssertLessThan(animatedSample, 0.4)

                transaction.setValue(Transaction())
                mesh.setValue(makeShiftedMesh(offset: 0.8))
                let plainRetargetSample = try firstPointX(output.value)
                XCTAssertLessThan(plainRetargetSample, 0.8)

                time.setValue(Time(seconds: 1))
                let laterSample = try firstPointX(output.value)
                XCTAssertGreaterThan(laterSample, plainRetargetSample)
                XCTAssertLessThan(laterSample, 0.8)

                time.setValue(Time(seconds: 3))
                XCTAssertEqual(
                    try firstPointX(output.value),
                    0.8,
                    accuracy: 0.000_1
                )

                // ASSERTIONS helperModelDataGateObserved
            }
        }
    }

    private func makeSolidMesh(color: VUI.Color) -> MeshGradient {
        MeshGradient(
            width: 2,
            height: 2,
            points: [
                SIMD2(0, 0), SIMD2(1, 0),
                SIMD2(0, 1), SIMD2(1, 1),
            ],
            colors: [color, color, color, color]
        )
    }

    private func makeShiftedMesh(offset: Float) -> MeshGradient {
        MeshGradient(
            width: 2,
            height: 2,
            points: [
                SIMD2(offset, 0), SIMD2(1, 0),
                SIMD2(offset, 1), SIMD2(1, 1),
            ],
            colors: [.red, .green, .blue, .white]
        )
    }

    func testMetalRendererProducesObservedDeviceAndInvalidLocationPixels() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let resolved: [VUI.Color.Resolved] = [
            .init(colorSpace: .sRGB, red: 1, green: 0, blue: 0),
            .init(colorSpace: .sRGB, red: 0, green: 1, blue: 0),
            .init(colorSpace: .sRGB, red: 0, green: 0, blue: 1),
            .init(colorSpace: .sRGB, red: 1, green: 1, blue: 1),
        ]
        let points: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0),
            SIMD2(0, 1), SIMD2(1, 1),
        ]

        let valid = try render(
            MeshGradient(
                width: 2,
                height: 2,
                points: points,
                resolvedColors: resolved,
                smoothsColors: false
            ),
            deviceContext: deviceContext
        )
        let topLeft = valid.pixel(x: 1, y: 1)
        let topRight = valid.pixel(x: 62, y: 1)
        let bottomLeft = valid.pixel(x: 1, y: 62)
        let bottomRight = valid.pixel(x: 62, y: 62)
        let center = valid.pixel(x: 32, y: 32)
        XCTAssertGreaterThan(topLeft.r, 230)
        XCTAssertLessThan(topLeft.g, 24)
        XCTAssertLessThan(topLeft.b, 24)
        XCTAssertGreaterThan(topRight.g, 230)
        XCTAssertLessThan(topRight.r, 24)
        XCTAssertLessThan(topRight.b, 24)
        XCTAssertGreaterThan(bottomLeft.b, 230)
        XCTAssertLessThan(bottomLeft.r, 24)
        XCTAssertLessThan(bottomLeft.g, 24)
        XCTAssertGreaterThan(bottomRight.r, 230)
        XCTAssertGreaterThan(bottomRight.g, 230)
        XCTAssertGreaterThan(bottomRight.b, 230)
        XCTAssertEqual(center.r, 128, accuracy: 8)
        XCTAssertEqual(center.g, 128, accuracy: 8)
        XCTAssertEqual(center.b, 128, accuracy: 8)
        XCTAssertEqual(center.a, 255)

        let smoothed = try render(
            MeshGradient(
                width: 2,
                height: 2,
                points: points,
                resolvedColors: resolved,
                smoothsColors: true
            ),
            deviceContext: deviceContext
        ).pixel(x: 16, y: 16)
        XCTAssertEqual(smoothed.r, 181, accuracy: 10)
        XCTAssertEqual(smoothed.g, 42, accuracy: 10)
        XCTAssertEqual(smoothed.b, 42, accuracy: 10)

        let perceptual = try render(
            MeshGradient(
                width: 2,
                height: 2,
                points: points,
                resolvedColors: resolved,
                smoothsColors: false,
                colorSpace: .perceptual
            ),
            deviceContext: deviceContext
        ).pixel(x: 16, y: 16)
        XCTAssertEqual(perceptual.r, 195, accuracy: 12)
        XCTAssertEqual(perceptual.g, 127, accuracy: 12)
        XCTAssertEqual(perceptual.b, 115, accuracy: 12)

        let invalid = try render(
            MeshGradient(
                width: 2,
                height: 2,
                points: Array(points.dropLast()),
                resolvedColors: resolved,
                background: .yellow,
                smoothsColors: false
            ),
            deviceContext: deviceContext
        )
        let background = invalid.pixel(x: 32, y: 32)
        XCTAssertEqual(background.r, 255, accuracy: 2)
        XCTAssertEqual(background.g, 204, accuracy: 2)
        XCTAssertEqual(background.b, 0, accuracy: 2)
        XCTAssertEqual(background.a, 255)

        let curvedPoints = [
            MeshGradient.BezierPoint(
                position: SIMD2(0.1, 0.1),
                leadingControlPoint: SIMD2(0.1, 0.1),
                topControlPoint: SIMD2(0.1, 0.1),
                trailingControlPoint: SIMD2(0.35, 0.35),
                bottomControlPoint: SIMD2(0.35, 0.35)
            ),
            MeshGradient.BezierPoint(
                position: SIMD2(0.9, 0.1),
                leadingControlPoint: SIMD2(0.65, 0.35),
                topControlPoint: SIMD2(0.9, 0.1),
                trailingControlPoint: SIMD2(0.9, 0.1),
                bottomControlPoint: SIMD2(0.65, 0.35)
            ),
            MeshGradient.BezierPoint(
                position: SIMD2(0.1, 0.9),
                leadingControlPoint: SIMD2(0.1, 0.9),
                topControlPoint: SIMD2(0.35, 0.65),
                trailingControlPoint: SIMD2(0.35, 0.65),
                bottomControlPoint: SIMD2(0.1, 0.9)
            ),
            MeshGradient.BezierPoint(
                position: SIMD2(0.9, 0.9),
                leadingControlPoint: SIMD2(0.65, 0.65),
                topControlPoint: SIMD2(0.65, 0.65),
                trailingControlPoint: SIMD2(0.9, 0.9),
                bottomControlPoint: SIMD2(0.9, 0.9)
            ),
        ]
        let curvedPixels = try render(
            MeshGradient(
                width: 2,
                height: 2,
                bezierPoints: curvedPoints,
                colors: [.white, .white, .white, .white],
                smoothsColors: false
            ),
            deviceContext: deviceContext
        )
        let curved = curvedPixels.coverage(alphaThreshold: 128)
        XCTAssertEqual(curved.count, 1_072, accuracy: 96)
        XCTAssertEqual(curved.minX, 6, accuracy: 5)
        XCTAssertEqual(curved.minY, 6, accuracy: 5)
        XCTAssertEqual(curved.maxX, 57, accuracy: 5)
        XCTAssertEqual(curved.maxY, 57, accuracy: 5)

        // ASSERTIONS meshGradientVisualRuntimeObserved
    }

    func testDisplayListInterpolatorMixesCompatibleMeshPayloads() throws {
        let bounds = CGRect(x: 0, y: 0, width: 40, height: 30)
        let sourcePoints: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0),
            SIMD2(0, 1), SIMD2(1, 1),
        ]
        let targetPoints = sourcePoints.map { $0 + SIMD2(0.2, 0.1) }
        let sourceColors: [VUI.Color.Resolved] = [
            .init(colorSpace: .sRGBLinear, red: 1, green: 0, blue: 0),
            .init(colorSpace: .sRGBLinear, red: 0, green: 1, blue: 0),
            .init(colorSpace: .sRGBLinear, red: 0, green: 0, blue: 1),
            .init(colorSpace: .sRGBLinear, red: 1, green: 1, blue: 1),
        ]
        let targetColors: [VUI.Color.Resolved] = [
            .init(colorSpace: .sRGBLinear, red: 0, green: 0, blue: 1),
            .init(colorSpace: .sRGBLinear, red: 1, green: 0, blue: 0),
            .init(colorSpace: .sRGBLinear, red: 0, green: 1, blue: 0),
            .init(colorSpace: .sRGBLinear, red: 0, green: 0, blue: 0),
        ]
        let sourceMesh = MeshGradient(
            width: 2,
            height: 2,
            points: sourcePoints,
            resolvedColors: sourceColors,
            background: .clear,
            smoothsColors: false
        )
        let targetMesh = MeshGradient(
            width: 2,
            height: 2,
            points: targetPoints,
            resolvedColors: targetColors,
            background: .white,
            smoothsColors: false
        )
        var source = DisplayList()
        source.appendShapeItem(
            path: Path(bounds),
            role: .fill,
            style: sourceMesh,
            bounds: bounds
        )
        var target = DisplayList()
        target.appendShapeItem(
            path: Path(bounds),
            role: .fill,
            style: targetMesh,
            bounds: bounds
        )

        let midpoint = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [:]
        ).copyContents(withProgress: 0.5)
        XCTAssertEqual(midpoint.items.count, 1)
        guard case let .meshGradient(recorded)? = midpoint.itemRecords.first?.shapeStyle,
              case let .content(content) = midpoint.items[0].value,
              case let .shape(shape) = content.value,
              case let .meshGradient(rendered)? = shape.shading.properties.first else {
            return XCTFail("compatible mesh should remain one typed mixed shape")
        }
        XCTAssertEqual(recorded, rendered)
        guard case let .points(points) = rendered.locations,
              case let .resolvedColors(colors) = rendered.colors else {
            return XCTFail("expected resolved midpoint mesh payload")
        }
        XCTAssertEqual(points[0], SIMD2(0.1, 0.05))
        XCTAssertEqual(points[3], SIMD2(1.1, 1.05))
        XCTAssertEqual(colors[0].linearRed, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(colors[0].linearGreen, 0, accuracy: 0.000_001)
        XCTAssertEqual(colors[0].linearBlue, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(colors[0].opacity, 1, accuracy: 0.000_001)

        var incompatible = DisplayList()
        incompatible.appendShapeItem(
            path: Path(bounds),
            role: .fill,
            style: MeshGradient(
                width: 2,
                height: 2,
                points: targetPoints,
                resolvedColors: targetColors,
                smoothsColors: true
            ),
            bounds: bounds
        )
        XCTAssertEqual(
            RBDisplayListInterpolator(
                from: source,
                to: incompatible,
                options: [:]
            ).copyContents(withProgress: 0.5).itemRecords.first?.effectKind,
            .crossFade
        )

        // ASSERTIONS rbMeshGradientFillRuntimeObserved
        // ASSERTIONS rbMeshGradientFillMixSemanticsObserved
    }

    private struct Pixel {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }

    private struct Pixels {
        var bytes: [UInt8]
        var width: Int

        func pixel(x: Int, y: Int) -> Pixel {
            let offset = (y * width + x) * 4
            return Pixel(
                r: bytes[offset],
                g: bytes[offset + 1],
                b: bytes[offset + 2],
                a: bytes[offset + 3]
            )
        }

        func coverage(alphaThreshold: UInt8) -> (
            count: Int,
            minX: Int,
            minY: Int,
            maxX: Int,
            maxY: Int
        ) {
            var count = 0
            var minX = Int.max
            var minY = Int.max
            var maxX = Int.min
            var maxY = Int.min
            let height = bytes.count / (width * 4)
            for y in 0..<height {
                for x in 0..<width where pixel(x: x, y: y).a >= alphaThreshold {
                    count += 1
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
            return (count, minX, minY, maxX, maxY)
        }
    }

    private func render(
        _ mesh: MeshGradient,
        deviceContext: GraphicsDeviceContext
    ) throws -> Pixels {
        let width = 64
        let height = 64
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(),
            environment: EnvironmentValues(),
            viewport: CGRect(x: 0, y: 0, width: width, height: height),
            contentOffset: .zero,
            contentScaleFactor: 1,
            resolution: CGSize(width: width, height: height),
            commandBuffer: commandBuffer
        ))
        context.clear(with: .clear)
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        context.fill(Path(frame), with: .meshGradient(mesh))
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let count = width * height * 4
        return Pixels(
            bytes: Array(UnsafeRawBufferPointer(start: pointer, count: count)),
            width: width
        )
    }

    private func waitForCompletion(_ commandBuffer: CommandBuffer) throws {
        let condition = NSCondition()
        var completed = false
        commandBuffer.addCompletedHandler { _ in
            condition.lock()
            completed = true
            condition.broadcast()
            condition.unlock()
        }
        condition.lock()
        defer { condition.unlock() }
        XCTAssertTrue(commandBuffer.commit())
        let timeout = Date(timeIntervalSinceNow: 5)
        while !completed {
            if !condition.wait(until: timeout) {
                XCTFail("GPU command buffer timed out")
                break
            }
        }
    }
}

private enum ShapeStyleResolverTestError: Error {
    case missingMeshPaint
}
