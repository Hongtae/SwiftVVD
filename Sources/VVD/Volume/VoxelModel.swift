//
//  File: VoxelModel.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct VoxelModel: Volume {
    public struct Metadata: Hashable, Sendable {
        public var center: Vector3
        public var scale: Scalar

        public init(center: Vector3 = Vector3(0.5, 0.5, 0.5), scale: Scalar = 1.0) {
            self.center = center
            self.scale = scale
        }
    }

    public private(set) var depth: UInt32
    public var metadata: Metadata

    var root: VoxelOctree?

    public init(depth: UInt32 = 0, metadata: Metadata = .init()) {
        self.depth = depth
        self.metadata = metadata
        self.root = nil
    }

    public mutating func update(x: UInt32, y: UInt32, z: UInt32, value: Voxel) {
        let resolution = addressableResolution()
        precondition(UInt64(x) < resolution &&
                     UInt64(y) < resolution &&
                     UInt64(z) < resolution,
                     "Voxel coordinates are out of range.")

        if root == nil {
            root = VoxelOctree(value: value)
        }

        if resolution > 1 {
            var rootNode = root!
            if rootNode.update(x: UInt64(x),
                               y: UInt64(y),
                               z: UInt64(z),
                               dimension: resolution >> 1,
                               value: value) {
                _ = rootNode.mergeSolidBranches()
            }
            root = rootNode
        } else {
            root?.value = value
        }
    }

    public mutating func erase(x: UInt32, y: UInt32, z: UInt32) {
        let resolution = addressableResolution()
        precondition(UInt64(x) < resolution &&
                     UInt64(y) < resolution &&
                     UInt64(z) < resolution,
                     "Voxel coordinates are out of range.")

        guard var rootNode = root else { return }

        if resolution > 1 {
            if rootNode.erase(x: UInt64(x),
                              y: UInt64(y),
                              z: UInt64(z),
                              dimension: resolution >> 1) {
                if rootNode.isLeaf {
                    root = nil
                } else {
                    _ = rootNode.mergeSolidBranches()
                    root = rootNode
                }
            }
        } else {
            root = nil
        }
    }

    public func lookup(x: UInt32, y: UInt32, z: UInt32) -> Voxel? {
        let resolution = addressableResolution()
        precondition(UInt64(x) < resolution &&
                     UInt64(y) < resolution &&
                     UInt64(z) < resolution,
                     "Voxel coordinates are out of range.")

        guard let root else { return nil }

        if resolution > 1 {
            let node = root.lookup(x: UInt64(x),
                                   y: UInt64(y),
                                   z: UInt64(z),
                                   dimension: resolution >> 1)
            return node.isLeaf ? node.value : nil
        }
        return root.value
    }

    public func rayTest(_ ray: Ray, option: VoxelRayHit.Option = .closest) -> VoxelRayHit? {
        var rayHit: VoxelRayHit?

        switch option {
        case .any:
            _ = rayTest(ray) { hit in
                rayHit = hit
                return false
            }
        case .closest:
            _ = rayTest(ray) { hit in
                if let current = rayHit {
                    if hit.t < current.t {
                        rayHit = hit
                    }
                } else {
                    rayHit = hit
                }
                return true
            }
        case .longest:
            _ = rayTest(ray) { hit in
                if let current = rayHit {
                    if hit.t > current.t {
                        rayHit = hit
                    }
                } else {
                    rayHit = hit
                }
                return true
            }
        }
        return rayHit
    }

    @discardableResult
    public func rayTest(_ ray: Ray, _ body: (VoxelRayHit) throws -> Bool) rethrows -> UInt64 {
        guard let root else { return 0 }

        var continueRayTest = true
        let normalizedRay = ray.normalized(to: metadata)
        return try RayTestNode(node: root,
                               center: Vector3(0.5, 0.5, 0.5),
                               depth: 0,
                               resolution: addressableResolution())
            .rayTest(normalizedRay,
                     continueRayTest: &continueRayTest,
                     body)
    }

    public func packedVoxelOctree(maxDepth: UInt32? = nil) -> PackedVoxelOctree {
        guard let root else { return PackedVoxelOctree() }
        return PackedVoxelOctree(
            nodes: Self.packedNodes(from: root,
                                    center: Vector3(0.5, 0.5, 0.5),
                                    level: 0,
                                    maxDepth: resolvedPackingMaxDepth(maxDepth)))
    }

    public func packedVoxelOctree(normalizedPosition position: Vector3,
                                  level: UInt32,
                                  maxDepth: UInt32? = nil) -> PackedVoxelOctree {
        guard let root,
              position.x >= .zero, position.x <= 1,
              position.y >= .zero, position.y <= 1,
              position.z >= .zero, position.z <= 1,
              let subtree = root.subtree(containing: position,
                                         center: Vector3(0.5, 0.5, 0.5),
                                         level: 0,
                                         targetLevel: level)
        else { return PackedVoxelOctree() }

        return PackedVoxelOctree(
            nodes: Self.packedNodes(from: subtree.node,
                                    center: subtree.center,
                                    level: subtree.level,
                                    maxDepth: resolvedPackingMaxDepth(maxDepth)))
    }

    public func packedVoxelOctreeChunks(splitLevel: UInt32,
                                        maxDepth: UInt32? = nil) -> [PackedVoxelOctreeChunk] {
        guard let root else { return [] }

        let maxDepth = resolvedPackingMaxDepth(maxDepth)
        let unitBounds = AABB(min: .zero, max: Vector3(1, 1, 1))
        var chunks: [PackedVoxelOctreeChunk] = []

        root.forEachNode(atLevel: splitLevel, bounds: unitBounds, level: 0) { bounds, level, node in
            let octree = PackedVoxelOctree(
                nodes: Self.packedNodes(from: node,
                                        center: bounds.center,
                                        level: level,
                                        maxDepth: maxDepth))
            chunks.append(PackedVoxelOctreeChunk(bounds: bounds, level: level, octree: octree))
        }
        return chunks
    }

    private struct RayTestNode {
        let node: VoxelOctree
        let center: Vector3
        let depth: UInt32
        let resolution: UInt64

        func rayTest(_ ray: Ray,
                     continueRayTest: inout Bool,
                     _ body: (VoxelRayHit) throws -> Bool) rethrows -> UInt64 {
            let halfExtent = VoxelOctree.halfExtent(atDepth: depth)
            let aabb = AABB(center: center,
                            halfExtents: Vector3(halfExtent, halfExtent, halfExtent))
            let t = aabb.rayTest(rayOrigin: ray.origin, direction: ray.direction)
            if t < .zero {
                return 0
            }

            var hitCount: UInt64 = 0

            try node.forEachChild(center: center, depth: depth) { childCenter, childDepth, child in
                if continueRayTest {
                    hitCount += try RayTestNode(node: child,
                                                center: childCenter,
                                                depth: childDepth,
                                                resolution: resolution)
                        .rayTest(ray,
                                 continueRayTest: &continueRayTest,
                                 body)
                }
            }

            if node.isLeaf {
                let hit = VoxelRayHit(t: t,
                                      location: location,
                                      depth: depth,
                                      voxel: node.value)
                hitCount += 1
                if try body(hit) == false {
                    continueRayTest = false
                }
            }
            return hitCount
        }

        private var location: (x: UInt32, y: UInt32, z: UInt32) {
            assert(resolution > 0)
            let maxValue = resolution - 1

            func component(_ value: Scalar) -> UInt32 {
                let scaled = (value * Scalar(resolution)).rounded(.down)
                if scaled <= .zero {
                    return 0
                }
                let coordinate = UInt64(scaled)
                return UInt32(Swift.min(coordinate, maxValue))
            }

            return (x: component(center.x),
                    y: component(center.y),
                    z: component(center.z))
        }
    }

    private func addressableResolution() -> UInt64 {
        precondition(depth <= 32, "VoxelModel coordinates are UInt32, so depth must be 32 or less.")
        return UInt64(1) << Int(depth)
    }

    private func resolvedPackingMaxDepth(_ maxDepth: UInt32?) -> UInt32 {
        Swift.min(maxDepth ?? depth, VoxelOctree.maxDepth)
    }

    private static func packedNodes(from node: VoxelOctree,
                                    center: Vector3,
                                    level: UInt32,
                                    maxDepth: UInt32) -> [_PackedVoxelOctreeNode] {
        var nodes: [_PackedVoxelOctreeNode] = []
        appendPackedNode(from: node,
                         center: center,
                         level: level,
                         maxDepth: maxDepth,
                         to: &nodes)
        return nodes
    }

    private static func appendPackedNode(from node: VoxelOctree,
                                         center: Vector3,
                                         level: UInt32,
                                         maxDepth: UInt32,
                                         to nodes: inout [_PackedVoxelOctreeNode]) {
        let index = nodes.count
        nodes.append(_PackedVoxelOctreeNode(x: quantizeNormalized(center.x),
                                            y: quantizeNormalized(center.y),
                                            z: quantizeNormalized(center.z),
                                            depth: UInt8(Swift.min(level, UInt32(UInt8.max))),
                                            flags: 0,
                                            advance: 0,
                                            color: node.value.packedColor))

        if level < maxDepth {
            node.forEachChild(center: center, depth: level) { childCenter, childLevel, child in
                appendPackedNode(from: child,
                                 center: childCenter,
                                 level: childLevel,
                                 maxDepth: maxDepth,
                                 to: &nodes)
            }
        }

        let advance = nodes.count - index
        precondition(advance <= Int(UInt32.max), "Packed voxel octree node advance exceeds UInt32 range.")
        nodes[index].advance = UInt32(advance)
        if advance == 1 {
            nodes[index].flags = _PackedVoxelOctreeNode.flagLeafNode |
                                 _PackedVoxelOctreeNode.flagMaterial
        }
    }

    private static func quantizeNormalized(_ value: Scalar) -> UInt16 {
        let scaled = value * Scalar(UInt16.max)
        if scaled <= .zero {
            return 0
        }
        if scaled >= Scalar(UInt16.max) {
            return UInt16.max
        }
        return UInt16(scaled)
    }
}

private extension Ray {
    func normalized(to metadata: VoxelModel.Metadata) -> Ray {
        precondition(metadata.scale > .zero, "VoxelModel metadata scale must be greater than zero.")

        let halfScale = Vector3(metadata.scale, metadata.scale, metadata.scale) * 0.5
        let min = metadata.center - halfScale
        return Ray(origin: (origin - min) / metadata.scale,
                   direction: direction / metadata.scale)
    }
}

struct VoxelOctree {
    static let maxDepth: UInt32 = 124

    var value: Voxel
    var childMask: UInt8
    var children: [VoxelOctree]

    var isLeaf: Bool { childMask == 0 }

    init(value: Voxel = Voxel(), childMask: UInt8 = 0, children: [VoxelOctree] = []) {
        assert(children.count == childMask.nonzeroBitCount)
        self.value = value
        self.childMask = childMask
        self.children = children
    }

    func childOffset(for index: UInt8) -> Int? {
        assert(index < 8)
        let bit = UInt8(1) << index
        if (childMask & bit) == 0 {
            return nil
        }
        return (childMask & (bit - 1)).nonzeroBitCount
    }

    mutating func ensureChild(at index: UInt8) -> (offset: Int, inserted: Bool) {
        assert(index < 8)
        if let offset = childOffset(for: index) {
            return (offset, false)
        }

        let bit = UInt8(1) << index
        let nextMask = childMask | bit
        let offset = (childMask & (bit - 1)).nonzeroBitCount
        var nextChildren = Array(repeating: VoxelOctree(),
                                 count: nextMask.nonzeroBitCount)

        for childIndex in UInt8(0)..<UInt8(8) {
            let childBit = UInt8(1) << childIndex
            if (childMask & childBit) != 0 {
                let oldOffset = (childMask & (childBit - 1)).nonzeroBitCount
                let nextOffset = (nextMask & (childBit - 1)).nonzeroBitCount
                nextChildren[nextOffset] = children[oldOffset]
            }
        }

        childMask = nextMask
        children = nextChildren
        return (offset, true)
    }

    mutating func subdivide(mask: UInt8) {
        let nextMask = childMask | mask
        if nextMask == childMask {
            return
        }

        var nextChildren = Array(repeating: VoxelOctree(value: value),
                                 count: nextMask.nonzeroBitCount)
        for index in UInt8(0)..<UInt8(8) {
            let bit = UInt8(1) << index
            if (childMask & bit) != 0 {
                let oldOffset = (childMask & (bit - 1)).nonzeroBitCount
                let nextOffset = (nextMask & (bit - 1)).nonzeroBitCount
                nextChildren[nextOffset] = children[oldOffset]
            }
        }

        childMask = nextMask
        children = nextChildren
    }

    mutating func removeChildren(mask removalMask: UInt8) {
        let nextMask = childMask & ~removalMask
        if nextMask == childMask {
            return
        }

        if nextMask == 0 {
            childMask = 0
            children.removeAll()
            return
        }

        var nextChildren = Array(repeating: VoxelOctree(),
                                 count: nextMask.nonzeroBitCount)

        for index in UInt8(0)..<UInt8(8) {
            let bit = UInt8(1) << index
            if (childMask & bit) != 0 && (nextMask & bit) != 0 {
                let oldOffset = (childMask & (bit - 1)).nonzeroBitCount
                let nextOffset = (nextMask & (bit - 1)).nonzeroBitCount
                nextChildren[nextOffset] = children[oldOffset]
            }
        }

        childMask = nextMask
        children = nextChildren
    }

    mutating func update(x: UInt64, y: UInt64, z: UInt64, dimension: UInt64, value: Voxel) -> Bool {
        assert(dimension > 0)

        let index = UInt8((((z / dimension) & 1) << 2) |
                          (((y / dimension) & 1) << 1) |
                          ((x / dimension) & 1))

        let child = ensureChild(at: index)
        var updated = child.inserted

        if dimension > 1 {
            if children[child.offset].update(x: x % dimension,
                                             y: y % dimension,
                                             z: z % dimension,
                                             dimension: dimension >> 1,
                                             value: value) {
                updated = true
            }
        } else if children[child.offset].value != value {
            children[child.offset].value = value
            updated = true
        }

        if updated {
            _ = mergeSolidBranches()
        }
        return updated
    }

    mutating func erase(x: UInt64, y: UInt64, z: UInt64, dimension: UInt64) -> Bool {
        assert(dimension > 0)

        let index = UInt8((((z / dimension) & 1) << 2) |
                          (((y / dimension) & 1) << 1) |
                          ((x / dimension) & 1))
        let bit = UInt8(1) << index

        if dimension > 1 {
            if isLeaf {
                subdivide(mask: 0xff)
            }

            guard let offset = childOffset(for: index) else {
                return false
            }

            if children[offset].erase(x: x % dimension,
                                      y: y % dimension,
                                      z: z % dimension,
                                      dimension: dimension >> 1) {
                if children[offset].isLeaf {
                    removeChildren(mask: bit)
                }
                _ = mergeSolidBranches()
                return true
            }
        } else {
            if let offset = childOffset(for: index) {
                assert(children[offset].isLeaf)
                removeChildren(mask: bit)
                _ = mergeSolidBranches()
                return true
            } else if isLeaf {
                subdivide(mask: 0xff & ~bit)
                return true
            }
        }
        return false
    }

    func lookup(x: UInt64, y: UInt64, z: UInt64, dimension: UInt64) -> VoxelOctree {
        assert(dimension > 0)

        let index = UInt8((((z / dimension) & 1) << 2) |
                          (((y / dimension) & 1) << 1) |
                          ((x / dimension) & 1))

        guard let offset = childOffset(for: index) else {
            return self
        }

        if dimension > 1 {
            return children[offset].lookup(x: x % dimension,
                                           y: y % dimension,
                                           z: z % dimension,
                                           dimension: dimension >> 1)
        }
        return children[offset]
    }

    func subtree(containing point: Vector3,
                 center: Vector3,
                 level: UInt32,
                 targetLevel: UInt32) -> (node: VoxelOctree, center: Vector3, level: UInt32)? {
        if level >= targetLevel || isLeaf {
            return (self, center, level)
        }

        let x = point.x >= center.x ? UInt8(1) : UInt8(0)
        let y = point.y >= center.y ? UInt8(1) : UInt8(0)
        let z = point.z >= center.z ? UInt8(1) : UInt8(0)
        let index = (z << 2) | (y << 1) | x

        guard let offset = childOffset(for: index) else {
            return nil
        }

        let childCenter = childCenter(for: index, center: center, depth: level)
        return children[offset].subtree(containing: point,
                                        center: childCenter,
                                        level: level + 1,
                                        targetLevel: targetLevel)
    }

    mutating func mergeSolidBranches() -> Bool {
        if children.isEmpty {
            return false
        }

        value = Voxel(averaging: children.map(\.value))

        if children.count == 8 && children.allSatisfy({ $0.isLeaf && $0.value == value }) {
            childMask = 0
            children.removeAll()
        }
        return true
    }

    static func halfExtent(atDepth depth: UInt32) -> Scalar {
        let clampedDepth = Swift.min(depth, 125)
        let exponent = (UInt32(126) - clampedDepth) << 23
        return Scalar(Float32(bitPattern: exponent))
    }

    func forEachChild(_ body: (UInt8, VoxelOctree) throws -> Void) rethrows {
        var childOffset = 0
        for index in UInt8(0)..<UInt8(8) {
            if (childMask & (1 << index)) != 0 {
                try body(index, children[childOffset])
                childOffset += 1
            }
        }
    }

    mutating func forEachChild(_ body: (UInt8, inout VoxelOctree) throws -> Void) rethrows {
        var childOffset = 0
        for index in UInt8(0)..<UInt8(8) {
            if (childMask & (1 << index)) != 0 {
                try body(index, &children[childOffset])
                childOffset += 1
            }
        }
    }

    func forEachChild(in bounds: AABB, _ body: (AABB, VoxelOctree) throws -> Void) rethrows {
        let pivot = bounds.min
        let halfExtents = bounds.extents * 0.5

        try forEachChild { index, child in
            let x = Scalar(index & 1)
            let y = Scalar((index >> 1) & 1)
            let z = Scalar((index >> 2) & 1)
            let min = pivot + halfExtents * Vector3(x, y, z)
            try body(AABB(min: min, max: min + halfExtents), child)
        }
    }

    @discardableResult
    func forEachNode(atLevel targetLevel: UInt32,
                     bounds: AABB,
                     level: UInt32,
                     _ body: (AABB, UInt32, VoxelOctree) throws -> Void) rethrows -> UInt32 {
        if level < targetLevel {
            var count: UInt32 = 0
            try forEachChild(in: bounds) { childBounds, child in
                count += try child.forEachNode(atLevel: targetLevel,
                                               bounds: childBounds,
                                               level: level + 1,
                                               body)
            }
            if count > 0 {
                return count
            }
        }

        try body(bounds, level, self)
        return 1
    }

    func forEachChild(center: Vector3,
                      depth: UInt32,
                      _ body: (Vector3, UInt32, VoxelOctree) throws -> Void) rethrows {
        try forEachChild { index, child in
            try body(childCenter(for: index, center: center, depth: depth),
                     depth + 1,
                     child)
        }
    }

    private func childCenter(for index: UInt8, center: Vector3, depth: UInt32) -> Vector3 {
        let halfExtent = Self.halfExtent(atDepth: depth)
        let x = Scalar(index & 1) - 0.5
        let y = Scalar((index >> 1) & 1) - 0.5
        let z = Scalar((index >> 2) & 1) - 0.5
        return center + Vector3(x, y, z) * halfExtent
    }
}

private extension Voxel {
    init(averaging voxels: [Voxel]) {
        assert(voxels.isEmpty == false)

        var r: UInt32 = 0
        var g: UInt32 = 0
        var b: UInt32 = 0
        var a: UInt32 = 0
        var metallic: UInt32 = 0
        var roughness: UInt32 = 0

        for voxel in voxels {
            let color = voxel.rgba8
            r += UInt32(color.r)
            g += UInt32(color.g)
            b += UInt32(color.b)
            a += UInt32(color.a)
            metallic += UInt32(voxel.metallic)
            roughness += UInt32(voxel.roughness)
        }

        let count = UInt32(voxels.count)
        self.init(rgba8: .init(r: UInt8(r / count),
                               g: UInt8(g / count),
                               b: UInt8(b / count),
                               a: UInt8(a / count)),
                  metallic: UInt8(metallic / count),
                  roughness: UInt8(roughness / count))
    }
}
