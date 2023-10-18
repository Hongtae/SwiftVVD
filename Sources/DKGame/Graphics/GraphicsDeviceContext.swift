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
    public var cachedQueues: [CommandQueue] = []

    public init(device: GraphicsDevice) {
        self.device = device
    }

    deinit {
        self.cachedDeviceResources.removeAll()     
        self.cachedQueues.removeAll()
    }

    public func commandQueue(flags: CommandQueueFlags = []) -> CommandQueue? {
        if let queue = self.cachedQueues.first(where: {
            $0.flags.intersection(flags) == flags
        }) {
            return queue;
        }

        if let queue = device.makeCommandQueue(flags: flags) {
            cachedQueues.append(queue)
            return queue
        }
        return nil
    }

    public func renderQueue() -> CommandQueue? {
        commandQueue(flags: .render) 
    }

    public func computeQueue() -> CommandQueue? {
        commandQueue(flags: .compute)
    }

    public func copyQueue() -> CommandQueue? {
        commandQueue(flags: .copy)
    }

    public func makeCPUAccessible(buffer: Buffer) -> Buffer? {
        if buffer.contents() != nil {
            return buffer
        }
        guard let queue = copyQueue() else {
            fatalError("Unable to make command queue")
        }

        if let stgBuffer = device.makeBuffer(length: buffer.length,
                                             storageMode: .shared,
                                             cpuCacheMode: .defaultCache) {
            if let cbuffer = queue.makeCommandBuffer(),
               let encoder = cbuffer.makeCopyCommandEncoder() {

                let cond = NSCondition()
                let timeout = 2.0

                encoder.copy(from: buffer, sourceOffset: 0,
                             to: stgBuffer, destinationOffset: 0,
                             size: buffer.length)
                encoder.endEncoding()
                cbuffer.addCompletedHandler { _ in
                    cond.lock()
                    defer { cond.unlock() }
                    cond.broadcast()
                }
                cbuffer.commit()

                cond.lock()
                defer { cond.unlock() }

                if cond.wait(until: Date(timeIntervalSinceNow: timeout)) == false {
                    // timeout
                    Log.error("The operation timed out. Device did not respond to the command.")
                    return nil                    
                }
                if stgBuffer.contents() != nil {
                    return stgBuffer
                }
            }
        }
        return nil
    }
}

public enum GraphicsAPI {
    case auto, vulkan, metal, d3d12
}

public func makeGraphicsDeviceContext(api: GraphicsAPI = .auto) -> GraphicsDeviceContext? {
    if api == .vulkan || api == .auto {
#if ENABLE_VULKAN
        var enableValidation = false
#if DEBUG
        if CommandLine.arguments.contains(where: { $0.lowercased() == "--disable-validation"}) == false {
            enableValidation = true
        }
#endif
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
