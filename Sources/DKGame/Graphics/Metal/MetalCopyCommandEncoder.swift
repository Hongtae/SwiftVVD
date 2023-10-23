//
//  File: MetalCopyCommandEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalCopyCommandEncoder: CopyCommandEncoder {

    struct EncodingState {
        let encoder: Encoder
    }
    
    class Encoder: MetalCommandEncoder {
        typealias Command = (MTLBlitCommandEncoder, inout EncodingState)->Void
        var commands: [Command] = []
        var events: [Event] = []
        var semaphores: [Semaphore] = []

        var waitEvents: Set<MetalHashable<MetalEvent>> = []
        var signalEvents: Set<MetalHashable<MetalEvent>> = []
        var waitSemaphores: [MetalHashable<MetalSemaphore>: UInt64] = [:]
        var signalSemaphores: [MetalHashable<MetalSemaphore>: UInt64] = [:]

        override init() {
            super.init()
            self.commands.reserveCapacity(self.initialNumberOfCommands)
        }

        override func encode(_ buffer: MTLCommandBuffer) -> Bool {
            if let encoder = buffer.makeBlitCommandEncoder() {
                self.waitEvents.forEach {
                    let event: MetalEvent = $0.object
                    buffer.encodeWaitForEvent(event.event,
                                              value: event.nextWaitValue())
                }
                self.waitSemaphores.forEach { (key, value) in
                    let event: MetalSemaphore = key.object
                    buffer.encodeWaitForEvent(event.event, value: value)
                }

                var state = EncodingState(encoder: self)
                self.commands.forEach { $0(encoder, &state) }
                encoder.endEncoding()

                self.signalEvents.forEach {
                    let event: MetalEvent = $0.object
                    buffer.encodeSignalEvent(event.event,
                                             value: event.nextSignalValue())
                }
                self.signalSemaphores.forEach { (key, value) in
                    let event: MetalSemaphore = key.object
                    buffer.encodeSignalEvent(event.event, value: value)
                }

                return true
            }
            return false
        }
    }

    private var encoder: Encoder?
    public let commandBuffer: CommandBuffer

    init(buffer: MetalCommandBuffer) {
        self.commandBuffer = buffer
        self.encoder = Encoder()
    }

    public func copy(from src: Buffer, sourceOffset: Int, to dst: Buffer, destinationOffset: Int, size: Int) {
        assert(self.encoder != nil)
        assert(src is MetalBuffer)
        assert(dst is MetalBuffer)

        if let src = src as? MetalBuffer, let dst = dst as? MetalBuffer,
           let encoder = self.encoder {

            encoder.commands.append {
                (encoder: MTLBlitCommandEncoder, state: inout EncodingState) in

                encoder.copy(from: src.buffer,
                             sourceOffset: sourceOffset,
                             to: dst.buffer,
                             destinationOffset: destinationOffset,
                             size: size)
            }
        }
    }

    public func copy(from src: Buffer, sourceOffset: BufferImageOrigin, to dst: Texture, destinationOffset: TextureOrigin, size: TextureSize) {
        assert(self.encoder != nil)
        assert(src is MetalBuffer)
        assert(dst is MetalTexture)

        if let src = src as? MetalBuffer, let dst = dst as? MetalTexture,
           let encoder = self.encoder {

            encoder.commands.append {
                (encoder: MTLBlitCommandEncoder, state: inout EncodingState) in

                let buffer = src.buffer
                let texture = dst.texture

                let bytesPerPixel = dst.pixelFormat.bytesPerPixel
                assert(bytesPerPixel > 0)
                let bytesPerRow = sourceOffset.imageWidth * bytesPerPixel
                assert(bytesPerRow > 0)
                let bytesPerImage = bytesPerRow * sourceOffset.imageHeight
                assert(bytesPerImage > 0)

                encoder.copy(from: buffer,
                             sourceOffset: sourceOffset.offset,
                             sourceBytesPerRow: bytesPerRow,
                             sourceBytesPerImage: bytesPerImage,
                             sourceSize: MTLSize(width: size.width,
                                                 height: size.height,
                                                 depth: size.depth),
                             to: texture,
                             destinationSlice: destinationOffset.layer,
                             destinationLevel: destinationOffset.level,
                             destinationOrigin: MTLOrigin(x: destinationOffset.x,
                                                          y: destinationOffset.y,
                                                          z: destinationOffset.z))
            }
        }
    }

    public func copy(from src: Texture, sourceOffset: TextureOrigin, to dst: Buffer, destinationOffset: BufferImageOrigin, size: TextureSize) {
        assert(self.encoder != nil)
        assert(src is MetalTexture)
        assert(dst is MetalBuffer)

        if let src = src as? MetalTexture, let dst = dst as? MetalBuffer,
           let encoder = self.encoder {

            encoder.commands.append {
                (encoder: MTLBlitCommandEncoder, state: inout EncodingState) in

                let texture = src.texture
                let buffer = dst.buffer

                let bytesPerPixel = src.pixelFormat.bytesPerPixel
                assert(bytesPerPixel > 0)
                let bytesPerRow = destinationOffset.imageWidth * bytesPerPixel
                assert(bytesPerRow > 0)
                let bytesPerImage = bytesPerRow * destinationOffset.imageHeight
                assert(bytesPerImage > 0)

                encoder.copy(from: texture,
                             sourceSlice: sourceOffset.layer,
                             sourceLevel: sourceOffset.level,
                             sourceOrigin: MTLOrigin(x: sourceOffset.x,
                                                     y: sourceOffset.y,
                                                     z: sourceOffset.z),
                             sourceSize: MTLSize(width: size.width,
                                                 height: size.height,
                                                 depth: size.depth),
                             to: buffer,
                             destinationOffset: destinationOffset.offset,
                             destinationBytesPerRow: bytesPerRow,
                             destinationBytesPerImage: bytesPerImage)
            }
        }
    }

    public func copy(from src: Texture, sourceOffset: TextureOrigin, to dst: Texture, destinationOffset: TextureOrigin, size: TextureSize) {
        assert(self.encoder != nil)
        assert(src is MetalTexture)
        assert(dst is MetalTexture)

        if let src = src as? MetalTexture, let dst = dst as? MetalTexture,
           let encoder = self.encoder {

            encoder.commands.append {
                (encoder: MTLBlitCommandEncoder, state: inout EncodingState) in

                encoder.copy(from: src.texture,
                             sourceSlice: sourceOffset.layer,
                             sourceLevel: sourceOffset.level,
                             sourceOrigin: MTLOrigin(x: sourceOffset.x,
                                                     y: sourceOffset.y,
                                                     z: sourceOffset.z),
                             sourceSize: MTLSize(width: size.width,
                                                 height: size.height,
                                                 depth: size.depth),
                             to: dst.texture,
                             destinationSlice: destinationOffset.layer,
                             destinationLevel: destinationOffset.level,
                             destinationOrigin: MTLOrigin(x: destinationOffset.x,
                                                          y: destinationOffset.y,
                                                          z: destinationOffset.z))
            }
        }
    }

    public func fill(buffer: Buffer, offset: Int, length: Int, value: UInt8) {
        assert(self.encoder != nil)
        assert(buffer is MetalBuffer)

        if let buffer = buffer as? MetalBuffer, let encoder = self.encoder {
            encoder.commands.append {
                (encoder: MTLBlitCommandEncoder, state: inout EncodingState) in

                encoder.fill(buffer: buffer.buffer,
                             range: offset..<(offset+length),
                             value: value)
            }
        }
    }

    public func endEncoding() {
        assert(self.encoder != nil)
        if let commandBuffer = self.commandBuffer as? MetalCommandBuffer,
           let encoder = self.encoder {
            commandBuffer.endEncoder(encoder)
        }
        self.encoder = nil
    }

    public var isCompleted: Bool {
        return self.encoder == nil
    }

    public func waitEvent(_ event: Event) {
        assert(event is MetalEvent)
        assert(self.encoder != nil)
        if let event = event as? MetalEvent, let encoder = self.encoder {
            encoder.events.append(event)
            encoder.waitEvents.insert(MetalHashable(event))
        }
    }

    public func signalEvent(_ event: Event) {
        assert(event is MetalEvent)
        assert(self.encoder != nil)
        if let event = event as? MetalEvent, let encoder = self.encoder {
            encoder.events.append(event)
            encoder.signalEvents.insert(MetalHashable(event))
        }
    }

    public func waitSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {
        assert(semaphore is MetalSemaphore)
        assert(self.encoder != nil)
        if let semaphore = semaphore as? MetalSemaphore,
           let encoder = self.encoder {
            let key = MetalHashable(semaphore)
            if let waitValue = encoder.waitSemaphores[key] {
                if value > waitValue {
                    encoder.waitSemaphores[key] = value
                }
            } else {
                encoder.semaphores.append(semaphore)
                encoder.waitSemaphores[key] = value
            }
        }
    }

    public func signalSemaphoreValue(_ semaphore: Semaphore, value: UInt64) {
        assert(semaphore is MetalSemaphore)
        assert(self.encoder != nil)
        if let semaphore = semaphore as? MetalSemaphore,
           let encoder = self.encoder {
            let key = MetalHashable(semaphore)
            if let signalValue = encoder.signalSemaphores[key] {
                if value > signalValue {
                    encoder.waitSemaphores[key] = value
                }
            } else {
                encoder.semaphores.append(semaphore)
                encoder.signalSemaphores[key] = value
            }
        }
    }
}
#endif //if ENABLE_METAL
