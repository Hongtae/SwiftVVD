//
//  File: GraphicsPipeline.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame


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


private enum _Shader {
    case stencil        // fill stencil, no fragment function
    case color          // vertex color
    case image          // texture with tint color
    case alphaTexture   // for glyph (single channel texture)
    case resolveMask    // merge two masks (a8, r8) to render target (r8)
}

private enum _Stencil {
    case generateWindingNumber
    case nonZero        // filled using the non-zero rule
    case even           // even-odd winding rule
    case zero           // zero stencil (inverse of non-zero rule)
    case odd            // odd winding (inverse of even-odd rule)
    case ignore         // don't read stencil
}

private struct _Vertex {
    var position: Float2
    var texcoord: Float2
    var color: Float4
}

private struct _PushConstant {
    var maskLinear: Float32 = 1.0
    var maskConstant: Float32 = 0.0
    var colorMatrix: ColorMatrix = .init()
    static let identity = _PushConstant()
}

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

    fileprivate struct RenderState: Hashable {
        let shader: _Shader
        let colorFormat: PixelFormat
        let depthFormat: PixelFormat
        let blendState: BlendState
    }

    private var pipelineStates: [RenderState: RenderPipelineState] = [:]
    private var depthStencilStates: [_Stencil: DepthStencilState] = [:]

    fileprivate func renderState(_ rs: RenderState) -> RenderPipelineState? {
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
            Log.debug("PipelineState (_Shader.\(rs.shader)) Reflection: \(reflection)")
            pipelineStates[rs] = state
            return pipelineStates[rs]
        }
        return nil
    }

    fileprivate func depthStencilState(_ ds: _Stencil) -> DepthStencilState? {
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
        self.pipelineStates = [:]
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
                Log.err("\(Self.self).\(#function): makeSampler failed.")
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
        if let queue = deviceContext.renderQueue() {
            if let state = GraphicsPipelineStates.sharedInstance(commandQueue: queue) {
                deviceContext.cachedDeviceResources["DKGUI.GraphicsPipelineStates"] = state
                return true
            }
        }
        return false
    }

    public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        if var context = self.makeLayerContext() {
            do {
                try content(&context)
                let offset = -context.contentBounds.origin
                let scale = context.contentBounds.size
                self._draw(texture: context.backBuffer,
                           in: CGRect(origin: offset, size: scale),
                           color: .white)
            } catch {
                Log.err("GraphicsContext error: \(error)")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    func drawRegionLayer(_ frame: CGRect, content: (inout GraphicsContext) throws -> Void) rethrows {
        if var context = self.makeRegionLayerContext(frame) {
            do {
                try content(&context)
                self._draw(texture: context.backBuffer,
                           in: frame,
                           color: .white)
            } catch {
                Log.err("GraphicsContext error: \(error)")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    func _draw(texture: Texture, in: CGRect, color: DKGame.Color) {
        fatalError("Not implemented")
    }

    func _resolveMaskTexture(_ texture1: Texture, _ texture2: Texture, opacity: Double, inverse: Bool) -> Texture? {
        fatalError("Not implemented")
    }

    @discardableResult
    func _fillStencil(_ path: Path, backBuffer: Texture, draw: (_: RenderCommandEncoder) -> Bool) -> Bool{
        if path.isEmpty { return false }

        assert(backBuffer.dimensions == stencilBuffer.dimensions)

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
                        if polygon.vertices.last != p0 {
                            polygon.vertices.append(p0)
                        }
                        polygon.vertices.append(p1)
                    }
                    currentPoint = p1
                case .quadCurve(let p2, let p1):
                    if let p0 = currentPoint {
                        if polygon.vertices.last != p0 {
                            polygon.vertices.append(p0)
                        }
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
                        if polygon.vertices.last != p0 {
                            polygon.vertices.append(p0)
                        }
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
        if vertexData.count < 3 { return false }
        if indexData.count < 3 { return false }

        let queue = self.commandBuffer.commandQueue
        guard let pipeline = GraphicsPipelineStates.sharedInstance(commandQueue: queue) else {
            Log.err("GraphicsContext error: pipeline failed.")
            return false
        }
        guard let vertexBuffer = pipeline.makeBuffer(vertexData) else {
            Log.err("GraphicsContext error: pipeline.makeBuffer failed.")
            return false
        }
        guard let indexBuffer = pipeline.makeBuffer(indexData) else {
            Log.err("GraphicsContext error: pipeline.makeBuffer failed.")
            return false
        }

        // pipeline states for generate polgon winding numbers
        guard let pipelineState = pipeline.renderState(
            .init(shader: .stencil,
                  colorFormat: backBuffer.pixelFormat,
                  depthFormat: stencilBuffer.pixelFormat,
                  blendState: .defaultOpaque)) else {
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
        if draw(encoder) {
            encoder.endEncoding()
            return true
        } else {
            Log.err("GraphicsContext error: draw callback failed.")
        }
        return false
    }

    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        self._fillStencil(path, backBuffer: self.backBuffer) { encoder in
            let queue = self.commandBuffer.commandQueue
            guard let pipeline = GraphicsPipelineStates.sharedInstance(commandQueue: queue) else {
                Log.err("GraphicsContext error: pipeline failed.")
                return false
            }

            // pipeline states for polygon fill
            guard let pipelineState = pipeline.renderState(
                .init(shader: .color,
                      colorFormat: backBuffer.pixelFormat,
                      depthFormat: stencilBuffer.pixelFormat,
                      blendState: .defaultAlpha)) else {
                Log.err("GraphicsContext error: pipeline.renderState failed.")
                return false
            }
            let depthState: DepthStencilState?
            if style.isEOFilled {
                depthState = pipeline.depthStencilState(.even)
            } else {
                depthState = pipeline.depthStencilState(.nonZero)
            }
            guard let depthState else {
                Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
                return false
            }

            let makeVertex = { x, y in
                _Vertex(position: Vector2(x, y).float2,
                        texcoord: Vector2.zero.float2,
                        color: DKGame.Color.red.float4)
            }
            let rectVertices: [_Vertex] = [
                makeVertex(-1, -1), makeVertex(-1, 1), makeVertex(1, -1),
                makeVertex(1, -1), makeVertex(-1, 1), makeVertex(1, 1)
            ]

            guard let vertexBuffer = pipeline.makeBuffer(rectVertices) else {
                Log.err("GraphicsContext error: pipeline.makeBuffer() failed.")
                return false
            }

            pipeline.defaultBindingSet1.setTexture(self.maskTexture, binding: 0)
            pipeline.defaultBindingSet1.setSamplerState(pipeline.defaultSampler, binding: 0)

            encoder.setRenderPipelineState(pipelineState)
            encoder.setDepthStencilState(depthState)
            encoder.setResource(pipeline.defaultBindingSet1, atIndex: 0)
            encoder.setCullMode(.none)
            encoder.setFrontFacing(.clockwise)
            encoder.setStencilReferenceValue(0)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

            let pc = _PushConstant()
            withUnsafeBytes(of: pc) {
                encoder.pushConstant(stages: .fragment, offset: 0, data: $0)
            }

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

    public mutating func clip(to path: Path,
                              style: FillStyle = FillStyle(),
                              options: ClipOptions = ClipOptions()) {
        let resolution = self.resolution
        let width = Int(resolution.width.rounded())
        let height = Int(resolution.height.rounded())
        let device = self.commandBuffer.device
        if let maskTexture = device.makeTexture(
            descriptor: TextureDescriptor(textureType: .type2D,
                                          pixelFormat: .r8Unorm,
                                          width: width,
                                          height: height,
                                          usage: [.renderTarget, .sampled])) {
            if let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: RenderPassDescriptor(colorAttachments: [
                    RenderPassColorAttachmentDescriptor(renderTarget: backBuffer,
                                                        loadAction: .clear,
                                                        storeAction: .store,
                                                        clearColor: .white)])) {
                encoder.endEncoding()
            } else {
                Log.err("GraphicsContext warning: makeRenderCommandEncoder failed.")
            }
            // Create a new context to draw paths to a new mask texture
            let drawn = self._fillStencil(path, backBuffer: maskTexture) { encoder in
                let queue = self.commandBuffer.commandQueue
                guard let pipeline = GraphicsPipelineStates.sharedInstance(commandQueue: queue) else {
                    Log.err("GraphicsContext error: pipeline failed.")
                    return false
                }

                // pipeline states for polygon fill
                guard let pipelineState = pipeline.renderState(
                    .init(shader: .color,
                          colorFormat: backBuffer.pixelFormat,
                          depthFormat: stencilBuffer.pixelFormat,
                          blendState: .defaultAlpha)) else {
                    Log.err("GraphicsContext error: pipeline.renderState failed.")
                    return false
                }
                let depthState: DepthStencilState?
                if style.isEOFilled {
                    if options.contains(.inverse) {
                        depthState = pipeline.depthStencilState(.odd)
                    } else {
                        depthState = pipeline.depthStencilState(.even)
                    }
                } else {
                    if options.contains(.inverse) {
                        depthState = pipeline.depthStencilState(.zero)
                    }
                    else {
                        depthState = pipeline.depthStencilState(.nonZero)
                    }
                }
                guard let depthState else {
                    Log.err("GraphicsContext error: pipeline.depthStencilState failed.")
                    return false
                }

                let makeVertex = { x, y in
                    _Vertex(position: Vector2(x, y).float2,
                            texcoord: Vector2.zero.float2,
                            color: DKGame.Color.white.float4)
                }
                let rectVertices: [_Vertex] = [
                    makeVertex(-1, -1), makeVertex(-1, 1), makeVertex(1, -1),
                    makeVertex(1, -1), makeVertex(-1, 1), makeVertex(1, 1)
                ]

                guard let vertexBuffer = pipeline.makeBuffer(rectVertices) else {
                    Log.err("GraphicsContext error: pipeline.makeBuffer() failed.")
                    return false
                }

                // use current mask texture!
                pipeline.defaultBindingSet1.setTexture(self.maskTexture, binding: 0)
                pipeline.defaultBindingSet1.setSamplerState(pipeline.defaultSampler, binding: 0)

                encoder.setRenderPipelineState(pipelineState)
                encoder.setDepthStencilState(depthState)
                encoder.setResource(pipeline.defaultBindingSet1, atIndex: 0)
                encoder.setCullMode(.none)
                encoder.setFrontFacing(.clockwise)
                encoder.setStencilReferenceValue(0)
                encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

                let pc = _PushConstant()
                withUnsafeBytes(of: pc) {
                    encoder.pushConstant(stages: .fragment, offset: 0, data: $0)
                }

                encoder.draw(vertexStart: 0,
                             vertexCount: rectVertices.count,
                             instanceCount: 1,
                             baseInstance: 0)
                return true
            }
            if drawn {
                self.clipBoundingRect = self.clipBoundingRect.union(path.boundingBoxOfPath)
                self.maskTexture = maskTexture
            }
        } else {
            Log.err("GraphicsContext error: makeTexture failed.")
        }
    }

    public mutating func clipToLayer(opacity: Double = 1,
                                     options: ClipOptions = ClipOptions(),
                                     content: (inout GraphicsContext) throws -> Void) rethrows {
        if var context = self.makeLayerContext() {
            do {
                try content(&context)
                if let maskTexture = self._resolveMaskTexture(
                    self.maskTexture,
                    context.backBuffer,
                    opacity: opacity,
                    inverse: options.contains(.inverse)) {
                    self.maskTexture = maskTexture
                } else {
                    Log.err("GraphicsContext error: unable to resolve mask image.")
                }
            } catch {
                Log.err("GraphicsContext error: \(error)")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

}
