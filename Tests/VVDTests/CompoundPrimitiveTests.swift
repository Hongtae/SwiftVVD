import XCTest
import VVD

final class CompoundPrimitiveTests: XCTestCase {
    func testBoundsUnionUsesChildTransforms() {
        let boxChild = CompoundPrimitive.Child(Box(halfExtents: Vector3(1, 1, 1)),
                                               transform: Transform(position: Vector3(2, 0, 0)))
        let sphereChild = CompoundPrimitive.Child(Sphere(center: .zero, radius: 0.5),
                                                  transform: Transform(position: Vector3(-2, 0, 0)))

        let compound = CompoundPrimitive(children: [boxChild, sphereChild])

        XCTAssertTrue(compound.isValid)
        XCTAssertEqual(compound.bounds.min.x, -2.5, accuracy: 1.0e-9)
        XCTAssertEqual(compound.bounds.min.y, -1.0, accuracy: 1.0e-9)
        XCTAssertEqual(compound.bounds.min.z, -1.0, accuracy: 1.0e-9)
        XCTAssertEqual(compound.bounds.max.x, 3.0, accuracy: 1.0e-9)
        XCTAssertEqual(compound.bounds.max.y, 1.0, accuracy: 1.0e-9)
        XCTAssertEqual(compound.bounds.max.z, 1.0, accuracy: 1.0e-9)
    }

    func testFlattenedChildrenComposeNestedTransforms() {
        let leaf = CompoundPrimitive.Child(Sphere(center: .zero, radius: 0.5),
                                           transform: Transform(position: Vector3(1, 0, 0)))
        let nested = CompoundPrimitive(children: [leaf])
        let parentTransform = Transform(orientation: Quaternion(angle: Scalar.pi * 0.5,
                                                                axis: Vector3(0, 0, 1)),
                                        position: Vector3(0, 2, 0))
        let parentChild = CompoundPrimitive.Child(nested,
                                                  transform: parentTransform)
        let compound = CompoundPrimitive(children: [parentChild])

        let flattenedChildren = compound.flattenedChildren()

        XCTAssertEqual(flattenedChildren.count, 1)
        XCTAssertEqual(flattenedChildren[0].transform.position.x, 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(flattenedChildren[0].transform.position.y, 3.0, accuracy: 1.0e-9)
        XCTAssertEqual(flattenedChildren[0].transform.position.z, 0.0, accuracy: 1.0e-9)
        XCTAssertEqual(flattenedChildren[0].bounds.min.x, -0.5, accuracy: 1.0e-9)
        XCTAssertEqual(flattenedChildren[0].bounds.min.y, 2.5, accuracy: 1.0e-9)
        XCTAssertEqual(flattenedChildren[0].bounds.min.z, -0.5, accuracy: 1.0e-9)
        XCTAssertEqual(flattenedChildren[0].bounds.max.x, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(flattenedChildren[0].bounds.max.y, 3.5, accuracy: 1.0e-9)
        XCTAssertEqual(flattenedChildren[0].bounds.max.z, 0.5, accuracy: 1.0e-9)

        let flattened = compound.flattened()
        XCTAssertEqual(flattened.children.count, 1)
        XCTAssertTrue(flattened.isValid)
        XCTAssertEqual(flattened.bounds.min.x, -0.5, accuracy: 1.0e-9)
        XCTAssertEqual(flattened.bounds.max.y, 3.5, accuracy: 1.0e-9)
    }

    func testEmptyCompoundIsInvalidWithNullBounds() {
        let compound = CompoundPrimitive()

        XCTAssertFalse(compound.isValid)
        XCTAssertTrue(compound.bounds.isNull)
        XCTAssertTrue(compound.flattenedChildren().isEmpty)
        XCTAssertFalse(CollisionAlgorithms.intersects(
            Box(halfExtents: Vector3(1, 1, 1)),
            compound))
        XCTAssertFalse(CollisionAlgorithms.intersects(compound, compound))
    }

    func testPrimitiveIntersectionUsesFlattenedChildTransforms() {
        let leaf = CompoundPrimitive.Child(
            Sphere(center: .zero, radius: 0.5),
            transform: Transform(position: Vector3(1, 0, 0)))
        let nested = CompoundPrimitive(children: [leaf])
        let compound = CompoundPrimitive(children: [
            CompoundPrimitive.Child(
                nested,
                transform: Transform(position: Vector3(2, 0, 0)))
        ])
        let box = Box(halfExtents: Vector3(0.5, 0.5, 0.5))
        let overlappingFrame = Transform(position: Vector3(-2.75, 0, 0))
        let separatedFrame = Transform(position: Vector3(2, 0, 0))

        XCTAssertTrue(CollisionAlgorithms.intersects(box,
                                                      compound,
                                                      frame: overlappingFrame))
        XCTAssertTrue(CollisionAlgorithms.intersects(
            compound,
            box,
            frame: overlappingFrame.inverted()))
        XCTAssertFalse(CollisionAlgorithms.intersects(box,
                                                       compound,
                                                       frame: separatedFrame))
    }

    func testCompoundIntersectionComposesBothChildFrames() {
        let compoundA = CompoundPrimitive(children: [
            CompoundPrimitive.Child(
                Box(halfExtents: Vector3(0.5, 0.5, 0.5)),
                transform: Transform(position: Vector3(0, 2, 0)))
        ])
        let compoundB = CompoundPrimitive(children: [
            CompoundPrimitive.Child(
                Sphere(center: .zero, radius: 0.4),
                transform: Transform(position: Vector3(1, 0, 0)))
        ])
        let overlappingFrame = Transform(
            orientation: Quaternion(angle: Scalar.pi * 0.5,
                                    axis: Vector3(0, 0, 1)),
            position: Vector3(0, 1, 0))
        let separatedFrame = Transform(position: Vector3(0, 4, 0))

        XCTAssertTrue(CollisionAlgorithms.intersects(compoundA,
                                                      compoundB,
                                                      frame: overlappingFrame))
        XCTAssertTrue(CollisionAlgorithms.intersects(
            compoundB,
            compoundA,
            frame: overlappingFrame.inverted()))
        XCTAssertFalse(CollisionAlgorithms.intersects(compoundA,
                                                       compoundB,
                                                       frame: separatedFrame))
    }

    func testCompoundIntersectionDoesNotRejectNullBoundsPrimitive() {
        let plane = StaticPlane(Plane(normal: Vector3(0, 1, 0), point: .zero))
        let overlapping = CompoundPrimitive(children: [
            CompoundPrimitive.Child(Sphere(center: .zero, radius: 0.5))
        ])
        let separated = CompoundPrimitive(children: [
            CompoundPrimitive.Child(
                Sphere(center: .zero, radius: 0.5),
                transform: Transform(position: Vector3(0, 2, 0)))
        ])

        XCTAssertTrue(CollisionAlgorithms.intersects(plane, overlapping))
        XCTAssertTrue(CollisionAlgorithms.intersects(overlapping, plane))
        XCTAssertFalse(CollisionAlgorithms.intersects(plane, separated))
    }

    func testContainsTransformsPointIntoChildSpace() {
        let compound = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 1),
                  transform: Transform(position: Vector3(3, 0, 0))),
            .init(Box(halfExtents: Vector3(0.5, 0.5, 0.5)),
                  transform: Transform(position: Vector3(-2, 0, 0)))
        ])

        XCTAssertTrue(compound.contains(Vector3(3.5, 0, 0)))
        XCTAssertTrue(compound.contains(Vector3(-2, 0, 0)))
        XCTAssertFalse(compound.contains(.zero))
    }

    func testRayHitUsesClosestTransformedChildGeometry() throws {
        let compound = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 1),
                  transform: Transform(position: Vector3(4, 0, 0))),
            .init(Box(halfExtents: Vector3(0.5, 0.5, 0.5)),
                  transform: Transform(position: Vector3(2, 0, 0)))
        ])
        let ray = Ray(origin: .zero, direction: Vector3(2, 0, 0))

        let hit = try XCTUnwrap(compound.rayTest(ray))

        XCTAssertEqual(hit.parameter, 0.75, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position, Vector3(1.5, 0, 0))
        XCTAssertEqual(hit.normal, Vector3(-1, 0, 0))
    }
}
