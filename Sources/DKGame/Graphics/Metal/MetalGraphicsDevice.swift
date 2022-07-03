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
    public var name: String { "" }

    public func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue? {
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
        return nil
    }

    public func makeTexture(descriptor: TextureDescriptor) -> Texture? {
        return nil
    }

    public func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState? {
        return nil
    }

    public func makeEvent() -> Event? {
        return nil
    }

    public func makeSemaphore() -> Semaphore? {
        return nil
    }

}
#endif //if ENABLE_METAL
