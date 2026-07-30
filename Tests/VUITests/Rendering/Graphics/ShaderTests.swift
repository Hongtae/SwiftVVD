import Foundation
import VVD
import XCTest
@testable import VUI

final class ShaderTests: XCTestCase {
    func testPublicLibraryFunctionArgumentAndUsageCarriersMatchObservedSemantics() {
        let data = Data([0, 1, 2, 3])
        let library = ShaderLibrary(data: data)
        XCTAssertEqual(ShaderLibrary.default, .bundle(.main))
        XCTAssertNotEqual(library, ShaderLibrary(data: data))
        XCTAssertNotEqual(
            ShaderLibrary(url: URL(fileURLWithPath: "/tmp/a")),
            ShaderLibrary(url: URL(fileURLWithPath: "/tmp/a"))
        )

        let function = ShaderFunction(library: library, name: "probe")
        XCTAssertEqual(function, library.probe)
        XCTAssertNotEqual(function, library.other)

        let arguments: [VUI.Shader.Argument] = [
            .float(1),
            .float2(1, 2),
            .float3(1, 2, 3),
            .float4(1, 2, 3, 4),
            .float2(CGPoint(x: 5, y: 6)),
            .float2(CGSize(width: 7, height: 8)),
            .float2(CGVector(dx: 9, dy: 10)),
            .floatArray([11, 12]),
            .boundingRect,
            .color(.red),
            .colorArray([.green, .blue]),
            .image(Image(systemName: "star")),
            .data(data),
        ]
        var shader = VUI.Shader(function: function, arguments: arguments)
        XCTAssertEqual(shader.function, function)
        XCTAssertEqual(shader.arguments, arguments)
        XCTAssertFalse(shader.dithersColor)
        shader.dithersColor = true
        XCTAssertTrue(shader.dithersColor)
        XCTAssertEqual(shader.options.rawValue, 1)
        shader.dithersColor = false
        XCTAssertEqual(shader.options.rawValue, 0)

        XCTAssertEqual(VUI.Shader.UsageType.shapeStyle.rawValue, 0)
        XCTAssertEqual(VUI.Shader.UsageType.colorEffect.rawValue, 1)
        XCTAssertEqual(VUI.Shader.UsageType.layerEffect.rawValue, 2)
        XCTAssertEqual(VUI.Shader.UsageType.distortionEffect.rawValue, 3)
        XCTAssertEqual(Set([
            VUI.Shader.UsageType.shapeStyle,
            .colorEffect,
            .distortionEffect,
            .layerEffect,
        ]).count, 4)

        var shape = _ShapeStyle_Shape(
            operation: .fallbackColor(level: 0),
            environment: EnvironmentValues()
        )
        shader._apply(to: &shape)
        guard case let .shader(storedShader, bounds)? =
            shape.resolvedShading?.properties.first
        else {
            return XCTFail("expected shader shape style shading")
        }
        XCTAssertEqual(storedShader, shader)
        XCTAssertTrue(bounds.isNull)

        // ASSERTIONS shaderPublicSurfaceObserved
        // ASSERTIONS shaderRuntimeSemanticsObserved
    }

    func testViewAndVisualFactoriesPreserveFilterBitsOffsetsAndEnablement() throws {
        var shader = ShaderLibrary.default.probe(.float(1))
        shader.dithersColor = true

        let color = try XCTUnwrap(shaderFilter(in: Color.red.colorEffect(shader, isEnabled: false)))
        XCTAssertEqual(color.shader.options.rawValue, 3)
        XCTAssertEqual(color.maxSampleOffset, .zero)
        XCTAssertFalse(color.enabled)

        let distortion = try XCTUnwrap(shaderFilter(in: Color.red.distortionEffect(
            shader,
            maxSampleOffset: CGSize(width: -3, height: 4),
            isEnabled: false
        )))
        XCTAssertEqual(distortion.shader.options.rawValue, 5)
        XCTAssertEqual(distortion.maxSampleOffset, CGSize(width: -3, height: 4))
        XCTAssertFalse(distortion.enabled)

        let layer = try XCTUnwrap(shaderFilter(in: Color.red.layerEffect(
            shader,
            maxSampleOffset: CGSize(width: 5, height: -6)
        )))
        XCTAssertEqual(layer.shader.options.rawValue, 1)
        XCTAssertEqual(layer.maxSampleOffset, CGSize(width: 5, height: -6))
        XCTAssertTrue(layer.enabled)

        let visual = try XCTUnwrap(shaderFilter(in: EmptyVisualEffect().colorEffect(
            shader,
            isEnabled: false
        )))
        XCTAssertEqual(visual.shader.options.rawValue, 3)
        XCTAssertFalse(visual.enabled)

        let shading = GraphicsContext.Shading.shader(shader, bounds: CGRect(x: 1, y: 2, width: 3, height: 4))
        guard case let .shader(storedShader, bounds) = shading.properties.first else {
            return XCTFail("expected shader shading")
        }
        XCTAssertEqual(storedShader, shader)
        XCTAssertEqual(bounds, CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    func testGraphResolutionPublishesAnimatableShaderDisplayEffect() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var environment = EnvironmentValues()
            environment.colorScheme = .dark
            let inputs = makeViewInputs(graph: graph, environment: environment)
            let shader = ShaderLibrary.default.probe(
                .float(2),
                .color(.primary),
                .boundingRect
            )
            let modifier = graph.makeInput(value: _ShaderFilterEffect(
                shader: shader,
                maxSampleOffset: CGSize(width: 3, height: 4),
                enabled: true
            ))
            let source = graph.makeInput(value: makeDisplayList())

            let outputs = _ShaderFilterEffect._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, _ in
                var outputs = _ViewOutputs()
                outputs.preferences.append(DisplayList.Key.self, node: source.identifier)
                return outputs
            }

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID).value
            guard case let .shader(resolved)? = output.effects.first?.effect else {
                return XCTFail("expected resolved shader effect")
            }
            XCTAssertEqual(resolved.maxSampleOffset, CGSize(width: 3, height: 4))
            XCTAssertEqual(resolved.options.rawValue, 0)
            XCTAssertEqual(resolved.shader?.arguments.count, 3)
            guard case .resolvedColor = resolved.shader?.arguments[1].storage else {
                return XCTFail("expected environment-resolved color argument")
            }

            // ASSERTIONS shaderGraphDisassemblyObserved
        }
    }

    func testResolvedShaderAnimatableDataUpdatesNumericAndResolvedColorArguments() {
        let resolvedColor = Color.ResolvedHDR(
            Color.Resolved(
                colorSpace: .sRGBLinear,
                red: 0.1,
                green: 0.2,
                blue: 0.3,
                opacity: 0.4
            )
        )
        let shader = VUI.Shader(
            function: ShaderFunction(library: .default, name: "probe"),
            arguments: [
                .float(1),
                VUI.Shader.Argument(storage: .resolvedColor(resolvedColor)),
                .data(Data([1])),
            ]
        )
        var resolved = VUI.Shader.ResolvedShader(
            shader: shader,
            maxSampleOffset: .zero,
            options: []
        )
        XCTAssertEqual(resolved.animatableData.elements, [
            .float(1),
            .float4(0.1, 0.2, 0.3, 0.4),
            .zero,
        ])

        resolved.animatableData = ShaderVectorData(elements: [
            .float(5),
            .float4(0.5, 0.6, 0.7, 0.8),
            .float(9),
        ])
        guard let arguments = resolved.shader?.arguments else {
            return XCTFail("missing resolved shader")
        }
        XCTAssertEqual(arguments[0], .float(5))
        guard case let .resolvedColor(color) = arguments[1].storage else {
            return XCTFail("expected resolved color")
        }
        XCTAssertEqual(color.linearRed, 0.5)
        XCTAssertEqual(color.linearGreen, 0.6)
        XCTAssertEqual(color.linearBlue, 0.7)
        XCTAssertEqual(color.opacity, 0.8)
        XCTAssertEqual(arguments[2], .data(Data([1])))
    }

    func testDirectShaderShapeStyleInterpolatesResolvedArgumentsInTypedShapeRecord() throws {
        let library = ShaderLibrary(data: Data([0x03, 0x02, 0x23, 0x07]))
        let function = ShaderFunction(library: library, name: "shape")
        let frame = CGRect(x: 2, y: 3, width: 20, height: 10)

        func list(value: Float, color: VUI.Color) -> DisplayList {
            var list = DisplayList()
            list.appendShapeItem(
                path: Path(frame),
                role: .fill,
                style: VUI.Shader(
                    function: function,
                    arguments: [
                        .float(value),
                        .color(color),
                        .data(Data([7])),
                        .boundingRect,
                    ]
                ),
                bounds: frame,
                environment: EnvironmentValues()
            )
            return list
        }

        let source = list(value: 1, color: .red)
        let target = list(value: 5, color: .blue)
        guard case let .shader(sourceRecord)? = source.itemRecords.first?.shapeStyle,
              case .resolvedColor = sourceRecord.shader?.arguments[1].storage else {
            return XCTFail("direct shader style should record an environment-resolved paint")
        }

        let midpoint = RBDisplayListInterpolator(
            from: source,
            to: target
        ).copyContents(withProgress: 0.5)
        let item = try XCTUnwrap(midpoint.items.first)
        guard case let .content(content) = item.value,
              case let .shape(shape) = content.value,
              case let .shader(record)? = shape.command.record.shapeStyle,
              let shader = record.shader,
              case let .shader(renderShader, bounds)? = shape.shading.properties.first else {
            return XCTFail("compatible shader paints should remain one typed shape")
        }
        XCTAssertTrue(bounds.isNull)
        XCTAssertEqual(shader, renderShader)
        XCTAssertEqual(shader.function, function)
        guard case let .float(value) = shader.arguments[0].storage else {
            return XCTFail("expected interpolated float argument")
        }
        XCTAssertEqual(value, 3, accuracy: 0.000_001)
        XCTAssertEqual(shader.arguments[2], VUI.Shader.Argument.data(Data([7])))
        XCTAssertEqual(shader.arguments[3], VUI.Shader.Argument.boundingRect)
    }

    func testCompileValidatesHLSLGeneratedSPIRV() async throws {
        let shader = try customPassthroughShader(tint: (1, 1, 1, 1))
        try await shader.compile(as: .layerEffect)
    }

    func testHLSLGeneratedSPIRVRendersThroughMetalBackend() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let width = 8
        let height = 8
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
        let shader = try customPassthroughShader(tint: (0.5, 1, 1, 1))
        let resolved = VUI.Shader.ResolvedShader(
            shader: shader,
            maxSampleOffset: .zero,
            options: []
        )
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        var contents = DisplayList()
        contents.appendDebugItem(bounds: frame) { context in
            context.fill(
                Path(frame),
                with: .color(Color(.sRGB, red: 1, green: 0, blue: 0))
            )
        }
        let list = DisplayList.effect(.shader(resolved), contents: contents)
        DisplayList.GraphicsRenderer().render(
            list: list,
            at: .zero,
            in: context
        )
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        for index in 0..<(width * height) {
            XCTAssertEqual(bytes[index * 4], 128, accuracy: 1)
            XCTAssertEqual(bytes[index * 4 + 1], 0, accuracy: 1)
            XCTAssertEqual(bytes[index * 4 + 2], 0, accuracy: 1)
            XCTAssertEqual(bytes[index * 4 + 3], 255, accuracy: 1)
        }

        // ASSERTIONS shaderRuntimeSemanticsObserved
    }

    func testHLSLGeneratedShaderShapeStyleUsesStencilAndImplicitBoundingRect() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let width = 8
        let height = 8
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
        let frame = CGRect(x: 2, y: 2, width: 4, height: 3)
        let shader = try customShader(
            named: "custom_shape",
            arguments: [.float4(0, 1, 0, 1), .boundingRect]
        )
        context.fill(
            Path(frame),
            with: .style(shader)
        )
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        var coloredPixelCount = 0
        for index in 0..<(width * height) where bytes[index * 4 + 3] > 0 {
            coloredPixelCount += 1
            XCTAssertEqual(bytes[index * 4], 0)
            XCTAssertEqual(bytes[index * 4 + 1], 255)
            XCTAssertEqual(bytes[index * 4 + 2], 0)
            XCTAssertEqual(bytes[index * 4 + 3], 255)
        }
        XCTAssertEqual(coloredPixelCount, 12)
    }

    func testHLSLGeneratedShapeShaderBindsImageArgument() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let width = 8
        let height = 8
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

        let imageContext = try XCTUnwrap(context.makeLayerContext(CGSize(width: 1, height: 1)))
        imageContext.clear(with: .blue)
        let image = Image(decorative: imageContext.backdrop, scale: 1)
        let frame = CGRect(x: 2, y: 2, width: 4, height: 3)
        let shader = try customShader(named: "custom_image", arguments: [.image(image)])
        context.fill(Path(frame), with: .shader(shader, bounds: frame))
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        var coloredPixelCount = 0
        for index in 0..<(width * height) where bytes[index * 4 + 3] > 0 {
            coloredPixelCount += 1
            XCTAssertEqual(bytes[index * 4], 0)
            XCTAssertEqual(bytes[index * 4 + 1], 0)
            XCTAssertEqual(bytes[index * 4 + 2], 255)
            XCTAssertEqual(bytes[index * 4 + 3], 255)
        }
        XCTAssertEqual(coloredPixelCount, 12)
    }

    func testHLSLGeneratedShaderPacksArrayDataAndBoundsArguments() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let width = 2
        let height = 2
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
        let rawValue = [UInt32(1), 0, 0, 0].withUnsafeBytes { Data($0) }
        let shader = try customShader(
            named: "custom_arguments",
            arguments: [
                .floatArray([0.25, 0.5, 0.75]),
                .colorArray([
                    Color(.sRGBLinear, red: 0, green: 1, blue: 0),
                    Color(.sRGBLinear, red: 0, green: 0, blue: 1),
                ]),
                .data(rawValue),
                .boundingRect,
            ]
        )
        context.fill(Path(frame), with: .shader(shader, bounds: frame))
        try waitForCompletion(commandBuffer)

        let staging = try XCTUnwrap(deviceContext.makeCPUAccessible(texture: context.backdrop))
        let pointer = try XCTUnwrap(staging.contents())
        let bytes = UnsafeRawBufferPointer(start: pointer, count: width * height * 4)
        for index in 0..<(width * height) {
            XCTAssertEqual(bytes[index * 4], 64, accuracy: 1)
            XCTAssertEqual(bytes[index * 4 + 1], 255, accuracy: 1)
            XCTAssertEqual(bytes[index * 4 + 2], 255, accuracy: 1)
            XCTAssertEqual(bytes[index * 4 + 3], 255, accuracy: 1)
        }
    }

    private func shaderFilter(in value: Any, depth: Int = 0) -> _ShaderFilterEffect? {
        guard depth < 8 else { return nil }
        if let filter = value as? _ShaderFilterEffect {
            return filter
        }
        for child in Mirror(reflecting: value).children {
            if let filter = shaderFilter(in: child.value, depth: depth + 1) {
                return filter
            }
        }
        return nil
    }

    private func customPassthroughShader(tint: Float4) throws -> VUI.Shader {
        try customShader(
            named: "custom_passthrough",
            arguments: [
                .float4(tint.0, tint.1, tint.2, tint.3),
                .boundingRect,
            ]
        )
    }

    private func customShader(
        named name: String,
        arguments: [VUI.Shader.Argument]
    ) throws -> VUI.Shader {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "\(name).frag",
            withExtension: "spv",
            subdirectory: "SPIRV"
        ))
        return VUI.Shader(
            function: ShaderFunction(library: ShaderLibrary(url: url), name: name),
            arguments: arguments
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

    private func makeDisplayList() -> DisplayList {
        var list = DisplayList()
        list.appendDebugItem { _ in }
        return list
    }

    private func makeViewInputs(
        graph: _AGGraph,
        environment: EnvironmentValues
    ) -> _ViewInputs {
        let environment = graph.makeInput(value: environment)
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: Phase()),
            environment: environment,
            transaction: graph.makeInput(value: Transaction())
        )
        return _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 10, height: 10)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
