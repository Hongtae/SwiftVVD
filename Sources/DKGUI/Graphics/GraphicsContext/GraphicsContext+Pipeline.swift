//
//  File: GraphicsContext+Pipeline.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

// MARK: - SPIR-V Shaders
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
    XQAAAAR4AgAAAAAAAAABgJdesnC95qjyNRPxiVbqegigYKDoCIXwQXVuG9QUdX/sz/g0ud\
    Z1k9NMG4TOnzFTBQWL0mum/q1NErbUd7wshLipDIuwIE/3pJbxD0oPiyriJ9ME6rvrrNEK\
    3yiko9ulTcWJOlMz9ZO+aUyf3WUw/WQ5tqoIyvbK6Ne+GivV5pvo2dX2+hzkJ9cH082r1K\
    Wbh3D8SghnyRA3ymyR2ju+b8hXKAXIqk9toUqXZI5wODcc03rWbnT1lW5YHGytgQVvc5ZV\
    sUFn5EsZY3P+3s+h8PF5h+sh8EXya8RNGWYxbs9yCpBLutJ7cccwXimZP3DwVCNDJlg=
    """

private let vsGLSL = """
    /* vertex shader for vertex-color, texcoord */
    #version 450

    layout (location=0) in vec2 position;
    layout (location=1) in vec2 texcoord;
    layout (location=2) in vec4 color;

    layout (location=0) out vec2 outMaskUV;
    layout (location=1) out vec2 outTexUV;
    layout (location=2) out vec4 outColor;

    void main() {
        outMaskUV = (position + vec2(1, -1)) * vec2(0.5, -0.5);
        outTexUV = texcoord;
        outColor = color;
        gl_Position = vec4(position, 0, 1);
    }
    """

private let vsSpvCEB64 = """
    XQAAAAQQBAAAAAAAAAABgJdesnC95qjyNRPy1HqTc7gPRthELV8YDfBHNWmt93l0V6ZSk2\
    s6fW41iQ5gA3M3dIKJKHQBbfk2ux785iNMcOzvSUxGzMdCYrZ1qT/LVH9/z/oSnRpnkLix\
    kQ15KbbSYTuAEEVwxpGQ1QXokFQsHl4pd0qLCZzOvH/xzezIiNwnzG7nAUdPeQJzwRYZjp\
    P0LHfRAgDbn30FRqT3HB3Y+TQUYnc1k/pMSnSQgBmp13QHXYLyZRt+E6aTrGLqg7jtsgDA\
    wxsnlA3WyMhcnHuq9FyVQysA/CoLBDy0r7XobWVvQJ2BJxOFhvT3U5IlU/miEMC5+npsUU\
    2DCnXXCer6hDoJXnbNHI+avpFcdDBbB+P8/jLtp+qNMVmYmrUCjvhM+EiGZ15ms7yCzAk2\
    41WIbZH6Q4iCPH0E3YsiAexGTRNjAeFh9tAsAA==
    """

private let fsVertexColorGLSL = """
    #version 450

    layout (binding=0) uniform sampler2D maskImage;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main(void) {
        if (texture(maskImage, maskUV).r <= 0)
            discard;
        outFragColor = color;
    }
    """

private let fsVertexColorSpvCEB64 = """
    XQAAAASUAgAAAAAAAAABgJdesnDIkXTyNRPx9MW6ESsyRORUOdl1zDyzarYlCfMkl6fI14\
    mXogxjfgm++4bKnd4h29/GCiwUxwJag764lX2AzXjdZaXubDwWd/Fr2CV/e6R13bj2xYYi\
    7ryYNC91RJk8F/6t11QO+5hTX0Cqi3k7YqGDh2Y4IrTCZu/fBBEG6d8CtNoXDDHGh+fav8\
    iOBrC3jR114MbV/ympDPJsrN7aFjKUJC8CMMLhVSCmO89CQxxq3TqR3Q2H7X6SoDvwYJY7\
    vBXrqhEyXjYRebYsHgy85x0uDLrV6qgAHkRxKCt2ffl7IQ02n6oKd5UtGQ9pNd86LnEnQd\
    9+uiss7KYRNcQkhAA=
    """

private let fsImageGLSL = """
    #version 450

    layout (binding=0) uniform sampler2D maskImage;
    layout (binding=1) uniform sampler2D image;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main() {
        if (texture(maskImage, maskUV).r <= 0)
            discard;
        outFragColor = texture(image, texUV) * color;
    }
    """

private let fsImageSpvCEB64 = """
    XQAAAAQ0AwAAAAAAAAABgJdesnDIkXTyNRPyaB1kVkXQvrmDdSIJ3pa9vk6Vb+532Il6Az\
    ZWXfTwVJfXA+P+cPurpexpQfF8OuSqKY4gIf4ThhmBOvi1hxWEFA+l8t7/elXTSQ69x0EZ\
    B/il77Vh+X/TjUHm9ZhAoCl92jGjYLpX+OkRhzK6fBBwSL5vltf2gOGuskZgD5H+2oLoB8\
    7M/6mDOPA6VE+HOqXa+11bds3yNwsC9/NACG5BGeLUmLOLby8no6YZf1ogVFFSymst9Pph\
    PEJkaGaWvJPqT8SOpS8Z2jg7W7oyygpcX0gLTbaofBMWPw4MJ2YkwwrbenWprffg2wfSeg\
    iJLeNoGLxBMGhZwePC21RxrGqC11nriEO88nKYxJ/XrAr7CyMD/gwA
    """

private let fsRedToAlphaImageGLSL = """
    #version 450

    layout (binding=0) uniform sampler2D maskImage;
    layout (binding=1) uniform sampler2D image;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main(void) {
        if (texture(maskImage, maskUV).r <= 0)
            discard;
        outFragColor = vec4(color.rgb, texture(image, texUV).r * color.a);
    }
    """

private let fsRedToAlphaImageSpvCEB64 = """
    XQAAAAT0AwAAAAAAAAABgJdesnDIkXTyNRPzLU/7FEkN1hUbMQvGqhcxUct3e3t7iNtpvE\
    ZYQFGWZGd2oDREzGh0F99vQXe6znzgxXRaerG7l0NoHFEZRZ1LHxGpkorLEpcd8y4jYUML\
    wt6aj1iRVmi/lUldd6bU5Ws77LmgM9GYvhidpUldJMwXLvDDeKVDsfkue7s70F0ysJ+aWc\
    N5EQTw4kHd6PP7c9uaZQdi7qObtkb4yyLZcrQLvq1Mr8MRPOb2tAKaedXWPYmCb8E5p7XX\
    oaRl3iDoPjaa3kfDO5QF/L0sFXh2kgh1IGui56ThenmYU+1kAfkylxWWeUFZUKoZ/UVp9W\
    34ztcvdCPlM0clD9KXBrp1IqaLzsui7he3Zf4ulKmcHnu5caN2YckOkDWb2zBR/25gEB0N\
    sUDX6kMjySM7ZpotaAFYLfi91v0WWe/48P/HGBNJIkrlXZQA
    """

private let fsResolveMaskGLSL = """
    #version 450

    layout (binding=0) uniform sampler2D maskImage;
    layout (binding=1) uniform sampler2D image;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main() {
        if (texture(maskImage, maskUV).r <= 0)
            discard;

        vec4 c = texture(image, texUV) * color;
        /* output target should be r8unorm */
        outFragColor = c.aaaa;
    }
    """

private let fsResolveMaskSpvCEB64 = """
    XQAAAARYAwAAAAAAAAABgJdesnDIkXTyNRPysLo7c7gPRthELV8WOPdqmzPcDt/U+ygmOh\
    3wlFVLEXTbfT8wG1R6wUKE6/M7779voxmGUK9Ko/Xb5akEVe8/ETGqlrDigO+pNAsx45+g\
    PWVIoQy+HUk6L3xxMSZZXHxiJu3UksL+LXCw6/oR5c/rgaM+T3FmNkome6WAevjN5WbsZ2\
    WdWxh1S9kNDbiFoDxEMrAqn6XPuQvIMH/AYMwWUkEOkVqFyGEqApMKi6HRTSxtdy0UiF23\
    +eJifpHHYgtPQ/t338ok4V7LIlbS2p81LCqJl/LRvFVWn3JevQ5RvtCY4ey/7OrbFYni8O\
    DY0PZlefvACJ+wQBvTRsyEQsEnpCZkJqNkNUKI7ug3SksOjOv1wzgg0nBEgUA=
    """

private let fsColorMatrixImageGLSL = """
    #version 450

    layout (push_constant) uniform Constants {
        float colorMatrixR[5];
        float colorMatrixG[5];
        float colorMatrixB[5];
        float colorMatrixA[5];
    } pc;

    layout (binding=0) uniform sampler2D maskImage;
    layout (binding=1) uniform sampler2D image;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main() {
        if (texture(maskImage, maskUV).r <= 0)
            discard;
        vec4 fragColor = texture(image, texUV) * color;
        vec4 cmR = vec4(pc.colorMatrixR[0], pc.colorMatrixR[1], pc.colorMatrixR[2], pc.colorMatrixR[3]);
        vec4 cmG = vec4(pc.colorMatrixG[0], pc.colorMatrixG[1], pc.colorMatrixG[2], pc.colorMatrixG[3]);
        vec4 cmB = vec4(pc.colorMatrixB[0], pc.colorMatrixB[1], pc.colorMatrixB[2], pc.colorMatrixB[3]);
        vec4 cmA = vec4(pc.colorMatrixA[0], pc.colorMatrixA[1], pc.colorMatrixA[2], pc.colorMatrixA[3]);
        float r = dot(fragColor, cmR) + pc.colorMatrixR[4];
        float g = dot(fragColor, cmG) + pc.colorMatrixG[4];
        float b = dot(fragColor, cmB) + pc.colorMatrixB[4];
        float a = dot(fragColor, cmA) + pc.colorMatrixA[4];
        outFragColor = vec4(r, g, b, a);
    }
    """

private let fsColorMatrixImageSpvCEB64 = """
    XQAAAAQoCQAAAAAAAAABgJdesnDIkXTyNRP3eX+1wTM2BjHpoMwrILM5Tt4ypo/o5Hzcc4\
    fVT3pcir7GSZahyo6w0qIEQwu0yF5Q3L4VDFBKSEempWTi8pXfUkh8Z3PKE3DJwDlwR7uI\
    iZ6YwbUPqHNNfdPbnxEG1+da/rwkLWcfAtyHTI+wlSmG3s78bDvVS6jzvTbwBNVBhkhZQ1\
    27J32RcsQxAdix1RVbkQJQHaWM5Lq7Gc7YBuOicgOQyT7QnuyG269xsyGagVTz4ppic7xm\
    GVWeq8Vz3W6PqNhgoYojfES1+Xl16SmxeNL0iBCHpeJ/DnFUUI6Havo3Kvl/Y4Bv8kDbIe\
    30w2nGbQLq1LQeO94DNxirSTmOicceayDmS4AzA5DUiBQi2OcjfR9Zbzwgy6NlDn+0B7px\
    7tWqVP4RxP0wIFMYI14YcsclnAfTRLJdKCH+PHSeRwgSKUW0Pq7qDoYxk+ITfgmzwllZcE\
    YXo8BawzzUZte7wUM0l1t4FORCn2fSW2dzFguD4qJG+A304T2l5Oqck2WklWBacd1cbHuT\
    vE+19ASW0E8sy5IwL6eRx6rl/5qblKUvQErRtCGQv98j3iTCISWOFI7hV8B48YFJ35/pah\
    v3PxGeVdJ7ZgdBZc/zW8V7qyK2+mdt0eWNR0uPClPHOXnAsdN9h/IIc2LV3xZB9Lj0godI\
    kfxeInef6twkwzEAs1da9eMZ15iPeg9AJgCUWBIsVAQ/G3wIqbFSB3T5wpqmD8oA
    """

private let fsBlurImageGLSL = ""

private let fsBlurImageSpvCEB64 = ""


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

// MARK: - Pipeline Types
enum _Shader {
    case stencil        // fill stencil, no fragment function
    case vertexColor    // vertex color
    case image          // texture with tint color
    case rcImage        // for glyph, single(red) channel texture
    case resolveMask    // merge two masks (a8, r8) to render target (r8)
    case colorMatrixImage
    case blurImage
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

    let defaultBindingSet1: ShaderBindingSet    // 1 texture (mask)
    let defaultBindingSet2: ShaderBindingSet    // 2 textures (mask, diffuse)
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
        repeat {
            let loadShader = { (name: String, content: String) -> ShaderFunction? in
                let fn = decodeShader(device: device, encodedText: content)
                if fn == nil {
                    Log.err("\(Self.self).\(#function): unable to decode shader: \(name)")
                }
                return fn
            }

            guard let vsStencilFunction = loadShader("vs-stencil", vsStencilSpvCEB64)
            else { break }

            guard let vertexFunction = loadShader("vs-default", vsSpvCEB64)
            else { break }

            guard let fsVertexColorFunction = loadShader("fs-vertex-color", fsVertexColorSpvCEB64)
            else { break }

            guard let fsImageFunction = loadShader("fs-image", fsImageSpvCEB64)
            else { break }

            guard let fsRCImageFunction = loadShader("fs-red-alpha-channel-image", fsRedToAlphaImageSpvCEB64)
            else { break }

            guard let fsResolveMaskFunction = loadShader("fs-resolve-mask", fsResolveMaskSpvCEB64)
            else { break }

            guard let fsColorMatrixImageFunction = loadShader("fs-color-matrix-image", fsColorMatrixImageSpvCEB64)
            else { break }

            var shaderFunctions: [_Shader: ShaderFunctions] = [:]
            shaderFunctions[.stencil] = ShaderFunctions(
                vertexFunction: vsStencilFunction, fragmentFunction: nil)
            shaderFunctions[.vertexColor] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsVertexColorFunction)
            shaderFunctions[.image] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsImageFunction)
            shaderFunctions[.rcImage] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsRCImageFunction)
            shaderFunctions[.resolveMask] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsResolveMaskFunction)
            shaderFunctions[.colorMatrixImage] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsColorMatrixImageFunction)
            shaderFunctions[.blurImage] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsImageFunction)

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
                Log.err("\(Self.self).\(#function): makeShaderBindingSet failed.")
                break
            }
            guard let defaultBindingSet2 = device.makeShaderBindingSet(layout: bindingLayout2)
            else {
                Log.err("\(Self.self).\(#function): makeShaderBindingSet failed.")
                break
            }

            let samplerDesc = SamplerDescriptor()
            guard let defaultSampler = device.makeSamplerState(descriptor: samplerDesc)
            else {
                Log.err("\(Self.self).\(#function): makeSampler failed.")
                break
            }
            
            guard let defaultMaskTexture = device.makeTexture(
                descriptor: TextureDescriptor(textureType: .type2D,
                                              pixelFormat: .r8Unorm,
                                              width: 2,
                                              height: 2,
                                              usage: [.copyDestination, .sampled]))
            else {
                Log.err("\(Self.self).\(#function): makeTexture failed.")
                break
            }

            let texWidth = defaultMaskTexture.width
            let texHeight = defaultMaskTexture.height
            let bufferLength = texWidth * texHeight
            guard let stgBuffer = device.makeBuffer(length: bufferLength,
                                                    storageMode: .shared,
                                                    cpuCacheMode: .writeCombined)
            else {
                Log.err("\(Self.self).\(#function): makeBuffer failed.")
                break
            }
            if let ptr = stgBuffer.contents() {
                let pixelData = [UInt8](repeating: 1, count: bufferLength)
                pixelData.withUnsafeBytes {
                    assert($0.count == bufferLength)
                    ptr.copyMemory(from: $0.baseAddress!, byteCount: $0.count)
                }
                stgBuffer.flush()
            } else {
                Log.err("\(Self.self).\(#function): buffer.contents() failed.")
                break
            }

            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                Log.err("\(Self.self).\(#function): makeCommandBuffer failed.")
                break
            }
            guard let encoder = commandBuffer.makeCopyCommandEncoder() else {
                Log.err("\(Self.self).\(#function): makeCopyCommandEncoder failed.")
                break
            }
            encoder.copy(from: stgBuffer,
                         sourceOffset: BufferImageOrigin(offset: 0, imageWidth: texWidth, imageHeight: texHeight),
                         to: defaultMaskTexture,
                         destinationOffset: TextureOrigin(layer: 0, level: 0, x: 0, y: 0, z: 0),
                         size: TextureSize(width: texWidth, height: texHeight, depth: 1))

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
            Log.info("\(Self.self) instance created.")
        } while false

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

    func _makeEncoder(_ backBuffer: Texture,
                  stencilBuffer: Texture? = nil) -> RenderCommandEncoder? {
        var renderPass = RenderPassDescriptor(
            colorAttachments: [
                RenderPassColorAttachmentDescriptor(
                    renderTarget: backBuffer,
                    loadAction: .load,
                    storeAction: .store)
            ])
        if let stencilBuffer {
            renderPass.depthStencilAttachment = RenderPassDepthStencilAttachmentDescriptor(
                renderTarget: stencilBuffer,
                loadAction: .clear,
                storeAction: .dontCare,
                clearStencil: 0)
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            Log.err("GraphicsContext error: makeRenderCommandEncoder failed.")
            return nil
        }
        return encoder
    }

    func _draw(texture: Texture,
               in frame: CGRect,
               transform: CGAffineTransform,
               textureFrame: CGRect,
               textureTransform: CGAffineTransform,
               blendState: BlendState,
               color: DKGame.Color,
               colorMatrix: ColorMatrix? = nil) {
        let trans = transform.concatenating(self.viewTransform)
        let makeVertex = { x, y, u, v in
            _Vertex(position: Vector2(x, y).applying(trans).float2,
                    texcoord: Vector2(u, v).applying(textureTransform).float2,
                    color: color.float4)
        }
        let uvMinX = textureFrame.minX / CGFloat(texture.width)
        let uvMaxX = textureFrame.maxX / CGFloat(texture.width)
        let uvMinY = textureFrame.minY / CGFloat(texture.height)
        let uvMaxY = textureFrame.maxY / CGFloat(texture.height)

        let vertices: [_Vertex] = [
            makeVertex(frame.minX, frame.maxY, uvMinX, uvMaxY),
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY),
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY),
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY),
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY),
            makeVertex(frame.maxX, frame.minY, uvMaxX, uvMinY)
        ]

        guard let encoder = self._makeEncoder(self.backBuffer) else {
            return
        }

        if let colorMatrix {
            let pc = _PushConstant(colorMatrix: colorMatrix)
            self._encodeDrawCommand(shader: .colorMatrixImage,
                                    stencil: .ignore,
                                    vertices: vertices,
                                    indices: nil,
                                    texture: texture,
                                    blendState: blendState,
                                    pushConstantData: pc,
                                    encoder: encoder)
        } else {
            self._encodeDrawCommand(shader: .image,
                                    stencil: .ignore,
                                    vertices: vertices,
                                    indices: nil,
                                    texture: texture,
                                    blendState: blendState,
                                    pushConstantData: nil,
                                    encoder: encoder)
        }
        encoder.endEncoding()
    }

    func _resolveMaskTexture(_ texture1: Texture, _ texture2: Texture, opacity: Double, inverse: Bool) -> Texture? {
        fatalError("Not implemented")
    }

    func _encodeFillCommand(with shading: GraphicsContext.Shading,
                            stencil: _Stencil,
                            blendState: BlendState = .alphaBlend,
                            encoder: RenderCommandEncoder) {

        if shading.properties.isEmpty { return }

        var vertices: [_Vertex] = []
        var shader: _Shader = .vertexColor

        if let property = shading.properties.first {
            switch property {
            case let .color(c):
                shader = .vertexColor
                let makeVertex = { x, y in
                    _Vertex(position: Vector2(x, y).float2,
                            texcoord: Vector2.zero.float2,
                            color: c.dkColor.float4)
                }
                vertices = [
                    makeVertex(-1, -1), makeVertex(-1, 1), makeVertex(1, -1),
                    makeVertex(1, -1), makeVertex(-1, 1), makeVertex(1, 1)
                ]
            case let .linearGradient(gradient, startPoint, endPoint, options):
                let stops = gradient.normalized().stops
                if stops.isEmpty { return }
                let gradientVector = endPoint - startPoint
                let length = gradientVector.magnitude
                if length < .ulpOfOne {
                    return self._encodeFillCommand(with: .color(stops[0].color),
                                                   stencil: stencil,
                                                   encoder: encoder)
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

                let addGradientBox = { (x1: CGFloat, x2: CGFloat, c1: DKGame.Color, c2: DKGame.Color) in
                    let verts = [_Vertex(position: Vector2(x1, maxY).applying(gradientToViewportTransform).float2,
                                         texcoord: Vector2.zero.float2,
                                         color: c1.float4),
                                 _Vertex(position: Vector2(x1, minY).applying(gradientToViewportTransform).float2,
                                         texcoord: Vector2.zero.float2,
                                         color: c1.float4),
                                 _Vertex(position: Vector2(x2, maxY).applying(gradientToViewportTransform).float2,
                                         texcoord: Vector2.zero.float2,
                                         color: c2.float4),
                                 _Vertex(position: Vector2(x2, minY).applying(gradientToViewportTransform).float2,
                                         texcoord: Vector2.zero.float2,
                                         color: c2.float4)]
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
                                               s1.color.dkColor,
                                               s2.color.dkColor)
                            }
                        } else {
                            for i in 0..<(stops.count-1) {
                                let s1 = stops[i]
                                let s2 = stops[i+1]

                                if s1.location + pos > maxX { break }
                                if s2.location + pos < minX { continue }
                                addGradientBox(s1.location + pos,
                                               s2.location + pos,
                                               s1.color.dkColor,
                                               s2.color.dkColor)
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
                                           s1.color.dkColor,
                                           s2.color.dkColor)
                        }
                        pos += 1
                    }
                } else {
                    for i in 0..<(stops.count-1) {
                        let s1 = stops[i]
                        let s2 = stops[i+1]

                        addGradientBox(s1.location, s2.location,
                                       s1.color.dkColor, s2.color.dkColor)
                    }
                    if let first = stops.first, first.location > minX {
                        addGradientBox(minX, first.location,
                                       first.color.dkColor, first.color.dkColor)
                    }
                    if let last = stops.last, last.location < maxX {
                        addGradientBox(last.location, maxX,
                                       last.color.dkColor, last.color.dkColor)
                    }
                }
            case let .radialGradient(gradient, center, startRadius, endRadius, options):
                let stops = gradient.normalized().stops
                if stops.isEmpty { return }

                let length = (endRadius - startRadius).magnitude
                if length < .ulpOfOne {
                    if options.contains(.repeat) && !options.contains(.mirror) {
                        return self._encodeFillCommand(with:
                                .color(stops.last!.color),
                                                       stencil: stencil,
                                                       encoder: encoder)
                    } else {
                        return self._encodeFillCommand(with:
                                .color(stops.first!.color),
                                                       stencil: stencil,
                                                       encoder: encoder)
                    }
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
                        c2 = .lerp(c1, c2, (x2 - scale)/(x2 - x1))
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
                                                    color: colors[i].dkColor.float4))
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
            case let .conicGradient(gradient, center, angle, _):
                let gradient = gradient.normalized()
                if gradient.stops.isEmpty { return }
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
                                            color: color1.dkColor.float4))
                    vertices.append(_Vertex(position: p0.float2,
                                            texcoord: texCoord,
                                            color: color1.dkColor.float4))
                    vertices.append(_Vertex(position: p1.float2,
                                            texcoord: texCoord,
                                            color: color2.dkColor.float4))

                    progress += step
                }
            default:
                Log.err("Not implemented yet")
                return
            }
        }

        self._encodeDrawCommand(shader: shader,
                                stencil: stencil,
                                vertices: vertices,
                                indices: nil,
                                texture: nil,
                                blendState: blendState,
                                pushConstantData: nil,
                                encoder: encoder)
    }

    func _encodeDrawCommand(shader: _Shader,
                            stencil: _Stencil,
                            vertices: [_Vertex],
                            indices: [UInt32]?,
                            texture: Texture?,
                            blendState: BlendState,
                            pushConstantData: _PushConstant?,
                            encoder: RenderCommandEncoder) {
        assert(shader != .stencil) // .stencil uses a different vertex format.

        if shader == .colorMatrixImage {
            assert(pushConstantData != nil)
        }

        if vertices.isEmpty { return }
        if let indices, indices.isEmpty { return }

        let queue = self.commandBuffer.commandQueue
        guard let pipeline = GraphicsPipelineStates.sharedInstance(commandQueue: queue) else {
            Log.err("GraphicsContext error: pipeline failed.")
            return
        }
        guard let renderState = pipeline.renderState(
            shader: shader,
            colorFormat: backBuffer.pixelFormat,
            depthFormat: stencil == .ignore ? .invalid : stencilBuffer.pixelFormat,
            blendState: blendState) else {
            Log.err("GraphicsContext error: pipeline.renderState failed.")
            return
        }
        guard let depthState = pipeline.depthStencilState(stencil) else {
            Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
            return
        }
        guard let vertexBuffer = self._makeBuffer(vertices) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return
        }

        encoder.setRenderPipelineState(renderState)
        encoder.setDepthStencilState(depthState)
        if let texture {
            pipeline.defaultBindingSet2.setTexture(self.maskTexture, binding: 0)
            pipeline.defaultBindingSet2.setTexture(texture, binding: 1)
            pipeline.defaultBindingSet2.setSamplerState(pipeline.defaultSampler, binding: 0)
            pipeline.defaultBindingSet2.setSamplerState(pipeline.defaultSampler, binding: 1)
            encoder.setResource(pipeline.defaultBindingSet2, atIndex: 0)
        } else {
            pipeline.defaultBindingSet1.setTexture(self.maskTexture, binding: 0)
            pipeline.defaultBindingSet1.setSamplerState(pipeline.defaultSampler, binding: 0)
            encoder.setResource(pipeline.defaultBindingSet1, atIndex: 0)
        }
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        encoder.setStencilReferenceValue(0)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        if shader == .colorMatrixImage {
            let pushConstantData = pushConstantData ?? _PushConstant()
            withUnsafeBytes(of: pushConstantData) {
                encoder.pushConstant(stages: .fragment, offset: 0, data: $0)
            }
        }

        if let indices {
            guard let indexBuffer = self._makeBuffer(indices) else {
                Log.err("GraphicsContext error: _makeBuffer failed.")
                return
            }
            encoder.drawIndexed(indexCount: indices.count,
                                indexType: .uint32,
                                indexBuffer: indexBuffer,
                                indexBufferOffset: 0,
                                instanceCount: 1,
                                baseVertex: 0,
                                baseInstance: 0)
        } else {
            encoder.draw(vertexStart: 0,
                         vertexCount: vertices.count,
                         instanceCount: 1,
                         baseInstance: 0)
        }
    }

    func _makeBuffer<T>(_ data: [T]) -> Buffer? {
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
