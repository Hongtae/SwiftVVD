import Foundation

public enum VisibilityResultMode {
    case disabled
    case boolean
    case counting
}

public struct Viewport {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    public var nearZ: Float
    public var farZ: Float

    public init(x: Float,
                y: Float,
                width: Float,
                height: Float,
                nearZ: Float,
                farZ: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.nearZ = nearZ
        self.farZ = farZ
    }
}

public protocol RenderCommandEncoder: CommandEncoder {
    func setResource(_: ShaderBindingSet, atIndex: UInt32)
    func setViewport(_: Viewport)
    func setRenderPipelineState(_: RenderPipelineState)
    func setVertexBuffer(_: Buffer, offset: UInt64, index: UInt32)
    func setVertexBuffers(_: [Buffer], offsets: [UInt64], index: UInt32)
    func setIndexBuffer(_: Buffer, offset: UInt64, type: IndexType)
    
    func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: UInt32, data: D)

    func draw(numVertices: Int, numInstances: Int, baseVertex: Int, baseInstance: Int)
    func drawIndexed(numIndices: Int, numInstances: Int, indexOffset: Int, vertexOffset: Int, baseInstance: Int)
}
