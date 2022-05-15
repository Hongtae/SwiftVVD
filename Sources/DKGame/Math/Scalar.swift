import Foundation

public typealias Scalar = Float32

public func clamp<T>(_ value: T, min: T, max: T) -> T where T: Comparable {
    if value < min { return min }
    if value > max { return max }
    return value
}

public typealias Half2 = (Float16, Float16)
public typealias Float2 = (Float32, Float32)
public typealias Double2 = (Float64, Float64)

public typealias Half3 = (Float16, Float16, Float16)
public typealias Float3 = (Float32, Float32, Float32)
public typealias Double3 = (Float64, Float64, Float64)

public typealias Half4 = (Float16, Float16, Float16, Float16)
public typealias Float4 = (Float32, Float32, Float32, Float32)
public typealias Double4 = (Float64, Float64, Float64, Float64)

public typealias Half2x2 = (Half2, Half2)
public typealias Float2x2 = (Float2, Float2)
public typealias Double2x2 = (Double2, Double2)

public typealias Half3x3 = (Half3, Half3, Half3)
public typealias Float3x3 = (Float3, Float3, Float3)
public typealias Double3x3 = (Double3, Double3, Double3)

public typealias Half4x4 = (Half4, Half4, Half4, Half4)
public typealias Float4x4 = (Float4, Float4, Float4, Float4)
public typealias Double4x4 = (Double4, Double4, Double4, Double4)
