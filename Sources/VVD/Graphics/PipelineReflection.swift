//
//  File: PipelineReflection.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct PipelineReflection: CustomStringConvertible {
    public var inputAttributes: [ShaderAttribute] = []
    public var pushConstantLayouts: [ShaderPushConstantLayout] = []
    public var resources: [ShaderResource] = []

    public var description: String {
        var str = ""
        str += "PipelineReflection.inputAttributes: \(self.inputAttributes.count)"
        for (i, attr) in self.inputAttributes.enumerated() {
            str += "\n [in] ShaderAttribute[\(i)]: \(attr.name) (type: \(attr.type), location: \(attr.location))"
        }
        str += "\nPipelineReflection.resources: \(self.resources.count)"
        for res in self.resources {
            str += "\n" + res.description
        }
        for (i, layout) in self.pushConstantLayouts.enumerated() {
            str += "\npushConstant[\(i)] \(layout.name) (offset: \(layout.offset), size: \(layout.size), stages: \(layout.stages))"
            for mem in layout.members {
                str += "\n" + describeShaderResourceStructMember(mem, indent: 1)
            }
        }
        return str
    }

    public init(inputAttributes: [ShaderAttribute] = [],
                pushConstantLayouts: [ShaderPushConstantLayout] = [],
                resources: [ShaderResource] = []) {
        self.inputAttributes = inputAttributes
        self.pushConstantLayouts = pushConstantLayouts
        self.resources = resources
    }
}