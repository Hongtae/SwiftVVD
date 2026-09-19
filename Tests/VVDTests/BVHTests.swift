//
//  File: BVHTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class BVHTests: XCTestCase {
    func testEmptyTreeAndNullElementsHaveNoCandidates() {
        let empty = BVH()
        let nullOnly = BVH([
            BVH.Element(bounds: .null, primitiveIndex: 7)
        ])

        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(empty.bounds.isNull)
        XCTAssertEqual(empty.elementCount, 0)
        XCTAssertEqual(empty.nodeCount, 0)

        XCTAssertTrue(nullOnly.isEmpty)
        XCTAssertTrue(nullOnly.bounds.isNull)
        XCTAssertEqual(nullOnly.elementCount, 0)
        XCTAssertEqual(nullOnly.nodeCount, 0)
        XCTAssertTrue(nullOnly.primitiveIndices(overlapping: unitBounds()).isEmpty)
    }

    func testBuildsBoundsAndReturnsOverlappingPrimitiveIndices() {
        let bvh = BVH([
            BVH.Element(bounds: bounds(minX: 0, maxX: 1),
                        primitiveIndex: 10),
            BVH.Element(bounds: bounds(minX: 2, maxX: 3),
                        primitiveIndex: 20),
            BVH.Element(bounds: bounds(minX: -3, maxX: -2),
                        primitiveIndex: 30),
            BVH.Element(bounds: .null,
                        primitiveIndex: 40)
        ])

        XCTAssertFalse(bvh.isEmpty)
        XCTAssertEqual(bvh.elementCount, 3)
        XCTAssertEqual(bvh.nodeCount, 5)
        XCTAssertEqual(bvh.bounds,
                       AABB(min: Vector3(-3, -1, -1),
                            max: Vector3(3, 1, 1)))

        let candidates = bvh.primitiveIndices(
            overlapping: bounds(minX: 0.5, maxX: 2.5))
        XCTAssertEqual(Set(candidates), Set([10, 20]))
        XCTAssertTrue(bvh.primitiveIndices(overlapping: .null).isEmpty)
    }

    func testQueryVisitorCanStopTraversal() {
        let bvh = BVH([
            BVH.Element(bounds: bounds(minX: -2, maxX: -1),
                        primitiveIndex: 1),
            BVH.Element(bounds: bounds(minX: 1, maxX: 2),
                        primitiveIndex: 2)
        ])
        var visited: [Int] = []

        let completed = bvh.query(
            overlapping: bounds(minX: -3, maxX: 3)) { primitiveIndex in
                visited.append(primitiveIndex)
                return false
            }

        XCTAssertFalse(completed)
        XCTAssertEqual(visited.count, 1)
    }

    func testQueriesMatchLinearAABBScan() {
        let elements = (0..<27).map { primitiveIndex in
            let x = Scalar(primitiveIndex % 3) * 3
            let y = Scalar((primitiveIndex / 3) % 3) * 3
            let z = Scalar(primitiveIndex / 9) * 3
            return BVH.Element(
                bounds: AABB(center: Vector3(x, y, z),
                             halfExtents: Vector3(0.75, 0.75, 0.75)),
                primitiveIndex: primitiveIndex)
        }
        let bvh = BVH(elements)
        let queries = [
            AABB(center: .zero,
                 halfExtents: Vector3(1, 1, 1)),
            AABB(center: Vector3(3, 3, 3),
                 halfExtents: Vector3(2, 2, 2)),
            AABB(center: Vector3(4.5, 1.5, 4.5),
                 halfExtents: Vector3(2, 2, 2)),
            AABB(center: Vector3(20, 20, 20),
                 halfExtents: Vector3(1, 1, 1))
        ]

        for query in queries {
            let expected = Set(elements.compactMap { element in
                element.bounds.intersects(query) ? element.primitiveIndex : nil
            })
            let result = Set(bvh.primitiveIndices(overlapping: query))
            XCTAssertEqual(result, expected)
        }
    }

    private func bounds(minX: Scalar, maxX: Scalar) -> AABB {
        AABB(min: Vector3(minX, -1, -1),
             max: Vector3(maxX, 1, 1))
    }

    private func unitBounds() -> AABB {
        bounds(minX: -1, maxX: 1)
    }
}
