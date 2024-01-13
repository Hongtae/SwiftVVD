//
//  File: GPUBuffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public enum StorageMode: UInt {
    case shared     // accessible to both the CPU and the GPU
    case `private`  // only accessible to the GPU
}

public protocol GPUBuffer: AnyObject {
    func contents() -> UnsafeMutableRawPointer?
    func flush()
    var length: Int { get }
    var device: GraphicsDevice { get }
}
