//
//  File: MetalEvent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalEvent: Event {
    public let device: GraphicsDevice
    let event: MTLEvent

    let waitValue: AtomicNumber64
    let signalValue: AtomicNumber64

    init(device: MetalGraphicsDevice, event: MTLEvent) {
        self.device = device
        self.event = event
        self.waitValue = AtomicNumber64(0)
        self.signalValue = AtomicNumber64(0)
    }

    func nextWaitValue() -> UInt64 {
        UInt64(bitPattern: waitValue.increment())
    }

    func nextSignalValue() -> UInt64 {
        UInt64(bitPattern: signalValue.increment())
    }
}
#endif //if ENABLE_METAL
