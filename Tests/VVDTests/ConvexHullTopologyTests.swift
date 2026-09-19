//
//  File: ConvexHullTopologyTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class ConvexHullTopologyTests: XCTestCase {
    func testVertexCloudRemainsValidWithoutSurfaceQueries() {
        let hull = ConvexHull(vertices: cubeVertices())

        XCTAssertTrue(hull.isValid)
        XCTAssertFalse(hull.hasSurfaceTopology)
        XCTAssertTrue(hull.faces.isEmpty)
        XCTAssertFalse(hull.contains(.zero))
        XCTAssertNil(hull.rayTest(
            Ray(origin: Vector3(-2, 0, 0), direction: Vector3(1, 0, 0))))
    }

    func testClosedOutwardTopologySupportsContainment() {
        let hull = cubeHull()

        XCTAssertTrue(hull.isValid)
        XCTAssertTrue(hull.hasSurfaceTopology)
        XCTAssertEqual(hull.faces.count, 6)
        XCTAssertTrue(hull.contains(.zero))
        XCTAssertTrue(hull.contains(Vector3(1, 0.5, -0.5)))
        XCTAssertTrue(hull.contains(Vector3(1, 1, 1)))
        XCTAssertFalse(hull.contains(Vector3(1.01, 0, 0)))
    }

    func testRayHitReportsEntryAndInsideExitFromFacePlanes() throws {
        let hull = cubeHull()

        let entry = try XCTUnwrap(hull.rayTest(
            Ray(origin: Vector3(-3, 0, 0), direction: Vector3(2, 0, 0))))
        XCTAssertEqual(entry.parameter, 1, accuracy: 1.0e-9)
        XCTAssertEqual(entry.position, Vector3(-1, 0, 0))
        XCTAssertEqual(entry.normal, Vector3(-1, 0, 0))

        let exit = try XCTUnwrap(hull.rayTest(
            Ray(origin: .zero, direction: Vector3(0, 4, 0))))
        XCTAssertEqual(exit.parameter, 0.25, accuracy: 1.0e-9)
        XCTAssertEqual(exit.position, Vector3(0, 1, 0))
        XCTAssertEqual(exit.normal, Vector3(0, 1, 0))
    }

    func testTriangulatedTopologyIsAccepted() {
        let quadFaces = cubeFaces()
        let triangleFaces = quadFaces.flatMap { face in
            [[face[0], face[1], face[2]], [face[0], face[2], face[3]]]
        }
        let hull = ConvexHull(vertices: cubeVertices(), faces: triangleFaces)

        XCTAssertTrue(hull.isValid)
        XCTAssertTrue(hull.hasSurfaceTopology)
        XCTAssertTrue(hull.contains(.zero))
    }

    func testOpenInwardAndOutOfRangeTopologyIsInvalid() {
        let vertices = cubeVertices()
        let faces = cubeFaces()
        let open = ConvexHull(vertices: vertices,
                              faces: Array(faces.dropLast()))
        var inwardFaces = faces
        inwardFaces[0].reverse()
        let inward = ConvexHull(vertices: vertices, faces: inwardFaces)
        var outOfRangeFaces = faces
        outOfRangeFaces[0][0] = vertices.count
        let outOfRange = ConvexHull(vertices: vertices,
                                    faces: outOfRangeFaces)

        for hull in [open, inward, outOfRange] {
            XCTAssertFalse(hull.isValid)
            XCTAssertFalse(hull.hasSurfaceTopology)
            XCTAssertFalse(hull.contains(.zero))
            XCTAssertNil(hull.rayTest(
                Ray(origin: Vector3(-2, 0, 0), direction: Vector3(1, 0, 0))))
        }
    }

    private func cubeHull() -> ConvexHull {
        ConvexHull(vertices: cubeVertices(), faces: cubeFaces())
    }

    private func cubeVertices() -> [Vector3] {
        [
            Vector3(-1, -1, -1), // 0
            Vector3(1, -1, -1),  // 1
            Vector3(-1, 1, -1),  // 2
            Vector3(1, 1, -1),   // 3
            Vector3(-1, -1, 1),  // 4
            Vector3(1, -1, 1),   // 5
            Vector3(-1, 1, 1),   // 6
            Vector3(1, 1, 1),    // 7
        ]
    }

    private func cubeFaces() -> [[Int]] {
        [
            [1, 3, 7, 5], // +X
            [0, 4, 6, 2], // -X
            [2, 6, 7, 3], // +Y
            [0, 1, 5, 4], // -Y
            [4, 5, 7, 6], // +Z
            [0, 2, 3, 1], // -Z
        ]
    }
}
