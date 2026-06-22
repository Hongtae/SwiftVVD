import XCTest
@testable import VVD

final class AABBTests: XCTestCase {
    func testInitializesFromVertices() {
        let vertices = [
            Vector3(1, -2, 3),
            Vector3(-4, 5, 0),
            Vector3(2, 0, -6)
        ]

        let bounds = AABB(vertices[...])

        XCTAssertFalse(bounds.isNull)
        XCTAssertEqual(bounds.min.x, -4, accuracy: 1.0e-9)
        XCTAssertEqual(bounds.min.y, -2, accuracy: 1.0e-9)
        XCTAssertEqual(bounds.min.z, -6, accuracy: 1.0e-9)
        XCTAssertEqual(bounds.max.x, 2, accuracy: 1.0e-9)
        XCTAssertEqual(bounds.max.y, 5, accuracy: 1.0e-9)
        XCTAssertEqual(bounds.max.z, 3, accuracy: 1.0e-9)
    }

    func testInitializesEmptyCollectionAsNull() {
        let vertices: [Vector3] = []

        XCTAssertTrue(AABB(vertices).isNull)
    }

    func testAppliesTransform() {
        let bounds = AABB(min: Vector3(-1, -2, -3), max: Vector3(1, 2, 3))
        let transformed = bounds.applying(Transform(position: Vector3(4, 5, 6)))

        XCTAssertEqual(transformed.min.x, 3, accuracy: 1.0e-9)
        XCTAssertEqual(transformed.min.y, 3, accuracy: 1.0e-9)
        XCTAssertEqual(transformed.min.z, 3, accuracy: 1.0e-9)
        XCTAssertEqual(transformed.max.x, 5, accuracy: 1.0e-9)
        XCTAssertEqual(transformed.max.y, 7, accuracy: 1.0e-9)
        XCTAssertEqual(transformed.max.z, 9, accuracy: 1.0e-9)
    }
}
