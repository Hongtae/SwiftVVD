public struct ShaderBinding {
    var binding : UInt32
    var type : ShaderDescriptorType
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
    func setBuffer(_: Buffer, offset: UInt64, length: UInt64, binding: UInt32)
    func setBufferArray(_ : [GPUBufferBindingInfo], binding: UInt32)

    // bind textures
    func setTexture(_: Texture, binding: UInt32)
    func setTextureArray(_: [Texture], binding: UInt32)

    // bind samplers
    func setSamplerState(_: SamplerState, binding: UInt32)
    func setSamplerStateArray(_: [SamplerState], binding: UInt32)

    var device: GraphicsDevice { get }
}
