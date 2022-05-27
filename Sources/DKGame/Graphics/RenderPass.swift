public enum RenderPassAttachmentLoadAction {
    case dontCare
    case load
    case clear
}

public enum RenderPassAttachmentStoreAction {
    case dontCare
    case store
}

public protocol RenderPassAttachmentDescriptor {
    var renderTarget: Texture? { get }
    var loadAction: RenderPassAttachmentLoadAction { get }
    var storeAction: RenderPassAttachmentStoreAction { get }
}

public struct RenderPassColorAttachmentDescriptor: RenderPassAttachmentDescriptor {
    public var renderTarget: Texture?
    public var loadAction: RenderPassAttachmentLoadAction
    public var storeAction: RenderPassAttachmentStoreAction

    public var clearColor: Color

    public init(renderTarget: Texture? = nil,
                loadAction: RenderPassAttachmentLoadAction = .dontCare,
                storeAction: RenderPassAttachmentStoreAction = .dontCare,
                clearColor: Color = .black) {
        self.renderTarget = renderTarget
        self.loadAction = loadAction
        self.storeAction = storeAction
        self.clearColor = clearColor
    }
}

public struct RenderPassDepthStencilAttachmentDescriptor: RenderPassAttachmentDescriptor {
    public var renderTarget: Texture?
    public var loadAction: RenderPassAttachmentLoadAction
    public var storeAction: RenderPassAttachmentStoreAction

    public var clearDepth: Float
    public var clearStencil: UInt32

    public init(renderTarget: Texture? = nil,
                loadAction: RenderPassAttachmentLoadAction = .dontCare,
                storeAction: RenderPassAttachmentStoreAction = .dontCare,
                clearDepth: Float = 1.0,
                clearStencil: UInt32 = 0) {
        self.renderTarget = renderTarget
        self.loadAction = loadAction
        self.storeAction = storeAction
        self.clearDepth = clearDepth
        self.clearStencil = clearStencil
    }
}

public struct RenderPassDescriptor {
    public var colorAttachments: [RenderPassColorAttachmentDescriptor]
    public var depthStencilAttachment: RenderPassDepthStencilAttachmentDescriptor

    public var numberOfActiveLayers: UInt64

    public init(colorAttachments: [RenderPassColorAttachmentDescriptor] = [],
                depthStencilAttachment: RenderPassDepthStencilAttachmentDescriptor = .init(),
                numberOfActiveLayers: UInt64 = 0) {
        self.colorAttachments = colorAttachments
        self.depthStencilAttachment = depthStencilAttachment
        self.numberOfActiveLayers = numberOfActiveLayers
    }
}
