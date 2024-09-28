//
//  File: MetalDepthStencilState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalDepthStencilState: DepthStencilState {
    public let device: GraphicsDevice

    let depthStencilState: MTLDepthStencilState

    init(device: MetalGraphicsDevice, depthStencilState: MTLDepthStencilState) {
        self.device = device
        self.depthStencilState = depthStencilState
    }
}
#endif //if ENABLE_METAL
