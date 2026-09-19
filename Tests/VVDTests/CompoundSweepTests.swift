//
//  File: CompoundSweepTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class CompoundSweepTests: XCTestCase {
    func testMovingCompoundUsesChildTransform() throws {
        let compound = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 0.5),
                  transform: Transform(position: Vector3(1, 0, 0))),
        ])

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            compound,
            Sphere(center: .zero, radius: 0.5),
            frame: Transform(position: Vector3(4, 0, 0)),
            translation: Vector3(4, 0, 0)))

        XCTAssertEqual(impact.fraction, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(impact.pointOnA, Vector3(3.5, 0, 0))
        XCTAssertEqual(impact.pointOnB, Vector3(3.5, 0, 0))
        XCTAssertEqual(impact.normal, Vector3(1, 0, 0))
    }

    func testStationaryCompoundUsesChildTransform() throws {
        let compound = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 0.5),
                  transform: Transform(position: Vector3(2, 0, 0))),
        ])

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            Sphere(center: .zero, radius: 0.5),
            compound,
            frame: Transform(position: Vector3(2, 0, 0)),
            translation: Vector3(5, 0, 0)))

        XCTAssertEqual(impact.fraction, 0.6, accuracy: 1.0e-9)
        XCTAssertEqual(impact.pointOnA, Vector3(3.5, 0, 0))
        XCTAssertEqual(impact.pointOnB, Vector3(3.5, 0, 0))
        XCTAssertEqual(impact.normal, Vector3(1, 0, 0))
    }

    func testNestedCompoundsChooseEarliestLeafPair() throws {
        let nested = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 0.5),
                  transform: Transform(position: Vector3(1, 0, 0))),
        ])
        let moving = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 0.5)),
            .init(nested, transform: Transform(position: Vector3(1, 0, 0))),
        ])
        let stationary = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 0.5),
                  transform: Transform(position: Vector3(5, 0, 0))),
        ])

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            moving,
            stationary,
            translation: Vector3(6, 0, 0)))

        XCTAssertEqual(impact.fraction, 1.0 / 3.0, accuracy: 1.0e-9)
        XCTAssertEqual(impact.pointOnA, Vector3(4.5, 0, 0))
        XCTAssertEqual(impact.pointOnB, Vector3(4.5, 0, 0))
    }

    func testCollisionSpaceSweepsCompoundWithoutMutatingIt() throws {
        let compound = CompoundPrimitive(children: [
            .init(Box(halfExtents: Vector3(0.5, 0.5, 0.5)),
                  transform: Transform(position: Vector3(1, 0, 0))),
        ])
        let collider = Collider(
            primitive: Sphere(center: .zero, radius: 0.5),
            transform: Transform(position: Vector3(4, 0, 0)))
        let space = CollisionSpace(colliders: [collider])

        let hit = try XCTUnwrap(space.sweep(
            compound,
            translation: Vector3(4, 0, 0)))

        XCTAssertEqual(hit.fraction, 0.5, accuracy: 1.0e-7)
        XCTAssertEqual(hit.pointOnMoving.x, 3.5, accuracy: 1.0e-7)
        XCTAssertEqual(compound.children[0].transform.position,
                       Vector3(1, 0, 0))
    }
}
