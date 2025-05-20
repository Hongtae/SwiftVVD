//
//  File: MetalBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalBuffer: GPUBuffer {
    let device: GraphicsDevice
    var length: Int { buffer.length }

    let buffer: MTLBuffer

    init(device: MetalGraphicsDevice, buffer: MTLBuffer) {
        self.device = device
        self.buffer = buffer
    }

    func contents() -> UnsafeMutableRawPointer? {
        return self.buffer.contents()
    }

    func flush() {
#if os(macOS) || targetEnvironment(macCatalyst)
        if buffer.storageMode == .managed {
            buffer.didModifyRange(0..<buffer.length)
        }
#endif
    }
}
#endif //if ENABLE_METAL
