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

    private func renderSymbol(
        _ name: String,
        deviceContext: GraphicsDeviceContext,
        layerOpacities: [Double]? = nil,
        variableColorOpacities: [Double]? = nil,
        drawProgresses: [Double]? = nil,
        drawFallbackProgresses: [Double]? = nil,
        drawsReversed: Bool = false,
        drawFallbackOpacity: Double? = nil
    ) throws -> (count: Int, centerAlpha: UInt8) {
        let width = 24
        let height = 24
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let context = try XCTUnwrap(
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
        let symbol = try XCTUnwrap(SymbolAssetCatalog.resolve(
            name: name,
            variableValue: nil,
            bundle: nil
        ))
        var image = GraphicsContext.ResolvedImage(symbol: symbol)
        image.symbolLayerOpacities = layerOpacities
        image.symbolVariableColorOpacities = variableColorOpacities
        image.symbolDrawProgresses = drawProgresses
        image.symbolDrawFallbackProgresses = drawFallbackProgresses
        image.symbolDrawsReversed = drawsReversed
        image.symbolDrawFallbackOpacity = drawFallbackOpacity
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        var count = 0
        for index in 0..<(width * height) where bytes[index * 4 + 3] > 0 {
            count += 1
        }
        let centerOffset = ((12 * width) + 12) * 4 + 3
        return (count, bytes[centerOffset])
    }

    func testBundledCoreSymbolCatalogResolvesEverySVGAsset() throws {
        let names = [
            "add",
            "arrow.left",
            "arrow.right",
            "battery.alert",
            "battery.charging",
            "battery.full",
            "battery.low",
            "bell",
            "bell.fill",
            "check",
            "chevron.down",
            "chevron.left",
            "chevron.right",
            "chevron.up",
            "cloud",
            "cloud.fill",
            "close",
            "copy",
            "download",
            "draw",
            "edit",
            "error",
            "error.fill",
            "file",
            "file.fill",
            "filter",
            "folder",
            "folder.fill",
            "folder.open",
            "heart",
            "heart.fill",
            "help",
            "help.fill",
            "home",
            "home.fill",
            "info",
            "info.fill",
            "lock",
            "lock.fill",
            "lock.open",
            "lock.open.fill",
            "menu",
            "more.horizontal",
            "more.vertical",
            "pause",
            "person",
            "person.fill",
            "photo",
            "photo.fill",
            "play",
            "recycle",
            "refresh",
            "remove",
            "save",
            "search",
            "settings",
            "settings.fill",
            "share",
            "sort",
            "star",
            "star.fill",
            "stop",
            "trash",
            "trash.fill",
            "upload",
            "visibility",
            "visibility.fill",
            "visibility.off",
            "visibility.off.fill",
            "volume",
            "volume.off",
            "warning",
            "warning.fill",
            "wifi",
            "wifi.off",
        ]

        for name in names {
            let symbol = try XCTUnwrap(
                SymbolAssetCatalog.resolve(
                    name: name,
                    variableValue: nil,
                    bundle: nil
                ),
                "Failed to resolve bundled symbol \(name)"
            )
            XCTAssertFalse(symbol.layers.isEmpty, name)
        }
    }

    func testBundledCoreSymbolFillPairsUseDistinctGeometry() throws {
        let pairedNames = [
            "bell",
            "cloud",
            "error",
            "file",
            "folder",
            "heart",
            "help",
            "home",
            "info",
            "lock",
            "lock.open",
            "person",
            "photo",
            "settings",
            "star",
            "trash",
            "visibility",
            "visibility.off",
            "warning",
        ]

        for name in pairedNames {
            let regular = try XCTUnwrap(SymbolAssetCatalog.resolve(
                name: name,
                variableValue: nil,
                bundle: nil
            ))
            let filled = try XCTUnwrap(SymbolAssetCatalog.resolve(
                name: "\(name).fill",
                variableValue: nil,
                bundle: nil
            ))
            XCTAssertNotEqual(
                regular.layers.map(\.path),
                filled.layers.map(\.path),
                "\(name) and \(name).fill must use distinct geometry"
            )
        }
    }

    func testWarningSymbolOutlineRendersLessInkThanFilledVariantOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let warning = try renderSymbol("warning", deviceContext: deviceContext)
        let filledWarning = try renderSymbol(
            "warning.fill",
            deviceContext: deviceContext
        )

        XCTAssertGreaterThan(warning.count, 0)
        XCTAssertGreaterThan(filledWarning.count, warning.count)
    }

    func testPortableVectorSymbolsRenderOutlineAndFilledVariantsOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let outline = try renderSymbol("star", deviceContext: deviceContext)
        let filled = try renderSymbol("star.fill", deviceContext: deviceContext)

        XCTAssertGreaterThan(outline.count, 0)
        XCTAssertGreaterThan(filled.count, outline.count)
        XCTAssertLessThan(outline.centerAlpha, filled.centerAlpha)
        // The default symbol foreground resolves through system primary.
        XCTAssertEqual(filled.centerAlpha, 216)

        let photo = try renderSymbol("photo.fill", deviceContext: deviceContext)
        let primaryHidden = try renderSymbol(
            "photo.fill",
            deviceContext: deviceContext,
            layerOpacities: [0, 1]
        )
        let secondaryHidden = try renderSymbol(
            "photo.fill",
            deviceContext: deviceContext,
            layerOpacities: [1, 0]
        )
        XCTAssertGreaterThan(primaryHidden.count, 0)
        XCTAssertGreaterThan(secondaryHidden.count, 0)
        XCTAssertLessThan(primaryHidden.count, photo.count)
        XCTAssertLessThan(secondaryHidden.count, photo.count)

        let independentlyHidden = try renderSymbol(
            "photo.fill",
            deviceContext: deviceContext,
            layerOpacities: [0, 1],
            variableColorOpacities: [1, 0]
        )
        XCTAssertEqual(independentlyHidden.count, 0)

        let draw = try renderSymbol("draw", deviceContext: deviceContext)
        let halfDrawn = try renderSymbol(
            "draw",
            deviceContext: deviceContext,
            drawProgresses: [0.5, 0.5]
        )
        let reverseHalfDrawn = try renderSymbol(
            "draw",
            deviceContext: deviceContext,
            drawProgresses: [0.5, 0.5],
            drawsReversed: true
        )
        let drawHidden = try renderSymbol(
            "draw",
            deviceContext: deviceContext,
            drawProgresses: [0, 0],
            drawFallbackProgresses: [0, 0]
        )
        let reversedHideBoundary = try renderSymbol(
            "draw",
            deviceContext: deviceContext,
            drawProgresses: [1, 0],
            drawsReversed: true
        )
        let reversedHideNextGroup = try renderSymbol(
            "draw",
            deviceContext: deviceContext,
            drawProgresses: [0.999_9, 0],
            drawsReversed: true
        )
        let reversedRestoreBoundary = try renderSymbol(
            "draw",
            deviceContext: deviceContext,
            drawProgresses: [0, 1],
            drawsReversed: true
        )
        let reversedRestoreNextGroup = try renderSymbol(
            "draw",
            deviceContext: deviceContext,
            drawProgresses: [0.000_1, 1],
            drawsReversed: true
        )
        XCTAssertGreaterThan(draw.count, halfDrawn.count)
        XCTAssertGreaterThan(halfDrawn.count, 0)
        XCTAssertGreaterThan(reverseHalfDrawn.count, 0)
        XCTAssertEqual(drawHidden.count, 0)
        XCTAssertLessThanOrEqual(
            abs(reversedHideBoundary.count - reversedHideNextGroup.count),
            2
        )
        XCTAssertLessThanOrEqual(
            abs(reversedRestoreBoundary.count - reversedRestoreNextGroup.count),
            2
        )

        let fallbackHidden = try renderSymbol(
            "star.fill",
            deviceContext: deviceContext,
            drawFallbackOpacity: 0
        )
        XCTAssertEqual(fallbackHidden.count, 0)

        // ASSERTIONS symbolEffectImageConsumerDisassemblyObserved
        // ASSERTIONS symbolEffectPulseLayeredRuntimeObserved
        // ASSERTIONS symbolEffectVariableColorRuntimeObserved
        // ASSERTIONS symbolEffectDrawDisassemblyObserved
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

    // ASSERTIONS scrollClipDisabledPlatformConsumerObserved
    func testPlatformGroupUsesScrollEnvironmentPresentationClipOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)
        let attachment = graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            )
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 2, y: 3),
                contentFrame: CGRect(x: 0, y: 0, width: 12, height: 12),
                containingSize: CGSize(width: 4, height: 3),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            return (host, HostingScrollView.PlatformContainer(scrollView: host))
        }
        XCTAssertTrue(
            attachment.1.platformGroupContainer === attachment.0.host
        )

        let width = 16
        let height = 16
        let contentBounds = CGRect(x: 0, y: 0, width: 12, height: 12)
        let viewportFrame = CGRect(x: 5, y: 4, width: 4, height: 3)
        var contents = DisplayList()
        contents.appendItem(bounds: contentBounds) { context in
            context.fill(Path(contentBounds), with: .color(.red))
        }
        var list = DisplayList()
        list.appendEffect(
            .platformGroup(attachment.1),
            contents: contents,
            frame: viewportFrame,
            identity: _DisplayList_Identity(decodedValue: 91),
            version: DisplayList.Version(value: 1)
        )

        func renderedBounds() throws -> CGRect {
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

            let renderer = DisplayList.GraphicsRenderer()
            renderer.render(list: list, at: .zero, in: context)
            try waitForCompletion(commandBuffer)

            let staging = try XCTUnwrap(
                deviceContext.makeCPUAccessible(texture: context.backdrop)
            )
            let pointer = try XCTUnwrap(staging.contents())
            let bytes = UnsafeRawBufferPointer(
                start: pointer,
                count: width * height * 4
            )
            var occupiedBounds = CGRect.null
            for y in 0..<height {
                for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 0 {
                    occupiedBounds = occupiedBounds.union(
                        CGRect(x: x, y: y, width: 1, height: 1)
                    )
                }
            }
            XCTAssertEqual(renderer.animatorCount, 0)
            return occupiedBounds
        }

        XCTAssertEqual(try renderedBounds(), viewportFrame)

        var properties = ScrollEnvironmentProperties()
        properties.isClippingEnabled = false
        attachment.0.updateProperties(properties)
        XCTAssertEqual(
            try renderedBounds(),
            CGRect(x: 3, y: 1, width: 12, height: 12)
        )
    }

    // ASSERTIONS projectionNonAffineScrollPresentationObserved
    func testDisplayListComposesInvertibleNonAffineProjectionsOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
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

        let localBounds = CGRect(x: 0, y: 0, width: 24, height: 20)
        let markerBounds = CGRect(x: 14, y: 6, width: 4, height: 4)
        let frame = CGRect(x: 10, y: 12, width: 24, height: 20)
        var projection = ProjectionTransform()
        projection.m11 = 1.1
        projection.m12 = 0.08
        projection.m13 = 0.006
        projection.m21 = -0.04
        projection.m22 = 1.02
        projection.m23 = 0.004
        projection.m31 = 5
        projection.m32 = 3
        var outerProjection = ProjectionTransform()
        outerProjection.m11 = 0.97
        outerProjection.m12 = -0.03
        outerProjection.m13 = -0.002
        outerProjection.m21 = 0.04
        outerProjection.m22 = 1.03
        outerProjection.m23 = 0.001
        outerProjection.m31 = 2
        outerProjection.m32 = 4

        var contents = DisplayList()
        contents.appendItem(bounds: localBounds) { context in
            context.fill(Path(localBounds), with: .color(.red))
        }
        contents.appendItem(bounds: markerBounds) { context in
            context.fill(Path(markerBounds), with: .color(.blue))
        }
        var projectedContents = DisplayList()
        projectedContents.appendEffect(
            .transform(projection),
            contents: contents,
            frame: CGRect(origin: .zero, size: localBounds.size),
            identity: _DisplayList_Identity(decodedValue: 95),
            version: DisplayList.Version(value: 1)
        )
        var list = DisplayList()
        list.appendEffect(
            .transform(outerProjection),
            contents: projectedContents,
            frame: frame,
            identity: _DisplayList_Identity(decodedValue: 96),
            version: DisplayList.Version(value: 1)
        )

        DisplayList.GraphicsRenderer().render(
            list: list,
            at: .zero,
            in: context
        )
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(
            deviceContext.makeCPUAccessible(texture: context.backdrop)
        )
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(
            start: pointer,
            count: width * height * 4
        )
        var occupiedBounds = CGRect.null
        var markerSum = CGPoint.zero
        var markerCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard bytes[offset + 3] > 0 else { continue }
                occupiedBounds = occupiedBounds.union(
                    CGRect(x: x, y: y, width: 1, height: 1)
                )
                if Int(bytes[offset + 2]) > Int(bytes[offset]) + 32 {
                    markerSum.x += CGFloat(x) + 0.5
                    markerSum.y += CGFloat(y) + 0.5
                    markerCount += 1
                }
            }
        }

        let projectedCorners = [
            CGPoint(x: localBounds.minX, y: localBounds.minY),
            CGPoint(x: localBounds.maxX, y: localBounds.minY),
            CGPoint(x: localBounds.maxX, y: localBounds.maxY),
            CGPoint(x: localBounds.minX, y: localBounds.maxY),
        ].map {
            let point = $0
                .applying(projection)
                .applying(outerProjection)
            return CGPoint(x: point.x + frame.minX, y: point.y + frame.minY)
        }
        let expectedBounds = projectedCorners.dropFirst().reduce(
            CGRect(origin: projectedCorners[0], size: .zero)
        ) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
        XCTAssertFalse(occupiedBounds.isNull)
        XCTAssertEqual(occupiedBounds.minX, expectedBounds.minX, accuracy: 3)
        XCTAssertEqual(occupiedBounds.minY, expectedBounds.minY, accuracy: 3)
        XCTAssertEqual(occupiedBounds.maxX, expectedBounds.maxX, accuracy: 3)
        XCTAssertEqual(occupiedBounds.maxY, expectedBounds.maxY, accuracy: 3)

        XCTAssertGreaterThan(markerCount, 2)
        let markerCentroid = CGPoint(
            x: markerSum.x / CGFloat(markerCount),
            y: markerSum.y / CGFloat(markerCount)
        )
        let expectedMarker = CGPoint(
            x: markerBounds.midX,
            y: markerBounds.midY
        )
            .applying(projection)
            .applying(outerProjection)
        XCTAssertEqual(
            markerCentroid.x,
            expectedMarker.x + frame.minX,
            accuracy: 1
        )
        XCTAssertEqual(
            markerCentroid.y,
            expectedMarker.y + frame.minY,
            accuracy: 1
        )
    }

    // ASSERTIONS projectionNonAffineScrollPresentationObserved
    func testPlatformGroupClipsNonAffineProjectionAfterContentMappingOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)
        let attachment = graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(
                axes: [.horizontal, .vertical],
                showsIndicators: false
            ))
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 260, height: 240),
                containingSize: CGSize(width: 180, height: 140),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            return HostingScrollView.PlatformContainer(scrollView: host)
        }

        let width = 240
        let height = 200
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

        let contentBounds = CGRect(x: 0, y: 0, width: 260, height: 240)
        let markerBounds = CGRect(x: 225, y: 95, width: 10, height: 10)
        let viewportFrame = CGRect(x: 20, y: 20, width: 180, height: 140)
        var projection = ProjectionTransform()
        projection.m11 = 1.04
        projection.m12 = 0.08
        projection.m13 = 0.0014
        projection.m21 = -0.05
        projection.m22 = 0.96
        projection.m23 = 0.0009
        projection.m31 = 6
        projection.m32 = 4

        var rawContents = DisplayList()
        rawContents.appendItem(bounds: contentBounds) { context in
            context.fill(Path(contentBounds), with: .color(.red))
        }
        rawContents.appendItem(bounds: markerBounds) { context in
            context.fill(Path(markerBounds), with: .color(.blue))
        }
        var projectedContents = DisplayList()
        projectedContents.appendEffect(
            .transform(projection),
            contents: rawContents,
            frame: contentBounds,
            identity: _DisplayList_Identity(decodedValue: 96),
            version: DisplayList.Version(value: 1)
        )
        var list = DisplayList()
        list.appendEffect(
            .platformGroup(attachment),
            contents: projectedContents,
            frame: viewportFrame,
            identity: _DisplayList_Identity(decodedValue: 97),
            version: DisplayList.Version(value: 1)
        )

        DisplayList.GraphicsRenderer().render(
            list: list,
            at: .zero,
            in: context
        )
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(
            deviceContext.makeCPUAccessible(texture: context.backdrop)
        )
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(
            start: pointer,
            count: width * height * 4
        )
        var occupiedBounds = CGRect.null
        var markerSum = CGPoint.zero
        var markerCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard bytes[offset + 3] > 0 else { continue }
                occupiedBounds = occupiedBounds.union(
                    CGRect(x: x, y: y, width: 1, height: 1)
                )
                if Int(bytes[offset + 2]) > Int(bytes[offset]) + 32 {
                    markerSum.x += CGFloat(x) + 0.5
                    markerSum.y += CGFloat(y) + 0.5
                    markerCount += 1
                }
            }
        }

        XCTAssertFalse(occupiedBounds.isNull)
        XCTAssertGreaterThanOrEqual(occupiedBounds.minX, viewportFrame.minX)
        XCTAssertGreaterThanOrEqual(occupiedBounds.minY, viewportFrame.minY)
        XCTAssertLessThanOrEqual(occupiedBounds.maxX, viewportFrame.maxX)
        XCTAssertLessThanOrEqual(occupiedBounds.maxY, viewportFrame.maxY)
        XCTAssertGreaterThan(markerCount, 4)

        let expectedMarker = CGPoint(
            x: markerBounds.midX,
            y: markerBounds.midY
        ).applying(projection)
        XCTAssertGreaterThan(markerBounds.minX, viewportFrame.width)
        XCTAssertLessThan(expectedMarker.x, viewportFrame.width)
        XCTAssertLessThan(expectedMarker.y, viewportFrame.height)
        XCTAssertEqual(
            markerSum.x / CGFloat(markerCount),
            expectedMarker.x + viewportFrame.minX,
            accuracy: 1.5
        )
        XCTAssertEqual(
            markerSum.y / CGFloat(markerCount),
            expectedMarker.y + viewportFrame.minY,
            accuracy: 1.5
        )
    }

    // ASSERTIONS projectionNonAffineScrollPresentationObserved
    func testNonAffineProjectionMapsPlatformGroupAfterViewportClipOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)
        let viewportSize = CGSize(width: 80, height: 60)
        let contentBounds = CGRect(x: 0, y: 0, width: 120, height: 100)
        let attachment = graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(
                axes: [.horizontal, .vertical],
                showsIndicators: false
            ))
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: contentBounds,
                containingSize: viewportSize,
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            return HostingScrollView.PlatformContainer(scrollView: host)
        }

        let width = 140
        let height = 120
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

        var projection = ProjectionTransform()
        projection.m11 = 1.04
        projection.m12 = 0.08
        projection.m13 = 0.0014
        projection.m21 = -0.05
        projection.m22 = 0.96
        projection.m23 = 0.0009
        projection.m31 = 6
        projection.m32 = 4
        let viewportBounds = CGRect(origin: .zero, size: viewportSize)
        let projectedFrame = CGRect(
            x: 25,
            y: 20,
            width: viewportSize.width,
            height: viewportSize.height
        )

        var rawContents = DisplayList()
        rawContents.appendItem(bounds: contentBounds) { context in
            context.fill(Path(contentBounds), with: .color(.red))
        }
        var hostedContents = DisplayList()
        hostedContents.appendEffect(
            .platformGroup(attachment),
            contents: rawContents,
            frame: viewportBounds,
            identity: _DisplayList_Identity(decodedValue: 98),
            version: DisplayList.Version(value: 1)
        )
        var list = DisplayList()
        list.appendEffect(
            .transform(projection),
            contents: hostedContents,
            frame: projectedFrame,
            identity: _DisplayList_Identity(decodedValue: 99),
            version: DisplayList.Version(value: 1)
        )

        DisplayList.GraphicsRenderer().render(
            list: list,
            at: .zero,
            in: context
        )
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(
            deviceContext.makeCPUAccessible(texture: context.backdrop)
        )
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(
            start: pointer,
            count: width * height * 4
        )
        var occupiedBounds = CGRect.null
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard bytes[offset + 3] > 0 else { continue }
                occupiedBounds = occupiedBounds.union(
                    CGRect(x: x, y: y, width: 1, height: 1)
                )
            }
        }

        let projectedCorners = [
            CGPoint(x: viewportBounds.minX, y: viewportBounds.minY),
            CGPoint(x: viewportBounds.maxX, y: viewportBounds.minY),
            CGPoint(x: viewportBounds.maxX, y: viewportBounds.maxY),
            CGPoint(x: viewportBounds.minX, y: viewportBounds.maxY),
        ].map {
            let point = $0.applying(projection)
            return CGPoint(
                x: point.x + projectedFrame.minX,
                y: point.y + projectedFrame.minY
            )
        }
        let expectedBounds = projectedCorners.dropFirst().reduce(
            CGRect(origin: projectedCorners[0], size: .zero)
        ) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
        XCTAssertFalse(occupiedBounds.isNull)
        XCTAssertEqual(occupiedBounds.minX, expectedBounds.minX, accuracy: 2)
        XCTAssertEqual(occupiedBounds.minY, expectedBounds.minY, accuracy: 2)
        XCTAssertEqual(occupiedBounds.maxX, expectedBounds.maxX, accuracy: 2)
        XCTAssertEqual(occupiedBounds.maxY, expectedBounds.maxY, accuracy: 2)
    }

    // ASSERTIONS scrollIndicatorSkinRuntimeObserved
    func testPlatformGroupRendersFixedScrollIndicatorOutsideContentClipOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)
        let attachment = graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(
                axes: .vertical,
                showsIndicators: false
            ))
            var properties = ScrollEnvironmentProperties()
            properties.verticalIndicator = ScrollIndicatorConfiguration(
                visibility: .hidden,
                style: .fixedArea
            )
            host.updateProperties(properties)
            host.updateIndicatorPresentation(
                outerSize: CGSize(width: 6, height: 4),
                metrics: ScrollIndicatorMetricsStorage(
                    vertical: ScrollIndicatorMetrics(
                        thickness: 2,
                        minimumThumbLength: 1
                    )
                )
            )
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 0, y: 2),
                contentFrame: CGRect(x: 0, y: 0, width: 4, height: 8),
                containingSize: CGSize(width: 4, height: 4),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            return (host, HostingScrollView.PlatformContainer(scrollView: host))
        }

        let width = 12
        let height = 10
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

        let contentBounds = CGRect(x: 0, y: 0, width: 4, height: 8)
        let outerFrame = CGRect(x: 2, y: 2, width: 6, height: 4)
        var contents = DisplayList()
        contents.appendItem(bounds: contentBounds) { context in
            context.fill(Path(contentBounds), with: .color(.red))
        }
        var list = DisplayList()
        list.appendEffect(
            .platformGroup(attachment.1),
            contents: contents,
            frame: outerFrame,
            identity: _DisplayList_Identity(decodedValue: 93),
            version: DisplayList.Version(value: 1)
        )

        DisplayList.GraphicsRenderer().render(list: list, at: .zero, in: context)
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(
            deviceContext.makeCPUAccessible(texture: context.backdrop)
        )
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(
            start: pointer,
            count: width * height * 4
        )
        func pixel(x: Int, y: Int) -> [UInt8] {
            let index = (y * width + x) * 4
            return Array(bytes[index..<(index + 4)])
        }

        XCTAssertEqual(pixel(x: 3, y: 3), [255, 56, 60, 255])
        XCTAssertEqual(pixel(x: 7, y: 2), [0, 0, 0, 12])
        XCTAssertEqual(pixel(x: 7, y: 3), [0, 0, 0, 73])
        XCTAssertEqual(pixel(x: 8, y: 3), [0, 0, 0, 0])
    }

    func testPlatformGroupUsesLiveViewportWithoutRebuildingDisplayListOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)
        let attachment = graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            )
            host.host.updateViewport(
                contentOffset: .zero,
                containingSize: CGSize(width: 4, height: 3)
            )
            return (host, HostingScrollView.PlatformContainer(scrollView: host))
        }

        let viewportFrame = CGRect(x: 5, y: 4, width: 4, height: 3)
        var contents = DisplayList()
        contents.appendItem(bounds: CGRect(x: 0, y: 0, width: 4, height: 3)) { context in
            context.fill(
                Path(CGRect(x: 0, y: 0, width: 4, height: 3)),
                with: .color(.red)
            )
        }
        contents.appendItem(bounds: CGRect(x: 0, y: 3, width: 4, height: 3)) { context in
            context.fill(
                Path(CGRect(x: 0, y: 3, width: 4, height: 3)),
                with: .color(.blue)
            )
        }
        var list = DisplayList()
        list.appendEffect(
            .platformGroup(attachment.1),
            contents: contents,
            frame: viewportFrame,
            identity: _DisplayList_Identity(decodedValue: 92),
            version: DisplayList.Version(value: 1)
        )
        let renderer = DisplayList.GraphicsRenderer()

        func renderedPixel() throws -> [UInt8] {
            let width = 16
            let height = 16
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
            renderer.render(list: list, at: .zero, in: context)
            try waitForCompletion(commandBuffer)

            let staging = try XCTUnwrap(
                deviceContext.makeCPUAccessible(texture: context.backdrop)
            )
            let pointer = try XCTUnwrap(staging.contents())
            let bytes = UnsafeRawBufferPointer(
                start: pointer,
                count: width * height * 4
            )
            let offset = ((5 * width) + 6) * 4
            return Array(bytes[offset..<(offset + 4)])
        }

        let initialPixel = try renderedPixel()
        XCTAssertGreaterThan(initialPixel[0], initialPixel[2])
        XCTAssertEqual(initialPixel[3], 255)

        attachment.0.host.updateViewport(
            contentOffset: CGPoint(x: 0, y: 3),
            containingSize: CGSize(width: 4, height: 3)
        )

        let scrolledPixel = try renderedPixel()
        XCTAssertGreaterThan(scrolledPixel[2], scrolledPixel[0])
        XCTAssertEqual(scrolledPixel[3], 255)
        XCTAssertNotEqual(scrolledPixel, initialPixel)
        XCTAssertEqual(renderer.animatorCount, 0)
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

    func testDirectAndNestedMaskTopologyFallbackPreservesBothBranchesOnGPU() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let width = 80
        let height = 80
        let sourceMaskBounds = CGRect(x: 10, y: 15, width: 20, height: 20)
        let targetMaskBounds = CGRect(x: 40, y: 15, width: 20, height: 20)
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

        let directMask = shapeList(bounds: sourceMaskBounds, color: .white)
        let nestedMask = DisplayList.effect(
            .mask(shapeList(bounds: targetMaskBounds, color: .white), []),
            contents: shapeList(bounds: contentBounds, color: .white)
        )
        let contents = shapeList(
            bounds: contentBounds,
            color: VUI.Color(.sRGB, red: 1, green: 0, blue: 0)
        )

        let transition = RBTransition()
        transition.method = ContentTransition.Method.diff.method
        let effect = RBTransitionEffect()
        effect.type = ContentTransition.EffectType(type: 3).type
        effect.events = 3
        transition.addEffect(effect)

        func pixels(for sampled: DisplayList) throws -> [UInt8] {
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

            let staging = try XCTUnwrap(
                deviceContext.makeCPUAccessible(texture: context.backdrop)
            )
            let pointer = try XCTUnwrap(staging.contents())
            return Array(UnsafeRawBufferPointer(
                start: pointer,
                count: width * height * 4
            ))
        }

        func pixel(_ pixels: [UInt8], x: Int, y: Int) -> [UInt8] {
            let offset = (y * width + x) * 4
            return Array(pixels[offset..<(offset + 4)])
        }

        let source = DisplayList.effect(.mask(directMask, []), contents: contents)
        let target = DisplayList.effect(.mask(nestedMask, []), contents: contents)
        let transitioned = RBDisplayListInterpolator(
            from: source,
            to: target,
            options: [.transition: transition]
        ).copyContents(withProgress: 0.5)
        let transitionedPixels = try pixels(for: transitioned)
        XCTAssertEqual(pixel(transitionedPixels, x: 15, y: 20), [255, 0, 0, 255])
        XCTAssertEqual(pixel(transitionedPixels, x: 30, y: 20), [0, 0, 0, 0])
        XCTAssertEqual(pixel(transitionedPixels, x: 45, y: 20), [255, 0, 0, 255])
        XCTAssertEqual(pixel(transitionedPixels, x: 0, y: 0), [0, 0, 0, 0])

        let defaultMidpoint = RBDisplayListInterpolator(
            from: source,
            to: target
        ).copyContents(withProgress: 0.5)
        let defaultPixels = try pixels(for: defaultMidpoint)
        XCTAssertEqual(pixel(defaultPixels, x: 15, y: 20), [128, 0, 0, 128])
        XCTAssertEqual(pixel(defaultPixels, x: 30, y: 20), [0, 0, 0, 0])
        XCTAssertEqual(pixel(defaultPixels, x: 45, y: 20), [128, 0, 0, 128])
        XCTAssertEqual(pixel(defaultPixels, x: 0, y: 0), [0, 0, 0, 0])
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
