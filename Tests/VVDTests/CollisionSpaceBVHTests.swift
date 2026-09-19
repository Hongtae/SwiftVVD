//
//  File: CollisionSpaceBVHTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class CollisionSpaceBVHTests: XCTestCase {
    func testOverlapAndPairResultsPreserveStorageOrder() {
        let first = sphereCollider(position: Vector3(4, 0, 0), radius: 10)
        let second = sphereCollider(position: Vector3(-4, 0, 0), radius: 10)
        let third = sphereCollider(position: .zero, radius: 10)
        let space = CollisionSpace(colliders: [first, second, third])
        let query = sphereCollider(position: .zero, radius: 20)

        let overlaps = space.overlaps(with: query)
        XCTAssertEqual(overlaps.count, 3)
        XCTAssertTrue(overlaps[0] === first)
        XCTAssertTrue(overlaps[1] === second)
        XCTAssertTrue(overlaps[2] === third)

        let pairs = space.collisionPairs()
        XCTAssertEqual(pairs.count, 3)
        XCTAssertTrue(pairs[0].colliderA === first)
        XCTAssertTrue(pairs[0].colliderB === second)
        XCTAssertTrue(pairs[1].colliderA === first)
        XCTAssertTrue(pairs[1].colliderB === third)
        XCTAssertTrue(pairs[2].colliderA === second)
        XCTAssertTrue(pairs[2].colliderB === third)
    }

    func testNullBoundsColliderRemainsBroadPhaseCandidate() throws {
        let farSphere = sphereCollider(position: Vector3(10, 0, 0), radius: 1)
        let plane = Collider(primitive: StaticPlane(
            Plane(normal: Vector3(1, 0, 0), point: .zero)))
        let nearSphere = sphereCollider(position: .zero, radius: 1)
        let space = CollisionSpace(colliders: [farSphere, plane, nearSphere])

        let pairs = space.collisionPairs()
        XCTAssertEqual(pairs.count, 1)
        let pair = try XCTUnwrap(pairs.first)
        XCTAssertTrue(pair.colliderA === plane)
        XCTAssertTrue(pair.colliderB === nearSphere)

        let planeOverlaps = space.overlaps(with: plane)
        XCTAssertEqual(planeOverlaps.count, 1)
        XCTAssertTrue(planeOverlaps[0] === nearSphere)

        let sphereOverlaps = space.overlaps(with: nearSphere)
        XCTAssertEqual(sphereOverlaps.count, 1)
        XCTAssertTrue(sphereOverlaps[0] === plane)
    }

    func testQuerySnapshotUsesCurrentColliderTransform() {
        let colliderA = sphereCollider(position: .zero, radius: 1)
        let colliderB = sphereCollider(position: Vector3(5, 0, 0), radius: 1)
        let space = CollisionSpace(colliders: [colliderA, colliderB])

        XCTAssertTrue(space.collisionPairs().isEmpty)

        colliderB.transform = Transform(position: Vector3(1.5, 0, 0))
        XCTAssertEqual(space.collisionPairs().count, 1)

        colliderB.transform = Transform(position: Vector3(5, 0, 0))
        XCTAssertTrue(space.collisionPairs().isEmpty)
    }

    private func sphereCollider(position: Vector3,
                                radius: Scalar) -> Collider {
        Collider(primitive: Sphere(center: .zero, radius: radius),
                 transform: Transform(position: position))
    }
}
