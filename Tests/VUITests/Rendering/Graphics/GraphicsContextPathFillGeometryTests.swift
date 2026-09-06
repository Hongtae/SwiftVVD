import XCTest
import VVD
@testable import VUI

final class GraphicsContextPathFillGeometryTests: XCTestCase {
    private struct ReferencePolygon {
        var vertices: [CGPoint] = []
    }

    private func referenceGeometry(
        path: Path,
        transform: CGAffineTransform,
        pathTransform: CGAffineTransform? = nil
    ) -> (vertices: [Float2], indices: [UInt32]) {
        var polygons: [ReferencePolygon] = []
        var initialPoint: CGPoint?
        var currentPoint: CGPoint?
        var polygon = ReferencePolygon()

        // Keep the reference independent of the scalar interpolation fast path.
        path.forEach { element in
            // Transform enumerated controls, without rebuilding primitive storage.
            // A reflected primitive can enumerate differently after Path.applying.
            var element = element
            if let pathTransform, !pathTransform.isIdentity {
                switch element {
                case .move(let point):
                    element = .move(to: point.applying(pathTransform))
                case .line(let point):
                    element = .line(to: point.applying(pathTransform))
                case .quadCurve(let point, let control):
                    element = .quadCurve(to: point.applying(pathTransform),
                                         control: control.applying(pathTransform))
                case .curve(let point, let control1, let control2):
                    element = .curve(to: point.applying(pathTransform),
                                     control1: control1.applying(pathTransform),
                                     control2: control2.applying(pathTransform))
                case .closeSubpath:
                    break
                }
            }
            switch element {
            case .move(let to):
                polygons.append(polygon)
                polygon = ReferencePolygon()
                initialPoint = to
                currentPoint = to

            case .line(let p1):
                if let p0 = currentPoint {
                    if polygon.vertices.isEmpty {
                        polygon.vertices.append(p0)
                    }
                    polygon.vertices.append(p1)
                }
                currentPoint = p1

            case .quadCurve(let p2, let p1):
                if let p0 = currentPoint {
                    let curve = QuadraticBezier(p0: p0, p1: p1, p2: p2)
                    let length = curve.approximateLength()
                    if length > .ulpOfOne {
                        if polygon.vertices.isEmpty {
                            polygon.vertices.append(p0)
                        }
                        let step = 1.0 / length
                        var t = step
                        while t < 1.0 {
                            polygon.vertices.append(
                                curve.interpolate(CGPoint(x: t, y: t))
                            )
                            t += step
                        }
                        polygon.vertices.append(p2)
                    }
                }
                currentPoint = p2

            case .curve(let p3, let p1, let p2):
                if let p0 = currentPoint {
                    let curve = CubicBezier(
                        p0: p0,
                        p1: p1,
                        p2: p2,
                        p3: p3
                    )
                    let length = curve.approximateLength()
                    if length > .ulpOfOne {
                        if polygon.vertices.isEmpty {
                            polygon.vertices.append(p0)
                        }
                        let step = 1.0 / length
                        var t = step
                        while t < 1.0 {
                            polygon.vertices.append(
                                curve.interpolate(CGPoint(x: t, y: t))
                            )
                            t += step
                        }
                        polygon.vertices.append(p3)
                    }
                }
                currentPoint = p3

            case .closeSubpath:
                polygons.append(polygon)
                polygon = ReferencePolygon()
                currentPoint = initialPoint
            }
        }
        polygons.append(polygon)

        var numVertices = 0
        polygons.forEach {
            numVertices += $0.vertices.count + 2
        }
        var vertexData: [Float2] = []
        vertexData.reserveCapacity(numVertices)

        var indexData: [UInt32] = []
        indexData.reserveCapacity(numVertices * 3)

        polygons.forEach { polygon in
            if polygon.vertices.count < 2 { return }

            let baseIndex = UInt32(vertexData.count)
            var center: Vector2 = .zero
            polygon.vertices.forEach { point in
                let vertex = Vector2(point.applying(transform))
                vertexData.append(vertex.float2)
                center += vertex
            }
            center = center / Scalar(polygon.vertices.count)
            let pivotIndex = UInt32(vertexData.count)
            vertexData.append(center.float2)

            for index in (baseIndex + 1)..<pivotIndex {
                indexData.append(index - 1)
                indexData.append(index)
                indexData.append(pivotIndex)
            }
            indexData.append(pivotIndex - 1)
            indexData.append(baseIndex)
            indexData.append(pivotIndex)
        }
        return (vertexData, indexData)
    }

    private func XCTAssertEqualBits(
        _ lhs: [Float2],
        _ rhs: [Float2],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for (index, pair) in zip(lhs, rhs).enumerated() {
            XCTAssertEqual(
                pair.0.0.bitPattern,
                pair.1.0.bitPattern,
                "vertex \(index) x",
                file: file,
                line: line
            )
            XCTAssertEqual(
                pair.0.1.bitPattern,
                pair.1.1.bitPattern,
                "vertex \(index) y",
                file: file,
                line: line
            )
        }
    }

    private func indexValues(
        _ geometry: GraphicsContext.StencilPathFillGeometry
    ) -> [UInt32] {
        geometry.triangleIndices.withUnsafeBytes {
            Array($0.bindMemory(to: UInt32.self))
        }
    }

    func testStreamingBuilderMatchesPreviousGeometryExactly() {
        var path = Path()
        path.move(to: CGPoint(x: -3, y: 2))
        path.addLine(to: CGPoint(x: 5, y: 1))
        path.addQuadCurve(
            to: CGPoint(x: 7, y: 9),
            control: CGPoint(x: 11, y: -4)
        )
        path.addCurve(
            to: CGPoint(x: -2, y: 6),
            control1: CGPoint(x: 12, y: 13),
            control2: CGPoint(x: -8, y: 15)
        )
        path.closeSubpath()
        path.addLine(to: CGPoint(x: -9, y: -3))
        path.move(to: CGPoint(x: 4, y: 4))
        path.addQuadCurve(
            to: CGPoint(x: 4, y: 4),
            control: CGPoint(x: 4, y: 4)
        )
        path.move(to: CGPoint(x: 20, y: 10))
        path.addLine(to: CGPoint(x: 24, y: 17))

        let transform = CGAffineTransform(
            a: 1.25,
            b: -0.375,
            c: 0.625,
            d: 0.875,
            tx: 13,
            ty: -7
        )
        let expected = referenceGeometry(path: path, transform: transform)
        let actual = GraphicsContext.StencilPathFillGeometry(
            path: path,
            transform: transform
        )

        XCTAssertEqualBits(actual.vertices, expected.vertices)
        XCTAssertEqual(indexValues(actual), expected.indices)
        XCTAssertEqual(actual.indexCount, expected.indices.count)
    }

    func testStreamingBuilderDropsContoursWithFewerThanTwoVertices() {
        var path = Path()
        path.move(to: CGPoint(x: 1, y: 2))
        path.move(to: CGPoint(x: 3, y: 4))
        path.addQuadCurve(
            to: CGPoint(x: 3, y: 4),
            control: CGPoint(x: 3, y: 4)
        )
        path.closeSubpath()

        let geometry = GraphicsContext.StencilPathFillGeometry(
            path: path,
            transform: .identity
        )
        XCTAssertTrue(geometry.vertices.isEmpty)
        XCTAssertTrue(geometry.triangleIndices.isEmpty)
        XCTAssertEqual(geometry.indexCount, 0)
    }

    func testPathTransformMatchesPretransformedPathExactly() {
        var path = Path()
        path.move(to: CGPoint(x: -3, y: 2))
        path.addLine(to: CGPoint(x: 5, y: 1))
        path.addQuadCurve(
            to: CGPoint(x: 7, y: 9),
            control: CGPoint(x: 11, y: -4)
        )
        path.addCurve(
            to: CGPoint(x: -2, y: 6),
            control1: CGPoint(x: 12, y: 13),
            control2: CGPoint(x: -8, y: 15)
        )
        path.closeSubpath()

        let pathTransform = CGAffineTransform(
            translationX: 23,
            y: -11
        ).scaledBy(x: 0.625, y: 0.625)
        let renderTransform = CGAffineTransform(
            a: 1.25,
            b: -0.375,
            c: 0.625,
            d: 0.875,
            tx: 13,
            ty: -7
        )
        let expected = GraphicsContext.StencilPathFillGeometry(
            path: path.applying(pathTransform),
            transform: renderTransform
        )
        let actual = GraphicsContext.StencilPathFillGeometry(
            path: path,
            transform: renderTransform,
            pathTransform: pathTransform
        )

        XCTAssertEqualBits(actual.vertices, expected.vertices)
        XCTAssertEqual(indexValues(actual), indexValues(expected))
        XCTAssertEqual(actual.indexCount, expected.indexCount)
    }

    func testTriangleIndexStorageMatchesPackedUInt32Bytes() {
        typealias Triangle = GraphicsContext.StencilPathFillGeometry.TriangleIndices
        XCTAssertEqual(MemoryLayout<Triangle>.stride, MemoryLayout<UInt32>.stride * 3)
        XCTAssertEqual(MemoryLayout<Triangle>.alignment, MemoryLayout<UInt32>.alignment)

        let triangles: [Triangle] = [
            (0x01020304, 0x11223344, 0x55667788),
            (0x99AABBCC, 0xDDEEFF00, UInt32.max),
        ]
        let expected: [UInt32] = [
            0x01020304, 0x11223344, 0x55667788,
            0x99AABBCC, 0xDDEEFF00, UInt32.max,
        ]
        XCTAssertEqual(
            triangles.withUnsafeBytes { Array($0) },
            expected.withUnsafeBytes { Array($0) }
        )
    }

    func testTriangleIndicesPreserveTopologyAcrossArrayGrowth() {
        var path = Path()
        let counts = [2, 3, 4, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128, 511, 512, 1023, 1024]
        for (contour, count) in counts.enumerated() {
            let y = CGFloat(contour) * 20
            path.move(to: CGPoint(x: -1, y: y))
            for index in 1..<count {
                path.addLine(to: CGPoint(x: CGFloat(index), y: y + CGFloat(index % 17)))
            }
            path.closeSubpath()
        }
        let transform = CGAffineTransform(
            a: 1.25, b: -0.375, c: 0.625, d: 0.875, tx: 13, ty: -7
        )
        let expected = referenceGeometry(path: path, transform: transform)
        let actual = GraphicsContext.StencilPathFillGeometry(path: path, transform: transform)
        let indices = indexValues(actual)

        XCTAssertEqualBits(actual.vertices, expected.vertices)
        XCTAssertEqual(indices, expected.indices)
        XCTAssertEqual(actual.indexCount, expected.indices.count)
        XCTAssertTrue(indices.allSatisfy { $0 < UInt32(actual.vertices.count) })
        XCTAssertEqual(
            actual.triangleIndices.withUnsafeBytes { Array($0) },
            expected.indices.withUnsafeBytes { Array($0) }
        )
    }

    func testScratchGeometryMatchesFreshBuildAcrossChangingInputs() {
        var mixed = Path()
        mixed.move(to: CGPoint(x: -3, y: 2))
        mixed.addCurve(to: CGPoint(x: 7, y: 9),
                       control1: CGPoint(x: 11, y: -4),
                       control2: CGPoint(x: -8, y: 15))
        mixed.addQuadCurve(to: CGPoint(x: -2, y: 6), control: CGPoint(x: 12, y: 13))
        mixed.closeSubpath()
        mixed.addLine(to: CGPoint(x: -9, y: -3))
        var degenerate = Path()
        degenerate.move(to: CGPoint(x: 4, y: 4))
        degenerate.addQuadCurve(to: CGPoint(x: 4, y: 4), control: CGPoint(x: 4, y: 4))
        degenerate.closeSubpath()
        let paths = [mixed, Path(), Path(ellipseIn: CGRect(x: 1, y: -2, width: 31, height: 17)),
                     degenerate, Path(CGRect(x: -5, y: 3, width: 2, height: 8))]
        let transforms: [CGAffineTransform] = [
            .identity,
            .init(a: 1.25, b: -0.375, c: 0.625, d: 0.875, tx: 13, ty: -7),
            .init(scaleX: -1, y: 0),
        ]
        let pathTransforms: [CGAffineTransform?] = [
            nil, .identity,
            .init(translationX: 23.25, y: -11.75).scaledBy(x: 0.625, y: 0.625),
            .init(translationX: -100.125, y: 200.75).scaledBy(x: 1.75, y: -0.5),
        ]
        let scratch = GraphicsContext.StencilPathGeometryScratch()
        for transform in transforms {
            for pathTransform in pathTransforms {
                for path in paths {
                    let expected = referenceGeometry(
                        path: path,
                        transform: transform,
                        pathTransform: pathTransform
                    )
                    let actual = scratch.makeGeometry(
                        path: path, transform: transform, pathTransform: pathTransform
                    )
                    XCTAssertEqualBits(actual.vertices, expected.vertices)
                    XCTAssertEqual(indexValues(actual), expected.indices)
                }
            }
        }
    }

    func testScratchGeometryReusesUniqueArrayStorage() {
        let scratch = GraphicsContext.StencilPathGeometryScratch()
        var large = Path()
        large.move(to: .zero)
        for index in 1..<4096 {
            large.addLine(to: CGPoint(x: index, y: index % 17))
        }
        large.closeSubpath()
        func storageAddresses(_ path: Path) -> (UInt, UInt) {
            let geometry = scratch.makeGeometry(path: path, transform: .identity)
            return (
                geometry.vertices.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) },
                geometry.triangleIndices.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
            )
        }
        let initial = storageAddresses(large)
        let reused = storageAddresses(Path(CGRect(x: 1, y: 2, width: 3, height: 4)))
        XCTAssertEqual(initial.0, reused.0)
        XCTAssertEqual(initial.1, reused.1)
        let empty = scratch.makeGeometry(path: Path(), transform: .identity)
        XCTAssertTrue(empty.vertices.isEmpty)
        XCTAssertTrue(empty.triangleIndices.isEmpty)
    }

    func testScratchGeometryPreservesRetainedSnapshots() {
        let scratch = GraphicsContext.StencilPathGeometryScratch()
        let first = scratch.makeGeometry(
            path: Path(ellipseIn: CGRect(x: 1, y: 2, width: 31, height: 17)),
            transform: .identity
        )
        let expectedVertices = first.vertices.withUnsafeBytes { Array($0) }
        let expectedIndices = first.triangleIndices.withUnsafeBytes { Array($0) }
        let second = scratch.makeGeometry(
            path: Path(CGRect(x: -10, y: -20, width: 3, height: 4)),
            transform: .init(translationX: 19, y: 23)
        )
        let secondVertices = second.vertices.withUnsafeBytes { Array($0) }
        _ = scratch.makeGeometry(path: Path(), transform: .identity)
        XCTAssertEqual(first.vertices.withUnsafeBytes { Array($0) }, expectedVertices)
        XCTAssertEqual(first.triangleIndices.withUnsafeBytes { Array($0) }, expectedIndices)
        XCTAssertEqual(second.vertices.withUnsafeBytes { Array($0) }, secondVertices)
    }

    func testGeometrySnapshotDoesNotRetainScratchOwner() {
        weak var weakScratch: GraphicsContext.StencilPathGeometryScratch?
        let path = Path(CGRect(x: 1, y: 2, width: 3, height: 4))
        let geometry = {
            let scratch = GraphicsContext.StencilPathGeometryScratch()
            weakScratch = scratch
            return scratch.makeGeometry(path: path, transform: .identity)
        }()
        XCTAssertNil(weakScratch)
        let expected = referenceGeometry(path: path, transform: .identity)
        XCTAssertEqualBits(geometry.vertices, expected.vertices)
        XCTAssertEqual(indexValues(geometry), expected.indices)
    }
}
