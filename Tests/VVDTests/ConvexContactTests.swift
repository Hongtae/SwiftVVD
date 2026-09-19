//
//  File: ConvexContactTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class ConvexContactTests: XCTestCase {
    func testBoxCapsuleContactReportsPenetrationWitnesses() throws {
        let manifold = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            Box(halfExtents: Vector3(1, 1, 1)),
            Capsule(radius: 0.5, height: 1),
            frame: Transform(position: Vector3(1.2, 0, 0))))
        let contact = try XCTUnwrap(manifold.contacts.first)

        XCTAssertEqual(contact.normal.x, 1, accuracy: 1.0e-6)
        XCTAssertEqual(contact.normal.y, 0, accuracy: 1.0e-6)
        XCTAssertEqual(contact.normal.z, 0, accuracy: 1.0e-6)
        XCTAssertEqual(contact.penetrationDepth, 0.3, accuracy: 1.0e-6)
        XCTAssertEqual(contact.pointOnA.x - contact.pointOnB.x,
                       contact.penetrationDepth,
                       accuracy: 1.0e-6)
    }

    func testSphereCylinderContactAndReversedGeometry() throws {
        let sphere = Sphere(center: .zero, radius: 0.75)
        let cylinder = Cylinder(radius: 0.5, height: 2)
        let frame = Transform(position: Vector3(1, 0, 0))

        let forward = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            sphere, cylinder, frame: frame)?.contacts.first)
        let reverse = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            cylinder, sphere, frame: frame.inverted())?.contacts.first)

        XCTAssertEqual(forward.penetrationDepth, 0.25, accuracy: 1.0e-6)
        XCTAssertEqual(forward.normal.x, 1, accuracy: 1.0e-6)
        XCTAssertEqual(reverse.penetrationDepth,
                       forward.penetrationDepth,
                       accuracy: 1.0e-6)
        XCTAssertEqual(reverse.normal.x, -1, accuracy: 1.0e-6)
        XCTAssertEqual(reverse.pointOnA.applying(frame),
                       forward.pointOnB)
        XCTAssertEqual(reverse.pointOnB.applying(frame),
                       forward.pointOnA)
    }

    func testHullContactUsesVertexCloudSupport() throws {
        let hull = cubeHull(halfExtent: 0.5)

        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            hull,
            hull,
            frame: Transform(position: Vector3(0.75, 0, 0)))?
            .contacts.first)

        XCTAssertEqual(contact.normal.x, 1, accuracy: 1.0e-6)
        XCTAssertEqual(contact.penetrationDepth, 0.25, accuracy: 1.0e-6)
        XCTAssertEqual(contact.pointOnA.x, 0.5, accuracy: 1.0e-6)
        XCTAssertEqual(contact.pointOnB.x, 0.25, accuracy: 1.0e-6)
    }

    func testConvexContactRejectsSeparatedPair() {
        XCTAssertNil(CollisionAlgorithms.contactManifold(
            Cylinder(radius: 0.5, height: 1),
            Cone(radius: 0.5, height: 1),
            frame: Transform(position: Vector3(3, 0, 0))))
    }

    func testCapsulePlaneContactUsesSupportProjection() throws {
        let plane = StaticPlane(Plane(normal: Vector3(1, 0, 0),
                                      point: .zero))
        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            Capsule(radius: 0.5, height: 1),
            plane,
            frame: Transform(position: Vector3(0.25, 0, 0)))?
            .contacts.first)

        XCTAssertEqual(contact.normal, Vector3(1, 0, 0))
        XCTAssertEqual(contact.penetrationDepth, 0.25, accuracy: 1.0e-9)
        XCTAssertEqual(contact.pointOnA.x, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(contact.pointOnB.x, 0.25, accuracy: 1.0e-9)
    }

    func testConePlaneContactSupportsReversedOrder() throws {
        let cone = Cone(radius: 1, height: 2)
        let plane = StaticPlane(Plane(normal: Vector3(0, 1, 0),
                                      point: .zero))
        let frame = Transform(position: Vector3(0, 0.5, 0))

        let forward = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            cone, plane, frame: frame)?.contacts.first)
        let reverse = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            plane, cone, frame: frame.inverted())?.contacts.first)

        XCTAssertEqual(forward.penetrationDepth, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(forward.normal, Vector3(0, 1, 0))
        XCTAssertEqual(reverse.normal, Vector3(0, -1, 0))
        XCTAssertEqual(reverse.penetrationDepth,
                       forward.penetrationDepth,
                       accuracy: 1.0e-9)
    }

    func testBuiltinRegistryProducesContactForEveryConvexPair() {
        let primitives: [(String, any CollisionPrimitive)] = [
            ("box", Box(halfExtents: Vector3(1, 1, 1))),
            ("sphere", Sphere(center: .zero, radius: 1)),
            ("capsule", Capsule(radius: 1, height: 1)),
            ("cylinder", Cylinder(radius: 1, height: 2)),
            ("cone", Cone(radius: 1, height: 2)),
            ("hull", cubeHull(halfExtent: 1)),
        ]
        let frame = Transform(
            orientation: Quaternion(angle: 0.2,
                                    axis: Vector3(0, 0, 1)),
            position: Vector3(0.2, 0.1, -0.1))

        for indexA in primitives.indices {
            for indexB in indexA..<primitives.count {
                let a = primitives[indexA]
                let b = primitives[indexB]
                let message = "\(a.0)-\(b.0)"
                XCTAssertTrue(CollisionAlgorithms.intersects(
                    a.1, b.1, frame: frame), message)
                guard let manifold = CollisionAlgorithms.contactManifold(
                    a.1, b.1, frame: frame) else {
                    XCTFail("missing contact: \(message)")
                    continue
                }
                XCTAssertFalse(manifold.isEmpty, message)
                for contact in manifold.contacts {
                    XCTAssertGreaterThanOrEqual(contact.penetrationDepth,
                                                .zero,
                                                message)
                    XCTAssertEqual(contact.normal.length,
                                   1,
                                   accuracy: 1.0e-6,
                                   message)
                }
            }
        }
    }

    func testBuiltinRegistryProducesContactForEveryConvexPlanePair() {
        let primitives: [(String, any CollisionPrimitive)] = [
            ("box", Box(halfExtents: Vector3(1, 1, 1))),
            ("sphere", Sphere(center: .zero, radius: 1)),
            ("capsule", Capsule(radius: 1, height: 1)),
            ("cylinder", Cylinder(radius: 1, height: 2)),
            ("cone", Cone(radius: 1, height: 2)),
            ("hull", cubeHull(halfExtent: 1)),
        ]
        let plane = StaticPlane(Plane(normal: Vector3(1, 0, 0),
                                      point: .zero))
        let frame = Transform(position: Vector3(0.25, 0, 0))

        for primitive in primitives {
            let contact = CollisionAlgorithms.contactManifold(
                primitive.1, plane, frame: frame)?.contacts.first
            XCTAssertNotNil(contact, primitive.0)
            XCTAssertGreaterThanOrEqual(contact?.penetrationDepth ?? -1,
                                        .zero,
                                        primitive.0)
        }
    }

    func testGenericContactIncludesTouchingPair() throws {
        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            Cylinder(radius: 1, height: 2),
            Cylinder(radius: 1, height: 2),
            frame: Transform(position: Vector3(2, 0, 0)))?
            .contacts.first)

        XCTAssertEqual(contact.penetrationDepth, .zero, accuracy: 1.0e-7)
        XCTAssertEqual(contact.pointOnA.x, 1, accuracy: 1.0e-7)
        XCTAssertEqual(contact.pointOnB.x, 1, accuracy: 1.0e-7)
        XCTAssertEqual(contact.normal.x, 1, accuracy: 1.0e-7)
    }

    private func cubeHull(halfExtent h: Scalar) -> ConvexHull {
        ConvexHull(vertices: [
            Vector3(-h, -h, -h), Vector3(h, -h, -h),
            Vector3(-h, h, -h), Vector3(h, h, -h),
            Vector3(-h, -h, h), Vector3(h, -h, h),
            Vector3(-h, h, h), Vector3(h, h, h),
        ])
    }
}
