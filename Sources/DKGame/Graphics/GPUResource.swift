//
//  File: GPUResource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public enum CPUCacheMode: UInt {
    case defaultCache   // read write
    case writeCombined  // write only
}

public protocol GPUEvent {
    var device: GraphicsDevice { get }
}

public protocol GPUSemaphore {
    var device: GraphicsDevice { get }
}
