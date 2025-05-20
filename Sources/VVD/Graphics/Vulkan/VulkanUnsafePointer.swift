//
//  File: VulkanUnsafePointer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_VULKAN
import Foundation
import Vulkan

final class TemporaryBufferHolder {
    var buffers: [UnsafeRawPointer] = []
    let label: String
    init (label: String) {
        self.label = label
    }
    deinit {
        //Log.verbose("<< TemporaryBufferHolder(label:\"\(self.label)\") deallocate \(buffers.count) buffers. >>")
        for ptr in buffers {
            ptr.deallocate()
        }
    }
}

func unsafePointerCopy<T>(from object: T, holder: TemporaryBufferHolder) -> UnsafePointer<T> {
    let buffer: UnsafeMutablePointer<T> = .allocate(capacity: 1)
    withUnsafePointer(to: object) {
        buffer.initialize(from: $0, count: 1)
    }
    holder.buffers.append(buffer)
    return UnsafePointer<T>(buffer)
}

func unsafePointerCopy(string str: String, holder: TemporaryBufferHolder) -> UnsafePointer<CChar> {
    let buffer = str.withCString { ptr -> UnsafePointer<CChar> in
        let count = strlen(ptr)
        let length = count + 1
        let buffer: UnsafeMutablePointer<CChar> = .allocate(capacity: length)
#if os(Windows)
        strncpy_s(buffer, length, ptr, count)
#else
        strncpy(buffer, ptr, length)
#endif
        return UnsafePointer(buffer)
    }
    holder.buffers.append(buffer)
    return buffer
}

func unsafePointerCopy<C>(collection source: C, holder: TemporaryBufferHolder) -> UnsafePointer<C.Element>? where C: Collection {
    if source.isEmpty { return nil }

    let buffer: UnsafeMutableBufferPointer<C.Element> = .allocate(capacity: source.count)
    _ = buffer.initialize(from: source)
    let ptr = UnsafePointer<C.Element>(buffer.baseAddress!)
    holder.buffers.append(ptr)
    return ptr
}

func enumerateNextChain(_ pNext: UnsafeRawPointer?,
                        callback: (VkStructureType, UnsafeRawPointer)->Void) {
    var ptr: UnsafePointer<VkBaseInStructure>? = pNext?
        .assumingMemoryBound(to: VkBaseInStructure.self)
    while ptr != nil {
        if let ptr { callback(ptr.pointee.sType, UnsafeRawPointer(ptr)) }
        ptr = ptr?.pointee.pNext
    }
}

func appendNextChain<T>(_ s: inout T, _ pNext: UnsafeRawPointer) {
    withUnsafeMutablePointer(to: &s) {
        var ptr = UnsafeMutableRawPointer($0)
            .assumingMemoryBound(to: VkBaseOutStructure.self)
        while ptr.pointee.pNext != nil {
            ptr = ptr.pointee.pNext!
        }
        ptr.pointee.pNext = UnsafeMutableRawPointer(mutating: pNext)
            .assumingMemoryBound(to: VkBaseOutStructure.self)
    }
}
#endif //if ENABLE_VULKAN
