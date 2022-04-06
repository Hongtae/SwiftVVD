public struct ShaderFunctionConstant {
    var name: String
    var type: ShaderDataType
    var index: UInt32
    var required: Bool
}

public protocol ShaderFunction {
    var stageInputAttributes: [ShaderAttribute] { get }
    var functionConstants: [String: ShaderFunctionConstant] { get }
    var functionName: String { get }
    var stage: ShaderStage { get }

    var device: GraphicsDevice { get }
}
