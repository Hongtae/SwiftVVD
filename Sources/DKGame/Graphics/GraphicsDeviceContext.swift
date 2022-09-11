//
//  File: GraphicsDeviceContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public class GraphicsDeviceContext {
    public let device: GraphicsDevice
    public var cachedDeviceResources: [String: AnyObject] = [:]

    public init(device: GraphicsDevice) {
        self.device = device
    }

    deinit {
        self.cachedDeviceResources.removeAll()        
        self.renderQueues.removeAll()
        self.computeQueues.removeAll()
        self.copyQueues.removeAll()
    }

    // cached command queue.
    public func renderQueue() -> CommandQueue? {
        if renderQueues.isEmpty {
            if let queue = device.makeCommandQueue(flags: .render) {
                if queue.flags.contains(.render) {
                    renderQueues.append(queue)
                }
                if queue.flags.contains(.compute) {
                    computeQueues.append(queue)
                }
                copyQueues.append(queue)

                if queue.flags.contains(.render) {
                    return queue
                }
            }
        }
        return renderQueues.first
    }

    public func computeQueue() -> CommandQueue? {
        if computeQueues.isEmpty {
            if let queue = device.makeCommandQueue(flags: .compute) {
                if queue.flags.contains(.render) {
                    renderQueues.append(queue)
                }
                if queue.flags.contains(.compute) {
                    computeQueues.append(queue)
                }
                copyQueues.append(queue)

                if queue.flags.contains(.compute) {
                    return queue
                }
            }                        
        }
        return computeQueues.first
    }

    public func copyQueue() -> CommandQueue? {
        if copyQueues.isEmpty {
            if let queue = device.makeCommandQueue(flags: .copy) {
                if queue.flags.contains(.render) {
                    renderQueues.append(queue)
                }
                if queue.flags.contains(.compute) {
                    computeQueues.append(queue)
                }
                copyQueues.append(queue)

                return queue
            }                        
        }
        return copyQueues.first
    }

    private var renderQueues: [CommandQueue] = []
    private var computeQueues: [CommandQueue] = []
    private var copyQueues: [CommandQueue] = []
}

public enum GraphicsAPI {
    case auto, vulkan, metal, d3d12
}

public func makeGraphicsDeviceContext(api: GraphicsAPI = .auto) -> GraphicsDeviceContext? {
    var enableValidation = false
#if DEBUG
        enableValidation = true
#endif

    if api == .vulkan || api == .auto {
#if ENABLE_VULKAN
        if let instance = VulkanInstance(enableValidation: enableValidation) {
            if let device = instance.makeDevice() {
                return GraphicsDeviceContext(device: device)
            }
        }
#endif
    }
    if api == .metal || api == .auto {
#if ENABLE_METAL
        if let device = MetalGraphicsDevice() {
            return GraphicsDeviceContext(device: device)
        }
#endif        
    }
    return nil
}
