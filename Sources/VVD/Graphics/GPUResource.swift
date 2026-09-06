//
//  File: GPUResource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public enum CPUCacheMode: UInt, Sendable {
    case defaultCache   // read write
    case writeCombined  // write only
}

public protocol GPUEvent: Sendable {
    var device: GraphicsDevice { get }
}

public protocol GPUSemaphore: Sendable {
    var device: GraphicsDevice { get }
}
