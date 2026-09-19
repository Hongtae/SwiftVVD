//
//  File: ConvexSweepTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class ConvexSweepTests: XCTestCase {
    func testBoxBoxSweepUsesGJKWitnesses() throws {
        let box = Box(halfExtents: Vector3(1, 1, 1))

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            box,
            box,
            frame: Transform(position: Vector3(5, 0, 0)),
            translation: Vector3(6, 0, 0)))

        XCTAssertEqual(impact.fraction, 0.5, accuracy: 1.0e-7)
        XCTAssertEqual(impact.pointOnA.x, 4, accuracy: 1.0e-7)
        XCTAssertEqual(impact.pointOnB.x, 4, accuracy: 1.0e-7)
        XCTAssertEqual(impact.normal.x, 1, accuracy: 1.0e-7)
        XCTAssertEqual(impact.normal.y, 0, accuracy: 1.0e-7)
        XCTAssertEqual(impact.normal.z, 0, accuracy: 1.0e-7)
    }

    func testRotatedBoxSweepUsesConservativeAdvancement() throws {
        let box = Box(halfExtents: Vector3(1, 1, 1))
        let rotation = Quaternion(angle: Scalar.pi * 0.25,
                                  axis: Vector3(0, 0, 1))

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            box,
            box,
            frame: Transform(orientation: rotation,
                             position: Vector3(5, 0, 0)),
            translation: Vector3(6, 0, 0)))
        let expected = (Scalar(5) - 1 - Scalar(2).squareRoot()) / 6

        XCTAssertEqual(impact.fraction, expected, accuracy: 1.0e-6)
        XCTAssertEqual(impact.normal.x, 1, accuracy: 1.0e-6)
    }

    func testBoxSweepDistinguishesGrazingFromParallelSeparation() throws {
        let box = Box(halfExtents: Vector3(1, 1, 1))
        let translation = Vector3(6, 0, 0)

        let grazing = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            box,
            box,
            frame: Transform(position: Vector3(5, 2, 0)),
            translation: translation))

        XCTAssertEqual(grazing.fraction, 0.5, accuracy: 1.0e-6)
        XCTAssertNil(CollisionAlgorithms.timeOfImpact(
            box,
            box,
            frame: Transform(position: Vector3(5, 2.01, 0)),
            translation: translation))
        XCTAssertNil(CollisionAlgorithms.timeOfImpact(
            box,
            box,
            frame: Transform(position: Vector3(5, 0, 0)),
            translation: Vector3(0, 6, 0)))
    }

    func testConvexPlaneSweepUsesSupportProjection() throws {
        let box = Box(halfExtents: Vector3(1, 2, 3))
        let plane = StaticPlane(Plane(normal: Vector3(1, 0, 0),
                                      point: .zero))

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            box,
            plane,
            frame: Transform(position: Vector3(5, 0, 0)),
            translation: Vector3(8, 0, 0)))

        XCTAssertEqual(impact.fraction, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(impact.pointOnA.x, 5, accuracy: 1.0e-9)
        XCTAssertEqual(impact.pointOnB.x, 5, accuracy: 1.0e-9)
        XCTAssertEqual(impact.normal, Vector3(1, 0, 0))
        XCTAssertNil(CollisionAlgorithms.timeOfImpact(
            box,
            plane,
            frame: Transform(position: Vector3(5, 0, 0)),
            translation: Vector3(-8, 0, 0)))
    }

    func testInitialConvexOverlapReturnsFractionZero() throws {
        let box = Box(halfExtents: Vector3(1, 1, 1))
        let capsule = Capsule(radius: 0.5, height: 1)

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            box,
            capsule,
            frame: Transform(position: Vector3(0.5, 0, 0)),
            translation: .zero))

        XCTAssertEqual(impact.fraction, .zero)
        XCTAssertTrue(impact.isValid)
    }

    func testCollisionSpaceSweepsBoxAgainstSphere() throws {
        let target = Collider(
            primitive: Sphere(center: .zero, radius: 0.5),
            transform: Transform(position: Vector3(3, 0, 0)))
        let space = CollisionSpace(colliders: [target])

        let hit = try XCTUnwrap(space.sweep(
            Box(halfExtents: Vector3(0.5, 0.5, 0.5)),
            translation: Vector3(4, 0, 0)))

        XCTAssertEqual(hit.fraction, 0.5, accuracy: 1.0e-7)
        XCTAssertEqual(hit.pointOnMoving.x, 2.5, accuracy: 1.0e-7)
        XCTAssertEqual(hit.pointOnCollider.x, 2.5, accuracy: 1.0e-7)
        XCTAssertEqual(hit.normal.x, 1, accuracy: 1.0e-7)
    }

    func testBuiltinRegistryCoversConvexAndPlaneSweepPairs() {
        let registry = CollisionAlgorithmRegistry()

        XCTAssertNotNil(registry.timeOfImpact(
            Capsule(radius: 0.5, height: 1),
            Cone(radius: 0.5, height: 1),
            frame: Transform(position: Vector3(3, 0, 0)),
            translation: Vector3(4, 0, 0)))
        XCTAssertNotNil(registry.timeOfImpact(
            Cylinder(radius: 0.5, height: 1),
            StaticPlane(Plane(normal: Vector3(1, 0, 0), point: .zero)),
            frame: Transform(position: Vector3(3, 0, 0)),
            translation: Vector3(4, 0, 0)))
        let hull = ConvexHull(vertices: [
            Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
            Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5),
            Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
            Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5),
        ])
        XCTAssertNotNil(registry.timeOfImpact(
            hull,
            hull,
            frame: Transform(position: Vector3(3, 0, 0)),
            translation: Vector3(4, 0, 0)))
        XCTAssertNotNil(registry.timeOfImpact(
            StaticPlane(Plane(normal: Vector3(1, 0, 0), point: .zero)),
            Cone(radius: 0.5, height: 1),
            frame: Transform(position: Vector3(3, 0, 0)),
            translation: Vector3(4, 0, 0)))
    }

    func testCapsuleSweepIncludesSphericalSupportAlongAxis() throws {
        let capsule = Capsule(radius: 0.5, height: 2)
        let sphere = Sphere(center: .zero, radius: 0.5)

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            capsule,
            sphere,
            frame: Transform(position: Vector3(0, 4, 0)),
            translation: Vector3(0, 4, 0)))

        XCTAssertEqual(impact.fraction, 0.5, accuracy: 1.0e-7)
        XCTAssertEqual(impact.pointOnA.y, 3.5, accuracy: 1.0e-7)
        XCTAssertEqual(impact.pointOnB.y, 3.5, accuracy: 1.0e-7)
        XCTAssertEqual(impact.normal, Vector3(0, 1, 0))
    }
}
