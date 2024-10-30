//
//  File: Mesh.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

public class Mesh {
    public var material: Material?
    public var aabb: AABB

    public struct VertexAttribute {
        public var semantic: VertexAttributeSemantic
        public var format: VertexFormat
        public var offset: Int
        public var name: String
        public init(semantic: VertexAttributeSemantic, format: VertexFormat, offset: Int, name: String) {
            self.semantic = semantic
            self.format = format
            self.offset = offset
            self.name = name
        }
    }
    public struct VertexBuffer {
        public var byteOffset: Int
        public var byteStride: Int
        public var vertexCount: Int
        public var buffer: GPUBuffer
        public var attributes: [VertexAttribute]
        public init(byteOffset: Int, byteStride: Int, vertexCount: Int, buffer: GPUBuffer, attributes: [VertexAttribute]) {
            self.byteOffset = byteOffset
            self.byteStride = byteStride
            self.vertexCount = vertexCount
            self.buffer = buffer
            self.attributes = attributes
        }
    }
    public var vertexBuffers: [VertexBuffer]
    public var indexBuffer: GPUBuffer?
    public var indexBufferByteOffset: Int = 0
    public var indexBufferBaseVertexIndex: Int = 0
    public var vertexStart: Int = 0
    public var indexCount: Int
    public var indexType: IndexType
    public var primitiveType: PrimitiveType

    public enum BufferUsagePolicy {
        case useExternalBufferManually
        case singleBuffer
        case singleBufferPerSet
        case singleBufferPerResource
    }

    struct ResourceBinding {
        let resource: ShaderResource
        let binding: ShaderBinding
    }
    struct ResourceBindingSet {
        let index: Int
        let bindingSet: ShaderBindingSet
        let resources: [ResourceBinding]
    }
    struct PushConstantData {
        let layout: ShaderPushConstantLayout
        var data: [UInt8]
    }
    var pipelineState: RenderPipelineState?
    var pipelineReflection: PipelineReflection?
    var resourceBindings: [ResourceBindingSet]
    var pushConstants: [PushConstantData]

    struct BufferResource {
        let name: String
        let buffers: [BufferBindingInfo]
    }
    var bufferResources: [ShaderBindingLocation: BufferResource]


    public init() {
        self.indexCount = 0
        self.indexType = .uint16
        self.vertexBuffers = []
        self.primitiveType = .triangle

        self.resourceBindings = []
        self.pushConstants = []
        self.bufferResources = [:]

        self.aabb = AABB()
    }

    func availableVertexBuffers(for material: Material) -> [VertexBuffer] {
        guard let vertexFunction = material.shader.function(stage: .vertex)
        else { return [] }

        let vertexInputs = vertexFunction.stageInputAttributes
        let attributeSemantics = material.shader.inputAttributeSemantics

        let attrs: [(semantic: VertexAttributeSemantic, name: String)] = 
            vertexInputs.filter(\.enabled).map {
                (semantic: attributeSemantics[$0.location, default: .userDefined],
                 name: $0.name)                
            }
        return self.vertexBuffers.filter { vertexBuffer in
            vertexBuffer.attributes.contains { attribute in
                if attribute.semantic != .userDefined {
                    if attrs.contains(where: { $0.semantic == attribute.semantic }) {
                        return true
                    }
                }
                if attribute.name.isEmpty == false {
                    return attrs.contains { $0.name == attribute.name }
                }
                return false
            }
        }
    }

    public var vertexDescriptor: VertexDescriptor {
        guard let material else { return .init() }
        guard let vertexFunction = material.shader.function(stage: .vertex)
        else { return .init() }

        let vertexBuffers = self.availableVertexBuffers(for: material)
        if vertexBuffers.isEmpty { return .init() }

        let vertexInputs = vertexFunction.stageInputAttributes
        let attributeSemantics = material.shader.inputAttributeSemantics

        let findBufferIndexAttribute = {
            (s: VertexAttributeSemantic) -> (Int, VertexAttribute)? in
            for index in 0..<vertexBuffers.count {
                if let attr = vertexBuffers[index].attributes
                    .first(where: { $0.semantic == s }) {
                    return (index, attr)
                }
            }
            return nil
        }
        let findBufferIndexAttributeByName = {
            (name: String) -> (Int, VertexAttribute)? in
            for index in 0..<vertexBuffers.count {
                if let attr = vertexBuffers[index].attributes
                    .first(where: { $0.name == name }) {
                    return (index, attr)
                }
            }
            return nil
        }

        var attributes: [VertexAttributeDescriptor] = []
        attributes.reserveCapacity(vertexInputs.count)
        for input in vertexInputs {
            if input.enabled == false { continue }

            let semantic = attributeSemantics[input.location, default: .userDefined]
            var bufferIndexAttr: (Int, VertexAttribute)? = nil
            if semantic == .userDefined && input.name.isEmpty == false {
                bufferIndexAttr = findBufferIndexAttributeByName(input.name)
            }
            if bufferIndexAttr == nil {
                bufferIndexAttr = findBufferIndexAttribute(semantic)
            }
            if let (bufferIndex, attr) = bufferIndexAttr {
                let descriptor = VertexAttributeDescriptor(
                    format: attr.format,
                    offset: attr.offset,
                    bufferIndex: bufferIndex,
                    location: input.location)
                attributes.append(descriptor)
            } else {
                Log.error("Cannot bind vertex buffer at location: \(input.location) (name: \(input.name))")
            }
        }

        let layouts = vertexBuffers.enumerated().map { index, buffer in
            VertexBufferLayoutDescriptor(stepRate: .vertex,
                                         stride: buffer.byteStride)
        }
        return VertexDescriptor(attributes: attributes, layouts: layouts)
    }

    public func initResources(device: GraphicsDevice,
                              bufferPolicy policy: BufferUsagePolicy) -> Bool {
        if self.material == nil { return false }
        if self.pipelineState == nil { _ = buildPipelineState(device: device) }
        if self.pipelineState == nil { return false }

        var numBuffersGenerated = 0
        var totalBytesAllocated = 0

        struct OptBufferInfo {
            var offset: Int
            var length: Int
            func bindingInfo(with buffer: GPUBuffer) -> BufferBindingInfo {
                BufferBindingInfo(buffer: buffer, offset: offset, length: length)
            }
        }
        struct OptBufferResource {
            var name: String
            var buffers: [OptBufferInfo]
            func bufferResource(with buffer: GPUBuffer) -> BufferResource {
                BufferResource(name: name, buffers: buffers.map {
                    $0.bindingInfo(with: buffer)
                })
            }
        }

        switch policy {
        case .singleBuffer:
            var bufferOffset = 0
            var bufferLength = 0
            var resourceMap: [ShaderBindingLocation: OptBufferResource] = [:]

            self.resourceBindings.forEach { bset in
                bset.resources.forEach { rb in
                    if rb.resource.type == .buffer {
                        let bufferTypeInfo = rb.resource.bufferTypeInfo!
                        let buffers = (0..<rb.resource.count).map { _ in
                            bufferOffset += rb.resource.stride
                            return OptBufferInfo(offset: bufferOffset,
                                                 length: bufferTypeInfo.size)
                        }
                        bufferLength = bufferOffset + bufferTypeInfo.size
                        bufferLength = bufferLength.alignedUp(toMultipleOf: 16)
                        bufferOffset = bufferOffset.alignedUp(toMultipleOf: 16)

                        let location = ShaderBindingLocation(
                            set: rb.resource.set,
                            binding: rb.resource.binding,
                            offset: 0)
                        resourceMap[location] = OptBufferResource(
                            name: rb.resource.name,
                            buffers: buffers)
                    }
                }
            }
            if bufferLength > 0 {
                let buffer = device.makeBuffer(length: bufferLength,
                                               storageMode: .shared,
                                               cpuCacheMode: .writeCombined)
                guard let buffer else {
                    Log.error("failed to make buffer with length \(bufferLength)")
                    return false
                }
                numBuffersGenerated += 1
                totalBytesAllocated += bufferLength

                resourceMap.forEach { key, value in
                    self.bufferResources[key] = value.bufferResource(with: buffer)
                }
            }
        case .singleBufferPerSet:
            var bufferResourcesTmp: [ShaderBindingLocation: BufferResource] = [:]
            for bset in self.resourceBindings {
                var bufferOffset = 0
                var bufferLength = 0
                var resourceMap: [ShaderBindingLocation: OptBufferResource] = [:]

                bset.resources.forEach { rb in
                    if rb.resource.type == .buffer {
                        let bufferTypeInfo = rb.resource.bufferTypeInfo!
                        let buffers = (0..<rb.resource.count).map { _ in
                            bufferOffset += rb.resource.stride
                            return OptBufferInfo(offset: bufferOffset, length: bufferTypeInfo.size)
                        }
                        bufferLength = bufferOffset + bufferTypeInfo.size
                        bufferLength = bufferLength.alignedUp(toMultipleOf: 16)
                        bufferOffset = bufferOffset.alignedUp(toMultipleOf: 16)

                        let location = ShaderBindingLocation(
                            set: rb.resource.set,
                            binding: rb.resource.binding,
                            offset: 0)
                        resourceMap[location] = OptBufferResource(
                            name: rb.resource.name,
                            buffers: buffers)
                    }
                }
                if bufferLength > 0 {
                    let buffer = device.makeBuffer(length: bufferLength,
                                                   storageMode: .shared,
                                                   cpuCacheMode: .writeCombined)
                    guard let buffer else {
                        Log.error("failed to make buffer with length \(bufferLength)")
                        return false
                    }
                    numBuffersGenerated += 1
                    totalBytesAllocated += bufferLength

                    resourceMap.forEach { key, value in
                        bufferResourcesTmp[key] = value.bufferResource(with: buffer)
                    }
                }
            }
            self.bufferResources.merge(bufferResourcesTmp) { $1 }
        case .singleBufferPerResource:
            var bufferResourcesTmp: [ShaderBindingLocation: BufferResource] = [:]
            for bset in self.resourceBindings {
                for rb in bset.resources {
                    var bufferOffset = 0
                    var bufferLength = 0
                    var resourceMap: [ShaderBindingLocation: OptBufferResource] = [:]

                    if rb.resource.type == .buffer {
                        let bufferTypeInfo = rb.resource.bufferTypeInfo!
                        let buffers = (0..<rb.resource.count).map { _ in
                            bufferOffset += rb.resource.stride
                            return OptBufferInfo(offset: bufferOffset,
                                                 length: bufferTypeInfo.size)
                        }
                        bufferLength = bufferOffset + bufferTypeInfo.size
                        bufferLength = bufferLength.alignedUp(toMultipleOf: 16)
                        bufferOffset = bufferOffset.alignedUp(toMultipleOf: 16)

                        let location = ShaderBindingLocation(
                            set: rb.resource.set,
                            binding: rb.resource.binding,
                            offset: 0)
                        resourceMap[location] = OptBufferResource(
                            name: rb.resource.name,
                            buffers: buffers)
                    }
                    if bufferLength > 0 {
                        let buffer = device.makeBuffer(
                            length: bufferLength,
                            storageMode: .shared,
                            cpuCacheMode: .writeCombined)
                        guard let buffer else {
                            Log.error("failed to make buffer with length \(bufferLength)")
                            return false
                        }
                        numBuffersGenerated += 1
                        totalBytesAllocated += bufferLength

                        resourceMap.forEach { key, value in
                            bufferResourcesTmp[key] = value.bufferResource(with: buffer)
                        }
                    }
                }
            }
            self.bufferResources.merge(bufferResourcesTmp) { $1 }
        default:
            break
        }
        Log.debug("initResources generated \(numBuffersGenerated) buffers, \(totalBytesAllocated) bytes.")
        return true
    }

    public func buildPipelineState(device: GraphicsDevice,
                                   reflection ref: UnsafeMutablePointer<PipelineReflection>? = nil) -> Bool {
        guard let material else {
            Log.error("The material does not exist.")
            return false
        }

        let vertexFunction = material.shader.function(stage: .vertex)
        let fragmentFunction = material.shader.function(stage: .fragment)

        if vertexFunction == nil {
            Log.error("Materials do not have a vertex function.")
            return false
        }

        let vertexDescriptor = self.vertexDescriptor
        if vertexDescriptor.attributes.isEmpty || vertexDescriptor.layouts.isEmpty {
            Log.error("Invalid vertex descriptor!")
            return false
        }

        let pipelineDescriptor = RenderPipelineDescriptor(
            vertexFunction: vertexFunction,
            fragmentFunction: fragmentFunction,
            vertexDescriptor: vertexDescriptor,
            colorAttachments: material.attachments.enumerated().map {
                index, attr in
                RenderPipelineColorAttachmentDescriptor(
                    index: index,
                    pixelFormat: attr.format,
                    blendState: attr.blendState)
            },
            depthStencilAttachmentPixelFormat: material.depthFormat,
            primitiveTopology: self.primitiveType,
            triangleFillMode: material.triangleFillMode,
            rasterizationEnabled: true)

        var reflection = PipelineReflection()
        guard let pso = device.makeRenderPipelineState(
            descriptor: pipelineDescriptor,
            reflection: &reflection)
        else {
            Log.error("GraphicsDevice.makeRenderPipelineState failed.")
            return false
        }

        let strict = true

        // setup binding table
        struct OptResourceBindingSet {
            let index: Int
            var bindingSet: ShaderBindingSet?
            var resources: [ResourceBinding] = []
        }

        var resourceBindingsTmp: [OptResourceBindingSet] = []
        for res in reflection.resources {
            let location = ShaderBindingLocation(set: res.set,
                                                 binding: res.binding,
                                                 offset: 0)
            if let descriptor = material.shader.descriptor(location: location,
                                                           stages: res.stages) {
                let type: ShaderResourceType = switch descriptor.type {
                case .uniformBuffer, .storageBuffer, .uniformTexelBuffer, .storageTexelBuffer:
                        .buffer
                case .storageTexture, .texture:
                        .texture
                case .textureSampler:
                        .textureSampler
                case .sampler:
                        .sampler
                }
                if type == res.type {
                    var rbset = OptResourceBindingSet(index: res.set)
                    let index = resourceBindingsTmp.firstIndex {
                        $0.index == res.set
                    }
                    if let index {
                        rbset = resourceBindingsTmp[index]
                    }

                    let binding = ShaderBinding(binding: res.binding,
                                                type: descriptor.type,
                                                arrayLength: descriptor.count)
                    let resource = ResourceBinding(resource: res,
                                                   binding: binding)
                    rbset.resources.append(resource)

                    if let index {
                        resourceBindingsTmp[index] = rbset
                    } else {
                        resourceBindingsTmp.append(rbset)
                    }
                } else {
                    Log.error("Unable to find shader resource information (set: \(res.set), binding: \(res.binding), name: \(res.name))")
                    if strict { return false }
                }
            } else {
                Log.error("Unable to find shader resource descriptor. (name: \(res.name))")
                if strict { return false }
            }
        }
        resourceBindingsTmp.sort { $0.index < $1.index }
        for i in 0..<resourceBindingsTmp.count {
            var rbs = resourceBindingsTmp[i]
            rbs.resources.sort { $0.binding.binding < $1.binding.binding }

            let layout = ShaderBindingSetLayout(
                bindings: rbs.resources.map { $0.binding })

            rbs.bindingSet = device.makeShaderBindingSet(layout: layout)
            if rbs.bindingSet == nil {
                Log.error("GraphicsDevice.makeShaderBindingSet failed.")
                return false
            }
            resourceBindingsTmp[i] = rbs
        }

        if let ref {
            ref.pointee = reflection
        }

        self.pipelineState = pso
        self.pipelineReflection = reflection
        self.resourceBindings = resourceBindingsTmp.map {
            ResourceBindingSet(index: $0.index,
                               bindingSet: $0.bindingSet!,
                               resources: $0.resources)
        }
        self.pushConstants = reflection.pushConstantLayouts.map { layout in
            PushConstantData(layout: layout, data: [])
        }
        return true
    }

    public func updateShadingProperties(sceneState: SceneState?) {
        guard let material else { return }

        struct StructMemberBind {
            let sceneState: SceneState?
            let mesh: Mesh
            let member: ShaderResourceStructMember
            let parentPath: String
            let arrayIndex: Int
            let set: Int
            let binding: Int
            let offset: Int // struct offset

            func bind(buffer: UnsafeMutableRawBufferPointer) -> Int {
                let bindingOffset = member.offset + self.offset

                assert(member.size <= buffer.count)

                let path = if self.parentPath.count > 0 {
                    "\(self.parentPath).\(member.name)"
                } else {
                    member.name
                }

                var copied = 0
                if member.dataType == .struct {
                    for m in member.members {
                        if m.offset >= buffer.count { continue }
                        if m.offset + m.size > buffer.count { continue }

                        let s = StructMemberBind(sceneState: sceneState,
                                                 mesh: mesh,
                                                 member: m,
                                                 parentPath: path,
                                                 arrayIndex: arrayIndex,
                                                 set: set, binding: binding,
                                                 offset: bindingOffset)
                            .bind(buffer: .init(rebasing: buffer[m.offset...]))
                        if s == 0 {
                            Log.warning("Unable to bind shader uniform struct element: \(set) name: \(path)")
                        }
                        copied = member.offset + s
                    }
                } else {
                    // find semantic
                    let material = mesh.material!
                    let location = ShaderBindingLocation(set: set,
                                                         binding: binding,
                                                         offset: bindingOffset)
                    let semantic = material.shader.resourceSemantics[location] ?? .material(.userDefined)

                    if case let .uniform(ss) = semantic {
                        if let sceneState {
                            copied = mesh.bindShaderUniformBuffer(
                                semantic: ss,
                                dataType: member.dataType,
                                name: path,
                                sceneState: sceneState,
                                buffer: buffer)
                        }
                    }
                    if copied == 0 {
                        let ms: MaterialSemantic
                        if case let .material(ss) = semantic {
                            ms = ss
                        } else {
                            ms = .userDefined
                        }

                        let offset = member.count * member.stride * arrayIndex
                        copied = mesh.bindMaterialProperty(semantic: ms,
                                                           location: location,
                                                           dataType: member.dataType,
                                                           name: path,
                                                           offset: offset,
                                                           buffer: buffer)
                    }
                    if copied == 0 {
                        //Log.warning("Unable to bind shader uniform struct (\(location)), arrayIndex: \(arrayIndex), name:\"\(path)\"")
                    }
                }
                return copied
            }
        }

        let copyStructProperty = {
            (type: ShaderDataType,
             set: Int,
             binding: Int,
             offset: Int,
             size: Int,
             stride: Int,
             arrayIndex: Int,
             members: [ShaderResourceStructMember],
             name: String,
             buffer: UnsafeMutableRawBufferPointer) -> Int in

            let location = ShaderBindingLocation(set: set,
                                                 binding: binding,
                                                 offset: offset)

            let semantic = material.shader.resourceSemantics[location] ?? .material(.userDefined)

            var copied = 0
            if type == .struct {
                if case let .material(ms) = semantic {
                    copied = self.bindMaterialProperty(semantic: ms,
                                                       location: location,
                                                       dataType: type,
                                                       name: name,
                                                       offset: offset,
                                                       buffer: buffer)
                }
                if copied != size {
                    // The entire buffer wasn't copied,
                    // so we split it into members of a struct and try to copy it.
                    copied = 0
                    for member in members {
                        if member.offset < offset { continue }
                        if member.offset >= (offset + size) { break }
                        if member.offset + member.size > offset + size { break }

                        let path = if name.isEmpty == false && member.name.isEmpty == false {
                            "\(name).\(member.name)"
                        } else {
                            member.name
                        }

                        if member.offset + member.size - offset > buffer.count {
                            Log.error("Insufficient buffer for shader uniform struct at location:\(location), size:\(size), name:\"\(path)\"")
                            break
                        }

                        let d = member.offset - offset
                        let s = StructMemberBind(sceneState: sceneState,
                                                 mesh: self,
                                                 member: member,
                                                 parentPath: name,
                                                 arrayIndex: arrayIndex,
                                                 set: set,
                                                 binding: binding,
                                                 offset: 0)
                            .bind(buffer: .init(rebasing: buffer[d...]))

                        if s > 0 {
                            copied += s
                        } else {
                            if copied < d + member.size { // Failed to copy data.
                                let loc = ShaderBindingLocation(set: set, binding: binding, offset: member.offset)
                                Log.warning("Unable to bind shader uniform struct at location:\(loc), size:\(size), name:\"\(path)\"")
                            }
                        }
                    }
                }
            } else {
                if case let .uniform(ss) = semantic {
                    if let sceneState {
                        copied = self.bindShaderUniformBuffer(semantic: ss,
                                                              dataType: type,
                                                              name: name,
                                                              sceneState: sceneState,
                                                              buffer: buffer)
                    }
                }
                if copied == 0 {
                    let ms: MaterialSemantic
                    if case let .material(ss) = semantic {
                        ms = ss
                    } else {
                        ms = .userDefined
                    }
                    let offset = arrayIndex * stride
                    copied = self.bindMaterialProperty(semantic: ms,
                                                       location: location,
                                                       dataType: type,
                                                       name: name,
                                                       offset: offset,
                                                       buffer: buffer)
                }
                if copied == 0 {
                    Log.warning("Unable to bind shader uniform struct (\(location)), arrayIndex: \(arrayIndex), name:\"\(name)\"")
                }
            }
            return copied
        }

        for rbs in self.resourceBindings {
            for rb in rbs.resources {
                let res = rb.resource
                if res.type == .buffer {
                    let typeInfo = res.bufferTypeInfo!
                    let loc = ShaderBindingLocation(set: res.set, binding: res.binding, offset: 0)
                    if let buffers = self.bufferResources[loc]?.buffers {
                        var updatedBuffers: [BufferBindingInfo] = []
                        let validBufferCount = min(buffers.count, res.count)
                        updatedBuffers.reserveCapacity(validBufferCount)

                        for index in 0..<validBufferCount {
                            let bufferInfo = buffers[index]
                            if bufferInfo.offset + bufferInfo.length <= bufferInfo.buffer.length {
                                if let ptr = bufferInfo.buffer.contents() {
                                    let buffer = UnsafeMutableRawBufferPointer(
                                        start: ptr + bufferInfo.offset,
                                        count: bufferInfo.length)

                                    let copied = copyStructProperty(
                                        typeInfo.dataType,
                                        res.set,
                                        res.binding,
                                        0,
                                        typeInfo.size,
                                        res.stride,
                                        index,
                                        res.members,
                                        res.name,
                                        buffer)
                                    if copied > 0 {
                                        bufferInfo.buffer.flush()
                                    }
                                    updatedBuffers.append(bufferInfo)
                                } else {
                                    Log.error("Failed to map buffer for resource set:\(res.set), binding:\(res.binding), name:\"\(res.name)\"")
                                }
                            } else {
                                Log.error("buffer is too small for resource set:\(res.set), binding:\(res.binding), name:\"\(res.name)\"")
                                updatedBuffers.removeAll()
                                break
                            }
                        }
                        if updatedBuffers.isEmpty == false {
                            rbs.bindingSet.setBufferArray(updatedBuffers, binding: res.binding)
                        } else {
                            Log.error("Failed to bind buffer resource set:\(res.set), binding:\(res.binding), name:\"\(res.name)\"")
                        }
                    }
                } else {
                    let location = ShaderBindingLocation(set: res.set,
                                                         binding: res.binding,
                                                         offset: 0)
                    let semantic = material.shader.resourceSemantics[location] ?? .material(.userDefined)

                    var bounds = 0
                    if case let .uniform(ss) = semantic {
                        if let sceneState {
                            switch res.type {
                            case .texture:
                                bounds = self.bindShaderUniformTextures(semantic: ss, name: res.name, sceneState: sceneState, bindingSet: rbs.bindingSet)
                            case .sampler:
                                bounds = self.bindShaderUniformSamplers(semantic: ss, name: res.name, sceneState: sceneState, bindingSet: rbs.bindingSet)
                            case .textureSampler:
                                let b1 = self.bindShaderUniformTextures(semantic: ss, name: res.name, sceneState: sceneState, bindingSet: rbs.bindingSet)
                                let b2 = self.bindShaderUniformSamplers(semantic: ss, name: res.name, sceneState: sceneState, bindingSet: rbs.bindingSet)
                                bounds = min(b1,b2)
                            case .buffer:
                                break
                            }
                        }
                    }
                    if bounds == 0 {
                        let ms: MaterialSemantic
                        if case let .material(ss) = semantic {
                            ms = ss
                        } else {
                            ms = .userDefined
                        }
                        switch res.type {
                        case .texture:
                            bounds = self.bindMaterialTextures(semantic: ms, resource: res, bindingSet: rbs.bindingSet)
                        case .sampler:
                            bounds = self.bindMaterialSamplers(semantic: ms, resource: res, bindingSet: rbs.bindingSet)
                        case .textureSampler:
                            let b1 = self.bindMaterialTextures(semantic: ms, resource: res, bindingSet: rbs.bindingSet)
                            let b2 = self.bindMaterialSamplers(semantic: ms, resource: res, bindingSet: rbs.bindingSet)
                            bounds = min(b1,b2)
                        case .buffer:
                            break
                        }
                    }

                    if bounds == 0 {
                        Log.error("Failed to bind resource: \(res.binding) (name:\"\(res.name)\", type:\(res.type))")
                    }
                }
            }
        }
        for i in 0..<self.pushConstants.count {
            var pc = self.pushConstants[i]
            if pc.layout.size == 0 { continue }

            if pc.data.count != pc.layout.size {
                pc.data = .init(repeating: 0, count: pc.layout.size)
            }
            pc.data.withUnsafeMutableBytes { buffer in
                let location = ShaderBindingLocation.pushConstant(offset: pc.layout.offset)
                _=copyStructProperty(.struct,
                                     location.set,
                                     location.binding,
                                     location.offset,
                                     pc.layout.size,
                                     pc.layout.size,  // stride
                                     0,               // arrayIndex
                                     pc.layout.members,
                                     pc.layout.name,
                                     buffer)
            }
            self.pushConstants[i] = pc
        }
    }

    func bindMaterialTextures(semantic: MaterialSemantic,
                              resource: ShaderResource,
                              bindingSet: ShaderBindingSet) -> Int {
        guard let material else { return 0 }

        var textures: [Texture] = []
        if semantic != .userDefined {
            if let prop = material.properties[semantic] {
                textures = prop.textures()
            }
        }
        if textures.isEmpty {
            let location = ShaderBindingLocation(set: resource.set,
                                                 binding: resource.binding,
                                                 offset: 0)
            if let prop = material.userDefinedProperties[location] {
                textures = prop.textures()
            }
        }
        if textures.isEmpty {
            if let texture = material.defaultTexture {
                textures.append(texture)
            }
        }
        if textures.isEmpty == false {
            let n = min(resource.count, textures.count)
            bindingSet.setTextureArray(textures, binding: resource.binding)
            return n
        }
        return 0
    }

    func bindMaterialSamplers(semantic: MaterialSemantic,
                              resource: ShaderResource,
                              bindingSet: ShaderBindingSet) -> Int {
        guard let material else { return 0 }

        var samplers: [SamplerState] = []
        if semantic != .userDefined {
            if let prop = material.properties[semantic] {
                samplers = prop.samplers()
            }
        }
        if samplers.isEmpty {
            let location = ShaderBindingLocation(set: resource.set,
                                                 binding: resource.binding,
                                                 offset: 0)
            if let prop = material.userDefinedProperties[location] {
                samplers = prop.samplers()
            }
        }
        if samplers.isEmpty {
            if let sampler = material.defaultSampler {
                samplers.append(sampler)
            }
        }
        if samplers.isEmpty == false {
            let n = min(resource.count, samplers.count)
            bindingSet.setSamplerStateArray(samplers, binding: resource.binding)
            return n
        }
        return 0
    }

    func bindMaterialProperty(semantic: MaterialSemantic,
                              location: ShaderBindingLocation,
                              dataType: ShaderDataType,
                              name: String,
                              offset: Int,
                              buffer: UnsafeMutableRawBufferPointer) -> Int {
        guard let material else { return 0 }

        var data: [UInt8] = []

        func bindNumerics<T: Numeric>(as: T.Type, array: [any Numeric]) {
            let numerics = array.map { $0 as! T }
            numerics.withUnsafeBytes {
                data.append(contentsOf: $0)
            }
        }

        let bind = { (prop: MaterialProperty) in
            if case let .buffer(buffer) = prop {
                data = buffer
            } else {
                if let components = dataType.components() {
                    let numerics = prop.castNumericArray(as: components.type)
                    bindNumerics(as: components.type, array: numerics)
                }
            }
        }

        if semantic != .userDefined {
            if let prop = material.properties[semantic] {
                bind(prop)
            }
        }
        if data.isEmpty {
            if let prop = material.userDefinedProperties[location] {
                bind(prop)
            }
        }
        if data.isEmpty == false {
            if data.count > offset {
                let s = min(data.count - offset, buffer.count)
                buffer.copyBytes(from: data[0..<s])
                return s
            }
        }
        return 0
    }

    func bindShaderUniformTextures(semantic: ShaderUniformSemantic,
                                   name: String,
                                   sceneState: SceneState,
                                   bindingSet: ShaderBindingSet) -> Int {
        Log.warn("No textures for ShaderUniformSemantic: \(semantic), name:\"\(name)\"")
        return 0
    }

    func bindShaderUniformSamplers(semantic: ShaderUniformSemantic,
                                   name: String,
                                   sceneState: SceneState,
                                   bindingSet: ShaderBindingSet) -> Int {
        Log.warn("No samplers for ShaderUniformSemantic: \(semantic), name:\"\(name)\"")
        return 0
    }

    func bindShaderUniformBuffer(semantic: ShaderUniformSemantic,
                                 dataType: ShaderDataType,
                                 name: String,
                                 sceneState: SceneState,
                                 buffer: UnsafeMutableRawBufferPointer) -> Int {
        let bindMatrix4 = { (matrix: Matrix4) in
            if dataType == .float4x4 {
                return withUnsafeBytes(of: matrix.float4x4) {
                    buffer.copyBytes(from: $0)
                    return $0.count
                }
            }
            if dataType == .float3x3 {
                let mat = Matrix3(matrix.m11, matrix.m12, matrix.m13,
                                  matrix.m21, matrix.m22, matrix.m23,
                                  matrix.m31, matrix.m32, matrix.m33)
                return withUnsafeBytes(of: mat.float3x3) {
                    buffer.copyBytes(from: $0)
                    return $0.count
                }
            }
            return 0
        }

        switch semantic {
        case .modelMatrix:
            return bindMatrix4(sceneState.model)
        case .viewMatrix:
            return bindMatrix4(sceneState.view.matrix4)
        case .projectionMatrix:
            return bindMatrix4(sceneState.projection.matrix)
        case .viewProjectionMatrix:
            return bindMatrix4(sceneState.view.matrix4
                .concatenating(sceneState.projection.matrix))
        case .modelViewProjectionMatrix:
            return bindMatrix4(sceneState.model
                .concatenating(sceneState.view.matrix4)
                .concatenating(sceneState.projection.matrix))
        case .inverseModelMatrix:
            return bindMatrix4(sceneState.model.inverted() ?? .identity)
        case .inverseViewMatrix:
            return bindMatrix4(sceneState.view.matrix4.inverted() ?? .identity)
        case .inverseProjectionMatrix:
            return bindMatrix4(sceneState.projection.matrix
                .inverted() ?? .identity)
        case .inverseViewProjectionMatrix:
            return bindMatrix4(sceneState.view.matrix4
                .concatenating(sceneState.projection.matrix)
                .inverted() ?? .identity)
        case .inverseModelViewProjectionMatrix:
            return bindMatrix4(sceneState.model
                .concatenating(sceneState.view.matrix4)
                .concatenating(sceneState.projection.matrix)
                .inverted() ?? .identity)
        default:
            Log.error("Not supported or not yet implemented.")
        }
        return 0
    }

    @discardableResult
    public func encodeRenderCommand(encoder: RenderCommandEncoder, numInstances: Int = 1, baseInstance: Int = 0) -> Bool {
        if let pipelineState, let material, vertexBuffers.isEmpty == false {
            let vertexBuffers = self.availableVertexBuffers(for: material)
            if vertexBuffers.isEmpty { return false }

            encoder.setRenderPipelineState(pipelineState)
            encoder.setFrontFacing(material.frontFace)
            encoder.setCullMode(material.cullMode)

            self.resourceBindings.forEach {
                encoder.setResource($0.bindingSet, index: $0.index)
            }
            if self.pushConstants.isEmpty == false {
                var begin = pushConstants[0].layout.offset
                var end = begin
                var stages: ShaderStageFlags = []

                self.pushConstants.forEach { pc in
                    begin = min(begin, pc.layout.offset)
                    end = max(end, pc.layout.offset + pc.layout.size)
                    stages = stages.union(pc.layout.stages)
                }
                let bufferSize = end - begin
                if bufferSize > 0 && stages.rawValue != 0 {
                    var buffer: [UInt8] = .init(repeating: 0, count: bufferSize)
                    buffer.withUnsafeMutableBytes { ptr in
                        for pc in self.pushConstants {
                            if pc.data.count < pc.layout.size {
                                Log.error("PushConstant (name:\"\(pc.layout.name)\", offset:\(pc.layout.offset), size:\(pc.layout.size)) data is missing!")
                                continue
                            }
                            let data = pc.data[..<pc.layout.size]
                            let addr = ptr[pc.layout.offset...]
                            UnsafeMutableRawBufferPointer(rebasing: addr)
                                .copyBytes(from: data)
                        }
                    }

                    encoder.pushConstant(stages: stages, offset: begin, data: buffer)
                }
            }
            vertexBuffers.enumerated().forEach { index, vb in
                encoder.setVertexBuffer(vb.buffer, offset: vb.byteOffset, index: index)
            }

            let vertexCount = vertexBuffers.reduce(vertexBuffers[0].vertexCount) {
                count, vb in
                min(count, vb.vertexCount)
            }
            if vertexCount > 0 {
                if let indexBuffer {
                    encoder.drawIndexed(indexCount: self.indexCount,
                                        indexType: self.indexType,
                                        indexBuffer: indexBuffer,
                                        indexBufferOffset: self.indexBufferByteOffset,
                                        instanceCount: numInstances,
                                        baseVertex: self.indexBufferBaseVertexIndex,
                                        baseInstance: baseInstance)
                } else {
                    if vertexCount > self.vertexStart {
                        encoder.draw(vertexStart: vertexStart,
                                     vertexCount: vertexCount - vertexStart,
                                     instanceCount: numInstances,
                                     baseInstance: baseInstance)
                    }
                }
            }
            return true
        }
        return false
    }

    public func enumerateVertexBufferContent(semantic: VertexAttributeSemantic,
                                             context: GraphicsDeviceContext,
                                             _ handler: ((_:UnsafeRawPointer, _:VertexFormat, Int)-> Bool)? = nil) -> Bool {
        var attrib: VertexAttribute? = nil
        var vertexBuffer: VertexBuffer? = nil

        for vb in self.vertexBuffers {
            attrib = vb.attributes.first(where: { $0.semantic == semantic })
            if attrib != nil {
                vertexBuffer = vb
                break
            }
        }
        if let attrib, let vertexBuffer {
            guard let handler else { return true }

            if let buffer = context.makeCPUAccessible(buffer: vertexBuffer.buffer) {
                if var mapped = buffer.contents() {
                    mapped += vertexBuffer.byteOffset + attrib.offset
                    for i in 0..<vertexBuffer.vertexCount {
                        // stop enumeration if the handler returns false.
                        if handler(mapped, attrib.format, i) == false {
                            return true
                        }
                        mapped += vertexBuffer.byteStride
                    }
                    return true
                }
            }
        }
        return false
    }

    public func enumerateIndexBufferContent(context: GraphicsDeviceContext,
                                            _ handler: ((_:Int)-> Bool)? = nil) -> Bool {
        if let indexBuffer {
            guard indexCount > 0 else { return true }
            guard let handler else { return true }

            if let buffer = context.makeCPUAccessible(buffer: indexBuffer) {
                if var mapped = buffer.contents() {
                    mapped += indexBufferByteOffset
                    let base = indexBufferBaseVertexIndex

                    switch self.indexType {
                    case .uint16:
                        let p = mapped.assumingMemoryBound(to: UInt16.self)
                        for i in 0..<self.indexCount {
                            let index = p[i]
                            if handler(Int(index) + base) == false {
                                return true
                            }
                        }
                    case .uint32:
                        let p = mapped.assumingMemoryBound(to: UInt32.self)
                        for i in 0..<self.indexCount {
                            let index = p[i]
                            if handler(Int(index) + base) == false {
                                return true
                            }
                        }
                    }
                    return true
                }
            }
        }
        return false
    }
}
