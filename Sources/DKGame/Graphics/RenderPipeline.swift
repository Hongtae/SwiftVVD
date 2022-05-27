public struct RenderPipelineColorAttachmentDescriptor {
    public var index: UInt32
    public var pixelFormat: PixelFormat
    public var blendState: BlendState

    public init(index: UInt32,
                pixelFormat: PixelFormat,
                blendState: BlendState) {
        self.index = index
        self.pixelFormat = pixelFormat
        self.blendState = blendState
    }
}

public enum PrimitiveType {
	case point
	case line
	case lineStrip
	case triangle
	case triangleStrip
}

public enum IndexType {
    case uint16
    case uint32
}

public enum TriangleFillMode {
    case fill
    case lines
}

public enum CullMode {
    case none
    case front
    case back
}

public enum FrontFace {
    case cw
    case ccw
}

public enum DepthClipMode {
    case clip
    case clamp
}

public struct RenderPipelineDescriptor {
    public var vertexFunction: ShaderFunction?
    public var fragmentFunction: ShaderFunction?
    public var vertexDescriptor: VertexDescriptor
    public var colorAttachments: [RenderPipelineColorAttachmentDescriptor]
    public var depthStencilAttachmentPixelFormat: PixelFormat
    public var depthStencilDescriptor: DepthStencilDescriptor

    public var primitiveTopology: PrimitiveType

    public var triangleFillMode: TriangleFillMode
    public var depthClipMode: DepthClipMode
    public var cullMode: CullMode
    public var frontFace: FrontFace
    public var rasterizationEnabled: Bool

    public init(vertexFunction: ShaderFunction? = nil,
                fragmentFunction: ShaderFunction? = nil,
                vertexDescriptor: VertexDescriptor = .init(),
                colorAttachments: [RenderPipelineColorAttachmentDescriptor] = [],
                depthStencilAttachmentPixelFormat: PixelFormat = .invalid,
                depthStencilDescriptor: DepthStencilDescriptor = .init(),
                primitiveTopology: PrimitiveType = .point,
                triangleFillMode: TriangleFillMode = .fill,
                depthClipMode: DepthClipMode = .clip,
                cullMode: CullMode = .back,
                frontFace: FrontFace = .ccw,
                rasterizationEnabled: Bool = true) {
        self.vertexFunction = vertexFunction
        self.fragmentFunction = fragmentFunction
        self.vertexDescriptor = vertexDescriptor
        self.colorAttachments = colorAttachments
        self.depthStencilAttachmentPixelFormat = depthStencilAttachmentPixelFormat
        self.depthStencilDescriptor = depthStencilDescriptor
        self.primitiveTopology = primitiveTopology
        self.triangleFillMode = triangleFillMode
        self.depthClipMode = depthClipMode
        self.cullMode = cullMode
        self.frontFace = frontFace
        self.rasterizationEnabled = rasterizationEnabled
    }
}

public protocol RenderPipelineState {
    var device: GraphicsDevice { get }
}
