//
//  File: RigidBodyMassPropertiesTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class RigidBodyMassPropertiesTests: XCTestCase {
    func testBoxAndOffsetSphereUseAnalyticMassProperties() throws {
        let box = try XCTUnwrap(RigidBodyMassProperties(
            primitive: Box(halfExtents: Vector3(1, 2, 3)),
            density: 0.5))
        XCTAssertEqual(box.mass, 24, accuracy: 1.0e-9)
        XCTAssertEqual(box.centerOfMass, .zero)
        assertDiagonal(box.inertiaTensor, Vector3(104, 80, 40))

        let sphere = try XCTUnwrap(RigidBodyMassProperties(
            primitive: Sphere(center: Vector3(2, -1, 3), radius: 2),
            density: 3))
        let sphereMass = Scalar(32) * Scalar.pi
        XCTAssertEqual(sphere.mass, sphereMass, accuracy: 1.0e-9)
        XCTAssertEqual(sphere.centerOfMass, Vector3(2, -1, 3))
        assertDiagonal(sphere.inertiaTensor,
                       Vector3(repeating: Scalar(1.6) * sphereMass))
    }

    func testAxialPrimitiveMassPropertiesUseTheirCentersOfMass() throws {
        let cylinder = try XCTUnwrap(RigidBodyMassProperties(
            primitive: Cylinder(radius: 2, height: 4),
            density: 1))
        let cylinderMass = Scalar(16) * Scalar.pi
        XCTAssertEqual(cylinder.mass, cylinderMass, accuracy: 1.0e-9)
        XCTAssertEqual(cylinder.centerOfMass, .zero)
        assertDiagonal(cylinder.inertiaTensor,
                       Vector3(cylinderMass * Scalar(7.0 / 3.0),
                               cylinderMass * 2,
                               cylinderMass * Scalar(7.0 / 3.0)))

        let cone = try XCTUnwrap(RigidBodyMassProperties(
            primitive: Cone(radius: 2, height: 4),
            density: 1))
        let coneMass = Scalar(16.0 / 3.0) * Scalar.pi
        XCTAssertEqual(cone.mass, coneMass, accuracy: 1.0e-9)
        XCTAssertEqual(cone.centerOfMass, Vector3(0, -1, 0))
        assertDiagonal(cone.inertiaTensor,
                       Vector3(coneMass * Scalar(1.2),
                               coneMass * Scalar(1.2),
                               coneMass * Scalar(1.2)))

        let capsule = try XCTUnwrap(RigidBodyMassProperties(
            primitive: Capsule(radius: 2, height: 0),
            density: 3))
        let sphere = try XCTUnwrap(RigidBodyMassProperties(
            primitive: Sphere(center: .zero, radius: 2),
            density: 3))
        XCTAssertEqual(capsule.mass, sphere.mass, accuracy: 1.0e-9)
        assertMatrix(capsule.inertiaTensor,
                     equals: sphere.inertiaTensor)
    }

    func testClosedHullAndMeshMatchAnalyticBox() throws {
        let vertices = cubeVertices()
        let faces = cubeFaces()
        let box = try XCTUnwrap(RigidBodyMassProperties(
            primitive: Box(halfExtents: Vector3(1, 2, 3)),
            density: 2))
        let hull = try XCTUnwrap(RigidBodyMassProperties(
            primitive: ConvexHull(vertices: vertices, faces: faces),
            density: 2))
        let triangles = faces.flatMap { face -> [Triangle] in
            let first = vertices[face[0]]
            return (1..<(face.count - 1)).map {
                Triangle(first, vertices[face[$0]], vertices[face[$0 + 1]])
            }
        }
        let mesh = try XCTUnwrap(RigidBodyMassProperties(
            primitive: TriangleMesh(triangles: triangles),
            density: 2))
        let inwardMesh = try XCTUnwrap(RigidBodyMassProperties(
            primitive: TriangleMesh(triangles: triangles.map {
                Triangle($0.p0, $0.p2, $0.p1)
            }),
            density: 2))

        for properties in [hull, mesh, inwardMesh] {
            XCTAssertEqual(properties.mass, box.mass, accuracy: 1.0e-8)
            XCTAssertEqual(properties.centerOfMass.x, 0, accuracy: 1.0e-9)
            XCTAssertEqual(properties.centerOfMass.y, 0, accuracy: 1.0e-9)
            XCTAssertEqual(properties.centerOfMass.z, 0, accuracy: 1.0e-9)
            assertMatrix(properties.inertiaTensor,
                         equals: box.inertiaTensor,
                         accuracy: 1.0e-8)
        }

        XCTAssertNil(RigidBodyMassProperties(
            primitive: TriangleMesh(triangles: Array(triangles.dropLast())),
            density: 2))
    }

    func testCompoundCombinesLeafMassAndParallelAxisTerms() throws {
        let compound = CompoundPrimitive(children: [
            .init(Sphere(center: .zero, radius: 1),
                  transform: Transform(position: Vector3(-2, 0, 0))),
            .init(Sphere(center: .zero, radius: 1),
                  transform: Transform(position: Vector3(1, 0, 0))),
        ])
        let properties = try XCTUnwrap(RigidBodyMassProperties(
            primitive: compound,
            density: 1))
        let leafMass = Scalar(4.0 / 3.0) * Scalar.pi

        XCTAssertEqual(properties.mass, leafMass * 2, accuracy: 1.0e-9)
        XCTAssertEqual(properties.centerOfMass, Vector3(-0.5, 0, 0))
        assertDiagonal(properties.inertiaTensor,
                       Vector3(Scalar(0.8) * leafMass,
                               Scalar(5.3) * leafMass,
                               Scalar(5.3) * leafMass),
                       accuracy: 1.0e-8)
    }

    func testCompoundPreservesRotatedFullInertiaTensor() throws {
        let rotation = Quaternion(angle: Scalar.pi * 0.25,
                                  axis: Vector3(0, 0, 1))
        let compound = CompoundPrimitive(children: [
            .init(Box(halfExtents: Vector3(1, 2, 3)),
                  transform: Transform(orientation: rotation,
                                       position: Vector3(4, 5, 6))),
        ])
        let properties = try XCTUnwrap(RigidBodyMassProperties(
            primitive: compound,
            density: 1))

        XCTAssertEqual(properties.mass, 48, accuracy: 1.0e-9)
        XCTAssertEqual(properties.centerOfMass, Vector3(4, 5, 6))
        XCTAssertEqual(properties.inertiaTensor.m11, 184, accuracy: 1.0e-8)
        XCTAssertEqual(properties.inertiaTensor.m22, 184, accuracy: 1.0e-8)
        XCTAssertEqual(properties.inertiaTensor.m12, 24, accuracy: 1.0e-8)
        XCTAssertEqual(properties.inertiaTensor.m21, 24, accuracy: 1.0e-8)
        XCTAssertEqual(properties.inertiaTensor.m33, 80, accuracy: 1.0e-8)

        let product = properties.inertiaTensor *
            properties.inverseInertiaTensor
        assertMatrix(product, equals: .identity, accuracy: 1.0e-8)
    }

    func testUnsupportedAndZeroVolumePrimitivesDoNotDeriveMass() {
        XCTAssertNil(RigidBodyMassProperties(
            primitive: StaticPlane(Plane(normal: Vector3(0, 1, 0),
                                         point: .zero)),
            density: 1))
        XCTAssertNil(RigidBodyMassProperties(
            primitive: ConvexHull(vertices: cubeVertices()),
            density: 1))
        XCTAssertNil(RigidBodyMassProperties(
            primitive: Box(halfExtents: Vector3(1, 0, 1)),
            density: 1))
        XCTAssertNil(RigidBodyMassProperties(
            primitive: Sphere(center: .zero, radius: 1),
            density: 0))
    }

    func testRigidBodyCanDeriveAndRecalculateMassProperties() throws {
        let body = try XCTUnwrap(RigidBody(
            primitive: Sphere(center: .zero, radius: 1),
            density: 2))
        let originalMass = body.massProperties.mass
        body.collider.primitive = Sphere(center: Vector3(1, 0, 0), radius: 2)

        XCTAssertTrue(body.recalculateMassProperties(density: 2))
        XCTAssertEqual(body.massProperties.mass,
                       originalMass * 8,
                       accuracy: 1.0e-9)
        XCTAssertEqual(body.massProperties.centerOfMass, Vector3(1, 0, 0))

        let rotatedBody = try XCTUnwrap(RigidBody(
            primitive: Box(halfExtents: Vector3(1, 2, 3)),
            density: 1,
            transform: Transform(
                orientation: Quaternion(angle: Scalar.pi * 0.5,
                                        axis: Vector3(0, 0, 1)))))
        let localInverse = rotatedBody.inverseInertiaTensor
        let worldInverse = rotatedBody.worldInverseInertiaTensor
        XCTAssertEqual(worldInverse.m11, localInverse.m22, accuracy: 1.0e-9)
        XCTAssertEqual(worldInverse.m22, localInverse.m11, accuracy: 1.0e-9)
        XCTAssertEqual(worldInverse.m33, localInverse.m33, accuracy: 1.0e-9)
    }

    private func assertDiagonal(
        _ matrix: Matrix3,
        _ diagonal: Vector3,
        accuracy: Scalar = 1.0e-9,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertMatrix(matrix,
                     equals: Matrix3(diagonal.x, 0, 0,
                                     0, diagonal.y, 0,
                                     0, 0, diagonal.z),
                     accuracy: accuracy,
                     file: file,
                     line: line)
    }

    private func assertMatrix(
        _ matrix: Matrix3,
        equals expected: Matrix3,
        accuracy: Scalar = 1.0e-9,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for row in 0..<3 {
            for column in 0..<3 {
                XCTAssertEqual(matrix[row, column],
                               expected[row, column],
                               accuracy: accuracy,
                               file: file,
                               line: line)
            }
        }
    }

    private func cubeVertices() -> [Vector3] {
        [
            Vector3(-1, -2, -3), Vector3(1, -2, -3),
            Vector3(-1, 2, -3), Vector3(1, 2, -3),
            Vector3(-1, -2, 3), Vector3(1, -2, 3),
            Vector3(-1, 2, 3), Vector3(1, 2, 3),
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

private extension Vector3 {
    init(repeating value: Scalar) {
        self.init(value, value, value)
    }
}
