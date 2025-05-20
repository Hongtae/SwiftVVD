//
//  File: MetalComputePipelineState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalComputePipelineState: ComputePipelineState {
    let device: GraphicsDevice

    let pipelineState: MTLComputePipelineState
    let bindings: MetalStageResourceBindingMap
    let workgroupSize: MTLSize

    init(device: MetalGraphicsDevice, pipelineState: MTLComputePipelineState, workgroupSize: MTLSize) {
        self.device = device
        self.pipelineState = pipelineState
        self.workgroupSize = workgroupSize

        self.bindings = MetalStageResourceBindingMap(
            resourceBindings: [],
            inputAttributeIndexOffset: 0,
            pushConstantIndex: 0,
            pushConstantOffset: 0,
            pushConstantSize: 0,
            pushConstantBufferSize: 0)
    }

    init(device: MetalGraphicsDevice,
         pipelineState: MTLComputePipelineState,
         workgroupSize: MTLSize,
         bindings: MetalStageResourceBindingMap) {
        self.device = device
        self.pipelineState = pipelineState
        self.workgroupSize = workgroupSize
        self.bindings = bindings
    }
}
#endif //if ENABLE_METAL
