//
//  File: MetalComputePipelineState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalComputePipelineState: ComputePipelineState {
    public let device: GraphicsDevice

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

}
#endif //if ENABLE_METAL
