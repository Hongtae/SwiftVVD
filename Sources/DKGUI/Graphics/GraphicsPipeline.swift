//
//  File: GraphicsPipeline.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame


// glslc {input-file} -o {output-file} -Os --target-env=vulkan1.3
private let vsStencilGLSL = """
    /* vertex shader for writing stencil only */
    #version 450

    layout (location=0) in vec2 position;

    void main() {
        gl_Position = vec4(position, 0, 1);
    }
    """

private let vsStencilSpvCEB64 = """
    XQAAAAR4AgAAAAAAAAABgJdesntsONN+HGcuNYYB2HaeuzqB/1JEjzTMhsjJ47cvV+jDp5\
    wmI6dY7v+CjHUnSZSByNZ1Fsvw6oKTEP6ntLqjDTOV81fDIOfUM7gZIajT4DC7D1knh4og\
    uymzewwBXQtEig5UNZ30zr2Q06FKGV/UGL7kfXtcGmiN3uoXRKKkRyQhSuUKAgkP+DaEdq\
    1K5QkEzWZdAhajbWmWeYc7FopuJlgZX34yDCmYdjU3uw668eOYxNG6+GY1Ub2jL2TeTnTA0\
    mpLzlmE9f35ILERvvTZ5CqORtiFgD2xGeioWInO3XgtB2hcWX1ZQpbHFHPP77eF4IIA
    """

private let vsGLSL = """
    /* vertex shader for vertex-color, texcoord */
    #version 450

    layout (location=0) in vec2 position;
    layout (location=1) in vec2 texcoord;
    layout (location=2) in vec4 color;

    layout (location=0) out vec2 outPosition;
    layout (location=1) out vec2 outTexcoord;
    layout (location=2) out vec4 outColor;

    void main() {
        outPosition = position;
        outTexcoord = texcoord;
        outColor = color;
        gl_Position = vec4(position, 0, 1);
    }
    """

private let vsSpvCEB64 = """
    XQAAAASwBAAAAAAAAAABgJdesntsONM6MGcxLKsQZjMqZyK9s+I5F9rVJqCzj9BrRuMFcP\
    pPjJTufO2GnekV4S/IzcItw0iVP+X5oQW6csvuo5GS2Ihrgt9U/0k7XYsDg2hWLwWyNRd2\
    i5M7LA80mBfTGUL9qSH5IFJp2HmzlKr7mK0KjEZMHymQ2d17sbqWysevCH7QwIrKiTJ6X6\
    7R3nygYevfIGd9/G1/mYy9LVUDz8qDF5yRF1XvNLB2eRYmsICZnTd8UzfX6FkcWANoWXkm\
    8lJzw7/smwtoZ0shMDC+fR5ikvCX052fx7xhfmsNbuFO6YHWvgq/Mj+UA3LCin/xaDjXR2\
    19dyOxOJlxm67UUTY2NJuf8NA6EK7djXgF1hRy2FRcwVTgmX8iY8VnvCXs+Q4ITlnxTBjR\
    aKUUDxfL2Jb9nN2WefrCzIjnYM/PRYF/aCv7qXfdLT56ToL+MPguij1J7zOPSJiPi//03P\
    JkFAwhjUgkApaaAwscDAVqDQ/YpX876Q5J1FDKuHkIc1XbdTpf8lygzFQmW+4b38wA
    """

private let fsGLSL = """
    /* fragment-shader: vertex color */
    #version 450

    layout (location=0) in vec2 position;
    layout (location=1) in vec2 texcoord;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main(void) {
        outFragColor = color;
    }
    """

private let fsSpvCEB64 = """
    XQAAAAQMAgAAAAAAAAABgJdesntsONM6MGcrJRJFH8eaWFhPhF/JgkVaMKDLBIehEkszc0\
    5hwuLCi2c2uZq7XW/7AY0KbL2Rwo/dGk5XbL0h8jqJ+yz0XcClGDo6FfdY3mTBUeJufqjr\
    3Lkng6/V1JJBTLD+nnardxsTuWH+d3kqBsEOvJvHvaVvd+3ubsYeulURrEldB0aem8ZuH4\
    ooN+cYIQNr5N/zMd3m2O7cPoMu2fZGV9swxtT3y+umjWnu2em3LxwYLtSFak8FfL5JUx14\
    v+OoioDBuElhe+DpDeo/UDLsl5HSSjUdWAeWXFGcRgA=
    """

private let fsTextureGLSL = """
    /* fragment-shader: vertex color, uniform texture */
    #version 450

    layout (binding=0) uniform sampler2D image;

    layout (location=0) in vec2 position;
    layout (location=1) in vec2 texcoord;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main() {
        outFragColor = texture(image, texcoord) * color;
    }
    """

private let fsTextureSpvCEB64 = """
    XQAAAATUAgAAAAAAAAABgJdesntsONM6MGctmKIB2HaeuzmgkxfX256KE1HOZIhrusCJ00\
    Nn8k7Pi3d42hliNd0QudCMu4Bu1dAmK7j4zRV2qYZl5l8PfDaM/mz2/HgrqvHwcD7o5Eli\
    3bGZ9xrelsWEyh6qGbUpnDohd44jZu9o/zr5ARxpz2vf4dN7QWpcWAq55iqfP/J8AlWOfV\
    kGj7T1eUc2PTgf+YHYzY0iA+z6RLnuO6xN0PAKlU1+YizwCgEyOQBziBKKn3TdyE3n1YhA\
    vl5+QSCCH1dDw00JUPw1MpYo5i8gMBYBWOgtTBfv8egGietEE/LzjZVup9AMgiqPl2WMif\
    ooq/JVNDsy1RTy3hGj5UMrgWOqYseDd+b6yUjCdu3Fb0avP7HF9ZkeaUYA
    """

private let fsAlphaTextureGLSL = """
    /* fragment-shader: vertex color, uniform texture alpha (r8) */
    #version 450

    layout (binding=0) uniform sampler2D image;

    layout (location=0) in vec2 position;
    layout (location=1) in vec2 texcoord;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main(void) {
        outFragColor = vec4(color.rgb, texture(image, texcoord).r * color.a);
    }
    """

private let fsAlphaTextureSpvCEB64 = """
    XQAAAASUAwAAAAAAAAABgJdesntsONM6MGcxcoMSBeaqbZCSM/1LXfg6AGNgofxumxOEb8\
    b615/PtnqMfm/XWlm6+YN+BmCRldMPqKzeHyGTCvtXjSGTE/R59f4ITWJxQxQ2jpntrZGM\
    +h2a2cA1ClEKyd6JekmlZv1J2/H56RGAYWG91/hL5cHNzd1V85upoxe2/2bUWjbCtzvULQ\
    nY3L6Nxy7SJx2le0r6QBFVnrTnu5xrChvOHTmN6r+Jnt12HzXZ2bNgFrS8SEFA30Sbv/Bm\
    9hv2EHOEMwczX2+Crjq9tL0Fiuzouw1TolIEJ/bXUMJTpN1PBHTTus7hBxkOmGkwC/GIeL\
    J/l+Bq187SedQRz9zWyKfo1UgnMo2LOtuc/V50ujE14A5R5sau6RNxh40RSF67eBahuEC5\
    TWYNZckWtKxwY0icr0gZ5LKhJsWwNspes4qNS9cXn/IMfuvMZO4A
    """

private func decodeShader(device: GraphicsDevice, encodedText: String) -> ShaderFunction? {
    if let data = Data(base64Encoded: encodedText, options: .ignoreUnknownCharacters) {
        let inputStream = InputStream(data: data)
        let outputStream = OutputStream.toMemory()

        if decompress(input: inputStream, output: outputStream) == .success {
            let decodedData = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
            if let shader = Shader(data: decodedData), shader.validate() {
                if let module = device.makeShaderModule(from: shader) {
                    return module.makeFunction(name: module.functionNames.first ?? "")
                }
            }
        }
    }
    return nil
}

private func encodeSPIRVData(from url: URL?) -> String? {
    if let url {
        do {
            let data = try Data(contentsOf: url, options: [])
            let length = data.count
            Log.debug("URL:\(url) loaded \(length) bytes.")
            let inputStream = InputStream(data: data)
            let outputStream = OutputStream.toMemory()

            let compressionResult = compress(input: inputStream, inputBytes: length, output: outputStream, method: .best)
            if compressionResult == .success {
                let compressedData = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
                return compressedData.base64EncodedString()
            } else {
                Log.error("\(#function) compression failed: \(compressionResult)")
            }
        } catch {
            Log.error("\(#function) error on loading data: \(error)")
        }
    } else {
        Log.error("\(#function) error: Invalid URL")
    }
    return nil
}

private class GraphicsPipelineStates {
    enum Shader {
        case stencil        // fill stencil, no fragment function
        case color          // vertex color
        case image          // texture with tint color
        case alphaTexture   // for glyph (single channel texture)
        //case resolveMask    // merge two masks (a8, r8) to render target (r8)
    }
    enum DepthStencil {
        case generateWindingNumber
        case nonZero        // filled using the non-zero rule
        case even           // even-odd winding rule
        case zero           // zero stencil (inverse of non-zero rule)
        case odd            // odd winding (inverse of even-odd rule)
        case ignore         // don't read stencil
    }

    struct Vertex {
        var position: Float2
        var texcoord: Float2
        var color: Float4
    }

    struct ShaderFunctions {
        let vertexFunction: ShaderFunction
        let fragmentFunction: ShaderFunction?
    }

    private let device: GraphicsDevice
    private let shaderFunctions: [Shader: ShaderFunctions]
    private let defaultBindingSet: ShaderBindingSet
    private let defaultSampler: SamplerState

    struct RenderState: Hashable {
        let shader: Shader
        let colorFormat: PixelFormat
        let depthFormat: PixelFormat
        let blendState: BlendState
    }

    var pipelineStates: [RenderState: RenderPipelineState] = [:]
    var depthStencilStates: [DepthStencil: DepthStencilState] = [:]

    func renderState(_ rs: RenderState) -> RenderPipelineState? {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        if let state = pipelineStates[rs] { return state }

        guard let shader = shaderFunctions[rs.shader] else { return nil }

        var pipelineDescriptor = RenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = shader.vertexFunction
        pipelineDescriptor.fragmentFunction = shader.fragmentFunction
        pipelineDescriptor.colorAttachments = [
            .init(index: 0, pixelFormat: rs.colorFormat, blendState: rs.blendState)
        ]
        pipelineDescriptor.depthStencilAttachmentPixelFormat = rs.depthFormat
        if rs.shader == .stencil {
            pipelineDescriptor.vertexDescriptor.attributes = [
                .init(format: .float2, offset: 0, bufferIndex: 0, location: 0 ),
            ]
            pipelineDescriptor.vertexDescriptor.layouts = [
                .init(step: .vertex, stride: MemoryLayout<Float2>.stride, bufferIndex: 0)
            ]
        } else {
            pipelineDescriptor.vertexDescriptor.attributes = [
                .init(format: .float2, offset: 0, bufferIndex: 0, location: 0 ),
                .init(format: .float2, offset: MemoryLayout<Vertex>.offset(of: \.texcoord)!, bufferIndex: 0, location: 1 ),
                .init(format: .float4, offset: MemoryLayout<Vertex>.offset(of: \.color)!, bufferIndex: 0, location: 2 ),
            ]
            pipelineDescriptor.vertexDescriptor.layouts = [
                .init(step: .vertex, stride: MemoryLayout<Vertex>.stride, bufferIndex: 0)
            ]
        }
        pipelineDescriptor.primitiveTopology = .triangle
        pipelineDescriptor.triangleFillMode = .fill

        if let state = device.makeRenderPipelineState(descriptor: pipelineDescriptor) {
            pipelineStates[rs] = state
            return pipelineStates[rs]
        }
        return nil
    }

    func depthStencilState(_ ds: DepthStencil) -> DepthStencilState? {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        if let state = depthStencilStates[ds] { return state }

        var descriptor = DepthStencilDescriptor()
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = false

        switch ds {
        case .generateWindingNumber:
            descriptor.frontFaceStencil.depthStencilPassOperation = .incrementWrap
            descriptor.backFaceStencil.depthStencilPassOperation = .decrementWrap
        case .nonZero:
            // filled using the non-zero rule. (reference stencil value: 0)
            descriptor.frontFaceStencil.stencilCompareFunction = .notEqual
            descriptor.backFaceStencil.stencilCompareFunction = .notEqual
        case .even:
            // even-odd winding rule. (reference stencil value: 0)
            descriptor.frontFaceStencil.stencilCompareFunction = .notEqual
            descriptor.backFaceStencil.stencilCompareFunction = .notEqual
            descriptor.frontFaceStencil.readMask = 1
            descriptor.backFaceStencil.readMask = 1
        case .zero:
            // inverse of non-zero rule
            descriptor.frontFaceStencil.stencilCompareFunction = .equal
            descriptor.backFaceStencil.stencilCompareFunction = .equal
        case .odd:
            // inverse of even-odd rule
            descriptor.frontFaceStencil.stencilCompareFunction = .equal
            descriptor.backFaceStencil.stencilCompareFunction = .equal
            descriptor.frontFaceStencil.readMask = 1
            descriptor.backFaceStencil.readMask = 1
        case .ignore:
            break
        }

        if let depthStencilState = device.makeDepthStencilState(descriptor: descriptor) {
            depthStencilStates[ds] = depthStencilState
            return depthStencilStates[ds]
        }
        return nil
    }

    private init(device: GraphicsDevice,
                 shaderFunctions: [Shader: ShaderFunctions],
                 defaultBindingSet: ShaderBindingSet,
                 defaultSampler: SamplerState) {
        self.device = device
        self.shaderFunctions = shaderFunctions
        self.defaultBindingSet = defaultBindingSet
        self.defaultSampler = defaultSampler
        self.pipelineStates = [:]
        self.depthStencilStates = [:]
    }

    private static let lock = NSLock()
    private static weak var sharedInstance: GraphicsPipelineStates? = nil

    static func sharedInstance(device: GraphicsDevice) -> GraphicsPipelineStates? {
        if let instance = sharedInstance {
            return instance
        }
        lock.lock()
        defer { lock.unlock() }

        var instance = sharedInstance
        if instance != nil { return instance }

        repeat {
            let loadShader = { (name: String, content: String) -> ShaderFunction? in
                let fn = decodeShader(device: device, encodedText: content)
                if fn == nil {
                    Log.err("\(Self.self).\(#function): unable to decode shader: \(name)")
                }
                return fn
            }

            let vsStencilFunction = loadShader("vs-stencil", vsStencilSpvCEB64)
            if vsStencilFunction == nil { break }

            let vertexFunction = loadShader("vs-default", vsSpvCEB64)
            if vertexFunction == nil { break }

            let fragColorFunction = loadShader("fs-defalut", fsSpvCEB64)
            if fragColorFunction == nil { break }

            let fragTextureFunction = loadShader("fs-texture", fsTextureSpvCEB64)
            if fragTextureFunction == nil { break }

            let fragAlphaTextureFunction = loadShader("fs-alpha-texture", fsAlphaTextureSpvCEB64)
            if fragAlphaTextureFunction == nil { break }

            var shaderFunctions: [Shader: ShaderFunctions] = [:]
            shaderFunctions[.stencil] = ShaderFunctions(
                vertexFunction: vsStencilFunction!, fragmentFunction: nil)
            shaderFunctions[.color] = ShaderFunctions(
                vertexFunction: vertexFunction!, fragmentFunction: fragColorFunction)
            shaderFunctions[.image] = ShaderFunctions(
                vertexFunction: vertexFunction!, fragmentFunction: fragTextureFunction)
            shaderFunctions[.alphaTexture] = ShaderFunctions(
                vertexFunction: vertexFunction!, fragmentFunction: fragAlphaTextureFunction)

            let bindingLayout = ShaderBindingSetLayout(
                bindings: [
                    .init(binding: 0, type: .textureSampler, arrayLength: 1)
                ])

            let defaultBindingSet = device.makeShaderBindingSet(layout: bindingLayout)
            if defaultBindingSet == nil {
                Log.err("\(Self.self).\(#function): makeShaderBindingSet failed.")
                break
            }

            let samplerDesc = SamplerDescriptor()
            let defaultSampler = device.makeSamplerState(descriptor: samplerDesc)
            if defaultSampler == nil {
                Log.err("\(Self.self).\(#function): makeSampler failed.")
                break
            }

            instance = GraphicsPipelineStates(
                device: device,
                shaderFunctions: shaderFunctions,
                defaultBindingSet: defaultBindingSet!,
                defaultSampler: defaultSampler!)

            // make weak-ref
            Self.sharedInstance = instance
            Log.info("\(Self.self) instance created.")
        } while false

        return instance
    }

    func makeBuffer<T>(_ data: [T]) -> Buffer? {
        if data.isEmpty { return nil }

        let length = MemoryLayout<T>.stride * data.count
        if let buffer = device.makeBuffer(length: length,
                                          storageMode: .shared,
                                          cpuCacheMode: .writeCombined) {
            if let ptr = buffer.contents() {
                data.withUnsafeBytes {
                    assert($0.count == length)
                    ptr.copyMemory(from: $0.baseAddress!, byteCount: $0.count)
                }
                buffer.flush()
                return buffer
            }
        }
        return nil
    }
}


extension GraphicsContext {
    @discardableResult
    static func cachePipelineContext(_ deviceContext: GraphicsDeviceContext) -> Bool {
        if let state = GraphicsPipelineStates.sharedInstance(device: deviceContext.device) {
            deviceContext.cachedDeviceResources["DKGUI.GraphicsPipelineStates"] = state
            return true
        }
        return false
    }

    public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        let device = self.commandBuffer.device
        let width = self.backBuffer.width
        let height = self.backBuffer.height
        let pixelFormat = self.backBuffer.pixelFormat

        let backBuffer = device.makeTexture(
            descriptor: TextureDescriptor(textureType: .type2D,
                                          pixelFormat: pixelFormat,
                                          width: width,
                                          height: height,
                                          usage: [.renderTarget, .sampled]))

        if let backBuffer {
            var context = self
            context.backBuffer = backBuffer
            do {
                try content(&context)
                // TODO: draw context.backBuffer to self

            } catch {
                Log.error("Error!")
            }
        }
    }

    private func _fillStencil(_ path: Path, draw: (_: RenderCommandEncoder) -> Bool) {
        if path.isEmpty { return }

        struct PolygonElement {
            var vertices: [CGPoint] = []
        }
        var polygons: [PolygonElement] = []
        if true {
            var startPoint: CGPoint? = nil
            var currentPoint: CGPoint? = nil
            var polygon = PolygonElement()
            path.forEach { element in
                // make polygon array from path
                switch element {
                case .move(let to):
                    startPoint = to
                    currentPoint = to
                case .line(let p1):
                    if let p0 = currentPoint {
                        if polygon.vertices.last != p0 { polygon.vertices.append(p0) }
                        polygon.vertices.append(p1)
                    }
                    currentPoint = p1
                case .quadCurve(let p2, let p1):
                    if let p0 = currentPoint {
                        if polygon.vertices.last != p0 { polygon.vertices.append(p0) }
                        let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                        let length = curve.approximateLength()
                        if length > .ulpOfOne {
                            let step = 1.0 / curve.approximateLength()
                            var t = step
                            while t < 1.0 {
                                t += step
                                let pt = curve.interpolate(t)
                                polygon.vertices.append(pt)
                            }
                            polygon.vertices.append(p2)
                        }
                    }
                    currentPoint = p2
                case .curve(let p3, let p1, let p2):
                    if let p0 = currentPoint {
                        if polygon.vertices.last != p0 { polygon.vertices.append(p0) }
                        let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                        let length = curve.approximateLength()
                        if length > .ulpOfOne {
                            let step = 1.0 / curve.approximateLength()
                            var t = step
                            while t < 1.0 {
                                t += step
                                let pt = curve.interpolate(t)
                                polygon.vertices.append(pt)
                            }
                            polygon.vertices.append(p2)
                        }
                    }
                    currentPoint = p3
                case .closeSubpath:
                    if polygon.vertices.count > 0 {
                        polygons.append(polygon)
                        polygon = PolygonElement()
                    }
                    currentPoint = startPoint
                }
            }
        }

        let transform = self.transform.concatenating(self.viewTransform)
        var numVertices = 0
        polygons.forEach {
            numVertices += $0.vertices.count + 1
        }
        var vertexData: [Float2] = []
        vertexData.reserveCapacity(numVertices)

        var indexData: [UInt32] = []
        indexData.reserveCapacity(numVertices * 3)

        polygons.forEach { element in
            // make vertex, index data.
            if element.vertices.count < 2 { return }

            let baseIndex = UInt32(vertexData.count)
            var center: Vector2 = .zero
            element.vertices.forEach { pt in
                let v = Vector2(pt.applying(transform))
                vertexData.append(v.float2)
                center += v
            }
            center = center / Scalar(element.vertices.count)
            let pivotIndex = UInt32(vertexData.count)
            vertexData.append(center.float2)
            for i in 1..<pivotIndex {
                indexData.append(baseIndex + i - 1)
                indexData.append(baseIndex + i)
                indexData.append(pivotIndex)
            }
            indexData.append(pivotIndex - 1)
            indexData.append(baseIndex)
            indexData.append(pivotIndex)
        }
        if vertexData.count < 3 { return }
        if indexData.count < 3 { return }

        let device = self.commandBuffer.device
        guard let pipeline = GraphicsPipelineStates.sharedInstance(device: device) else {
            Log.err("GraphicsContext.fill() error: pipeline failed.")
            return
        }

        guard let vertexBuffer = pipeline.makeBuffer(vertexData) else {
            Log.err("GraphicsContext.fill() error: pipeline.makeBuffer failed.")
            return
        }
        guard let indexBuffer = pipeline.makeBuffer(indexData) else {
            Log.err("GraphicsContext.fill() error: pipeline.makeBuffer failed.")
            return
        }

        // pipeline states for generate polgon winding numbers
        guard let pipelineState = pipeline.renderState(
            .init(shader: .stencil,
                  colorFormat: backBuffer.pixelFormat,
                  depthFormat: stencilBuffer.pixelFormat,
                  blendState: .defaultOpaque)) else {
            Log.err("GraphicsContext.fill() error: pipeline.renderState failed.")
            return
        }
        guard let depthState = pipeline.depthStencilState(.generateWindingNumber) else {
            Log.err("GraphicsContext.fill() error: pipeline.depthStencilState failed.")
            return
        }

        let renderPass = RenderPassDescriptor(
            colorAttachments: [
                RenderPassColorAttachmentDescriptor(
                    renderTarget: backBuffer,
                    loadAction: .load,
                    storeAction: .store)
            ],
            depthStencilAttachment:
                RenderPassDepthStencilAttachmentDescriptor(
                    renderTarget: stencilBuffer,
                    loadAction: .clear,
                    storeAction: .dontCare,
                    clearStencil: 0))

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            Log.err("GraphicsContext.fill() error: makeRenderCommandEncoder failed.")
            return
        }

        // pass1: Generate polygon winding numbers to stencil buffer
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)

        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        encoder.setStencilReferenceValue(0)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.drawIndexed(indexCount: indexData.count,
                            indexType: .uint32,
                            indexBuffer: indexBuffer,
                            indexBufferOffset: 0,
                            instanceCount: 1,
                            baseVertex: 0,
                            baseInstance: 0)

        // pass2: draw only pixels that pass the stencil test
        if draw(encoder) {
            encoder.endEncoding()
        } else {
            Log.err("GraphicsContext.fill() error: draw callback failed.")
        }
    }

    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        self._fillStencil(path) { encoder in
            let device = self.commandBuffer.device
            guard let pipeline = GraphicsPipelineStates.sharedInstance(device: device) else {
                Log.err("GraphicsContext.fill() error: pipeline failed.")
                return false
            }

            // pipeline states for polygon fill
            guard let pipelineState = pipeline.renderState(.init(shader: .color,
                                                                colorFormat: backBuffer.pixelFormat,
                                                                depthFormat: stencilBuffer.pixelFormat,
                                                                blendState: .defaultAlpha)) else {
                Log.err("GraphicsContext.fill() error: pipeline.renderState failed.")
                return false
            }
            let depthState: DepthStencilState?
            if style.isEOFilled {
                depthState = pipeline.depthStencilState(.even)
            } else {
                depthState = pipeline.depthStencilState(.nonZero)
            }
            guard let depthState else {
                Log.err("GraphicsContext.fill() error: pipeline.depthStencilState failed.")
                return false
            }

            let texcoord = Vector2(0, 0).float2
            let color = DKGame.Color.red.float4
            let rectVertices: [GraphicsPipelineStates.Vertex] = [
                .init(position: Vector2(-1, -1).float2, texcoord: texcoord, color: color),
                .init(position: Vector2(-1, 1).float2, texcoord: texcoord, color: color),
                .init(position: Vector2(1, -1).float2, texcoord: texcoord, color: color),

                .init(position: Vector2(1, -1).float2, texcoord: texcoord, color: color),
                .init(position: Vector2(-1, 1).float2, texcoord: texcoord, color: color),
                .init(position: Vector2(1, 1).float2, texcoord: texcoord, color: color),
            ]

            guard let vertexBuffer = pipeline.makeBuffer(rectVertices) else {
                Log.err("GraphicsContext.fill() error: pipeline.makeBuffer() failed.")
                return false
            }
            encoder.setCullMode(.none)
            encoder.setFrontFacing(.clockwise)
            encoder.setStencilReferenceValue(0)
            encoder.setRenderPipelineState(pipelineState)
            encoder.setDepthStencilState(depthState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.draw(vertexStart: 0,
                         vertexCount: rectVertices.count,
                         instanceCount: 1,
                         baseInstance: 0)
            return true
        }
    }

    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        if path.isEmpty { return }
    }

    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }

    
}
