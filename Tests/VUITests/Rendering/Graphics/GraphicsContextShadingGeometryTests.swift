import XCTest
import VVD
@testable import VUI

private typealias Color = VUI.Color

final class GraphicsContextShadingGeometryTests: XCTestCase {
    private final class CaptureEncoder: RenderCommandEncoder {
        var isCompleted = false
        var commandBuffer: CommandBuffer { fatalError("Only vertex uploads are captured") }
        private var buffer: GPUBuffer?
        private var offset = 0
        var vertices: [_Vertex] = []

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
        func setCullMode(_ mode: CullMode) {}
        func setFrontFacing(_ winding: Winding) {}
        func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {}
        func setStencilReferenceValue(_ value: UInt32) {}
        func setStencilReferenceValues(front: UInt32, back: UInt32) {}
        func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {}
        func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D) {}
        func memoryBarrier(after: RenderStages, before: RenderStages) {}
        func draw(vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int) {
            guard let buffer, let contents = buffer.contents() else {
                XCTFail("Missing uploaded vertices")
                return
            }
            XCTAssertEqual(vertexStart, 0)
            XCTAssertEqual(instanceCount, 1)
            XCTAssertEqual(baseInstance, 0)
            XCTAssertLessThanOrEqual(offset + vertexCount * MemoryLayout<_Vertex>.stride,
                                     buffer.length)
            vertices = Array(UnsafeBufferPointer(
                start: contents.advanced(by: offset).assumingMemoryBound(to: _Vertex.self),
                count: vertexCount
            ))
        }
        func drawIndexed(indexCount: Int, indexType: IndexType, indexBuffer: GPUBuffer,
                         indexBufferOffset: Int, instanceCount: Int, baseVertex: Int,
                         baseInstance: Int) {
            XCTFail("Shading must preserve the non-indexed vertex draw")
        }
    }

    private final class ResolutionCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
        func increment() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    private struct CounterKey: EnvironmentKey {
        static let defaultValue: ResolutionCounter? = nil
    }

    private enum CountingColorDefinition: SystemColorDefinition {
        static func value(for type: SystemColorType,
                          environment: EnvironmentValues) -> Color.ResolvedHDR {
            environment[CounterKey.self]?.increment()
            return Color.ResolvedHDR(Color(
                .displayP3,
                red: environment.colorScheme == .dark ? 0.75 : 0.25,
                green: environment.colorSchemeContrast == .increased ? 0.6 : 0.4,
                blue: type == .primary ? 0.2 : 0.8,
                opacity: 0.65
            ).resolve(in: environment))
        }
    }

    private func makeContext() throws -> GraphicsContext {
        guard let deviceContext = makeGraphicsDeviceContext() else {
            throw XCTSkip("Graphics device unavailable")
        }
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        return try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(), environment: EnvironmentValues(),
            viewport: CGRect(x: 0, y: 0, width: 32, height: 32),
            contentOffset: .zero, contentScaleFactor: 1,
            resolution: CGSize(width: 32, height: 32), commandBuffer: commandBuffer
        ))
    }

    private func capture(_ shading: GraphicsContext.Shading,
                         in context: GraphicsContext) -> [_Vertex] {
        let encoder = CaptureEncoder()
        let pass = GraphicsContext.RenderPass(
            encoder: encoder,
            descriptor: RenderPassDescriptor(colorAttachments: [
                .init(renderTarget: context.renderTargets.source)
            ]),
            sampleCount: 1
        )
        context.encodeShadingBoxCommand(
            renderPass: pass, shading: shading, stencil: .ignore, blendState: .opaque
        )
        pass.end()
        return encoder.vertices
    }

    private func assertBitsEqual(_ actual: [_Vertex], _ expected: [_Vertex],
                                 _ label: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(MemoryLayout<_Vertex>.stride, 8 * MemoryLayout<Float>.stride,
                       file: file, line: line)
        XCTAssertEqual(actual.count, expected.count, label, file: file, line: line)
        let actualWords = actual.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        let expectedWords = expected.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        XCTAssertEqual(actualWords, expectedWords, label, file: file, line: line)
    }

    func testSolidShadingResolvesOnceAndReevaluatesEnvironment() throws {
        var context = try makeContext()
        let counter = ResolutionCounter()
        context.environment[CounterKey.self] = counter
        context.environment.systemColorDefinition = .init(base: CountingColorDefinition.self)
        let color = Color.primary.opacity(0.37)
        var previous: [UInt32]?
        for (index, scheme) in [ColorScheme.light, .dark, .light].enumerated() {
            context.environment.colorScheme = scheme
            let actual = capture(.color(color), in: context)
            XCTAssertEqual(counter.value, index * 2 + 1)
            let expected = _premultipliedVertexColor(color.backendColor(in: context.environment))
            XCTAssertEqual(actual.count, 6)
            for vertex in actual {
                XCTAssertEqual([vertex.color.0.bitPattern, vertex.color.1.bitPattern,
                                vertex.color.2.bitPattern, vertex.color.3.bitPattern],
                               [expected.0.bitPattern, expected.1.bitPattern,
                                expected.2.bitPattern, expected.3.bitPattern])
            }
            let words = actual.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
            if let previous { XCTAssertNotEqual(words, previous) }
            previous = words
        }
    }

    func testLinearShadingPreservesEveryUploadedComponentAndResolutionCount() throws {
        var context = try makeContext()
        let counter = ResolutionCounter()
        context.environment[CounterKey.self] = counter
        context.environment.systemColorDefinition = .init(base: CountingColorDefinition.self)
        let p3 = Color(.displayP3, red: 0.9, green: 0.3, blue: 0.1, opacity: 0.6)
        let gradients: [Gradient] = [
            .init(stops: [.init(color: .primary.opacity(0.35), location: 0.2),
                          .init(color: p3, location: 0.6),
                          .init(color: .secondary, location: 0.8)]),
            .init(stops: [.init(color: p3, location: 0.8),
                          .init(color: .primary, location: 0.2),
                          .init(color: .secondary, location: 0.2)]),
            .init(stops: [.init(color: p3, location: -0.25),
                          .init(color: .secondary, location: 1.25)]),
            .init(stops: []),
            .init(stops: [.init(color: .primary.opacity(0.37), location: 0.5)]),
            .init(colors: [.primary]),
            .init(colors: [p3, .black.opacity(0.2)]),
            .init(colors: [.init(.sRGBLinear, red: -0.2, green: 1.4, blue: 0.5,
                                opacity: 0.4), .white])
        ]
        let transforms: [CGAffineTransform] = [
            .identity,
            .init(a: 0.75, b: -0.25, c: 0.125, d: 1.25, tx: 0.25, ty: -0.5),
            .init(scaleX: -1.5, y: 0.75),
            .init(scaleX: 0, y: 1)
        ]
        let points: [(CGPoint, CGPoint)] = [
            (.zero, .init(x: 0.4, y: 0)),
            (.init(x: -0.25, y: 0.125), .init(x: 0.4, y: 0.75)),
            (.init(x: 0.75, y: 0.25), .init(x: -0.5, y: -0.5)),
            (.init(x: -2, y: 0), .init(x: 2, y: 0)),
            (.init(x: 0.25, y: -0.5), .init(x: 0.25, y: -0.5))
        ]
        let options: [GraphicsContext.GradientOptions] = [[], .repeat, .mirror, [.repeat, .mirror]]
        for scheme in [ColorScheme.light, .dark] {
            context.environment.colorScheme = scheme
            context.environment._colorSchemeContrast = .increased
            for transform in transforms {
                context.viewTransform = transform
                let reference = ReferenceShadingGeometry(
                    environment: context.environment, viewTransform: transform
                )
                for (gradientIndex, gradient) in gradients.enumerated() {
                    for (start, end) in points {
                        for option in options {
                            let beforeReference = counter.value
                            let expected = reference.linear(
                                gradient, startPoint: start, endPoint: end, options: option
                            )
                            let referenceResolutions = counter.value - beforeReference
                            let beforeActual = counter.value
                            let actual = capture(.linearGradient(
                                gradient, startPoint: start, endPoint: end, options: option
                            ), in: context)
                            XCTAssertEqual(counter.value - beforeActual, referenceResolutions)
                            assertBitsEqual(actual, expected,
                                "linear \(gradientIndex)/\(scheme)/\(transform)/\(start)/\(end)/\(option)")
                        }
                    }
                }
            }
        }
    }

    func testGradientViewportCornersPreserveAffineAndCollapsedExtents() throws {
        var context = try makeContext()
        let gradient = Gradient(stops: [
            .init(color: .primary.opacity(0.35), location: 0.2),
            .init(color: .init(.displayP3, red: 0.9, green: 0.3, blue: 0.1,
                              opacity: 0.6), location: 0.6),
            .init(color: .secondary, location: 0.8)
        ])
        let transforms: [CGAffineTransform] = [
            .init(a: 1, b: -0.0, c: 0, d: 1, tx: -0.0, ty: 0),
            .init(scaleX: -1, y: 1),
            .init(scaleX: 1, y: -1),
            .init(rotationAngle: .pi / 2),
            .init(a: 0.75, b: -0.25, c: 0.125, d: 1.25, tx: 0.25, ty: -0.5),
            .init(scaleX: 0, y: 1),
            .init(scaleX: 1, y: 0),
            .init(a: -0.0, b: 0, c: 0, d: -0.0, tx: -0.0, ty: 0)
        ]
        let options: [GraphicsContext.GradientOptions] = [[], .repeat, .mirror, [.repeat, .mirror]]
        let lines: [(CGPoint, CGPoint)] = [
            (.init(x: -1, y: 0), .init(x: 1, y: 0)),
            (.init(x: 0, y: -1), .init(x: 0, y: 1)),
            (.init(x: -0.25, y: 0.125), .init(x: 0.4, y: 0.75))
        ]
        let centers: [CGPoint] = [.zero, .init(x: -0.5, y: -0.5),
                                  .init(x: -0.5, y: 0.5), .init(x: 0.5, y: 0.5),
                                  .init(x: 0.5, y: -0.5)]
        for scheme in [ColorScheme.light, .dark] {
            context.environment.colorScheme = scheme
            for transform in transforms {
                context.viewTransform = transform
                let reference = ReferenceShadingGeometry(
                    environment: context.environment, viewTransform: transform
                )
                for option in options {
                    for (start, end) in lines {
                        assertBitsEqual(capture(.linearGradient(
                            gradient, startPoint: start, endPoint: end, options: option
                        ), in: context), reference.linear(
                            gradient, startPoint: start, endPoint: end, options: option
                        ), "linear viewport \(scheme)/\(transform)/\(start)/\(end)/\(option)")
                    }
                    for center in centers {
                        assertBitsEqual(capture(.radialGradient(
                            gradient, center: center, startRadius: 0.25, endRadius: 2,
                            options: option
                        ), in: context), reference.radial(
                            gradient, center: center, startRadius: 0.25, endRadius: 2,
                            options: option
                        ), "radial viewport \(scheme)/\(transform)/\(center)/\(option)")
                    }
                }
            }
        }
    }

    func testRadialShadingResolvesEndpointsOutsideTheAngularLoop() throws {
        var context = try makeContext()
        context.viewTransform = .identity
        let counter = ResolutionCounter()
        context.environment[CounterKey.self] = counter
        context.environment.systemColorDefinition = .init(base: CountingColorDefinition.self)
        // Interior stops stay semantic through normalization; no endpoint lerp is needed.
        let gradient = Gradient(stops: [
            .init(color: .primary, location: 0.25),
            .init(color: .secondary, location: 0.75)
        ])
        let vertices = capture(.radialGradient(
            gradient, center: .zero, startRadius: 0, endRadius: 0.4
        ), in: context)
        XCTAssertGreaterThan(vertices.count, 1000)
        // Three normalized intervals and the outer extension each resolve two endpoints.
        XCTAssertEqual(counter.value, 8)
    }

    func testSolidShadingPreservesEveryUploadedComponent() throws {
        var context = try makeContext()
        let colors: [Color] = [
            .primary, .secondary.opacity(0.37), .red, .clear,
            Color(.sRGB, red: -0.25, green: 1.25, blue: 0.6, opacity: 0.35),
            Color(.sRGBLinear, red: 0.125, green: 0.5, blue: 0.875, opacity: 0.6),
            Color(.displayP3, red: 0.9, green: 0.3, blue: 0.1, opacity: 0.4)
                .opacity(0.75)
        ]
        for scheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                context.environment.colorScheme = scheme
                context.environment._colorSchemeContrast = contrast
                let reference = ReferenceShadingGeometry(
                    environment: context.environment, viewTransform: context.viewTransform
                )
                for color in colors {
                    assertBitsEqual(capture(.color(color), in: context),
                                    reference.solid(color), "\(scheme)/\(contrast)/\(color)")
                }
            }
        }
    }

    func testRadialShadingPreservesClippingReversalAndRepeatVertices() throws {
        var context = try makeContext()
        let gradient = Gradient(stops: [
            .init(color: .primary.opacity(0.35), location: 0.2),
            .init(color: Color(.displayP3, red: 0.9, green: 0.3, blue: 0.1,
                               opacity: 0.6), location: 0.6),
            .init(color: .secondary, location: 0.8)
        ])
        let radii: [(CGFloat, CGFloat)] = [(0, 0.4), (0.2, 0.8), (0.8, 0.2),
                                          (-0.3, 0.7), (0.3, 3), (0.5, 0.5)]
        for scheme in [ColorScheme.light, .dark] {
            context.environment.colorScheme = scheme
            context.environment._colorSchemeContrast = .increased
            for transform in [CGAffineTransform.identity,
                              .init(a: 0.75, b: -0.25, c: 0.125, d: 1.25,
                                    tx: 0.25, ty: -0.5)] {
                context.viewTransform = transform
                let reference = ReferenceShadingGeometry(
                    environment: context.environment, viewTransform: transform
                )
                for (start, end) in radii {
                    for options in [GraphicsContext.GradientOptions(), .repeat, .mirror] {
                        let center = CGPoint(x: 0.125, y: -0.25)
                        let actual = capture(.radialGradient(
                            gradient, center: center, startRadius: start, endRadius: end,
                            options: options
                        ), in: context)
                        assertBitsEqual(actual, reference.radial(
                            gradient, center: center, startRadius: start, endRadius: end,
                            options: options
                        ), "radial \(scheme)/\(transform)/\(start)/\(end)/\(options)")
                    }
                }
            }
        }
    }

    func testRadialShadingPreservesTriangleAndQuadBoundaryVertices() throws {
        var context = try makeContext()
        let step = CGFloat.pi / 45
        func isTriangle(_ radius: CGFloat) -> Bool {
            let point = Vector2(radius, 0)
            return (point.rotated(by: step) - point).magnitudeSquared < .ulpOfOne
        }
        let unit = Vector2(1, 0)
        let edgeSquared = (unit.rotated(by: step) - unit).magnitudeSquared
        var upper = CGFloat((Scalar.ulpOfOne / edgeSquared).squareRoot())
        for _ in 0..<64 {
            if isTriangle(upper) {
                upper = upper.nextUp
            } else if !isTriangle(upper.nextDown) {
                upper = upper.nextDown
            } else {
                break
            }
        }
        let lower = upper.nextDown
        XCTAssertTrue(isTriangle(lower))
        XCTAssertFalse(isTriangle(upper))

        // This gradient leaves one central disk and one clipped annular arc.
        let gradient = Gradient(stops: [
            .init(color: .primary.opacity(0.37), location: 0.5)
        ])
        var progress: CGFloat = 0
        var steps = 0
        while progress < .pi * 2 {
            steps += 1
            progress += step
        }
        context.viewTransform = .identity
        let triangle = capture(.radialGradient(
            gradient, center: .zero, startRadius: lower, endRadius: 4
        ), in: context)
        let quads = capture(.radialGradient(
            gradient, center: .zero, startRadius: upper, endRadius: 4
        ), in: context)
        XCTAssertEqual(triangle.count, steps * 6)
        XCTAssertEqual(quads.count, steps * 9)
        for offset in stride(from: steps * 3, to: quads.count, by: 6) {
            assertBitsEqual([quads[offset + 2]], [quads[offset + 3]], "shared outer vertex")
            assertBitsEqual([quads[offset + 1]], [quads[offset + 4]], "shared inner vertex")
        }

        let radii: [CGFloat] = [0, lower * 0.5, lower.nextDown, lower,
                                upper, upper.nextUp, upper * 2, 0.2]
        let transforms: [CGAffineTransform] = [
            .identity,
            .init(a: 0.75, b: -0.25, c: 0.125, d: 1.25, tx: 0.25, ty: -0.5),
            .init(scaleX: -1.5, y: 0.75),
            .init(scaleX: 0, y: 1)
        ]
        for scheme in [ColorScheme.light, .dark] {
            context.environment.colorScheme = scheme
            context.environment._colorSchemeContrast = .increased
            for transform in transforms {
                context.viewTransform = transform
                let reference = ReferenceShadingGeometry(
                    environment: context.environment, viewTransform: transform
                )
                for center in [CGPoint.zero, CGPoint(x: 0.125, y: -0.25)] {
                    for radius in radii {
                        let actual = capture(.radialGradient(
                            gradient, center: center, startRadius: radius, endRadius: 4
                        ), in: context)
                        assertBitsEqual(actual, reference.radial(
                            gradient, center: center, startRadius: radius, endRadius: 4,
                            options: []
                        ), "radial boundary \(scheme)/\(transform)/\(center)/\(radius)")
                    }
                }
            }
        }
    }

    func testRadialShadingPreservesAccumulatedRotationsAcrossScales() throws {
        var context = try makeContext()
        let gradient = Gradient(stops: [
            .init(color: .primary.opacity(0.35), location: 0.2),
            .init(color: .init(.displayP3, red: 0.9, green: 0.3, blue: 0.1,
                              opacity: 0.6), location: 0.6),
            .init(color: .secondary, location: 0.8)
        ])
        let scales: [CGFloat] = [0.000001, 0.001, 0.5, 1, 3, 32, 1024, 1_000_000]
        let transforms: [CGAffineTransform] = [
            .init(a: 1, b: -0.0, c: 0, d: 1, tx: -0.0, ty: 0),
            .init(rotationAngle: .pi / 2),
            .init(scaleX: -1.5, y: 0.75),
            .init(a: 0.75, b: -0.25, c: 0.125, d: 1.25, tx: 0.25, ty: -0.5)
        ]
        for scheme in [ColorScheme.light, .dark] {
            context.environment.colorScheme = scheme
            context.environment._colorSchemeContrast = .increased
            for scale in scales {
                for transform in transforms {
                    context.viewTransform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)
                        .concatenating(transform)
                    let reference = ReferenceShadingGeometry(
                        environment: context.environment, viewTransform: context.viewTransform
                    )
                    let center = CGPoint(x: 0.125 * scale, y: -0.25 * scale)
                    for start in [CGFloat.zero, 0.2 * scale] {
                        let end = 0.8 * scale
                        let actual = capture(.radialGradient(
                            gradient, center: center, startRadius: start, endRadius: end
                        ), in: context)
                        XCTAssertFalse(actual.isEmpty)
                        assertBitsEqual(actual, reference.radial(
                            gradient, center: center, startRadius: start, endRadius: end,
                            options: []
                        ), "radial rotation \(scheme)/\(scale)/\(transform)/\(start)")
                    }
                }
            }
        }
    }

    func testConicShadingPreservesInterpolatedVertexColors() throws {
        var context = try makeContext()
        let gradients = [
            Gradient(colors: [.primary.opacity(0.35), .secondary]),
            Gradient(colors: [Color(.displayP3, red: 0.8, green: 0.2, blue: 0.4,
                                    opacity: 0.6), .blue.opacity(0.2), .clear]),
            Gradient(colors: []),
            Gradient(colors: [.red])
        ]
        for scheme in [ColorScheme.light, .dark] {
            context.environment.colorScheme = scheme
            let reference = ReferenceShadingGeometry(
                environment: context.environment, viewTransform: context.viewTransform
            )
            for gradient in gradients {
                let center = CGPoint(x: 7.25, y: -2.5)
                let angle = Angle.radians(-0.375)
                assertBitsEqual(capture(.conicGradient(
                    gradient, center: center, angle: angle
                ), in: context), reference.conic(
                    gradient, center: center, angle: angle
                ), "conic \(scheme)/\(gradient)")
            }
        }
    }

    func testConicShadingPreservesSharedEndpointsAcrossStopsAndTransforms() throws {
        var context = try makeContext()
        let step = CGFloat.pi / 180
        var progress: CGFloat = .zero
        var locations: [CGFloat] = [0]
        while progress < .pi * 2 {
            progress += step
            locations.append(progress / (.pi * 2))
        }
        let boundary = locations[120]
        let p3 = Color(.displayP3, red: 0.9, green: 0.3, blue: 0.1, opacity: 0.6)
        let gradients = [
            Gradient(stops: [
                .init(color: .primary.opacity(0.35), location: 0.2),
                .init(color: p3, location: 0.6),
                .init(color: .secondary, location: 0.8)
            ]),
            Gradient(stops: [
                .init(color: .red.opacity(0.2), location: boundary.nextUp),
                .init(color: .primary, location: boundary.nextDown),
                .init(color: p3, location: boundary),
                .init(color: .secondary.opacity(0.7), location: boundary),
                .init(color: .clear, location: 1)
            ]),
            Gradient(stops: [
                .init(color: Color(.sRGBLinear, red: -0.25, green: 1.25, blue: 0.5,
                                   opacity: 0.4), location: -0.25),
                .init(color: p3, location: 0.35),
                .init(color: .secondary, location: 1.25)
            ]),
            Gradient(stops: [.init(color: .primary.opacity(0.37), location: 0.5)]),
            Gradient(colors: []),
            Gradient(colors: [.red])
        ]
        let transforms: [CGAffineTransform] = [
            .identity,
            .init(a: 0.75, b: -0.25, c: 0.125, d: 1.25, tx: 0.25, ty: -0.5),
            .init(scaleX: -1.5, y: 0.75),
            .init(scaleX: 0, y: 1)
        ]
        func positionBits(_ vertex: _Vertex) -> [UInt32] {
            [vertex.position.0.bitPattern, vertex.position.1.bitPattern]
        }
        func colorBits(_ vertex: _Vertex) -> [UInt32] {
            [vertex.color.0.bitPattern, vertex.color.1.bitPattern,
             vertex.color.2.bitPattern, vertex.color.3.bitPattern]
        }

        // Keep the repeated-addition endpoint, including the final step beyond one turn.
        XCTAssertGreaterThanOrEqual(locations.last!, 1)
        for scheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                context.environment.colorScheme = scheme
                context.environment._colorSchemeContrast = contrast
                for transform in transforms {
                    context.viewTransform = transform
                    let reference = ReferenceShadingGeometry(
                        environment: context.environment, viewTransform: transform
                    )
                    for (index, gradient) in gradients.enumerated() {
                        for angle in [Angle.zero, .radians(-0.375)] {
                            let center = CGPoint(x: 0.125, y: -0.25)
                            let actual = capture(.conicGradient(
                                gradient, center: center, angle: angle
                            ), in: context)
                            assertBitsEqual(actual, reference.conic(
                                gradient, center: center, angle: angle
                            ), "conic \(scheme)/\(contrast)/\(transform)/\(index)/\(angle)")
                            if !actual.isEmpty {
                                XCTAssertEqual(actual.count, (locations.count - 1) * 3)
                                for triangle in 1..<(actual.count / 3) {
                                    let endpoint = actual[triangle * 3 - 1]
                                    let nextCenter = actual[triangle * 3]
                                    let nextStart = actual[triangle * 3 + 1]
                                    XCTAssertEqual(positionBits(endpoint), positionBits(nextStart))
                                    XCTAssertEqual(colorBits(endpoint), colorBits(nextStart))
                                    XCTAssertEqual(colorBits(endpoint), colorBits(nextCenter))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testConicShadingPreservesDenseStopSearchAcrossDraws() throws {
        var context = try makeContext()
        let step = CGFloat.pi / 180
        var progress: CGFloat = .zero
        var locations: [CGFloat] = [0]
        while progress < .pi * 2 {
            progress += step
            locations.append(progress / (.pi * 2))
        }
        let colors: [Color] = [
            .primary.opacity(0.35),
            Color(.displayP3, red: 0.9, green: 0.3, blue: 0.1, opacity: 0.6),
            .secondary, .clear
        ]
        var gradients = [64, 1024].map { count in
            Gradient(stops: (0..<count).map {
                .init(color: colors[$0 % colors.count],
                      location: CGFloat($0 + 1) / CGFloat(count + 1))
            })
        }
        let boundaryStops = [1, 120, 360].flatMap { index in
            let location = locations[index]
            return [location.nextDown, location, location, location.nextUp]
                .enumerated().map {
                    Gradient.Stop(color: colors[$0.offset], location: $0.element)
                }
        }
        gradients.append(Gradient(stops: Array(boundaryStops.reversed())))
        // One angular step skips the entire cluster, including duplicate stops.
        gradients.append(Gradient(stops: (0..<128).map {
            .init(color: colors[$0 % colors.count],
                  location: locations[120] + (locations[121] - locations[120]) *
                      CGFloat($0 / 2 + 1) / 65)
        }))
        gradients.append(Gradient(colors: [colors[0], colors[1]]))
        gradients.append(Gradient(stops: [
            .init(color: .red, location: -1), .init(color: .blue, location: 0)
        ]))
        XCTAssertGreaterThan(gradients[1].normalized().stops.count, locations.count)
        // Keep the existing normalized endpoint and empty-input behavior.
        XCTAssertEqual(gradients[4].normalized().stops.count, 1)
        XCTAssertTrue(gradients[5].normalized().stops.isEmpty)

        let transforms: [CGAffineTransform] = [
            .identity,
            .init(a: 0.75, b: -0.25, c: 0.125, d: 1.25, tx: 0.25, ty: -0.5),
            .init(scaleX: -1.5, y: 0.75),
            .init(scaleX: 0, y: 1)
        ]
        for scheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                context.environment.colorScheme = scheme
                context.environment._colorSchemeContrast = contrast
                for transform in transforms {
                    context.viewTransform = transform
                    let reference = ReferenceShadingGeometry(
                        environment: context.environment, viewTransform: transform
                    )
                    // Repeated draws on one context must restart the stop search.
                    for (index, gradient) in gradients.enumerated() {
                        for angle in [Angle.zero, .radians(-0.375)] {
                            let center = CGPoint(x: 0.125, y: -0.25)
                            assertBitsEqual(capture(.conicGradient(
                                gradient, center: center, angle: angle
                            ), in: context), reference.conic(
                                gradient, center: center, angle: angle
                            ), "conic stops \(scheme)/\(contrast)/\(transform)/\(index)/\(angle)")
                        }
                    }
                }
            }
        }
    }

    func testSolidLinearRadialAndConicShadingPreserveMetalPixels() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let queue = try XCTUnwrap(deviceContext.renderQueue())
        let bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        let path = Path(ellipseIn: CGRect(x: 3.25, y: 4.5, width: 24.5, height: 21.25))
        let color = Color(.displayP3, red: 0.85, green: 0.2, blue: 0.4, opacity: 0.37)
        let gradient = Gradient(colors: [.primary.opacity(0.35), color, .secondary])
        let repeatedGradient = Gradient(stops: [
            .init(color: .primary.opacity(0.35), location: 0.2),
            .init(color: color, location: 0.6),
            .init(color: .secondary, location: 0.8)
        ])
        let denseConicStops: [Gradient.Stop] = (0..<64).map { index in
            let stopColor: Color = index % 2 == 0 ? .primary.opacity(0.35) : color
            return .init(color: stopColor, location: CGFloat(index + 1) / 65)
        }
        let conicGradients = [
            Gradient(stops: denseConicStops),
            Gradient(stops: [
                .init(color: .secondary, location: 0.8),
                .init(color: .primary.opacity(0.35), location: 0.2),
                .init(color: color, location: 0.6),
                .init(color: .clear, location: 0.6)
            ])
        ]

        func render(_ kind: Int, reference: Bool, msaa: Bool,
                    background: BackendColor) throws -> [UInt8] {
            let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
            var environment = EnvironmentValues()
            environment.colorScheme = .dark
            environment._colorSchemeContrast = .increased
            let context = try XCTUnwrap(GraphicsContext(
                sceneResources: SceneResources(), environment: environment,
                viewport: bounds, contentOffset: .zero, contentScaleFactor: 1,
                resolution: bounds.size, commandBuffer: commandBuffer
            ))
            context.clear(with: background)
            let center = CGPoint(x: 12.5, y: 14.25)
            let angle = Angle.radians(-0.375)
            let shading: GraphicsContext.Shading
            switch kind {
            case 0: shading = .color(color)
            case 1: shading = .radialGradient(
                gradient, center: center, startRadius: -3, endRadius: 24
            )
            case 3, 4: shading = .radialGradient(
                repeatedGradient, center: center, startRadius: -3, endRadius: 9,
                options: kind == 3 ? .repeat : .mirror
            )
            case 5: shading = .radialGradient(
                repeatedGradient, center: center, startRadius: 24, endRadius: -3
            )
            case 6...10: shading = .linearGradient(
                repeatedGradient,
                startPoint: kind == 9 ? CGPoint(x: 25.25, y: 21.75) : center,
                endPoint: kind == 9 || kind == 10 ? center : CGPoint(x: 21.25, y: 20.75),
                options: kind == 7 ? .repeat : kind == 8 ? .mirror : []
            )
            case 11, 12: shading = .conicGradient(
                conicGradients[kind - 11], center: center, angle: angle
            )
            default: shading = .conicGradient(gradient, center: center, angle: angle)
            }
            if reference {
                let geometry = ReferenceShadingGeometry(
                    environment: environment, viewTransform: context.viewTransform
                )
                let vertices: [_Vertex]
                switch kind {
                case 0: vertices = geometry.solid(color)
                case 1: vertices = geometry.radial(
                    gradient, center: center, startRadius: -3, endRadius: 24, options: []
                )
                case 3, 4: vertices = geometry.radial(
                    repeatedGradient, center: center, startRadius: -3, endRadius: 9,
                    options: kind == 3 ? .repeat : .mirror
                )
                case 5: vertices = geometry.radial(
                    repeatedGradient, center: center, startRadius: 24, endRadius: -3,
                    options: []
                )
                case 6...10: vertices = geometry.linear(
                    repeatedGradient,
                    startPoint: kind == 9 ? CGPoint(x: 25.25, y: 21.75) : center,
                    endPoint: kind == 9 || kind == 10 ? center : CGPoint(x: 21.25, y: 20.75),
                    options: kind == 7 ? .repeat : kind == 8 ? .mirror : []
                )
                case 11, 12: vertices = geometry.conic(
                    conicGradients[kind - 11], center: center, angle: angle
                )
                default: vertices = geometry.conic(gradient, center: center, angle: angle)
                }
                let pass = try XCTUnwrap(context.beginRenderPass(
                    enableStencil: true, enableMSAA: msaa
                ))
                XCTAssertTrue(context.encodeStencilPathFillCommand(renderPass: pass, path: path))
                context.encodeDrawCommand(
                    renderPass: pass, shader: .vertexColor, stencil: .testNonZero,
                    vertices: vertices, texture: nil, blendState: .opaque
                )
                pass.end()
                context.drawSource()
            } else {
                context.fill(path, with: shading, style: FillStyle(antialiased: msaa))
            }

            let condition = NSCondition()
            var completed = false
            commandBuffer.addCompletedHandler { _ in
                condition.lock()
                completed = true
                condition.broadcast()
                condition.unlock()
            }
            condition.lock()
            XCTAssertTrue(commandBuffer.commit())
            let timeout = Date(timeIntervalSinceNow: 5)
            while !completed {
                if !condition.wait(until: timeout) { break }
            }
            condition.unlock()
            XCTAssertTrue(completed, "GPU command buffer timed out")
            guard completed else { return [] }

            let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
            let contents = try XCTUnwrap(staging.contents())
            return Array(UnsafeRawBufferPointer(start: contents, count: 32 * 32 * 4))
        }

        for kind in 0..<13 {
            for msaa in [false, true] {
                for background in [BackendColor.clear, BackendColor(0.3, 0.2, 0.1, 0.5)] {
                    let expected = try render(kind, reference: true, msaa: msaa,
                                              background: background)
                    let actual = try render(kind, reference: false, msaa: msaa,
                                            background: background)
                    XCTAssertEqual(actual.count, 32 * 32 * 4)
                    XCTAssertEqual(actual, expected, "kind \(kind), MSAA \(msaa)")
                    XCTAssertTrue(actual.enumerated().contains {
                        $0.offset % 4 == 3 && $0.element > 0
                    })
                }
            }
        }
    }

}

// Keep color resolution inside the former per-vertex loops as an independent oracle.
@inline(__always)
private func _premultipliedVertexColor(_ color: BackendColor) -> Float4 {
    let alpha = Float32(color.a)
    return (Float32(color.r) * alpha, Float32(color.g) * alpha,
            Float32(color.b) * alpha, alpha)
}
private struct ReferenceShadingGeometry {
    let environment: EnvironmentValues
    let viewTransform: CGAffineTransform

    func solid(_ c: Color) -> [_Vertex] {
        var vertices: [_Vertex] = []

        let makeVertex = { (x: Scalar, y: Scalar) in
            _Vertex(position: Vector2(x, y).float2,
                    texcoord: Vector2.zero.float2,
                    color: _premultipliedVertexColor(c.backendColor(in: self.environment)))
        }
        vertices = [
            makeVertex(-1, -1), makeVertex(-1, 1), makeVertex(1, -1),
            makeVertex(1, -1), makeVertex(-1, 1), makeVertex(1, 1)
        ]

        return vertices
    }

    func linear(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint,
                options: GraphicsContext.GradientOptions) -> [_Vertex] {
        var vertices: [_Vertex] = []
        let stops = gradient.normalized().stops
        if stops.isEmpty { return [] }
        let gradientVector = endPoint - startPoint
        let length = gradientVector.magnitude
        if length < .ulpOfOne {
            // Capture the already-hoisted solid fallback at this linear baseline.
            let color = _premultipliedVertexColor(stops[0].color.backendColor(in: environment))
            let vertex = { (x: Scalar, y: Scalar) in
                _Vertex(position: Vector2(x, y).float2, texcoord: Vector2.zero.float2,
                        color: color)
            }
            return [vertex(-1, -1), vertex(-1, 1), vertex(1, -1),
                    vertex(1, -1), vertex(-1, 1), vertex(1, 1)]
        }
        let dir = gradientVector.normalized()
        // transform gradient space to world space
        // ie: (0, 0) -> startPoint, (1, 0) -> endPoint
        let gradientTransform = CGAffineTransform(
            a: dir.x * length, b: dir.y * length,
            c: -dir.y, d: dir.x,
            tx: startPoint.x, ty: startPoint.y)

        let viewportToGradientTransform = self.viewTransform.inverted()
            .concatenating(gradientTransform.inverted())

        let viewportExtents = [CGPoint(x: -1, y: -1),   // left-bottom
                               CGPoint(x: -1, y: 1),    // left-top
                               CGPoint(x: 1, y: 1),     // right-top
                               CGPoint(x: 1, y: -1)]    // right-bottom
            .map { $0.applying(viewportToGradientTransform) }
        let maxX = viewportExtents.max { $0.x < $1.x }!.x
        let minX = viewportExtents.min { $0.x < $1.x }!.x
        let maxY = viewportExtents.max { $0.y < $1.y }!.y
        let minY = viewportExtents.min { $0.y < $1.y }!.y

        let gradientToViewportTransform = gradientTransform
            .concatenating(self.viewTransform)

        let addGradientBox = { (x1: CGFloat, x2: CGFloat, c1: BackendColor, c2: BackendColor) in
            let verts = [_Vertex(position: Vector2(x1, maxY).applying(gradientToViewportTransform).float2,
                                 texcoord: Vector2.zero.float2,
                                 color: _premultipliedVertexColor(c1)),
                         _Vertex(position: Vector2(x1, minY).applying(gradientToViewportTransform).float2,
                                 texcoord: Vector2.zero.float2,
                                 color: _premultipliedVertexColor(c1)),
                         _Vertex(position: Vector2(x2, maxY).applying(gradientToViewportTransform).float2,
                                 texcoord: Vector2.zero.float2,
                                 color: _premultipliedVertexColor(c2)),
                         _Vertex(position: Vector2(x2, minY).applying(gradientToViewportTransform).float2,
                                 texcoord: Vector2.zero.float2,
                                 color: _premultipliedVertexColor(c2))]
            vertices.append(contentsOf: [verts[0], verts[1], verts[2]])
            vertices.append(contentsOf: [verts[2], verts[1], verts[3]])
        }
        if options.contains(.mirror) {
            var pos = floor(minX)
            let rstops = stops.reversed()
            while pos < ceil(maxX) {
                if pos.magnitude.truncatingRemainder(dividingBy: 2).rounded() == 1.0 {
                    for i in 0..<(rstops.count-1) {
                        let s1 = stops[i]
                        let s2 = stops[i+1]

                        let loc1 = (1.0 - s1.location)
                        let loc2 = (1.0 - s2.location)
                        if loc1 + pos > maxX { break }
                        if loc2 + pos < minX { continue }
                        addGradientBox(loc1 + pos,
                                       loc2 + pos,
                                       s1.color.backendColor(in: self.environment),
                                       s2.color.backendColor(in: self.environment))
                    }
                } else {
                    for i in 0..<(stops.count-1) {
                        let s1 = stops[i]
                        let s2 = stops[i+1]

                        if s1.location + pos > maxX { break }
                        if s2.location + pos < minX { continue }
                        addGradientBox(s1.location + pos,
                                       s2.location + pos,
                                       s1.color.backendColor(in: self.environment),
                                       s2.color.backendColor(in: self.environment))
                    }
                }
                pos += 1
            }
        } else if options.contains(.repeat) {
            var pos = floor(minX)
            while pos < ceil(maxX) {
                for i in 0..<(stops.count-1) {
                    let s1 = stops[i]
                    let s2 = stops[i+1]

                    if s1.location + pos > maxX { break }
                    if s2.location + pos < minX { continue }
                    addGradientBox(s1.location + pos,
                                   s2.location + pos,
                                   s1.color.backendColor(in: self.environment),
                                   s2.color.backendColor(in: self.environment))
                }
                pos += 1
            }
        } else {
            for i in 0..<(stops.count-1) {
                let s1 = stops[i]
                let s2 = stops[i+1]

                addGradientBox(s1.location, s2.location,
                               s1.color.backendColor(in: self.environment),
                               s2.color.backendColor(in: self.environment))
            }
            if let first = stops.first, first.location > minX {
                addGradientBox(minX, first.location,
                               first.color.backendColor(in: self.environment),
                               first.color.backendColor(in: self.environment))
            }
            if let last = stops.last, last.location < maxX {
                addGradientBox(last.location, maxX,
                               last.color.backendColor(in: self.environment),
                               last.color.backendColor(in: self.environment))
            }
        }
        return vertices
    }

    func radial(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat,
                endRadius: CGFloat, options: GraphicsContext.GradientOptions) -> [_Vertex] {
        var vertices: [_Vertex] = []

        let stops = gradient.normalized().stops
        if stops.isEmpty { return [] }

        let length = (endRadius - startRadius).magnitude
        if length < .ulpOfOne {
            return solid(options.contains(.repeat) && !options.contains(.mirror)
                ? stops.last!.color : stops.first!.color)
        }
        let invViewTransform = self.viewTransform.inverted()
        let scale = [CGPoint(x: -1, y: -1),     // left-bottom
                     CGPoint(x: -1, y: 1),      // left-top
                     CGPoint(x: 1, y: 1),       // right-top
                     CGPoint(x: 1, y: -1)]      // right-bottom
            .map { ($0.applying(invViewTransform) - center).magnitudeSquared }
            .max()!.squareRoot()

        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .concatenating(self.viewTransform)

        let texCoord = Vector2.zero.float2
        let step = CGFloat.pi / 45.0
        let addCircularArc = {
            (x1: CGFloat, x2: CGFloat, c1: Color, c2: Color) in

            if x1 >= scale && x2 >= scale { return }
            if x1 <= 0 && x2 <= 0 { return }
            if (x2 - x1).magnitude < .ulpOfOne { return }

            var x1 = x1, x2 = x2
            var c1 = c1, c2 = c2
            if x1 > x2 {
                (x1, x2) = (x2, x1)
                (c1, c2) = (c2, c1)
            }
            if x1 < 0 {
                c1 = .lerp(c1, c2, (0 - x1)/(x2 - x1))
                x1 = 0
            }
            if x2 > scale {
                c2 = .lerp(c1, c2, (scale - x1)/(x2 - x1))
                x2 = scale
            }
            if (x2 - x1) < .ulpOfOne { return }
            assert(x2 > x1)

            let p0 = Vector2(x1, 0)
            let p1 = p0.rotated(by: step)
            let p2 = Vector2(x2, 0)
            let p3 = p2.rotated(by: step)

            let verts: [Vector2]
            let colors: [Color]
            if (p1 - p0).magnitudeSquared < .ulpOfOne {
                verts = [p0, p2, p3]
                colors = [c1, c2, c2]
            } else {
                verts = [p1, p0, p3, p3, p0, p2]
                colors = [c1, c1, c2, c2, c1, c2]
            }
            let numVertices = Int((CGFloat.pi * 2) / step) + 1
            vertices.reserveCapacity(vertices.count + numVertices * verts.count)
            var progress: CGFloat = .zero
            while progress < .pi * 2  {
                for (i, p) in verts.enumerated() {
                    vertices.append(_Vertex(position: p.rotated(by: progress).applying(transform).float2,
                                            texcoord: texCoord,
                                            color: _premultipliedVertexColor(
                                                colors[i].backendColor(in: self.environment)
                                            )))
                }
                progress += step
            }
        }

        if options.contains(.mirror) {
            var startRadius = startRadius
            var reverse = false
            while startRadius > 0 {
                startRadius = startRadius - length
                reverse = !reverse
            }
            while startRadius < scale {
                if reverse {
                    for i in 0..<(stops.count - 1) {
                        let s1 = stops[i]
                        let s2 = stops[i+1]
                        let loc1 = startRadius + length - (s1.location * length)
                        let loc2 = startRadius + length - (s2.location * length)
                        if loc1 <= 0 && loc2 <= 0 { break }
                        addCircularArc(loc1, loc2, s1.color, s2.color)
                    }
                } else {
                    for i in 0..<(stops.count - 1) {
                        let s1 = stops[i]
                        let s2 = stops[i+1]
                        let loc1 = (s1.location * length) + startRadius
                        let loc2 = (s2.location * length) + startRadius
                        if loc1 >= scale && loc2 >= scale { break }
                        addCircularArc(loc1, loc2, s1.color, s2.color)
                    }
                }
                startRadius += length
                reverse = !reverse
            }
        } else if options.contains(.repeat) {
            var startRadius = startRadius
            let reverse = endRadius < startRadius
            while startRadius > 0 {
                startRadius = startRadius - length
            }
            if reverse {
                while startRadius < scale {
                    for i in 0..<(stops.count - 1) {
                        let s1 = stops[i]
                        let s2 = stops[i+1]
                        let loc1 = startRadius + length - (s1.location * length)
                        let loc2 = startRadius + length - (s2.location * length)
                        if loc1 <= 0 && loc2 <= 0 { break }
                        addCircularArc(loc1, loc2, s1.color, s2.color)
                    }
                    startRadius += length
                }
            } else {
                while startRadius < scale {
                    for i in 0..<(stops.count - 1) {
                        let s1 = stops[i]
                        let s2 = stops[i+1]
                        let loc1 = (s1.location * length) + startRadius
                        let loc2 = (s2.location * length) + startRadius
                        if loc1 >= scale && loc2 >= scale { break }
                        addCircularArc(loc1, loc2, s1.color, s2.color)
                    }
                    startRadius += length
                }
            }
        } else {
            if endRadius > startRadius {
                addCircularArc(0, startRadius, stops[0].color, stops[0].color)
                for i in 0..<(stops.count - 1) {
                    let s1 = stops[i]
                    let s2 = stops[i+1]
                    let loc1 = (s1.location * length) + startRadius
                    let loc2 = (s2.location * length) + startRadius
                    if loc1 >= scale && loc2 >= scale { break }
                    addCircularArc(loc1, loc2, s1.color, s2.color)
                }
                addCircularArc(endRadius, scale, stops.last!.color, stops.last!.color)
            } else {
                addCircularArc(0, endRadius, stops.last!.color, stops.last!.color)
                for i in 0..<(stops.count - 1) {
                    let s1 = stops[i]
                    let s2 = stops[i+1]
                    let loc1 = startRadius - (s1.location * length)
                    let loc2 = startRadius - (s2.location * length)
                    if loc1 <= 0 && loc2 <= 0 { break }
                    addCircularArc(loc1, loc2, s1.color, s2.color)
                }
                addCircularArc(startRadius, scale, stops[0].color, stops[0].color)
            }
        }

        return vertices
    }

    func conic(_ gradient: Gradient, center: CGPoint, angle: Angle) -> [_Vertex] {
        var vertices: [_Vertex] = []

        let gradient = gradient.normalized()
        if gradient.stops.isEmpty { return [] }
        let invViewTransform = self.viewTransform.inverted()
        let scale = [CGPoint(x: -1, y: -1),     // left-bottom
                     CGPoint(x: -1, y: 1),      // left-top
                     CGPoint(x: 1, y: 1),       // right-top
                     CGPoint(x: 1, y: -1)]      // right-bottom
            .map { ($0.applying(invViewTransform) - center).magnitudeSquared }
            .max()!.squareRoot()

        let transform = CGAffineTransform(rotationAngle: angle.radians)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            .concatenating(self.viewTransform)

        let step = CGFloat.pi / 180.0
        var progress: CGFloat = .zero
        let texCoord = Vector2.zero.float2
        let center = Vector2(0, 0).applying(transform)
        let numTriangles = Int((CGFloat.pi * 2) / step) + 1
        vertices.reserveCapacity(numTriangles * 3)
        while progress < .pi * 2 {
            let p0 = Vector2(1, 0).rotated(by: progress).applying(transform)
            let p1 = Vector2(1, 0).rotated(by: progress + step).applying(transform)
            let color1 = gradient._linearInterpolatedColor(at: progress / (.pi * 2))
            let color2 = gradient._linearInterpolatedColor(at: (progress + step) / (.pi * 2))

            vertices.append(_Vertex(position: center.float2,
                                    texcoord: texCoord,
                                    color: _premultipliedVertexColor(
                                        color1.backendColor(in: self.environment)
                                    )))
            vertices.append(_Vertex(position: p0.float2,
                                    texcoord: texCoord,
                                    color: _premultipliedVertexColor(
                                        color1.backendColor(in: self.environment)
                                    )))
            vertices.append(_Vertex(position: p1.float2,
                                    texcoord: texCoord,
                                    color: _premultipliedVertexColor(
                                        color2.backendColor(in: self.environment)
                                    )))

            progress += step
        }

        return vertices
    }
}
