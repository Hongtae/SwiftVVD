public enum RenderPassAttachmentLoadAction {
    case dontCare
    case load
    case clear
}

public enum RenderPassAttachmentStoreAction {
    case dontCare
    case store
}

protocol RenderPassAttachmentDescriptor {
    var renderTarget: Texture? { get }
    var loadAction: RenderPassAttachmentLoadAction { get }
    var storeAction: RenderPassAttachmentStoreAction { get }
}

public struct RenderPassColorAttachmentDescriptor: RenderPassAttachmentDescriptor {
    public var renderTarget: Texture?
    public var loadAction: RenderPassAttachmentLoadAction = .dontCare
    public var storeAction: RenderPassAttachmentStoreAction = .dontCare

    public var clearColor: Color = .black
}

public struct RenderPassDepthStencilAttachmentDescriptor: RenderPassAttachmentDescriptor {
    public var renderTarget: Texture?
    public var loadAction: RenderPassAttachmentLoadAction = .dontCare
    public var storeAction: RenderPassAttachmentStoreAction = .dontCare

    public var clearDepth: Float = 1.0
    public var clearStencil: UInt32 = 0
}

public struct RenderPassDescriptor {
    var colorAttachments: [RenderPassColorAttachmentDescriptor]
    var depthStencilAttachment: RenderPassDepthStencilAttachmentDescriptor

    var numberOfActiveLayers: UInt64 = 0
}
