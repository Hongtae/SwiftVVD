//
//  File: BVH.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// An immutable bounding-volume hierarchy over integer primitive identifiers.
///
/// A BVH is built from finite bounds. Invalid or nonfinite elements are excluded.
/// Null bounds cannot be rejected by an AABB query; callers should
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
            element.bounds.isNull || !element.bounds.min.x.isFinite ||
                !element.bounds.min.y.isFinite || !element.bounds.min.z.isFinite ||
                !element.bounds.max.x.isFinite || !element.bounds.max.y.isFinite ||
                !element.bounds.max.z.isFinite
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
        if let result = quantized16() {
            return result
        }
        if let result = quantized32() {
            return result
        }
        Log.error("BVH bounds, nodes, or primitive indices cannot be represented by the quantized formats.")
        return nil
    }

    public func quantized32() -> QuantizedBVH32? {
        guard let result: ([_QuantizedBVHNode<UInt32>], Vector3) =
                makeQuantizedNodes()
        else { return nil }
        return QuantizedBVH32(nodes: result.0,
                              bounds: bounds,
                              quantizationStep: result.1)
    }

    public func quantized16() -> QuantizedBVH16? {
        guard let result: ([_QuantizedBVHNode<UInt16>], Vector3) =
                makeQuantizedNodes()
        else { return nil }
        return QuantizedBVH16(nodes: result.0,
                              bounds: bounds,
                              quantizationStep: result.1)
    }

    private func makeQuantizedNodes<T>() -> ([_QuantizedBVHNode<T>], Vector3)?
    where T: FixedWidthInteger,
          T: UnsignedInteger,
          T: SIMDScalar {
        guard nodes.count <= Int(T.max) else { return nil }
        if nodes.isEmpty {
            return ([], .zero)
        }

        let maximumCode = Scalar(T.max)
        let extents = bounds.extents
        // Even finite endpoints can overflow when their extent is computed.
        guard extents.x.isFinite, extents.y.isFinite, extents.z.isFinite else { return nil }
        let step = Vector3(
            extents.x > .zero ? extents.x / maximumCode : .zero,
            extents.y > .zero ? extents.y / maximumCode : .zero,
            extents.z > .zero ? extents.z / maximumCode : .zero)

        func quantize(_ value: Scalar,
                      axis: Int,
                      rounding rule: FloatingPointRoundingRule) -> T {
            let extent = extents[axis]
            guard extent > .zero else { return .zero }
            let normalized = ((value - bounds.min[axis]) / extent)
                .clamp(min: .zero, max: Scalar(1))
            let code = (normalized * maximumCode).rounded(rule)
            var integerCode = UInt64(code)
            let maximumIntegerCode = UInt64(T.max)
            if rule == .down && integerCode > 0 {
                integerCode -= 1
            } else if rule == .up && integerCode < maximumIntegerCode {
                integerCode += 1
            }
            return T(integerCode)
        }

        var result: [_QuantizedBVHNode<T>] = []
        result.reserveCapacity(nodes.count)
        for node in nodes {
            let advanceValue: Int
            let flags: T
            if let primitiveIndex = node.primitiveIndex {
                guard primitiveIndex >= 0,
                      let encodedIndex = T(exactly: primitiveIndex)
                else { return nil }
                advanceValue = Int(encodedIndex)
                flags = 1
            } else {
                advanceValue = node.escapeIndex
                flags = 0
            }
            guard let advance = T(exactly: advanceValue) else { return nil }

            result.append(_QuantizedBVHNode(
                minAndAdvance: SIMD4(
                    quantize(node.bounds.min.x, axis: 0, rounding: .down),
                    quantize(node.bounds.min.y, axis: 1, rounding: .down),
                    quantize(node.bounds.min.z, axis: 2, rounding: .down),
                    advance),
                maxAndFlags: SIMD4(
                    quantize(node.bounds.max.x, axis: 0, rounding: .up),
                    quantize(node.bounds.max.y, axis: 1, rounding: .up),
                    quantize(node.bounds.max.z, axis: 2, rounding: .up),
                    flags)))
        }
        return (result, step)
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

public enum QuantizedBVHFormat: Hashable, Sendable {
    case uint16
    case uint32
}

/// A conservative integer encoding of a CPU `BVH` snapshot.
///
/// Node bytes contain two native-endian integer vectors. XYZ store quantized
/// minimum and maximum bounds. For internal nodes, `minAndAdvance.w` stores the
/// preorder escape index and `maxAndFlags.w` is zero. For leaf nodes, the flag
/// is one and `minAndAdvance.w` stores the nonnegative primitive index. Bounds
/// and `quantizationStep` are supplied separately to consumers.
public protocol QuantizedBVH {
    var format: QuantizedBVHFormat { get }
    var bounds: AABB { get }
    var quantizationStep: Vector3 { get }
    var nodeCount: Int { get }
    var nodeStride: Int { get }
    var byteCount: Int { get }

    func nodeBounds(at index: Int) -> AABB?
    func primitiveIndex(at nodeIndex: Int) -> Int?
    func escapeIndex(at nodeIndex: Int) -> Int?
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
    func copy(to buffer: GPUBuffer, destinationOffset: Int) -> Bool
}

public struct QuantizedBVH16: QuantizedBVH {
    typealias Node = _QuantizedBVHNode<UInt16>
    let nodes: [Node]

    public let bounds: AABB
    public let quantizationStep: Vector3

    init(nodes: [Node], bounds: AABB, quantizationStep: Vector3) {
        self.nodes = nodes
        self.bounds = bounds
        self.quantizationStep = quantizationStep
    }

    public var format: QuantizedBVHFormat { .uint16 }
    public var nodeCount: Int { nodes.count }
    public var nodeStride: Int { MemoryLayout<Node>.stride }
    public var byteCount: Int { nodes.count * MemoryLayout<Node>.stride }

    public func nodeBounds(at index: Int) -> AABB? {
        _quantizedNodeBounds(nodes, index: index,
                             bounds: bounds,
                             step: quantizationStep)
    }

    public func primitiveIndex(at nodeIndex: Int) -> Int? {
        _quantizedPrimitiveIndex(nodes, index: nodeIndex)
    }

    public func escapeIndex(at nodeIndex: Int) -> Int? {
        _quantizedEscapeIndex(nodes, index: nodeIndex)
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try nodes.withUnsafeBytes(body)
    }
}

public struct QuantizedBVH32: QuantizedBVH {
    typealias Node = _QuantizedBVHNode<UInt32>
    let nodes: [Node]

    public let bounds: AABB
    public let quantizationStep: Vector3

    init(nodes: [Node], bounds: AABB, quantizationStep: Vector3) {
        self.nodes = nodes
        self.bounds = bounds
        self.quantizationStep = quantizationStep
    }

    public var format: QuantizedBVHFormat { .uint32 }
    public var nodeCount: Int { nodes.count }
    public var nodeStride: Int { MemoryLayout<Node>.stride }
    public var byteCount: Int { nodes.count * MemoryLayout<Node>.stride }

    public func nodeBounds(at index: Int) -> AABB? {
        _quantizedNodeBounds(nodes, index: index,
                             bounds: bounds,
                             step: quantizationStep)
    }

    public func primitiveIndex(at nodeIndex: Int) -> Int? {
        _quantizedPrimitiveIndex(nodes, index: nodeIndex)
    }

    public func escapeIndex(at nodeIndex: Int) -> Int? {
        _quantizedEscapeIndex(nodes, index: nodeIndex)
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try nodes.withUnsafeBytes(body)
    }
}

extension QuantizedBVH {
    /// Returns quantized-tree overlap candidates. Quantization is conservative,
    /// so this set may contain false positives but does not omit CPU-BVH hits.
    public func primitiveIndices(overlapping queryBounds: AABB) -> [Int] {
        var result: [Int] = []
        query(overlapping: queryBounds) {
            result.append($0)
            return true
        }
        return result
    }

    /// Traverses the preorder nodes without decoding or rebuilding the tree.
    @discardableResult
    public func query(overlapping queryBounds: AABB,
                      _ body: (Int) throws -> Bool) rethrows -> Bool {
        guard queryBounds.isNull == false else { return true }

        var nodeIndex = 0
        while nodeIndex < nodeCount {
            guard let nodeBounds = nodeBounds(at: nodeIndex),
                  nodeBounds.intersects(queryBounds) else {
                guard let escapeIndex = escapeIndex(at: nodeIndex) else {
                    return true
                }
                nodeIndex = escapeIndex
                continue
            }

            if let primitiveIndex = primitiveIndex(at: nodeIndex),
               try body(primitiveIndex) == false {
                return false
            }
            nodeIndex += 1
        }
        return true
    }

    public func copy(to buffer: GPUBuffer, destinationOffset: Int = 0) -> Bool {
        guard destinationOffset >= 0,
              byteCount <= buffer.length,
              destinationOffset <= buffer.length - byteCount,
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

private func _quantizedNodeBounds<T>(
    _ nodes: [_QuantizedBVHNode<T>],
    index: Int,
    bounds: AABB,
    step: Vector3
) -> AABB?
where T: FixedWidthInteger,
      T: UnsignedInteger,
      T: SIMDScalar {
    guard nodes.indices.contains(index) else { return nil }
    let node = nodes[index]
    return AABB(
        min: Vector3(bounds.min.x + Scalar(node.min.0) * step.x,
                     bounds.min.y + Scalar(node.min.1) * step.y,
                     bounds.min.z + Scalar(node.min.2) * step.z),
        max: Vector3(bounds.min.x + Scalar(node.max.0) * step.x,
                     bounds.min.y + Scalar(node.max.1) * step.y,
                     bounds.min.z + Scalar(node.max.2) * step.z))
}

private func _quantizedPrimitiveIndex<T>(
    _ nodes: [_QuantizedBVHNode<T>],
    index: Int
) -> Int?
where T: FixedWidthInteger,
      T: UnsignedInteger,
      T: SIMDScalar {
    guard nodes.indices.contains(index), nodes[index].flags == 1 else {
        return nil
    }
    return Int(nodes[index].advance)
}

private func _quantizedEscapeIndex<T>(
    _ nodes: [_QuantizedBVHNode<T>],
    index: Int
) -> Int?
where T: FixedWidthInteger,
      T: UnsignedInteger,
      T: SIMDScalar {
    guard nodes.indices.contains(index) else { return nil }
    return nodes[index].flags == 1
        ? index + 1
        : Int(nodes[index].advance)
}
