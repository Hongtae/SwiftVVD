public enum ShaderDataType {
    case unknown
    case none

    case `struct`
    case texture
    case sampler

    case bool
    case boolV2
    case boolV3
    case boolV4

    case int8
    case int8V2
    case int8V3
    case int8V4

    case uint8
    case uint8V2
    case uint8V3
    case uint8V4

    case int16
    case int16V2
    case int16V3
    case int16V4

    case uint16
    case uint16V2
    case uint16V3
    case uint16V4

    case int32
    case int32V2
    case int32V3
    case int32V4

    case uint32
    case uint32V2
    case uint32V3
    case uint32V4
    
    case int64
    case int64V2
    case int64V3
    case int64V4

    case uint64
    case uint64V2
    case uint64V3
    case uint64V4

    case float16
    case float16V2
    case float16V3
    case float16V4
    case float16M2x2
    case float16M2x3
    case float16M2x4
    case float16M3x2
    case float16M3x3
    case float16M3x4
    case float16M4x2
    case float16M4x3
    case float16M4x4

    case float32
    case float32V2
    case float32V3
    case float32V4
    case float32M2x2
    case float32M2x3
    case float32M2x4
    case float32M3x2
    case float32M3x3
    case float32M3x4
    case float32M4x2
    case float32M4x3
    case float32M4x4

    case float64
    case float64V2
    case float64V3
    case float64V4
    case float64M2x2
    case float64M2x3
    case float64M2x4
    case float64M3x2
    case float64M3x3
    case float64M3x4
    case float64M4x2
    case float64M4x3
    case float64M4x4
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

public struct ShaderStageFlags: OptionSet {
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

public struct ShaderResourceBuffer {
    var dataType : ShaderDataType
    var alignment : UInt32
    var size : UInt32
}

public struct ShaderResourceTexture {
    var dataType : ShaderDataType
    var textureType : TextureType
}

public struct ShaderResourceThreadgroup {
    var alignment : UInt32
    var size : UInt32
}

public struct ShaderResourceStructMember {
    var dataType : ShaderDataType
    var name : String
    var offset : UInt32
    var size : UInt32   // declared size
    var count : UInt32  // array length
    var stride : UInt32 // stride between array elements

    var members : [ShaderResourceStructMember]
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
    var set : UInt32
    var binding : UInt32
    var name : String
    var type: ShaderResourceType
    var stages : ShaderStageFlags

    var count : UInt32  // array length
    var stride : UInt32 // stride between array elements

    var enabled : Bool
    var access : ShaderResourceAccess

    // typeinfo
    var bufferTypeInfo : ShaderResourceBuffer?
    var textureTypeInfo : ShaderResourceTexture?
    var threadgroupTypeInfo : ShaderResourceThreadgroup?

    // struct members (struct only)
    var members : [ShaderResourceStructMember]
}

public struct ShaderPushConstantLayout {
    var name : String
    var offset : UInt32
    var size : UInt32
    var stages : ShaderStageFlags
    var members : [ShaderResourceStructMember]
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
