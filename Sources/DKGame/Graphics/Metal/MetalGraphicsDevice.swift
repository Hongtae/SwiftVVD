//
//  File: MetalGraphicsDevice.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_METAL
import Foundation
import Metal

public class MetalGraphicsDevice: GraphicsDevice {

    public var name: String { device.name }
    let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    init?(name: String) {
        var device: MTLDevice? = nil

        if name.isEmpty {
            device = MTLCreateSystemDefaultDevice()
        } else {
            let devices = MTLCopyAllDevices()
            for dev in devices {
                if name.caseInsensitiveCompare(dev.name) == .orderedSame {
                    device = dev
                    break
                }
            }
        }

        if let device = device {
            self.device = device
        } else {
            return nil
        }
    }

    public func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue? {
        if let queue = self.device.makeCommandQueue() {
            return MetalCommandQueue(device: self, queue: queue)
        }
        return nil
    }

    public func makeShaderModule(from: Shader) -> ShaderModule? {
        return nil
    }

    public func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet? {
        return nil
    }

    public func makeRenderPipelineState(descriptor: RenderPipelineDescriptor, reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState? {
        return nil
    }

    public func makeComputePipelineState(descriptor: ComputePipelineDescriptor, reflection: UnsafeMutablePointer<PipelineReflection>?) -> ComputePipelineState? {
        return nil
    }

    public func makeBuffer(length: Int, storageMode: StorageMode, cpuCacheMode: CPUCacheMode) -> Buffer? {
        if length > 0 {
            var options: MTLResourceOptions = []
            switch storageMode {
            case .shared:
                options.insert(.storageModeShared)
            case .private:
                options.insert(.storageModePrivate)
            }
            switch cpuCacheMode {
            case .defaultCache:
                break
            case .writeCombined:
                options.insert(.cpuCacheModeWriteCombined)
            }

            if let buffer = device.makeBuffer(length: length, options: options) {
                return MetalBuffer(device: self, buffer: buffer)
            } else
            {
                Log.err("MTLDevice.makeBuffer failed.")
            }
        }
        return nil
    }

    public func makeTexture(descriptor: TextureDescriptor) -> Texture? {
        return nil
    }

    public func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState? {
        return nil
    }

    public func makeEvent() -> Event? {
        if let event = device.makeEvent() {
            return MetalEvent(device: self, event: event)
        }
        return nil
    }

    public func makeSemaphore() -> Semaphore? {
        if let event = device.makeEvent() {
            return MetalSemaphore(device: self, event: event)
        }
        return nil
    }

}
#endif //if ENABLE_METAL
