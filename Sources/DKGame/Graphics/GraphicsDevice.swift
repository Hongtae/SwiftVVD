//
//  File: GraphicsDevice.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol GraphicsDevice {
    var name: String { get }

    func makeCommandQueue(flags: CommandQueueFlags) -> CommandQueue?
    func makeShaderModule(from: Shader) -> ShaderModule?
    func makeShaderBindingSet(layout: ShaderBindingSetLayout) -> ShaderBindingSet?

    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor, reflection: UnsafeMutablePointer<PipelineReflection>?) -> RenderPipelineState?
    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor) -> RenderPipelineState?

    func makeComputePipelineState(descriptor: ComputePipelineDescriptor, reflection: UnsafeMutablePointer<PipelineReflection>?) -> ComputePipelineState?
    func makeComputePipelineState(descriptor: ComputePipelineDescriptor) -> ComputePipelineState?

    func makeDepthStencilState(descriptor: DepthStencilDescriptor) -> DepthStencilState?

    func makeBuffer(length: Int, storageMode: StorageMode, cpuCacheMode: CPUCacheMode) -> GPUBuffer?
    func makeTexture(descriptor: TextureDescriptor) -> Texture?
    func makeTransientRenderTarget(type: TextureType, pixelFormat: PixelFormat, width: Int, height: Int, depth: Int) -> Texture?
    func makeSamplerState(descriptor: SamplerDescriptor) -> SamplerState?

    func makeEvent() -> GPUEvent?
    func makeSemaphore() -> GPUSemaphore?
}

public extension GraphicsDevice {
    func makeRenderPipelineState(descriptor: RenderPipelineDescriptor) -> RenderPipelineState? {
        return self.makeRenderPipelineState(descriptor: descriptor, reflection: nil)
    }

    func makeComputePipelineState(descriptor: ComputePipelineDescriptor) -> ComputePipelineState? {
        return self.makeComputePipelineState(descriptor: descriptor, reflection: nil)
    }
}
