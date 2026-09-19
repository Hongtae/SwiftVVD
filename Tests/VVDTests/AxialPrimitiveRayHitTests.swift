//
//  File: AxialPrimitiveRayHitTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class AxialPrimitiveRayHitTests: XCTestCase {
    func testCapsuleReportsSideAndInsideExitHits() throws {
        let capsule = Capsule(radius: 1, height: 2)

        let side = try XCTUnwrap(capsule.rayTest(
            Ray(origin: Vector3(-3, 0, 0), direction: Vector3(2, 0, 0))))
        XCTAssertEqual(side.parameter, 1, accuracy: 1.0e-9)
        XCTAssertEqual(side.position, Vector3(-1, 0, 0))
        XCTAssertEqual(side.normal, Vector3(-1, 0, 0))

        let exit = try XCTUnwrap(capsule.rayTest(
            Ray(origin: .zero, direction: Vector3(0, 2, 0))))
        XCTAssertEqual(exit.parameter, 1, accuracy: 1.0e-9)
        XCTAssertEqual(exit.position, Vector3(0, 2, 0))
        XCTAssertEqual(exit.normal, Vector3(0, 1, 0))
    }

    func testCapsuleReportsHemisphereHit() throws {
        let capsule = Capsule(radius: 1, height: 2)
        let hit = try XCTUnwrap(capsule.rayTest(
            Ray(origin: Vector3(0, 3, 0), direction: Vector3(0, -2, 0))))

        XCTAssertEqual(hit.parameter, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position, Vector3(0, 2, 0))
        XCTAssertEqual(hit.normal, Vector3(0, 1, 0))
    }

    func testCylinderReportsSideAndCapHits() throws {
        let cylinder = Cylinder(radius: 1, height: 2)

        let side = try XCTUnwrap(cylinder.rayTest(
            Ray(origin: Vector3(-3, 0, 0), direction: Vector3(2, 0, 0))))
        XCTAssertEqual(side.parameter, 1, accuracy: 1.0e-9)
        XCTAssertEqual(side.position, Vector3(-1, 0, 0))
        XCTAssertEqual(side.normal, Vector3(-1, 0, 0))

        let cap = try XCTUnwrap(cylinder.rayTest(
            Ray(origin: Vector3(0, 2, 0), direction: Vector3(0, -2, 0))))
        XCTAssertEqual(cap.parameter, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(cap.position, Vector3(0, 1, 0))
        XCTAssertEqual(cap.normal, Vector3(0, 1, 0))
    }

    func testCylinderHitFromInsideReturnsExitCap() throws {
        let cylinder = Cylinder(radius: 1, height: 2)
        let hit = try XCTUnwrap(cylinder.rayTest(
            Ray(origin: .zero, direction: Vector3(0, 4, 0))))

        XCTAssertEqual(hit.parameter, 0.25, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position, Vector3(0, 1, 0))
        XCTAssertEqual(hit.normal, Vector3(0, 1, 0))
    }

    func testConeReportsSideAndBaseHits() throws {
        let cone = Cone(radius: 2, height: 4)

        let side = try XCTUnwrap(cone.rayTest(
            Ray(origin: Vector3(-3, 0, 0), direction: Vector3(2, 0, 0))))
        XCTAssertEqual(side.parameter, 1, accuracy: 1.0e-9)
        XCTAssertEqual(side.position, Vector3(-1, 0, 0))
        XCTAssertEqual(side.normal.x, -0.8944271909999159, accuracy: 1.0e-9)
        XCTAssertEqual(side.normal.y, 0.4472135954999579, accuracy: 1.0e-9)
        XCTAssertEqual(side.normal.z, 0, accuracy: 1.0e-9)

        let base = try XCTUnwrap(cone.rayTest(
            Ray(origin: Vector3(0, -3, 0), direction: Vector3(0, 2, 0))))
        XCTAssertEqual(base.parameter, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(base.position, Vector3(0, -2, 0))
        XCTAssertEqual(base.normal, Vector3(0, -1, 0))

        let exit = try XCTUnwrap(cone.rayTest(
            Ray(origin: .zero, direction: Vector3(0, -2, 0))))
        XCTAssertEqual(exit.parameter, 1, accuracy: 1.0e-9)
        XCTAssertEqual(exit.position, Vector3(0, -2, 0))
        XCTAssertEqual(exit.normal, Vector3(0, -1, 0))
    }

    func testAxialPrimitivesRejectMissesAndInvalidRays() {
        let miss = Ray(origin: Vector3(-3, 3, 0), direction: Vector3(1, 0, 0))
        let coneMiss = Ray(origin: Vector3(-3, 0, 3),
                           direction: Vector3(1, 0, 0))
        let invalid = Ray(origin: .zero, direction: .zero)

        XCTAssertNil(Capsule(radius: 1, height: 2).rayTest(miss))
        XCTAssertNil(Cylinder(radius: 1, height: 2).rayTest(miss))
        XCTAssertNil(Cone(radius: 1, height: 2).rayTest(miss))
        XCTAssertNil(Cone(radius: 2, height: 4).rayTest(coneMiss))
        XCTAssertNil(Capsule(radius: 1, height: 2).rayTest(invalid))
        XCTAssertNil(Cylinder(radius: 1, height: 2).rayTest(invalid))
        XCTAssertNil(Cone(radius: 1, height: 2).rayTest(invalid))
    }

    func testZeroRadiusConeUsesAxisSegmentAndZeroHeightIsInvalid() throws {
        let cone = Cone(radius: 0, height: 2)
        let hit = try XCTUnwrap(cone.rayTest(
            Ray(origin: Vector3(0, 2, 0), direction: Vector3(0, -2, 0))))

        XCTAssertEqual(hit.parameter, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position, Vector3(0, 1, 0))
        XCTAssertEqual(hit.normal, Vector3(0, 1, 0))
        XCTAssertFalse(Cone(radius: 1, height: 0).isValid)
    }
}
