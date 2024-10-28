//
//  File: ShaderResource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

public enum ShaderDataType {
    case unknown
    case none

    case `struct`
    case texture
    case sampler

    case bool
    case bool2
    case bool3
    case bool4

    case char
    case char2
    case char3
    case char4

    case uchar
    case uchar2
    case uchar3
    case uchar4

    case short
    case short2
    case short3
    case short4

    case ushort
    case ushort2
    case ushort3
    case ushort4

    case int
    case int2
    case int3
    case int4

    case uint
    case uint2
    case uint3
    case uint4
    
    case long
    case long2
    case long3
    case long4

    case ulong
    case ulong2
    case ulong3
    case ulong4

    case half
    case half2
    case half3
    case half4
    case half2x2
    case half2x3
    case half2x4
    case half3x2
    case half3x3
    case half3x4
    case half4x2
    case half4x3
    case half4x4

    case float
    case float2
    case float3
    case float4
    case float2x2
    case float2x3
    case float2x4
    case float3x2
    case float3x3
    case float3x4
    case float4x2
    case float4x3
    case float4x4

    case double
    case double2
    case double3
    case double4
    case double2x2
    case double2x3
    case double2x4
    case double3x2
    case double3x3
    case double3x4
    case double4x2
    case double4x3
    case double4x4
}

public extension ShaderDataType {
    func components() -> (type: Any.Type, rows: Int, columns: Int)? {
        switch self {
        case .bool:         return (Bool.self, 1, 1)
        case .bool2:        return (Bool.self, 2, 1)
        case .bool3:        return (Bool.self, 3, 1)
        case .bool4:        return (Bool.self, 4, 1)

        case .char:         return (Int8.self, 1, 1)
        case .char2:        return (Int8.self, 2, 1)
        case .char3:        return (Int8.self, 3, 1)
        case .char4:        return (Int8.self, 4, 1)

        case .uchar:        return (UInt8.self, 1, 1)
        case .uchar2:       return (UInt8.self, 2, 1)
        case .uchar3:       return (UInt8.self, 3, 1)
        case .uchar4:       return (UInt8.self, 4, 1)

        case .short:        return (Int16.self, 1, 1)
        case .short2:       return (Int16.self, 2, 1)
        case .short3:       return (Int16.self, 3, 1)
        case .short4:       return (Int16.self, 4, 1)

        case .ushort:       return (UInt16.self, 1, 1)
        case .ushort2:      return (UInt16.self, 2, 1)
        case .ushort3:      return (UInt16.self, 3, 1)
        case .ushort4:      return (UInt16.self, 4, 1)

        case .int:          return (Int32.self, 1, 1)
        case .int2:         return (Int32.self, 2, 1)
        case .int3:         return (Int32.self, 3, 1)
        case .int4:         return (Int32.self, 4, 1)

        case .uint:         return (UInt32.self, 1, 1)
        case .uint2:        return (UInt32.self, 2, 1)
        case .uint3:        return (UInt32.self, 3, 1)
        case .uint4:        return (UInt32.self, 4, 1)

        case .long:         return (Int64.self, 1, 1)
        case .long2:        return (Int64.self, 2, 1)
        case .long3:        return (Int64.self, 3, 1)
        case .long4:        return (Int64.self, 4, 1)

        case .ulong:        return (UInt64.self, 1, 1)
        case .ulong2:       return (UInt64.self, 2, 1)
        case .ulong3:       return (UInt64.self, 3, 1)
        case .ulong4:       return (UInt64.self, 4, 1)

        case .half:         return (Float16.self, 1, 1)
        case .half2:        return (Float16.self, 2, 1)
        case .half3:        return (Float16.self, 3, 1)
        case .half4:        return (Float16.self, 4, 1)
        case .half2x2:      return (Float16.self, 2, 2)
        case .half2x3:      return (Float16.self, 2, 3)
        case .half2x4:      return (Float16.self, 2, 4)
        case .half3x2:      return (Float16.self, 3, 2)
        case .half3x3:      return (Float16.self, 3, 3)
        case .half3x4:      return (Float16.self, 3, 4)
        case .half4x2:      return (Float16.self, 4, 2)
        case .half4x3:      return (Float16.self, 4, 3)
        case .half4x4:      return (Float16.self, 4, 4)

        case .float:        return (Float32.self, 1, 1)
        case .float2:       return (Float32.self, 2, 1)
        case .float3:       return (Float32.self, 3, 1)
        case .float4:       return (Float32.self, 4, 1)
        case .float2x2:     return (Float32.self, 2, 2)
        case .float2x3:     return (Float32.self, 2, 3)
        case .float2x4:     return (Float32.self, 2, 4)
        case .float3x2:     return (Float32.self, 3, 2)
        case .float3x3:     return (Float32.self, 3, 3)
        case .float3x4:     return (Float32.self, 3, 4)
        case .float4x2:     return (Float32.self, 4, 2)
        case .float4x3:     return (Float32.self, 4, 3)
        case .float4x4:     return (Float32.self, 4, 4)

        case .double:       return (Float64.self, 1, 1)
        case .double2:      return (Float64.self, 2, 1)
        case .double3:      return (Float64.self, 3, 1)
        case .double4:      return (Float64.self, 4, 1)
        case .double2x2:    return (Float64.self, 2, 2)
        case .double2x3:    return (Float64.self, 2, 3)
        case .double2x4:    return (Float64.self, 2, 4)
        case .double3x2:    return (Float64.self, 3, 2)
        case .double3x3:    return (Float64.self, 3, 3)
        case .double3x4:    return (Float64.self, 3, 4)
        case .double4x2:    return (Float64.self, 4, 2)
        case .double4x3:    return (Float64.self, 4, 3)
        case .double4x4:    return (Float64.self, 4, 4)
        default:
            return nil
        }
    }

    func size() -> Int {
        if let comp = self.components() {
            func stride<T>(of type: T.Type) -> Int {
                MemoryLayout<T>.stride
            }
            return stride(of: comp.type) * comp.rows * comp.columns
        }
        return 0
    }
}

public enum ShaderStage {
    case unknown
    case vertex
    case tessellationControl
    case tessellationEvaluation
    case geometry
    case fragment
    case compute
}

public struct ShaderStageFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public init(stage: ShaderStage) {
        switch stage {
        case .unknown:                  self.rawValue = 0
        case .vertex:                   self.rawValue = 1
        case .tessellationControl:      self.rawValue = 1 << 1
        case .tessellationEvaluation:   self.rawValue = 1 << 2
        case .geometry:                 self.rawValue = 1 << 3
        case .fragment:                 self.rawValue = 1 << 4
        case .compute:                  self.rawValue = 1 << 5
        }
    }

    public static let vertex                    = ShaderStageFlags(stage: .vertex)
    public static let tessellationControl       = ShaderStageFlags(stage: .tessellationControl)
    public static let tessellationEvaluation    = ShaderStageFlags(stage: .tessellationEvaluation)
    public static let geometry                  = ShaderStageFlags(stage: .geometry)
    public static let fragment                  = ShaderStageFlags(stage: .fragment)
    public static let compute                   = ShaderStageFlags(stage: .compute)

    public static let unknown: ShaderStageFlags = []

    public var isSingleOption: Bool {
        if self.rawValue > 0 {
            return self.rawValue & (self.rawValue - 1) == 0
        }
        return false
    }
}

extension ShaderStageFlags: CustomStringConvertible {
    public var description: String {
        var result: [String] = []
        
        if contains(.vertex) { result.append(".vertex") }
        if contains(.tessellationControl) { result.append(".tessellationControl")}
        if contains(.tessellationEvaluation) { result.append(".tessellationEvaluation") }
        if contains(.geometry) { result.append(".geometry") }
        if contains(.fragment) { result.append(".fragment") }
        if contains(.compute) { result.append(".compute") }
        
        return "[\(result.joined(separator: ", "))]"
    }
}

public struct ShaderResourceBuffer {
    public var dataType: ShaderDataType
    public var alignment: Int
    public var size: Int
}

public struct ShaderResourceTexture {
    public var dataType: ShaderDataType
    public var textureType: TextureType
}

public struct ShaderResourceThreadgroup {
    public var alignment: Int
    public var size: Int
}

public struct ShaderResourceStructMember {
    public var dataType: ShaderDataType
    public var name: String
    public var offset: Int
    public var size: Int   // declared size
    public var count: Int  // array length
    public var stride: Int // stride between array elements

    public var members: [ShaderResourceStructMember]
}

public enum ShaderResourceType: Comparable {
    case buffer
    case texture
    case sampler
    case textureSampler // texture and sampler (combined)
}

public enum ShaderResourceAccess {
    case readOnly
    case writeOnly
    case readWrite
}

public struct ShaderResource {
    public var set: Int
    public var binding: Int
    public var name: String
    public var type: ShaderResourceType
    public var stages: ShaderStageFlags

    public var count: Int  // array length
    public var stride: Int // stride between array elements

    public var enabled: Bool
    public var access: ShaderResourceAccess

    // typeinfo
    public var bufferTypeInfo: ShaderResourceBuffer?
    public var textureTypeInfo: ShaderResourceTexture?
    public var threadgroupTypeInfo: ShaderResourceThreadgroup?

    // struct members (struct only)
    public var members: [ShaderResourceStructMember]
}

public struct ShaderPushConstantLayout {
    public var name: String
    public var offset: Int
    public var size: Int
    public var stages: ShaderStageFlags
    public var members: [ShaderResourceStructMember]
}

func describeShaderResourceStructMember(_ member: ShaderResourceStructMember, indent: Int = 0) -> String {
    var indentStr = ""
    for _ in 0..<indent {
        indentStr += "    "
    }
    var str = ""
    if member.count > 1 {
        str = "\(indentStr)\"\(member.name)[\(member.count)]\" (type: \(member.dataType), offset: \(member.offset), size: \(member.size), stride: \(member.stride))"
    } else {
        str = "\(indentStr)\"\(member.name)\" (type: \(member.dataType), offset: \(member.offset), size: \(member.size))"
    }
    for mem in member.members {
        str += "\n" + describeShaderResourceStructMember(mem, indent: indent+1)
    }
    return str    
}

extension ShaderResourceStructMember: CustomStringConvertible {
    public var description: String { describeShaderResourceStructMember(self, indent: 0) }
}

extension ShaderResource: CustomStringConvertible {
    public var description: String {
        var str = "ShaderResource: \"\(self.name)\""
        if self.count > 1 { str += "[\(self.count)]" }
        str += " (set: \(self.set), binding: \(self.binding), stages: \(self.stages))\n"
        if self.type == .buffer {
            str += " type: \(self.type), access: \(self.access), enabled: \(self.enabled), size: \(self.bufferTypeInfo!.size)"

            if self.bufferTypeInfo!.dataType == .struct {
                for member in self.members {
                    str += "\n" + describeShaderResourceStructMember(member, indent: 1)
                }                
            }
        } else {
            str += " type: \(self.type), access: \(self.access), enabled: \(self.enabled)"
        }
        return str
    }
}
