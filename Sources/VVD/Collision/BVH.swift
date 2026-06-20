//
//  File: BVH.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct BVH {
    public let bounds: AABB

    public struct Node {
        public let aabb: AABB
        public let primitiveIndex: Int
    }

    let nodes: [Node]

    public init(_ bounds: AABB = .null) {
        self.bounds = bounds
        self.nodes = []
    }

    public init(bounds: AABB, nodes: [Node]) {
        self.bounds = bounds
        self.nodes = nodes
    }

    public func quantized() -> (any QuantizedBVH)? {
        if nodes.count <= UInt16.max {
            return quantized16()
        } else if nodes.count <= UInt32.max {
            return quantized32()
        }
        Log.error("BVH node count exceeds UInt32.max. Cannot quantize BVH.")
        return nil
    }

    public func quantized32() -> QuantizedBVH32 {
        QuantizedBVH32()
    }

    public func quantized16() -> QuantizedBVH16 {
        QuantizedBVH16()
    }
}

struct _QuantizedBVHNode<T>
where T: FixedWidthInteger, T: UnsignedInteger, T: SIMDScalar {
    let minAndAdvance: SIMD4<T>
    let maxAndFlags: SIMD4<T>

    var min: (T, T, T) { (minAndAdvance.x, minAndAdvance.y, minAndAdvance.z) }
    var max: (T, T, T) { (maxAndFlags.x, maxAndFlags.y, maxAndFlags.z) }
    var advance: T { minAndAdvance.w }
    var flags: T { maxAndFlags.w }
}

public enum QuantizedBVHFormat {
    case uint16
    case uint32
}

public protocol QuantizedBVH {
    var format: QuantizedBVHFormat { get }
    var nodeCount: Int { get }
    var nodeStride: Int { get }
    var byteCount: Int { get }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
    func copy(to buffer: GPUBuffer, destinationOffset: Int) -> Bool
}

public struct QuantizedBVH16: QuantizedBVH {
    typealias Node = _QuantizedBVHNode<UInt16>
    let nodes: [Node] = []

    public var format: QuantizedBVHFormat { .uint16 }
    public var nodeCount: Int { nodes.count }
    public var nodeStride: Int { MemoryLayout<Node>.stride }
    public var byteCount: Int { nodes.count * MemoryLayout<Node>.stride }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try nodes.withUnsafeBytes(body)
    }
}

public struct QuantizedBVH32: QuantizedBVH {
    typealias Node = _QuantizedBVHNode<UInt32>
    let nodes: [Node] = []

    public var format: QuantizedBVHFormat { .uint32 }
    public var nodeCount: Int { nodes.count }
    public var nodeStride: Int { MemoryLayout<Node>.stride }
    public var byteCount: Int { nodes.count * MemoryLayout<Node>.stride }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try nodes.withUnsafeBytes(body)
    }
}

extension QuantizedBVH {
    public func copy(to buffer: GPUBuffer, destinationOffset: Int = 0) -> Bool {
        guard destinationOffset >= 0,
              destinationOffset + byteCount <= buffer.length,
              let destination = buffer.contents()
        else { return false }

        self.withUnsafeBytes {
            if let source = $0.baseAddress, $0.count > 0 {
                destination.advanced(by: destinationOffset)
                    .copyMemory(from: source, byteCount: $0.count)
            }
        }
        buffer.flush()
        return true
    }
}
