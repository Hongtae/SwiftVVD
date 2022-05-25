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

private struct VertexData {
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
            .init(format: .float2, offset: MemoryLayout<VertexData>.offset(of: \.texcoord)!, bufferIndex: 0, location: 1 ),
            .init(format: .float4, offset: MemoryLayout<VertexData>.offset(of: \.color)!, bufferIndex: 0, location: 2 ),
        ]
        pipelineDescriptor.vertexDescriptor.layouts = [
            .init(step: .vertex, stride: MemoryLayout<VertexData>.stride, bufferIndex: 0)
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

    public static let minimumScaleFactor: CGFloat = 0.000001

    private var commandBuffer: CommandBuffer?
    private var renderTarget: Texture?

    private var _viewport: CGRect	  
    private var _contentBounds: CGRect	  
    private var _contentTransform: Matrix3 
    private var _deviceOrientation: Matrix3 

    private var screenTransform: Matrix3 // for 2d scene

    private var pipelineStates: CanvasPipelineStates?

    public var viewport: CGRect {
        get { _viewport }
        set(rect) {
            _viewport = rect
            self.updateTransform()
        }
    }

    public var contentBounds: CGRect {
        get { _contentBounds }
        set(rect) {
            _contentBounds = rect
            self.updateTransform()
        }
    }

    public var contentTransform: Matrix3 {
        get { _contentTransform }
        set(mat) {
            _contentTransform = mat
            self.updateTransform()
        }
    }

    public var deviceOrientation: Matrix3 {
        get { _deviceOrientation }
        set(mat) {
            _deviceOrientation = mat
            self.updateTransform()
        }
    }

    public init(commandBuffer: CommandBuffer, renderTarget: Texture) {
        self.commandBuffer = commandBuffer
        self.renderTarget = renderTarget
        self._viewport = CGRect(x: 0, y: 0, width: 1, height: 1)
        self._contentBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        self._contentTransform = .identity
        self._deviceOrientation = .identity
        self.screenTransform = .identity
        self.pipelineStates = .sharedInstance(device: commandBuffer.device)
    }

    public func clear(color: Color) {            
        let colorAttachmentDesc = RenderPassColorAttachmentDescriptor(
            renderTarget: renderTarget,
            loadAction: .clear,
            storeAction: .store,
            clearColor: color)

        let depthAttachmentDesc = RenderPassDepthStencilAttachmentDescriptor()

        let desc = RenderPassDescriptor(
            colorAttachments: [colorAttachmentDesc],
            depthStencilAttachment: depthAttachmentDesc)

        if let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: desc) {
            encoder.endEncoding()
        }
    }

    public func drawLines(_ points: [CGPoint],
                          lineWidth: CGFloat = 1.0,
                          color: Color,
                          blendState: BlendState) {
        if points.isEmpty || lineWidth < Self.minimumScaleFactor { return }

        let numPoints = points.count
        let halfWidth = Scalar(lineWidth * 0.5)
        var vertices: [Vector2] = []
        vertices.reserveCapacity(numPoints * 3)

        var index = 0
        while index + 1 < numPoints {
            let v0 = Vector2(points[index])
            let v1 = Vector2(points[index+1])
            var line = v1 - v0
            let length = line.length
            if length > Scalar(Self.minimumScaleFactor) {
                line.normalize()
                let cosR = line.x
                let sinR = line.y
                let rotate = Matrix2(cosR, sinR, -sinR, cosR)

                let box0 = Vector2(0.0, halfWidth).transformed(by: rotate) + v0
                let box1 = Vector2(0.0, -halfWidth).transformed(by: rotate) + v0
                let box2 = Vector2(length, halfWidth).transformed(by: rotate) + v0
                let box3 = Vector2(length, -halfWidth).transformed(by: rotate) + v0
                
                vertices.append(box0)
                vertices.append(box1)
                vertices.append(box2)
                vertices.append(box2)
                vertices.append(box1)
                vertices.append(box3)
            }
            index += 2
        }
        self.drawTriangles(vertices.map{ CGPoint($0) }, color: color, blendState: blendState)
    }

    public func drawLineStrip(_ points: [CGPoint],
                              lineWidth: CGFloat = 1.0,
                              color: Color,
                              blendState: BlendState) {

        if points.isEmpty || lineWidth < Self.minimumScaleFactor { return }

        let numPoints = points.count
        let halfWidth = Scalar(lineWidth * 0.5)
        var vertices: [Vector2] = []
        vertices.reserveCapacity(numPoints * 4)

        for index in 0..<(numPoints - 1) {
            let v0 = Vector2(points[index])
            let v1 = Vector2(points[index+1])
            var line = v1 - v0
            let length = line.length
            if length > Scalar(Self.minimumScaleFactor) {
                line.normalize()
                let cosR = line.x
                let sinR = line.y
                let rotate = Matrix2(cosR, sinR, -sinR, cosR)

                let box0 = Vector2(0.0, halfWidth).transformed(by: rotate) + v0
                let box1 = Vector2(0.0, -halfWidth).transformed(by: rotate) + v0
                let box2 = Vector2(length, halfWidth).transformed(by: rotate) + v0
                let box3 = Vector2(length, -halfWidth).transformed(by: rotate) + v0
                
                vertices.append(box0)
                vertices.append(box1)
                vertices.append(box2)
                vertices.append(box3)
            }
        }
        self.drawTriangleStrip(vertices.map{ CGPoint($0) }, color: color, blendState: blendState)
    }

    public func drawTriangles(_ vertices: [CGPoint],
                              color: Color,
                              blendState: BlendState) {
        let numVerts = vertices.count
        if numVerts > 2 {
            var vertexData: [VertexData] = []
            vertexData.reserveCapacity(numVerts)

            for pt in vertices {
                let pos = Vector2(pt).transformed(by: screenTransform).float2
                vertexData.append(VertexData(position: pos,
                                             texcoord: Float2(0, 0),
                                             color: color.float4))
            }

            self.encodeDrawCommand(shaderIndex: .vertexColor,
                                   vertices: vertexData,
                                   texture: nil,
                                   blendState: blendState,
                                   pushConstantData: nil)
        }
    }

    public func drawTriangles(_ vertices: [ColoredVertex],
                              blendState: BlendState) {
        let numVerts = vertices.count
        if numVerts > 2 {
            var vertexData: [VertexData] = []
            vertexData.reserveCapacity(numVerts)

            for v in vertices {
                let pos = Vector2(v.position).transformed(by: screenTransform).float2
                vertexData.append(VertexData(position: pos,
                                             texcoord: Float2(0, 0),
                                             color: v.color.float4))
            }

            self.encodeDrawCommand(shaderIndex: .vertexColor,
                                   vertices: vertexData,
                                   texture: nil,
                                   blendState: blendState,
                                   pushConstantData: nil)
        }
    }

    public func drawTriangles(_ vertices: [TexturedVertex],
                              texture: Texture,
                              blendState: BlendState) {
        let numVerts = vertices.count
        if numVerts > 2 {
            var vertexData: [VertexData] = []
            vertexData.reserveCapacity(numVerts)

            for v in vertices {
                let pos = Vector2(v.position).transformed(by: screenTransform).float2
                vertexData.append(VertexData(position: pos,
                                             texcoord: Vector2(v.texcoord).float2,
                                             color: v.color.float4))
            }

            self.encodeDrawCommand(shaderIndex: .vertexColor,
                                   vertices: vertexData,
                                   texture: nil,
                                   blendState: blendState,
                                   pushConstantData: nil)
        }
    }

    public func  drawTriangleStrip(_ vertices: [CGPoint],
                                   color: Color,
                                   blendState: BlendState) {
        let numVerts = vertices.count
        if numVerts > 2 {
            var verts: [CGPoint] = []
            verts.reserveCapacity(numVerts * 3)

            for i in 0..<(numVerts - 2) {
                if i & 1 == 0 {
                    verts.append(vertices[i])
                    verts.append(vertices[i+1])
                } else {
                    verts.append(vertices[i+1])
                    verts.append(vertices[i])
                }
                verts.append(vertices[i+2])
            }
            self.drawTriangles(verts, color: color, blendState: blendState)
        }
    }

    public func  drawTriangleStrip(_ vertices: [ColoredVertex],
                                   blendState: BlendState) {
        let numVerts = vertices.count
        if numVerts > 2 {
            var verts: [ColoredVertex] = []
            verts.reserveCapacity(numVerts * 3)

            for i in 0..<(numVerts - 2) {
                if i & 1 == 0 {
                    verts.append(vertices[i])
                    verts.append(vertices[i+1])
                } else {
                    verts.append(vertices[i+1])
                    verts.append(vertices[i])
                }
                verts.append(vertices[i+2])
            }
            self.drawTriangles(verts, blendState: blendState)
        }
    }

    public func  drawTriangleStrip(_ vertices: [TexturedVertex],
                                   texture: Texture,
                                   blendState: BlendState) {
        let numVerts = vertices.count
        if numVerts > 2 {
            var verts: [TexturedVertex] = []
            verts.reserveCapacity(numVerts * 3)

            for i in 0..<(numVerts - 2) {
                if i & 1 == 0 {
                    verts.append(vertices[i])
                    verts.append(vertices[i+1])
                } else {
                    verts.append(vertices[i+1])
                    verts.append(vertices[i])
                }
                verts.append(vertices[i+2])
            }
            self.drawTriangles(verts, texture: texture, blendState: blendState)
        }
    }

    public func drawQuad(leftTop lt: CGPoint,
                         rightTop rt: CGPoint,
                         leftBottom lb: CGPoint,
                         rightBottom rb: CGPoint,
                         color: Color,
                         blendState: BlendState) {
        let tpos0 = lt.transformed(by: self._contentTransform)
        let tpos1 = rt.transformed(by: self._contentTransform)
        let tpos2 = lb.transformed(by: self._contentTransform)
        let tpos3 = rb.transformed(by: self._contentTransform)

        let t1 = self._contentBounds.intersectsTriangle(tpos0, tpos2, tpos1)
        let t2 = self._contentBounds.intersectsTriangle(tpos1, tpos2, tpos3)
        if t1 && t2 {
            let vertices = [lt, lb, rt, rb, lb, rb]
            self.drawTriangles(vertices, color: color, blendState: blendState)
        } else if t1 {
            let vertices = [lt, lb, rt]
            self.drawTriangles(vertices, color: color, blendState: blendState)
        } else if t2 {
            let vertices = [rt, lb, rb]
            self.drawTriangles(vertices, color: color, blendState: blendState)
        }
    }

    public func drawQuad(leftTop lt: TexturedVertex,
                         rightTop rt: TexturedVertex,
                         leftBottom lb: TexturedVertex,
                         rightBottom rb: TexturedVertex,
                         texture: Texture,
                         blendState: BlendState) {
        let tpos0 = lt.position.transformed(by: self._contentTransform)
        let tpos1 = rt.position.transformed(by: self._contentTransform)
        let tpos2 = lb.position.transformed(by: self._contentTransform)
        let tpos3 = rb.position.transformed(by: self._contentTransform)

        let t1 = self._contentBounds.intersectsTriangle(tpos0, tpos2, tpos1)
        let t2 = self._contentBounds.intersectsTriangle(tpos1, tpos2, tpos3)
        if t1 && t2 {
            let vertices = [lt, lb, rt, rb, lb, rb]
            self.drawTriangles(vertices, texture: texture, blendState: blendState)
        } else if t1 {
            let vertices = [lt, lb, rt]
            self.drawTriangles(vertices, texture: texture, blendState: blendState)
        } else if t2 {
            let vertices = [rt, lb, rb]
            self.drawTriangles(vertices, texture: texture, blendState: blendState)
        }
    }

    public func drawRect(_ rect: CGRect,
                         transform tm: Matrix3,
                         color: Color,
                         blendState: BlendState) {        
        if rect.isEmpty || rect.isInfinite { return }

        let pos0 = CGPoint(x: rect.minX, y: rect.minY).transformed(by: tm) // left-top
        let pos1 = CGPoint(x: rect.maxX, y: rect.minY).transformed(by: tm) // right-top
        let pos2 = CGPoint(x: rect.minX, y: rect.maxY).transformed(by: tm) // left-bottom
        let pos3 = CGPoint(x: rect.maxX, y: rect.maxY).transformed(by: tm) // right-bottom

        let tpos0 = pos0.transformed(by: _contentTransform)
        let tpos1 = pos1.transformed(by: _contentTransform)
        let tpos2 = pos2.transformed(by: _contentTransform)
        let tpos3 = pos3.transformed(by: _contentTransform)
        
        let t1 = _contentBounds.intersectsTriangle(tpos0, tpos2, tpos1)
        let t2 = _contentBounds.intersectsTriangle(tpos1, tpos2, tpos3)
        if t1 && t2 {
            let vertices = [ pos0, pos2, pos1, pos1, pos2, pos3 ]
            self.drawTriangles(vertices, color: color, blendState: blendState)
        } else if t1 {
            let vertices = [ pos0, pos2, pos1 ]
            self.drawTriangles(vertices, color: color, blendState: blendState)
        } else if t2 {
            let vertices = [ pos1, pos2, pos3 ]
            self.drawTriangles(vertices, color: color, blendState: blendState)
        }
    }

    public func drawRect(_ rect: CGRect,
                         transform tm: Matrix3,
                         textureRect texRect: CGRect,
                         textureTransform texTM: Matrix3,
                         texture: Texture,
                         color: Color,
                         blendState: BlendState) {
        if rect.isEmpty || rect.isInfinite { return }

        let pos0 = CGPoint(x: rect.minX, y: rect.minY).transformed(by: tm) // left-top
        let pos1 = CGPoint(x: rect.maxX, y: rect.minY).transformed(by: tm) // right-top
        let pos2 = CGPoint(x: rect.minX, y: rect.maxY).transformed(by: tm) // left-bottom
        let pos3 = CGPoint(x: rect.maxX, y: rect.maxY).transformed(by: tm) // right-bottom

        let tex0 = CGPoint(x: texRect.minX, y: texRect.minY).transformed(by: texTM) // left-top
        let tex1 = CGPoint(x: texRect.maxX, y: texRect.minY).transformed(by: texTM) // right-top
        let tex2 = CGPoint(x: texRect.minX, y: texRect.maxY).transformed(by: texTM) // left-bottom
        let tex3 = CGPoint(x: texRect.maxX, y: texRect.maxY).transformed(by: texTM) // right-bottom

        let tpos0 = pos0.transformed(by: _contentTransform)
        let tpos1 = pos1.transformed(by: _contentTransform)
        let tpos2 = pos2.transformed(by: _contentTransform)
        let tpos3 = pos3.transformed(by: _contentTransform)
        
        let t1 = _contentBounds.intersectsTriangle(tpos0, tpos2, tpos1)
        let t2 = _contentBounds.intersectsTriangle(tpos1, tpos2, tpos3)
        if t1 && t2 {
            let vertices: [TexturedVertex] = [
                TexturedVertex(position: pos0, texcoord: tex0, color: color),
                TexturedVertex(position: pos2, texcoord: tex2, color: color),
                TexturedVertex(position: pos1, texcoord: tex1, color: color),
                TexturedVertex(position: pos1, texcoord: tex1, color: color),
                TexturedVertex(position: pos2, texcoord: tex2, color: color),
                TexturedVertex(position: pos3, texcoord: tex3, color: color),
            ]
            self.drawTriangles(vertices, texture: texture, blendState: blendState)
        } else if t1 {
            let vertices: [TexturedVertex] = [
                TexturedVertex(position: pos0, texcoord: tex0, color: color),
                TexturedVertex(position: pos2, texcoord: tex2, color: color),
                TexturedVertex(position: pos1, texcoord: tex1, color: color),
            ]
            self.drawTriangles(vertices, texture: texture, blendState: blendState)
        } else if t2 {
            let vertices: [TexturedVertex] = [
                TexturedVertex(position: pos1, texcoord: tex1, color: color),
                TexturedVertex(position: pos2, texcoord: tex2, color: color),
                TexturedVertex(position: pos3, texcoord: tex3, color: color),
            ]
            self.drawTriangles(vertices, texture: texture, blendState: blendState)
        }
    }

    public func drawEllipse(bounds: CGRect,
                            inset: CGSize,
                            transform: Matrix3,
                            color: Color,
                            blendState: BlendState) {
        if bounds.isEmpty || bounds.isInfinite { return }
        if inset.width < Self.minimumScaleFactor || inset.height < Self.minimumScaleFactor { return }

        let innerBounds = bounds.insetBy(dx: inset.width, dy: inset.height)

        if innerBounds.width < Self.minimumScaleFactor || innerBounds.height < Self.minimumScaleFactor {
            return self.drawEllipse(bounds: bounds,
                                    transform: transform,
                                    color: color,
                                    blendState: blendState)
        }

        let tm = transform * screenTransform    // user transform * screen space
        let pos0 = Vector2(Scalar(bounds.minX), Scalar(bounds.minY)).transformed(by: tm)  // left-top
        let pos1 = Vector2(Scalar(bounds.maxX), Scalar(bounds.minY)).transformed(by: tm)  // right-top
        let pos2 = Vector2(Scalar(bounds.minX), Scalar(bounds.maxY)).transformed(by: tm)  // left-bottom
        let pos3 = Vector2(Scalar(bounds.maxX), Scalar(bounds.maxY)).transformed(by: tm)  // right-bottom

        let local = CGRect(x: -1.0, y: -1.0, width: 2.0, height: 2.0)   // 3d frustum space of screen.
        if local.intersectsTriangle(CGPoint(pos0), CGPoint(pos2), CGPoint(pos1)) ||
           local.intersectsTriangle(CGPoint(pos1), CGPoint(pos2), CGPoint(pos3)) {

            let radiusSq = Vector2((pos1 - pos0).lengthSquared * 0.25,
                                   (pos0 - pos2).lengthSquared * 0.25)
            if CGFloat(radiusSq.x * radiusSq.y) > Self.minimumScaleFactor {
                let ibpos0 = Vector2(Scalar(innerBounds.minX), Scalar(innerBounds.minY)).transformed(by: tm)  // left-top
                let ibpos1 = Vector2(Scalar(innerBounds.maxX), Scalar(innerBounds.minY)).transformed(by: tm)  // right-top
                let ibpos2 = Vector2(Scalar(innerBounds.minX), Scalar(innerBounds.maxY)).transformed(by: tm)  // left-bottom

                let ibRadiusSq = Vector2(x: (ibpos1 - ibpos0).lengthSquared * 0.25,
                                         y: (ibpos0 - ibpos2).lengthSquared * 0.25)

                // formula: X^2 / A^2 + Y^2 / B^2 = 1
                // A^2 = bounds.width/2, B^2 = bounds.height/2
                var ellipseData = EllipseUniformPushConstant(
                    outerRadiusSqInv: Vector2(1.0 / radiusSq.x, 1.0 / radiusSq.y).float2,
                    innerRadiusSqInv: Vector2(1.0 / ibRadiusSq.x, 1.0 / ibRadiusSq.y).float2,
                    center: Vector2(Scalar(bounds.midX), Scalar(bounds.midY)).transformed(by: screenTransform).float2)

                let texcoord = Vector2.zero.float2
                let vertexcolor = color.float4
                let vf: [VertexData] = [
                    VertexData(position: pos0.float2, texcoord: texcoord, color: vertexcolor),
                    VertexData(position: pos2.float2, texcoord: texcoord, color: vertexcolor),
                    VertexData(position: pos1.float2, texcoord: texcoord, color: vertexcolor),
                    VertexData(position: pos1.float2, texcoord: texcoord, color: vertexcolor),
                    VertexData(position: pos2.float2, texcoord: texcoord, color: vertexcolor),
                    VertexData(position: pos3.float2, texcoord: texcoord, color: vertexcolor),
                ]

                withUnsafeBytes(of: &ellipseData) {
                    self.encodeDrawCommand(shaderIndex: .vertexColorEllipseHole,
                                           vertices: vf,
                                           texture: nil,
                                           blendState: blendState,
                                           pushConstantData: $0)
                }
            }
        }
    }

    public func drawEllipse(bounds: CGRect,
                            transform: Matrix3,
                            color: Color,
                            blendState: BlendState) {
        if bounds.isEmpty || bounds.isInfinite { return }

        let tm = transform * screenTransform    // user transform * screen space
        let pos0 = Vector2(Scalar(bounds.minX), Scalar(bounds.minY)).transformed(by: tm)  // left-top
        let pos1 = Vector2(Scalar(bounds.maxX), Scalar(bounds.minY)).transformed(by: tm)  // right-top
        let pos2 = Vector2(Scalar(bounds.minX), Scalar(bounds.maxY)).transformed(by: tm)  // left-bottom
        let pos3 = Vector2(Scalar(bounds.maxX), Scalar(bounds.maxY)).transformed(by: tm)  // right-bottom

        let local = CGRect(x: -1.0, y: -1.0, width: 2.0, height: 2.0)   // 3d frustum space of screen.
        if local.intersectsTriangle(CGPoint(pos0), CGPoint(pos2), CGPoint(pos1)) ||
           local.intersectsTriangle(CGPoint(pos1), CGPoint(pos2), CGPoint(pos3)) {

            let radiusSq = Vector2((pos1 - pos0).lengthSquared * 0.25,
                                   (pos0 - pos2).lengthSquared * 0.25)
            if CGFloat(radiusSq.x * radiusSq.y) > Self.minimumScaleFactor {
                // formula: X^2 / A^2 + Y^2 / B^2 = 1
                // A^2 = bounds.width/2, B^2 = bounds.height/2
                var ellipseData = EllipseUniformPushConstant(
                    outerRadiusSqInv: Vector2(1.0 / radiusSq.x, 1.0 / radiusSq.y).float2,
                    innerRadiusSqInv: (0.0, 0.0),
                    center: Vector2(Scalar(bounds.midX), Scalar(bounds.midY)).transformed(by: screenTransform).float2)

                let texcoord = Vector2.zero.float2
                let vertexcolor = color.float4
                let vf: [VertexData] = [
                    VertexData(position: pos0.float2, texcoord: texcoord, color: vertexcolor),
                    VertexData(position: pos2.float2, texcoord: texcoord, color: vertexcolor),
                    VertexData(position: pos1.float2, texcoord: texcoord, color: vertexcolor),
                    VertexData(position: pos1.float2, texcoord: texcoord, color: vertexcolor),
                    VertexData(position: pos2.float2, texcoord: texcoord, color: vertexcolor),
                    VertexData(position: pos3.float2, texcoord: texcoord, color: vertexcolor),
                ]

                withUnsafeBytes(of: &ellipseData) {
                    self.encodeDrawCommand(shaderIndex: .vertexColorEllipse,
                                           vertices: vf,
                                           texture: nil,
                                           blendState: blendState,
                                           pushConstantData: $0)
                }
            }
        }
    }

    public func drawEllipse(bounds: CGRect,
                            transform: Matrix3,
                            textureBounds uvBounds: CGRect,
                            textureTransform uvTransform: Matrix3,
                            texture: Texture,
                            color: Color,
                            blendState: BlendState) {
        if bounds.isEmpty || bounds.isInfinite { return }

        let tm = transform * screenTransform    // user transform * screen space
        let pos0 = Vector2(Scalar(bounds.minX), Scalar(bounds.minY)).transformed(by: tm)  // left-top
        let pos1 = Vector2(Scalar(bounds.maxX), Scalar(bounds.minY)).transformed(by: tm)  // right-top
        let pos2 = Vector2(Scalar(bounds.minX), Scalar(bounds.maxY)).transformed(by: tm)  // left-bottom
        let pos3 = Vector2(Scalar(bounds.maxX), Scalar(bounds.maxY)).transformed(by: tm)  // right-bottom

        let local = CGRect(x: -1.0, y: -1.0, width: 2.0, height: 2.0)   // 3d frustum space of screen.
        if local.intersectsTriangle(CGPoint(pos0), CGPoint(pos2), CGPoint(pos1)) ||
           local.intersectsTriangle(CGPoint(pos1), CGPoint(pos2), CGPoint(pos3)) {

            let radiusSq = Vector2((pos1 - pos0).lengthSquared * 0.25,
                                   (pos0 - pos2).lengthSquared * 0.25)
            if CGFloat(radiusSq.x * radiusSq.y) > Self.minimumScaleFactor {
                // formula: X^2 / A^2 + Y^2 / B^2 = 1
                // A^2 = bounds.width/2, B^2 = bounds.height/2
                var ellipseData = EllipseUniformPushConstant(
                    outerRadiusSqInv: Vector2(1.0 / radiusSq.x, 1.0 / radiusSq.y).float2,
                    innerRadiusSqInv: (0.0, 0.0),
                    center: Vector2(Scalar(bounds.midX), Scalar(bounds.midY)).transformed(by: screenTransform).float2)

                let uv0 = Vector2(Scalar(uvBounds.minX), Scalar(uvBounds.minY)).transformed(by: uvTransform) // left-top
                let uv1 = Vector2(Scalar(uvBounds.maxX), Scalar(uvBounds.minY)).transformed(by: uvTransform) // right-top
                let uv2 = Vector2(Scalar(uvBounds.minX), Scalar(uvBounds.maxY)).transformed(by: uvTransform) // left-bottom
                let uv3 = Vector2(Scalar(uvBounds.maxX), Scalar(uvBounds.maxY)).transformed(by: uvTransform) // right-bottom

                let vertexcolor = color.float4
                let vf: [VertexData] = [
                    VertexData(position: pos0.float2, texcoord: uv0.float2, color: vertexcolor),
                    VertexData(position: pos2.float2, texcoord: uv2.float2, color: vertexcolor),
                    VertexData(position: pos1.float2, texcoord: uv1.float2, color: vertexcolor),
                    VertexData(position: pos1.float2, texcoord: uv1.float2, color: vertexcolor),
                    VertexData(position: pos2.float2, texcoord: uv2.float2, color: vertexcolor),
                    VertexData(position: pos3.float2, texcoord: uv3.float2, color: vertexcolor),
                ]

                withUnsafeBytes(of: &ellipseData) {
                    self.encodeDrawCommand(shaderIndex: .vertexColorTexturedEllipse,
                                           vertices: vf,
                                           texture: texture,
                                           blendState: blendState,
                                           pushConstantData: $0)
                }
            }
        }
    }

    public func drawText(_ text: String,
                         withFont font: Font,
                         bounds: CGRect,
                         transform: Matrix3,
                         color: Color) {
        if bounds.isEmpty || bounds.isInfinite { return }
        if text.isEmpty { return }

        struct GlyphVertex {
            let pos: Vector2
            let tex: Float2
        }
        struct Quad {
            let lt: GlyphVertex 
            let rt: GlyphVertex
            let lb: GlyphVertex
            let rb: GlyphVertex
            let texture: Texture
        }

        var quads: [Quad] = []
        let str = text.unicodeScalars
        quads.reserveCapacity(str.count)

        var bboxMin = Vector2(0, 0)
        var bboxMax = Vector2(0, 0)
        var offset: Scalar = 0.0        // accumulated text width (pixel)

        let colorF4 = color.float4

        var c1 = UnicodeScalar(UInt8(0)) 
        for c2 in str {
            // get glyph info from font object
            if let glyph = font.glyphData(forChar: c2) {
                offset += Scalar(font.kernAdvance(left: c1, right: c2).x)

                let posMin = Vector2(offset + Scalar(glyph.position.x), Scalar(glyph.position.y))
                let posMax = Vector2(Scalar(glyph.frame.maxX), Scalar(glyph.frame.maxY)) + posMin

                if offset > 0.0 {
                    if (bboxMin.x > posMin.x) { bboxMin.x = posMin.x }
                    if (bboxMin.y > posMin.y) { bboxMin.y = posMin.y }
                    if (bboxMax.x < posMax.x) { bboxMax.x = posMax.x }
                    if (bboxMax.y < posMax.y) { bboxMax.y = posMax.y }
                } else {
                    bboxMin = posMin
                    bboxMax = posMax
                }

                if let texture = glyph.texture {
                    let textureWidth = texture.width
                    let textureHeight = texture.height
                    if textureWidth > 0 && textureHeight > 0 {
                        let invW = 1.0 / Float(textureWidth)
                        let invH = 1.0 / Float(textureHeight)

                        let uvMinX = Float(glyph.frame.minX) * invW
                        let uvMinY = Float(glyph.frame.minY) * invH
                        let uvMaxX = Float(glyph.frame.maxX) * invW
                        let uvMaxY = Float(glyph.frame.maxY) * invH

                        let q = Quad(lt: GlyphVertex(pos: Vector2(posMin.x, posMin.y),
                                                     tex: (uvMinX, uvMinY)),
                                     rt: GlyphVertex(pos: Vector2(posMax.x, posMin.y),
                                                     tex: (uvMaxX, uvMinY)),
                                     lb: GlyphVertex(pos: Vector2(posMin.x, posMax.y),
                                                     tex: (uvMinX, uvMaxY)),
                                     rb: GlyphVertex(pos: Vector2(posMax.x, posMax.y),
                                                     tex: (uvMaxX, uvMaxY)),
                                     texture: texture)
                        quads.append(q)
                    }
                }
                offset += Scalar(glyph.advance.width)
            }
            c1 = c2
        }
        if quads.isEmpty { return }

        let width = bboxMax.x - bboxMin.x
        let height = bboxMax.y - bboxMin.y
        if width <= .ulpOfOne || height <= .ulpOfOne { return }

        // sort by texture order
        quads.sort {
            // unsafeBitCast($0.texture, to: UInt.self) > unsafeBitCast($1.texture, to: UInt.self)
            ObjectIdentifier($0.texture) > ObjectIdentifier($1.texture)
        }

        // calculate transform matrix
        var trans = AffineTransform2(x: -bboxMin.x, y: -bboxMin.y)    // move origin
        trans *= LinearTransform2(scaleX: 1.0 / width, scaleY: 1.0 / height) // normalize size
        trans *= LinearTransform2(scaleX: Scalar(bounds.maxX), scaleY: Scalar(bounds.maxY)) // scale to bounds
        trans.translate(x: Scalar(bounds.minX), y: Scalar(bounds.minY)) // move to bounds origin

        var matrix = trans.matrix3
        matrix *= transform         // user transform
        matrix *= screenTransform   // transform to screen-space

        var lastTexture: Texture? = nil
        var triangles: [VertexData] = []
        triangles.reserveCapacity(quads.count * 6)
        for q in quads {
            if q.texture !== lastTexture {
                if triangles.count > 0 {
                    self.encodeDrawCommand(shaderIndex: .vertexColorAlphaTexture,
                        vertices: triangles, texture: lastTexture!,
                        blendState: .defaultAlpha, pushConstantData: nil)
                }
                triangles.removeAll(keepingCapacity: true)
                lastTexture = q.texture
            }

            let vf: [VertexData] = [
                VertexData(position: q.lt.pos.transformed(by: matrix).float2, texcoord: q.lt.tex, color: colorF4),
                VertexData(position: q.lb.pos.transformed(by: matrix).float2, texcoord: q.lb.tex, color: colorF4),
                VertexData(position: q.rt.pos.transformed(by: matrix).float2, texcoord: q.rt.tex, color: colorF4),
                VertexData(position: q.rt.pos.transformed(by: matrix).float2, texcoord: q.rt.tex, color: colorF4),
                VertexData(position: q.lb.pos.transformed(by: matrix).float2, texcoord: q.lb.tex, color: colorF4),
                VertexData(position: q.rb.pos.transformed(by: matrix).float2, texcoord: q.rb.tex, color: colorF4),
            ]
            triangles.append(contentsOf: vf)
        }
        if triangles.count > 0 {
            self.encodeDrawCommand(shaderIndex: .vertexColorAlphaTexture,
                vertices: triangles, texture: lastTexture!,
                blendState: .defaultAlpha, pushConstantData: nil)
        }
    }

    public func drawText(_ text: String,
                         withFont font: Font,
                         baselineBegin: CGPoint,
                         baselineEnd: CGPoint,
                         color: Color) {
        if text.isEmpty { return }
        if (baselineEnd - baselineBegin).magnitude < .ulpOfOne { return }

        // font size, screen size in pixel units
        let ascender = font.ascender
        // let lineHeight = font.lineHeight()
        let lineWidth = font.lineWidth(of: text)
        let textBounds = font.bounds(of: text)

        let viewportSize = CGSize(width: _viewport.width, height: _viewport.height)
        let contentScale = CGSize(width: _contentBounds.width, height: _contentBounds.height)

        // change local-coords to pixel-coords
        let scaleToScreen = CGSize(width: viewportSize.width / contentScale.width,
                                   height: viewportSize.height / contentScale.height)
        let baselinePixelBegin = CGPoint(x: baselineBegin.x * scaleToScreen.width,
                                         y: baselineBegin.y * scaleToScreen.height)
        let baselinePixelEnd = CGPoint(x: baselineEnd.x * scaleToScreen.width,
                                       y: baselineEnd.y * scaleToScreen.height)
        let scale = (baselinePixelEnd - baselinePixelBegin).magnitude
        let baselinePixelDir = Vector2(baselinePixelEnd - baselinePixelBegin).normalized()
        let angle = acosf(baselinePixelDir.x) * ((baselinePixelDir.y < 0) ? -1.0 : 1.0)

        // calculate transform (matrix)
        var transform = AffineTransform2(x: 0, y: Scalar(-ascender))    // move pivot to baseline
        transform *= LinearTransform2()
            .scaled(by: Scalar(scale / lineWidth))                  // scale
            .rotated(by: angle)                             // rotate
            .scaled(x: Scalar(1.0 / viewportSize.width),
                    y: Scalar(1.0 / viewportSize.height))   // normalize (0~1)
            .scaled(by: Vector2(contentScale))              // apply contentScale
        transform.translate(by: Vector2(baselineBegin))

        self.drawText(text, withFont: font, bounds: textBounds, transform: transform.matrix3, color: color)
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

    private func updateTransform() {
        // let viewportOffset = _viewport.origin
        let contentOffset = _contentBounds.origin
        let contentScale = _contentBounds.size

        assert(contentScale.width > 0.0 && contentScale.height > 0.0)

        let targetOrient = AffineTransform2(_deviceOrientation)
        let offset = AffineTransform2(origin: -Vector2(contentOffset)).matrix3
        let s = LinearTransform2(scaleX: 1.0 / Scalar(contentScale.width), scaleY: 1.0 / Scalar(contentScale.height))

        // transform to screen viewport space.
        let normalize = Matrix3(row1: Vector3(2.0, 0.0, 0.0),
                                row2: Vector3(0.0, -2.0, 0.0),
                                row3: Vector3(-1.0, 1.0, 1.0))

        self.screenTransform = _contentTransform * offset * 
            AffineTransform2(linear: s).transformed(by: targetOrient).matrix3 * normalize
    }

    private func encodeDrawCommand(shaderIndex: CanvasShaderIndex,
                                   vertices: [VertexData],
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

        let bufferLength = MemoryLayout<VertexData>.stride * vertices.count
        guard let vertexBuffer = device.makeBuffer(length: bufferLength,
                                                   storageMode: .shared,
                                                   cpuCacheMode: .writeCombined) else {
            Log.err("Canvas.encodeDrawCommand: Cannot create GPU-Buffer object with length:\(bufferLength)")
            return
        }
        let numVertices = vertices.count
        if let buffer = vertexBuffer.contents() {
            vertices.withUnsafeBytes {
                buffer.copyMemory(from: $0.baseAddress!, byteCount: MemoryLayout<VertexData>.stride * numVertices)
            }
        } else {
            Log.err("Canvas.encodeDrawCommand: Vertex-Buffer is not writable.(Invalid-mapping)")
            return
        }

        let colorAttachmentDesc = RenderPassColorAttachmentDescriptor(
            renderTarget: renderTarget,
            loadAction: .load,
            storeAction: .store,
            clearColor: Color(0, 0, 0, 0))
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
