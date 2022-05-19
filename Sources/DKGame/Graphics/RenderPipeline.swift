public struct RenderPipelineColorAttachmentDescriptor {
    var index : UInt32
    var pixelFormat : PixelFormat
    var blendState : BlendState
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
    var vertexFunction : ShaderFunction?
    var fragmentFunction : ShaderFunction?
    var vertexDescriptor : VertexDescriptor = .init()
    var colorAttachments : [RenderPipelineColorAttachmentDescriptor] = []
    var depthStencilAttachmentPixelFormat : PixelFormat = .invalid
    var depthStencilDescriptor : DepthStencilDescriptor = .init()

    var primitiveTopology : PrimitiveType = .point

    var triangleFillMode : TriangleFillMode = .fill
    var depthClipMode : DepthClipMode = .clip
    var cullMode : CullMode = .back
    var frontFace : FrontFace = .ccw
    var rasterizationEnabled : Bool = true
}

public protocol RenderPipelineState {
    var device: GraphicsDevice { get }
}
