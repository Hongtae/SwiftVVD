//
//  File: MetalRenderPipelineState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalRenderPipelineState: RenderPipelineState {
    public let device: GraphicsDevice

    let pipelineState: MTLRenderPipelineState

    var primitiveType: MTLPrimitiveType
    var triangleFillMode: MTLTriangleFillMode

    var vertexBindings: MetalStageResourceBindingMap
    var fragmentBindings: MetalStageResourceBindingMap

    init(device: MetalGraphicsDevice, pipelineState: MTLRenderPipelineState) {
        self.device = device
        self.pipelineState = pipelineState

        self.primitiveType = .triangle
        self.triangleFillMode = .fill

        self.vertexBindings = MetalStageResourceBindingMap(
            resourceBindings: [],
            inputAttributeIndexOffset: 0,
            pushConstantIndex: 0,
            pushConstantOffset: 0,
            pushConstantSize: 0,
            pushConstantBufferSize: 0)

        self.fragmentBindings = MetalStageResourceBindingMap(
            resourceBindings: [],
            inputAttributeIndexOffset: 0,
            pushConstantIndex: 0,
            pushConstantOffset: 0,
            pushConstantSize: 0,
            pushConstantBufferSize: 0)
    }
}
#endif //if ENABLE_METAL
