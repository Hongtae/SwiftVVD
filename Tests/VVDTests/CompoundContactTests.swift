//
//  File: CompoundContactTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class CompoundContactTests: XCTestCase {
    func testPrimitiveCompoundContactUsesOverlappingLeaf() throws {
        let compound = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 0.5),
                  transform: Transform(position: Vector3(0.75, 0, 0))),
            .init(Sphere(center: .zero, radius: 0.5),
                  transform: Transform(position: Vector3(5, 0, 0))),
        ])

        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            Sphere(center: .zero, radius: 0.5),
            compound)?.contacts.first)

        XCTAssertEqual(contact.penetrationDepth, 0.25, accuracy: 1.0e-9)
        XCTAssertEqual(contact.pointOnA.x, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(contact.pointOnB.x, 0.25, accuracy: 1.0e-9)
        XCTAssertEqual(contact.normal, Vector3(1, 0, 0))
    }

    func testCompoundCompoundContactAggregatesLeafPairs() throws {
        let a = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 0.6),
                  transform: Transform(position: Vector3(-1, 0, 0))),
            .init(Sphere(center: .zero, radius: 0.6),
                  transform: Transform(position: Vector3(1, 0, 0))),
        ])
        let b = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 0.6),
                  transform: Transform(position: Vector3(-1, 0, 0))),
            .init(Sphere(center: .zero, radius: 0.6),
                  transform: Transform(position: Vector3(1, 0, 0))),
        ])

        let manifold = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            a,
            b,
            frame: Transform(position: Vector3(0.5, 0, 0))))

        XCTAssertEqual(manifold.contacts.count, 2)
        XCTAssertEqual(manifold.contacts[0].penetrationDepth,
                       0.7,
                       accuracy: 1.0e-9)
        XCTAssertEqual(manifold.contacts[1].penetrationDepth,
                       0.7,
                       accuracy: 1.0e-9)
        XCTAssertNotEqual(manifold.contacts[0].featureID,
                          manifold.contacts[1].featureID)
    }

    func testRotatedChildContactReturnsCompoundLocalGeometry() throws {
        let childTransform = Transform(
            orientation: Quaternion(angle: Scalar.pi * 0.5,
                                    axis: Vector3(0, 0, 1)),
            position: Vector3(2, 0, 0))
        let compound = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 1),
                  transform: childTransform),
        ])

        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(
            compound,
            Sphere(center: .zero, radius: 1),
            frame: Transform(position: Vector3(2, 1.5, 0)))?
            .contacts.first)

        XCTAssertEqual(contact.penetrationDepth, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(contact.pointOnA.x, 2, accuracy: 1.0e-9)
        XCTAssertEqual(contact.pointOnA.y, 1, accuracy: 1.0e-9)
        XCTAssertEqual(contact.pointOnB.x, 2, accuracy: 1.0e-9)
        XCTAssertEqual(contact.pointOnB.y, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(contact.normal.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(contact.normal.y, 1, accuracy: 1.0e-9)
    }

    func testSeparatedAndEmptyCompoundsHaveNoContact() {
        let compound = CompoundPrimitive(children: [
            .init(Box(halfExtents: Vector3(0.5, 0.5, 0.5)),
                  transform: Transform(position: Vector3(4, 0, 0))),
        ])

        XCTAssertNil(CollisionAlgorithms.contactManifold(
            Sphere(center: .zero, radius: 0.5),
            compound))
        XCTAssertNil(CollisionAlgorithms.contactManifold(
            CompoundPrimitive(),
            compound))
    }
}
