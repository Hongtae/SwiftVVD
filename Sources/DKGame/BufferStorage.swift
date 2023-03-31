//
//  File: BufferStorage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public class BufferStorage<Element> {
    public let pointer: UnsafeBufferPointer<Element>
    public var baseAddress: UnsafePointer<Element>? { pointer.baseAddress }
    public var count: Int { pointer.count }
    public var isEmpty: Bool { pointer.isEmpty }

    public init<C>(_ data: C) where C: RandomAccessCollection<Element> {
        if data.isEmpty == false {
            let count = data.count
            let buffer = UnsafeMutableBufferPointer<Element>.allocate(capacity: count)
            for (n, c) in data.enumerated() {
                buffer[n] = c
            }
            self.pointer = UnsafeBufferPointer<Element>(buffer)
        } else {
            self.pointer = UnsafeBufferPointer<Element>(start: nil, count: 0)
        }
    }

    deinit {
        if pointer.baseAddress != nil, pointer.count > 0 {
            pointer.deallocate()
        }
    }
}

public class RawBufferStorage {
    public let pointer: UnsafeRawBufferPointer
    public var baseAddress: UnsafeRawPointer? { pointer.baseAddress }
    public var count: Int { pointer.count }
    public var isEmpty: Bool { pointer.isEmpty }

    public init<D>(_ data: D) where D: DataProtocol {
        if data.isEmpty == false {
            let count = data.count
            let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: count, alignment: 1)
            data.copyBytes(to: buffer)
            self.pointer = UnsafeRawBufferPointer(buffer)
        } else {
            self.pointer = UnsafeRawBufferPointer(start: nil, count: 0)
        }
    }

    deinit {
        if pointer.baseAddress != nil, pointer.count > 0 {
            pointer.deallocate()
        }
    }
}
