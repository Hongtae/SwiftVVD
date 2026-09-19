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
        XCTAssertNotNil(defaultRegistry.timeOfImpact(
            sphereA,
            sphereB,
            frame: Transform(position: Vector3(3, 0, 0)),
            translation: Vector3(4, 0, 0)))
        XCTAssertNil(isolatedRegistry.timeOfImpact(
            sphereA,
            sphereB,
            frame: Transform(position: Vector3(3, 0, 0)),
            translation: Vector3(4, 0, 0)))
    }

    func testSymmetricSweepRegistrationReversesMotionAndGeometry() throws {
        var registry = CollisionAlgorithmRegistry(usesBuiltinFallback: false)
        registry.registerSymmetricSweep(RegistrySweepAlgorithm())

        XCTAssertTrue(registry.isSweepRegistered(RegistryPrimitiveA.self,
                                                 RegistryPrimitiveB.self))
        XCTAssertTrue(registry.isSweepRegistered(RegistryPrimitiveB.self,
                                                 RegistryPrimitiveA.self))

        let forward = try XCTUnwrap(registry.timeOfImpact(
            RegistryPrimitiveA(),
            RegistryPrimitiveB(),
            translation: Vector3(1, 0, 0)))
        XCTAssertEqual(forward.pointOnA, Vector3(0.25, 0, 0))
        XCTAssertEqual(forward.pointOnB, Vector3(0.5, 0, 0))
        XCTAssertEqual(forward.normal, Vector3(1, 0, 0))

        let reverse = try XCTUnwrap(registry.timeOfImpact(
            RegistryPrimitiveB(),
            RegistryPrimitiveA(),
            translation: Vector3(-1, 0, 0)))
        XCTAssertEqual(reverse.fraction, 0.25)
        XCTAssertEqual(reverse.pointOnA, Vector3(0.25, 0, 0))
        XCTAssertEqual(reverse.pointOnB, .zero)
        XCTAssertEqual(reverse.normal, Vector3(-1, 0, 0))

        XCTAssertTrue(registry.unregisterSweep(RegistryPrimitiveA.self,
                                               RegistryPrimitiveB.self))
        XCTAssertFalse(registry.isSweepRegistered(RegistryPrimitiveA.self,
                                                  RegistryPrimitiveB.self))
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

    func testRegistryRecursesThroughCompoundLeavesForSweeps() throws {
        var registry = CollisionAlgorithmRegistry(usesBuiltinFallback: false)
        registry.registerSweep(
            RegistryPrimitiveA.self,
            RegistryPrimitiveB.self
        ) { _, _, frame, translation in
            guard frame == .identity,
                  translation == Vector3(1, 0, 0)
            else { return nil }
            return TimeOfImpact(fraction: 0.25,
                                pointOnA: Vector3(0.25, 0, 0),
                                pointOnB: Vector3(0.5, 0, 0),
                                normal: Vector3(1, 0, 0))
        }
        let compoundA = CompoundPrimitive(children: [
            .init(RegistryPrimitiveA(),
                  transform: Transform(position: Vector3(2, 0, 0))),
        ])
        let compoundB = CompoundPrimitive(children: [
            .init(RegistryPrimitiveB(),
                  transform: Transform(position: Vector3(1, 0, 0))),
        ])

        let impact = try XCTUnwrap(registry.timeOfImpact(
            compoundA,
            compoundB,
            frame: Transform(position: Vector3(1, 0, 0)),
            translation: Vector3(1, 0, 0)))

        XCTAssertEqual(impact.fraction, 0.25)
        XCTAssertEqual(impact.pointOnA, Vector3(2.25, 0, 0))
        XCTAssertEqual(impact.pointOnB, Vector3(2.5, 0, 0))
        XCTAssertEqual(impact.normal, Vector3(1, 0, 0))
    }

    func testCompoundSweepTransformsTranslationAndGeometryThroughRotatedChild() throws {
        var registry = CollisionAlgorithmRegistry(usesBuiltinFallback: false)
        registry.registerSweep(
            RegistryPrimitiveA.self,
            RegistryPrimitiveB.self
        ) { _, _, frame, translation in
            guard frame.position.lengthSquared < 1.0e-12,
                  abs(frame.orientation.x) < 1.0e-9,
                  abs(frame.orientation.y) < 1.0e-9,
                  abs(frame.orientation.z) < 1.0e-9,
                  abs(abs(frame.orientation.w) - 1) < 1.0e-9,
                  (translation - Vector3(1, 0, 0)).lengthSquared < 1.0e-12
            else { return nil }
            return TimeOfImpact(fraction: 0.5,
                                pointOnA: Vector3(0.25, 0, 0),
                                pointOnB: Vector3(0.5, 0, 0),
                                normal: Vector3(1, 0, 0))
        }
        let childTransform = Transform(
            orientation: Quaternion(angle: Scalar.pi * 0.5,
                                    axis: Vector3(0, 0, 1)),
            position: Vector3(2, 0, 0))
        let compound = CompoundPrimitive(children: [
            .init(RegistryPrimitiveA(), transform: childTransform),
        ])

        let impact = try XCTUnwrap(registry.timeOfImpact(
            compound,
            RegistryPrimitiveB(),
            frame: childTransform,
            translation: Vector3(0, 1, 0)))

        XCTAssertEqual(impact.fraction, 0.5)
        XCTAssertEqual(impact.pointOnA.x, 2, accuracy: 1.0e-9)
        XCTAssertEqual(impact.pointOnA.y, 0.25, accuracy: 1.0e-9)
        XCTAssertEqual(impact.pointOnB.x, 2, accuracy: 1.0e-9)
        XCTAssertEqual(impact.pointOnB.y, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(impact.normal.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(impact.normal.y, 1, accuracy: 1.0e-9)
    }

    func testExplicitCompoundSweepRegistrationOverridesLeafTraversal() {
        var registry = CollisionAlgorithmRegistry(usesBuiltinFallback: false)
        registry.registerSweep(
            RegistryPrimitiveA.self,
            RegistryPrimitiveB.self
        ) { _, _, _, _ in
            TimeOfImpact(fraction: .zero,
                         pointOnA: .zero,
                         pointOnB: .zero,
                         normal: Vector3(1, 0, 0))
        }
        let compound = CompoundPrimitive(children: [
            .init(RegistryPrimitiveB()),
        ])

        XCTAssertNotNil(registry.timeOfImpact(
            RegistryPrimitiveA(),
            compound,
            translation: .zero))

        registry.registerSweep(
            RegistryPrimitiveA.self,
            CompoundPrimitive.self
        ) { _, _, _, _ in nil }

        XCTAssertNil(registry.timeOfImpact(
            RegistryPrimitiveA(),
            compound,
            translation: .zero))
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

        let pairs = space.collisionPairs()
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.contactManifold?.contacts.count, 1)
    }

    func testExactCompoundRegistrationOverridesLeafContactTraversal() {
        var registry = makeRegistry()
        let compound = CompoundPrimitive(children: [
            .init(RegistryPrimitiveB()),
        ])

        XCTAssertNotNil(registry.contactManifold(RegistryPrimitiveA(),
                                                 compound))

        registry.register(RegistryPrimitiveA.self,
                          CompoundPrimitive.self) { _, _, _ in true }

        XCTAssertNil(registry.contactManifold(RegistryPrimitiveA(),
                                              compound))
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

private struct RegistrySweepAlgorithm: CollisionSweepAlgorithm {
    func timeOfImpact(_ a: RegistryPrimitiveA,
                      _ b: RegistryPrimitiveB,
                      frame: Transform,
                      translation: Vector3) -> TimeOfImpact? {
        guard frame == .identity,
              translation == Vector3(1, 0, 0)
        else { return nil }
        return TimeOfImpact(fraction: 0.25,
                            pointOnA: Vector3(0.25, 0, 0),
                            pointOnB: Vector3(0.5, 0, 0),
                            normal: Vector3(1, 0, 0))
    }
}

private struct RegistryPrimitiveA: CollisionPrimitive {
    let bounds: AABB = .null
    let isValid = true

    func contains(_ point: Vector3) -> Bool { false }

    func closestPoint(to point: Vector3) -> PrimitiveClosestPoint? { nil }

    func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        nil
    }
}

private struct RegistryPrimitiveB: CollisionPrimitive {
    let bounds: AABB = .null
    let isValid = true

    func contains(_ point: Vector3) -> Bool { false }

    func closestPoint(to point: Vector3) -> PrimitiveClosestPoint? { nil }

    func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        nil
    }
}
