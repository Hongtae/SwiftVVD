import Foundation

public enum VisibilityResultMode {
    case disabled
    case boolean
    case counting
}

public struct Viewport {
    var x: Float
    var y: Float
    var width: Float
    var height: Float
    var nearZ: Float
    var farZ: Float
}

public protocol RenderCommandEncoder: CommandEncoder {
    func setResource(_: ShaderBindingSet, atIndex: UInt32)
    func setViewport(_: Viewport)
    func setRenderPipelineState(_: RenderPipelineState)
    func setVertexBuffer(_: Buffer, offset: UInt64, index: UInt32)
    func setVertexBuffers(_: [Buffer], offsets: [UInt64], index: UInt32)
    func setIndexBuffer(_: Buffer, offset: UInt64, type: IndexType)
    
    func pushConstant<D: DataProtocol>(stages: [ShaderStage], offset: UInt32, data: D)

    func draw(numVertices: UInt32, numInstances: UInt32, baseVertex: UInt32, baseInstance: UInt32)
    func drawIndexed(numIndices: UInt32, numInstances: UInt32, indexOffset: UInt32, vertexOffset: Int32, baseInstance: UInt32)
}
