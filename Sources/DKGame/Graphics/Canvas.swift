import Foundation

private let vsGLSL = """
    /* vertex shader */
    #version 450

    layout (location=0) in vec2 position;
    layout (location=1) in vec2 texcoord;
    layout (location=2) in vec4 color;

    layout (location=0) out vec2 outPosition;
    layout (location=1) out vec2 outTexcoord;
    layout (location=2) out vec4 outColor;

    void main()
    {
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

    void main(void)
    {
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

    void main()
    {
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

private let fsEllipseGLSL = """
    /* fragment-shader: vertex color ellipse */
    #version 450

    layout (push_constant) uniform Ellipse
    {
        vec2 outerRadiusSqInv; /* vec2(1/A^2, 1/B^2) where X^2 / A^2 + Y^2 / B^2 = 1 */
        vec2 innerRadiusSqInv;
        vec2 center;	/* center of ellipse */
    } ellipse;

    layout (location=0) in vec2 position;
    layout (location=1) in vec2 texcoord;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main()
    {
        vec2 vl = position - ellipse.center;
        float form = vl.x * vl.x * ellipse.outerRadiusSqInv.x + vl.y * vl.y * ellipse.outerRadiusSqInv.y;
        if (form > 1.0)
            discard;
        outFragColor = color;
    }
    """

private let fsEllipseSpvCEB64 = """
    XQAAAAT8BAAAAAAAAAABgJdesntsONM6MGc3MEApKl6gOKaOiphx2TUpKi7V15R/VQuLn+\
    KjvLo9ofgVgb40F/wOpzAAj5D4LefT647kouue3zFWqIW7pUYAIv+ki1qJ39xQTnZoUFBo\
    Ki8dyDOHF9/BQJD/8T4+qaLtGBo3q058zqkfOg1rWcMASaIzlPUtv384TEmI3x+sh2rvq8\
    MF1ABamMcbjB/ro/b/RICDpUeY3KmmnfTWY8336iFSPjwIvowCwv9bA8G2WF2Wwtv4wgTC\
    5lCWcZ6hpsKqb4EbV3+HCgPw3bxlv16bLNHjZOXumR4YMzYfvIK87IF5nz3jG9W7L3pOvv\
    yaWXnRABsV5GPmmeb7j+eqs70ZI9LlmCwWwxfqtdYmvQkrWyAo0kDFPpWdzgpysiWYFZHN\
    L9DJ3FxnxvZmL/2yS0aXKUwylFjxEkw7NyVq1cS0Pm/ynme/ZZu4+VboXJIo/IPx8oYvam\
    BEXRvv3GwWb7YkZZsrrJXPQh9toXih9BDNiqaZjpkYLfRhG94L6BKV3gyKuODagMegRc6s\
    pvKViBXGe/KWUOFQpGNSnkdsnF7DdWBOefAd8oORj04mKCoAjCERGrpFawA=
    """

private let fsEllipseHoleGLSL = """
    /* fragment-shader: vertex color ellipse with inner hole */
    #version 450

    layout (push_constant) uniform Ellipse
    {
        vec2 outerRadiusSqInv; /* vec2(1/A^2, 1/B^2) where X^2 / A^2 + Y^2 / B^2 = 1 */
        vec2 innerRadiusSqInv;
        vec2 center;	/* center of ellipse */
    } ellipse;

    layout (location=0) in vec2 position;
    layout (location=1) in vec2 texcoord;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main()
    {
        vec2 vl = position - ellipse.center;
        vec2 vl2 = vl * vl;

        vec2 f1 = vl2 * ellipse.outerRadiusSqInv;
        if (f1.x + f1.y > 1.0)
            discard;

        vec2 f2 = vl2 * ellipse.innerRadiusSqInv;
        if (f2.x + f2.y < 1.0)
            discard;

        outFragColor = color;
    }
    """

private let fsEllipseHoleSpvCEB64 = """
    XQAAAAQwBQAAAAAAAAABgJdesntsONM6MGc5Nh9bzUJKYSZtr/HmTOO3q0we73pfWtE2WY\
    tgJOm/qvdgX3ek2zUGzNqWjozNjWHktaqHPDu6k96ZB/XsYBiGM+lW/BlRFL+BxFhu9G0i\
    lggok3ioK53HbVFOjbADtg/s4cHxMheKPcm8fsQPO+niU1q8wMO7xazU0dM5CPDE6qZ+1f\
    bCV7XzOpCe04G7hstWeU0VR/RTZafdq0Me9DtLWCt6TVY99fUvvf/CzHz/rXBovU4djv2B\
    umGsYpoHuvTefJqzSRXBHcp5fgcf/3ConXkXvPNooi6ut+05u2TqehZqVLH5TsbPRzcXP4\
    gOj2sbDvrnEO6v3+y6JJ1nD9pgKLUfLIrg+HZVoh6BfvQ2ed0qOhCOgelLhG38ruCLE9jr\
    yc6JMfnMOvXyGFDKPRYhXvmfDoRzxWsSiUDKGHZ7E6l48edmKkv+uf1Pb7GbAVSIDhVK6F\
    PUkDDjZBsdxvDpcUBRDrqn43NTPpgDE8babfuQwsAByZZT9q8S0wfir89hTi8qs16wo1pw\
    iiSISYJwPPPLoNjub5hOdWUSxMcjy4SP9jyXLRjfBxNEJf7274JGqtvlo8AqjqLvAA==
    """

private let fsTextureEllipseGLSL = """
    /* fragment-shader: vertex color, uniform texture ellipse */
    #version 450

    layout (binding=0) uniform sampler2D image;

    layout (push_constant) uniform Ellipse
    {
        vec2 outerRadiusSqInv; /* vec2(1/A^2, 1/B^2) where X^2 / A^2 + Y^2 / B^2 = 1 */
        vec2 innerRadiusSqInv;
        vec2 center;	/* center of ellipse */
    } ellipse;

    layout (location=0) in vec2 position;
    layout (location=1) in vec2 texcoord;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main()
    {
        vec2 vl = position - ellipse.center;
        float form = vl.x * vl.x * ellipse.outerRadiusSqInv.x + vl.y * vl.y * ellipse.outerRadiusSqInv.y;
        if (form > 1.0)
            discard;
        outFragColor = texture(image, texcoord) * color;
    }
    """

private let fsTextureEllipseSpvCEB64 = """
    XQAAAATEBQAAAAAAAAABgJdesntsONM6MGc5AxVbzUJKYSZtr/HmTOO3q0we73pfWtE2WY\
    tgJOm/qvdgX3ek2zUGzNqWjozNjWHktMZeH4El3hNjzurD8LARAo6TjbRD5m2dcF4abd7U\
    F1Axz9RmJNpZ2uVwtLoOtdWJlTc3P/+HTq/ySsXSCLGpFxWJ26clENesBi05UxNoVgcWJZ\
    smibV1pdgOvSFaGyHG60tnzAIIYoEWzp7x3BH3T6pRz5Zy3gA+fLPHgXsXLUUbdFxWSLNI\
    9BWWcl6vxbXlGXswTqhXV6Z0EJ60+zfi9ObwGB3WxZPXm2T0k3lkmAhDd6TLsQLPop5vfd\
    nA8Hi3Y0y6qupsgZyDBmZ/s11gP0qKuL+wpsfeq8ugpitMm0OZxR2+IG6+5iSJIxA4ZU4h\
    ZPCGSm9vqpaKdiKH4aVy2R9JoBWKn1zUhLwu8yh4IxzdwZ/tv4N0/gs4FLLt6Jo2GPjPaY\
    q8pIArADT6jNN6nvF7mQcR5m2d1YCso1+scM8RivaLFA1Uky6Jjnno//SvM+RHFHqUi/+W\
    e7dIGzGd/uYGS6oYvQuAUILUyS0qSZr9WuSZiEuK1maun111gdf3LuiJYdHHXOyy+eN0Pg\
    yo/47Pdughx+TQXwcRmi58FYO0xZwZ4GbNDKhqAxAiC2VL/V6u4WqjgAA=
    """
    
private let fsAlphaTextureGLSL = """
    /* fragment-shader: vertex color, uniform texture alpha (r8) */
    #version 450

    layout (binding=0) uniform sampler2D image;

    layout (location=0) in vec2 position;
    layout (location=1) in vec2 texcoord;
    layout (location=2) in vec4 color;

    layout (location=0) out vec4 outFragColor;

    void main(void)
    {
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

private enum CanvasShaderIndex: Int, CaseIterable {
    case vertexColor
    case vertexColorTexture
    case vertexColorEllipse
    case vertexColorEllipseHole
    case vertexColorTexturedEllipse
    case vertexColorAlphaTexture
}

private struct CanvasPipelineDescriptor: Hashable {
    var shader: CanvasShaderIndex

    // render target format
    var colorFormat: PixelFormat = .invalid
    var depthFormat: PixelFormat = .invalid

    // render target blend factor
    var sourceRGBBlendFactor: BlendFactor = .one
    var sourceAlphaBlendFactor: BlendFactor = .one
    var destinationRGBBlendFactor: BlendFactor = .zero
    var destinationAlphaBlendFactor: BlendFactor = .zero
    var rgbBlendOperation: BlendOperation = .add
    var alphaBlendOperation: BlendOperation = .add
    var writeMask: ColorWriteMask = .all

    func blendState() -> BlendState {
        var state = BlendState()
        state.sourceRGBBlendFactor = sourceRGBBlendFactor
        state.sourceAlphaBlendFactor = sourceAlphaBlendFactor
        state.destinationRGBBlendFactor = destinationRGBBlendFactor
        state.destinationAlphaBlendFactor = destinationAlphaBlendFactor
        state.rgbBlendOperation = rgbBlendOperation
        state.alphaBlendOperation = alphaBlendOperation
        state.writeMask = writeMask
        if sourceRGBBlendFactor == .one &&
           sourceAlphaBlendFactor == .one &&
           destinationRGBBlendFactor == .zero &&
           destinationAlphaBlendFactor == .zero &&
           rgbBlendOperation == .add &&
           alphaBlendOperation == .add &&
           writeMask == .all {
            state.enabled = false
        } else {
            state.enabled = true
        }
        return state
    }

    mutating func setBlendState(_ state: BlendState) {
        if state.enabled {
            sourceRGBBlendFactor = state.sourceRGBBlendFactor
            sourceAlphaBlendFactor = state.sourceAlphaBlendFactor
            destinationRGBBlendFactor = state.destinationRGBBlendFactor
            destinationAlphaBlendFactor = state.destinationAlphaBlendFactor
            rgbBlendOperation = state.rgbBlendOperation
            alphaBlendOperation = state.alphaBlendOperation
            writeMask = state.writeMask
        } else {
            sourceRGBBlendFactor = .one
            sourceAlphaBlendFactor = .one
            destinationRGBBlendFactor = .zero
            destinationAlphaBlendFactor = .zero
            rgbBlendOperation = .add
            alphaBlendOperation = .add
            writeMask = .all
        } 
    }
}

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

private struct EllipseUniformPushConstant {
    // vec2(1/A^2,1/B^2) value from formula X^2 / A^2 + Y^2 / B^2 = 1
    var outerRadiusSqInv: Float2 // outer inversed squared radius
    var innerRadiusSqInv: Float2 // inner inversed squared radius
    var center: Float2           // center of ellipse
}

private struct CanvasColoredVertexData {
    var position: Float2
    var color: Float4
}

private struct CanvasTexturedVertexData {
    var position: Float2
    var texcoord: Float2
    var color: Float4
}

private class CanvasPipelineStates {
    let vertexFunction: ShaderFunction
    let fragmentFunctions: [ShaderFunction]

    var pipelineStates: [CanvasPipelineDescriptor: RenderPipelineState] = [:]
    let device: GraphicsDevice

    let defaultBindingSet: ShaderBindingSet
    let defaultSampler: SamplerState

    func state(for desc: CanvasPipelineDescriptor) -> RenderPipelineState? {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        if let state = pipelineStates[desc] { return state }

        var pipelineDescriptor = RenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunctions[desc.shader.rawValue]
        pipelineDescriptor.colorAttachments = [
            .init(index: 0, pixelFormat: desc.colorFormat, blendState: desc.blendState())
        ]
        pipelineDescriptor.depthStencilAttachmentPixelFormat = desc.depthFormat
        pipelineDescriptor.depthStencilDescriptor.depthCompareFunction = .always
        pipelineDescriptor.depthStencilDescriptor.depthWriteEnabled = false
        pipelineDescriptor.vertexDescriptor.attributes = [
            .init(format: .float2, offset: 0, bufferIndex: 0, location: 0 ),
            .init(format: .float2, offset: MemoryLayout<CanvasTexturedVertexData>.offset(of: \.texcoord)!, bufferIndex: 0, location: 1 ),
            .init(format: .float4, offset: MemoryLayout<CanvasTexturedVertexData>.offset(of: \.color)!, bufferIndex: 0, location: 2 ),
        ]
        pipelineDescriptor.vertexDescriptor.layouts = [
            .init(step: .vertex, stride: MemoryLayout<CanvasTexturedVertexData>.stride, bufferIndex: 0)
        ]
        pipelineDescriptor.primitiveTopology = .triangle
        pipelineDescriptor.frontFace = .ccw
        pipelineDescriptor.triangleFillMode = .fill
        pipelineDescriptor.depthClipMode = .clip
        pipelineDescriptor.cullMode = .none
        pipelineDescriptor.rasterizationEnabled = true

        if let state = device.makeRenderPipelineState(descriptor: pipelineDescriptor) {
            pipelineStates[desc] = state
            return state
        }
        return nil
    }

    private init(device: GraphicsDevice,
                 vertexFunction: ShaderFunction,
                 fragmentFunctions: [ShaderFunction],
                 defaultBindingSet: ShaderBindingSet,
                 defaultSampler: SamplerState) {
        self.device = device
        self.vertexFunction = vertexFunction
        self.fragmentFunctions = fragmentFunctions
        self.defaultBindingSet = defaultBindingSet
        self.defaultSampler = defaultSampler
    }

    private static let lock = NSLock()
    private static weak var sharedInstance: CanvasPipelineStates? = nil

    static func sharedInstance(device: GraphicsDevice) -> CanvasPipelineStates? {
        if let instance = Self.sharedInstance {
            return instance
        }
        var instance: CanvasPipelineStates? = nil
        Self.lock.lock()
        defer { Self.lock.unlock() }

        instance = Self.sharedInstance
        if instance == nil {
            initPipeline: repeat {
                let vertexFunction = decodeShader(device: device, encodedText: vsSpvCEB64)
                if vertexFunction == nil { break }

                let allShaders = CanvasShaderIndex.allCases
                var fsFunctions: [ShaderFunction?] = .init(repeating: nil, count: allShaders.count)
                for s in allShaders {
                    var function: ShaderFunction? = nil
                    switch s {
                    case .vertexColor:
                        function = decodeShader(device: device, encodedText: fsSpvCEB64)
                    case .vertexColorTexture:
                        function = decodeShader(device: device, encodedText: fsTextureSpvCEB64)
                    case .vertexColorEllipse:
                        function = decodeShader(device: device, encodedText: fsEllipseSpvCEB64)
                    case .vertexColorEllipseHole:
                        function = decodeShader(device: device, encodedText: fsEllipseHoleSpvCEB64)
                    case .vertexColorTexturedEllipse:
                        function = decodeShader(device: device, encodedText: fsTextureEllipseSpvCEB64)
                    case .vertexColorAlphaTexture:  
                        function = decodeShader(device: device, encodedText: fsAlphaTextureSpvCEB64)
                    }
                    if let function = function {
                        fsFunctions[s.rawValue] = function
                    } else {
                        break initPipeline
                    }
                }

                let fragmentFunctions = fsFunctions.compactMap { $0 }
                if fragmentFunctions.count != allShaders.count { break }

                let bindingLayout = ShaderBindingSetLayout(
                    bindings: [
                        .init(binding: 0, type: .textureSampler, arrayLength: 1)
                    ])
            
                let defaultBindingSet = device.makeShaderBindingSet(layout: bindingLayout)
                if defaultBindingSet == nil { break }

                let samplerDesc = SamplerDescriptor()
                let defaultSampler = device.makeSamplerState(descriptor: samplerDesc)
                if defaultSampler == nil { break }

                instance = CanvasPipelineStates(
                    device: device,
                    vertexFunction: vertexFunction!,
                    fragmentFunctions: fragmentFunctions,
                    defaultBindingSet: defaultBindingSet!,
                    defaultSampler: defaultSampler!)

                // make weak-ref
                Self.sharedInstance = instance

            } while false
        }
        return instance
    }
}

public class Canvas {
    public struct ColoredVertex {
        var position: CGPoint
        var color: Color
    }

    public struct TexturedVertex {
        var position: CGPoint
        var texcoord: CGPoint
        var color: Color
    }

    private var commandBuffer: CommandBuffer?
    private var renderTarget: Texture?

    private var _viewport: CGRect	  
    private var _contentBounds: CGRect	  
    private var _contentTransform: Matrix3 
    private var _screenTransform: Matrix3 // for 2d scene
    private var _deviceOrientation: Matrix3 

    private var pipelineStates: CanvasPipelineStates?

    public init(commandBuffer: CommandBuffer, renderTarget: Texture) {
        self.commandBuffer = commandBuffer
        self.renderTarget = renderTarget
        self._viewport = CGRect(x: 0, y: 0, width: 1, height: 1)
        self._contentBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        self._contentTransform = .identity
        self._screenTransform = .identity
        self._deviceOrientation = .identity
        self.pipelineStates = .sharedInstance(device: commandBuffer.device)
    }

    @discardableResult
    public func commit() -> Bool {
        let result = commandBuffer?.commit()
        commandBuffer = nil
        return result ?? false
    }

    @discardableResult
    public static func cachePipelineContext(_ deviceContext: GraphicsDeviceContext) -> Bool {
        if let state = CanvasPipelineStates.sharedInstance(device: deviceContext.device) {
            deviceContext.cachedDeviceResources["Canvas.CanvasPipelineStates"] = state
            return true
        }
        return false
    }

    private func encodeDrawCommand(shaderIndex: CanvasShaderIndex,
                                   vertices: [CanvasTexturedVertexData],
                                   texture: Texture?,
                                   blendState: BlendState,
                                   pushConstantData: UnsafeRawBufferPointer?) {

        guard let commandBuffer = commandBuffer else { return }
        guard let pipelineStates = pipelineStates else { return }
        guard let renderTarget = renderTarget else { return }

        if vertices.isEmpty { return }

        var textureRequired = false;
        var pushConstantDataRequired = false;

        switch shaderIndex {
        case .vertexColor:
            textureRequired = false
            pushConstantDataRequired = false
        case .vertexColorTexture:
            textureRequired = true
            pushConstantDataRequired = false
        case .vertexColorEllipse:
            textureRequired = false
            pushConstantDataRequired = true
        case .vertexColorEllipseHole:
            textureRequired = false
            pushConstantDataRequired = true
        case .vertexColorTexturedEllipse:
            textureRequired = true
            pushConstantDataRequired = true
        case .vertexColorAlphaTexture:
            textureRequired = true
            pushConstantDataRequired = false
        }

        if textureRequired && texture == nil {
            Log.err("Canvas.encodeDrawCommand: Invalid Texture Object (Texture cannot be nil)")
            return
        }
        if pushConstantDataRequired {
            if pushConstantData == nil ||
               pushConstantData!.count != MemoryLayout<EllipseUniformPushConstant>.size {
                Log.err("Canvas.encodeDrawCommand: Invalid Ellipse (Push-Constant) Data")
                return
            }
        }

        var desc = CanvasPipelineDescriptor(shader: shaderIndex)
        desc.colorFormat = renderTarget.pixelFormat
        desc.depthFormat = .invalid
        desc.setBlendState(blendState)

        guard let pso = pipelineStates.state(for: desc) else {
            Log.err("Canvas.encodeDrawCommand: failed to create pipeline state object.")
            return        
        }
        
        let device = commandBuffer.device

        let bufferLength = MemoryLayout<CanvasTexturedVertexData>.stride * vertices.count
        guard let vertexBuffer = device.makeBuffer(length: bufferLength,
                                                storageMode: .shared,
                                                cacheMode: .writeOnly) else {
            Log.err("Canvas.encodeDrawCommand: Cannot create GPU-Buffer object with length:\(bufferLength)")
            return
        }
        let numVertices = vertices.count
        if let buffer = vertexBuffer.contents() {
            vertices.withUnsafeBytes {
                buffer.copyMemory(from: $0.baseAddress!, byteCount: MemoryLayout<CanvasTexturedVertexData>.stride * numVertices)
            }
        } else {
            Log.err("Canvas.encodeDrawCommand: Vertex-Buffer is not writable.(Invalid-mapping)")
            return
        }

        let colorAttachmentDesc = RenderPassColorAttachmentDescriptor()
        colorAttachmentDesc.renderTarget = renderTarget
        colorAttachmentDesc.loadAction = .load
        colorAttachmentDesc.storeAction = .store
        colorAttachmentDesc.clearColor = Color(0, 0, 0, 0)
        let depthAttachmentDesc = RenderPassDepthStencilAttachmentDescriptor()
        let renderPassDesc = RenderPassDescriptor(colorAttachments: [colorAttachmentDesc],
                                                  depthStencilAttachment: depthAttachmentDesc)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            Log.err("Canvas.encodeDrawCommand: Failed to create rencoder command encoder.")
            return
        }

        encoder.setRenderPipelineState(pso)
        if textureRequired {
            pipelineStates.defaultBindingSet.setTexture(texture!, binding: 0)
            pipelineStates.defaultBindingSet.setSamplerState(pipelineStates.defaultSampler, binding: 0)
            encoder.setResource(pipelineStates.defaultBindingSet, atIndex: 0)
        }
        if pushConstantDataRequired {
            encoder.pushConstant(stages: .fragment,
                                 offset: 0,
                                 data: pushConstantData!)
        }
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.draw(numVertices: numVertices, numInstances: 1, baseVertex: 0, baseInstance: 0)
        encoder.endEncoding()
    }
}
