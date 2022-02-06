public struct ShaderSpecialization {
    var type : ShaderDataType
    var data : Any?
    var index : UInt32
    var size : UInt
}

public protocol ShaderModule {
    func makeFunction(name: String)
    func makeSpecializedFunction(name: String, specializedValues: [ShaderSpecialization])

    var functionNames: [String] { get }
}

