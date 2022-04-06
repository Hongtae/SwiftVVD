public struct PipelineReflection: CustomStringConvertible {
    public var inputAttributes: [ShaderAttribute]
    public var pushConstantLayouts: [ShaderPushConstantLayout]
    public var resources: [ShaderResource]

    public var description: String {
        var str = ""
        str += "PipelineReflection.inputAttributes: \(self.inputAttributes.count)"
        for i in 0..<self.inputAttributes.count {
            let attr = self.inputAttributes[i]
            str += "\n [in] ShaderAttribute[\(i)]: \(attr.name) (type: \(attr.type), location: \(attr.location))"
        }
        str += "\nPipelineReflection.resources: \(self.resources.count)"
        for res in self.resources {
            str += "\n" + res.description
        }
        for i in 0..<self.pushConstantLayouts.count {
            let layout = self.pushConstantLayouts[i]
            str += "\npushConstant[\(i)] \(layout.name) (offset: \(layout.offset), size: \(layout.size), stages: \(layout.stages))"
            for mem in layout.members {
                str += "\n" + describeShaderResourceStructMember(mem, indent: 1)
            }
        }
        return str
    }
}