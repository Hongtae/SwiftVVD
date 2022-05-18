import Foundation

public protocol ComputeCommandEncoder: CommandEncoder {
    func setResource(_: ShaderBindingSet, atIndex: UInt32)
    func setComputePipelineState(_: ComputePipelineState)

    func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: UInt32, data: D)

    func dispatch(numGroupX: UInt32, numGroupY: UInt32, numGroupZ: UInt32)
}
