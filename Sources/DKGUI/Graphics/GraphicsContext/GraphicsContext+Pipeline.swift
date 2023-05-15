//
//  File: GraphicsContext+Pipeline.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

#if false
private func decodeShader(device: GraphicsDevice, encodedText: String) -> ShaderFunction? {
    if let data = Data(base64Encoded: encodedText, options: .ignoreUnknownCharacters) {
        let inputStream = InputStream(data: data)
        let outputStream = OutputStream.toMemory()

        if decompress(input: inputStream, output: outputStream) == .success {
            let decodedData = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
            if let shader = Shader(data: decodedData), shader.validate() {
                Log.debug("GraphicsPipeline Shader loaded: \(shader)")
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
#endif

// MARK: - Pipeline Types
enum _Shader {
    case stencil        // fill stencil, no fragment function
    case vertexColor    // vertex color
    case image          // texture with tint color
    case rcImage        // for glyph, single(red) channel texture
    case resolveMask    // merge two masks (a8, r8) to render target (r8)

    case filterProjectionTransform
    case filterColorMatrix
    case filterBlur
    case filterSrgbToLinear
    case filterLinearToSrgb

    case blendNormal
    case blendMultiply
    case blendScreen
    case blendOverlay
    case blendDarken
    case blendLighten
    case blendColorDodge
    case blendColorBurn
    case blendSoftLight
    case blendHardLight
    case blendDifference
    case blendExclusion
    case blendHue
    case blendSaturation
    case blendColor
    case blendLuminosity
    case blendClear
    case blendCopy
    case blendSourceIn
    case blendSourceOut
    case blendSourceAtop
    case blendDestinationOver
    case blendDestinationIn
    case blendDestinationOut
    case blendDestinationAtop
    case blendXor
    case blendPlusDarker
    case blendPlusLighter
}

enum _Stencil {
    case makeFill
    case makeStroke
    case testNonZero    // filled using the non-zero rule
    case testEven       // even-odd winding rule
    case testZero       // zero stencil (inverse of non-zero rule)
    case testOdd        // odd winding (inverse of even-odd rule)
    case ignore         // don't read stencil
}

struct _Vertex {
    var position: Float2
    var texcoord: Float2
    var color: Float4
}

// MARK: - Graphics Pipeline
class GraphicsPipelineStates {

    struct ShaderFunctions {
        let vertexFunction: ShaderFunction
        let fragmentFunction: ShaderFunction?
    }

    let device: GraphicsDevice
    private let shaderFunctions: [_Shader: ShaderFunctions]

    let defaultBindingSet1: ShaderBindingSet    // 1 texture
    let defaultBindingSet2: ShaderBindingSet    // 2 textures
    let defaultSampler: SamplerState
    let defaultMaskTexture: Texture // 2x2 r8

    struct RenderStateDescriptor: Hashable {
        let shader: _Shader
        let colorFormat: PixelFormat
        let depthFormat: PixelFormat
        let blendState: BlendState
    }
    private var renderStates: [RenderStateDescriptor: RenderPipelineState] = [:]
    private var depthStencilStates: [_Stencil: DepthStencilState] = [:]

    func renderState(shader: _Shader,
                     colorFormat: PixelFormat,
                     depthFormat: PixelFormat,
                     blendState: BlendState) -> RenderPipelineState? {
        renderState(RenderStateDescriptor(shader: shader,
                                          colorFormat: colorFormat,
                                          depthFormat: depthFormat,
                                          blendState: blendState))
    }

    func renderState(_ rs: RenderStateDescriptor) -> RenderPipelineState? {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        if let state = renderStates[rs] { return state }

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
                .init(format: .float2, offset: MemoryLayout<_Vertex>.offset(of: \.texcoord)!, bufferIndex: 0, location: 1 ),
                .init(format: .float4, offset: MemoryLayout<_Vertex>.offset(of: \.color)!, bufferIndex: 0, location: 2 ),
            ]
            pipelineDescriptor.vertexDescriptor.layouts = [
                .init(step: .vertex, stride: MemoryLayout<_Vertex>.stride, bufferIndex: 0)
            ]
        }
        pipelineDescriptor.primitiveTopology = .triangle
        pipelineDescriptor.triangleFillMode = .fill

        var reflection = PipelineReflection()
        if let state = device.makeRenderPipelineState(descriptor: pipelineDescriptor,
                                                      reflection: &reflection) {
            Log.debug("RenderPipelineState (_Shader.\(rs.shader)) Reflection: \(reflection)")
            renderStates[rs] = state
            return renderStates[rs]
        }
        return nil
    }

    func depthStencilState(_ ds: _Stencil) -> DepthStencilState? {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        if let state = depthStencilStates[ds] { return state }

        var descriptor = DepthStencilDescriptor()
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = false

        switch ds {
        case .makeFill:
            descriptor.frontFaceStencil.depthStencilPassOperation = .incrementWrap
            descriptor.backFaceStencil.depthStencilPassOperation = .decrementWrap
        case .makeStroke:
            descriptor.frontFaceStencil.depthStencilPassOperation = .incrementClamp
            descriptor.backFaceStencil.depthStencilPassOperation = .incrementClamp
        case .testNonZero:
            // filled using the non-zero rule. (reference stencil value: 0)
            descriptor.frontFaceStencil.stencilCompareFunction = .notEqual
            descriptor.backFaceStencil.stencilCompareFunction = .notEqual
        case .testEven:
            // even-odd winding rule. (reference stencil value: 0)
            descriptor.frontFaceStencil.stencilCompareFunction = .notEqual
            descriptor.backFaceStencil.stencilCompareFunction = .notEqual
            descriptor.frontFaceStencil.readMask = 1
            descriptor.backFaceStencil.readMask = 1
        case .testZero:
            // inverse of non-zero rule
            descriptor.frontFaceStencil.stencilCompareFunction = .equal
            descriptor.backFaceStencil.stencilCompareFunction = .equal
        case .testOdd:
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
                 shaderFunctions: [_Shader: ShaderFunctions],
                 defaultBindingSet1: ShaderBindingSet,
                 defaultBindingSet2: ShaderBindingSet,
                 defaultSampler: SamplerState,
                 defaultMaskTexture: Texture) {
        self.device = device
        self.shaderFunctions = shaderFunctions
        self.defaultBindingSet1 = defaultBindingSet1
        self.defaultBindingSet2 = defaultBindingSet2
        self.defaultSampler = defaultSampler
        self.defaultMaskTexture = defaultMaskTexture
        self.renderStates = [:]
        self.depthStencilStates = [:]
    }

    private static let lock = NSLock()
    private static weak var sharedInstance: GraphicsPipelineStates? = nil

    static func sharedInstance(commandQueue: CommandQueue) -> GraphicsPipelineStates? {
        if let instance = sharedInstance {
            return instance
        }
        lock.lock()
        defer { lock.unlock() }

        var instance = sharedInstance
        if instance != nil { return instance }

        let device = commandQueue.device
        do {
            struct LoadError: Error {
                let message: String
            }

            let loadShader = { (name: String) throws -> ShaderFunction in
                if let url = Bundle.module.url(forResource: name,
                                               withExtension: "spv",
                                               subdirectory: "SPIRV") {
                    do {
                        let d = try Data(contentsOf: url, options: [])
                        if let shader = Shader(data: d, name: name), shader.validate() {
                            Log.debug("GraphicsPipeline Shader loaded: \(shader)")
                            if let module = device.makeShaderModule(from: shader) {
                                if let fn = module.makeFunction(name: module.functionNames.first ?? "") {
                                    return fn
                                }
                            }
                        } else {
                            throw LoadError(message: "Failed to load shader: \(name)")
                        }
                    } catch {
                        Log.error("URL(\(url)) error: \(error)")
                        throw error
                    }
                }
                throw LoadError(message: "Unable to load shader: \(name)")
            }

            let vertexFunction = try loadShader("default.vert")

            var shaderFunctions: [_Shader: ShaderFunctions] = [:]

            //NOTE - Vulkan does not allow nil-fragment shader, unless rasterizer discard is enabled.
            // The Vulkan spec states: The pipeline must be created with a complete set of state
            // [VUID-VkGraphicsPipelineCreateInfo-None-06573]
            // https://registry.khronos.org/vulkan/specs/1.3/html/chap10.html#pipelines-graphics-subsets-complete
            shaderFunctions[.stencil] = ShaderFunctions(
                vertexFunction: try loadShader("stencil.vert"),
                fragmentFunction: try loadShader("stencil.frag"))

            let loadFragmentFunction = { (name: String) in
                ShaderFunctions(vertexFunction: vertexFunction,
                                fragmentFunction: try loadShader(name))
            }

            shaderFunctions[.vertexColor] = try loadFragmentFunction("vertex_color.frag")
            shaderFunctions[.image] = try loadFragmentFunction("draw_image.frag")
            shaderFunctions[.rcImage] = try loadFragmentFunction("draw_r8_opacity_image.frag")
            shaderFunctions[.resolveMask] = try loadFragmentFunction("resolve_mask.frag")

            // load filters
            shaderFunctions[.filterProjectionTransform] = try loadFragmentFunction("filter_projectionTransform.frag")
            shaderFunctions[.filterColorMatrix] = try loadFragmentFunction("filter_colorMatrix.frag")
            shaderFunctions[.filterBlur] = try loadFragmentFunction("filter_blur.frag")
            shaderFunctions[.filterSrgbToLinear] = try loadFragmentFunction("filter_srgbToLinear.frag")
            shaderFunctions[.filterLinearToSrgb] = try loadFragmentFunction("filter_linearToSrgb.frag")

            // load blend functions
            shaderFunctions[.blendNormal] = try loadFragmentFunction("blend_normal.frag")
            shaderFunctions[.blendMultiply] = try loadFragmentFunction("blend_multiply.frag")
            shaderFunctions[.blendScreen] = try loadFragmentFunction("blend_screen.frag")
            shaderFunctions[.blendOverlay] = try loadFragmentFunction("blend_overlay.frag")
            shaderFunctions[.blendDarken] = try loadFragmentFunction("blend_darken.frag")
            shaderFunctions[.blendLighten] = try loadFragmentFunction("blend_lighten.frag")
            shaderFunctions[.blendColorDodge] = try loadFragmentFunction("blend_colorDodge.frag")
            shaderFunctions[.blendColorBurn] = try loadFragmentFunction("blend_colorBurn.frag")
            shaderFunctions[.blendSoftLight] = try loadFragmentFunction("blend_softLight.frag")
            shaderFunctions[.blendHardLight] = try loadFragmentFunction("blend_hardLight.frag")
            shaderFunctions[.blendDifference] = try loadFragmentFunction("blend_difference.frag")
            shaderFunctions[.blendExclusion] = try loadFragmentFunction("blend_exclusion.frag")
            shaderFunctions[.blendHue] = try loadFragmentFunction("blend_hue.frag")
            shaderFunctions[.blendSaturation] = try loadFragmentFunction("blend_saturation.frag")
            shaderFunctions[.blendColor] = try loadFragmentFunction("blend_color.frag")
            shaderFunctions[.blendLuminosity] = try loadFragmentFunction("blend_luminosity.frag")
            shaderFunctions[.blendClear] = try loadFragmentFunction("blend_clear.frag")
            shaderFunctions[.blendCopy] = try loadFragmentFunction("blend_copy.frag")
            shaderFunctions[.blendSourceIn] = try loadFragmentFunction("blend_sourceIn.frag")
            shaderFunctions[.blendSourceOut] = try loadFragmentFunction("blend_sourceOut.frag")
            shaderFunctions[.blendSourceAtop] = try loadFragmentFunction("blend_sourceAtop.frag")
            shaderFunctions[.blendDestinationOver] = try loadFragmentFunction("blend_destinationOver.frag")
            shaderFunctions[.blendDestinationIn] = try loadFragmentFunction("blend_destinationIn.frag")
            shaderFunctions[.blendDestinationOut] = try loadFragmentFunction("blend_destinationOut.frag")
            shaderFunctions[.blendDestinationAtop] = try loadFragmentFunction("blend_destinationAtop.frag")
            shaderFunctions[.blendXor] = try loadFragmentFunction("blend_xor.frag")
            shaderFunctions[.blendPlusDarker] = try loadFragmentFunction("blend_plusDarker.frag")
            shaderFunctions[.blendPlusLighter] = try loadFragmentFunction("blend_plusLighter.frag")

            let bindingLayout1 = ShaderBindingSetLayout(
                bindings: [
                    ShaderBinding(binding: 0, type: .textureSampler, arrayLength: 1),
                ])

            let bindingLayout2 = ShaderBindingSetLayout(
                bindings: [
                    ShaderBinding(binding: 0, type: .textureSampler, arrayLength: 1),
                    ShaderBinding(binding: 1, type: .textureSampler, arrayLength: 1),
                ])

            guard let defaultBindingSet1 = device.makeShaderBindingSet(layout: bindingLayout1)
            else {
                throw LoadError(message: "makeShaderBindingSet failed.")
            }
            guard let defaultBindingSet2 = device.makeShaderBindingSet(layout: bindingLayout2)
            else {
                throw LoadError(message: "makeShaderBindingSet failed.")
            }

            let samplerDesc = SamplerDescriptor(minFilter: .linear,
                                                magFilter: .linear)
            guard let defaultSampler = device.makeSamplerState(descriptor: samplerDesc)
            else {
                throw LoadError(message: "makeSampler failed.")
            }
            
            guard let defaultMaskTexture = device.makeTexture(
                descriptor: TextureDescriptor(textureType: .type2D,
                                              pixelFormat: .r8Unorm,
                                              width: 2,
                                              height: 2,
                                              usage: [.copyDestination, .sampled]))
            else {
                throw LoadError(message: "makeTexture failed.")
            }

            let texWidth = defaultMaskTexture.width
            let texHeight = defaultMaskTexture.height
            let bufferLength = texWidth * texHeight
            guard let stgBuffer = device.makeBuffer(length: bufferLength,
                                                    storageMode: .shared,
                                                    cpuCacheMode: .writeCombined)
            else {
                throw LoadError(message: "makeBuffer failed.")
            }
            if let ptr = stgBuffer.contents() {
                let pixelData = [UInt8](repeating: 1, count: bufferLength)
                pixelData.withUnsafeBytes {
                    assert($0.count == bufferLength)
                    ptr.copyMemory(from: $0.baseAddress!, byteCount: $0.count)
                }
                stgBuffer.flush()
            } else {
                throw LoadError(message: "buffer.contents() failed.")
            }

            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                throw LoadError(message: "makeCommandBuffer failed.")
            }
            guard let encoder = commandBuffer.makeCopyCommandEncoder() else {
                throw LoadError(message: "makeCopyCommandEncoder failed.")
            }
            encoder.copy(from: stgBuffer,
                         sourceOffset: BufferImageOrigin(
                            offset: 0,
                            imageWidth: texWidth,
                            imageHeight: texHeight),
                         to: defaultMaskTexture,
                         destinationOffset: TextureOrigin(layer: 0, level: 0,
                                                          x: 0, y: 0, z: 0),
                         size: TextureSize(width: texWidth,
                                           height: texHeight,
                                           depth: 1))

            encoder.endEncoding()
            commandBuffer.commit()

            instance = GraphicsPipelineStates(
                device: device,
                shaderFunctions: shaderFunctions,
                defaultBindingSet1: defaultBindingSet1,
                defaultBindingSet2: defaultBindingSet2,
                defaultSampler: defaultSampler,
                defaultMaskTexture: defaultMaskTexture)

            // make weak-ref
            Self.sharedInstance = instance
            Log.info("\(Self.self).\(#function): instance created.")
        } catch {
            fatalError("\(Self.self).\(#function) Error: \(error)")
        }

        return instance
    }
}

// MARK: - GraphicsContext extensions
extension GraphicsContext {
    @discardableResult
    static func cachePipelineContext(_ deviceContext: GraphicsDeviceContext) -> Bool {
        if let queue = deviceContext.renderQueue() {
            if let state = GraphicsPipelineStates.sharedInstance(commandQueue: queue) {
                deviceContext.cachedDeviceResources["DKGUI.GraphicsPipelineStates"] = state
                return true
            }
        }
        return false
    }

    struct RenderPass {
        let encoder: RenderCommandEncoder
        let descriptor: RenderPassDescriptor

        func end() {
            if self.encoder.isCompleted == false {
                self.encoder.endEncoding()
            }
        }

        var colorFormat: PixelFormat {
            descriptor.colorAttachments.first?.renderTarget?.pixelFormat ??
                .invalid
        }

        var depthFormat: PixelFormat {
            descriptor.depthStencilAttachment.renderTarget?.pixelFormat ??
                .invalid
        }
    }

    func beginRenderPass(enableStencil: Bool) -> RenderPass? {
        let stencil = enableStencil ? self.renderTargets.stencilBuffer : nil
        return beginRenderPass(viewport: self.viewport,
                               renderTarget: self.renderTargets.source,
                               stencilBuffer: stencil,
                               loadAction: .clear,
                               clearColor: .clear)
    }

    func beginRenderPassCompositionTarget() -> RenderPass? {
        return beginRenderPass(viewport: self.viewport,
                               renderTarget: self.renderTargets.composited,
                               stencilBuffer: nil,
                               loadAction: .dontCare,
                               clearColor: .clear)
    }

    func beginRenderPassBackdropTarget(clear: Bool = false,
                                       clearColor: DKGame.Color = .clear
    ) -> RenderPass? {
        let loadAction: RenderPassAttachmentLoadAction = clear ? .clear : .load
        return beginRenderPass(viewport: self.viewport,
                               renderTarget: self.renderTargets.backdrop,
                               stencilBuffer: nil,
                               loadAction: loadAction,
                               clearColor: clearColor)
    }

    func beginRenderPass(viewport: CGRect,
                         renderTarget: Texture,
                         stencilBuffer: Texture?,
                         loadAction: RenderPassAttachmentLoadAction,
                         clearColor: DKGame.Color) -> RenderPass? {
        var descriptor = RenderPassDescriptor(
            colorAttachments: [.init(renderTarget: renderTarget,
                                     loadAction: loadAction,
                                     storeAction: .store,
                                     clearColor: clearColor)])
        if let stencilBuffer {
            descriptor.depthStencilAttachment = .init(
                renderTarget: stencilBuffer,
                loadAction: .clear,
                storeAction: .dontCare,
                clearStencil: 0)
        }
        return self.beginRenderPass(descriptor: descriptor, viewport: viewport)
    }

    func beginRenderPass(descriptor: RenderPassDescriptor,
                         viewport: CGRect) -> RenderPass? {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor) else {
            Log.err("GraphicsContext error: makeRenderCommandEncoder failed.")
            return nil
        }
        let viewport = viewport.standardized
        let x = Int(viewport.origin.x)
        let y = Int(viewport.origin.y)
        let width = Int(viewport.width)
        let height = Int(viewport.height)

        encoder.setViewport(Viewport(x: viewport.origin.x,
                                     y: viewport.origin.y,
                                     width: viewport.width,
                                     height: viewport.height,
                                     nearZ: .zero, farZ: 1))
        encoder.setScissorRect(ScissorRect(x: x, y: y,
                                           width: width, height: height))

        return RenderPass(encoder: encoder,
                          descriptor: descriptor)
    }

    func clear(with color: DKGame.Color) {
        if let renderPass = self.beginRenderPassBackdropTarget(
            clear: true,
            clearColor: color) {
            renderPass.end()
        }
    }

    func encodeDrawCommand(renderPass: RenderPass,
                           shader: _Shader,
                           stencil: _Stencil,
                           vertices: [_Vertex],
                           texture: Texture?,
                           blendState: BlendState) {
        assert(shader != .stencil) // .stencil uses a different vertex format.

        if vertices.isEmpty { return }

        guard let renderState = pipeline.renderState(
            shader: shader,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: blendState) else {
            Log.err("GraphicsContext error: pipeline.renderState failed.")
            return
        }
        guard let depthState = pipeline.depthStencilState(stencil) else {
            Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
            return
        }
        guard let vertexBuffer = self.makeBuffer(vertices) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return
        }

        let encoder = renderPass.encoder
        encoder.setRenderPipelineState(renderState)
        encoder.setDepthStencilState(depthState)
        if let texture {
            pipeline.defaultBindingSet1.setTexture(texture, binding: 0)
            pipeline.defaultBindingSet1.setSamplerState(pipeline.defaultSampler, binding: 0)
            encoder.setResource(pipeline.defaultBindingSet1, atIndex: 0)
        }

        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        encoder.setStencilReferenceValue(0)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.draw(vertexStart: 0,
                     vertexCount: vertices.count,
                     instanceCount: 1,
                     baseInstance: 0)
    }

    func makeBuffer<T>(_ data: [T]) -> Buffer? {
        if data.isEmpty { return nil }

        let device = self.commandBuffer.device
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
