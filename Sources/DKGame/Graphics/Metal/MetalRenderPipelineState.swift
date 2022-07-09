//
//  File: MetalRenderPipelineState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalRenderPipelineState: RenderPipelineState {
    public let device: GraphicsDevice

    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState

    let primitiveType: MTLPrimitiveType
    let depthClipMode: MTLDepthClipMode
    let triangleFillMode: MTLTriangleFillMode
    let frontFacingWinding: MTLWinding
    let cullMode: MTLCullMode

    let vertexBindings: MetalStageResourceBindingMap
    let fragmentBindings: MetalStageResourceBindingMap


    init(device: MetalGraphicsDevice, pipelineState: MTLRenderPipelineState, depthStencilState: MTLDepthStencilState) {
        self.device = device
        self.pipelineState = pipelineState
        self.depthStencilState = depthStencilState

        self.primitiveType = .triangle
        self.depthClipMode = .clip
        self.triangleFillMode = .fill
        self.frontFacingWinding = .counterClockwise
        self.cullMode = .none

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
