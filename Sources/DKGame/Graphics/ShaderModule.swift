import Foundation

public struct ShaderSpecialization {
    var type : ShaderDataType
    var data : ContiguousBytes
    var index : UInt32
    var size : Int
}

public protocol ShaderModule {
    func makeFunction(name: String) -> ShaderFunction?
    func makeFunction(name: String, specializedValues: [ShaderSpecialization]) -> ShaderFunction?

    var functionNames: [String] { get }
    var device: GraphicsDevice { get }
}

