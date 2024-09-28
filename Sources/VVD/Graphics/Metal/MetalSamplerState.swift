//
//  File: MetalSamplerState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalSamplerState: SamplerState {
    public let device: GraphicsDevice
    let sampler: MTLSamplerState

    init(device: MetalGraphicsDevice, sampler: MTLSamplerState) {
        self.device = device
        self.sampler = sampler
    }
}
#endif //if ENABLE_METAL
