//
//  File: ShaderFunction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct ShaderFunctionConstant {
    public var name: String
    public var type: ShaderDataType
    public var index: UInt32
    public var required: Bool

    public init(name: String,
                type: ShaderDataType,
                index: UInt32,
                required: Bool) {
        self.name = name
        self.type = type
        self.index = index
        self.required = required
    }
}

public protocol ShaderFunction {
    var stageInputAttributes: [ShaderAttribute] { get }
    var functionConstants: [String: ShaderFunctionConstant] { get }
    var functionName: String { get }
    var stage: ShaderStage { get }

    var device: GraphicsDevice { get }
}
