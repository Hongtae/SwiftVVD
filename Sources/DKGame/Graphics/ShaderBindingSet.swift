public struct ShaderBinding {
    var binding : UInt32
    var type : Shader.DescriptorType
    var arrayLength : UInt32
    var immutableSamplers : SamplerState?
}

public struct ShaderBindingSetLayout {
    public typealias Binding = ShaderBinding
    var bindings : [Binding]
}

public struct GPUBufferBindingInfo {
    var buffer : Buffer
    var offset : UInt64
    var length : UInt64
}

public protocol ShaderBindingSet {
    // bind buffers
    func setBuffer(binding: UInt32, buffer: Buffer, offset: UInt64, length: UInt64)
    func setBufferArray(binding: UInt32, buffers: [GPUBufferBindingInfo])

    // bind textures
    func setTexture(binding: UInt32, texture: Texture)
    func setTextureArray(binding: UInt32, textures: [Texture])

    // bind samplers
    func setSamplerState(binding: UInt32, sampler: SamplerState)
    func setSamplerStateArray(binding: UInt32, samplers: [SamplerState])
}
