import SPIRV_Cross
import Foundation

public struct ShaderAttribute {
    public var name : String
    public var location : UInt32
    public var type : ShaderDataType
    public var enabled : Bool
}

public enum ShaderDescriptorType {
    case uniformBuffer
    case storageBuffer
    case storageTexture
    case uniformTexelBuffer // readonly texture 'buffer'
    case storageTexelBuffer // writable texture 'buffer'
    case textureSampler     // texture, sampler combined
    case texture
    case sampler
}

public struct ShaderDescriptor {
    public var set : UInt32
    public var binding : UInt32
    public var count : UInt32 // array size
    public var type : ShaderDescriptorType
}

private func dataTypeFromSPVC(type: spvc_type) -> ShaderDataType {

    let basetype = spvc_type_get_basetype(type)
    let vecsize = spvc_type_get_vector_size(type)
    let columns = spvc_type_get_columns(type)
    let bitwidth = spvc_type_get_bit_width(type)

    switch basetype {
    case SPVC_BASETYPE_UNKNOWN: return .unknown
	case SPVC_BASETYPE_VOID:    return .none
	case SPVC_BASETYPE_BOOLEAN:
        switch vecsize {
        case 1:     return .bool
        case 2:     return .boolV2
        case 3:     return .boolV3
        case 4:     return .boolV4
        default:    break
        }
	case SPVC_BASETYPE_INT8:
        switch vecsize {
        case 1:     return .int8
        case 2:     return .int8V2
        case 3:     return .int8V3
        case 4:     return .int8V4
        default:    break
        }
	case SPVC_BASETYPE_UINT8:
        switch vecsize {
        case 1:     return .uint8
        case 2:     return .uint8V2
        case 3:     return .uint8V3
        case 4:     return .uint8V4
        default:    break
        }
	case SPVC_BASETYPE_INT16:
        switch vecsize {
        case 1:     return .int16
        case 2:     return .int16V2
        case 3:     return .int16V3
        case 4:     return .int16V4
        default:    break
        }
	case SPVC_BASETYPE_UINT16:
        switch vecsize {
        case 1:     return .uint16
        case 2:     return .uint16V2
        case 3:     return .uint16V3
        case 4:     return .uint16V4
        default:    break
        }
	case SPVC_BASETYPE_INT32:
        switch vecsize {
        case 1:     return .int32
        case 2:     return .int32V2
        case 3:     return .int32V3
        case 4:     return .int32V4
        default:    break
        }
	case SPVC_BASETYPE_UINT32:
        switch vecsize {
        case 1:     return .uint32
        case 2:     return .uint32V2
        case 3:     return .uint32V3
        case 4:     return .uint32V4
        default:    break
        }
	case SPVC_BASETYPE_INT64:
        switch vecsize {
        case 1:     return .int64
        case 2:     return .int64V2
        case 3:     return .int64V3
        case 4:     return .int64V4
        default:    break
        }
	case SPVC_BASETYPE_UINT64:
        switch vecsize {
        case 1:     return .uint16
        case 2:     return .uint16V2
        case 3:     return .uint16V3
        case 4:     return .uint16V4
        default:    break
        }
	case SPVC_BASETYPE_FP16:
        switch (vecsize, columns) {
        case (1, _):    return .float16
        case (2, 1):    return .float16V2
        case (3, 1):    return .float16V3
        case (4, 1):    return .float16V4
        case (2, 2):    return .float16M2x2
        case (3, 2):    return .float16M3x2
        case (4, 2):    return .float16M4x2
        case (2, 3):    return .float16M2x3
        case (3, 3):    return .float16M3x3
        case (4, 3):    return .float16M4x3
        case (2, 4):    return .float16M2x4
        case (3, 4):    return .float16M3x4
        case (4, 4):    return .float16M4x4
        default:        break
        }
	case SPVC_BASETYPE_FP32:
        switch (vecsize, columns) {
        case (1, _):    return .float32
        case (2, 1):    return .float32V2
        case (3, 1):    return .float32V3
        case (4, 1):    return .float32V4
        case (2, 2):    return .float32M2x2
        case (3, 2):    return .float32M3x2
        case (4, 2):    return .float32M4x2
        case (2, 3):    return .float32M2x3
        case (3, 3):    return .float32M3x3
        case (4, 3):    return .float32M4x3
        case (2, 4):    return .float32M2x4
        case (3, 4):    return .float32M3x4
        case (4, 4):    return .float32M4x4
        default:        break
        }
	case SPVC_BASETYPE_FP64:
        switch (vecsize, columns) {
        case (1, _):    return .float64
        case (2, 1):    return .float64V2
        case (3, 1):    return .float64V3
        case (4, 1):    return .float64V4
        case (2, 2):    return .float64M2x2
        case (3, 2):    return .float64M3x2
        case (4, 2):    return .float64M4x2
        case (2, 3):    return .float64M2x3
        case (3, 3):    return .float64M3x3
        case (4, 3):    return .float64M4x3
        case (2, 4):    return .float64M2x4
        case (3, 4):    return .float64M3x4
        case (4, 4):    return .float64M4x4
        default:        break
        }
	case SPVC_BASETYPE_STRUCT:          return .struct
	case SPVC_BASETYPE_IMAGE,
	     SPVC_BASETYPE_SAMPLED_IMAGE:   return .texture
	case SPVC_BASETYPE_SAMPLER:         return .sampler
    default:
        break
    }
    Log.err("Unsupported type:\(basetype) (bit-width:\(bitwidth), vector-size:\(vecsize), columns:\(columns))")
    return .unknown
}

private enum SPVCError: Error {
    case spvcResult(spvc_result)
    case runtimeError(String)
    case unknownError
}

private func stageFromSPVC(compiler: spvc_compiler) -> ShaderStage {
    switch spvc_compiler_get_execution_model(compiler) {
    case SpvExecutionModelVertex:
        return .vertex
    case SpvExecutionModelTessellationControl:
        return .tessellationControl
    case SpvExecutionModelTessellationEvaluation:
        return .tessellationEvaluation
    case SpvExecutionModelGeometry:
        return .geometry
    case SpvExecutionModelFragment:
        return .fragment
    case SpvExecutionModelGLCompute:
        return .compute
    default:
        break 
    }
    // Log.err("Unknown shader type")
    return .unknown
}

private func descriptorFromSPVC(compiler: spvc_compiler,
                                resource: spvc_reflected_resource,
                                type: ShaderDescriptorType) -> ShaderDescriptor {
    let set = spvc_compiler_get_decoration(compiler, resource.id, SpvDecorationDescriptorSet)
    let binding = spvc_compiler_get_decoration(compiler, resource.id, SpvDecorationBinding)

    // get array length
    let spvcType = spvc_compiler_get_type_handle(compiler, resource.type_id)
    var count: UInt32 = 1
    for i in 0..<spvc_type_get_num_array_dimensions(spvcType) {
        count = count * spvc_type_get_array_dimension(spvcType, i)
    }
    return ShaderDescriptor(set: set, binding: binding, count: count, type: type)
}

private func resourceStructMembersFromSPVC(compiler: spvc_compiler,
                                           type: spvc_type) throws -> [ShaderResourceStructMember] {

    var members: [ShaderResourceStructMember] = []
    for i in 0..<spvc_type_get_num_member_types(type) {
        let memberTypeId = spvc_type_get_member_type(type, i)
        let memberType = spvc_compiler_get_type_handle(compiler, memberTypeId)
        let dataType = dataTypeFromSPVC(type: memberType!)
        assert(dataType != .unknown)
        assert(dataType != .none)

        let name = String(cString: spvc_compiler_get_member_name(compiler, spvc_type_get_base_type_id(type), i))
        var offset: UInt32 = 0
        var result = spvc_compiler_type_struct_member_offset(compiler, type, i, &offset)
        if result != SPVC_SUCCESS { throw SPVCError.spvcResult(result) }

        var size: Int = 0
        result = spvc_compiler_get_declared_struct_member_size(compiler, type, i, &size)
        if result != SPVC_SUCCESS { throw SPVCError.spvcResult(result) }
        assert(size > 0)

        var count: UInt32 = 0
        for n in 0..<spvc_type_get_num_array_dimensions(type) {
            count = count * spvc_type_get_array_dimension(type, n)
        }

        var stride: UInt32 = 0
        if count > 1 {
            result = spvc_compiler_type_struct_member_array_stride(compiler, type, i, &stride)
            if result != SPVC_SUCCESS { throw SPVCError.spvcResult(result) }
        }

        var structMembers: [ShaderResourceStructMember] = []
        if dataType == .struct {
            structMembers = try resourceStructMembersFromSPVC(compiler: compiler, type: memberType!)
        }

        members.append(ShaderResourceStructMember(dataType: dataType,
                                                  name: name,
                                                  offset: offset,
                                                  size: UInt32(size),
                                                  count: count,
                                                  stride: stride,
                                                  members:structMembers))
    }
    return members
}

private func resourceFromSPVC(compiler: spvc_compiler,
                              resource: spvc_reflected_resource,
                              enabled: Bool,
                              access: ShaderResourceAccess) throws -> ShaderResource {

    let set = spvc_compiler_get_decoration(compiler, resource.id, SpvDecorationDescriptorSet)
    let binding = spvc_compiler_get_decoration(compiler, resource.id, SpvDecorationBinding)
    let name = String(cString: resource.name)

    let stage = stageFromSPVC(compiler: compiler)
    assert(stage != .unknown)
    let stride = spvc_compiler_get_decoration(compiler, resource.id, SpvDecorationArrayStride)
    let spvctype = spvc_compiler_get_type_handle(compiler, resource.type_id)

    // get array length
    var count: UInt32 = 1
    for n in 0..<spvc_type_get_num_array_dimensions(spvctype) {
        count = count * spvc_type_get_array_dimension(spvctype, n)
    }

    var type: ShaderResourceType = .buffer
    var bufferTypeInfo: ShaderResourceBuffer? = nil
    var textureTypeInfo : ShaderResourceTexture? = nil

    let textureType = { () -> TextureType in
        switch spvc_type_get_image_dimension(spvctype) {
            case SpvDim1D:  return .type1D
            case SpvDim2D:  return .type2D
            case SpvDim3D:  return .type3D
            case SpvDimCube:    return .typeCube
            default:        return .unknown
        }
    }

    switch spvc_type_get_basetype(spvctype) {
    case SPVC_BASETYPE_IMAGE:
        type = .texture
        textureTypeInfo = ShaderResourceTexture(dataType: .texture, textureType: textureType())
    case SPVC_BASETYPE_SAMPLED_IMAGE:
        type = .textureSampler
        textureTypeInfo = ShaderResourceTexture(dataType: .texture, textureType: textureType())
    case SPVC_BASETYPE_SAMPLER:
        type = .sampler
    case SPVC_BASETYPE_STRUCT:
        type = .buffer
        let alignment = spvc_compiler_get_decoration(compiler, resource.id, SpvDecorationAlignment)
        var size: Int = 0
        let result = spvc_compiler_get_declared_struct_size(compiler, spvctype, &size)
        if result != SPVC_SUCCESS { throw SPVCError.spvcResult(result) }

        bufferTypeInfo = ShaderResourceBuffer(dataType: .struct, alignment: alignment, size: UInt32(size))
    default:
        assert(false, "Unsupported shader resource type")
    }

    let basetype = spvc_compiler_get_type_handle(compiler, resource.base_type_id)
    let members: [ShaderResourceStructMember] = try resourceStructMembersFromSPVC(compiler: compiler, type: basetype!)

    return ShaderResource(set: set,
        binding: binding,
        name: name,
        type: type,
        stages: ShaderStageFlags(stage: stage),
        count: count,
        stride: stride,
        enabled: enabled,
        access: access,
        bufferTypeInfo: bufferTypeInfo,
        textureTypeInfo: textureTypeInfo,
        threadgroupTypeInfo: nil,
        members: members)
}

private func attributeFromSPVC(compiler: spvc_compiler,
                               resource: spvc_reflected_resource,
                               enabled: Bool) throws -> ShaderAttribute {
    let location = spvc_compiler_get_decoration(compiler, resource.id, SpvDecorationLocation)
    let name = String(cString: resource.name)
    let spvctype = spvc_compiler_get_type_handle(compiler, resource.type_id)
    let type = dataTypeFromSPVC(type: spvctype!)
    assert(type != .unknown)

    // get array length
    var count: UInt32 = 1
    for n in 0..<spvc_type_get_num_array_dimensions(spvctype) {
        count = count * spvc_type_get_array_dimension(spvctype, n)
    }
    
    return ShaderAttribute(name: name,
                          location: location,
                          type: type,
                          enabled: enabled)
}

public class Shader: CustomStringConvertible {
    public private(set) var stage: ShaderStage
    public private(set) var spirvData: [UInt32]

    public private(set) var functionNames: [String]
    public private(set) var inputAttributes: [ShaderAttribute]
    public private(set) var outputAttributes: [ShaderAttribute]
    public private(set) var resources: [ShaderResource]

    public private(set) var pushConstantLayouts: [ShaderPushConstantLayout]
    public private(set) var descriptors: [ShaderDescriptor]
    public private(set) var threadgroupSize: (x: UInt32, y: UInt32, z: UInt32)

    public var name: String

    public init(name: String? = nil) {
        self.stage = .unknown
        self.spirvData = []

        self.functionNames = []
        self.inputAttributes = []
        self.outputAttributes = []
        self.resources = []

        self.pushConstantLayouts = []
        self.descriptors = []

        self.threadgroupSize = (x: 1, y: 1, z: 1)
        self.name = name ?? ""
    }

    public convenience init?(data: UnsafeBufferPointer<UInt32>, name: String? = nil) {
        self.init(name: name)
        if self.compile(data: data) == false {
            return nil
        }
    }

    public convenience init?<D>(data: D, name: String? = nil) where D: DataProtocol {
        self.init(name: name)
        if self.compile(data: data) == false {
            return nil
        }
    }

    public func compile<D>(data: D) -> Bool where D: DataProtocol {
        if data.count > 4 {
            let numWords = data.count / 4
            let array: [UInt32] = .init(unsafeUninitializedCapacity: numWords) {
                data.copyBytes(to: $0, count: data.count)
                $1 = numWords
            }
            return array.withUnsafeBufferPointer { compile(data: $0) }
        }
        return false
    }

    public func compile(data: UnsafeBufferPointer<UInt32>) -> Bool {
        guard data.count > 0 else { return false }

        class SPVCErrorCallback {
            var message: String = String()
        }

        var result: spvc_result = SPVC_SUCCESS
        let spverror = SPVCErrorCallback()
        var context: spvc_context? = nil

        spvc_context_create(&context)
        spvc_context_set_error_callback(context, {
            (userdata: UnsafeMutableRawPointer?, errorMessage: UnsafePointer<CChar>?) in
            Log.err("SPIRV-Cross: \(String(cString: errorMessage!))")

            let obj: AnyObject? = unsafeBitCast(userdata, to: AnyObject.self)
            if let cb = obj as? SPVCErrorCallback {
                cb.message = String(cString: errorMessage!)
            } else {
                fatalError("Unable to recover object")
            }
        }, unsafeBitCast(spverror as AnyObject, to: UnsafeMutableRawPointer.self))

        defer {
            spvc_context_destroy(context)
            if spverror.message.isEmpty == false {
                Log.err("Shader.compile() error: \"\(spverror.message)\", \(result)")
            }
        }

        do {
            var ir: spvc_parsed_ir? = nil
            result = spvc_context_parse_spirv(context, data.baseAddress, data.count, &ir)
            if result != SPVC_SUCCESS { return false }

            var compilerPtr: spvc_compiler? = nil
            result = spvc_context_create_compiler(context,
                                                SPVC_BACKEND_NONE,
                                                ir,
                                                SPVC_CAPTURE_MODE_TAKE_OWNERSHIP,
                                                &compilerPtr)
            if result != SPVC_SUCCESS { return false }
            let compiler = compilerPtr!

            // execution model
            self.stage = stageFromSPVC(compiler: compiler)
            assert(self.stage != .unknown, "Unknown shader stage type")

            self.functionNames = []
            self.resources = []
            self.inputAttributes = []
            self.outputAttributes = []
            self.pushConstantLayouts = []
            self.descriptors = []
            self.threadgroupSize = (1, 1, 1)
            
            // get thread group size
            if spvc_compiler_get_execution_model(compiler) == SpvExecutionModelGLCompute {
                var localSizeX = spvc_compiler_get_execution_mode_argument_by_index(compiler, SpvExecutionModeLocalSize, 0)
                var localSizeY = spvc_compiler_get_execution_mode_argument_by_index(compiler, SpvExecutionModeLocalSize, 1)
                var localSizeZ = spvc_compiler_get_execution_mode_argument_by_index(compiler, SpvExecutionModeLocalSize, 2)            

                var x = spvc_specialization_constant()
                var y = spvc_specialization_constant()
                var z = spvc_specialization_constant()
                let constantID = spvc_compiler_get_work_group_size_specialization_constants(compiler, &x, &y, &z)
                if x.id != 0 {
                    let constant = spvc_compiler_get_constant_handle(compiler, x.id)
                    localSizeX = spvc_constant_get_scalar_u32(constant, 0, 0)
                }
                if y.id != 0 {
                    let constant = spvc_compiler_get_constant_handle(compiler, y.id)
                    localSizeY = spvc_constant_get_scalar_u32(constant, 0, 0)
                }
                if z.id != 0 {
                    let constant = spvc_compiler_get_constant_handle(compiler, z.id)
                    localSizeZ = spvc_constant_get_scalar_u32(constant, 0, 0)
                }

                Log.debug("ComputeShader.constantId: \(constantID)")
                Log.debug("ComputeShader.LocalSize.X: \(localSizeX) (specialized: \(x.id), specializationID: \(x.constant_id))")
                Log.debug("ComputeShader.LocalSize.Y: \(localSizeY) (specialized: \(y.id), specializationID: \(y.constant_id))")
                Log.debug("ComputeShader.LocalSize.Z: \(localSizeZ) (specialized: \(z.id), specializationID: \(z.constant_id))")

                self.threadgroupSize.x = max(localSizeX, 1)
                self.threadgroupSize.y = max(localSizeY, 1)
                self.threadgroupSize.z = max(localSizeZ, 1)
            }

            // get resources
            var resources: spvc_resources? = nil
            result = spvc_compiler_create_shader_resources(compiler, &resources)
            if result != SPVC_SUCCESS { return false }

            var spvcActiveSet: spvc_set? = nil
            result = spvc_compiler_get_active_interface_variables(compiler, &spvcActiveSet)
            var activeResources: spvc_resources? = nil
            result = spvc_compiler_create_shader_resources_for_active_variables(compiler, &activeResources, spvcActiveSet)
            if result != SPVC_SUCCESS { return false }

            let getActiveVariableSet = {
                (type: spvc_resource_type) -> Set<spvc_variable_id> in
                var list: UnsafePointer<spvc_reflected_resource>? = nil
                var count: Int = 0
                let result = spvc_resources_get_resource_list_for_type(activeResources, type, &list, &count)
                if result != SPVC_SUCCESS { throw SPVCError.spvcResult(result) }

                var set = Set<spvc_variable_id>()
                for n in 0..<count {
                    set.update(with: list![n].id)
                }
                return set
            }

            let enumerateResources = {
                (_ type: spvc_resource_type, _ body: (_: UnsafeBufferPointer<spvc_reflected_resource>) throws ->Void) -> spvc_result
                in
                var list: UnsafePointer<spvc_reflected_resource>? = nil
                var count: Int = 0

                let result: spvc_result =
                    spvc_resources_get_resource_list_for_type(resources, type, &list, &count)
                if result == SPVC_SUCCESS && count > 0 {
                    try body(UnsafeBufferPointer(start: list, count: count))
                }
                return result
            }

            // https://github.com/KhronosGroup/SPIRV-Cross/wiki/Reflection-API-user-guide
            // uniform_buffers
            result = try enumerateResources(SPVC_RESOURCE_TYPE_UNIFORM_BUFFER) {
                (ptr: UnsafeBufferPointer<spvc_reflected_resource>) in
                let activeSet = try getActiveVariableSet(SPVC_RESOURCE_TYPE_UNIFORM_BUFFER)
                for i in 0..<ptr.count {
                    self.resources.append(try resourceFromSPVC(compiler: compiler, resource: ptr[i], enabled: activeSet.contains(ptr[i].id), access: .readOnly))
                    self.descriptors.append(descriptorFromSPVC(compiler: compiler, resource: ptr[i], type: .uniformBuffer))
                }
            }
            if result != SPVC_SUCCESS { return false }

            // storage_buffers
            result = try enumerateResources(SPVC_RESOURCE_TYPE_STORAGE_BUFFER) {
                (ptr: UnsafeBufferPointer<spvc_reflected_resource>) in
                let activeSet = try getActiveVariableSet(SPVC_RESOURCE_TYPE_STORAGE_BUFFER)
                for i in 0..<ptr.count {
                    self.resources.append(try resourceFromSPVC(compiler: compiler, resource: ptr[i], enabled: activeSet.contains(ptr[i].id), access: .readWrite))
                    self.descriptors.append(descriptorFromSPVC(compiler: compiler, resource: ptr[i], type: .storageBuffer))
                }
            }
            if result != SPVC_SUCCESS { return false }

            // storage_images
            result = try enumerateResources(SPVC_RESOURCE_TYPE_STORAGE_IMAGE) {
                (ptr: UnsafeBufferPointer<spvc_reflected_resource>) in
                let activeSet = try getActiveVariableSet(SPVC_RESOURCE_TYPE_STORAGE_IMAGE)
                for i in 0..<ptr.count {
                    let basetype = spvc_compiler_get_type_handle(compiler, ptr[i].base_type_id)
                    var type: ShaderDescriptorType = .storageTexture
                    if spvc_type_get_image_dimension(basetype) == SpvDimBuffer {
                        type = .storageTexelBuffer
                    }
                    self.resources.append(try resourceFromSPVC(compiler: compiler, resource: ptr[i], enabled: activeSet.contains(ptr[i].id), access: .readWrite))
                    self.descriptors.append(descriptorFromSPVC(compiler: compiler, resource: ptr[i], type: type))
                }
            }
            if result != SPVC_SUCCESS { return false }

            // sampled_images (sampler2D)
            result = try enumerateResources(SPVC_RESOURCE_TYPE_SAMPLED_IMAGE) {
                (ptr: UnsafeBufferPointer<spvc_reflected_resource>) in
                let activeSet = try getActiveVariableSet(SPVC_RESOURCE_TYPE_SAMPLED_IMAGE)
                for i in 0..<ptr.count {
                    self.resources.append(try resourceFromSPVC(compiler: compiler, resource: ptr[i], enabled: activeSet.contains(ptr[i].id), access: .readOnly))
                    self.descriptors.append(descriptorFromSPVC(compiler: compiler, resource: ptr[i], type: .textureSampler))
                }
            }
            if result != SPVC_SUCCESS { return false }

            // separate_images
            result = try enumerateResources(SPVC_RESOURCE_TYPE_SEPARATE_IMAGE) {
                (ptr: UnsafeBufferPointer<spvc_reflected_resource>) in
                let activeSet = try getActiveVariableSet(SPVC_RESOURCE_TYPE_SEPARATE_IMAGE)
                for i in 0..<ptr.count {
                    let basetype = spvc_compiler_get_type_handle(compiler, ptr[i].base_type_id)
                    var type: ShaderDescriptorType = .texture
                    if spvc_type_get_image_dimension(basetype) == SpvDimBuffer {
                        type = .uniformTexelBuffer
                    }
                    self.resources.append(try resourceFromSPVC(compiler: compiler, resource: ptr[i], enabled: activeSet.contains(ptr[i].id), access: .readOnly))
                    self.descriptors.append(descriptorFromSPVC(compiler: compiler, resource: ptr[i], type: type))
                }
            }
            if result != SPVC_SUCCESS { return false }

            // separate_samplers
            result = try enumerateResources(SPVC_RESOURCE_TYPE_SEPARATE_SAMPLERS) {
                (ptr: UnsafeBufferPointer<spvc_reflected_resource>) in
                let activeSet = try getActiveVariableSet(SPVC_RESOURCE_TYPE_SEPARATE_SAMPLERS)
                for i in 0..<ptr.count {
                    self.resources.append(try resourceFromSPVC(compiler: compiler, resource: ptr[i], enabled: activeSet.contains(ptr[i].id), access: .readOnly))
                    self.descriptors.append(descriptorFromSPVC(compiler: compiler, resource: ptr[i], type: .sampler))
                }
            }
            if result != SPVC_SUCCESS { return false }

            // stage_inputs
            result = try enumerateResources(SPVC_RESOURCE_TYPE_STAGE_INPUT) {
                (ptr: UnsafeBufferPointer<spvc_reflected_resource>) in
                let activeSet = try getActiveVariableSet(SPVC_RESOURCE_TYPE_STAGE_INPUT)
                for i in 0..<ptr.count {
                    self.inputAttributes.append(try attributeFromSPVC(compiler: compiler, resource: ptr[i], enabled: activeSet.contains(ptr[i].id)))
                }
            }
            if result != SPVC_SUCCESS { return false }

            // stage_outputs
            result = try enumerateResources(SPVC_RESOURCE_TYPE_STAGE_OUTPUT) {
                (ptr: UnsafeBufferPointer<spvc_reflected_resource>) in
                let activeSet = try getActiveVariableSet(SPVC_RESOURCE_TYPE_STAGE_OUTPUT)
                for i in 0..<ptr.count {
                    self.outputAttributes.append(try attributeFromSPVC(compiler: compiler, resource: ptr[i], enabled: activeSet.contains(ptr[i].id)))
                }
            }
            if result != SPVC_SUCCESS { return false }

            // push constant range
            result = try enumerateResources(SPVC_RESOURCE_TYPE_PUSH_CONSTANT) {
                (ptr: UnsafeBufferPointer<spvc_reflected_resource>) in
                for i in 0..<ptr.count {
                    var ranges: UnsafePointer<spvc_buffer_range>? = nil
                    var numRanges: Int = 0
                    let result = spvc_compiler_get_active_buffer_ranges(compiler, ptr[i].id, &ranges, &numRanges)
                    if result == SPVC_SUCCESS { throw SPVCError.spvcResult(result) }
                    assert(numRanges > 0)
                    if let ranges = ranges, numRanges > 0 {
                        var rangeBegin = ranges[0].offset
                        var rangeEnd = ranges[0].offset + ranges[0].range
                        for i in 1..<numRanges {
                            rangeBegin = min(ranges[i].offset, rangeBegin)
                            rangeEnd = max(ranges[i].offset + ranges[i].range, rangeEnd)
                        }
                        assert(rangeEnd > rangeBegin)
                        assert(rangeBegin % 4 == 0)
                        assert(rangeEnd % 4 == 0)

                        let name = String(cString: spvc_compiler_get_name(compiler, ptr[i].id))
                        let basetype = spvc_compiler_get_type_handle(compiler, ptr[i].base_type_id)
                        let members = try resourceStructMembersFromSPVC(compiler: compiler, type: basetype!)
                        let layout = ShaderPushConstantLayout(name: name,
                                                            offset: UInt32(rangeBegin),
                                                            size: UInt32(rangeEnd - rangeBegin),
                                                            stages: ShaderStageFlags(stage: self.stage),
                                                            members: members)

                        self.pushConstantLayouts.append(layout)
                    }
                }
            }
            if result != SPVC_SUCCESS { return false }

            // module entry points
            var entryPoints: UnsafePointer<spvc_entry_point>? = nil
            var numEntryPoints: Int = 0
            result = spvc_compiler_get_entry_points(compiler, &entryPoints, &numEntryPoints)
            if result != SPVC_SUCCESS { return false }
            for i in 0..<numEntryPoints {
                self.functionNames.append(String(cString: entryPoints![i].name))
            }

            // specialization constants
            var spConstants: UnsafePointer<spvc_specialization_constant>? = nil
            var numSpConstants: Int = 0
            result = spvc_compiler_get_specialization_constants(compiler, &spConstants, &numSpConstants)
            if result != SPVC_SUCCESS { return false }
            // for i in 0..<numSpConstants {
            //     let constSpvID = spConstants![i].id
            //     let constID = spConstants![i].constant_id
            // }
        } catch SPVCError.spvcResult(let r) {
            Log.err("SPVC Exception caught: \(r)")
            result = r
            return false
        } catch SPVCError.runtimeError(let mesg){
            Log.err("RuntimeError Exception caught: \(mesg)")
            spverror.message = mesg
            return false            
        } catch {
            Log.err("Unexpected error: \(error).")
            return false
        }

        // sort bindings
        self.descriptors.sort { a, b in
            if a.set == b.set { return a.binding < b.binding }
            return a.set < b.set
        }
        self.resources.sort { a, b in
            if a.type == b.type {
                if a.set == b.set { return a.binding < b.binding }
                return a.set < b.set
            }
            return a.type < b.type
        }
        self.inputAttributes.sort { $0.location < $1.location }
        self.outputAttributes.sort { $0.location < $1.location }

        // copy spir-v data
        self.spirvData = Array(data)

        assert(result == SPVC_SUCCESS)
        return result == SPVC_SUCCESS
    }

    public func validate() -> Bool {
        return false
    }

    public var description: String {
        var str = "Shader(name: \"\(self.name)\"), stage: \(self.stage), \(self.spirvData.count * 4) bytes."
        str += "\nShader<\(self.stage).SPIR-V>.inputAttributes: \(self.inputAttributes.count)"
        for i in 0..<self.inputAttributes.count {
            let attr = self.inputAttributes[i]
            str += "\n [in] ShaderAttribute[\(i)]: \"\(attr.name)\" (type: \(attr.type), location: \(attr.location))"
        }
        str += "\nShader<\(self.stage).SPIR-V>.outputAttributes: \(self.outputAttributes.count)"
        for i in 0..<self.outputAttributes.count {
            let attr = self.outputAttributes[i]
            str += "\n [out] ShaderAttribute[\(i)]: \"\(attr.name)\" (type: \(attr.type), location: \(attr.location))"
        }
        str += "\nShader<\(self.stage).SPIR-V>.resources: \(self.resources.count)"
        for res in self.resources {
            str += "\n" + res.description
        }
        for i in 0..<self.pushConstantLayouts.count {
            let layout = self.pushConstantLayouts[i]
            str += "\npushConstant[\(i)] \"\(layout.name)\" (offset: \(layout.offset), size: \(layout.size), stages: \(layout.stages))"
            for mem in layout.members {
                str += "\n" + describeShaderResourceStructMember(mem, indent: 1)
            }
        }
        return str
    }
}
