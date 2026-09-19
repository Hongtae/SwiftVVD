//
//  File: MeshContactTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class MeshContactTests: XCTestCase {
    func testConvexMeshContactUsesDeepestCandidateAndFeature() throws {
        let wall = Triangle(Vector3(0, -3, -3),
                            Vector3(0, 3, -3),
                            Vector3(0, 0, 3))
        let mesh = TriangleMesh(triangles: [
            Triangle(Vector3(0, 20, -3),
                     Vector3(0, 26, -3),
                     Vector3(0, 23, 3)),
            wall,
        ])

        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            Sphere(center: .zero, radius: 1),
            mesh,
            frame: Transform(position: Vector3(0.75, 0, 0)))?
            .contacts.first)

        XCTAssertEqual(contact.normal.x, 1, accuracy: 1.0e-6)
        XCTAssertEqual(contact.penetrationDepth, 0.25, accuracy: 1.0e-6)
        XCTAssertEqual(contact.pointOnA.x, 1, accuracy: 1.0e-6)
        XCTAssertEqual(contact.pointOnB.x, 0.75, accuracy: 1.0e-6)
        XCTAssertEqual(contact.featureID, ContactFeatureID(1))
    }

    func testReversedMeshContactTransformsGeometry() throws {
        let mesh = TriangleMesh(triangles: [
            Triangle(Vector3(0, -3, -3),
                     Vector3(0, 3, -3),
                     Vector3(0, 0, 3)),
        ])
        let frame = Transform(position: Vector3(-0.75, 0, 0))

        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            mesh,
            Sphere(center: .zero, radius: 1),
            frame: frame)?.contacts.first)

        XCTAssertEqual(contact.normal.x, -1, accuracy: 1.0e-6)
        XCTAssertEqual(contact.penetrationDepth, 0.25, accuracy: 1.0e-6)
        XCTAssertEqual(contact.pointOnA.x, 0, accuracy: 1.0e-6)
        XCTAssertEqual(contact.pointOnB.x, 0.25, accuracy: 1.0e-6)
    }

    func testMeshMeshContactReportsCrossingSegmentMidpoint() throws {
        let a = TriangleMesh(triangles: [
            Triangle(Vector3(-1, -1, 0),
                     Vector3(1, -1, 0),
                     Vector3(0, 1, 0)),
        ])
        let b = TriangleMesh(triangles: [
            Triangle(Vector3(0, -1, -1),
                     Vector3(0, 1, -1),
                     Vector3(0, 0, 1)),
        ])

        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            a, b)?.contacts.first)

        XCTAssertEqual(contact.penetrationDepth, .zero)
        XCTAssertEqual(contact.pointOnA, contact.pointOnB)
        XCTAssertEqual(contact.pointOnA.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(contact.pointOnA.z, 0, accuracy: 1.0e-9)
        XCTAssertEqual(contact.normal.length, 1, accuracy: 1.0e-9)
    }

    func testMeshMeshContactFindsCoplanarOverlapPoint() throws {
        let a = TriangleMesh(triangles: [
            Triangle(Vector3(-2, -1, 0),
                     Vector3(2, -1, 0),
                     Vector3(0, 2, 0)),
        ])
        let b = TriangleMesh(triangles: [
            Triangle(Vector3(-1, -2, 0),
                     Vector3(1, 2, 0),
                     Vector3(2, -2, 0)),
        ])

        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            a, b)?.contacts.first)

        XCTAssertEqual(contact.penetrationDepth, .zero)
        XCTAssertEqual(contact.pointOnA, contact.pointOnB)
        XCTAssertEqual(contact.pointOnA.z, 0, accuracy: 1.0e-9)
        XCTAssertNotNil(a.triangle(at: 0).barycentric(at: contact.pointOnA))
        XCTAssertNotNil(b.triangle(at: 0).barycentric(at: contact.pointOnB))
    }

    func testPlaneMeshContactUsesTrianglePlaneIntersection() throws {
        let plane = StaticPlane(Plane(normal: Vector3(1, 0, 0),
                                      point: .zero))
        let mesh = TriangleMesh(triangles: [
            Triangle(Vector3(-1, -1, 0),
                     Vector3(1, -1, 0),
                     Vector3(0, 1, 0)),
        ])

        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            plane, mesh)?.contacts.first)

        XCTAssertEqual(contact.penetrationDepth, .zero)
        XCTAssertEqual(contact.pointOnA, contact.pointOnB)
        XCTAssertEqual(contact.pointOnA.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(contact.normal, Vector3(1, 0, 0))
        XCTAssertNil(CollisionAlgorithms.contactManifold(
            plane,
            mesh,
            frame: Transform(position: Vector3(3, 0, 0))))
    }
}
