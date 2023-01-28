//
//  File: Shading.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

class GraphicsPipelineStates {
    enum Shading {
        case color
        case radient
        case image
    }
    enum DepthStencil {
        case generateWindingNumber
        case nonZero
        case evenOdd
        case ignore
    }

    let vertexFunction: ShaderFunction
    let fragmentFunctions: [ShaderFunction]

    let device: GraphicsDevice
    let defaultBindingSet: ShaderBindingSet
    let defaultSampler: SamplerState

    var renderStates: [Shading: RenderPipelineState] = [:]
    var depthStencilStates: [DepthStencil: DepthStencilState] = [:]

    func renderState(_ shading: Shading) -> RenderPipelineState? {
        nil
    }

    func depthStencilState(_ stencil: DepthStencil) -> DepthStencilState? {
        nil
    }

    private init(device: GraphicsDevice,
                 vertexFunction: ShaderFunction,
                 fragmentFunctions: [ShaderFunction],
                 defaultBindingSet: ShaderBindingSet,
                 defaultSampler: SamplerState) {
        self.device = device
        self.vertexFunction = vertexFunction
        self.fragmentFunctions = fragmentFunctions
        self.defaultBindingSet = defaultBindingSet
        self.defaultSampler = defaultSampler
    }

    private static let lock = NSLock()
    private static weak var sharedInstance: GraphicsPipelineStates? = nil

    static func sharedInstance(device: GraphicsDevice) -> GraphicsPipelineStates? {
        if let instance = sharedInstance {
            return instance
        }
        lock.lock()
        defer { lock.unlock() }

        var instance = sharedInstance
        if instance == nil {



        }
        return instance
    }

    static func cacheContext(_ deviceContext: GraphicsDeviceContext) -> Bool {
        if let state = GraphicsPipelineStates.sharedInstance(device: deviceContext.device) {
            deviceContext.cachedDeviceResources["DKGUI.GraphicsPipelineStates"] = state
            return true
        }
        return false
    }
}
