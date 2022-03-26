public struct ComputePipelineDescriptor {
    var computeFunction: ShaderFunction
    var deferCompile: Bool = false
    var disableOptimization: Bool = false
}

public protocol ComputePipelineState {
    var device: GraphicsDevice { get }
}
