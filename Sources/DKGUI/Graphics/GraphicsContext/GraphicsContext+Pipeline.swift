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

    case filterColorMatrix
    case filterBlur

    case blendNormal;
    case blendMultiply;
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

struct _PushConstant {
    var colorMatrix: ColorMatrix = .init()
    static let identity = _PushConstant()
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
            shaderFunctions[.stencil] = ShaderFunctions(
                vertexFunction: try loadShader("stencil.vert"),
                fragmentFunction: try loadShader("stencil.frag"))
            shaderFunctions[.vertexColor] = ShaderFunctions(
                vertexFunction: vertexFunction,
                fragmentFunction: try loadShader("vertex_color.frag"))
            shaderFunctions[.image] = ShaderFunctions(
                vertexFunction: vertexFunction,
                fragmentFunction: try loadShader("draw_image.frag"))
            shaderFunctions[.rcImage] = ShaderFunctions(
                vertexFunction: vertexFunction,
                fragmentFunction: try loadShader("draw_r8_opacity_image.frag"))
            shaderFunctions[.resolveMask] = ShaderFunctions(
                vertexFunction: vertexFunction,
                fragmentFunction: try loadShader("resolve_mask.frag"))

            // load filter
            shaderFunctions[.filterColorMatrix] = ShaderFunctions(
                vertexFunction: vertexFunction,
                fragmentFunction: try loadShader("filter_color_matrix.frag"))

            // load blend functions
            shaderFunctions[.blendNormal] = ShaderFunctions(
                vertexFunction: vertexFunction,
                fragmentFunction: try loadShader("blend_normal.frag"))
            shaderFunctions[.blendMultiply] = ShaderFunctions(
                vertexFunction: vertexFunction,
                fragmentFunction: try loadShader("blend_multiply.frag"))

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

            let samplerDesc = SamplerDescriptor()
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
            Log.error("\(Self.self).\(#function) Error: \(error)")
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

    func makeEncoder(enableStencil: Bool) -> RenderCommandEncoder? {
        return makeEncoder(renderTarget: self.renderTargets.source,
                           enableStencil: enableStencil,
                           clear: true,
                           clearColor: .clear)
    }

    func makeEncoderCompositionTarget() -> RenderCommandEncoder? {
        return makeEncoder(renderTarget: self.renderTargets.composited,
                           enableStencil: false,
                           clear: true,
                           clearColor: .clear)
    }

    func makeEncoderBackdrop(clear: Bool = false,
                             clearColor: DKGame.Color = .clear) -> RenderCommandEncoder? {
        return makeEncoder(renderTarget: self.renderTargets.backdrop,
                           enableStencil: false,
                           clear: clear,
                           clearColor: clearColor)
    }

    func makeEncoder(renderTarget: Texture,
                     enableStencil: Bool,
                     clear: Bool,
                     clearColor: DKGame.Color? = nil) -> RenderCommandEncoder? {
        let loadAction: RenderPassAttachmentLoadAction
        if clear {
            loadAction = .clear
        } else {
            loadAction = .load
        }
        let clearColor = clearColor ?? .clear
        var renderPass = RenderPassDescriptor(
            colorAttachments: [.init(renderTarget: renderTarget,
                                     loadAction: loadAction,
                                     storeAction: .store,
                                     clearColor: clearColor)])
        if enableStencil {
            renderPass.depthStencilAttachment = .init(
                renderTarget: self.renderTargets.stencilBuffer,
                loadAction: .clear,
                storeAction: .dontCare,
                clearStencil: 0)
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            Log.err("GraphicsContext error: makeRenderCommandEncoder failed.")
            return nil
        }
        let x = Int(self.viewport.origin.x)
        let y = Int(self.viewport.origin.y)
        let width = Int(self.viewport.width)
        let height = Int(self.viewport.height)
        if x != 0 && y != 0
            && width != self.renderTargets.width
            && height != self.renderTargets.height {
            encoder.setViewport(Viewport(x: self.viewport.origin.x,
                                         y: self.viewport.origin.y,
                                         width: self.viewport.width,
                                         height: self.viewport.height,
                                         nearZ: .zero, farZ: 1))
            encoder.setScissorRect(ScissorRect(x: x, y: y,
                                               width: width, height: height))
        }
        return encoder
    }

    func clear(with color: DKGame.Color) {
        if let encoder = self.makeEncoderBackdrop(clear: true,
                                                  clearColor: color) {
            encoder.endEncoding()
        }
    }

    func encodeDrawCommand(shader: _Shader,
                           stencil: _Stencil,
                           vertices: [_Vertex],
                           texture: Texture?,
                           blendState: BlendState,
                           encoder: RenderCommandEncoder) {
        assert(shader != .stencil) // .stencil uses a different vertex format.
        assert(shader != .filterColorMatrix)

        if vertices.isEmpty { return }

        guard let renderState = pipeline.renderState(
            shader: shader,
            colorFormat: self.renderTargets.colorFormat,
            depthFormat: stencil == .ignore ? .invalid : stencilBuffer.pixelFormat,
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
