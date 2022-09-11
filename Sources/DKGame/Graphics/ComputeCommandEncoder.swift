//
//  File: ComputeCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol ComputeCommandEncoder: CommandEncoder {
    func setResource(_: ShaderBindingSet, atIndex: Int)
    func setComputePipelineState(_: ComputePipelineState)

    func pushConstant<D: DataProtocol>(stages: ShaderStageFlags, offset: Int, data: D)

    func dispatch(numGroupX: Int, numGroupY: Int, numGroupZ: Int)
}
