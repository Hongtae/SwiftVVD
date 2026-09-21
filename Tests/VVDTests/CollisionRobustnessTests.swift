import XCTest
import VVD

final class CollisionRobustnessTests: XCTestCase {
    func testNearlyParallelBoxesChooseTheMinimumUnitAxisDepth() throws {
        let box = Box(halfExtents: Vector3(1, 1, 1))
        let angle = Scalar(2.5) * .pi / 180
        let frame = Transform(orientation: Quaternion(angle: angle, axis: Vector3(0, 0, 1)),
                              position: Vector3(1.5, 0, 0))
        let contact = try XCTUnwrap(CollisionAlgorithms.contactManifold(box, box, frame: frame)?
            .contacts.first)

        XCTAssertEqual(contact.normal, Vector3(1, 0, 0))
        XCTAssertEqual(contact.penetrationDepth, 1 + cos(angle) + sin(angle) - 1.5,
                       accuracy: 1.0e-9)
    }

    func testCompoundPreservesAllBitsOfMeshContactFeatures() throws {
        let meshA = TriangleMesh(triangles: [
            Triangle(Vector3(-2, 0, -1), Vector3(-1, 0, -1), Vector3(-2, 0, 0)),
            Triangle(Vector3(1, 0, -1), Vector3(2, 0, -1), Vector3(1, 0, 0)),
        ])
        let meshB = TriangleMesh(triangles: [
            Triangle(Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(0, 0, 10)),
        ])
        let compound = CompoundPrimitive(children: [.init(meshA)])
        let contacts = try XCTUnwrap(CollisionAlgorithms.contactManifold(compound, meshB)).contacts
        XCTAssertEqual(contacts.count, 2)
        XCTAssertEqual(Set(contacts.map(\.featureID)).count, contacts.count)
        XCTAssertEqual(contacts.map(\.featureID),
                       CollisionAlgorithms.contactManifold(compound, meshB)?.contacts.map(\.featureID))
    }

    func testUnboundedCompoundSurvivesNestedBroadPhaseAndRayQueries() throws {
        let box = Box(halfExtents: Vector3(1, 1, 1))
        let plane = StaticPlane(Plane(normal: Vector3(0, 1, 0), point: .zero))
        let compound = CompoundPrimitive(children: [.init(box), .init(plane)])
        let nested = CompoundPrimitive(children: [.init(compound)])
        for primitive in [compound, nested] {
            XCTAssertTrue(primitive.bounds.isNull)
            let support = Collider(primitive: primitive)
            let sphere = Collider(primitive: Sphere(center: .zero, radius: 0.5),
                                  transform: Transform(position: Vector3(100, 0.25, 0)))
            let space = CollisionSpace(colliders: [support, sphere])
            XCTAssertTrue(support.intersects(sphere))
            XCTAssertEqual(space.collisionPairs().count, 1)
            XCTAssertNotNil(space.collisionPairs().first?.worldContactManifold)
            let ray = Ray(origin: Vector3(200, 2, 0), direction: Vector3(0, -1, 0))
            let hit = try XCTUnwrap(space.raycast(ray))
            XCTAssertTrue(hit.collider === support)
            XCTAssertEqual(hit.distance, 2, accuracy: 1.0e-9)
            XCTAssertTrue(CollisionMotion(translation: Vector3(1, 0, 0)).sweptBounds(of: primitive).isNull)
        }
        let bounded = CompoundPrimitive(children: [.init(box), .init(CompoundPrimitive()),
            .init(StaticPlane(Plane(normal: .zero, point: .zero)))])
        XCTAssertEqual(bounded.bounds, box.bounds)
    }

    func testNonfiniteRaysAreRejectedAtPrimitiveSpaceAndBVHBoundaries() {
        let box = Box(halfExtents: Vector3(1, 1, 1))
        let primitives: [any CollisionPrimitive] = [box, Sphere(center: .zero, radius: 1),
            Capsule(radius: 1, height: 2), Cylinder(radius: 1, height: 2),
            Cone(radius: 1, height: 2),
            StaticPlane(Plane(normal: Vector3(0, 1, 0), point: .zero)),
            CompoundPrimitive(children: [.init(box)])]
        let space = CollisionSpace(colliders: primitives.map { Collider(primitive: $0) })
        let bvh = BVH([.init(bounds: box.bounds, primitiveIndex: 0)])
        for value in [Scalar.nan, .infinity, -.infinity] {
            let rays = [
                Ray(origin: Vector3(value, 0, 0), direction: Vector3(1, 1, 1)),
                Ray(origin: Vector3(value, value, value), direction: Vector3(1, 1, 1)),
                Ray(origin: .zero, direction: Vector3(value, 1, 1)),
            ]
            for ray in rays {
                XCTAssertFalse(ray.isValid)
                for primitive in primitives { XCTAssertNil(primitive.rayTest(ray)) }
                XCTAssertNil(space.raycast(ray))
                XCTAssertTrue(bvh.primitiveIndices(intersecting: ray).isEmpty)
                XCTAssertFalse(box.bounds.intersects(ray))
                XCTAssertLessThan(box.bounds.rayTest(rayOrigin: ray.origin, direction: ray.direction), 0)
                XCTAssertLessThan(box.bounds.rayTest1(rayOrigin: ray.origin, direction: ray.direction), 0)
            }
        }
    }

    func testNaNAndInfiniteBoundsCannotReachQuantization() throws {
        let valid = AABB(center: .zero, halfExtents: Vector3(1, 1, 1))
        let nan = AABB(min: Vector3(Scalar.nan, 0, 0), max: Vector3(1, 1, 1))
        let infinite = AABB(min: Vector3(-Scalar.infinity, -1, -1),
                            max: Vector3(Scalar.infinity, 1, 1))
        XCTAssertTrue(nan.isNull)
        XCTAssertEqual(valid.combining(nan), valid)
        for elements in [[valid, nan, infinite], [nan, infinite, valid]] {
            let bvh = BVH(elements.enumerated().map { .init(bounds: $0.element, primitiveIndex: $0.offset) })
            XCTAssertEqual(bvh.elementCount, 1)
            XCTAssertEqual(bvh.bounds, valid)
            XCTAssertNotNil(bvh.quantized16())
            XCTAssertNotNil(bvh.quantized32())
        }
        let huge = AABB(min: Vector3(-Scalar.greatestFiniteMagnitude, -1, -1),
                        max: Vector3(Scalar.greatestFiniteMagnitude, 1, 1))
        let bvh = BVH([.init(bounds: huge, primitiveIndex: 0)])
        XCTAssertEqual(bvh.elementCount, 1)
        XCTAssertNil(bvh.quantized())
    }

    func testPlaneQueriesAreIndependentOfNormalScaleAndPreserveSurfaceOrientation() throws {
        for scale: Scalar in [1.0e-3, 1, 100] {
            let plane = StaticPlane(Plane(normal: Vector3(0, scale, 0), point: .zero))
            let origin = Vector3(0, 1.0e-13, 0)
            XCTAssertFalse(plane.contains(origin))
            XCTAssertNil(plane.rayTest(Ray(origin: origin, direction: Vector3(0, 1, 0))))
            let hit = try XCTUnwrap(plane.rayTest(Ray(origin: origin, direction: Vector3(0, -1, 0))))
            XCTAssertEqual(hit.parameter, origin.y, accuracy: 1.0e-20)
            XCTAssertEqual(hit.normal, Vector3(0, 1, 0))
            let underside = try XCTUnwrap(plane.rayTest(
                Ray(origin: Vector3(0, -1, 0), direction: Vector3(0, 1, 0))))
            XCTAssertEqual(underside.normal, Vector3(0, 1, 0))
            XCTAssertEqual(plane.rayTest(Ray(origin: .zero, direction: Vector3(1, 0, 0)))?.parameter, 0)
        }
    }
}
