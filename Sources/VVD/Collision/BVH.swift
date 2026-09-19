//
//  File: BVH.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// An immutable bounding-volume hierarchy over integer primitive identifiers.
///
/// A BVH is built from a bounds snapshot. Elements with null bounds are not
/// included because they cannot be rejected by an AABB query; callers should
/// retain those elements separately and include them as unconditional
/// candidates.
public struct BVH: Sendable {
    public struct Element: Hashable, Sendable {
        public let bounds: AABB
        public let primitiveIndex: Int

        public init(bounds: AABB, primitiveIndex: Int) {
            self.bounds = bounds
            self.primitiveIndex = primitiveIndex
        }
    }

    private struct Node: Sendable {
        let bounds: AABB
        let primitiveIndex: Int?
        var escapeIndex: Int
    }

    private struct BuildElement {
        let element: Element
        let insertionIndex: Int
    }

    public let bounds: AABB
    public let elementCount: Int

    public var nodeCount: Int { nodes.count }
    public var isEmpty: Bool { nodes.isEmpty }

    private let nodes: [Node]

    public init() {
        self.bounds = .null
        self.elementCount = 0
        self.nodes = []
    }

    public init(_ elements: [Element]) {
        var elements = elements.enumerated().compactMap { index, element in
            element.bounds.isNull
                ? nil
                : BuildElement(element: element, insertionIndex: index)
        }
        guard elements.isEmpty == false else {
            self.bounds = .null
            self.elementCount = 0
            self.nodes = []
            return
        }

        var nodes: [Node] = []
        nodes.reserveCapacity(elements.count * 2 - 1)
        Self.buildNodes(elements: &elements,
                        range: elements.indices,
                        nodes: &nodes)

        self.bounds = nodes[0].bounds
        self.elementCount = elements.count
        self.nodes = nodes
    }

    /// Returns primitive identifiers whose bounds overlap `queryBounds`.
    ///
    /// Result order follows tree traversal and is not an insertion-order
    /// guarantee. A null query has no finite overlap candidates.
    public func primitiveIndices(overlapping queryBounds: AABB) -> [Int] {
        var result: [Int] = []
        query(overlapping: queryBounds) { primitiveIndex in
            result.append(primitiveIndex)
            return true
        }
        return result
    }

    /// Returns primitive identifiers whose bounds intersect `ray`.
    ///
    /// Result order follows tree traversal and is not an insertion-order
    /// guarantee. An invalid ray has no candidates.
    public func primitiveIndices(intersecting ray: Ray) -> [Int] {
        var result: [Int] = []
        query(intersecting: ray) { primitiveIndex in
            result.append(primitiveIndex)
            return true
        }
        return result
    }

    /// Visits primitive identifiers whose bounds overlap `queryBounds`.
    ///
    /// Return `false` from `body` to stop traversal. The return value is `true`
    /// when the full query completed and `false` when the visitor stopped it.
    @discardableResult
    public func query(overlapping queryBounds: AABB,
                      _ body: (Int) throws -> Bool) rethrows -> Bool {
        guard queryBounds.isNull == false else { return true }

        return try queryNodes(where: { $0.intersects(queryBounds) }, body)
    }

    /// Visits primitive identifiers whose bounds intersect `ray`.
    ///
    /// Return `false` from `body` to stop traversal. The return value is `true`
    /// when the full query completed and `false` when the visitor stopped it.
    @discardableResult
    public func query(intersecting ray: Ray,
                      _ body: (Int) throws -> Bool) rethrows -> Bool {
        guard ray.isValid else { return true }

        return try queryNodes(where: { $0.intersects(ray) }, body)
    }

    private func queryNodes(where intersects: (AABB) -> Bool,
                            _ body: (Int) throws -> Bool) rethrows -> Bool {
        var nodeIndex = 0
        while nodeIndex < nodes.count {
            let node = nodes[nodeIndex]
            guard intersects(node.bounds) else {
                nodeIndex = node.escapeIndex
                continue
            }

            if let primitiveIndex = node.primitiveIndex,
               try body(primitiveIndex) == false {
                return false
            }
            nodeIndex += 1
        }
        return true
    }

    private static func buildNodes(elements: inout [BuildElement],
                                   range: Range<Int>,
                                   nodes: inout [Node]) {
        var nodeBounds = AABB.null
        var centerBounds = AABB.null
        for index in range {
            nodeBounds.combine(elements[index].element.bounds)
            centerBounds.expand(elements[index].element.bounds.center)
        }

        let nodeIndex = nodes.count
        nodes.append(Node(bounds: nodeBounds,
                          primitiveIndex: nil,
                          escapeIndex: nodeIndex + 1))

        if range.count == 1 {
            nodes[nodeIndex] = Node(
                bounds: nodeBounds,
                primitiveIndex: elements[range.lowerBound].element.primitiveIndex,
                escapeIndex: nodeIndex + 1)
            return
        }

        let axis = longestAxis(centerBounds.extents)
        elements[range].sort { lhs, rhs in
            let lhsCenter = lhs.element.bounds.center[axis]
            let rhsCenter = rhs.element.bounds.center[axis]
            if lhsCenter == rhsCenter {
                return lhs.insertionIndex < rhs.insertionIndex
            }
            return lhsCenter < rhsCenter
        }

        let middleIndex = range.lowerBound + range.count / 2
        buildNodes(elements: &elements,
                   range: range.lowerBound..<middleIndex,
                   nodes: &nodes)
        buildNodes(elements: &elements,
                   range: middleIndex..<range.upperBound,
                   nodes: &nodes)
        nodes[nodeIndex].escapeIndex = nodes.count
    }

    private static func longestAxis(_ extents: Vector3) -> Int {
        var axis = 0
        if extents.y > extents[axis] { axis = 1 }
        if extents.z > extents[axis] { axis = 2 }
        return axis
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
