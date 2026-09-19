//
//  File: CollisionSpaceSweepTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class CollisionSpaceSweepTests: XCTestCase {
    func testSphereSweepReturnsClosestAndTimeOrderedHits() throws {
        let far = sphereCollider(position: Vector3(6, 0, 0))
        let near = sphereCollider(position: Vector3(2, 0, 0))
        let middle = sphereCollider(position: Vector3(4, 0, 0))
        let space = CollisionSpace(colliders: [far, near, middle])
        let moving = Sphere(center: .zero, radius: 0.5)

        let closest = try XCTUnwrap(space.sweep(
            moving,
            translation: Vector3(8, 0, 0)))
        XCTAssertTrue(closest.collider === near)
        XCTAssertEqual(closest.fraction, 0.125, accuracy: 1.0e-9)
        XCTAssertEqual(closest.distance, 1, accuracy: 1.0e-9)
        XCTAssertEqual(closest.pointOnMoving, Vector3(1.5, 0, 0))
        XCTAssertEqual(closest.pointOnCollider, Vector3(1.5, 0, 0))
        XCTAssertEqual(closest.normal, Vector3(1, 0, 0))

        let hits = space.sweepAll(moving,
                                  translation: Vector3(8, 0, 0))
        XCTAssertEqual(hits.count, 3)
        XCTAssertTrue(hits[0].collider === near)
        XCTAssertTrue(hits[1].collider === middle)
        XCTAssertTrue(hits[2].collider === far)
        XCTAssertEqual(hits.map(\.fraction), [0.125, 0.375, 0.625])
    }

    func testSphereSweepHitsUnboundedPlane() throws {
        let plane = Collider(
            primitive: StaticPlane(Plane(normal: Vector3(1, 0, 0),
                                         point: .zero)),
            transform: Transform(position: Vector3(2, 0, 0)))
        let space = CollisionSpace(colliders: [plane])

        let hit = try XCTUnwrap(space.sweep(
            Sphere(center: .zero, radius: 0.5),
            translation: Vector3(4, 0, 0)))

        XCTAssertTrue(hit.collider === plane)
        XCTAssertEqual(hit.fraction, 0.375, accuracy: 1.0e-9)
        XCTAssertEqual(hit.distance, 1.5, accuracy: 1.0e-9)
        XCTAssertEqual(hit.pointOnMoving, Vector3(2, 0, 0))
        XCTAssertEqual(hit.pointOnCollider, Vector3(2, 0, 0))
        XCTAssertEqual(hit.normal, Vector3(1, 0, 0))
    }

    func testInitialOverlapReturnsZeroForZeroTranslation() throws {
        let target = sphereCollider(position: Vector3(0.75, 0, 0))
        let space = CollisionSpace(colliders: [target])

        let hit = try XCTUnwrap(space.sweep(
            Sphere(center: .zero, radius: 0.5),
            translation: .zero))

        XCTAssertEqual(hit.fraction, .zero)
        XCTAssertEqual(hit.distance, .zero)
        XCTAssertEqual(hit.normal, Vector3(1, 0, 0))
    }

    func testSweepAppliesMutualFilterAndRejectsInvalidInput() {
        let groupA = CollisionGroup.bit(1)
        let groupB = CollisionGroup.bit(2)
        let queryGroup = CollisionGroup.bit(3)
        let first = sphereCollider(
            position: Vector3(2, 0, 0),
            filter: CollisionFilter(group: groupA, mask: .all))
        let second = sphereCollider(
            position: Vector3(4, 0, 0),
            filter: CollisionFilter(group: groupB, mask: .all))
        let rejectsQuery = sphereCollider(
            position: Vector3(3, 0, 0),
            filter: CollisionFilter(group: groupB, mask: .none))
        let space = CollisionSpace(colliders: [first, second, rejectsQuery])
        let queryFilter = CollisionFilter(group: queryGroup,
                                          mask: CollisionMask(groupB))

        let hits = space.sweepAll(
            Sphere(center: .zero, radius: 0.5),
            translation: Vector3(6, 0, 0),
            filter: queryFilter)

        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].collider === second)
        XCTAssertTrue(space.sweepAll(
            Sphere(),
            translation: Vector3(1, 0, 0)).isEmpty)
        XCTAssertTrue(space.sweepAll(
            Sphere(center: .zero, radius: 0.5),
            translation: Vector3(Scalar.nan, 0, 0)).isEmpty)
    }

    func testColliderSweepExcludesItselfWithoutMutatingTransform() throws {
        let moving = sphereCollider(position: .zero)
        let target = sphereCollider(position: Vector3(3, 0, 0))
        let startTransform = moving.transform
        let space = CollisionSpace(colliders: [moving, target])

        let hit = try XCTUnwrap(space.sweep(
            moving,
            translation: Vector3(4, 0, 0)))

        XCTAssertTrue(hit.collider === target)
        XCTAssertEqual(hit.fraction, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(moving.transform, startTransform)
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
