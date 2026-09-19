//
//  File: PrimitiveClosestPointTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class PrimitiveClosestPointTests: XCTestCase {
    func testBoxClosestPointHandlesExteriorCornerAndInteriorFace() throws {
        let box = Box(halfExtents: Vector3(1, 2, 3))

        let exterior = try XCTUnwrap(box.closestPoint(
            to: Vector3(2, 4, 3)))
        XCTAssertEqual(exterior.position, Vector3(1, 2, 3))
        XCTAssertEqual(exterior.normal,
                       Vector3(1, 2, 0).normalized())
        XCTAssertEqual(exterior.distance, Scalar(5).squareRoot(),
                       accuracy: 1.0e-9)

        let interior = try XCTUnwrap(box.closestPoint(to: .zero))
        XCTAssertEqual(interior.position, Vector3(1, 0, 0))
        XCTAssertEqual(interior.normal, Vector3(1, 0, 0))
        XCTAssertEqual(interior.distance, 1, accuracy: 1.0e-9)
    }

    func testSphereAndCapsuleReturnNearestClosedSurface() throws {
        let sphere = Sphere(center: Vector3(1, 0, 0), radius: 2)
        let sphereCenter = try XCTUnwrap(sphere.closestPoint(
            to: Vector3(1, 0, 0)))
        XCTAssertEqual(sphereCenter.position, Vector3(3, 0, 0))
        XCTAssertEqual(sphereCenter.normal, Vector3(1, 0, 0))
        XCTAssertEqual(sphereCenter.distance, 2, accuracy: 1.0e-9)

        let capsule = Capsule(radius: 1, height: 2)
        let cap = try XCTUnwrap(capsule.closestPoint(
            to: Vector3(0, 3, 0)))
        XCTAssertEqual(cap.position, Vector3(0, 2, 0))
        XCTAssertEqual(cap.normal, Vector3(0, 1, 0))
        XCTAssertEqual(cap.distance, 1, accuracy: 1.0e-9)

        let axis = try XCTUnwrap(capsule.closestPoint(to: .zero))
        XCTAssertEqual(axis.position, Vector3(1, 0, 0))
        XCTAssertEqual(axis.normal, Vector3(1, 0, 0))
        XCTAssertEqual(axis.distance, 1, accuracy: 1.0e-9)
    }

    func testCylinderChoosesSideCapAndRim() throws {
        let cylinder = Cylinder(radius: 2, height: 4)

        let side = try XCTUnwrap(cylinder.closestPoint(
            to: Vector3(0.5, 0, 0)))
        XCTAssertEqual(side.position, Vector3(2, 0, 0))
        XCTAssertEqual(side.normal, Vector3(1, 0, 0))
        XCTAssertEqual(side.distance, 1.5, accuracy: 1.0e-9)

        let cap = try XCTUnwrap(cylinder.closestPoint(
            to: Vector3(0, 1.75, 0)))
        XCTAssertEqual(cap.position, Vector3(0, 2, 0))
        XCTAssertEqual(cap.normal, Vector3(0, 1, 0))
        XCTAssertEqual(cap.distance, 0.25, accuracy: 1.0e-9)

        let rim = try XCTUnwrap(cylinder.closestPoint(
            to: Vector3(3, 3, 0)))
        XCTAssertEqual(rim.position, Vector3(2, 2, 0))
        XCTAssertEqual(rim.normal, Vector3(1, 1, 0).normalized())
        XCTAssertEqual(rim.distance, Scalar(2).squareRoot(),
                       accuracy: 1.0e-9)
    }

    func testConeChoosesLateralBaseAndDegenerateAxis() throws {
        let cone = Cone(radius: 1, height: 2)
        let lateralNormal = Vector3(1, 0.5, 0).normalized()
        let lateralQuery = Vector3(0.5, 0, 0) + lateralNormal * 2
        let lateral = try XCTUnwrap(cone.closestPoint(to: lateralQuery))
        XCTAssertEqual(lateral.position.x, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(lateral.position.y, 0, accuracy: 1.0e-9)
        XCTAssertEqual(lateral.position.z, 0, accuracy: 1.0e-9)
        XCTAssertEqual(lateral.normal, lateralNormal)
        XCTAssertEqual(lateral.distance, 2, accuracy: 1.0e-9)

        let base = try XCTUnwrap(cone.closestPoint(to: Vector3(0, -2, 0)))
        XCTAssertEqual(base.position, Vector3(0, -1, 0))
        XCTAssertEqual(base.normal, Vector3(0, -1, 0))
        XCTAssertEqual(base.distance, 1, accuracy: 1.0e-9)

        let axis = try XCTUnwrap(Cone(radius: 0, height: 2)
            .closestPoint(to: Vector3(2, 0.25, 0)))
        XCTAssertEqual(axis.position, Vector3(0, 0.25, 0))
        XCTAssertEqual(axis.normal, Vector3(1, 0, 0))
        XCTAssertEqual(axis.distance, 2, accuracy: 1.0e-9)
    }

    func testStaticPlanePreservesDeclaredNormalOrientation() throws {
        let plane = StaticPlane(Plane(normal: Vector3(0, 2, 0),
                                      point: Vector3(0, 1, 0)))
        let above = try XCTUnwrap(plane.closestPoint(to: Vector3(2, 4, 3)))
        let below = try XCTUnwrap(plane.closestPoint(to: Vector3(2, -2, 3)))

        XCTAssertEqual(above.position, Vector3(2, 1, 3))
        XCTAssertEqual(above.normal, Vector3(0, 1, 0))
        XCTAssertEqual(above.distance, 3, accuracy: 1.0e-9)
        XCTAssertEqual(below.position, Vector3(2, 1, 3))
        XCTAssertEqual(below.normal, Vector3(0, 1, 0))
        XCTAssertEqual(below.distance, 3, accuracy: 1.0e-9)
    }

    func testTriangleClosestPointCoversFaceEdgeAndDegenerateGeometry() {
        let triangle = Triangle(Vector3(0, 0, 0),
                                Vector3(2, 0, 0),
                                Vector3(0, 2, 0))
        XCTAssertEqual(triangle.closestPoint(to: Vector3(0.5, 0.5, 3)),
                       Vector3(0.5, 0.5, 0))
        XCTAssertEqual(triangle.closestPoint(to: Vector3(2, 2, 0)),
                       Vector3(1, 1, 0))

        let degenerate = Triangle(Vector3(0, 0, 0),
                                  Vector3(2, 0, 0),
                                  Vector3(4, 0, 0))
        XCTAssertEqual(degenerate.closestPoint(to: Vector3(3, 1, 0)),
                       Vector3(3, 0, 0))
    }

    func testHullRequiresSurfaceTopologyForClosestPoint() throws {
        let vertices = cubeVertices()
        XCTAssertNil(ConvexHull(vertices: vertices)
            .closestPoint(to: Vector3(3, 0.25, -0.5)))

        let closest = try XCTUnwrap(ConvexHull(vertices: vertices,
                                               faces: cubeFaces())
            .closestPoint(to: Vector3(3, 0.25, -0.5)))
        XCTAssertEqual(closest.position, Vector3(1, 0.25, -0.5))
        XCTAssertEqual(closest.normal, Vector3(1, 0, 0))
        XCTAssertEqual(closest.distance, 2, accuracy: 1.0e-9)
    }

    func testMeshUsesClosestValidTriangleAndWindingNormal() throws {
        let mesh = TriangleMesh(triangles: [
            Triangle(Vector3(0, 0, 10),
                     Vector3(1, 0, 10),
                     Vector3(0, 1, 10)),
            Triangle(Vector3(0, 0, 0),
                     Vector3(1, 0, 0),
                     Vector3(0, 1, 0)),
        ])

        let closest = try XCTUnwrap(mesh.closestPoint(
            to: Vector3(0.25, 0.25, 2)))
        XCTAssertEqual(closest.position, Vector3(0.25, 0.25, 0))
        XCTAssertEqual(closest.normal, Vector3(0, 0, 1))
        XCTAssertEqual(closest.distance, 2, accuracy: 1.0e-9)
    }

    func testCompoundTransformsClosestLeafGeometry() throws {
        let nested = CompoundPrimitive(children: [
            .init(CompoundPrimitive(children: [
                .init(Box(halfExtents: Vector3(1, 0.5, 0.5)),
                      transform: Transform(
                        orientation: Quaternion(angle: Scalar.pi * 0.5,
                                                axis: Vector3(0, 0, 1)),
                        position: Vector3(2, 0, 0))),
            ]), transform: Transform(position: Vector3(1, 0, 0))),
            .init(Sphere(center: .zero, radius: 0.5),
                  transform: Transform(position: Vector3(20, 0, 0))),
        ])

        let closest = try XCTUnwrap(nested.closestPoint(
            to: Vector3(3, 2, 0)))
        XCTAssertEqual(closest.position.x, 3, accuracy: 1.0e-9)
        XCTAssertEqual(closest.position.y, 1, accuracy: 1.0e-9)
        XCTAssertEqual(closest.position.z, 0, accuracy: 1.0e-9)
        XCTAssertEqual(closest.normal.x, 0, accuracy: 1.0e-9)
        XCTAssertEqual(closest.normal.y, 1, accuracy: 1.0e-9)
        XCTAssertEqual(closest.normal.z, 0, accuracy: 1.0e-9)
        XCTAssertEqual(closest.distance, 1, accuracy: 1.0e-9)
    }

    func testShapeForwardsClosestPointAndInvalidPrimitiveReturnsNil() throws {
        let shape = SphereShape(Sphere(center: .zero, radius: 1))
        let closest = try XCTUnwrap(shape.closestPoint(to: Vector3(3, 0, 0)))
        XCTAssertEqual(closest.position, Vector3(1, 0, 0))
        XCTAssertEqual(closest.distance, 2, accuracy: 1.0e-9)
        XCTAssertNil(Sphere().closestPoint(to: .zero))
        XCTAssertNil(TriangleMesh().closestPoint(to: .zero))
        XCTAssertNil(CompoundPrimitive().closestPoint(to: .zero))
    }

    private func cubeVertices() -> [Vector3] {
        [
            Vector3(-1, -1, -1), Vector3(1, -1, -1),
            Vector3(-1, 1, -1), Vector3(1, 1, -1),
            Vector3(-1, -1, 1), Vector3(1, -1, 1),
            Vector3(-1, 1, 1), Vector3(1, 1, 1),
        ]
    }

    private func cubeFaces() -> [[Int]] {
        [
            [1, 3, 7, 5], [0, 4, 6, 2],
            [2, 6, 7, 3], [0, 1, 5, 4],
            [4, 5, 7, 6], [0, 2, 3, 1],
        ]
    }
}
