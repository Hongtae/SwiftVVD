import XCTest
import VVD
@testable import VUI

final class GraphicsContextPathStrokeGeometryTests: XCTestCase {
    private final class CaptureEncoder: RenderCommandEncoder {
        var isCompleted = false
        var commandBuffer: CommandBuffer { fatalError("Only vertex uploads are captured") }
        private var buffer: GPUBuffer?
        private var offset = 0
        var vertices: [Float2] = []
        var drawCount = 0
        var onDraw: (() -> Void)?
        var upload: (GPUBuffer, Int, [UInt8])? {
            guard let buffer, !vertices.isEmpty else { return nil }
            return (buffer, offset, vertices.withUnsafeBytes { Array($0) })
        }

        func endEncoding() { isCompleted = true }
        func waitEvent(_ event: GPUEvent) {}
        func signalEvent(_ event: GPUEvent) {}
        func waitSemaphoreValue(_ semaphore: GPUSemaphore, value: UInt64) {}
        func signalSemaphoreValue(_ semaphore: GPUSemaphore, value: UInt64) {}
        func setResource(_ resource: ShaderBindingSet, index: Int) {}
        func setViewport(_ viewport: Viewport) {}
        func setScissorRect(_ rect: ScissorRect) {}
        func setRenderPipelineState(_ state: RenderPipelineState) {}
        func setVertexBuffer(_ buffer: GPUBuffer, offset: Int, index: Int) {
            XCTAssertEqual(index, 0)
            self.buffer = buffer
            self.offset = offset
        }
        func setVertexBuffers(_ buffers: [GPUBuffer], offsets: [Int], index: Int) {}
        func setDepthStencilState(_ state: DepthStencilState?) {}
        func setDepthClipMode(_ mode: DepthClipMode) {}
        func setCullMode(_ mode: CullMode) {
            // Render-pass tests cover the selected face; this capture compares vertex bytes.
            XCTAssertTrue(mode == .back || mode == .front)
        }
        func setFrontFacing(_ winding: Winding) { XCTAssertEqual(winding, .clockwise) }
        func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {}
        func setStencilReferenceValue(_ value: UInt32) { XCTAssertEqual(value, 0) }
        func setStencilReferenceValues(front: UInt32, back: UInt32) {}
        func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {}
        func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D) {}
        func memoryBarrier(after: RenderStages, before: RenderStages) {}
        func draw(vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int) {
            drawCount += 1
            guard let buffer, let contents = buffer.contents() else {
                XCTFail("Missing uploaded vertices")
                return
            }
            XCTAssertEqual(vertexStart, 0)
            XCTAssertEqual(instanceCount, 1)
            XCTAssertEqual(baseInstance, 0)
            XCTAssertLessThanOrEqual(offset + vertexCount * MemoryLayout<Float2>.stride,
                                     buffer.length)
            vertices = Array(UnsafeBufferPointer(
                start: contents.advanced(by: offset).assumingMemoryBound(to: Float2.self),
                count: vertexCount
            ))
            onDraw?()
        }
        func drawIndexed(indexCount: Int, indexType: IndexType, indexBuffer: GPUBuffer,
                         indexBufferOffset: Int, instanceCount: Int, baseVertex: Int,
                         baseInstance: Int) {
            XCTFail("Stroke must preserve the non-indexed vertex draw")
        }
    }

    private func makeContext(scale: CGFloat = 1) throws -> GraphicsContext {
        guard let device = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        return try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(), environment: EnvironmentValues(),
            viewport: CGRect(x: 0, y: 0, width: 32, height: 32),
            contentOffset: .zero, contentScaleFactor: scale,
            resolution: CGSize(width: 32, height: 32), commandBuffer: commands
        ))
    }

    private func capture(_ path: Path, style: StrokeStyle,
                         context: GraphicsContext, reference: Bool = false,
                         onDraw: (() -> Void)? = nil,
                         recordUpload: ((GPUBuffer, Int, [UInt8]) -> Void)? = nil) -> [Float2] {
        let encoder = CaptureEncoder()
        encoder.onDraw = onDraw
        let pass = GraphicsContext.RenderPass(
            encoder: encoder,
            descriptor: RenderPassDescriptor(
                colorAttachments: [.init(renderTarget: context.renderTargets.source)],
                depthStencilAttachment: .init(renderTarget: context.stencilBuffer)
            ), sampleCount: 1
        )
        let encoded = reference
            ? context.referenceStrokeCommand(renderPass: pass, path: path, style: style)
            : context.encodeStencilPathStrokeCommand(renderPass: pass, path: path, style: style)
        XCTAssertEqual(encoded, !encoder.vertices.isEmpty)
        XCTAssertEqual(encoder.drawCount, encoded ? 1 : 0)
        XCTAssertEqual(encoder.vertices.count % 3, 0)
        pass.end()
        if let recordUpload, let upload = encoder.upload {
            recordUpload(upload.0, upload.1, upload.2)
        }
        return encoder.vertices
    }

    private func assertGeometry(_ path: Path, style: StrokeStyle,
                                context: GraphicsContext, label: String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        let expected = capture(path, style: style, context: context, reference: true)
        let actual = capture(path, style: style, context: context)
        XCTAssertEqual(actual.count, expected.count, label, file: file, line: line)
        let words = actual.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        let referenceWords = expected.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        XCTAssertEqual(words, referenceWords, label, file: file, line: line)
    }

    private func polyline(reversed: Bool = false, closed: Bool = false) -> Path {
        let points = [CGPoint(x: 4, y: 6), CGPoint(x: 20, y: 6),
                      CGPoint(x: 12, y: 20), CGPoint(x: 26, y: 14)]
        return Path { path in
            let points = reversed ? Array(points.reversed()) : points
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            if closed { path.closeSubpath() }
        }
    }

    private func curvedPath() -> Path {
        Path { path in
            path.move(to: CGPoint(x: 3, y: 8))
            path.addQuadCurve(to: CGPoint(x: 14, y: 12), control: CGPoint(x: 6, y: 24))
            path.addCurve(to: CGPoint(x: 27, y: 9),
                          control1: CGPoint(x: 17, y: -3), control2: CGPoint(x: 24, y: 28))
            path.addLine(to: CGPoint(x: 17, y: 25))
        }
    }

    func testStrokeCapsJoinsAndMiterLimitsPreserveVertexBits() throws {
        let context = try makeContext()
        for reversed in [false, true] {
            for closed in [false, true] {
                for cap in [CGLineCap.butt, .square, .round] {
                    for join in [CGLineJoin.miter, .bevel, .round] {
                        for limit: CGFloat in [0, 1, 2, 10] {
                            for width: CGFloat in [0.5, 4] {
                                let style = StrokeStyle(lineWidth: width, lineCap: cap,
                                                        lineJoin: join, miterLimit: limit)
                                assertGeometry(polyline(reversed: reversed, closed: closed),
                                               style: style, context: context,
                                               label: "\(reversed)/\(closed)/\(style)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testRoundJoinEndpointsPreserveBitsAcrossStepBoundariesAndTransforms() throws {
        let widths: [CGFloat] = [
            0.5, CGFloat(1).nextDown, 1, CGFloat(1).nextUp,
            CGFloat(8).nextDown, 8, CGFloat(8).nextUp, 31.25, 32
        ]
        let transforms: [CGAffineTransform] = [
            .identity,
            .init(a: 1.25, b: -0.375, c: 0.625, d: 0.875, tx: 13, ty: -7),
            .init(scaleX: -1, y: 0),
            .init(a: 0.03125, b: -3.25, c: 1.625, d: 0.125,
                  tx: 10_000_000_000.25, ty: -10_000_000_000.75)
        ]
        let paths = [
            polyline(), polyline(reversed: true),
            polyline(closed: true), polyline(reversed: true, closed: true), curvedPath()
        ]
        for transform in transforms {
            var context = try makeContext(scale: 2)
            context.transform = transform
            for width in widths {
                for dash: [CGFloat] in [[], [4, 2, 1]] {
                    let style = StrokeStyle(lineWidth: width, lineCap: .round,
                                            lineJoin: .round, dash: dash, dashPhase: -3.5)
                    for path in paths {
                        assertGeometry(path, style: style, context: context,
                                       label: "\(transform)/\(style)")
                    }
                }
            }
        }
    }

    func testStrokeMiterCutoffAndNearlyCollinearTurnsPreserveVertexBits() throws {
        let context = try makeContext()
        let cutoff = 1 / sin(acos(CGFloat.zero) * 0.5)
        for endY: CGFloat in [5, 27] {
            let corner = Path { path in
                path.move(to: CGPoint(x: 5, y: 16))
                path.addLine(to: CGPoint(x: 16, y: 16))
                path.addLine(to: CGPoint(x: 16, y: endY))
            }
            for limit in [cutoff.nextDown, cutoff, cutoff.nextUp] {
                let style = StrokeStyle(lineWidth: 4, miterLimit: limit)
                assertGeometry(corner, style: style, context: context)
                XCTAssertEqual(capture(corner, style: style, context: context).count,
                               limit < cutoff ? 15 : 18)
            }
        }
        for end in [CGPoint(x: 27, y: 16), CGPoint(x: 5, y: 16),
                    CGPoint(x: 27, y: CGFloat(16).nextUp),
                    CGPoint(x: 5.001, y: 16.001)] {
            let turn = Path { path in
                path.move(to: CGPoint(x: 5, y: 16))
                path.addLine(to: CGPoint(x: 16, y: 16))
                path.addLine(to: end)
            }
            for join in [CGLineJoin.miter, .bevel, .round] {
                assertGeometry(turn, style: StrokeStyle(lineWidth: 4, lineJoin: join),
                               context: context)
            }
        }
    }

    func testStrokeDashPhaseVisibilityAndContourResetPreserveVertexBits() throws {
        var contours = polyline()
        contours.addPath(polyline(reversed: true, closed: true),
                         transform: CGAffineTransform(translationX: 31, y: -4))
        let patterns: [[CGFloat]] = [
            [], [0, 0], [0, 2, 0, 3], [3, 2], [3, 1, 2], [-3, 2],
            [0.5, 0.5], [CGFloat(0.5).nextDown, CGFloat(0.5).nextDown],
            [CGFloat(0.5).nextUp, CGFloat(0.5).nextUp]
        ]
        for scale: CGFloat in [0.5, 1, 2] {
            let context = try makeContext(scale: scale)
            for dash in patterns {
                for phase: CGFloat in [-19, -6, -0.5, 0, 0.5, 6, 19] {
                    for cap in [CGLineCap.butt, .square, .round] {
                        let style = StrokeStyle(lineWidth: 2, lineCap: cap,
                                                lineJoin: .round, dash: dash, dashPhase: phase)
                        assertGeometry(contours, style: style, context: context,
                                       label: "scale \(scale)/\(style)")
                    }
                }
            }
        }
    }

    func testStrokeCurvesDegeneraciesAndTransformsPreserveVertexBits() throws {
        let degenerate = Path { path in
            path.move(to: CGPoint(x: 4, y: 4))
            path.addLine(to: CGPoint(x: 4, y: 4))
            path.addQuadCurve(to: CGPoint(x: 12, y: 4), control: CGPoint(x: 4, y: 4))
            path.addCurve(to: CGPoint(x: 12, y: 4),
                          control1: CGPoint(x: 12, y: 4), control2: CGPoint(x: 12, y: 4))
            path.closeSubpath()
            path.closeSubpath()
            path.addLine(to: CGPoint(x: 8, y: 16))
            path.move(to: CGPoint(x: 5, y: 9))
        }
        let transforms: [CGAffineTransform] = [
            .identity, .init(translationX: 13.25, y: -7.5),
            .init(a: 1.25, b: -0.375, c: 0.625, d: 0.875, tx: 13, ty: -7),
            .init(scaleX: -0.75, y: 1.5), .init(scaleX: 0, y: 0.5)
        ]
        var context = try makeContext()
        for transform in transforms {
            context.transform = transform
            for path in [curvedPath(), degenerate,
                         Path(ellipseIn: CGRect(x: 3.25, y: 4.5, width: 24.5, height: 21.25))] {
                for cap in [CGLineCap.butt, .square, .round] {
                    for join in [CGLineJoin.miter, .bevel, .round] {
                        assertGeometry(path, style: StrokeStyle(
                            lineWidth: 3.25, lineCap: cap, lineJoin: join, dash: [4, 2, 1],
                            dashPhase: -3.5
                        ), context: context, label: "\(transform)/\(cap)/\(join)")
                    }
                }
            }
        }
    }

    func testStrokeEmptyAndSuppressedPathsDoNotDraw() throws {
        let context = try makeContext()
        let moveOnly = Path { $0.move(to: CGPoint(x: 4, y: 4)) }
        let zeroCurve = Path { path in
            path.move(to: .zero)
            path.addCurve(to: .zero, control1: .zero, control2: .zero)
            path.closeSubpath()
        }
        for path in [Path(), moveOnly, zeroCurve] {
            for cap in [CGLineCap.butt, .square, .round] {
                let style = StrokeStyle(lineWidth: 3, lineCap: cap)
                XCTAssertTrue(capture(path, style: style, context: context).isEmpty)
                assertGeometry(path, style: style, context: context)
            }
        }
        for width: CGFloat in [-2, 0, CGFloat.ulpOfOne.nextDown] {
            XCTAssertTrue(capture(polyline(), style: StrokeStyle(lineWidth: width),
                                  context: context).isEmpty)
        }
        // At the width gate itself a nondegenerate line still emits two triangles.
        let line = Path { path in
            path.move(to: CGPoint(x: 4, y: 4))
            path.addLine(to: CGPoint(x: 20, y: 4))
        }
        XCTAssertEqual(capture(line, style: StrokeStyle(lineWidth: .ulpOfOne),
                               context: context).count, 6)
    }

    func testStrokeInterleavingPreservesFillSnapshotsAndEarlierUploads() throws {
        let context = try makeContext(scale: 2)
        var copy = context
        copy.transform = .init(a: -1, b: 0.25, c: 0.5, d: 0.75, tx: 4, ty: -3)
        let layer = try XCTUnwrap(context.makeLayerContext())
        let sizedLayer = try XCTUnwrap(context.makeLayerContext(CGSize(width: 16, height: 12)))
        let snapshot = context.pathGeometryScratch.makeGeometry(
            path: curvedPath(), transform: .identity
        )
        let snapshotVertices = snapshot.vertices.withUnsafeBytes { Array($0) }
        let snapshotIndices = snapshot.triangleIndices.withUnsafeBytes { Array($0) }
        var uploads: [(GPUBuffer, Int, [UInt8])] = []
        let paths = [
            curvedPath(), Path(), polyline(reversed: true, closed: true),
            Path { $0.move(to: CGPoint(x: 4, y: 4)) }, polyline()
        ]
        let styles = [
            StrokeStyle(lineWidth: 3.25, lineCap: .round, lineJoin: .round,
                        dash: [4, 2, 1], dashPhase: -3.5),
            StrokeStyle(lineWidth: 0), StrokeStyle(lineWidth: 1)
        ]
        for active in [context, copy, layer, sizedLayer] {
            for path in paths {
                for style in styles {
                    let expected = capture(path, style: style, context: active, reference: true)
                    let actual = capture(path, style: style, context: active,
                                         recordUpload: { uploads.append(($0, $1, $2)) })
                    XCTAssertEqual(actual.withUnsafeBytes { Array($0) },
                                   expected.withUnsafeBytes { Array($0) })
                    let fillPath = Path(CGRect(x: -3, y: 2, width: 19, height: 7))
                    let transform = active.transform.concatenating(active.viewTransform)
                    let fill = active.pathGeometryScratch.makeGeometry(
                        path: fillPath, transform: transform
                    )
                    let expectedFill = GraphicsContext.StencilPathFillGeometry(
                        path: fillPath, transform: transform
                    )
                    XCTAssertEqual(fill.vertices.withUnsafeBytes { Array($0) },
                                   expectedFill.vertices.withUnsafeBytes { Array($0) })
                    XCTAssertEqual(fill.triangleIndices.withUnsafeBytes { Array($0) },
                                   expectedFill.triangleIndices.withUnsafeBytes { Array($0) })
                    let vertices = try XCTUnwrap(active.makeBuffer(fill.vertices))
                    let indices = try XCTUnwrap(active.makeBuffer(fill.triangleIndices))
                    uploads.append((vertices.buffer, vertices.offset,
                                    fill.vertices.withUnsafeBytes { Array($0) }))
                    uploads.append((indices.buffer, indices.offset,
                                    fill.triangleIndices.withUnsafeBytes { Array($0) }))
                }
            }
        }
        XCTAssertEqual(uploads.count, 144)
        XCTAssertEqual(snapshot.vertices.withUnsafeBytes { Array($0) }, snapshotVertices)
        XCTAssertEqual(snapshot.triangleIndices.withUnsafeBytes { Array($0) }, snapshotIndices)
        for (buffer, offset, bytes) in uploads {
            let contents = try XCTUnwrap(buffer.contents())
            let actual = Array(UnsafeRawBufferPointer(
                start: contents.advanced(by: offset), count: bytes.count
            ))
            XCTAssertEqual(actual, bytes)
        }
    }

    func testStrokeReentrantRecordingPreservesBorrowedAndRetainedGeometry() throws {
        let context = try makeContext()
        let path = curvedPath()
        let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        let expected = capture(path, style: style, context: context, reference: true)
        let nestedPath = polyline(reversed: true)
        let expectedNested = capture(nestedPath, style: style, context: context, reference: true)
        var nestedVertices: [Float2] = []
        var nestedFill: GraphicsContext.StencilPathFillGeometry?
        var nestedFillBytes: [UInt8] = []
        let actual = capture(path, style: style, context: context, onDraw: {
            nestedVertices = self.capture(nestedPath, style: style, context: context)
            let fill = context.pathGeometryScratch.makeGeometry(
                path: nestedPath, transform: .identity
            )
            nestedFillBytes = fill.vertices.withUnsafeBytes { Array($0) }
            nestedFill = fill
        })
        XCTAssertEqual(actual.withUnsafeBytes { Array($0) },
                       expected.withUnsafeBytes { Array($0) })
        XCTAssertEqual(nestedVertices.withUnsafeBytes { Array($0) },
                       expectedNested.withUnsafeBytes { Array($0) })
        _ = capture(polyline(closed: true), style: StrokeStyle(lineWidth: 1), context: context)
        _ = context.pathGeometryScratch.makeGeometry(path: Path(), transform: .identity)
        let retained = try XCTUnwrap(nestedFill)
        XCTAssertEqual(retained.vertices.withUnsafeBytes { Array($0) }, nestedFillBytes)
    }

    func testStrokeReturnsReusableVertexCapacityAcrossEarlyExits() throws {
        let context = try makeContext()
        let large = Path { path in
            path.move(to: .zero)
            for index in 1..<1024 {
                path.addLine(to: CGPoint(x: index, y: index % 17))
            }
        }
        let style = StrokeStyle(lineWidth: 3)
        let count = capture(large, style: style, context: context, reference: true).count
        XCTAssertGreaterThan(count, 6000)
        XCTAssertEqual(capture(large, style: style, context: context).count, count)
        func fillStorage() -> (address: UInt, capacity: Int) {
            let geometry = context.pathGeometryScratch.makeGeometry(
                path: Path(CGRect(x: 1, y: 2, width: 3, height: 4)), transform: .identity
            )
            XCTAssertEqual(geometry.vertices.count, 5)
            return (geometry.vertices.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) },
                    geometry.vertices.capacity)
        }
        let initial = fillStorage()
        XCTAssertGreaterThanOrEqual(initial.capacity, count)
        let moveOnly = Path { $0.move(to: CGPoint(x: 4, y: 4)) }
        XCTAssertFalse(moveOnly.isEmpty)
        for (path, style) in [
            (Path(), style), (moveOnly, style),
            (polyline(), StrokeStyle(lineWidth: 0)),
            (curvedPath(), StrokeStyle(lineWidth: 1))
        ] {
            assertGeometry(path, style: style, context: context)
            let reused = fillStorage()
            XCTAssertEqual(reused.address, initial.address)
            XCTAssertEqual(reused.capacity, initial.capacity)
        }
    }

    func testStrokePreservesMetalPixelsAcrossCapsJoinsAndDashes() throws {
        guard let device = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let queue = try XCTUnwrap(device.renderQueue())
        let bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        let background = BackendColor(0.3, 0.2, 0.1, 0.5)
        let shading = GraphicsContext.Shading.color(VUI.Color.red.opacity(0.37))
        func render(path: Path, style: StrokeStyle, reference: Bool,
                    msaa: Bool) throws -> [UInt8] {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            let context = try XCTUnwrap(GraphicsContext(
                sceneResources: SceneResources(), environment: EnvironmentValues(),
                viewport: bounds, contentOffset: .zero, contentScaleFactor: 1,
                resolution: bounds.size, commandBuffer: commands
            ))
            context.clear(with: background)
            if reference {
                let pass = try XCTUnwrap(context.beginRenderPass(
                    enableStencil: true, enableMSAA: msaa
                ))
                XCTAssertTrue(context.referenceStrokeCommand(
                    renderPass: pass, path: path, style: style
                ))
                context.encodeShadingBoxCommand(renderPass: pass, shading: shading,
                                                 stencil: .testNonZero, blendState: .opaque)
                pass.end()
                context.drawSource()
            } else {
                context.stroke(path, with: shading, style: style, isAntialiased: msaa)
            }
            let condition = NSCondition()
            var completed = false
            commands.addCompletedHandler { _ in
                condition.lock()
                completed = true
                condition.broadcast()
                condition.unlock()
            }
            condition.lock()
            XCTAssertTrue(commands.commit())
            let timeout = Date(timeIntervalSinceNow: 5)
            while !completed {
                if !condition.wait(until: timeout) { break }
            }
            condition.unlock()
            XCTAssertTrue(completed, "GPU command buffer timed out")
            guard completed else { return [] }
            let staging = try XCTUnwrap(device.makeCPUAccessible(texture: context.backdrop))
            let contents = try XCTUnwrap(staging.contents())
            return Array(UnsafeRawBufferPointer(start: contents, count: 32 * 32 * 4))
        }
        for cap in [CGLineCap.butt, .square, .round] {
            for join in [CGLineJoin.miter, .bevel, .round] {
                for msaa in [false, true] {
                    for dashed in [false, true] {
                        let style = StrokeStyle(
                            lineWidth: 3.25, lineCap: cap, lineJoin: join,
                            miterLimit: 2, dash: dashed ? [4, 2, 1] : [], dashPhase: -3.5
                        )
                        let path = dashed ? curvedPath() : polyline()
                        let expected = try render(path: path, style: style,
                                                  reference: true, msaa: msaa)
                        let actual = try render(path: path, style: style,
                                                reference: false, msaa: msaa)
                        XCTAssertEqual(actual.count, 32 * 32 * 4)
                        XCTAssertEqual(actual, expected, "\(style)/MSAA \(msaa)")
                        // Prove that both paths did more than clear the target.
                        XCTAssertGreaterThan(Set(actual).count, 4)
                    }
                }
            }
        }
    }
}

// Preserve the previous temporary-array algorithm as an independent output oracle.
private extension GraphicsContext {
    func referenceStrokeCommand(renderPass: RenderPass,
                                        path: Path,
                                        style: StrokeStyle) -> Bool {
        if path.isEmpty { return false }
        if style.lineWidth < .ulpOfOne { return false }

        let minVisibleDashes = 1.0 / self.contentScaleFactor

        let lineWidth = style.lineWidth
        let halfWidth = lineWidth * 0.5

        let dash = style.dash.map { $0.magnitude }
        let numDashes = dash.count
        let dashPatternLength = dash.reduce(0, +)
//        let dashesLength = stride(from: 0, to: dash.count, by: 2).map { dash[$0] }.reduce(0, +)
//        let gapsLength = stride(from: 1, to: dash.count, by: 2).map { dash[$0] }.reduce(0, +)

        let dashLength = { index in dash[index % numDashes] }
        let dashAvailable = (numDashes > 0 && (dashPatternLength / CGFloat(numDashes)) >= minVisibleDashes)

        var dashIndex: Int = 0      // even: dash, odd: gap
        var dashRemain: CGFloat = 0 // remaining length of the current dash(gap)
        if dash.isEmpty == false && dashPatternLength > .ulpOfOne {
            let fullCycleLength = dash.count.isMultiple(of: 2)
                ? dashPatternLength
                : dashPatternLength * 2
            var phase = style.dashPhase.truncatingRemainder(dividingBy: fullCycleLength)
            if phase < 0 { phase += fullCycleLength }
            dashRemain = dashLength(dashIndex)
            if phase > .ulpOfOne {
                while phase > dashRemain {
                    dashIndex += 1
                    dashRemain += dashLength(dashIndex)
                }
                dashRemain -= phase
            }
            while dashRemain < .ulpOfOne {
                dashIndex += 1
                dashRemain += dashLength(dashIndex)
            }
        }
        let _initialDashIndex = dashIndex
        let _initialDashRemain = dashRemain
        let resetDashPhase = {
            dashIndex = _initialDashIndex
            dashRemain = _initialDashRemain
        }

        var vertexData: [Float2] = []

        let transform = self.transform.concatenating(self.viewTransform)
        let drawLineSegment = { (start: CGPoint, end: CGPoint, dir0: CGPoint, dir1: CGPoint) in
            let t0 = CGAffineTransform(a: dir0.x, b: dir0.y,
                                       c: -lineWidth * dir0.y,
                                       d: lineWidth * dir0.x,
                                       tx: start.x, ty: start.y)

            let t1 = CGAffineTransform(a: dir1.x, b: dir1.y,
                                       c: -lineWidth * dir1.y,
                                       d: lineWidth * dir1.x,
                                       tx: end.x, ty: end.y)

            let box = [Vector2(0, -0.5).applying(t0),
                       Vector2(0, -0.5).applying(t1),
                       Vector2(0,  0.5).applying(t0),
                       Vector2(0,  0.5).applying(t1)].map {
                $0.applying(transform)
            }

            vertexData.append(contentsOf: [
                box[2].float2, box[0].float2, box[3].float2,
                box[3].float2, box[0].float2, box[1].float2])
        }

        let addStrokeCap = { (p: CGPoint, d: CGPoint) in
            switch style.lineCap {
            case .round:
                let trans = CGAffineTransform(a: d.x, b: d.y,
                                              c: -d.y, d: d.x,
                                              tx: p.x, ty: p.y)
                    .concatenating(transform)

                let step = CGFloat.pi / lineWidth
                var progress = CGFloat.zero

                let center = Vector2(p).applying(transform)
                var pt0 = Vector2(0, -halfWidth).applying(trans)
                while progress < .pi {
                    let pt1 = Vector2(0, -halfWidth).applying(
                            CGAffineTransform(rotationAngle: progress)
                                .concatenating(trans))

                    vertexData.append(contentsOf: [center.float2,
                                                   pt0.float2,
                                                   pt1.float2])
                    pt0 = pt1
                    progress += step
                }
                let pt1 = Vector2(0, halfWidth).applying(trans)
                vertexData.append(contentsOf: [center.float2,
                                               pt0.float2,
                                               pt1.float2])
            case .square:
                let trans = CGAffineTransform(a: lineWidth * d.x,
                                              b: lineWidth * d.y,
                                              c: lineWidth * -d.y,
                                              d: lineWidth * d.x,
                                              tx: p.x, ty: p.y)
                    .concatenating(transform)

                let pt = [Vector2(0.0,  0.5),
                          Vector2(0.0, -0.5),
                          Vector2(0.5,  0.5),
                          Vector2(0.5, -0.5)].map {
                    $0.applying(trans).float2
                }
                vertexData.append(contentsOf: [pt[0], pt[1], pt[2],
                                             pt[2], pt[1], pt[3]])
            default:
                return
            }
        }

        let addStrokeLine = { (p0: CGPoint, p1: CGPoint, d0: CGPoint, d1: CGPoint) in
            let d = p1 - p0
            let length = d.magnitude
            if length < .ulpOfOne { return }
            if dashAvailable {
                var drawn: CGFloat = 0
                var start = p0
                var dir0 = d0
                var drawLineCap = false
                while drawn < length {

                    while dashRemain < .ulpOfOne {
                        dashIndex += 1
                        dashRemain += dashLength(dashIndex)
                        drawLineCap = true
                    }

                    let remains = length - drawn
                    let len = min(remains, dashRemain)

                    if len > .ulpOfOne {
                        let t = (drawn + len) / length
                        let end = lerp(p0, p1, t)
                        let dir1 = lerp(d0, d1, t)

                        if dashIndex % 2 == 0 {
                            if drawLineCap {
                                addStrokeCap(start, -dir1)
                                drawLineCap = false
                            }
                            drawLineSegment(start, end, dir0, dir1)
                            if len == dashRemain {
                                addStrokeCap(end, dir1)
                            }
                        }
                        start = end
                        dir0 = dir1
                    }
                    drawn += len
                    dashRemain -= len
                }
            } else {
                drawLineSegment(p0, p1, d0, d1)
            }
        }
        let addStrokeJoin = { (p: CGPoint, dir0: CGPoint, dir1: CGPoint) in

            if 1.0 - CGPoint.dot(dir0, dir1) < .ulpOfOne { return }

            var join = style.lineJoin
            if join == .miter {
                let dot = CGPoint.dot(-dir0, dir1)
                let angle = acos(dot)
                let s = sin(angle * 0.5)
                if s > .ulpOfOne {
                    let miterLength = lineWidth / s
                    if miterLength > style.miterLimit * lineWidth {
                        join = .bevel
                    }
                } else {
                    join = .bevel
                }
            }

            let angle = { (d: CGPoint) -> CGFloat in
                if d.y < 0 {
                    return .pi * 2 - acos(d.x)
                }
                return acos(d.x)
            }
            var r1 = angle(dir0)
            var r2 = angle(dir1)
            if (r1 - r2).magnitude > .pi {
                if r1 > r2 { r2 += .pi * 2 }
                else { r1 += .pi * 2}
            }

            switch join {
            case .bevel:
                let t0 = CGAffineTransform(a: dir0.x, b: dir0.y,
                                           c: -lineWidth * dir0.y,
                                           d: lineWidth * dir0.x,
                                           tx: p.x, ty: p.y)

                let t1 = CGAffineTransform(a: dir1.x, b: dir1.y,
                                           c: -lineWidth * dir1.y,
                                           d: lineWidth * dir1.x,
                                           tx: p.x, ty: p.y)
                if r1 > r2 {
                    let pt = [Vector2(p),
                              Vector2(0,  0.5).applying(t0),
                              Vector2(0,  0.5).applying(t1)].map {
                        $0.applying(transform).float2
                    }
                    vertexData.append(contentsOf: [pt[0], pt[2], pt[1]])

                } else {
                    let pt = [Vector2(p),
                              Vector2(0, -0.5).applying(t0),
                              Vector2(0, -0.5).applying(t1)].map {
                        $0.applying(transform).float2
                    }
                    vertexData.append(contentsOf: [pt[0], pt[1], pt[2]])
                }
            case .round:
                let step = 1.0 / lineWidth
                var progress: CGFloat = step
                let p0 = Vector2(p)
                if r1 > r2 {
                    var p1 = Vector2(0, halfWidth).rotated(by: r1)
                    while progress < 1.0 {
                        let r = lerp(r1, r2, progress)
                        let p2 = Vector2(0, halfWidth).rotated(by: r)
                        vertexData.append(contentsOf: [p0, p2 + p0, p1 + p0].map {
                            $0.applying(transform).float2
                        })
                        progress += step
                        p1 = p2
                    }
                    let p2 = Vector2(0, halfWidth).rotated(by: r2)
                    vertexData.append(contentsOf: [p0, p2 + p0, p1 + p0].map {
                        $0.applying(transform).float2
                    })
                } else {
                    var p1 = Vector2(0, -halfWidth).rotated(by: r1)
                    while progress < 1.0 {
                        let r = lerp(r1, r2, progress)
                        let p2 = Vector2(0, -halfWidth).rotated(by: r)
                        vertexData.append(contentsOf: [p0, p1 + p0, p2 + p0].map {
                            $0.applying(transform).float2
                        })
                        progress += step
                        p1 = p2
                    }
                    let p2 = Vector2(0, -halfWidth).rotated(by: r2)
                    vertexData.append(contentsOf: [p0, p1 + p0, p2 + p0].map {
                        $0.applying(transform).float2
                    })
                }
            case .miter:
                let t0 = CGAffineTransform(a: dir0.x, b: dir0.y,
                                           c: -lineWidth * dir0.y,
                                           d: lineWidth * dir0.x,
                                           tx: p.x, ty: p.y)

                let t1 = CGAffineTransform(a: dir1.x, b: dir1.y,
                                           c: -lineWidth * dir1.y,
                                           d: lineWidth * dir1.x,
                                           tx: p.x, ty: p.y)
                let dir0 = Vector2(dir0)
                let dir1 = Vector2(dir1)
                if r1 > r2 {
                    let pt = [Vector2(0, 0.5).applying(t0),
                              Vector2(0, 0.5).applying(t1)]

                    let p0 = Vector2(p)
                    let s = Vector2.cross(dir0, dir1)
                    let t = Vector2.cross(pt[1] - pt[0], dir1) / s
                    let p1 = pt[0] + dir0 * t

                    let triangles = [p0, p1, pt[0], p0, pt[1], p1].map {
                        $0.applying(transform).float2
                    }
                    vertexData.append(contentsOf: triangles)
                } else {
                    let pt = [Vector2(0, -0.5).applying(t0),
                              Vector2(0, -0.5).applying(t1)]

                    let p0 = Vector2(p)
                    let s = Vector2.cross(dir0, dir1)
                    let t = Vector2.cross(pt[1] - pt[0], dir1) / s
                    let p1 = pt[0] + dir0 * t

                    let triangles = [p0, pt[0], p1, p0, p1, pt[1]].map {
                        $0.applying(transform).float2
                    }
                    vertexData.append(contentsOf: triangles)
                }
            @unknown default:
                fatalError("Unknown value")
            }
        }

        var initialPoint: CGPoint? = nil
        var currentPoint: CGPoint? = nil
        var initialDir: CGPoint? = nil
        var currentDir: CGPoint? = nil
        path.forEach { element in
            switch element {
            case .move(let to):
                if let p0 = initialPoint, let d0 = initialDir,
                   let p1 = currentPoint, let d1 = currentDir {

                    if dashIndex % 2 == 0 {
                        // line cap current point
                        addStrokeCap(p1, d1)
                    }
                    resetDashPhase()
                    if dashIndex % 2 == 0 {
                        // line cap initial point
                        addStrokeCap(p0, -d0)
                    }
                }

                initialPoint = to
                currentPoint = to
                initialDir = nil
                currentDir = nil
                resetDashPhase()
            case .line(let p1):
                if let p0 = currentPoint {
                    let d = p1 - p0
                    let length = d.magnitude
                    if length > .ulpOfOne {
                        let d1 = d / length
                        if let d0 = currentDir, dashIndex % 2 == 0 {
                            addStrokeJoin(p0, d0, d1)
                        }
                        addStrokeLine(p0, p1, d1, d1)
                        currentDir = d1
                        initialDir = initialDir ?? currentDir
                    }
                }
                currentPoint = p1
            case .quadCurve(let p2, let p1):
                if let p0 = currentPoint {
                    let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                    let length = curve.approximateLength()
                    if length > .ulpOfOne {
                        let step = 1.0 / length
                        var t = step
                        var pt0 = p0
                        var d0 = currentDir ?? (p1 - p0).normalized()
                        while t < 1.0 {
                            let pt1 = curve.interpolate(t)
                            let d1 = curve.tangent(t).normalized()
                            addStrokeLine(pt0, pt1, d0, d1)
                            pt0 = pt1
                            d0 = d1
                            t += step
                        }
                        let d1 = (p2 - p1).normalized()
                        addStrokeLine(pt0, p2, d0, d1)
                        currentDir = d1
                        initialDir = initialDir ?? currentDir
                    }
                }
                currentPoint = p2
            case .curve(let p3, let p1, let p2):
                if let p0 = currentPoint {
                    let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                    let length = curve.approximateLength()
                    if length > .ulpOfOne {
                        let step = 1.0 / length
                        var t = step
                        var pt0 = p0
                        var d0 = currentDir ?? (p1 - p0).normalized()
                        while t < 1.0 {
                            let pt1 = curve.interpolate(t)
                            let d1 = curve.tangent(t).normalized()
                            addStrokeLine(pt0, pt1, d0, d1)
                            pt0 = pt1
                            d0 = d1
                            t += step
                        }
                        let d1 = (p3 - p2).normalized()
                        addStrokeLine(pt0, p3, d0, d1)
                        currentDir = d1
                        initialDir = initialDir ?? currentDir
                    }
                }
                currentPoint = p3
            case .closeSubpath:
                if let p0 = currentPoint, let p1 = initialPoint {
                    let diff = p1 - p0
                    let length = diff.magnitude
                    if length > .ulpOfOne {
                        let d = diff / length
                        if let d0 = currentDir, dashIndex % 2 == 0 {
                            addStrokeJoin(p0, d0, d)
                        }
                        addStrokeLine(p0, p1, d, d)
                        if let d1 = initialDir {
                            if dashIndex % 2 == 0 {
                                resetDashPhase()
                                if dashIndex % 2 == 0 {
                                    // join with initial point
                                    addStrokeJoin(p1, d, d1)
                                } else {
                                    // line cap current point
                                    addStrokeCap(p1, d)
                                }
                            } else {
                                resetDashPhase()
                                if dashIndex % 2 == 0 {
                                    // line cap initial point
                                    addStrokeCap(p1, -d1)
                                }
                            }
                        }
                    } else if let d0 = currentDir, let d1 = initialDir {
                        resetDashPhase()
                        if dashIndex % 2 == 0 {
                            addStrokeJoin(p1, d0, d1)
                        }
                    }
                }
                currentPoint = initialPoint
                initialDir = nil
                currentDir = nil
                resetDashPhase()
            }
        }
        if let p0 = initialPoint, let d0 = initialDir,
           let p1 = currentPoint, let d1 = currentDir {
            if dashIndex % 2 == 0 {
                addStrokeCap(p1, d1)
            }
            resetDashPhase()
            if dashIndex % 2 == 0 {
                addStrokeCap(p0, -d0)
            }
        }

        if vertexData.count < 3 { return false }

        guard let vertexBuffer = self.makeBuffer(vertexData) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }

        // pipeline states for generate polygon winding numbers
        guard let pipelineState = pipeline.renderState(
            shader: .stencil,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: BlendState(writeMask: []),
            sampleCount: renderPass.sampleCount) else {
            Log.err("GraphicsContext error: pipeline.renderState failed.")
            return false
        }
        guard let depthState = pipeline.depthStencilState(.makeStroke) else {
            Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
            return false
        }

        let encoder = renderPass.encoder

        // pass1: Generate polygon winding numbers to stencil buffer
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)

        encoder.setCullMode(.back)
        encoder.setFrontFacing(.clockwise)
        encoder.setStencilReferenceValue(0)
        encoder.setVertexBuffer(
            vertexBuffer.buffer,
            offset: vertexBuffer.offset,
            index: 0
        )
        encoder.draw(vertexStart: 0,
                     vertexCount: vertexData.count,
                     instanceCount: 1,
                     baseInstance: 0)
        return true
    }

}
