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
        float linear;
        float constant;
    } pc;

    layout (binding=0) uniform sampler2D maskImage;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main(void) {
        if ((texture(maskImage, maskUV).r * pc.linear + pc.constant) <= 0)
            discard;
        outFragColor = color;
    }
    """

private let fsSpvCEB64 = """
    XQAAAASkAwAAAAAAAAABgJdesnC95qjyNRPy5lq/c7gPRthELV8YDfBHNWmt93l0V6ZSk2\
    s6fW41iQ5gA3M3buNwyxVG6G3M7mn8NCxy4BegXw4XPfTOdfur0UFQsfE/do9CBAfT6FYp\
    ApdJDQy6pn4MTcQYrmVd7H7HN/8lPGZfYn/6mGRGwnvbkrLE7f7xFnIget4Mv96x7OlOMk\
    mdJjmq6dIgodCJyZq7Ir3V1b3Axq+zsAqxLa4Yh7XgEOhK4qlC4LiMFYl+ILXRX4zAyvQg\
    9kj1QTbp44H9jYG2XEc7I04mehrlhkQsLBfIUc/dIJjTsBgbmHU1z76Fb8TxTpbFlbjdyQ\
    VOGQMbcYYBDcKDQvFTREO7gtQLxvP323aVr2E+bQF3Vvbx884pYjIrjtX7vdriPoLtXJ6t\
    LWX24bHCo4XQeJWZm6O4+dtmKnvJ+CEjb3H6PuK1AA==
    """

private let fsTextureGLSL = """
    /* fragment-shader: vertex color, uniform texture */
    #version 450

    layout (push_constant) uniform Constants {
        float linear;
        float constant;
    } pc;

    layout (binding=0) uniform sampler2D maskImage;
    layout (binding=1) uniform sampler2D image;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main() {
        if ((texture(maskImage, maskUV).r * pc.linear + pc.constant) <= 0)
            discard;
        outFragColor = texture(image, texUV) * color;
    }
    """

private let fsTextureSpvCEB64 = """
    XQAAAAREBAAAAAAAAAABgJdesnC95qjyNRPzT/n7FEkN1hUbMQvIcJ3CE67M6dB2Y23RAR\
    9k2oVNOJaKtw9bEF24BbVkuOzAzXM/dJ3t1cc+fA2Rdpx4UOhzQXEsTjwj49uC58ZLPrwX\
    Zpigx+lHz8nMq6dt3xsj+qwseIjaSRNYHJTFWwArkOZ4bxzfpZOHa7yo5MlfpqytNco1fC\
    Y63iNrih9H7ByUP8Edj2hD7sl+92cJPbgz3ZYotqMc/U+TjxjOtHBYIvdCktOYZWk1aSeu\
    ttNC+KQ8/3BNEjLWtwksM0KvSJFCIKCxyTyQUYdshVfeLR2gLEU+ORPzxXLL+DBSvlS2Cl\
    4YuhWa1hWlQY2V7VVGhXODEdky1HXDimhsJYwlFABzBEI728dZGukgB34KB5PkAM1bWh33\
    jEtnTarJ+WzZtJRq/fEmdnttrK47OoA1fkLBM8vfZKyV2NLJ2hcy3Rh8rSPvviL1b60ltu\
    ysvKUy4xprew1EAA==
    """

private let fsAlphaTextureGLSL = """
    /* fragment-shader: vertex color, uniform texture alpha (r8) */
    #version 450

    layout (push_constant) uniform Constants {
        float linear;
        float constant;
    } pc;

    layout (binding=0) uniform sampler2D maskImage;
    layout (binding=1) uniform sampler2D image;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main(void) {
        if ((texture(maskImage, maskUV).r * pc.linear + pc.constant) <= 0)
            discard;
        outFragColor = vec4(color.rgb, texture(image, texUV).r * color.a);
    }
    """

private let fsAlphaTextureSpvCEB64 = """
    XQAAAAQEBQAAAAAAAAABgJdesnC95qjyNRP0DqSHSDMt2CDmdjcMiDoyZhb2n2T8l4pQf6\
    WN+e258rgjKEZeAhdTyJLzOfxsZ6OXHPSV2iIhV3tLxKZJuR+7ZB0KbciAQpZ2oatSGf7/\
    uqe0N1cPEdYK+7Qo1PmhkfVf/y1xjk/F7kvHejNsPrNTvXRHoklVbVr2fih27M3fbySNlb\
    DsXl7judQDjyAeE45px+nZ3JRxrYX4IYjzovv2nLrKfeV4w4lIT1p5XZrr8qYY8AOjXwDT\
    ij3e05GnmRGCRw7s8A7hptgHwD8YwNkP588mnYPVsPiQXCnJhDhGXbygX44zDn0BqgYcSg\
    VsKixPuzWN2gCtjCPOZVwyEjCcnBabCdKNP7URFpbLxpqn/+M+ZrOR8fhywSYkTsJNDrSp\
    y7k9fzf/ks3BLpVAn92FdgmiskewgYedENIZFYVaNkJX7myhWxK6sJP8UxxYLWUhtmd2fR\
    2SN7H/akbAUHPpASwVbkRDd+70HK4qxkQ32DrhRSwDJiqvDrd62KBZlL0NQeBUx0aRvKdo\
    bPul
    """

private let fsResolveMaskGLSL = """
    /* fragment-shader: vertex color, uniform texture */
    #version 450

    layout (push_constant) uniform Constants {
        float linear;
        float constant;
    } pc;

    layout (binding=0) uniform sampler2D maskImage;
    layout (binding=1) uniform sampler2D image;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main() {
        if ((texture(maskImage, maskUV).r * pc.linear + pc.constant) <= 0)
            discard;
        vec4 frag = texture(image, texUV) * color;
        outFragColor = frag.aaaa;
    }
    """

private let fsResolveMaskSpvCEB64 = """
    XQAAAARoBAAAAAAAAAABgJdesnC95qjyNRPzlU37FEkN1hUbMQvIcJ3CE67M6dB2Y23RAR\
    9k2oVNOJaKtw9bEF24BbVkuOzAzXM/dJ3t1cdSX7VBDeIDa9Bzm9V36LqNgXYFa1unRxUa\
    YllXRpNM5dJg53AawHFulwGoqEYQlmjmJ1lEhKcq5DHV9KXGsEe22GlgkJLFldK0Ze6ja2\
    sJOBtL2K8jYJ5nHrH542x8ZKubjWb+qmyzqT4HQDkiMVyiztA5hPw5WeS1ObBOlqfqSkH6\
    wnsqXftBkbhvAkX642k48yDKd2vyArYORPwobvAXQ0Sax3HjafF9dVMqcypHnl1CUG835E\
    GEuAQ/rOkMxnPDnQc8/MiODDY8I8jPCprkixL0MnpnSTLm3X7+nIstccxju76YlNUhUo5Q\
    ZslSywO2XhNK6DAyk+9G9zwFkhMdQ7iPKHta7bcAue7KbVlghuZQIA8Sdcn+b7+AnwwpG+\
    1wt0eEAnq5ry86OA==
    """

private let fsResolveInverseMaskGLSL = """
    /* fragment-shader: vertex color, uniform texture */
    #version 450

    layout (push_constant) uniform Constants {
        float linear;
        float constant;
    } pc;

    layout (binding=0) uniform sampler2D maskImage;
    layout (binding=1) uniform sampler2D image;

    layout (location=0) in vec2 maskUV;
    layout (location=1) in vec2 texUV;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main() {
        if ((texture(maskImage, maskUV).r * pc.linear + pc.constant) <= 0)
            discard;
        vec4 frag = texture(image, texUV) * color;
        outFragColor = 1 - frag.aaaa;
    }
    """

private let fsResolveInverseMaskSpvCEB64 = """
    XQAAAASoBAAAAAAAAAABgJdesnC95qjyNRPz2qO/SDMt2CDmdjcMiDoyZhb2n2T8l4pQf6\
    WN+e258rgjKEZeAhdTyJLzOfxsZ6OXHPSV2iI1PurjK2KHD13Efp/5gmhEozfvaThJ58Xv\
    iQDpkWCCdGO5a4b/Ur1O9ngaK27dyi7pR9CdNlf0LItB0o7AmLjcAyDwW8oJ2+ISu59S2q\
    WyV/6FG5VikuGWmEP8GvedZc3qllxMHxTqyqZdjQ/tEIAVS507hIt21XOoE06eyA/ULQM/\
    ghzrR1VbcJj+s5fgOFHGVBOvPLWoieMAAmEBuo9YGaFajZnizqzHT/54+niAVrzx/Sp/Cq\
    f5lKmN748grGPFjXlMkgWBrbIn5GwAkXX7oe2r52emG3/OnDFP5nzkj3J2diYNX7prXqTW\
    FAV+5bPInSt8D6P5ZymqOUNkYwmHftZGZc8JST3uIV01uA8mPUbuCEgt/punvt2RHUm8lR\
    3IquaYJSvfWC6d+brckAzbHyKk9w1iLl4i9A8YN3CcM5g723Fk
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


private enum _Shader {
    case stencil        // fill stencil, no fragment function
    case color          // vertex color
    case image          // texture with tint color
    case alphaTexture   // for glyph (single channel texture)
    case resolveMask    // merge two masks (a8, r8) to render target (r8)
    case resolveInverseMask
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
    var linear: Float32 = 1.0
    var constant: Float32 = 0.0
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

        if let state = device.makeRenderPipelineState(descriptor: pipelineDescriptor) {
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

            guard let fragColorFunction = loadShader("fs-defalut", fsSpvCEB64)
            else { break }

            guard let fragTextureFunction = loadShader("fs-texture", fsTextureSpvCEB64)
            else { break }

            guard let fragAlphaTextureFunction = loadShader("fs-alpha-texture", fsAlphaTextureSpvCEB64)
            else { break }

            guard let fsResolveMaskFunction = loadShader("fs-resolve-mask", fsResolveMaskSpvCEB64)
            else { break }

            guard let fsResolveInverseMaskFunction = loadShader("fs-resolve-inverse-mask", fsResolveInverseMaskSpvCEB64)
            else { break }

            var shaderFunctions: [_Shader: ShaderFunctions] = [:]
            shaderFunctions[.stencil] = ShaderFunctions(
                vertexFunction: vsStencilFunction, fragmentFunction: nil)
            shaderFunctions[.color] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fragColorFunction)
            shaderFunctions[.image] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fragTextureFunction)
            shaderFunctions[.alphaTexture] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fragAlphaTextureFunction)
            shaderFunctions[.resolveMask] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsResolveMaskFunction)
            shaderFunctions[.resolveInverseMask] = ShaderFunctions(
                vertexFunction: vertexFunction, fragmentFunction: fsResolveInverseMaskFunction)

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
                self._draw(texture: context.backBuffer, in: self.bounds)
            } catch {
                Log.error("Error: \(error)")
            }
        }
    }

    private func _draw(texture: Texture, in: CGRect, tintColor: DKGame.Color = .white) {

    }

    private func _resolveMaskTexture(_ texture1: Texture, _ texture2: Texture) -> Texture? {
        return nil
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

        let queue = self.commandBuffer.commandQueue
        guard let pipeline = GraphicsPipelineStates.sharedInstance(commandQueue: queue) else {
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
            let queue = self.commandBuffer.commandQueue
            guard let pipeline = GraphicsPipelineStates.sharedInstance(commandQueue: queue) else {
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
            let rectVertices: [_Vertex] = [
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

            encoder.setRenderPipelineState(pipelineState)
            encoder.setDepthStencilState(depthState)

            pipeline.defaultBindingSet1.setTexture(self.maskTexture, binding: 0)
            pipeline.defaultBindingSet1.setSamplerState(pipeline.defaultSampler, binding: 0)
            encoder.setResource(pipeline.defaultBindingSet1, atIndex: 0)

            encoder.setCullMode(.none)
            encoder.setFrontFacing(.clockwise)
            encoder.setStencilReferenceValue(0)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

            let pc = _PushConstant(linear: 1.0, constant: 0.0)
            withUnsafeBytes(of: pc) {
                encoder.pushConstant(stages: .fragment,
                                     offset: 0,
                                     data: $0)
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
}
