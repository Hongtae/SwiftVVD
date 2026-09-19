//
//  File: PrimitiveRayHitTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class PrimitiveRayHitTests: XCTestCase {
    func testSphereHitUsesRayParameterAndLocalSurfaceGeometry() throws {
        let sphere = Sphere(center: .zero, radius: 1)
        let ray = Ray(origin: Vector3(-3, 0, 0), direction: Vector3(2, 0, 0))

        let hit = try XCTUnwrap(sphere.rayTest(ray))

        XCTAssertEqual(hit.parameter, 1, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position, Vector3(-1, 0, 0))
        XCTAssertEqual(hit.normal, Vector3(-1, 0, 0))
        XCTAssertEqual(hit.position, ray.point(at: hit.parameter))
    }

    func testSphereHitFromInsideReturnsExitSurface() throws {
        let sphere = Sphere(center: .zero, radius: 1)
        let ray = Ray(origin: .zero, direction: Vector3(2, 0, 0))

        let hit = try XCTUnwrap(sphere.rayTest(ray))

        XCTAssertEqual(hit.parameter, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position, Vector3(1, 0, 0))
        XCTAssertEqual(hit.normal, Vector3(1, 0, 0))
    }

    func testBoxHitReportsEntryAndExitNormals() throws {
        let box = Box(halfExtents: Vector3(1, 2, 3))

        let entry = try XCTUnwrap(box.rayTest(
            Ray(origin: Vector3(-3, 0.5, 0), direction: Vector3(2, 0, 0))))
        XCTAssertEqual(entry.parameter, 1, accuracy: 1.0e-9)
        XCTAssertEqual(entry.position, Vector3(-1, 0.5, 0))
        XCTAssertEqual(entry.normal, Vector3(-1, 0, 0))

        let exit = try XCTUnwrap(box.rayTest(
            Ray(origin: .zero, direction: Vector3(0, 4, 0))))
        XCTAssertEqual(exit.parameter, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(exit.position, Vector3(0, 2, 0))
        XCTAssertEqual(exit.normal, Vector3(0, 1, 0))
    }

    func testStaticPlaneHitNormalIsNormalizedWithoutChangingParameter() throws {
        let plane = StaticPlane(Plane(normal: Vector3(2, 0, 0),
                                      point: Vector3(1, 0, 0)))
        let ray = Ray(origin: .zero, direction: Vector3(2, 0, 0))

        let hit = try XCTUnwrap(plane.rayTest(ray))

        XCTAssertEqual(hit.parameter, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position, Vector3(1, 0, 0))
        XCTAssertEqual(hit.normal, Vector3(1, 0, 0))
    }

    func testShapeForwardsStructuredPrimitiveHit() throws {
        let shape = SphereShape(Sphere(center: .zero, radius: 1))
        let ray = Ray(origin: Vector3(-2, 0, 0), direction: Vector3(1, 0, 0))

        let hit = try XCTUnwrap(shape.rayTest(ray))

        XCTAssertEqual(hit.parameter, 1, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position, Vector3(-1, 0, 0))
    }

    func testSupportedPrimitivesReturnNilWhenRayMisses() {
        let ray = Ray(origin: Vector3(-2, 2, 0), direction: Vector3(1, 0, 0))

        XCTAssertNil(Sphere(center: .zero, radius: 1).rayTest(ray))
        XCTAssertNil(Box(halfExtents: Vector3(1, 1, 1)).rayTest(ray))
        XCTAssertNil(StaticPlane(Plane(normal: Vector3(0, 1, 0),
                                      point: .zero)).rayTest(ray))
    }

    func testInvalidRayAndTopologylessHullReturnNoHit() {
        let invalidRay = Ray(origin: .zero, direction: .zero)
        XCTAssertNil(Sphere(center: .zero, radius: 1).rayTest(invalidRay))
        XCTAssertNil(Box(halfExtents: Vector3(1, 1, 1)).rayTest(invalidRay))
        XCTAssertNil(StaticPlane(Plane(normal: Vector3(0, 1, 0),
                                      point: .zero)).rayTest(invalidRay))

        let ray = Ray(origin: Vector3(-2, 0, 0), direction: Vector3(1, 0, 0))
        XCTAssertNil(ConvexHull(vertices: [Vector3(0, 0, 0),
                                           Vector3(1, 0, 0),
                                           Vector3(0, 1, 0)]).rayTest(ray))
    }
}
