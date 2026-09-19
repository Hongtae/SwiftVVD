//
//  File: CollisionAlgorithmRegistryTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class CollisionAlgorithmRegistryTests: XCTestCase {
    func testUnknownPrimitivePairHasNoBuiltInCollisionResult() {
        let primitiveA = RegistryPrimitiveA()
        let primitiveB = RegistryPrimitiveB()

        XCTAssertFalse(CollisionAlgorithms.intersects(primitiveA, primitiveB))
        XCTAssertNil(CollisionAlgorithms.contactManifold(primitiveA, primitiveB))
    }

    func testPrimitiveTypePairIsOrdered() {
        let pairAB = CollisionPrimitiveTypePair(RegistryPrimitiveA.self,
                                                RegistryPrimitiveB.self)
        let pairBA = CollisionPrimitiveTypePair(RegistryPrimitiveB.self,
                                                RegistryPrimitiveA.self)

        XCTAssertNotEqual(pairAB, pairBA)
        XCTAssertEqual(pairAB,
                       CollisionPrimitiveTypePair(RegistryPrimitiveA.self,
                                                  RegistryPrimitiveB.self))
    }

    func testRegisteredAlgorithmOverridesBuiltinFallback() {
        var registry = CollisionAlgorithmRegistry()
        registry.register(Sphere.self, Sphere.self) { _, _, _ in false }

        let sphereA = Sphere(center: .zero, radius: 1)
        let sphereB = Sphere(center: .zero, radius: 1)

        XCTAssertTrue(CollisionAlgorithms.intersects(sphereA, sphereB))
        XCTAssertFalse(registry.intersects(sphereA, sphereB))
    }

    func testBuiltinRegistryFallbackCanBeDisabled() {
        let sphereA = Sphere(center: .zero, radius: 1)
        let sphereB = Sphere(center: .zero, radius: 1)
        let defaultRegistry = CollisionAlgorithmRegistry()
        let isolatedRegistry = CollisionAlgorithmRegistry(
            usesBuiltinFallback: false)

        XCTAssertTrue(defaultRegistry.intersects(sphereA, sphereB))
        XCTAssertNotNil(defaultRegistry.contactManifold(sphereA, sphereB))
        XCTAssertFalse(isolatedRegistry.intersects(sphereA, sphereB))
        XCTAssertNil(isolatedRegistry.contactManifold(sphereA, sphereB))
    }

    func testSymmetricRegistrationReversesFrameAndContactGeometry() throws {
        let registry = makeRegistry()
        let primitiveA = RegistryPrimitiveA()
        let primitiveB = RegistryPrimitiveB()
        let frameAB = Transform(position: Vector3(0.5, 0, 0))
        let frameBA = frameAB.inverted()

        XCTAssertTrue(registry.isRegistered(RegistryPrimitiveA.self,
                                            RegistryPrimitiveB.self))
        XCTAssertTrue(registry.isRegistered(RegistryPrimitiveB.self,
                                            RegistryPrimitiveA.self))
        XCTAssertTrue(registry.intersects(primitiveA,
                                          primitiveB,
                                          frame: frameAB))
        XCTAssertTrue(registry.intersects(primitiveB,
                                          primitiveA,
                                          frame: frameBA))

        let contact = try XCTUnwrap(registry.contactManifold(
            primitiveB,
            primitiveA,
            frame: frameBA)?.contacts.first)
        XCTAssertEqual(contact.pointOnA, .zero)
        XCTAssertEqual(contact.pointOnB, Vector3(-0.5, 0, 0))
        XCTAssertEqual(contact.normal, Vector3(-1, 0, 0))
        XCTAssertEqual(contact.penetrationDepth, 0.25)
    }

    func testCollisionSpaceUsesItsAlgorithmRegistry() throws {
        let colliderB = Collider(primitive: RegistryPrimitiveB(),
                                 transform: Transform(position: Vector3(0.5, 0, 0)))
        let colliderA = Collider(primitive: RegistryPrimitiveA())
        let space = CollisionSpace(colliders: [colliderB, colliderA],
                                   algorithms: makeRegistry())

        let pair = try XCTUnwrap(space.collisionPairs().first)
        XCTAssertTrue(pair.colliderA === colliderB)
        XCTAssertTrue(pair.colliderB === colliderA)

        let contact = try XCTUnwrap(pair.worldContactManifold?.contacts.first)
        XCTAssertEqual(contact.pointOnA, Vector3(0.5, 0, 0))
        XCTAssertEqual(contact.pointOnB, .zero)
        XCTAssertEqual(contact.normal, Vector3(-1, 0, 0))
    }

    func testRegistryRecursesThroughCompoundLeavesInQueryOrder() {
        var registry = CollisionAlgorithmRegistry(usesBuiltinFallback: false)
        registry.register(RegistryAlgorithm())

        let compoundA = CompoundPrimitive(children: [
            CompoundPrimitive.Child(
                RegistryPrimitiveA(),
                transform: Transform(position: Vector3(2, 0, 0)))
        ])
        let compoundB = CompoundPrimitive(children: [
            CompoundPrimitive.Child(
                RegistryPrimitiveB(),
                transform: Transform(position: Vector3(1, 0, 0)))
        ])
        let overlappingFrame = Transform(position: Vector3(1.5, 0, 0))
        let separatedFrame = Transform(position: Vector3(3, 0, 0))

        XCTAssertTrue(registry.intersects(RegistryPrimitiveA(),
                                          compoundB,
                                          frame: Transform(position: Vector3(-0.5, 0, 0))))
        XCTAssertTrue(registry.intersects(compoundA,
                                          RegistryPrimitiveB(),
                                          frame: Transform(position: Vector3(2.5, 0, 0))))
        XCTAssertTrue(registry.intersects(compoundA,
                                          compoundB,
                                          frame: overlappingFrame))
        XCTAssertFalse(registry.intersects(compoundA,
                                           compoundB,
                                           frame: separatedFrame))

        // Only A-B is registered. Reversing the compound query must preserve
        // leaf order rather than silently invoking the A-B entry.
        XCTAssertFalse(registry.intersects(
            compoundB,
            compoundA,
            frame: overlappingFrame.inverted()))
    }

    func testExplicitCompoundRegistrationOverridesLeafTraversal() {
        var registry = makeRegistry()
        let primitiveA = RegistryPrimitiveA()
        let compoundB = CompoundPrimitive(children: [
            CompoundPrimitive.Child(
                RegistryPrimitiveB(),
                transform: Transform(position: Vector3(0.5, 0, 0)))
        ])

        XCTAssertTrue(registry.intersects(primitiveA, compoundB))

        registry.register(RegistryPrimitiveA.self,
                          CompoundPrimitive.self) { _, _, _ in false }

        XCTAssertFalse(registry.intersects(primitiveA, compoundB))
    }

    func testCollisionSpaceUsesRegisteredAlgorithmsInsideCompounds() {
        let compoundA = CompoundPrimitive(children: [
            CompoundPrimitive.Child(RegistryPrimitiveA())
        ])
        let compoundB = CompoundPrimitive(children: [
            CompoundPrimitive.Child(
                RegistryPrimitiveB(),
                transform: Transform(position: Vector3(0.5, 0, 0)))
        ])
        let space = CollisionSpace(
            colliders: [Collider(primitive: compoundA),
                        Collider(primitive: compoundB)],
            algorithms: makeRegistry())

        XCTAssertEqual(space.collisionPairs().count, 1)
    }

    func testColliderCanBeConstructedFromTypedShape() throws {
        let shape = BoxShape(Box(halfExtents: Vector3(1, 2, 3)))
        let collider = Collider(shape: shape)
        let primitive = try XCTUnwrap(collider.primitive as? Box)

        XCTAssertEqual(primitive, shape.primitive)
        XCTAssertEqual(collider.bounds, shape.bounds)
    }

    private func makeRegistry() -> CollisionAlgorithmRegistry {
        var registry = CollisionAlgorithmRegistry(usesBuiltinFallback: false)
        registry.registerSymmetric(RegistryAlgorithm())
        return registry
    }
}

private struct RegistryAlgorithm: CollisionAlgorithm {
    func intersects(_ a: RegistryPrimitiveA,
                    _ b: RegistryPrimitiveB,
                    frame: Transform) -> Bool {
        abs(frame.position.x) <= 1
    }

    func contactManifold(_ a: RegistryPrimitiveA,
                         _ b: RegistryPrimitiveB,
                         frame: Transform) -> ContactManifold? {
        ContactManifold(Contact(pointOnA: .zero,
                                pointOnB: Vector3(0.5, 0, 0),
                                normal: Vector3(1, 0, 0),
                                penetrationDepth: 0.25))
    }
}

private struct RegistryPrimitiveA: CollisionPrimitive {
    let bounds: AABB = .null
    let isValid = true

    func contains(_ point: Vector3) -> Bool { false }

    func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        -1
    }
}

private struct RegistryPrimitiveB: CollisionPrimitive {
    let bounds: AABB = .null
    let isValid = true

    func contains(_ point: Vector3) -> Bool { false }

    func rayTest(rayOrigin origin: Vector3, direction: Vector3) -> Scalar {
        -1
    }
}
