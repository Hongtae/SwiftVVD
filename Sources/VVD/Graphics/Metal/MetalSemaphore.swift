//
//  File: MetalSemaphore.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalSemaphore: GPUSemaphore {
    let device: GraphicsDevice
    let event: MTLEvent

    init(device: MetalGraphicsDevice, event: MTLEvent) {
        self.device = device
        self.event = event
    }
}
#endif //if ENABLE_METAL
