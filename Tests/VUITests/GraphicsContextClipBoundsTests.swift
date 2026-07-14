import XCTest
import VVD
@testable import VUI

final class GraphicsContextClipBoundsTests: XCTestCase {
    private struct PixelDigest {
        var count = 0
        var alpha = 0
        var clipBounds = CGRect.null
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

    private func renderLayerClip(
        deviceContext: GraphicsDeviceContext,
        opacity: Double,
        inverse: Bool,
        pathClip: CGRect? = nil,
        maskOpacity: Double = 1
    ) throws -> PixelDigest {
        let width = 8
        let height = 8
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        var context = try XCTUnwrap(
            GraphicsContext(
                sceneResources: SceneResources(),
                environment: EnvironmentValues(),
                viewport: CGRect(x: 0, y: 0, width: width, height: height),
                contentOffset: .zero,
                contentScaleFactor: 1,
                resolution: CGSize(width: width, height: height),
                commandBuffer: commandBuffer
            )
        )
        context.clear(with: .clear)
        if let pathClip {
            context.clip(to: Path(pathClip))
        }
        context.clipToLayer(
            opacity: opacity,
            options: inverse ? .inverse : []
        ) { mask in
            mask.opacity = maskOpacity
            mask.fill(
                Path(CGRect(x: 2, y: 2, width: 4, height: 3)),
                with: .color(.white)
            )
        }
        let clipBounds = context.clipBoundingRect
        context.fill(
            Path(CGRect(x: 0, y: 0, width: width, height: height)),
            with: .color(.red)
        )
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        var digest = PixelDigest(clipBounds: clipBounds)
        for index in 0..<(width * height) {
            let alpha = Int(bytes[index * 4 + 3])
            if alpha > 0 { digest.count += 1 }
            digest.alpha += alpha
        }
        return digest
    }

    func testResolvedClipBoundingRectIntersectsNormalAndPreservesInverseBounds() {
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 80)
        let clip = CGRect(x: 10, y: 15, width: 30, height: 20)
        let inner = CGRect(x: 20, y: 18, width: 10, height: 8)
        let disjoint = CGRect(x: 70, y: 60, width: 10, height: 10)

        let normal = GraphicsContext.resolvedClipBoundingRect(
            viewport,
            pathBounds: clip,
            options: []
        )
        XCTAssertEqual(normal, clip)
        XCTAssertEqual(
            GraphicsContext.resolvedClipBoundingRect(
                viewport,
                pathBounds: clip,
                options: .inverse
            ),
            viewport
        )
        XCTAssertEqual(
            GraphicsContext.resolvedClipBoundingRect(
                normal,
                pathBounds: inner,
                options: []
            ),
            inner
        )
        XCTAssertTrue(
            GraphicsContext.resolvedClipBoundingRect(
                normal,
                pathBounds: disjoint,
                options: []
            ).isNull
        )
    }

    func testRemappedClipBoundingRectTracksCurrentUserSpace() {
        let clip = CGRect(x: 10, y: 15, width: 30, height: 20)
        let translation = CGAffineTransform(translationX: 12, y: 7)
        let scale = CGAffineTransform(scaleX: 2, y: 0.5)

        XCTAssertEqual(
            GraphicsContext.remappedClipBoundingRect(
                clip,
                from: .identity,
                to: translation
            ),
            CGRect(x: -2, y: 8, width: 30, height: 20)
        )
        XCTAssertEqual(
            GraphicsContext.remappedClipBoundingRect(
                clip,
                from: .identity,
                to: scale
            ),
            CGRect(x: 5, y: 30, width: 15, height: 40)
        )
        XCTAssertEqual(
            GraphicsContext.remappedClipBoundingRect(
                clip,
                from: translation,
                to: .identity
            ),
            CGRect(x: 22, y: 22, width: 30, height: 20)
        )
        XCTAssertTrue(
            GraphicsContext.remappedClipBoundingRect(
                .null,
                from: .identity,
                to: translation
            ).isNull
        )
    }

    func testResolvedLayerClipBoundingRectTracksOpacityAndInverseMode() {
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 80)
        let layer = CGRect(x: 10, y: 15, width: 30, height: 20)
        let existing = CGRect(x: 20, y: 10, width: 30, height: 30)

        XCTAssertEqual(
            GraphicsContext.resolvedLayerClipBoundingRect(
                viewport,
                layerBounds: layer,
                opacity: 1,
                options: []
            ),
            layer
        )
        XCTAssertEqual(
            GraphicsContext.resolvedLayerClipBoundingRect(
                existing,
                layerBounds: layer,
                opacity: 0.5,
                options: []
            ),
            CGRect(x: 20, y: 15, width: 20, height: 20)
        )
        XCTAssertTrue(
            GraphicsContext.resolvedLayerClipBoundingRect(
                viewport,
                layerBounds: layer,
                opacity: 0,
                options: []
            ).isNull
        )
        XCTAssertTrue(
            GraphicsContext.resolvedLayerClipBoundingRect(
                viewport,
                layerBounds: .null,
                opacity: 1,
                options: []
            ).isNull
        )
        XCTAssertEqual(
            GraphicsContext.resolvedLayerClipBoundingRect(
                existing,
                layerBounds: layer,
                opacity: 0,
                options: .inverse
            ),
            existing
        )
    }

    func testClipToLayerAppliesNormalAndInverseOpacityMasksOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let normal = try renderLayerClip(
            deviceContext: deviceContext,
            opacity: 0.5,
            inverse: false
        )
        let inverse = try renderLayerClip(
            deviceContext: deviceContext,
            opacity: 0.5,
            inverse: true
        )
        let nested = try renderLayerClip(
            deviceContext: deviceContext,
            opacity: 1,
            inverse: false,
            pathClip: CGRect(x: 3, y: 1, width: 4, height: 5)
        )
        let halfMaskOpacity = try renderLayerClip(
            deviceContext: deviceContext,
            opacity: 1,
            inverse: false,
            maskOpacity: 0.5
        )
        let zeroMaskOpacity = try renderLayerClip(
            deviceContext: deviceContext,
            opacity: 1,
            inverse: false,
            maskOpacity: 0
        )

        XCTAssertEqual(normal.count, 12)
        XCTAssertEqual(normal.alpha, 12 * 128)
        XCTAssertEqual(inverse.count, 64)
        XCTAssertEqual(inverse.alpha, (52 * 255) + (12 * 128))
        XCTAssertEqual(nested.count, 9)
        XCTAssertEqual(nested.alpha, 9 * 255)
        XCTAssertEqual(halfMaskOpacity.count, normal.count)
        XCTAssertEqual(halfMaskOpacity.alpha, normal.alpha)
        XCTAssertEqual(halfMaskOpacity.clipBounds, CGRect(x: 2, y: 2, width: 4, height: 3))
        XCTAssertEqual(zeroMaskOpacity.count, 0)
        XCTAssertEqual(zeroMaskOpacity.alpha, 0)
        XCTAssertTrue(zeroMaskOpacity.clipBounds.isNull)
    }

    func testDrawLayerAppliesCallerTransformExactlyOnceOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let width = 48
        let height = 32
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        var context = try XCTUnwrap(
            GraphicsContext(
                sceneResources: SceneResources(),
                environment: EnvironmentValues(),
                viewport: CGRect(x: 0, y: 0, width: width, height: height),
                contentOffset: .zero,
                contentScaleFactor: 1,
                resolution: CGSize(width: width, height: height),
                commandBuffer: commandBuffer
            )
        )
        context.clear(with: .clear)
        context.translateBy(x: 10, y: 5)
        context.drawLayer { layer in
            layer.fill(
                Path(CGRect(x: 2, y: 3, width: 8, height: 6)),
                with: .color(.red)
            )
        }
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        var occupiedBounds = CGRect.null
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 0 {
                occupiedBounds = occupiedBounds.union(
                    CGRect(x: x, y: y, width: 1, height: 1)
                )
            }
        }

        XCTAssertEqual(
            occupiedBounds,
            CGRect(x: 12, y: 8, width: 8, height: 6)
        )
    }

    func testDifferentModeDisplayListMasksMergeComplementaryBranchesOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let width = 80
        let height = 80
        let maskBounds = CGRect(x: 10, y: 15, width: 30, height: 20)
        let contentBounds = CGRect(x: 0, y: 0, width: width, height: height)

        func shapeList(bounds: CGRect, color: VUI.Color) -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: Path(bounds),
                role: .fill,
                style: color,
                bounds: bounds
            )
            return list
        }

        let mask = shapeList(bounds: maskBounds, color: .white)
        let source = DisplayList.effect(
            .mask(mask, []),
            contents: shapeList(
                bounds: contentBounds,
                color: VUI.Color(.sRGB, red: 1, green: 0, blue: 0)
            )
        )
        let target = DisplayList.effect(
            .mask(mask, .inverse),
            contents: shapeList(
                bounds: contentBounds,
                color: VUI.Color(.sRGB, red: 0, green: 0, blue: 1)
            )
        )
        let sampled = RBDisplayListInterpolator(
            from: source,
            to: target
        ).copyContents(withProgress: 0.5)

        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(
            GraphicsContext(
                sceneResources: SceneResources(),
                environment: EnvironmentValues(),
                viewport: contentBounds,
                contentOffset: .zero,
                contentScaleFactor: 1,
                resolution: contentBounds.size,
                commandBuffer: commandBuffer
            )
        )
        context.clear(with: .clear)
        sampled.draw(in: context)
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        func pixel(x: Int, y: Int) -> [UInt8] {
            let offset = (y * width + x) * 4
            return Array(bytes[offset..<(offset + 4)])
        }

        XCTAssertEqual(pixel(x: 15, y: 20), [255, 0, 0, 255])
        XCTAssertEqual(pixel(x: 0, y: 0), [0, 0, 255, 255])
    }

    func testDifferentModeDisplayListMasksPreserveGeometryAndAlphaOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let width = 80
        let height = 80
        let contentBounds = CGRect(x: 0, y: 0, width: width, height: height)

        func shapeList(bounds: CGRect, color: VUI.Color) -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: Path(bounds),
                role: .fill,
                style: color,
                bounds: bounds
            )
            return list
        }

        let source = DisplayList.effect(
            .mask(
                shapeList(
                    bounds: CGRect(x: 10, y: 15, width: 30, height: 20),
                    color: VUI.Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.25)
                ),
                []
            ),
            contents: shapeList(
                bounds: contentBounds,
                color: VUI.Color(.sRGB, red: 1, green: 0, blue: 0)
            )
        )
        let target = DisplayList.effect(
            .mask(
                shapeList(
                    bounds: CGRect(x: 20, y: 10, width: 40, height: 30),
                    color: VUI.Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.75)
                ),
                .inverse
            ),
            contents: shapeList(
                bounds: contentBounds,
                color: VUI.Color(.sRGB, red: 0, green: 0, blue: 1)
            )
        )
        let sampled = RBDisplayListInterpolator(
            from: source,
            to: target
        ).copyContents(withProgress: 0.5)

        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(
            GraphicsContext(
                sceneResources: SceneResources(),
                environment: EnvironmentValues(),
                viewport: contentBounds,
                contentOffset: .zero,
                contentScaleFactor: 1,
                resolution: contentBounds.size,
                commandBuffer: commandBuffer
            )
        )
        context.clear(with: .clear)
        sampled.draw(in: context)
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        func pixel(x: Int, y: Int) -> [UInt8] {
            let offset = (y * width + x) * 4
            return Array(bytes[offset..<(offset + 4)])
        }

        XCTAssertEqual(pixel(x: 25, y: 20), [48, 0, 64, 112])
        XCTAssertEqual(pixel(x: 15, y: 20), [0, 0, 255, 255])
        XCTAssertEqual(pixel(x: 50, y: 20), [0, 0, 64, 64])
        XCTAssertEqual(pixel(x: 0, y: 0), [0, 0, 255, 255])
    }

    func testIncompatibleMaskCoverageKeepsSourcePixelsOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let width = 80
        let height = 80
        let maskBounds = CGRect(x: 10, y: 15, width: 30, height: 20)
        let contentBounds = CGRect(x: 0, y: 0, width: width, height: height)

        func shapeList(path: Path, bounds: CGRect, color: VUI.Color) -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: path,
                role: .fill,
                style: color,
                bounds: bounds
            )
            return list
        }

        let sourceMask = shapeList(
            path: Path(maskBounds),
            bounds: maskBounds,
            color: .white
        )
        let targetMask = shapeList(
            path: Path(ellipseIn: maskBounds),
            bounds: maskBounds,
            color: .white
        )
        let contents = shapeList(
            path: Path(contentBounds),
            bounds: contentBounds,
            color: VUI.Color(.sRGB, red: 1, green: 0, blue: 0)
        )
        let sampled = RBDisplayListInterpolator(
            from: .effect(.mask(sourceMask, []), contents: contents),
            to: .effect(.mask(targetMask, []), contents: contents)
        ).copyContents(withProgress: 0.5)

        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(
            GraphicsContext(
                sceneResources: SceneResources(),
                environment: EnvironmentValues(),
                viewport: contentBounds,
                contentOffset: .zero,
                contentScaleFactor: 1,
                resolution: contentBounds.size,
                commandBuffer: commandBuffer
            )
        )
        context.clear(with: .clear)
        sampled.draw(in: context)
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        func pixel(x: Int, y: Int) -> [UInt8] {
            let offset = (y * width + x) * 4
            return Array(bytes[offset..<(offset + 4)])
        }

        XCTAssertEqual(pixel(x: 25, y: 25), [255, 0, 0, 255])
        XCTAssertEqual(pixel(x: 11, y: 16), [255, 0, 0, 255])
        XCTAssertEqual(pixel(x: 0, y: 0), [0, 0, 0, 0])
    }

    func testDisplayListItemOpacityAppliesAtRendererAndImmediateReplayBoundaries() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }

        func renderedAlpha(usesRenderer: Bool) throws -> UInt8 {
            let bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
            let queue = try XCTUnwrap(deviceContext.renderQueue())
            let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
            let context = try XCTUnwrap(
                GraphicsContext(
                    sceneResources: SceneResources(),
                    environment: EnvironmentValues(),
                    viewport: bounds,
                    contentOffset: .zero,
                    contentScaleFactor: 1,
                    resolution: bounds.size,
                    commandBuffer: commandBuffer
                )
            )
            context.clear(with: .clear)
            let item = DisplayList.Item(
                command: .closure(bounds: bounds),
                opacity: 0.5
            ) { context in
                context.fill(Path(bounds), with: .color(.red))
            }
            if usesRenderer {
                var list = DisplayList()
                list.items = [item]
                list.interpolationBounds = bounds
                list.draw(in: context)
            } else {
                item(context)
            }
            try waitForCompletion(commandBuffer)

            let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
            let pointer = try XCTUnwrap(staging.contents())
            return pointer.load(fromByteOffset: ((2 * 4) + 2) * 4 + 3, as: UInt8.self)
        }

        XCTAssertEqual(try renderedAlpha(usesRenderer: true), 128)
        XCTAssertEqual(try renderedAlpha(usesRenderer: false), 128)
    }

    func testCompatibleImageTintMixRendersPremultipliedMidpointOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let bitmap = VVD.Image(
            width: 1,
            height: 1,
            pixelFormat: .rgba8,
            data: Data([255, 255, 255, 255])
        )
        let texture = try XCTUnwrap(bitmap.makeTexture(commandQueue: queue))
        let bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
        let sourceImage = GraphicsContext.ResolvedImage(
            baseline: 1,
            shading: .color(VUI.Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.25)),
            texture: texture,
            textureTransform: .identity,
            scaleFactor: 1
        )
        let targetImage = GraphicsContext.ResolvedImage(
            baseline: 1,
            shading: .color(VUI.Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 0.75)),
            texture: texture,
            textureTransform: .identity,
            scaleFactor: 1
        )
        var source = DisplayList()
        source.appendImageItem(sourceImage, bounds: bounds)
        var target = DisplayList()
        target.appendImageItem(targetImage, bounds: bounds)
        let midpoint = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [:]
        ).copyContents(withProgress: 0.5)

        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(
            GraphicsContext(
                sceneResources: SceneResources(),
                environment: EnvironmentValues(),
                viewport: bounds,
                contentOffset: .zero,
                contentScaleFactor: 1,
                resolution: bounds.size,
                commandBuffer: commandBuffer
            )
        )
        context.clear(with: .clear)
        midpoint.draw(in: context)
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let offset = ((2 * 4) + 2) * 4
        let pixel = UnsafeRawBufferPointer(start: pointer + offset, count: 4)
        XCTAssertEqual(Array(pixel), [32, 0, 96, 128])
    }

    func testCompatibleImagePlacementMixClipsToFixedCoverageOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let bitmap = VVD.Image(
            width: 1,
            height: 1,
            pixelFormat: .rgba8,
            data: Data([255, 255, 255, 255])
        )
        let texture = try XCTUnwrap(bitmap.makeTexture(commandQueue: queue))
        let coverage = CGRect(x: 0, y: 0, width: 20, height: 20)
        let image = GraphicsContext.ResolvedImage(
            baseline: 1,
            shading: nil,
            texture: texture,
            textureTransform: .identity,
            scaleFactor: 1
        )
        var source = DisplayList()
        source.appendImageItem(
            image,
            bounds: coverage,
            placementRect: coverage
        )
        var target = DisplayList()
        target.appendImageItem(
            image,
            bounds: coverage,
            placementRect: CGRect(x: 10, y: 0, width: 20, height: 20)
        )
        let midpoint = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [:]
        ).copyContents(withProgress: 0.5)

        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(
            GraphicsContext(
                sceneResources: SceneResources(),
                environment: EnvironmentValues(),
                viewport: coverage,
                contentOffset: .zero,
                contentScaleFactor: 1,
                resolution: coverage.size,
                commandBuffer: commandBuffer
            )
        )
        context.clear(with: .clear)
        midpoint.draw(in: context)
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(
            deviceContext.makeCPUAccessible(texture: context.backdrop)
        )
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(
            start: pointer,
            count: 20 * 20 * 4
        )
        var nonzeroCount = 0
        var minX = Int.max
        var maxX = Int.min
        for y in 0..<20 {
            for x in 0..<20 where bytes[((y * 20) + x) * 4 + 3] > 0 {
                nonzeroCount += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        XCTAssertEqual(nonzeroCount, 300)
        XCTAssertEqual(minX, 5)
        XCTAssertEqual(maxX, 19)
    }
}
