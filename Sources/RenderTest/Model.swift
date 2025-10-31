import Foundation
import VVD
import TinyGLTF

struct TriangleFace {
    struct Vertex {
        let pos: Vector3
        let uv: Vector2
        let color: Vector4
    }
    let vertices: (Vertex, Vertex, Vertex)
    let material: Material?
}

struct Model {
    struct Scene {
        var name: String
        var nodes: [SceneNode]
    }

    var scenes: [Scene]
    var defaultSceneIndex: Int

    func triangleList(scene: Int, deviceContext: GraphicsDeviceContext) -> [Triangle] {
        func meshTriangles(mesh: Mesh, transform: Matrix4) -> [Triangle] {
            if mesh.primitiveType != .triangle && mesh.primitiveType != .triangleStrip {
                return []
            }

            var triangles: [Triangle] = []
            var positions: [Vector3] = []

            _ = mesh.enumerateVertexBufferContent(semantic: .position,
                                                  context: deviceContext) {
                data, format, index in
                if format == .float3 {
                    let v = data.assumingMemoryBound(to: Float3.self).pointee
                    positions.append(Vector3(v).applying(transform, w: 1.0))
                    return true
                }
                return false
            }
            var indices: [Int] = []
            if mesh.indexBuffer != nil {
                indices.reserveCapacity(mesh.indexCount)
                _ = mesh.enumerateIndexBufferContent(context: deviceContext) {
                    indices.append($0)
                    return true
                }
            } else {
                indices = positions.indices.map { Int($0) }
            }

            if mesh.primitiveType == .triangleStrip {
                let numTris = indices.count > 2 ? indices.count - 2 : 0
                triangles.reserveCapacity(numTris)

                (0..<numTris).forEach { i in
                    var idx = (indices[i], indices[i+1], indices[i+2])
                    if i % 2 != 0 {
                        swap(&idx.0, &idx.1)
                    }
                    let t = Triangle(positions[idx.0], positions[idx.1], positions[idx.2])
                    triangles.append(t)
                }
            } else {
                let numTris = indices.count / 3
                triangles.reserveCapacity(numTris)
                (0..<numTris).forEach { i in
                    let idx = (indices[i*3], indices[i*3+1], indices[i*3+2])
                    let t = Triangle(positions[idx.0], positions[idx.1], positions[idx.2])
                    triangles.append(t)
                }
            }
            return triangles
        }

        if scene >= 0 && scene < self.scenes.count {
            var triangles: [Triangle] = []
            self.scenes[scene].forEachNode { node, transform in
                if let mesh = node.mesh {
                    let tm = AffineTransform3.identity
                        .scaled(by: node.scale)
                        .matrix4
                        .concatenating(transform.matrix4)

                    let tris = meshTriangles(mesh: mesh, transform: tm)
                    triangles.append(contentsOf: tris)
                }
            }
            return triangles
        }
        return []
    }

    func faceList(scene: Int, deviceContext: GraphicsDeviceContext) -> [TriangleFace] {
        func meshFaces(mesh: Mesh, transform: Matrix4) -> [TriangleFace] {
            if mesh.primitiveType != .triangle && mesh.primitiveType != .triangleStrip {
                return []
            }

            var faces: [TriangleFace] = []

            var positions: [Vector3] = []
            _ = mesh.enumerateVertexBufferContent(semantic: .position,
                                                  context: deviceContext) {
                data, format, index in
                if format == .float3 {
                    let v = data.assumingMemoryBound(to: Float3.self).pointee
                    positions.append(Vector3(v).applying(transform, w: 1.0))
                    return true
                }
                return false
            }
            var uvs: [Vector2] = []
            _ = mesh.enumerateVertexBufferContent(semantic: .textureCoordinates,
                                                  context: deviceContext) {
                data, format, index in
                if format == .float2 {
                    let v = data.assumingMemoryBound(to: Float2.self).pointee
                    uvs.append(Vector2(v))
                    return true
                }
                return false
            }
            var colors: [Vector4] = []
            _ = mesh.enumerateVertexBufferContent(semantic: .color,
                                                  context: deviceContext, {
                data, format, index in
                func normalize<T: FixedWidthInteger>(_ buffer: UnsafePointer<T>,
                                                     _ count: Int) -> Vector4 {
                    var vec = Vector4(0, 0, 0, 1)
                    let inv = Double(1.0) / Double(T.max)
                    (0..<(min(4, count))).forEach { i in
                        let v = Double(buffer[i]) * inv
                        vec[i] = Scalar(v)
                    }
                    return vec
                }

                switch format {
                case .char3, .char3Normalized:
                    let v = normalize(data.assumingMemoryBound(to: Int8.self), 3)
                    colors.append(v)
                case .uchar3, .uchar3Normalized:
                    let v = normalize(data.assumingMemoryBound(to: UInt8.self), 3)
                    colors.append(v)
                case .char4, .char4Normalized:
                    let v = normalize(data.assumingMemoryBound(to: Int8.self), 4)
                    colors.append(v)
                case .uchar4, .uchar4Normalized:
                    let v = normalize(data.assumingMemoryBound(to: UInt8.self), 4)
                    colors.append(v)
                case .short3, .short3Normalized:
                    let v = normalize(data.assumingMemoryBound(to: Int16.self), 3)
                    colors.append(v)
                case .ushort3, .ushort3Normalized:
                    let v = normalize(data.assumingMemoryBound(to: UInt16.self), 3)
                    colors.append(v)
                case .short4, .short4Normalized:
                    let v = normalize(data.assumingMemoryBound(to: Int16.self), 4)
                    colors.append(v)
                case .ushort4, .ushort4Normalized:
                    let v = normalize(data.assumingMemoryBound(to: UInt16.self), 4)
                    colors.append(v)
                case .int3:
                    let v = normalize(data.assumingMemoryBound(to: Int32.self), 3)
                    colors.append(v)
                case .uint3:
                    let v = normalize(data.assumingMemoryBound(to: UInt32.self), 3)
                    colors.append(v)
                case .int4:
                    let v = normalize(data.assumingMemoryBound(to: Int32.self), 4)
                    colors.append(v)
                case .uint4:
                    let v = normalize(data.assumingMemoryBound(to: UInt32.self), 4)
                    colors.append(v)
                case .float3:
                    let v = data.assumingMemoryBound(to: Float3.self).pointee
                    colors.append(Vector4(v.0, v.1, v.2, 1.0))
                case .float4:
                    let v = data.assumingMemoryBound(to: Float4.self).pointee
                    colors.append(Vector4(v.0, v.1, v.2, v.3))
                default:
                    return false
                }
                return true
            })

            if uvs.count < positions.count {
                uvs.append(contentsOf: repeatElement(Vector2.zero, count: positions.count - uvs.count))
            }
            if colors.count < positions.count {
                colors.append(contentsOf: repeatElement(Vector4(1, 1, 1, 1), count: positions.count - colors.count))
            }

            var indices: [Int] = []
            if mesh.indexBuffer != nil {
                indices.reserveCapacity(mesh.indexCount)
                _ = mesh.enumerateIndexBufferContent(context: deviceContext) {
                    indices.append($0)
                    return true
                }
            } else {
                indices = positions.indices.map { Int($0) }
            }

            if mesh.primitiveType == .triangleStrip {
                let numTris = indices.count > 2 ? indices.count - 2 : 0
                faces.reserveCapacity(numTris)

                (0..<numTris).forEach { i in
                    var idx = (indices[i], indices[i+1], indices[i+2])
                    if i % 2 != 0 {
                        swap(&idx.0, &idx.1)
                    }
                    let face = TriangleFace(
                        vertices: (.init(pos: positions[idx.0], uv: uvs[idx.0], color: colors[idx.0]),
                                   .init(pos: positions[idx.1], uv: uvs[idx.1], color: colors[idx.1]),
                                   .init(pos: positions[idx.2], uv: uvs[idx.2], color: colors[idx.2])),
                        material: mesh.material)
                    faces.append(face)
                }
            } else {
                let numTris = indices.count / 3
                faces.reserveCapacity(numTris)
                (0..<numTris).forEach { i in
                    let idx = (indices[i*3], indices[i*3+1], indices[i*3+2])
                    let face = TriangleFace(
                        vertices: (.init(pos: positions[idx.0], uv: uvs[idx.0], color: colors[idx.0]),
                                   .init(pos: positions[idx.1], uv: uvs[idx.1], color: colors[idx.1]),
                                   .init(pos: positions[idx.2], uv: uvs[idx.2], color: colors[idx.2])),
                        material: mesh.material)
                    faces.append(face)
                }
            }
            return faces
        }

        if scene >= 0 && scene < self.scenes.count {
            var faces: [TriangleFace] = []
            self.scenes[scene].forEachNode { node, transform in
                if let mesh = node.mesh {
                    let tm = AffineTransform3.identity
                        .scaled(by: node.scale)
                        .matrix4
                        .concatenating(transform.matrix4)

                    let f = meshFaces(mesh: mesh, transform: tm)
                    faces.append(contentsOf: f)
                }
            }
            return faces
        }
        return []
    }
}

extension Model.Scene {
    func forEachNode(body: (SceneNode, Transform)->Void) {
        self.nodes.forEach {
            $0.forEach(transform: .identity, body: body)
        }
    }
    mutating func forEachNode(body: (inout SceneNode, Transform)->Void) {
        self.nodes.indices.forEach {
            self.nodes[$0].forEach(transform: .identity, body: body)
        }
    }
}

extension SceneNode {
    func forEach(transform: Transform = .identity, body: (SceneNode, Transform)->Void) {
        let trans = self.transform.concatenating(transform)
        body(self, trans)
        self.children.forEach {
            $0.forEach(transform: trans, body: body)
        }
    }

    mutating func forEach(transform: Transform = .identity, body: (inout SceneNode, Transform)->Void) {
        let trans = self.transform.concatenating(transform)
        body(&self, trans)
        self.children.indices.forEach {
            self.children[$0].forEach(transform: trans, body: body)
        }
    }
}

func loadModel(from path: String, shader: MaterialShaderMap? = nil, queue: CommandQueue) -> Model? {
    var loader = tinygltf.TinyGLTF()
    var model = tinygltf.Model()
    var err = std.string()
    var warn = std.string()
    let result: Bool
    if path.lowercased().hasSuffix(".gltf") {  // text-format
        result = loader.LoadASCIIFromFile(&model, &err, &warn, std.string(path))
    } else { // binary-format
        result = loader.LoadBinaryFromFile(&model, &err, &warn, std.string(path))
    }
    if warn.empty() == false {
        Log.warning("glTF warning: \(warn)")
    }
    if err.empty() == false {
        Log.error("glTF error: \(err)")
    }

    if result {
        let defaultImage = Image(width: 1, height: 1, pixelFormat: .rgba8, content: Color(1, 0, 1, 1).rgba8)
        let defaultTexture = defaultImage.makeTexture(commandQueue: queue, usage: [.sampled, .storage])
        guard let defaultTexture else {
            Log.error("Image.makeTexture failed")
            return nil
        }
        let defaultSampler = queue.device.makeSamplerState(
            descriptor: SamplerDescriptor(addressModeU: .repeat,
                                          addressModeV: .repeat,
                                          addressModeW: .repeat))
        guard let defaultSampler else {
            Log.error("GraphicsDevice.makeSamplerState failed")
            return nil
        }
        let shaderMap = shader ?? MaterialShaderMap(functions: [], resourceSemantics: [:], inputAttributeSemantics: [:])
        let context = LoaderContext(model: model,
                                    queue: queue,
                                    shader: shaderMap,
                                    defaultTexture: defaultTexture,
                                    defaultSampler: defaultSampler)
        loadBuffers(context)
        loadImages(context)
        loadSamplerDescriptors(context)
        loadMaterials(context)
        loadMeshes(context)

        var scenes: [Model.Scene] = []
        context.model.scenes.forEach {
            let scene = loadScene(context, scene: $0)
            scenes.append(scene)
        }
        return Model(scenes: scenes, defaultSceneIndex: Int(context.model.defaultScene))
    }
    return nil
}

fileprivate class LoaderContext {
    let model: tinygltf.Model
    let queue: CommandQueue
    let shader: MaterialShaderMap

    var defaultTexture: Texture
    var defaultSampler: SamplerState

    var buffers: [GPUBuffer] = []
    var images: [Texture?] = []
    var materials: [Material] = []
    var meshes: [SceneNode] = []
    var samplerDescriptors: [SamplerDescriptor] = []

    init(model: tinygltf.Model, queue: CommandQueue, shader: MaterialShaderMap, defaultTexture: Texture, defaultSampler: SamplerState) {
        self.model = model
        self.queue = queue
        self.shader = shader
        self.defaultTexture = defaultTexture
        self.defaultSampler = defaultSampler
    }
}

fileprivate extension Collection where Self.Index == Int {
    subscript(position: some FixedWidthInteger) -> Self.Element {
        self[Index(position)]
    }
}

fileprivate func makeBuffer<T>(_ cbuffer: CommandBuffer,
                               length: Int,
                               data: UnsafePointer<T>?,
                               storageMode: StorageMode = .private,
                               cpuCacheMode: CPUCacheMode = .defaultCache) -> GPUBuffer? {
    let ptr = UnsafeRawBufferPointer(start: data, count: length)
    if let data = ptr.baseAddress, ptr.count > 0 {
        return makeBuffer(cbuffer, length: ptr.count, data: data, storageMode: storageMode, cpuCacheMode: cpuCacheMode)
    }
    return nil
}

fileprivate func makeBuffer(_ cbuffer: CommandBuffer,
                            length: Int,
                            data: UnsafeRawPointer,
                            storageMode: StorageMode = .private,
                            cpuCacheMode: CPUCacheMode = .defaultCache) -> GPUBuffer? {
    assert(length > 0)
    let device = cbuffer.device

    if storageMode == .shared {
        guard let buffer = device.makeBuffer(length: length,
                                             storageMode: storageMode,
                                             cpuCacheMode: cpuCacheMode) else {
            Log.error("makeBuffer(length: \(length), storageMode: \(storageMode), cpuCacheMode: \(cpuCacheMode)) failed.")
            return nil
        }

        guard let ptr = buffer.contents() else {
            Log.error("GPUBuffer map failed.")
            return nil
        }
        ptr.copyMemory(from: data, byteCount: length)
        buffer.flush()
        return buffer
    } else {
        guard let stgBuffer = device.makeBuffer(length: length,
                                                storageMode: .shared,
                                                cpuCacheMode: .writeCombined)
        else {
            Log.error("makeBuffer(length: \(length), storageMode: .shared, cpuCacheMode: writeCombined)) failed.")
            return nil
        }
        if let ptr = stgBuffer.contents() {
            ptr.copyMemory(from: data, byteCount: length)
            stgBuffer.flush()
        } else {
            Log.error("GPUBuffer map failed")
            return nil
        }

        guard let buffer = device.makeBuffer(length: length,
                                             storageMode: storageMode,
                                             cpuCacheMode: cpuCacheMode) else {
            Log.error("makeBuffer(length: \(length), storageMode: \(storageMode), cpuCacheMode: \(cpuCacheMode)) failed.")
            return nil
        }
        guard let encoder = cbuffer.makeCopyCommandEncoder() else {
            Log.error("makeCopyCommandEncoder failed.")
            return nil
        }
        encoder.copy(from: stgBuffer, sourceOffset: 0, to: buffer, destinationOffset: 0, size: length)
        encoder.endEncoding()

        return buffer
    }
}

fileprivate func loadBuffers(_ context: LoaderContext) {
    guard let cbuffer = context.queue.makeCommandBuffer() else {
        fatalError("CommandQueue.makeCommandBuffer failed.")
    }

    context.buffers = context.model.buffers.map {
        guard let buffer = makeBuffer(cbuffer, length: $0.data.count, data: $0.data.__dataUnsafe())
        else { fatalError("makeBuffer failed") }
        return buffer
    }
    assert(context.buffers.count == context.model.buffers.count)
    cbuffer.commit()
}

fileprivate func loadImages(_ context: LoaderContext) {
    context.images = context.model.images.map {
        let width = Int($0.width)
        let height = Int($0.height)
        let component = Int($0.component)
        let bits = Int($0.bits)

        var imageFormat = ImagePixelFormat.invalid
        switch (component, bits) {
        case (1, 8):    imageFormat = .r8
        case (1, 16):   imageFormat = .r16
        case (1, 32):   imageFormat = .r32
        case (2, 8):    imageFormat = .rg8
        case (2, 16):   imageFormat = .rg16
        case (2, 32):   imageFormat = .rg32
        case (3, 8):    imageFormat = .rgb8
        case (3, 16):   imageFormat = .rgb16
        case (3, 32):   imageFormat = .rgb32
        case (4, 8):    imageFormat = .rgba8
        case (4, 16):   imageFormat = .rgba16
        case (4, 32):   imageFormat = .rgba32        
        default:
            Log.error("Unsupported image pixel format.")
            return nil
        }
        let reqLength = (bits >> 3) * width * height * component
        if $0.image.count < reqLength {
            Log.error("Invalid image pixel data.")
            return nil
        }
        let data = UnsafeBufferPointer(start: $0.image.__dataUnsafe(), count: $0.image.count)
        let image = Image(width: width, height: height, pixelFormat: imageFormat, data: UnsafeRawBufferPointer(data))
        if let texture = image.makeTexture(commandQueue: context.queue) {
            return texture
        }
        Log.error("Failed to load image: \($0.name)")
        return nil
    }
    assert(context.images.count == context.model.images.count)
}

fileprivate func loadSamplerDescriptors(_ context: LoaderContext) {
    context.samplerDescriptors = context.model.samplers.map {
        var desc = SamplerDescriptor()
        switch $0.minFilter {
        case TINYGLTF_TEXTURE_FILTER_NEAREST,
        TINYGLTF_TEXTURE_FILTER_NEAREST_MIPMAP_NEAREST:
            desc.minFilter = .nearest
            desc.mipFilter = .nearest
        case TINYGLTF_TEXTURE_FILTER_LINEAR,
        TINYGLTF_TEXTURE_FILTER_NEAREST_MIPMAP_LINEAR:
            desc.minFilter = .linear
            desc.mipFilter = .nearest
        case TINYGLTF_TEXTURE_FILTER_LINEAR_MIPMAP_NEAREST:
            desc.minFilter = .linear
            desc.mipFilter = .nearest
        case TINYGLTF_TEXTURE_FILTER_LINEAR_MIPMAP_LINEAR:
            desc.minFilter = .linear
            desc.mipFilter = .linear
        default:
            desc.minFilter = .linear
            desc.mipFilter = .linear
        }
        if $0.magFilter == TINYGLTF_TEXTURE_FILTER_NEAREST {
            desc.magFilter = .nearest
        } else {
            desc.magFilter = .linear
        }

        let samplerAddressMode = { (wrap: Int32) -> SamplerAddressMode in
            switch wrap {
            case TINYGLTF_TEXTURE_WRAP_REPEAT:
                return .repeat
            case TINYGLTF_TEXTURE_WRAP_CLAMP_TO_EDGE:
                return .clampToEdge
            case TINYGLTF_TEXTURE_WRAP_MIRRORED_REPEAT:
                return .mirrorRepeat
            default:
                Log.error("Unknown address mode!")
                return .repeat;
            }
        }
        desc.addressModeU = samplerAddressMode($0.wrapS)
        desc.addressModeV = samplerAddressMode($0.wrapT)
        desc.addressModeV = samplerAddressMode(TINYGLTF_TEXTURE_WRAP_REPEAT)
        desc.lodMaxClamp = 256;
        return desc
    }
}

fileprivate func loadMaterials(_ context: LoaderContext) {
    context.materials = context.model.materials.map {
        let name = String($0.name)
        let material = Material(shaderMap: context.shader, name: name)
        material.defaultTexture = context.defaultTexture
        material.defaultSampler = context.defaultSampler

        if String($0.alphaMode) == "BLEND" {
            material.attachments[0].blendState = .alphaBlend
        } else {
            material.attachments[0].blendState = .opaque
        }

        //material.cullMode = $0.doubleSided ? .none : .back
        material.cullMode = .none
        material.frontFace = .counterClockwise

        material.properties[.baseColor] = .scalars($0.pbrMetallicRoughness.baseColorFactor[0...3])

        let textureSampler = { (index: Int32) -> MaterialProperty.CombinedTextureSampler? in
            let index = Int(index)
            if index >= 0 && index < context.model.textures.count {
                let texture = context.model.textures[index]
                var image: Texture? = nil
                if texture.source >= 0 && texture.source < context.images.count {
                    image = context.images[texture.source]
                }
                if let image {
                    var sampler: SamplerState? = nil
                    if texture.sampler >= 0 && texture.sampler < context.samplerDescriptors.count {
                        let samplerDesc = context.samplerDescriptors[texture.sampler]
                        sampler = context.queue.device.makeSamplerState(descriptor: samplerDesc)
                    }
                    return (texture: image, sampler: sampler ?? context.defaultSampler)
                }
            }
            return nil
        }

        if let ts = textureSampler($0.pbrMetallicRoughness.baseColorTexture.index) {
            material.properties[.baseColorTexture] = .combinedTextureSampler(ts)
        }
        if let ts = textureSampler($0.pbrMetallicRoughness.metallicRoughnessTexture.index) {
            material.properties[.metallicRoughnessTexture] = .combinedTextureSampler(ts)
        }
        material.properties[.metallic] = .scalar($0.pbrMetallicRoughness.metallicFactor)
        material.properties[.roughness] = .scalar($0.pbrMetallicRoughness.roughnessFactor)
        if let ts = textureSampler($0.normalTexture.index) {
            material.properties[.normalTexture] = .combinedTextureSampler(ts)
        }
        material.properties[.normalScaleFactor] = .scalar($0.normalTexture.scale)
        if let ts = textureSampler($0.occlusionTexture.index) {
            material.properties[.occlusionTexture] = .combinedTextureSampler(ts)
        }
        material.properties[.occlusionScale] = .scalar($0.occlusionTexture.strength)
        material.properties[.emissiveFactor] = .scalars($0.emissiveFactor[0...2])
        if let ts = textureSampler($0.emissiveTexture.index) {
            material.properties[.emissiveTexture] = .combinedTextureSampler(ts)
        }
        return material
    }
}

fileprivate func loadMeshes(_ context: LoaderContext) {
    guard let cbuffer = context.queue.makeCommandBuffer() else {
        fatalError("makeCommandBuffer failed")
    }

    context.meshes = context.model.meshes.map { mesh in
        let meshName = String(mesh.name)
        var node = SceneNode(name: meshName)

        mesh.primitives.forEach { primitive in
            let mesh = Mesh()

            var positions: [Vector3] = []
            var indices: [Int] = []
            var hasVertexNormal = false
            var hasVertexColor = false

            primitive.attributes.forEach { attr in
                let attributeName = String(attr.first)
                let accessorIndex = Int(attr.second)

                let accessor = context.model.accessors[accessorIndex]
                let bufferView = context.model.bufferViews[accessor.bufferView]
                let buffer = context.model.buffers[bufferView.buffer]

                let vertexStride = accessor.ByteStride(bufferView)
                var bufferOffset = bufferView.byteOffset
                var attribOffset = 0
                if bufferView.byteStride > 0 {
                    // separate
                    bufferOffset += accessor.byteOffset
                } else {
                    // packed (interleaved)
                    attribOffset = accessor.byteOffset
                }
                assert(vertexStride > 0)
                assert(attribOffset < vertexStride)

                if accessor.componentType == TINYGLTF_COMPONENT_TYPE_DOUBLE {
                    Log.error("Vertex component type for Double(Float64) is not supported!")
                    return
                }

                var attribute = Mesh.VertexAttribute(semantic: .userDefined,
                                                     format: .invalid,
                                                     offset: attribOffset,
                                                     name: attributeName)

                switch (accessor.type, accessor.componentType) {
                    // scalar
                case (TINYGLTF_TYPE_SCALAR, TINYGLTF_COMPONENT_TYPE_BYTE):
                    attribute.format = accessor.normalized ? .charNormalized : .char
                case (TINYGLTF_TYPE_SCALAR, TINYGLTF_COMPONENT_TYPE_UNSIGNED_BYTE):
                    attribute.format = accessor.normalized ? .ucharNormalized : .uchar
                case (TINYGLTF_TYPE_SCALAR, TINYGLTF_COMPONENT_TYPE_SHORT):
                    attribute.format = accessor.normalized ? .shortNormalized : .short
                case (TINYGLTF_TYPE_SCALAR, TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT):
                    attribute.format = accessor.normalized ? .ushortNormalized : .ushort
                case (TINYGLTF_TYPE_SCALAR, TINYGLTF_COMPONENT_TYPE_INT):
                    attribute.format = .int
                case (TINYGLTF_TYPE_SCALAR, TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT):
                    attribute.format = .uint
                case (TINYGLTF_TYPE_SCALAR, TINYGLTF_COMPONENT_TYPE_FLOAT):
                    attribute.format = .float
                    // vec2
                case (TINYGLTF_TYPE_VEC2, TINYGLTF_COMPONENT_TYPE_BYTE):
                    attribute.format = accessor.normalized ? .char2Normalized : .char2
                case (TINYGLTF_TYPE_VEC2, TINYGLTF_COMPONENT_TYPE_UNSIGNED_BYTE):
                    attribute.format = accessor.normalized ? .uchar2Normalized : .uchar2
                case (TINYGLTF_TYPE_VEC2, TINYGLTF_COMPONENT_TYPE_SHORT):
                    attribute.format = accessor.normalized ? .short2Normalized : .short2
                case (TINYGLTF_TYPE_VEC2, TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT):
                    attribute.format = accessor.normalized ? .ushort2Normalized : .ushort2
                case (TINYGLTF_TYPE_VEC2, TINYGLTF_COMPONENT_TYPE_INT):
                    attribute.format = .int2
                case (TINYGLTF_TYPE_VEC2, TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT):
                    attribute.format = .uint2
                case (TINYGLTF_TYPE_VEC2, TINYGLTF_COMPONENT_TYPE_FLOAT):
                    attribute.format = .float2
                    // vec3
                case (TINYGLTF_TYPE_VEC3, TINYGLTF_COMPONENT_TYPE_BYTE):
                    attribute.format = accessor.normalized ? .char3Normalized : .char3
                case (TINYGLTF_TYPE_VEC3, TINYGLTF_COMPONENT_TYPE_UNSIGNED_BYTE):
                    attribute.format = accessor.normalized ? .uchar3Normalized : .uchar3
                case (TINYGLTF_TYPE_VEC3, TINYGLTF_COMPONENT_TYPE_SHORT):
                    attribute.format = accessor.normalized ? .short3Normalized : .short3
                case (TINYGLTF_TYPE_VEC3, TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT):
                    attribute.format = accessor.normalized ? .ushort3Normalized : .ushort3
                case (TINYGLTF_TYPE_VEC3, TINYGLTF_COMPONENT_TYPE_INT):
                    attribute.format = .int3
                case (TINYGLTF_TYPE_VEC3, TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT):
                    attribute.format = .uint3
                case (TINYGLTF_TYPE_VEC3, TINYGLTF_COMPONENT_TYPE_FLOAT):
                    attribute.format = .float3
                    // vec4
                case (TINYGLTF_TYPE_VEC4, TINYGLTF_COMPONENT_TYPE_BYTE):
                    attribute.format = accessor.normalized ? .char4Normalized : .char4
                case (TINYGLTF_TYPE_VEC4, TINYGLTF_COMPONENT_TYPE_UNSIGNED_BYTE):
                    attribute.format = accessor.normalized ? .uchar4Normalized : .uchar4
                case (TINYGLTF_TYPE_VEC4, TINYGLTF_COMPONENT_TYPE_SHORT):
                    attribute.format = accessor.normalized ? .short4Normalized : .short4
                case (TINYGLTF_TYPE_VEC4, TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT):
                    attribute.format = accessor.normalized ? .ushort4Normalized : .ushort4
                case (TINYGLTF_TYPE_VEC4, TINYGLTF_COMPONENT_TYPE_INT):
                    attribute.format = .int4
                case (TINYGLTF_TYPE_VEC4, TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT):
                    attribute.format = .uint4
                case (TINYGLTF_TYPE_VEC4, TINYGLTF_COMPONENT_TYPE_FLOAT):
                    attribute.format = .float4
                default:
                    Log.error("Unhandled vertex attribute type: \(accessor.type)")
                    return
                }

                // Note:
                // https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#meshes
                switch attributeName.uppercased() {
                case "POSITION":
                    attribute.semantic = .position
                    if attribute.format == .float3 {
                        // get AABB
                        var ptr = UnsafeRawPointer(buffer.data.__dataUnsafe()!)
                        ptr += bufferOffset + attribOffset
                        var aabb = AABB()
                        positions.removeAll(keepingCapacity: true)
                        positions.reserveCapacity(accessor.count)
                        for _ in 0..<accessor.count {
                            let float3 = ptr.assumingMemoryBound(to: Float3.self).pointee
                            let p = Vector3(float3)
                            positions.append(p)
                            aabb.expand(p)
                            ptr += Int(vertexStride)
                        }
                        mesh.aabb = aabb
                    }
                case "NORMAL":
                    attribute.semantic = .normal
                    hasVertexNormal = true
                case "TANGENT":
                    attribute.semantic = .tangent
                case "TEXCOORD_0":
                    attribute.semantic = .textureCoordinates
                case "COLOR_0":
                    attribute.semantic = .color
                    hasVertexColor = true
                default:
                    Log.warning("Unhandled vertex buffer attribute: \(attributeName)")
                    return
                }

                let vertexBuffer = Mesh.VertexBuffer(byteOffset: bufferOffset,
                                                     byteStride: Int(vertexStride),
                                                     vertexCount: accessor.count,
                                                     buffer: context.buffers[bufferView.buffer],
                                                     attributes: [attribute])
                mesh.vertexBuffers.append(vertexBuffer)
            }

            switch primitive.mode {
            case TINYGLTF_MODE_POINTS:
                mesh.primitiveType = .point
            case TINYGLTF_MODE_LINE, TINYGLTF_MODE_LINE_LOOP:
                mesh.primitiveType = .line
            case TINYGLTF_MODE_LINE_STRIP:
                mesh.primitiveType = .lineStrip
            case TINYGLTF_MODE_TRIANGLES:
                mesh.primitiveType = .triangle
            case TINYGLTF_MODE_TRIANGLE_STRIP:
                mesh.primitiveType = .triangleStrip
            default:
                Log.error("Unsupported primitive type: \(primitive.mode)")
                return
            }

            if primitive.indices >= 0 {
                let accessor = context.model.accessors[primitive.indices]
                let bufferView = context.model.bufferViews[accessor.bufferView]
                let buffer = context.model.buffers[bufferView.buffer]

                mesh.indexBufferByteOffset = bufferView.byteOffset + accessor.byteOffset
                mesh.indexCount = accessor.count
                mesh.indexBuffer = context.buffers[bufferView.buffer]
                mesh.indexBufferBaseVertexIndex = 0

                indices.reserveCapacity(accessor.count)
                let ptr = UnsafeRawPointer(buffer.data.__dataUnsafe()!) + mesh.indexBufferByteOffset

                switch accessor.componentType {
                case TINYGLTF_COMPONENT_TYPE_UNSIGNED_BYTE: // convert to UInt16
                    assert(accessor.count > 0)
                    let p = ptr.assumingMemoryBound(to: UInt8.self)
                    var indexData: [UInt16] = []
                    indexData.reserveCapacity(accessor.count)
                    for i in 0..<accessor.count {
                        let index = p[i]
                        indexData.append(UInt16(index))
                        indices.append(Int(index))
                    }

                    guard let buffer = makeBuffer(cbuffer, length: indexData.count * 2, data: &indexData)
                    else { fatalError("makeBuffer failed") }

                    mesh.indexBuffer = buffer
                    mesh.indexType = .uint16
                    mesh.indexBufferByteOffset = 0
                case TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT:
                    let p = ptr.assumingMemoryBound(to: UInt16.self)
                    mesh.indexType = .uint16
                    for i in 0..<accessor.count {
                        let index = p[i]
                        indices.append(Int(index))
                    }
                case TINYGLTF_COMPONENT_TYPE_UNSIGNED_INT:
                    let p = ptr.assumingMemoryBound(to: UInt32.self)
                    mesh.indexType = .uint32
                    for i in 0..<accessor.count {
                        let index = p[i]
                        indices.append(Int(index))
                    }
                default:
                    fatalError("Unknown index type")
                }
            } else {
                indices.reserveCapacity(positions.count)
                positions.indices.forEach { indices.append($0) }
            }

            if hasVertexNormal == false {
                var normals = [Vector3](repeating: Vector3.zero, count: positions.count)

                let generateFaceNormal = { (i0: Int, i1: Int, i2: Int) in
                    let p0 = positions[i0]
                    let p1 = positions[i1]
                    let p2 = positions[i2]
                    let u = p1 - p0
                    let v = p2 - p0
                    let normal = Vector3.cross(u, v).normalized()
                    normals[i0] += normal
                    normals[i1] += normal
                    normals[i2] += normal
                }

                switch mesh.primitiveType {
                case .triangle:
                    var i = 0
                    while i+2 < indices.count {
                        generateFaceNormal(indices[i], indices[i+1], indices[i+2])
                        i += 3
                    }
                case .triangleStrip:
                    for i in 0..<(indices.count - 2) {
                        if i % 2 == 1 {
                            generateFaceNormal(indices[i+1], indices[i], indices[i+2])
                        } else {
                            generateFaceNormal(indices[i], indices[i+1], indices[i+2])
                        }
                    }
                default:
                    break
                }
                normals.indices.forEach {
                    normals[$0].normalize()
                }

                let normalData = normals.map { $0.float3 }
                let buffer = makeBuffer(cbuffer,
                                        length: normals.count * MemoryLayout<Float3>.size,
                                        data: normalData)
                guard let buffer else {
                    fatalError("makeBuffer failed")
                }
                let attribute = Mesh.VertexAttribute(semantic: .normal,
                                                     format: .float3,
                                                     offset: 0,
                                                     name: "Normal")
                let vb = Mesh.VertexBuffer(byteOffset: 0,
                                           byteStride: MemoryLayout<Float3>.size,
                                           vertexCount: normals.count,
                                           buffer: buffer,
                                           attributes: [attribute])
                mesh.vertexBuffers.append(vb)
            }

            if hasVertexColor == false {
                let colors = [Float4](repeating: Vector4(1, 1, 1, 1).float4, count: positions.count)
                let buffer = makeBuffer(cbuffer, length: colors.count * MemoryLayout<Float4>.size, data: colors)
                guard let buffer else {
                    fatalError("makeBuffer failed")
                }
                let attribute = Mesh.VertexAttribute(semantic: .color,
                                                     format: .float4,
                                                     offset: 0,
                                                     name: "Color")
                let vb = Mesh.VertexBuffer(byteOffset: 0,
                                           byteStride: MemoryLayout<Float4>.size,
                                           vertexCount: colors.count,
                                           buffer: buffer,
                                           attributes: [attribute])
                mesh.vertexBuffers.append(vb)
            }

            if primitive.material >= 0 {
                mesh.material = context.materials[primitive.material]
            } else {
                let material = Material(shaderMap: context.shader, name: "default")
                material.defaultTexture = context.defaultTexture
                material.defaultSampler = context.defaultSampler
                material.properties[.baseColor] = .color(.white)
                material.properties[.metallic] = .scalar(1.0)
                material.properties[.roughness] = .scalar(1.0)
                mesh.material = material
            }

            let meshNode = SceneNode(name: meshName, mesh: mesh)
            node.children.append(meshNode)
        }

        while node.mesh == nil && node.children.count == 1 {
            node = node.children[0]
        }
        return node
    }
    cbuffer.commit()
}

fileprivate func loadNode(_ context: LoaderContext, node: tinygltf.Node, transform baseTM: Matrix4) -> SceneNode {
    var output = SceneNode(name: String(node.name))
    if node.mesh >= 0 {
        var mesh = context.meshes[node.mesh]
        while mesh.mesh == nil && mesh.children.count == 1 {
            mesh = mesh.children[0]
        }
        if mesh.mesh != nil && mesh.children.isEmpty {
            output.mesh = mesh.mesh
        } else {
            output.children.append(mesh)
        }
    }

    var nodeTM = Matrix4.identity
    if node.matrix.count == 16 {
        for i in 0..<16 {
            nodeTM[i / 4, i % 4] = Scalar(node.matrix[i])
        }
    } else {
        var rotation = Quaternion.identity
        var scale = Vector3(1, 1, 1)
        var translation = Vector3.zero
        if node.rotation.count == 4 {
            for i in 0..<4 {
                rotation[i] = Scalar(node.rotation[i])
            }
        }
        if node.scale.count == 3 {
            for i in 0..<3 {
                scale[i] = Scalar(node.scale[i])
            }
        }
        if node.translation.count == 3 {
            for i in 0..<3 {
                translation[i] = Scalar(node.translation[i])
            }
        }
        // https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#transformations
        nodeTM = AffineTransform3.identity
            .scaled(by: scale)
            .rotated(by: rotation)
            .translated(by: translation)
            .matrix4
    }

    let worldTM = nodeTM.concatenating(baseTM)

    // remove scale component.
    let decompose = { (mat: Matrix4) -> (transform: Transform, scale: Vector3) in
        let affine = AffineTransform3(matrix4: mat)
        var scale = Vector3(1, 1, 1)
        var quat = Quaternion.identity
        if affine.linearTransform.decompose(scale: &scale, rotation: &quat) {
            return (Transform(orientation: quat, position: affine.translation),
                    scale)
        }
        return (Transform.identity, Vector3.zero)
    }

    let base = decompose(baseTM)
    let baseTrans = base.transform

    let ts = decompose(worldTM)
    output.transform = ts.transform.concatenating(baseTrans.inverted())
    output.scale = ts.scale

    // update mesh node transform
    output.children.indices.forEach {
        output.children[$0].forEach { (node: inout SceneNode, _) in
            node.scale = ts.scale
        }
    }
    
    node.children.forEach { index in
        let child = context.model.nodes[index]
        let node = loadNode(context, node: child, transform: worldTM)
        output.children.append(node)
    }
    return output
}

fileprivate func loadScene(_ context: LoaderContext, scene: tinygltf.Scene) -> Model.Scene {
    var output = Model.Scene(name: String(scene.name), nodes: [])
    output.nodes.reserveCapacity(scene.nodes.count)
    scene.nodes.forEach { index in
        let child = context.model.nodes[index]
        let node = loadNode(context, node: child, transform: .identity)
        output.nodes.append(node)
    }
    return output
}

