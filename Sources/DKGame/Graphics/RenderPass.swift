public class RenderPassAttachmentDescriptor {
    public enum LoadAction {
        case dontCare
        case load
        case clear
    }
    public enum StoreAction {
        case dontCare
        case store
    }

    var renderTarget: Texture?
    var loadAction: LoadAction = .dontCare
    var storeAction: StoreAction = .dontCare
}

public class RenderPassColorAttachmentDescriptor : RenderPassAttachmentDescriptor {
    var clearColor: Color = .black
}

public class RenderPassDepthStencilAttachmentDescriptor : RenderPassAttachmentDescriptor {
    var clearDepth: Float = 1.0
    var clearStencil: UInt32 = 0
}

public struct RenderPassDescriptor {
    var colorAttachments: [RenderPassColorAttachmentDescriptor]
    var depthStencilAttachment: RenderPassDepthStencilAttachmentDescriptor

    var numberOfActiveLayers: UInt64 = 0
}
