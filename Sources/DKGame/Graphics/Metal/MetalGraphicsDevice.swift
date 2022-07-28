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
#if os(macOS) || targetEnvironment(macCatalyst)
            let devices = MTLCopyAllDevices()
            for dev in devices {
                if name.caseInsensitiveCompare(dev.name) == .orderedSame {
                    device = dev
                    break
                }
            }
#endif
            if device == nil {
                device = MTLCreateSystemDefaultDevice()
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
        return MetalShaderBindingSet(device: self, layout: layout.bindings)
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
        let pixelFormat = descriptor.pixelFormat.mtlPixelFormat()
        let arrayLength = descriptor.arrayLength

        if arrayLength == 0 {
            Log.err("MetalGraphicsDevice.makeTexture error: Invalid array length!")
            return nil
        }
        if pixelFormat == .invalid {
            Log.err("MetalGraphicsDevice.makeTexture error: Invalid pixel format!")
            return nil
        }

        let desc = MTLTextureDescriptor()
        switch descriptor.textureType {
        case .type1D:
            desc.textureType = (arrayLength > 1) ? .type1DArray : .type1D
        case .type2D:
            desc.textureType = (arrayLength > 1) ? .type2DArray : .type2D
        case .typeCube:
            desc.textureType = (arrayLength > 1) ? .typeCubeArray : .typeCube
        case .type3D:
            desc.textureType = .type3D
        case .unknown:
            Log.err("MetalGraphicsDevice.makeTexture error: Unknown texture type!")
            return nil
        }
        desc.pixelFormat = pixelFormat
        desc.width = descriptor.width
        desc.height = descriptor.height
        desc.depth = descriptor.depth
        desc.mipmapLevelCount = descriptor.mipmapLevels
        desc.sampleCount = descriptor.sampleCount
        desc.arrayLength = arrayLength
        //desc.resourceOptions = .storageModePrivate
        desc.cpuCacheMode = .defaultCache
        desc.storageMode = .private
        desc.allowGPUOptimizedContents = true

        desc.usage = [] // MTLTextureUsageUnknown
        if descriptor.usage.intersection([.sampled, .shaderRead]).isEmpty == false {
            desc.usage.insert(.shaderRead)
        }
        if descriptor.usage.intersection([.storage, .shaderWrite]).isEmpty == false {
            desc.usage.insert(.shaderWrite)
        }
        if descriptor.usage.contains(.renderTarget) {
            desc.usage.insert(.renderTarget)
        }
        if descriptor.usage.contains(.pixelFormatView) {
            desc.usage.insert(.pixelFormatView) // view with a different pixel format.
        }

        if let texture = device.makeTexture(descriptor: desc) {
            return MetalTexture(device: self, texture: texture)
        } else {
            Log.err("MTLDevice.makeTexture failed!")
        }

        return nil
    }

    public func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState? {
        let addressMode = { (m: SamplerAddressMode) -> MTLSamplerAddressMode in
            switch m {
            case .clampToEdge:      return .clampToEdge
            case .repeat:           return .repeat
            case .mirrorRepeat:     return .mirrorRepeat
            case .clampToZero:      return .clampToZero
            }
        }
        let minMagFilter = { (f: SamplerMinMagFilter) -> MTLSamplerMinMagFilter in
            switch f {
            case .nearest:      return .nearest
            case .linear:       return .linear
            }
        }
        let mipFilter = { (f: SamplerMipFilter) -> MTLSamplerMipFilter in
            switch f {
            case .notMipmapped:     return .notMipmapped
            case .nearest:          return .nearest
            case .linear:           return .linear
            }
        }
        let compareFunction = { (fn: CompareFunction) -> MTLCompareFunction in
            switch fn {
            case .never:            return .never
            case .less:             return .less
            case .equal:            return .equal
            case .lessEqual:        return .lessEqual
            case .greater:          return .greater
            case .notEqual:         return .notEqual
            case .greaterEqual:     return .greaterEqual
            case .always:           return .always
            }
        }

        let desc = MTLSamplerDescriptor()
        desc.sAddressMode = addressMode(descriptor.addressModeU)
        desc.tAddressMode = addressMode(descriptor.addressModeV)
        desc.rAddressMode = addressMode(descriptor.addressModeW)
        desc.minFilter = minMagFilter(descriptor.minFilter)
        desc.magFilter = minMagFilter(descriptor.magFilter)
        desc.mipFilter = mipFilter(descriptor.mipFilter)
        desc.lodMinClamp = descriptor.minLod
        desc.lodMaxClamp = descriptor.maxLod
        desc.maxAnisotropy = descriptor.maxAnisotropy
        desc.normalizedCoordinates = descriptor.normalizedCoordinates
        if descriptor.normalizedCoordinates == false {
            desc.magFilter = desc.minFilter
            desc.sAddressMode = .clampToEdge
            desc.tAddressMode = .clampToEdge
            desc.rAddressMode = .clampToEdge
            desc.mipFilter = .notMipmapped
            desc.maxAnisotropy = 1
        }
        desc.compareFunction = compareFunction(descriptor.compareFunction)

        if let samplerState = device.makeSamplerState(descriptor: desc) {
            return MetalSamplerState(device: self, sampler: samplerState)
        } else {
            Log.err("MTLDevice.makeSamplerState failed.")
        }
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
