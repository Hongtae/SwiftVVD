public struct ShaderBinding {
    public var binding: UInt32
    public var type: ShaderDescriptorType
    public var arrayLength: UInt32
    public var immutableSamplers: SamplerState?

    public init(binding: UInt32,
                type: ShaderDescriptorType,
                arrayLength: UInt32,
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

public struct GPUBufferBindingInfo {
    public var buffer: Buffer
    public var offset: UInt64
    public var length: UInt64

    public init(buffer: Buffer,
                offset: UInt64,
                length: UInt64) {
        self.buffer = buffer
        self.offset = offset
        self.length = length
    }
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
