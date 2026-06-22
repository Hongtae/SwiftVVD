import XCTest
@testable import VVD

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
    }
}
