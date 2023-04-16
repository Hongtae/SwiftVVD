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

public protocol FixedAddressStorageData: DataProtocol {
    var count: Int { get }
    var isEmpty: Bool { get }
    var address: UnsafeRawPointer? { get }
}

extension BufferStorage: FixedAddressStorageData,
                         DataProtocol,
                         RandomAccessCollection,
                         BidirectionalCollection,
                         Collection,
                         Sequence
                          where Element == UInt8 {
    public typealias Element = UnsafeBufferPointer<Element>.Element
    public typealias Index = UnsafeBufferPointer<Element>.Index
    public typealias SubSequence = UnsafeBufferPointer<Element>.SubSequence
    public typealias Indices = UnsafeBufferPointer<Element>.Indices

    public var regions: UnsafeBufferPointer<Element>.Regions { pointer.regions }
    public subscript(bounds: Range<Index>) -> SubSequence { pointer[bounds] }
    public subscript(position: Index) -> Element { pointer[position] }
    public var startIndex: Index { pointer.startIndex }
    public var endIndex: Index { pointer.endIndex }
    public var address: UnsafeRawPointer? { UnsafeRawPointer(pointer.baseAddress) }
}

public class RawBufferStorage: FixedAddressStorageData {
    public let pointer: UnsafeRawBufferPointer
    public var baseAddress: UnsafeRawPointer? { pointer.baseAddress }
    public var address: UnsafeRawPointer? { pointer.baseAddress }
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

extension RawBufferStorage: DataProtocol {
    public typealias Element = UnsafeRawBufferPointer.Element
    public typealias Index = UnsafeRawBufferPointer.Index
    public typealias SubSequence = UnsafeRawBufferPointer.SubSequence
    public typealias Indices = UnsafeRawBufferPointer.Indices

    public var regions: UnsafeRawBufferPointer.Regions { pointer.regions }
    public subscript(bounds: Range<Index>) -> SubSequence { pointer[bounds] }
    public subscript(position: Index) -> Element { pointer[position] }
    public var startIndex: Index { pointer.startIndex }
    public var endIndex: Index { pointer.endIndex }
}

extension DataProtocol {
    public func makeFixedAddressStorage() -> any FixedAddressStorageData {
        if let buff = self as? (any FixedAddressStorageData) { return buff }
        return RawBufferStorage(self)
    }
}
