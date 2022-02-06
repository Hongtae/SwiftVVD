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
    var clearColor: Color = Color(red:0.0, green:0.0, blue:0.0, alpha:0.0)
}

public class RenderPassDepthStencilAttachmentDescriptor : RenderPassAttachmentDescriptor {
    var clearDepth: Float = 1.0
    var clearStencil: UInt32 = 0
}
