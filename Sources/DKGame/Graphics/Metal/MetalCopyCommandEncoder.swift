//
//  File: MetalCopyCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalCopyCommandEncoder: CopyCommandEncoder {
    public let commandBuffer: CommandBuffer

    init(buffer: MetalCommandBuffer) {
        self.commandBuffer = buffer
    }

    public func copy(from: Buffer, sourceOffset: Int, to: Buffer, destinationOffset: Int, size: Int) {

    }

    public func copy(from: Buffer, sourceOffset: BufferImageOrigin, to: Texture, destinationOffset: TextureOrigin, size: TextureSize) {

    }

    public func copy(from: Texture, sourceOffset: TextureOrigin, to: Buffer, destinationOffset: BufferImageOrigin, size: TextureSize) {

    }

    public func copy(from: Texture, sourceOffset: TextureOrigin, to: Texture, destinationOffset: TextureOrigin, size: TextureSize) {

    }

    public func fill(buffer: Buffer, offset: Int, length: Int, value: UInt8) {

    }

    public func endEncoding() {

    }

    public var isCompleted: Bool {
        return false
    }

    public func waitEvent(_ event: Event) {

    }

    public func signalEvent(_ event: Event) {

    }

    public func waitSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {

    }

    public func signalSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {

    }
}
#endif //if ENABLE_METAL
