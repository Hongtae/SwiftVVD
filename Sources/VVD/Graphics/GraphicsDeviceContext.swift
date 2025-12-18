//
//  File: GraphicsDeviceContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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

    let deviceWaitTimeout = 2.0

    public func makeCPUAccessible(buffer: GPUBuffer) -> GPUBuffer? {
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

                encoder.copy(from: buffer, sourceOffset: 0,
                             to: stgBuffer, destinationOffset: 0,
                             size: buffer.length)
                encoder.endEncoding()
                cbuffer.addCompletedHandler { _ in
                    cond.lock()
                    defer { cond.unlock() }
                    cond.broadcast()
                }

                cond.lock()
                defer { cond.unlock() }

                cbuffer.commit()

                if cond.wait(until: Date(timeIntervalSinceNow: deviceWaitTimeout)) == false {
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

    public func makeCPUAccessible(texture: Texture) -> GPUBuffer? {
        guard let queue = copyQueue() else {
            fatalError("Unable to make command queue")
        }

        let pixelFormat = texture.pixelFormat
        let bpp = pixelFormat.bytesPerPixel
        let width = texture.width
        let height = texture.height
        let bufferLength = width * height * bpp

        if let stgBuffer = device.makeBuffer(length: bufferLength,
                                             storageMode: .shared,
                                             cpuCacheMode: .defaultCache) {
            if let cbuffer = queue.makeCommandBuffer(),
               let encoder = cbuffer.makeCopyCommandEncoder() {

                let cond = NSCondition()

                encoder.copy(from: texture,
                             sourceOffset: TextureOrigin(layer: 0, level: 0, x: 0, y: 0, z: 0),
                             to: stgBuffer, 
                             destinationOffset: BufferImageOrigin(offset: 0, imageWidth: width, imageHeight: height),
                             size: TextureSize(width: width, height: height, depth: 1))
                encoder.endEncoding()
                cbuffer.addCompletedHandler { _ in
                    cond.lock()
                    defer { cond.unlock() }
                    cond.broadcast()
                }

                cond.lock()
                defer { cond.unlock() }

                cbuffer.commit()

                if cond.wait(until: Date(timeIntervalSinceNow: deviceWaitTimeout)) == false {
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

    public static func makeDefault() -> GraphicsDeviceContext? {
        return makeGraphicsDeviceContext()
    }
}

public enum GraphicsAPI {
    case auto, vulkan, metal
}

nonisolated(unsafe)
fileprivate var deviceNamePrefix: String? = {
    if let arg = CommandLine.arguments.first(where: { $0.lowercased().hasPrefix("--gpu-device-prefix=")}) {
        let parts = arg.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            return String(parts[1]).lowercased()
        }
    }
    return nil
}()

public func makeGraphicsDeviceContext(api: GraphicsAPI = .auto) -> GraphicsDeviceContext? {
    if api == .vulkan || api == .auto {
#if ENABLE_VULKAN
        var enableValidation = false
        let validationFeatures: VulkanValidationFeatures = [.coreValidation,
                                                            .synchronizationValidation]
#if DEBUG
        if CommandLine.arguments.contains(where: { $0.lowercased() == "--disable-validation"}) == false {
            enableValidation = true
        }
#endif
        if let instance = VulkanInstance(enableValidation: enableValidation,
                                         validationFeatures: validationFeatures) {
            var device: VulkanGraphicsDevice? = nil
            if let deviceNamePrefix {
                for physicalDevice in instance.physicalDevices {
                    if physicalDevice.name.lowercased().hasPrefix(deviceNamePrefix) {
                        device = instance.makeDevice(identifier: physicalDevice.registryID)
                        break
                    }
                }
            }
            if device == nil {
                device = instance.makeDevice()
            }
            if let device {
                return GraphicsDeviceContext(device: device)
            }
        }
#endif
    }
    if api == .metal || api == .auto {
#if ENABLE_METAL
        var device: MetalGraphicsDevice? = nil
        if let deviceNamePrefix {
            device = MetalGraphicsDevice { name in
                name.lowercased().hasPrefix(deviceNamePrefix)
            }
        }
        if device == nil {
            device = MetalGraphicsDevice()
        }
        if let device {
            return GraphicsDeviceContext(device: device)
        }
#endif
    }
    return nil
}
