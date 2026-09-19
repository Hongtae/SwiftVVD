//
//  File: CollisionSpaceRaycastTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class CollisionSpaceRaycastTests: XCTestCase {
    func testRaycastReturnsClosestHitAndRaycastAllUsesDistanceOrder() throws {
        let far = sphereCollider(position: Vector3(6, 0, 0))
        let near = sphereCollider(position: Vector3(2, 0, 0))
        let middle = sphereCollider(position: Vector3(4, 0, 0))
        let space = CollisionSpace(colliders: [far, near, middle])
        let ray = Ray(origin: .zero, direction: Vector3(2, 0, 0))

        let closest = try XCTUnwrap(space.raycast(ray))
        XCTAssertTrue(closest.collider === near)
        XCTAssertEqual(closest.distance, 1.5, accuracy: 1.0e-9)
        XCTAssertEqual(closest.position, Vector3(1.5, 0, 0))
        XCTAssertEqual(closest.normal, Vector3(-1, 0, 0))

        let hits = space.raycastAll(ray)
        XCTAssertEqual(hits.count, 3)
        XCTAssertTrue(hits[0].collider === near)
        XCTAssertTrue(hits[1].collider === middle)
        XCTAssertTrue(hits[2].collider === far)
        XCTAssertEqual(hits.map(\.distance), [1.5, 3.5, 5.5])
    }

    func testRaycastTransformsUnboundedPrimitiveGeometryIntoSpace() throws {
        let plane = Collider(
            primitive: StaticPlane(Plane(normal: Vector3(1, 0, 0),
                                         point: .zero)),
            transform: Transform(
                orientation: Quaternion(angle: Scalar.pi * 0.5,
                                        axis: Vector3(0, 0, 1)),
                position: Vector3(0, 2, 0)))
        let space = CollisionSpace(colliders: [plane])
        let ray = Ray(origin: .zero, direction: Vector3(0, 2, 0))

        let hit = try XCTUnwrap(space.raycast(ray))

        XCTAssertTrue(hit.collider === plane)
        XCTAssertEqual(hit.distance, 2, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position.y, 2, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position.z, 0, accuracy: 1.0e-9)
        XCTAssertEqual(hit.normal.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(hit.normal.y, 1, accuracy: 1.0e-9)
        XCTAssertEqual(hit.normal.z, 0, accuracy: 1.0e-9)
    }

    func testRaycastAppliesMutualQueryFilter() {
        let groupA = CollisionGroup.bit(1)
        let groupB = CollisionGroup.bit(2)
        let queryGroup = CollisionGroup.bit(3)
        let first = sphereCollider(
            position: Vector3(2, 0, 0),
            filter: CollisionFilter(group: groupA, mask: .all))
        let second = sphereCollider(
            position: Vector3(4, 0, 0),
            filter: CollisionFilter(group: groupB, mask: .all))
        let rejectsQueryGroup = sphereCollider(
            position: Vector3(3, 0, 0),
            filter: CollisionFilter(group: groupB, mask: .none))
        let space = CollisionSpace(colliders: [first, second, rejectsQueryGroup])
        let queryFilter = CollisionFilter(group: queryGroup,
                                          mask: CollisionMask(groupB))

        let hits = space.raycastAll(
            Ray(origin: .zero, direction: Vector3(1, 0, 0)),
            filter: queryFilter)

        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].collider === second)
    }

    func testRaycastHonorsMaximumDistanceAndInvalidInputs() {
        let collider = sphereCollider(position: Vector3(4, 0, 0))
        let space = CollisionSpace(colliders: [collider])
        let ray = Ray(origin: .zero, direction: Vector3(2, 0, 0))

        XCTAssertNil(space.raycast(ray, maximumDistance: 3))
        XCTAssertTrue(space.raycastAll(ray, maximumDistance: 3).isEmpty)
        XCTAssertNotNil(space.raycast(ray, maximumDistance: 3.5))
        XCTAssertNil(space.raycast(Ray(origin: .zero, direction: .zero)))
        XCTAssertTrue(space.raycastAll(ray, maximumDistance: -1).isEmpty)
    }

    func testEqualDistanceHitsPreserveColliderStorageOrder() {
        let upper = sphereCollider(position: Vector3(2, 0.5, 0))
        let lower = sphereCollider(position: Vector3(2, -0.5, 0))
        let space = CollisionSpace(colliders: [upper, lower])

        let hits = space.raycastAll(
            Ray(origin: .zero, direction: Vector3(1, 0, 0)))

        XCTAssertEqual(hits.count, 2)
        XCTAssertTrue(space.raycast(
            Ray(origin: .zero, direction: Vector3(1, 0, 0)))?.collider === upper)
        XCTAssertTrue(hits[0].collider === upper)
        XCTAssertTrue(hits[1].collider === lower)
        XCTAssertEqual(hits[0].distance, hits[1].distance, accuracy: 1.0e-9)
    }

    private func sphereCollider(
        position: Vector3,
        filter: CollisionFilter = CollisionFilter()
    ) -> Collider {
        Collider(primitive: Sphere(center: .zero, radius: 0.5),
                 transform: Transform(position: position),
                 filter: filter)
    }
}
