//
//  File: GraphicsPipeline.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

// MARK: - SPIR-V Shaders
// glslc {input-file} -o {output-file} -Os --target-env=vulkan1.2
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

private let fsGLSL = """
    /* fragment-shader: vertex color */
    #version 450

    layout (push_constant) uniform Constants {
        float maskLinear;
        float maskConstant;
        float colorMatrixR[5];
        float colorMatrixG[5];
        float colorMatrixB[5];
        float colorMatrixA[5];
    } pc;

    layout (binding=0) uniform sampler2D maskImage;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main(void) {
        if ((texture(maskImage, maskUV).r * pc.maskLinear + pc.maskConstant) <= 0)
            discard;
        vec4 cmR = vec4(pc.colorMatrixR[0], pc.colorMatrixR[1], pc.colorMatrixR[2], pc.colorMatrixR[3]);
        vec4 cmG = vec4(pc.colorMatrixG[0], pc.colorMatrixG[1], pc.colorMatrixG[2], pc.colorMatrixG[3]);
        vec4 cmB = vec4(pc.colorMatrixB[0], pc.colorMatrixB[1], pc.colorMatrixB[2], pc.colorMatrixB[3]);
        vec4 cmA = vec4(pc.colorMatrixA[0], pc.colorMatrixA[1], pc.colorMatrixA[2], pc.colorMatrixA[3]);

        float r = dot(color, cmR) + pc.colorMatrixR[4];
        float g = dot(color, cmG) + pc.colorMatrixG[4];
        float b = dot(color, cmB) + pc.colorMatrixB[4];
        float a = dot(color, cmA) + pc.colorMatrixA[4];
        outFragColor = vec4(r, g, b, a);
    }
    """

private let fsSpvCEB64 = """
    XQAAAAQwCQAAAAAAAAABgJdesnC95qjyNRP3b3W1wTM2BjHpoMwr6OqAkVzhyMYm25asbk\
    ckiEeMA4h9Gch5k9Liip1euGYLpx+XrZf81Fer63rg9Uo2ePP7TCWzYwudvprwuoN+z4Bq\
    jv6COKye8CMrSguozbHc1g/nneOnP0DUgz2G9XwxikXvHdrQQ0LBA4dEDwXSf/jC0cy1ma\
    R4CH3EDDqzZJ4AlnY6zii8cUAjwyqmjG3GfC9pIU/YtPzHIp7FY773jcHOdkEWiOI9Tz37\
    9bZunMPRCFn8onhSPaQ3Y1cOKq6WQyZStF6DKy+FgQzMuh8scg2zWlTRS5rl2c+znZEadD\
    zGuRl0MAIoKgHfQd8cc+bgQ0DswxNrUZZR+rkIH7sntGrN5+pbe3dyGXLMRf7j5yewylvo\
    FEbYSU21Ur+xvJfT3akNzAd6TeN2USBwKX8TodyE3QDE/+L0rz5opl/i8ZyPASJKpl9mez\
    loFY1VADWLlv3Vp2RXlIZjn/HGd0X798DGlHXWgRdaObSTG++k/977FPByDUmVEduiiXsJ\
    UZlz0RA/7pNACoz+qO5rTpfUun/pSCQ62/qYpQIUz1klFfuh2GkbAB9GwMwuHJ3wS42B4+\
    HjIz9iN7jb4oXCe1FXoTTmOqIwPv039/uocoCdV2GvsepSxAjiT0+njK3eAA5oNsjTvcHT\
    YetBeWIHoM+vX/ffmQiZUeJcNV4ccfC6ya+ylxlKFeRd7LZGH91h/S4b9OQ84UDRaY+ZTg\
    A=
    """

private let fsTextureGLSL = """
    /* fragment-shader: vertex color, uniform texture */
    #version 450

    layout (push_constant) uniform Constants {
        float maskLinear;
        float maskConstant;
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
        if ((texture(maskImage, maskUV).r * pc.maskLinear + pc.maskConstant) <= 0)
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

private let fsTextureSpvCEB64 = """
    XQAAAATQCQAAAAAAAAABgJdesnC95qjyNRP3v8W1wTM2BjHpoMwr6OqAkVzhyMYm25asbk\
    ckiEeMA4h9Gch5lXZ1/1xg8Mg+JKYBQqOqMgfbtxEa9gpBfcUzoORjKvVe0HwhWRcFAILe\
    bxgqnQQbHWwJ6m1n0W/C0a9EuscdOmzfl9rVso0qROBmPhXAzTJqd9B+ecKGATaer6OeRp\
    OjEhzADyUPtYRoP/SJkf3RfpJTFGf+gBY1UCZNBUhOP+33vN7KRJQRHRctxTLpRj0GKmEQ\
    L8WHm+HZah/am1C/twkpnoA9rGC9qCKdaRlZOAk8xYbZu4g3PLs17krFfVyzpD6TpGxuRK\
    OZ8Us/2GiMb5hyebAXINqTplsrTC6EzCb+uR04Xz32p02dRLZEzt0ef19DXKgGNcW20S4l\
    CfajHhNM3AXyIl+hEiAR+bs/aJGIOSf24z1DOsXwtqauD6Lbg1un9SQjw41XHbnRVg4hVH\
    FTxZwHLZyHweQOaOdeXFF2RCpHbJyv1MxzFJl2ilTmi951rNZS/Epp4nKxzQNy7IoDyume\
    Yz+rtXkvzcGCW7OxRJArkS0/L1meD6A7dp7Lhj0OB9bpup/lG+chEpgLVRrcgfD8eyXeL/\
    rE9iUlnOA+xkC6fT+hUnzFpe8PxdIS6hS326FwyK57K5qu5LMmbaKeOz9L4rySgfg+Wmkh\
    7CibvsoX4XR9WGSpMLZTN5sqhlepHquzk5ONgJj5/N11tQHFFcaK/A5TCFgOTSMIKpaGeJ\
    oR8JLikmlTSHXsSsvYkMH6Q2Ph9bt7e4RW/BnpzGkA
    """

private let fsAlphaTextureGLSL = """
    /* fragment-shader: vertex color, uniform texture alpha (r8) */
    #version 450

    layout (push_constant) uniform Constants {
        float maskLinear;
        float maskConstant;
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

    void main(void) {
        if ((texture(maskImage, maskUV).r * pc.maskLinear + pc.maskConstant) <= 0)
            discard;
        vec4 fragColor = vec4(color.rgb, texture(image, texUV).r * color.a);
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

private let fsAlphaTextureSpvCEB64 = """
    XQAAAASACgAAAAAAAAABgJdesnC95qjyNRP4LjR13ShGBjHpoMwr6OqAkVzhyMYm25asbk\
    ckiEeMA4h9Gch5lXZ1/1xg8Mg+JKYBQqOqMXLvaDa2VapCJlXKQRvkfsh+6rBb9AFK7tUY\
    Ai1iuBSo9Ajzu0M6+kTurMvtSygHZpcS6ybs4HaeTonW+8EkgeSoWp0KEICMv0LJ2G2r3m\
    OElTJ5sSl6V22G5M1+u+nqxzdxVwHc4YLK7BCfItj8pYPg3CUNVSpfD99MPPOgmS/d+8g4\
    unXefV6xrGUAPoI0I9xmU/wSqz2lUvVMvP0PWooBrMbKkWAONR5nAhdH6CDb1ZuGwkMW1s\
    eAkaSxmKT3hi0Wk4SEiEDy3Ugp2CCyeTo0t5Z7i9HEtqY34FpD4MhgOzLev53j3MgCe+so\
    K2Dh8wkECOUQx6EqD+RvWl9Vd8MSUOyyC7uZ2YIkOfqD4y/J8VMhs3RXDr0vlQdxCnaYe8\
    XFdlCEbDaW/70ifFI2qhTU8dfWiNSAc+Pya2mc1SZOJ49W8aER8c6uda5MyLMesM5ZQD1t\
    h97tYfkMMpbpf7Bv07ng+wXlOwGtAGXS+MiEciLVLrZ3WVeyxKbxBrsWINRYvGAHPDAJLH\
    P+ft80UnseiFASNR1kZRlbwkg/hNy5BFqZHpAGkRs8xxaSnmGRSSntYsXchaP6eni1z2MW\
    2jkSMfHmXVkFP1Y8zGrQq8MS3UFDRYeSeOkcJ/PSU7rA2kJYzyCTt6BZVWyC3N9o/qHLIN\
    Ohthd32UBa1NR++qTANMBvXKnfUWFqkumRjze30mhlRdWZeXPuy4kdF3dh6eJ45hdDjQPp\
    ApjhSqpMhdAaaK84IBOFlQA=
    """

private let fsResolveMaskGLSL = """
    /* fragment-shader: vertex color, uniform texture */
    #version 450

    layout (push_constant) uniform Constants {
        float maskLinear;
        float maskConstant;
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
        if ((texture(maskImage, maskUV).r * pc.maskLinear + pc.maskConstant) <= 0)
            discard;

        vec4 fragColor = texture(image, texUV) * color;
        vec4 cmA = vec4(pc.colorMatrixA[0], pc.colorMatrixA[1], pc.colorMatrixA[2], pc.colorMatrixA[3]);
        float a = dot(fragColor, cmA) + pc.colorMatrixA[4];
        /* output target should be r8unorm */
        outFragColor = vec4(a, a, a, a);
    }
    """

private let fsResolveMaskSpvCEB64 = """
    XQAAAAQEBgAAAAAAAAABgJdesnC95qjyNRP1TqkuUYBtYiFNRo5NmeAko5dxbKw6cfMUDv\
    m077Y8SFv99HGiKQgiCpqph1AP2+nGsMDjlco1L4uZXOVIpxqur90t6Hv0XWK+2+TQVq4p\
    VYetcae9cIzKya/aZZI8+awRrzXSaOxNfmvMrdjT48hm21MhvLZwTR1nY25jPg2RrVXL1r\
    bCwkCd8PdIrl8q3+ToxDf9slX7dryiKkojIfgpzaSe6rH7nhxKgHg3MN73fk0TLntycEaH\
    xpNU2Wx8sD9M7wW2HYrU773qveIlmyigmCdOzsCfHO5HeugrD5QdlOpw7idSzq8AIs2YLR\
    fCwoGkifOJlKaTLe1T7+DNTkeeCw1N9Bsce21iAxGTWEybgElOpeCsyZ6nP+gZ9Z/7b8i1\
    PuIemGepaWhiTRdCr5r4N9tLr5AfVasFbMwQmWwkPeqYH/a49Rm0dWqGDTYDbj8oTdQn4h\
    G/vfLqzohxUePf/pkPyQ42NhVTy5e+D3HPOnub2WA5ieRAt3nufgLzoePA1L65AMihj6rQ\
    omGyUrm2cDB1RIleDfkR5/DN0MQEb9E1o36eLloSiEMK1a9wQua90bglTgXqWzhcr3k/dj\
    rHs+mbDOkq/i4=
    """


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
    case color          // vertex color
    case image          // texture with tint color
    case alphaTexture   // for glyph (single channel texture)
    case resolveMask    // merge two masks (a8, r8) to render target (r8)
}

enum _Stencil {
    case generateWindingNumber
    case nonZero        // filled using the non-zero rule
    case even           // even-odd winding rule
    case zero           // zero stencil (inverse of non-zero rule)
    case odd            // odd winding (inverse of even-odd rule)
    case ignore         // don't read stencil
}

struct _Vertex {
    var position: Float2
    var texcoord: Float2
    var color: Float4
}

struct _PushConstant {
    var maskLinear: Float32 = 1.0
    var maskConstant: Float32 = 0.0
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

            guard let fsFunction = loadShader("fs-defalut", fsSpvCEB64)
            else { break }

            guard let fsTextureFunction = loadShader("fs-texture", fsTextureSpvCEB64)
            else { break }

            guard let fsAlphaTextureFunction = loadShader("fs-alpha-texture", fsAlphaTextureSpvCEB64)
            else { break }

            guard let fsResolveMaskFunction = loadShader("fs-resolve-mask", fsResolveMaskSpvCEB64)
            else { break }

            var shaderFunctions: [_Shader: ShaderFunctions] = [:]
            shaderFunctions[.stencil] = ShaderFunctions(
                vertexFunction: vsStencilFunction, fragmentFunction: nil)
            shaderFunctions[.color] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsFunction)
            shaderFunctions[.image] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsTextureFunction)
            shaderFunctions[.alphaTexture] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsAlphaTextureFunction)
            shaderFunctions[.resolveMask] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsResolveMaskFunction)

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

    func drawLayer(in frame: CGRect, content: (inout GraphicsContext, CGSize) throws -> Void) rethrows {
        if var context = self.makeRegionLayerContext(frame) {
            do {
                try content(&context, context.contentScale)
                let texture = context.backBuffer
                self._draw(texture: texture,
                           in: frame,
                           transform: .identity,
                           textureFrame: CGRect(x: 0, y: 0,
                                                width: texture.width,
                                                height: texture.height),
                           textureTransform: .identity,
                           blendMode: context.blendMode,
                           color: .white)
            } catch {
                Log.err("GraphicsContext error: \(error)")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    func _draw(texture: Texture,
               in: CGRect,
               transform: CGAffineTransform,
               textureFrame: CGRect,
               textureTransform: CGAffineTransform,
               blendMode: BlendMode,
               color: DKGame.Color) {
        let makeVertex = { x, y, u, v in
            _Vertex(position: Vector2(x, y).applying(transform).float2,
                    texcoord: Vector2(u, v).applying(textureTransform).float2,
                    color: color.float4)
        }
        let uvMinX = textureFrame.minX / CGFloat(texture.width)
        let uvMaxX = textureFrame.maxX / CGFloat(texture.width)
        let uvMinY = textureFrame.minY / CGFloat(texture.height)
        let uvMaxY = textureFrame.maxY / CGFloat(texture.height)

        let vertices: [_Vertex] = [
            makeVertex(-1, -1, uvMinX, uvMaxY),
            makeVertex(-1,  1, uvMinX, uvMinY),
            makeVertex( 1, -1, uvMaxX, uvMaxY),
            makeVertex( 1, -1, uvMaxX, uvMaxY),
            makeVertex(-1,  1, uvMinX, uvMinY),
            makeVertex( 1,  1, uvMaxX, uvMinY)
        ]
        let renderPass = RenderPassDescriptor(
            colorAttachments: [
                RenderPassColorAttachmentDescriptor(
                    renderTarget: backBuffer,
                    loadAction: .load,
                    storeAction: .store)
            ])
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            Log.err("GraphicsContext error: makeRenderCommandEncoder failed.")
            return
        }

        let pc = _PushConstant()
        self._encodeDrawCommand(shader: .image,
                                stencil: .ignore,
                                vertices: vertices,
                                indices: nil,
                                texture: texture,
                                blendState: .defaultAlpha,
                                pushConstantData: pc,
                                encoder: encoder)
        encoder.endEncoding()
    }

    func _resolveMaskTexture(_ texture1: Texture, _ texture2: Texture, opacity: Double, inverse: Bool) -> Texture? {
        fatalError("Not implemented")
    }

    @discardableResult
    func _drawPathStrokeWithStencil(_ path: Path,
                                    style: StrokeStyle,
                                    backBuffer: Texture,
                                    drawShading: (_: RenderCommandEncoder) -> Bool
    ) -> Bool {
        if path.isEmpty { return false }
        if style.lineWidth < .ulpOfOne { return false }

        assert(backBuffer.dimensions == stencilBuffer.dimensions)

        let dash = style.dash.map { $0.magnitude }
        if dash.isEmpty == false && dash.count % 2 == 0 {
            let dashes = stride(from: 0, to: dash.count, by: 2).map { dash[$0] }
                .reduce(0, +)
            let gaps = stride(from: 1, to: dash.count, by: 2).map { dash[$0] }
                .reduce(0, +)
            if gaps > 0 && dashes == 0 { return false }
        }
        let dashPatternLength = dash.reduce(0, +)
        let lineWidth = style.lineWidth

        var vertexData: [Float2] = []

        var dashOffset = style.dashPhase

        let nextDashPattern = { (t: CGFloat, visible: inout Bool) -> CGFloat in
            assert(dashPatternLength > .ulpOfOne)
            let r = t.truncatingRemainder(dividingBy: dashPatternLength)
            assert(r < dashPatternLength)
            var f: CGFloat = 0
            for d in dash {
                f = f + d
                if f > t {
                    visible = !visible
                    if d < .ulpOfOne {
                        continue
                    }
                    return f - t
                }
            }
            return 0
        }

        let transform = self.transform.concatenating(self.viewTransform)

        let addStrokeCap = { (pt: CGPoint, s: CGFloat) in
        }
        let addStrokeLine = { (p0: CGPoint, p1: CGPoint) in
            let d = p1 - p0
            let length = d.magnitude
            if length < .ulpOfOne { return }
            let dir = d.normalized()
            if dashPatternLength > 0 {

            } else {
                let trans = CGAffineTransform(a: length * dir.x,
                                              b: length * dir.y,
                                              c: -lineWidth * dir.y,
                                              d: lineWidth * dir.x,
                                              tx: p0.x, ty: p0.y)
                    .concatenating(transform)

                let box = [CGPoint(x: 0, y: -0.5), CGPoint(x: 1, y: -0.5),
                           CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)].map {
                    Vector2($0.applying(trans))
                }
                vertexData.append(contentsOf: [
                    box[2].float2, box[0].float2, box[3].float2,
                    box[3].float2, box[0].float2, box[1].float2])
            }
            dashOffset += length
        }
        let addStrokeJoin = { (pt: CGPoint, s0: CGFloat, s1: CGFloat) in
        }

        let slope = { (pt0: CGPoint, pt1: CGPoint) -> CGFloat in
            assert((pt1 - pt0).magnitudeSquared > .zero)
            let d = (pt1 - pt0).normalized()
            return d.y / d.x
        }

        var initialPoint: CGPoint? = nil
        var currentPoint: CGPoint? = nil
        var initialSlope: CGFloat? = nil
        var currentSlope: CGFloat? = nil
        path.forEach { element in
            switch element {
            case .move(let to):
                if let p = initialPoint, let s = initialSlope {
                    addStrokeCap(p, s)
                }
                if let p = currentPoint, let s = currentSlope {
                    addStrokeCap(p, s)
                }
                initialPoint = to
                currentPoint = to
                initialSlope = nil
                currentSlope = nil
            case .line(let p1):
                if let p0 = currentPoint {
                    let s1 = slope(p0, p1)
                    if let s0 = currentSlope {
                        addStrokeJoin(p0, s0, s1)
                    }
                    addStrokeLine(p0, p1)
                    currentSlope = s1
                    initialSlope = initialSlope ?? currentSlope
                }
                currentPoint = p1
            case .quadCurve(let p2, let p1):
                if let p0 = currentPoint {
                    let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                    let length = curve.approximateLength()
                    if length > .ulpOfOne {
                        let step = 1.0 / curve.approximateLength()
                        var t = step
                        var pt0 = p0
                        while t < 1.0 {
                            let pt1 = curve.interpolate(t)
                            addStrokeLine(pt0, pt1)
                            pt0 = pt1
                            t += step
                        }
                        currentSlope = slope(p1, p2)
                        initialSlope = initialSlope ?? currentSlope
                    }
                }
                currentPoint = p2
            case .curve(let p3, let p1, let p2):
                if let p0 = currentPoint {
                    let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                    let length = curve.approximateLength()
                    if length > .ulpOfOne {
                        let step = 1.0 / curve.approximateLength()
                        var t = step
                        var pt0 = p0
                        while t < 1.0 {
                            let pt1 = curve.interpolate(t)
                            addStrokeLine(pt0, pt1)
                            pt0 = pt1
                            t += step
                        }
                        currentSlope = slope(p2, p3)
                        initialSlope = initialSlope ?? currentSlope
                    }
                }
                currentPoint = p3
            case .closeSubpath:
                if let p0 = currentPoint, let p1 = initialPoint {
                    let s0 = slope(p0, p1)
                    if let s1 = initialSlope {
                        addStrokeJoin(p1, s0, s1)
                    }
                    addStrokeLine(p0, p1)
                }
                currentPoint = initialPoint
                initialSlope = nil
                currentSlope = nil
            }
        }

        if vertexData.count < 3 { return false }

        let queue = self.commandBuffer.commandQueue
        guard let pipeline = GraphicsPipelineStates.sharedInstance(commandQueue: queue) else {
            Log.err("GraphicsContext error: pipeline failed.")
            return false
        }
        guard let vertexBuffer = self._makeBuffer(vertexData) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }

        // pipeline states for generate polgon winding numbers
        guard let pipelineState = pipeline.renderState(
            shader: .stencil,
            colorFormat: backBuffer.pixelFormat,
            depthFormat: stencilBuffer.pixelFormat,
            blendState: .defaultOpaque) else {
            Log.err("GraphicsContext error: pipeline.renderState failed.")
            return false
        }
        guard let depthState = pipeline.depthStencilState(.generateWindingNumber) else {
            Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
            return false
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
            Log.err("GraphicsContext error: makeRenderCommandEncoder failed.")
            return false
        }

        // pass1: Generate polygon winding numbers to stencil buffer
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)

        encoder.setCullMode(.none)
        encoder.setFrontFacing(.clockwise)
        encoder.setStencilReferenceValue(0)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.draw(vertexStart: 0,
                     vertexCount: vertexData.count,
                     instanceCount: 1,
                     baseInstance: 0)

         // pass2: draw only pixels that pass the stencil test
        if drawShading(encoder) {
            encoder.endEncoding()
            return true
        } else {
            Log.err("GraphicsContext error: draw callback failed.")
        }
        return false
    }

    @discardableResult
    func _drawPathFillWithStencil(_ path: Path,
                                  backBuffer: Texture,
                                  drawShading: (_: RenderCommandEncoder) -> Bool
    ) -> Bool{
        if path.isEmpty { return false }

        assert(backBuffer.dimensions == stencilBuffer.dimensions)

        struct PolygonElement {
            var vertices: [CGPoint] = []
        }
        var polygons: [PolygonElement] = []
        if true {
            var initialPoint: CGPoint? = nil
            var currentPoint: CGPoint? = nil
            var polygon = PolygonElement()
            path.forEach { element in
                // make polygon array from path
                switch element {
                case .move(let to):
                    polygons.append(polygon)
                    polygon = PolygonElement()
                    initialPoint = to
                    currentPoint = to
                case .line(let p1):
                    if let p0 = currentPoint {
                        if polygon.vertices.isEmpty {
                            polygon.vertices.append(p0)
                        }
                        polygon.vertices.append(p1)
                    }
                    currentPoint = p1
                case .quadCurve(let p2, let p1):
                    if let p0 = currentPoint {
                        let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                        let length = curve.approximateLength()
                        if length > .ulpOfOne {
                            let step = 1.0 / curve.approximateLength()
                            var t = step
                            while t < 1.0 {
                                let pt = curve.interpolate(t)
                                polygon.vertices.append(pt)
                                t += step
                            }
                            polygon.vertices.append(p2)
                        }
                    }
                    currentPoint = p2
                case .curve(let p3, let p1, let p2):
                    if let p0 = currentPoint {
                        let curve = CubicBezier(p0: p0, p1: p1, p2: p2, p3: p3)
                        let length = curve.approximateLength()
                        if length > .ulpOfOne {
                            let step = 1.0 / curve.approximateLength()
                            var t = step
                            while t < 1.0 {
                                let pt = curve.interpolate(t)
                                polygon.vertices.append(pt)
                                t += step
                            }
                            polygon.vertices.append(p3)
                        }
                    }
                    currentPoint = p3
                case .closeSubpath:
                    polygons.append(polygon)
                    polygon = PolygonElement()
                    currentPoint = initialPoint
                }
            }
            polygons.append(polygon)
        }

        let transform = self.transform.concatenating(self.viewTransform)
        var numVertices = 0
        polygons.forEach {
            numVertices += $0.vertices.count + 2
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

            for i in (baseIndex + 1)..<pivotIndex {
                indexData.append(i - 1)
                indexData.append(i)
                indexData.append(pivotIndex)
            }
            indexData.append(pivotIndex - 1)
            indexData.append(baseIndex)
            indexData.append(pivotIndex)
        }
        if vertexData.count < 3 { return false }
        if indexData.count < 3 { return false }

        let queue = self.commandBuffer.commandQueue
        guard let pipeline = GraphicsPipelineStates.sharedInstance(commandQueue: queue) else {
            Log.err("GraphicsContext error: pipeline failed.")
            return false
        }
        guard let vertexBuffer = self._makeBuffer(vertexData) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }
        guard let indexBuffer = self._makeBuffer(indexData) else {
            Log.err("GraphicsContext error: _makeBuffer failed.")
            return false
        }

        // pipeline states for generate polgon winding numbers
        guard let pipelineState = pipeline.renderState(
            shader: .stencil,
            colorFormat: backBuffer.pixelFormat,
            depthFormat: stencilBuffer.pixelFormat,
            blendState: .defaultOpaque) else {
            Log.err("GraphicsContext error: pipeline.renderState failed.")
            return false
        }
        guard let depthState = pipeline.depthStencilState(.generateWindingNumber) else {
            Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
            return false
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
            Log.err("GraphicsContext error: makeRenderCommandEncoder failed.")
            return false
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
        if drawShading(encoder) {
            encoder.endEncoding()
            return true
        } else {
            Log.err("GraphicsContext error: draw callback failed.")
        }
        return false
    }

    func _encodeFillCommand(with shading: GraphicsContext.Shading,
                            stencil: _Stencil,
                            encoder: RenderCommandEncoder) {

        if shading.properties.isEmpty { return }

        var vertices: [_Vertex] = []
        var shader: _Shader = .color

        if let property = shading.properties.first {
            switch property {
            case let .color(c):
                shader = .color
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

        let pc = _PushConstant()
        self._encodeDrawCommand(shader: shader,
                                stencil: stencil,
                                vertices: vertices,
                                indices: nil,
                                texture: nil,
                                blendState: .defaultAlpha,
                                pushConstantData: pc,
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

        if let pushConstantData {
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
