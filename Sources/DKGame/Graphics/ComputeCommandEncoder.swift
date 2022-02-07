public protocol ComputeCommandEncoder: CommandEncoder {
    func setResource(set: UInt32, _: ShaderBindingSet)
    func setComputePipelineState(_: ComputePipelineState)

    func pushConstant(stages: [ShaderStage], offset: UInt32, data: UnsafeRawPointer)

    func dispatch(numGroupX: UInt32, numGroupY: UInt32, numGroupZ: UInt32)
}
