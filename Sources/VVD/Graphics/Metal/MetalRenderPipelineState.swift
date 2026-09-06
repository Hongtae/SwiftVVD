//
//  File: MetalRenderPipelineState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalRenderPipelineState: RenderPipelineState {
    let device: GraphicsDevice

    let pipelineState: MTLRenderPipelineState

    let primitiveType: MTLPrimitiveType
    let triangleFillMode: MTLTriangleFillMode

    let vertexBindings: MetalStageResourceBindingMap
    let fragmentBindings: MetalStageResourceBindingMap

    init(device: MetalGraphicsDevice,
         pipelineState: MTLRenderPipelineState,
         primitiveType: MTLPrimitiveType,
         triangleFillMode: MTLTriangleFillMode,
         vertexBindings: MetalStageResourceBindingMap?,
         fragmentBindings: MetalStageResourceBindingMap?) {
        self.device = device
        self.pipelineState = pipelineState

        self.primitiveType = primitiveType
        self.triangleFillMode = triangleFillMode

        self.vertexBindings = vertexBindings ?? MetalStageResourceBindingMap(
            resourceBindings: [],
            inputAttributeIndexOffset: 0,
            pushConstantIndex: 0,
            pushConstantOffset: 0,
            pushConstantSize: 0,
            pushConstantBufferSize: 0)

        self.fragmentBindings = fragmentBindings ?? MetalStageResourceBindingMap(
            resourceBindings: [],
            inputAttributeIndexOffset: 0,
            pushConstantIndex: 0,
            pushConstantOffset: 0,
            pushConstantSize: 0,
            pushConstantBufferSize: 0)
    }
}
#endif //if ENABLE_METAL
