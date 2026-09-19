import XCTest
@testable import VVD

final class CollisionPrimitiveOverlapTests: XCTestCase {
    func testBoxBoxOverlapUsesRelativeFrame() throws {
        let a = Box(halfExtents: Vector3(1, 1, 1))
        let b = Box(halfExtents: Vector3(0.5, 0.5, 0.5))

        let overlapping = Transform(position: Vector3(1.25, 0, 0))
        XCTAssertTrue(CollisionAlgorithms.intersects(a, b, frame: overlapping))
        let contact = try firstContact(a, b, frame: overlapping)
        XCTAssertEqual(contact.penetrationDepth, 0.25, accuracy: 1.0e-9)

        let separated = Transform(position: Vector3(1.6, 0, 0))
        XCTAssertFalse(CollisionAlgorithms.intersects(a, b, frame: separated))
        XCTAssertNil(CollisionAlgorithms.contactManifold(a, b, frame: separated))
    }

    func testRotatedBoxBoxOverlap() throws {
        let a = Box(halfExtents: Vector3(1, 1, 1))
        let b = Box(halfExtents: Vector3(0.5, 0.5, 0.5))
        let frame = Transform(orientation: Quaternion(angle: Scalar.pi * 0.25,
                                                      axis: Vector3(0, 1, 0)),
                              position: Vector3(1.45, 0, 0))

        XCTAssertTrue(CollisionAlgorithms.intersects(a, b, frame: frame))
        XCTAssertGreaterThanOrEqual(try firstContact(a, b, frame: frame).penetrationDepth, 0.0)
    }

    func testBoxSphereOverlapUsesRelativeFrame() throws {
        let box = Box(halfExtents: Vector3(1, 1, 1))
        let sphere = Sphere(center: .zero, radius: 0.5)

        let overlapping = Transform(position: Vector3(1.4, 0, 0))
        XCTAssertTrue(CollisionAlgorithms.intersects(box, sphere, frame: overlapping))
        let contact = try firstContact(box, sphere, frame: overlapping)
        XCTAssertEqual(contact.penetrationDepth, 0.1, accuracy: 1.0e-9)
        XCTAssertEqual(contact.normal.x, 1.0, accuracy: 1.0e-9)

        let separated = Transform(position: Vector3(1.6, 0, 0))
        XCTAssertFalse(CollisionAlgorithms.intersects(box, sphere, frame: separated))
        XCTAssertNil(CollisionAlgorithms.contactManifold(box, sphere, frame: separated))
    }

    func testSphereSphereAndSymmetricDispatch() throws {
        let a = Sphere(center: .zero, radius: 1.0)
        let b = Sphere(center: .zero, radius: 0.75)
        let frame = Transform(position: Vector3(1.25, 0, 0))

        XCTAssertTrue(CollisionAlgorithms.intersects(a, b, frame: frame))
        XCTAssertEqual(try firstContact(a, b, frame: frame).penetrationDepth,
                       0.5,
                       accuracy: 1.0e-9)
        XCTAssertEqual(try firstContact(b, a, frame: frame.inverted()).penetrationDepth,
                       0.5,
                       accuracy: 1.0e-9)
    }

    func testSphereCapsuleOverlap() throws {
        let sphere = Sphere(center: .zero, radius: 0.25)
        let capsule = Capsule(radius: 0.25, height: 2.0)

        let overlapping = Transform(position: Vector3(0.4, 0, 0))
        XCTAssertTrue(CollisionAlgorithms.intersects(sphere, capsule, frame: overlapping))
        XCTAssertEqual(try firstContact(sphere, capsule, frame: overlapping).penetrationDepth,
                       0.1,
                       accuracy: 1.0e-9)

        let separated = Transform(position: Vector3(0.6, 0, 0))
        XCTAssertFalse(CollisionAlgorithms.intersects(sphere, capsule, frame: separated))
        XCTAssertNil(CollisionAlgorithms.contactManifold(sphere, capsule, frame: separated))
    }

    func testConvexGJKOverlapForCylinderCone() {
        let cylinder = Cylinder(radius: 0.5, height: 1.0)
        let cone = Cone(radius: 0.5, height: 1.0)

        let overlapping = Transform(position: Vector3(0.2, 0, 0))
        XCTAssertTrue(CollisionAlgorithms.intersects(cylinder, cone, frame: overlapping))
        XCTAssertNotNil(CollisionAlgorithms.contactManifold(cylinder,
                                                             cone,
                                                             frame: overlapping))

        let separated = Transform(position: Vector3(2.0, 0, 0))
        XCTAssertFalse(CollisionAlgorithms.intersects(cylinder, cone, frame: separated))
    }

    func testConvexHullOverlapUsesSupportMap() {
        let box = Box(halfExtents: Vector3(0.5, 0.5, 0.5))
        let hull = cubeHull()

        XCTAssertTrue(hull.isValid)
        XCTAssertFalse(ConvexHull().isValid)
        XCTAssertFalse(CollisionAlgorithms.intersects(box, ConvexHull()))

        let overlapping = Transform(position: Vector3(0.75, 0, 0))
        XCTAssertTrue(CollisionAlgorithms.intersects(box, hull, frame: overlapping))
        XCTAssertTrue(CollisionAlgorithms.intersects(hull, hull, frame: overlapping))
        XCTAssertEqual(CollisionAlgorithms.contactManifold(
            box,
            hull,
            frame: overlapping)?.contacts.first?.penetrationDepth ?? -1,
                       0.25,
                       accuracy: 1.0e-6)

        let separated = Transform(position: Vector3(1.25, 0, 0))
        XCTAssertFalse(CollisionAlgorithms.intersects(box, hull, frame: separated))
        XCTAssertFalse(CollisionAlgorithms.intersects(hull, hull, frame: separated))
    }

    func testConvexHullStaticPlaneOverlap() {
        let hull = cubeHull()
        let plane = StaticPlane(Plane(normal: Vector3(1, 0, 0), point: .zero))

        XCTAssertTrue(CollisionAlgorithms.intersects(hull, plane))

        let separated = Transform(position: Vector3(1, 0, 0))
        XCTAssertFalse(CollisionAlgorithms.intersects(hull, plane, frame: separated))
    }

    func testBoxStaticPlaneOverlap() throws {
        let box = Box(halfExtents: Vector3(1, 1, 1))
        let plane = StaticPlane(Plane(normal: Vector3(1, 0, 0), point: .zero))

        XCTAssertTrue(CollisionAlgorithms.intersects(box, plane))
        XCTAssertEqual(try firstContact(box, plane).penetrationDepth, 1.0, accuracy: 1.0e-9)

        let separated = Transform(position: Vector3(2, 0, 0))
        XCTAssertFalse(CollisionAlgorithms.intersects(box, plane, frame: separated))
        XCTAssertNil(CollisionAlgorithms.contactManifold(box, plane, frame: separated))
    }

    func testStaticPlaneStaticPlaneOverlap() {
        let xPlane = StaticPlane(Plane(normal: Vector3(1, 0, 0), point: .zero))
        let yPlane = StaticPlane(Plane(normal: Vector3(0, 1, 0), point: .zero))
        let oppositeXPlane = StaticPlane(Plane(normal: Vector3(-1, 0, 0), point: .zero))

        XCTAssertTrue(CollisionAlgorithms.intersects(xPlane, yPlane))
        XCTAssertTrue(CollisionAlgorithms.intersects(xPlane, xPlane))
        XCTAssertTrue(CollisionAlgorithms.intersects(xPlane, oppositeXPlane))

        let separated = Transform(position: Vector3(1, 0, 0))
        XCTAssertFalse(CollisionAlgorithms.intersects(xPlane, xPlane, frame: separated))
    }

    func testBoxTriangleMeshOverlap() {
        let box = Box(halfExtents: Vector3(1, 1, 1))
        let mesh = TriangleMesh(storage: TestTriangleMeshStorage([
            Triangle(Vector3(-0.5, -0.5, 0.5),
                     Vector3(0.5, -0.5, 0.5),
                     Vector3(0, 0.5, 0.5))
        ]))

        XCTAssertTrue(CollisionAlgorithms.intersects(box, mesh))
        XCTAssertEqual(CollisionAlgorithms.contactManifold(
            box,
            mesh)?.contacts.first?.penetrationDepth ?? -1,
                       0.5,
                       accuracy: 1.0e-6)

        let separated = Transform(position: Vector3(0, 0, 2))
        XCTAssertFalse(CollisionAlgorithms.intersects(box, mesh, frame: separated))
    }

    func testBuiltInMeshQueriesConvexCandidatesInMeshSpace() {
        let box = Box(halfExtents: Vector3(0.5, 0.5, 0.5))
        let mesh = TriangleMesh(triangles: [
            Triangle(Vector3(-1, -1, 0),
                     Vector3(1, -1, 0),
                     Vector3(0, 1, 0)),
            Triangle(Vector3(99, -1, 0),
                     Vector3(101, -1, 0),
                     Vector3(100, 1, 0)),
        ])

        XCTAssertTrue(CollisionAlgorithms.intersects(box, mesh))
        XCTAssertFalse(CollisionAlgorithms.intersects(
            box,
            mesh,
            frame: Transform(position: Vector3(0, 0, 2))))
    }

    func testMeshMeshOverlapUsesTransformedTriangleCandidates() {
        let a = TriangleMesh(triangles: [
            Triangle(Vector3(-1, -1, 0),
                     Vector3(1, -1, 0),
                     Vector3(0, 1, 0)),
            Triangle(Vector3(49, -1, 0),
                     Vector3(51, -1, 0),
                     Vector3(50, 1, 0)),
        ])
        let b = TriangleMesh(triangles: [
            Triangle(Vector3(-1, -0.5, 0),
                     Vector3(1, -0.5, 0),
                     Vector3(0, 0.5, 0)),
            Triangle(Vector3(99, -1, 0),
                     Vector3(101, -1, 0),
                     Vector3(100, 1, 0)),
        ])
        let rotated = Quaternion(angle: Scalar.pi * 0.5,
                                 axis: Vector3(0, 1, 0))

        XCTAssertTrue(CollisionAlgorithms.intersects(
            a,
            b,
            frame: Transform(orientation: rotated)))
        XCTAssertFalse(CollisionAlgorithms.intersects(
            a,
            b,
            frame: Transform(orientation: rotated,
                             position: Vector3(3, 0, 0))))
    }

    private func firstContact(_ a: any CollisionPrimitive,
                              _ b: any CollisionPrimitive,
                              frame: Transform = .identity,
                              file: StaticString = #filePath,
                              line: UInt = #line) throws -> Contact {
        let manifold = try XCTUnwrap(CollisionAlgorithms.contactManifold(a, b, frame: frame),
                                     file: file,
                                     line: line)
        return try XCTUnwrap(manifold.contacts.first, file: file, line: line)
    }

    private func cubeHull(halfExtent: Scalar = 0.5) -> ConvexHull {
        ConvexHull(vertices: [
            Vector3(-halfExtent, -halfExtent, -halfExtent),
            Vector3(halfExtent, -halfExtent, -halfExtent),
            Vector3(-halfExtent, halfExtent, -halfExtent),
            Vector3(halfExtent, halfExtent, -halfExtent),
            Vector3(-halfExtent, -halfExtent, halfExtent),
            Vector3(halfExtent, -halfExtent, halfExtent),
            Vector3(-halfExtent, halfExtent, halfExtent),
            Vector3(halfExtent, halfExtent, halfExtent)
        ])
    }
}

private final class TestTriangleMeshStorage: TriangleMeshStorage {
    private let triangles: [Triangle]

    init(_ triangles: [Triangle]) {
        self.triangles = triangles
    }

    var bounds: AABB {
        var bounds = AABB()
        for triangle in triangles {
            bounds.combine(triangle.aabb)
        }
        return bounds
    }

    var isValid: Bool {
        triangles.isEmpty == false
    }

    var triangleCount: Int {
        triangles.count
    }

    func triangle(at index: Int) -> Triangle {
        triangles[index]
    }

    func contains(_ point: Vector3) -> Bool {
        false
    }

    func rayTest(_ ray: Ray) -> PrimitiveRayHit? {
        nil
    }
}
