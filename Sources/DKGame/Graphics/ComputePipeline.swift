//
//  File: ComputePipeline.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct ComputePipelineDescriptor {
    public var computeFunction: ShaderFunction?
    public var deferCompile: Bool
    public var disableOptimization: Bool

    public init(computeFunction: ShaderFunction? = nil,
                deferCompile: Bool = false,
                disableOptimization: Bool = false) {
        self.computeFunction = computeFunction
        self.deferCompile = deferCompile
        self.disableOptimization = disableOptimization
    }
}

public protocol ComputePipelineState {
    var device: GraphicsDevice { get }
}
