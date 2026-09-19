//
//  File: QuantizedBVHTests.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import XCTest
import VVD

final class QuantizedBVHTests: XCTestCase {
    func testUInt16EncodingPreservesNodesAndConservativeLeafBounds() throws {
        let elements = [
            BVH.Element(bounds: AABB(
                min: Vector3(-3.25, -1.5, 2.125),
                max: Vector3(-1.125, 0.25, 4.75)),
                        primitiveIndex: 7),
            BVH.Element(bounds: AABB(
                min: Vector3(0.125, -2.75, -1.625),
                max: Vector3(2.875, 3.5, 0.375)),
                        primitiveIndex: 42),
            BVH.Element(bounds: AABB(
                min: Vector3(5, 1, 1),
                max: Vector3(5, 1, 1)),
                        primitiveIndex: 65_535),
        ]
        let bvh = BVH(elements)
        let quantized = try XCTUnwrap(bvh.quantized16())

        XCTAssertEqual(quantized.format, .uint16)
        XCTAssertEqual(quantized.bounds, bvh.bounds)
        XCTAssertEqual(quantized.nodeCount, bvh.nodeCount)
        XCTAssertEqual(quantized.nodeStride, 16)
        XCTAssertEqual(quantized.byteCount,
                       quantized.nodeCount * quantized.nodeStride)
        XCTAssertEqual(quantized.escapeIndex(at: 0), quantized.nodeCount)
        XCTAssertNil(quantized.primitiveIndex(at: 0))

        var foundIndices: Set<Int> = []
        for nodeIndex in 0..<quantized.nodeCount {
            guard let primitiveIndex = quantized.primitiveIndex(
                at: nodeIndex) else { continue }
            foundIndices.insert(primitiveIndex)
            let original = try XCTUnwrap(elements.first {
                $0.primitiveIndex == primitiveIndex
            }?.bounds)
            let decoded = try XCTUnwrap(quantized.nodeBounds(at: nodeIndex))
            XCTAssertLessThanOrEqual(decoded.min.x, original.min.x)
            XCTAssertLessThanOrEqual(decoded.min.y, original.min.y)
            XCTAssertLessThanOrEqual(decoded.min.z, original.min.z)
            XCTAssertGreaterThanOrEqual(decoded.max.x, original.max.x)
            XCTAssertGreaterThanOrEqual(decoded.max.y, original.max.y)
            XCTAssertGreaterThanOrEqual(decoded.max.z, original.max.z)
            XCTAssertEqual(quantized.escapeIndex(at: nodeIndex),
                           nodeIndex + 1)
        }
        XCTAssertEqual(foundIndices, Set(elements.map(\.primitiveIndex)))

        let byteCount = quantized.withUnsafeBytes { $0.count }
        XCTAssertEqual(byteCount, quantized.byteCount)
    }

    func testQuantizedQueriesContainEveryCPUHierarchyCandidate() throws {
        let elements = (0..<64).map { index in
            let x = Scalar(index % 4) * 2.125 - 3.75
            let y = Scalar((index / 4) % 4) * 1.75 - 2.5
            let z = Scalar(index / 16) * 3.25 - 4.125
            return BVH.Element(
                bounds: AABB(center: Vector3(x, y, z),
                             halfExtents: Vector3(0.3, 0.4, 0.5)),
                primitiveIndex: index)
        }
        let bvh = BVH(elements)
        let quantized = try XCTUnwrap(bvh.quantized16())
        let queries = [
            AABB(center: .zero, halfExtents: Vector3(1, 1, 1)),
            AABB(center: Vector3(2.2, -0.5, 1.75),
                 halfExtents: Vector3(2, 1.5, 3)),
            AABB(center: Vector3(-20, 0, 0),
                 halfExtents: Vector3(0.25, 0.25, 0.25)),
            AABB(center: elements[37].bounds.max,
                 halfExtents: .zero),
        ]

        for query in queries {
            let cpu = Set(bvh.primitiveIndices(overlapping: query))
            let encoded = Set(quantized.primitiveIndices(overlapping: query))
            XCTAssertTrue(cpu.isSubset(of: encoded))
        }

        var visits = 0
        let completed = quantized.query(overlapping: bvh.bounds) { _ in
            visits += 1
            return false
        }
        XCTAssertFalse(completed)
        XCTAssertEqual(visits, 1)
    }

    func testAutomaticFormatFallsBackToUInt32ForLargePrimitiveIndex() throws {
        let bvh = BVH([
            BVH.Element(bounds: AABB(center: .zero,
                                     halfExtents: Vector3(1, 1, 1)),
                        primitiveIndex: 70_000),
        ])

        XCTAssertNil(bvh.quantized16())
        let quantized32 = try XCTUnwrap(bvh.quantized32())
        XCTAssertEqual(quantized32.nodeStride, 32)
        XCTAssertEqual(quantized32.primitiveIndex(at: 0), 70_000)

        let automatic = try XCTUnwrap(bvh.quantized())
        XCTAssertEqual(automatic.format, .uint32)
        XCTAssertEqual(automatic.primitiveIndex(at: 0), 70_000)
    }

    func testNegativePrimitiveIndicesCannotBeEncoded() {
        let bvh = BVH([
            BVH.Element(bounds: AABB(center: .zero,
                                     halfExtents: Vector3(1, 1, 1)),
                        primitiveIndex: -1),
        ])

        XCTAssertNil(bvh.quantized16())
        XCTAssertNil(bvh.quantized32())
    }

    func testEmptyHierarchyProducesEmptyUInt16Encoding() throws {
        let quantized = try XCTUnwrap(BVH().quantized16())

        XCTAssertTrue(quantized.bounds.isNull)
        XCTAssertEqual(quantized.quantizationStep, .zero)
        XCTAssertEqual(quantized.nodeCount, 0)
        XCTAssertEqual(quantized.byteCount, 0)
        XCTAssertNil(quantized.nodeBounds(at: 0))
        XCTAssertTrue(quantized.primitiveIndices(
            overlapping: AABB(center: .zero,
                              halfExtents: Vector3(1, 1, 1))).isEmpty)
    }
}
