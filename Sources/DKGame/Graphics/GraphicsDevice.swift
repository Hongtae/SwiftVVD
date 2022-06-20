//
//  File: GraphicsDevice.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public enum CPUCacheMode: UInt {
    case defaultCache   // read write
    case writeCombined  // write only
}

public protocol Event {
    var device: GraphicsDevice { get }
}

public protocol Semaphore {
    var device: GraphicsDevice { get }
}

public protocol GraphicsDevice {
    var name: String { get }

    func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue?
    func makeShaderModule(from: Shader) -> ShaderModule?
    func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet?

    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor, reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState?
    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor) -> RenderPipelineState?

    func makeComputePipelineState(descriptor: ComputePipelineDescriptor, reflection: UnsafeMutablePointer<PipelineReflection>?) -> ComputePipelineState?
    func makeComputePipelineState(descriptor: ComputePipelineDescriptor) -> ComputePipelineState?

    func makeBuffer(length: Int, storageMode: StorageMode, cpuCacheMode: CPUCacheMode) -> Buffer?
    func makeTexture(descriptor: TextureDescriptor) -> Texture?
    func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState?

    func makeEvent() -> Event?
    func makeSemaphore() -> Semaphore?
}

public extension GraphicsDevice {
    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor) -> RenderPipelineState? {
        return self.makeRenderPipelineState(descriptor: descriptor, reflection: nil)
    }

    func makeComputePipelineState(descriptor: ComputePipelineDescriptor) -> ComputePipelineState? {
        return self.makeComputePipelineState(descriptor: descriptor, reflection: nil)
    }
}
