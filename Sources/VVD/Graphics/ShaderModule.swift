//
//  File: ShaderModule.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ShaderFunctionConstantValue {
    public var type: ShaderDataType
    public var data: ContiguousBytes
    public var index: Int
    public var size: Int

    public init(type: ShaderDataType,
                data: ContiguousBytes,
                index: Int,
                size: Int) {
        self.type = type
        self.data = data
        self.index = index
        self.size = size
    }
}

public protocol ShaderModule {
    func makeFunction(name: String) -> ShaderFunction?
    func makeFunction(name: String, constantValues: [ShaderFunctionConstantValue]) -> ShaderFunction?

    var functionNames: [String] { get }
    var device: GraphicsDevice { get }
}

