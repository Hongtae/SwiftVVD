import Foundation
import VVD

func loadShader(from path: String, device: GraphicsDevice) -> MaterialShaderMap.Function? {
    Log.debug("loadShader(from: \(path))")
    if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
        if let shader = Shader(data: data) {
            if shader.validate() {
                printShaderReflection(shader)
                if let module = device.makeShaderModule(from: shader) {
                    let names = module.functionNames
                    if let name = names.first {
                        if let fn = module.makeFunction(name: name) {
                            return MaterialShaderMap.Function(function: fn,
                                                              descriptors: shader.descriptors)
                        } else {
                            Log.error("Unable to make shader function with name: \(name) (from path: \(path))")
                        }
                    } else {
                        Log.error("No entry point functions found in shader module at path: \(path)")
                    }
                }
            } else {
                Log.error("Shader validation failed for path: \(path)")
            }
        } else {
            Log.error("Failed to load shader from path: \(path)")
        }
    } else {
        Log.error("Cannot load data from path: \(path)")
    }
    return nil
}

func printShaderResourceStructMember(_ member: ShaderResourceStructMember,
                                     prefix: String,
                                     indent: Int,
                                     logLevel: Log.Level = .info) {
    var indentStr = ""
    for _ in 0..<indent {
        indentStr += "    "
    }

    if member.stride > 0 {
        let header = "\(prefix) \(indentStr)+ \(member.name)[\(member.count)]"
        let detail = "\(member.dataType), offset: \(member.offset), size: \(member.size), stride: \(member.stride)" 
        Log.log(level: logLevel, "\(header) (\(detail))")
    } else {
        let header = "\(prefix) \(indentStr)+ \(member.name)"
        let detail = "\(member.dataType), offset: \(member.offset), size: \(member.size), stride: \(member.stride)" 
        Log.log(level: logLevel, "\(header) (\(detail))")
    }
    member.members.forEach {
        printShaderResourceStructMember($0, prefix: prefix, indent: indent + 1, logLevel: logLevel)
    }
}

func printShaderResource(_ res: ShaderResource, logLevel: Log.Level = .info) {
    if res.count > 1 {
        let header = "\(res.name)[\(res.count)]"
        let detail = "set: \(res.set), binding: \(res.binding), stages: \(res.stages)"
        Log.log(level: logLevel, "ShaderResource: \(header) (\(detail))")
    } else {
        let header = "\(res.name)"
        let detail = "set: \(res.set), binding: \(res.binding), stages: \(res.stages)"
        Log.log(level: logLevel, "ShaderResource: \(header) (\(detail))")
    }

    if res.type == .buffer {
        let typeInfo = res.bufferTypeInfo!
        Log.log(level: logLevel, "type: \(res.type), access: \(res.access), enabled: \(res.enabled), size: \(typeInfo.size)")

        if typeInfo.dataType == .struct {
            Log.log(level: logLevel, "struct: \"\(res.name)\"")
            res.members.forEach {
                printShaderResourceStructMember($0, prefix: "", indent: 1, logLevel: logLevel)
            }
        }
    } else {
        Log.log(level: logLevel, "type: \(res.type), access: \(res.access), enabled: \(res.enabled)")
    }
}

private let lineSeparator1 = "========================================================="
private let lineSeparator2 = "---------------------------------------------------------"

func printShaderReflection(_ shader: Shader, logLevel: Log.Level = .info) {
    Log.log(level: logLevel, lineSeparator1)
    Log.log(level: logLevel, "Shader<\(shader.stage).SPIR-V>.inputAttributes: \(shader.inputAttributes.count)")
    shader.inputAttributes.indices.forEach { i in
        let attr = shader.inputAttributes[i]
        Log.log(level: logLevel, "  [in] ShaderAttribute[\(i)]: \"\(attr.name)\" (type: \(attr.type), location: \(attr.location))")
    }
    Log.log(level: logLevel, lineSeparator2)
    Log.log(level: logLevel, "Shader<\(shader.stage).SPIR-V>.outputAttributes: \(shader.outputAttributes.count)")
    shader.outputAttributes.indices.forEach { i in
        let attr = shader.outputAttributes[i]
        Log.log(level: logLevel, "  [out] ShaderAttribute[\(i)]: \"\(attr.name)\" (type: \(attr.type), location: \(attr.location))")
    }
    Log.log(level: logLevel, lineSeparator2)
    Log.log(level: logLevel, "Shader<\(shader.stage).SPIR-V>.resources: \(shader.resources.count)")
    shader.resources.forEach {
        printShaderResource($0, logLevel: logLevel)
    }
    shader.pushConstantLayouts.indices.forEach { i in
        let layout = shader.pushConstantLayouts[i]
        let detail = "offset: \(layout.offset), size: \(layout.size), stages: \(layout.stages)"
        Log.log(level: logLevel, "  PushConstantLayout[\(i)]: \"\(layout.name)\" (\(detail))")
        layout.members.forEach {
            printShaderResourceStructMember($0, prefix: "", indent: 1, logLevel: logLevel)
        }
    }
}

func printPipelineReflection(_ reflection: PipelineReflection, logLevel: Log.Level = .info) {
    Log.log(level: logLevel, lineSeparator1)
    Log.log(level: logLevel, "PipelineReflection.inputAttributes: \(reflection.inputAttributes.count)")
    reflection.inputAttributes.indices.forEach { index in
        let attr = reflection.inputAttributes[index]
        let detail = "type: \(attr.type), location: \(attr.location)"
        Log.log(level: logLevel, "  [in] ShaderAttribute:[\(index)]: \"\(attr.name)\" (\(detail))")
    }
    Log.log(level: logLevel, lineSeparator2)
    Log.log(level: logLevel, "PipelineReflection.resources: \(reflection.resources.count)")
    reflection.resources.forEach {
        printShaderResource($0, logLevel: logLevel)
    }
    reflection.pushConstantLayouts.indices.forEach { index in
        let layout = reflection.pushConstantLayouts[index]
        let detail = "offset: \(layout.offset), size: \(layout.size), stages: \(layout.stages)"
        Log.log(level: logLevel, "PipelineReflection.pushConstantLayout: \(index) \"\(layout.name)\" (\(detail))")
        layout.members.forEach {
            printShaderResourceStructMember($0, prefix: "", indent: 1, logLevel: logLevel)
        }
    }
    Log.log(level: logLevel, lineSeparator1)
}
