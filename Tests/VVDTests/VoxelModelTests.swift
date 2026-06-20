import XCTest
@testable import VVD

final class VoxelModelTests: XCTestCase {
    func testEraseRemovesLastVoxel() {
        var model = VoxelModel(depth: 2)
        let voxel = Voxel(color: .init(1, 0, 0, 1))

        model.update(x: 1, y: 1, z: 1, value: voxel)
        XCTAssertNotNil(model.root)
        XCTAssertEqual(model.lookup(x: 1, y: 1, z: 1), voxel)

        model.erase(x: 1, y: 1, z: 1)
        XCTAssertNil(model.root)
        XCTAssertNil(model.lookup(x: 1, y: 1, z: 1))
    }

    func testEraseSplitsSolidLeaf() {
        var model = VoxelModel(depth: 1)
        let voxel = Voxel(color: .init(1, 0, 0, 1))

        for z in UInt32(0)..<2 {
            for y in UInt32(0)..<2 {
                for x in UInt32(0)..<2 {
                    model.update(x: x, y: y, z: z, value: voxel)
                }
            }
        }

        XCTAssertEqual(model.root?.childMask, 0)
        XCTAssertEqual(model.lookup(x: 0, y: 0, z: 0), voxel)
        XCTAssertEqual(model.lookup(x: 1, y: 0, z: 0), voxel)

        model.erase(x: 1, y: 0, z: 0)
        XCTAssertEqual(model.root?.childMask, 0xfd)
        XCTAssertEqual(model.lookup(x: 0, y: 0, z: 0), voxel)
        XCTAssertNil(model.lookup(x: 1, y: 0, z: 0))
    }

    func testRayTestVisitsHits() {
        var model = VoxelModel(depth: 1)
        let left = Voxel(color: .init(1, 0, 0, 1))
        let right = Voxel(color: .init(0, 1, 0, 1))
        let ray = Ray(origin: Vector3(-1, 0.25, 0.25),
                      direction: Vector3(1, 0, 0))

        model.update(x: 0, y: 0, z: 0, value: left)
        model.update(x: 1, y: 0, z: 0, value: right)

        var locations: [(x: UInt32, y: UInt32, z: UInt32)] = []
        let count = model.rayTest(ray) { hit in
            locations.append(hit.location)
            return true
        }

        XCTAssertEqual(count, 2)
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[0].x, 0)
        XCTAssertEqual(locations[0].y, 0)
        XCTAssertEqual(locations[0].z, 0)
        XCTAssertEqual(locations[1].x, 1)
        XCTAssertEqual(locations[1].y, 0)
        XCTAssertEqual(locations[1].z, 0)
        XCTAssertEqual(model.rayTest(ray, option: .closest)?.location.x, 0)
        XCTAssertEqual(model.rayTest(ray, option: .longest)?.location.x, 1)

        var anyCount = 0
        let stoppedCount = model.rayTest(ray) { _ in
            anyCount += 1
            return false
        }
        XCTAssertEqual(stoppedCount, 1)
        XCTAssertEqual(anyCount, 1)
    }

    func testRayTestUsesWorldMetadata() {
        var model = VoxelModel(depth: 1,
                               metadata: .init(center: Vector3(10, 0, 0), scale: 4))
        let voxel = Voxel(color: .init(1, 0, 0, 1))
        let ray = Ray(origin: Vector3(7, -1, -1),
                      direction: Vector3(1, 0, 0))

        model.update(x: 0, y: 0, z: 0, value: voxel)

        let hit = model.rayTest(ray)
        XCTAssertEqual(hit?.location.x, 0)
        XCTAssertEqual(hit?.location.y, 0)
        XCTAssertEqual(hit?.location.z, 0)
    }

    func testPackedVoxelOctreeUsesPreorderAdvance() {
        var model = VoxelModel(depth: 1)
        let left = Voxel(color: .init(1, 0, 0, 1))
        let right = Voxel(color: .init(0, 1, 0, 1))

        model.update(x: 0, y: 0, z: 0, value: left)
        model.update(x: 1, y: 0, z: 0, value: right)

        let packed = model.packedVoxelOctree(maxDepth: 1)

        XCTAssertEqual(packed.nodeCount, 3)
        XCTAssertEqual(packed.nodes[0].depth, 0)
        XCTAssertEqual(packed.nodes[0].advance, 3)
        XCTAssertEqual(packed.nodes[0].flags, 0)
        XCTAssertEqual(packed.nodes[1].depth, 1)
        XCTAssertEqual(packed.nodes[1].advance, 1)
        XCTAssertNotEqual(packed.nodes[1].flags, 0)
        XCTAssertEqual(packed.nodes[1].color, left.packedColor)
        XCTAssertEqual(packed.nodes[2].depth, 1)
        XCTAssertEqual(packed.nodes[2].advance, 1)
        XCTAssertNotEqual(packed.nodes[2].flags, 0)
        XCTAssertEqual(packed.nodes[2].color, right.packedColor)
    }

    func testPackedVoxelOctreePartialUsesNormalizedPosition() {
        var model = VoxelModel(depth: 1)
        let left = Voxel(color: .init(1, 0, 0, 1))
        let right = Voxel(color: .init(0, 1, 0, 1))

        model.update(x: 0, y: 0, z: 0, value: left)
        model.update(x: 1, y: 0, z: 0, value: right)

        let packed = model.packedVoxelOctree(normalizedPosition: Vector3(0.75, 0.25, 0.25),
                                             level: 1,
                                             maxDepth: 1)

        XCTAssertEqual(packed.nodeCount, 1)
        XCTAssertEqual(packed.nodes[0].depth, 1)
        XCTAssertEqual(packed.nodes[0].advance, 1)
        XCTAssertNotEqual(packed.nodes[0].flags, 0)
        XCTAssertEqual(packed.nodes[0].color, right.packedColor)
    }

    func testPackedVoxelOctreeChunksSplitLevel() {
        var model = VoxelModel(depth: 1)
        let left = Voxel(color: .init(1, 0, 0, 1))
        let right = Voxel(color: .init(0, 1, 0, 1))

        model.update(x: 0, y: 0, z: 0, value: left)
        model.update(x: 1, y: 0, z: 0, value: right)

        let chunks = model.packedVoxelOctreeChunks(splitLevel: 1, maxDepth: 1)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].level, 1)
        XCTAssertEqual(chunks[0].bounds.center, Vector3(0.25, 0.25, 0.25))
        XCTAssertEqual(chunks[0].octree.nodeCount, 1)
        XCTAssertEqual(chunks[0].octree.nodes[0].color, left.packedColor)
        XCTAssertEqual(chunks[1].level, 1)
        XCTAssertEqual(chunks[1].bounds.center, Vector3(0.75, 0.25, 0.25))
        XCTAssertEqual(chunks[1].octree.nodeCount, 1)
        XCTAssertEqual(chunks[1].octree.nodes[0].color, right.packedColor)
    }
}
