//
//  File: Buffer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public enum StorageMode: UInt {
    case shared     // accessible to both the CPU and the GPU
    case `private`  // only accessible to the GPU
}

public protocol Buffer: AnyObject {
    func contents() -> UnsafeMutableRawPointer?
    func flush()
    var length: Int { get }
    var device: GraphicsDevice { get }
}
