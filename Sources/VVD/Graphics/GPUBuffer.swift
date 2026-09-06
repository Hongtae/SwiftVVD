//
//  File: GPUBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public enum StorageMode: UInt, Sendable {
    case shared     // accessible to both the CPU and the GPU
    case `private`  // only accessible to the GPU
}

public protocol GPUBuffer: AnyObject, Sendable {
    func contents() -> UnsafeMutableRawPointer?
    func flush()
    var length: Int { get }
    var device: GraphicsDevice { get }
}
