//
//  File: MetalBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

final class MetalBuffer: GPUBuffer {
    public let device: GraphicsDevice
    public var length: Int { buffer.length }

    let buffer: MTLBuffer

    init(device: MetalGraphicsDevice, buffer: MTLBuffer) {
        self.device = device
        self.buffer = buffer
    }

    public func contents() -> UnsafeMutableRawPointer? {
        return self.buffer.contents()
    }

    public func flush() {
#if os(macOS) || targetEnvironment(macCatalyst)
        if buffer.storageMode == .managed {
            buffer.didModifyRange(0..<buffer.length)
        }
#endif
    }
}
#endif //if ENABLE_METAL
