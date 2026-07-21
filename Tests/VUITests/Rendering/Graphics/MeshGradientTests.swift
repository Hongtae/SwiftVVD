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

        var shape = _ShapeStyle_Shape()
        mesh._apply(to: &shape)
        guard case let .meshGradient(applied)? = shape.shading?.properties.first else {
            return XCTFail("expected applied mesh-gradient shading")
        }
        XCTAssertEqual(applied, mesh)

        // ASSERTIONS meshGradientPublicSurfaceObserved
        // ASSERTIONS meshGradientFieldMetadataObserved
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
