//
//  File: PackedVoxelOctree.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct _PackedVoxelOctreeNode {
    static let flagLeafNode = UInt8(1)
    static let flagMaterial = UInt8(1 << 1)

    var x: UInt16
    var y: UInt16
    var z: UInt16
    var depth: UInt8
    var flags: UInt8
    var advance: UInt32
    var color: UInt32
}

public struct PackedVoxelOctreeChunk {
    public let bounds: AABB
    public let level: UInt32
    public let octree: PackedVoxelOctree

    init(bounds: AABB, level: UInt32, octree: PackedVoxelOctree) {
        self.bounds = bounds
        self.level = level
        self.octree = octree
    }
}

public struct PackedVoxelOctree {
    let nodes: [_PackedVoxelOctreeNode]

    init(nodes: [_PackedVoxelOctreeNode] = []) {
        self.nodes = nodes
    }

    public var nodeCount: Int { nodes.count }
    public var nodeStride: Int { MemoryLayout<_PackedVoxelOctreeNode>.stride }
    public var byteCount: Int { nodes.count * MemoryLayout<_PackedVoxelOctreeNode>.stride }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try nodes.withUnsafeBytes(body)
    }

    public func copy(to buffer: GPUBuffer, destinationOffset: Int = 0) -> Bool {
        guard destinationOffset >= 0,
              destinationOffset + byteCount <= buffer.length,
              let destination = buffer.contents()
        else { return false }

        nodes.withUnsafeBytes {
            if let source = $0.baseAddress, $0.count > 0 {
                destination.advanced(by: destinationOffset)
                    .copyMemory(from: source, byteCount: $0.count)
            }
        }
        buffer.flush()
        return true
    }
}
