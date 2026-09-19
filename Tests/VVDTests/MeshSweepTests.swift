//
//  File: MeshSweepTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class MeshSweepTests: XCTestCase {
    private let wall = Triangle(
        Vector3(3, -2, -2),
        Vector3(3, 2, -2),
        Vector3(3, 0, 2))

    func testConvexMeshSweepUsesTriangleCandidates() throws {
        let mesh = TriangleMesh(triangles: [
            Triangle(Vector3(3, 50, -2),
                     Vector3(3, 54, -2),
                     Vector3(3, 52, 2)),
            wall,
        ])

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            Sphere(center: .zero, radius: 0.5),
            mesh,
            translation: Vector3(4, 0, 0)))

        XCTAssertEqual(impact.fraction, 0.625, accuracy: 1.0e-7)
        XCTAssertEqual(impact.pointOnA.x, 3, accuracy: 1.0e-7)
        XCTAssertEqual(impact.pointOnB.x, 3, accuracy: 1.0e-7)
        XCTAssertEqual(impact.normal.x, 1, accuracy: 1.0e-7)
    }

    func testReversedMeshSweepTransformsMotionAndGeometry() throws {
        let mesh = TriangleMesh(triangles: [
            Triangle(Vector3(0, -2, -2),
                     Vector3(0, 2, -2),
                     Vector3(0, 0, 2)),
        ])

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            mesh,
            Sphere(center: .zero, radius: 0.5),
            frame: Transform(position: Vector3(3, 0, 0)),
            translation: Vector3(4, 0, 0)))

        XCTAssertEqual(impact.fraction, 0.625, accuracy: 1.0e-7)
        XCTAssertEqual(impact.pointOnA.x, 2.5, accuracy: 1.0e-7)
        XCTAssertEqual(impact.pointOnB.x, 2.5, accuracy: 1.0e-7)
        XCTAssertEqual(impact.normal.x, 1, accuracy: 1.0e-7)
    }

    func testMeshMeshSweepPrunesBothTriangleSets() throws {
        let moving = TriangleMesh(triangles: [
            Triangle(Vector3(0, 40, -1),
                     Vector3(0, 42, -1),
                     Vector3(0, 41, 1)),
            Triangle(Vector3(0, -1, -1),
                     Vector3(0, 1, -1),
                     Vector3(0, 0, 1)),
        ])
        let stationary = TriangleMesh(triangles: [
            Triangle(Vector3(3, -1, -1),
                     Vector3(3, 1, -1),
                     Vector3(3, 0, 1)),
            Triangle(Vector3(3, -42, -1),
                     Vector3(3, -40, -1),
                     Vector3(3, -41, 1)),
        ])

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            moving,
            stationary,
            translation: Vector3(4, 0, 0)))

        XCTAssertEqual(impact.fraction, 0.75, accuracy: 1.0e-7)
        XCTAssertEqual(impact.pointOnA.x, 3, accuracy: 1.0e-7)
        XCTAssertEqual(impact.pointOnB.x, 3, accuracy: 1.0e-7)
        XCTAssertEqual(impact.normal.x, 1, accuracy: 1.0e-7)
    }

    func testMeshPlaneSweepUsesEarliestTriangle() throws {
        let mesh = TriangleMesh(triangles: [
            Triangle(Vector3(-1, -1, -1),
                     Vector3(-1, 1, -1),
                     Vector3(-1, 0, 1)),
            Triangle(Vector3(0, -1, -1),
                     Vector3(0, 1, -1),
                     Vector3(0, 0, 1)),
        ])
        let plane = StaticPlane(Plane(normal: Vector3(1, 0, 0), point: .zero))

        let impact = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            mesh,
            plane,
            frame: Transform(position: Vector3(3, 0, 0)),
            translation: Vector3(4, 0, 0)))

        XCTAssertEqual(impact.fraction, 0.75, accuracy: 1.0e-9)
        XCTAssertEqual(impact.pointOnA.x, 3, accuracy: 1.0e-9)
        XCTAssertEqual(impact.pointOnB.x, 3, accuracy: 1.0e-9)
        XCTAssertEqual(impact.normal.x, 1, accuracy: 1.0e-9)
    }

    func testMeshSweepReportsInitialOverlapAndMiss() throws {
        let mesh = TriangleMesh(triangles: [wall])
        let overlapping = try XCTUnwrap(CollisionAlgorithms.timeOfImpact(
            Box(halfExtents: Vector3(0.5, 0.5, 0.5)),
            mesh,
            frame: Transform(position: Vector3(-2.75, 0, 0)),
            translation: .zero))

        XCTAssertEqual(overlapping.fraction, .zero)
        XCTAssertNil(CollisionAlgorithms.timeOfImpact(
            Sphere(center: .zero, radius: 0.5),
            mesh,
            translation: Vector3(-4, 0, 0)))
    }
}
