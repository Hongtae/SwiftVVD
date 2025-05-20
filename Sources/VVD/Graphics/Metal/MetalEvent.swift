//
//  File: MetalEvent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Synchronization
import Metal

final class MetalEvent: GPUEvent {
    let device: GraphicsDevice
    let event: MTLEvent

    let waitValue = Atomic<UInt64>(0)
    let signalValue = Atomic<UInt64>(0)

    init(device: MetalGraphicsDevice, event: MTLEvent) {
        self.device = device
        self.event = event
    }

    func nextWaitValue() -> UInt64 {
        waitValue.add(1, ordering: .sequentiallyConsistent).newValue
    }

    func nextSignalValue() -> UInt64 {
        signalValue.add(1, ordering: .sequentiallyConsistent).newValue
    }
}
#endif //if ENABLE_METAL
