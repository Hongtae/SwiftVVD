//
//  File: ShaderBindingSet.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct ShaderBinding {
    public var binding: Int
    public var type: ShaderDescriptorType
    public var arrayLength: Int
    public var immutableSamplers: SamplerState?

    public init(binding: Int,
                type: ShaderDescriptorType,
                arrayLength: Int,
                immutableSamplers: SamplerState? = nil) {
        self.binding = binding
        self.type = type
        self.arrayLength = arrayLength
        self.immutableSamplers = immutableSamplers
    }
}

public struct ShaderBindingSetLayout {
    public typealias Binding = ShaderBinding
    public var bindings: [Binding]

    public init(bindings: [Binding]) {
        self.bindings = bindings
    }
}

public struct BufferBindingInfo {
    public var buffer: GPUBuffer
    public var offset: Int
    public var length: Int

    public init(buffer: GPUBuffer,
                offset: Int,
                length: Int) {
        self.buffer = buffer
        self.offset = offset
        self.length = length
    }
}

public protocol ShaderBindingSet {
    // bind buffers
    func setBuffer(_: GPUBuffer, offset: Int, length: Int, binding: Int)
    func setBufferArray(_ : [BufferBindingInfo], binding: Int)

    // bind textures
    func setTexture(_: Texture, binding: Int)
    func setTextureArray(_: [Texture], binding: Int)

    // bind samplers
    func setSamplerState(_: SamplerState, binding: Int)
    func setSamplerStateArray(_: [SamplerState], binding: Int)

    var device: GraphicsDevice { get }
}
