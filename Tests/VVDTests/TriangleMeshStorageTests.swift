//
//  File: TriangleMeshStorageTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class TriangleMeshStorageTests: XCTestCase {
    func testArrayStorageBuildsBoundsAndSupportsMeshConstruction() {
        let triangles = cubeTriangles()
        let storage = TriangleArrayMeshStorage(triangles)
        let mesh = TriangleMesh(triangles: triangles)

        XCTAssertTrue(storage.isValid)
        XCTAssertEqual(storage.triangleCount, 12)
        XCTAssertEqual(storage.triangle(at: 0), triangles[0])
        XCTAssertEqual(storage.bounds,
                       AABB(min: Vector3(-1, -1, -1),
                            max: Vector3(1, 1, 1)))
        XCTAssertTrue(mesh.isValid)
        XCTAssertEqual(mesh.triangleCount, 12)
        XCTAssertEqual(mesh.bounds, storage.bounds)
    }

    func testClosedMeshContainsInteriorAndSurfacePoints() {
        let mesh = TriangleMesh(triangles: cubeTriangles())

        XCTAssertTrue(mesh.contains(.zero))
        XCTAssertTrue(mesh.contains(Vector3(1, 0, 0)))
        XCTAssertTrue(mesh.contains(Vector3(1, 1, 1)))
        XCTAssertFalse(mesh.contains(Vector3(2, 0, 0)))
    }

    func testMeshRayHitUsesClosestWindingNormal() throws {
        let mesh = TriangleMesh(triangles: cubeTriangles())

        let entry = try XCTUnwrap(mesh.rayTest(
            Ray(origin: Vector3(-3, 0, 0), direction: Vector3(2, 0, 0))))
        XCTAssertEqual(entry.parameter, 1, accuracy: 1.0e-9)
        XCTAssertEqual(entry.position, Vector3(-1, 0, 0))
        XCTAssertEqual(entry.normal, Vector3(-1, 0, 0))

        let exit = try XCTUnwrap(mesh.rayTest(
            Ray(origin: .zero, direction: Vector3(2, 0, 0))))
        XCTAssertEqual(exit.parameter, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(exit.position, Vector3(1, 0, 0))
        XCTAssertEqual(exit.normal, Vector3(1, 0, 0))
    }

    func testOpenMeshRayHitKeepsTriangleWindingNormal() throws {
        let triangle = Triangle(Vector3(0, -1, -1),
                                Vector3(0, 1, -1),
                                Vector3(0, 0, 1))
        let mesh = TriangleMesh(triangles: [triangle])

        let hit = try XCTUnwrap(mesh.rayTest(
            Ray(origin: Vector3(-1, 0, 0), direction: Vector3(2, 0, 0))))

        XCTAssertEqual(hit.parameter, 0.5, accuracy: 1.0e-9)
        XCTAssertEqual(hit.position, .zero)
        XCTAssertEqual(hit.normal, Vector3(1, 0, 0))
    }

    func testArrayStorageUsesBoundsCandidatesAndSupportsEarlyExit() {
        let triangles = [
            Triangle(Vector3(-1, -1, 0),
                     Vector3(1, -1, 0),
                     Vector3(0, 1, 0)),
            Triangle(Vector3(9, -1, 0),
                     Vector3(11, -1, 0),
                     Vector3(10, 1, 0)),
            Triangle(Vector3(19, -1, 0),
                     Vector3(21, -1, 0),
                     Vector3(20, 1, 0)),
        ]
        let storage = TriangleArrayMeshStorage(triangles)
        var candidates: [Int] = []

        let completed = storage.queryTriangles(
            overlapping: AABB(center: Vector3(10, 0, 0),
                              halfExtents: Vector3(0.5, 0.5, 0.5))) { index in
            candidates.append(index)
            return true
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(candidates, [1])

        var visited = 0
        let stopped = storage.queryTriangles(overlapping: storage.bounds) { _ in
            visited += 1
            return false
        }
        XCTAssertFalse(stopped)
        XCTAssertEqual(visited, 1)
    }

    func testEmptyDegenerateAndMissedMeshesHaveNoHit() {
        let empty = TriangleArrayMeshStorage([])
        let degenerate = TriangleArrayMeshStorage([
            Triangle(.zero, Vector3(1, 0, 0), Vector3(2, 0, 0))
        ])
        let mesh = TriangleMesh(triangles: cubeTriangles())

        XCTAssertFalse(empty.isValid)
        XCTAssertTrue(empty.bounds.isNull)
        XCTAssertFalse(degenerate.isValid)
        XCTAssertNil(mesh.rayTest(
            Ray(origin: Vector3(-3, 3, 0), direction: Vector3(1, 0, 0))))
        XCTAssertNil(mesh.rayTest(Ray(origin: .zero, direction: .zero)))
    }

    private func cubeTriangles() -> [Triangle] {
        let nnn = Vector3(-1, -1, -1)
        let nnp = Vector3(-1, -1, 1)
        let npn = Vector3(-1, 1, -1)
        let npp = Vector3(-1, 1, 1)
        let pnn = Vector3(1, -1, -1)
        let pnp = Vector3(1, -1, 1)
        let ppn = Vector3(1, 1, -1)
        let ppp = Vector3(1, 1, 1)

        return [
            Triangle(pnn, ppn, ppp), Triangle(pnn, ppp, pnp), // +X
            Triangle(nnp, npp, npn), Triangle(nnp, npn, nnn), // -X
            Triangle(npn, npp, ppp), Triangle(npn, ppp, ppn), // +Y
            Triangle(nnp, nnn, pnn), Triangle(nnp, pnn, pnp), // -Y
            Triangle(nnp, pnp, ppp), Triangle(nnp, ppp, npp), // +Z
            Triangle(pnn, nnn, npn), Triangle(pnn, npn, ppn)  // -Z
        ]
    }
}
