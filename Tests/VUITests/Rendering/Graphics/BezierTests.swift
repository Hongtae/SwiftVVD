import XCTest
@testable import VUI
import VVD

final class BezierTests: XCTestCase {
    func testScalarInterpolationMatchesPointArithmeticExactly() {
        let parameters: [CGFloat] = [
            -1, -0.125, -0.0, 0, .leastNonzeroMagnitude,
            .ulpOfOne, 0.125, 0.317, 0.5, 0.875, 1.nextDown, 1, 1.25, 2,
        ]
        let scales: [CGFloat] = [0, 0.000_001, 1, 4096, 1e100]

        for index in 0..<100 {
            let value = CGFloat(index) * 0.173
            for scale in scales {
                let quadratic = QuadraticBezier(
                    p0: CGPoint(x: sin(value) * scale, y: cos(value) * scale),
                    p1: CGPoint(
                        x: cos(value * 1.3) * scale,
                        y: sin(value * 1.7) * scale
                    ),
                    p2: CGPoint(
                        x: sin(value * 2.1) * scale,
                        y: cos(value * 1.9) * scale
                    )
                )
                let cubic = CubicBezier(
                    p0: quadratic.p0,
                    p1: quadratic.p1,
                    p2: quadratic.p2,
                    p3: CGPoint(
                        x: cos(value * 0.9) * scale,
                        y: sin(value * 1.1) * scale
                    )
                )

                for t in parameters {
                    let t2 = t * t
                    let t3 = t2 * t
                    let u = 1.0 - t
                    let u2 = u * u
                    let u3 = u2 * u
                    let expectedQuadratic = (quadratic.p0 * u2)
                        + (quadratic.p1 * u * t * 2) + (quadratic.p2 * t2)
                    let expectedCubic = (cubic.p0 * u3)
                        + (cubic.p1 * t * u2 * 3)
                        + (cubic.p2 * t2 * u * 3) + (cubic.p3 * t3)
                    let actualQuadratic = quadratic.interpolate(t)
                    let actualCubic = cubic.interpolate(t)

                    XCTAssertEqual(
                        actualQuadratic.x.native.bitPattern,
                        expectedQuadratic.x.native.bitPattern
                    )
                    XCTAssertEqual(
                        actualQuadratic.y.native.bitPattern,
                        expectedQuadratic.y.native.bitPattern
                    )
                    XCTAssertEqual(
                        actualCubic.x.native.bitPattern,
                        expectedCubic.x.native.bitPattern
                    )
                    XCTAssertEqual(
                        actualCubic.y.native.bitPattern,
                        expectedCubic.y.native.bitPattern
                    )
                }
            }
        }
    }

    func testCubicBoundingBoxMatchesAllocationBasedReference() {
        let fixtures = [
            CubicBezier(
                p0: CGPoint(x: 0, y: 0),
                p1: CGPoint(x: 1, y: 1),
                p2: CGPoint(x: 2, y: 2),
                p3: CGPoint(x: 3, y: 3)
            ),
            CubicBezier(
                p0: CGPoint(x: -4, y: 3),
                p1: CGPoint(x: 12, y: -18),
                p2: CGPoint(x: -15, y: 21),
                p3: CGPoint(x: 7, y: -2)
            ),
            CubicBezier(
                p0: CGPoint(x: 2, y: -3),
                p1: CGPoint(x: 8, y: 5),
                p2: CGPoint(x: 14, y: -11),
                p3: CGPoint(x: 20, y: 7)
            ),
            CubicBezier(
                p0: CGPoint(x: 5, y: 5),
                p1: CGPoint(x: 5, y: 5),
                p2: CGPoint(x: 5, y: 5),
                p3: CGPoint(x: 5, y: 5)
            ),
        ]

        for curve in fixtures {
            XCTAssertEqual(curve.boundingBox, referenceBoundingBox(curve))
        }

        for index in 0..<1_000 {
            let value = CGFloat(index) * 0.173
            let curve = CubicBezier(
                p0: CGPoint(
                    x: sin(value) * 40,
                    y: cos(value * 0.7) * 30
                ),
                p1: CGPoint(
                    x: cos(value * 1.3) * 70,
                    y: sin(value * 1.7) * 50
                ),
                p2: CGPoint(
                    x: sin(value * 2.1) * 60,
                    y: cos(value * 1.9) * 80
                ),
                p3: CGPoint(
                    x: cos(value * 0.9) * 35,
                    y: sin(value * 1.1) * 45
                )
            )
            XCTAssertEqual(curve.boundingBox, referenceBoundingBox(curve))
        }
    }

    func testApproximateLengthMatchesMaterializedSubdivisionOrder() {
        let subdivisions = [-1, 0, 1, 2, 3, 4, 5]

        for index in 0..<100 {
            let value = CGFloat(index) * 0.317
            let quadratic = QuadraticBezier(
                p0: CGPoint(x: sin(value) * 20, y: cos(value) * 30),
                p1: CGPoint(
                    x: cos(value * 1.7) * 50,
                    y: sin(value * 1.3) * 40
                ),
                p2: CGPoint(
                    x: sin(value * 0.9) * 35,
                    y: cos(value * 2.1) * 25
                )
            )
            let cubic = CubicBezier(
                p0: quadratic.p0,
                p1: quadratic.p1,
                p2: CGPoint(
                    x: cos(value * 0.8) * 45,
                    y: sin(value * 2.3) * 55
                ),
                p3: quadratic.p2
            )

            for subdivision in subdivisions {
                XCTAssertEqual(
                    quadratic.approximateLength(subdivide: subdivision),
                    referenceApproximateLength(
                        quadratic,
                        subdivide: subdivision
                    )
                )
                XCTAssertEqual(
                    cubic.approximateLength(subdivide: subdivision),
                    referenceApproximateLength(
                        cubic,
                        subdivide: subdivision
                    )
                )
            }
        }
    }

    func testOffsetCurveTraversalMatchesMaterializedSubdivisionOrder() {
        let subdivisions = [-1, 0, 1, 2, 3, 4, 5]

        for index in 0..<100 {
            let value = CGFloat(index) * 0.271
            let curve = CubicBezier(
                p0: CGPoint(x: sin(value) * 20, y: cos(value) * 30),
                p1: CGPoint(
                    x: cos(value * 1.7) * 50,
                    y: sin(value * 1.3) * 40
                ),
                p2: CGPoint(
                    x: cos(value * 0.8) * 45,
                    y: sin(value * 2.3) * 55
                ),
                p3: CGPoint(
                    x: sin(value * 0.9) * 35,
                    y: cos(value * 2.1) * 25
                )
            )
            let distance = sin(value * 0.6) * 12

            for subdivision in subdivisions {
                let expected = curve.subdivide(subdivision).map {
                    $0.offset(by: distance)
                }
                var actual: [CubicBezier] = []
                curve.forEachOffsetCurve(
                    by: distance,
                    subdivisions: subdivision
                ) {
                    actual.append($0)
                }

                XCTAssertEqual(actual.count, expected.count)
                for (actual, expected) in zip(actual, expected) {
                    XCTAssertEqual(actual.p0, expected.p0)
                    XCTAssertEqual(actual.p1, expected.p1)
                    XCTAssertEqual(actual.p2, expected.p2)
                    XCTAssertEqual(actual.p3, expected.p3)
                }
            }
        }
    }

    func testLineSegmentIntersectionsMatchAllocationBasedReference() {
        let segments = [
            (CGPoint(x: -30, y: 0), CGPoint(x: 30, y: 0)),
            (CGPoint(x: 0, y: -30), CGPoint(x: 0, y: 30)),
            (CGPoint(x: -25, y: -17), CGPoint(x: 22, y: 19)),
            (CGPoint(x: 30, y: 0), CGPoint(x: -30, y: 0)),
            (CGPoint(x: 4, y: 7), CGPoint(x: 4, y: 7)),
        ]
        let quadraticFixtures = [
            QuadraticBezier(
                p0: CGPoint(x: -12, y: -8),
                p1: CGPoint(x: -2, y: 22),
                p2: CGPoint(x: 12, y: -8)
            ),
            QuadraticBezier(
                p0: .zero,
                p1: .zero,
                p2: .zero
            ),
        ]
        let cubicFixtures = [
            CubicBezier(
                p0: CGPoint(x: -12, y: -8),
                p1: CGPoint(x: -9, y: 25),
                p2: CGPoint(x: 8, y: 5),
                p3: CGPoint(x: 12, y: -8)
            ),
            CubicBezier(
                p0: .zero,
                p1: .zero,
                p2: .zero,
                p3: .zero
            ),
        ]

        for curve in quadraticFixtures {
            for segment in segments {
                assertIntersections(
                    curve.intersectLineSegment(segment.0, segment.1),
                    equal: referenceIntersections(
                        curve,
                        begin: segment.0,
                        end: segment.1
                    )
                )
            }
        }
        for curve in cubicFixtures {
            for segment in segments {
                assertIntersections(
                    curve.intersectLineSegment(segment.0, segment.1),
                    equal: referenceIntersections(
                        curve,
                        begin: segment.0,
                        end: segment.1
                    )
                )
            }
        }

        for index in 0..<1_000 {
            let value = CGFloat(index) * 0.193
            let quadratic = QuadraticBezier(
                p0: CGPoint(
                    x: sin(value) * 30,
                    y: cos(value * 0.7) * 25
                ),
                p1: CGPoint(
                    x: cos(value * 1.3) * 45,
                    y: sin(value * 1.7) * 50
                ),
                p2: CGPoint(
                    x: sin(value * 2.1) * 35,
                    y: cos(value * 1.9) * 40
                )
            )
            let cubic = CubicBezier(
                p0: quadratic.p0,
                p1: quadratic.p1,
                p2: CGPoint(
                    x: cos(value * 0.8) * 55,
                    y: sin(value * 2.3) * 45
                ),
                p3: quadratic.p2
            )
            let horizontalBegin = CGPoint(
                x: -60,
                y: sin(value * 0.4) * 20
            )
            let horizontalEnd = CGPoint(
                x: cos(value * 0.6) * 25 + 30,
                y: horizontalBegin.y
            )
            let diagonalBegin = CGPoint(
                x: sin(value * 0.5) * 35 - 15,
                y: cos(value * 0.9) * 30 - 10
            )
            let diagonalEnd = CGPoint(
                x: cos(value * 1.1) * 30 + 15,
                y: sin(value * 1.5) * 35 + 10
            )

            for segment in [
                (horizontalBegin, horizontalEnd),
                (diagonalBegin, diagonalEnd),
            ] {
                assertIntersections(
                    quadratic.intersectLineSegment(segment.0, segment.1),
                    equal: referenceIntersections(
                        quadratic,
                        begin: segment.0,
                        end: segment.1
                    )
                )
                assertIntersections(
                    cubic.intersectLineSegment(segment.0, segment.1),
                    equal: referenceIntersections(
                        cubic,
                        begin: segment.0,
                        end: segment.1
                    )
                )
            }
        }
    }

    private func referenceBoundingBox(_ bezier: CubicBezier) -> CGRect {
        let threeP0 = bezier.p0 * 3
        let threeP1 = bezier.p1 * 3
        let sixP1 = bezier.p1 * 6
        let threeP2 = bezier.p2 * 3
        let a = bezier.p3 - threeP2 + threeP1 - bezier.p0
        let b = threeP2 - sixP1 + threeP0
        let c = threeP1 - threeP0
        let derivativeA = a * 3
        let derivativeB = b * 2
        let determinant = derivativeB * derivativeB
            - derivativeA * c * 4

        let roots = {
            (a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat) -> [CGFloat] in
            if d < 0 { return [] }
            if a.magnitude < .ulpOfOne {
                if b.magnitude < .ulpOfOne { return [] }
                return [-c / b]
            }
            if d.magnitude < .ulpOfOne { return [-b / (a * 2)] }
            let squareRoot = sqrt(d)
            return [
                (-b + squareRoot) / (a * 2),
                (-b - squareRoot) / (a * 2),
            ]
        }

        let coordinate = {
            (p0: CGFloat, p1: CGFloat, p2: CGFloat, p3: CGFloat, t: CGFloat) in
            let t2 = t * t
            let t3 = t2 * t
            return (p3 - 3 * p2 + 3 * p1 - p0) * t3
                + (3 * p2 - 6 * p1 + 3 * p0) * t2
                + (3 * p1 - 3 * p0) * t
                + p0
        }

        var minX = min(bezier.p0.x, bezier.p3.x)
        var minY = min(bezier.p0.y, bezier.p3.y)
        var maxX = max(bezier.p0.x, bezier.p3.x)
        var maxY = max(bezier.p0.y, bezier.p3.y)

        for t in roots(
            derivativeA.x,
            derivativeB.x,
            c.x,
            determinant.x
        ) where t > 0 && t < 1 {
            let x = coordinate(
                bezier.p0.x,
                bezier.p1.x,
                bezier.p2.x,
                bezier.p3.x,
                t
            )
            minX = min(x, minX)
            maxX = max(x, maxX)
        }

        for t in roots(
            derivativeA.y,
            derivativeB.y,
            c.y,
            determinant.y
        ) where t > 0 && t < 1 {
            let y = coordinate(
                bezier.p0.y,
                bezier.p1.y,
                bezier.p2.y,
                bezier.p3.y,
                t
            )
            minY = min(y, minY)
            maxY = max(y, maxY)
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private func referenceApproximateLength(
        _ bezier: QuadraticBezier,
        subdivide: Int
    ) -> CGFloat {
        bezier.subdivide(subdivide).reduce(into: CGFloat.zero) {
            $0 += $1.lengthOfPointSegments
        } * 0.5
    }

    private func referenceApproximateLength(
        _ bezier: CubicBezier,
        subdivide: Int
    ) -> CGFloat {
        bezier.subdivide(subdivide).reduce(into: CGFloat.zero) {
            $0 += $1.lengthOfPointSegments
        } * 0.5
    }

    private func assertIntersections(
        _ actual: BezierIntersections,
        equal expected: [CGFloat],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for index in 0..<actual.count {
            XCTAssertEqual(actual[index], expected[index], file: file, line: line)
        }
    }

    private func referenceIntersections(
        _ bezier: QuadraticBezier,
        begin: CGPoint,
        end: CGPoint
    ) -> [CGFloat] {
        let Q = end.y * (bezier.p0.x - 2 * bezier.p1.x + bezier.p2.x)
            - begin.y * (bezier.p0.x - 2 * bezier.p1.x + bezier.p2.x)
        let S = begin.x * (bezier.p0.y - 2 * bezier.p1.y + bezier.p2.y)
            - end.x * (bezier.p0.y - 2 * bezier.p1.y + bezier.p2.y)
        let R = end.y * 2 * (bezier.p1.x - bezier.p0.x)
            - begin.y * 2 * (bezier.p1.x - bezier.p0.x)
        let T = begin.x * 2 * (bezier.p1.y - bezier.p0.y)
            - end.x * 2 * (bezier.p1.y - bezier.p0.y)

        let A = S + Q
        let B = R + T
        let C = (end.y - begin.y) * bezier.p0.x
            + (begin.x + end.x) * bezier.p0.y
            + begin.x * (begin.y - end.y)
            + begin.y * (end.x - begin.x)

        let discriminant = sqrt(B * B - (4 * A * C))
        let inverseA2 = 1.0 / (2 * A)
        let roots = [
            (-B + discriminant) * inverseA2,
            (-B - discriminant) * inverseA2,
        ]

        return roots.filter { t in
            if t >= 0 && t <= 1 {
                let point = bezier.interpolate(t)
                let s: CGFloat
                if end.x - begin.x != 0 {
                    s = (point.x - begin.x) / (end.x - begin.x)
                } else {
                    s = (point.y - begin.y) / (end.y - begin.y)
                }
                return s >= 0 && s <= 1
            }
            return false
        }.sorted()
    }

    private func referenceIntersections(
        _ bezier: CubicBezier,
        begin: CGPoint,
        end: CGPoint
    ) -> [CGFloat] {
        let sign: (CGFloat) -> CGFloat = { $0 < 0 ? -1 : 1 }
        let cubicRoots = {
            (a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat) -> [CGFloat] in
            let inverseA = 1.0 / a
            let A = b * inverseA
            let B = c * inverseA
            let C = d * inverseA

            let Q = (3 * B - (A * A)) / 9
            let R = (9 * A * B - 27 * C - 2 * (A * A * A)) / 54
            let D = (Q * Q * Q) + (R * R)
            let A3 = A / 3

            var roots: [CGFloat] = [-1, -1, -1]
            if D >= 0 {
                let squareRoot = sqrt(D)
                let S = sign(R + squareRoot)
                    * pow((R + squareRoot).magnitude, 1.0 / 3)
                let T = sign(R - squareRoot)
                    * pow((R - squareRoot).magnitude, 1.0 / 3)

                roots[0] = -A3 + (S + T)

                let imaginary = (sqrt(3) * (S - T) / 2).magnitude
                if imaginary == .zero {
                    roots[1] = -A3 - (S + T) / 2
                    roots[2] = -A3 - (S + T) / 2
                }
            } else {
                let theta = acos(R / sqrt(-(Q * Q * Q)))
                let squareRoot = sqrt(-Q)
                roots[0] = 2 * squareRoot * cos(theta / 3) - A3
                roots[1] = 2 * squareRoot
                    * cos((theta + 2 * .pi) / 3) - A3
                roots[2] = 2 * squareRoot
                    * cos((theta + 4 * .pi) / 3) - A3
            }
            return roots.filter { $0 >= 0 && $0 <= 1 }
        }

        let b0 = -bezier.p0 + 3 * bezier.p1 - 3 * bezier.p2 + bezier.p3
        let b1 = 3 * bezier.p0 - 6 * bezier.p1 + 3 * bezier.p2
        let b2 = -3 * bezier.p0 + 3 * bezier.p1
        let b3 = bezier.p0

        let A = end.y - begin.y
        let B = begin.x - end.x
        let C = begin.x * (begin.y - end.y)
            + begin.y * (end.x - begin.x)
        let P0 = A * b0.x + B * b0.y
        let P1 = A * b1.x + B * b1.y
        let P2 = A * b2.x + B * b2.y
        let P3 = A * b3.x + B * b3.y + C

        return cubicRoots(P0, P1, P2, P3).filter { t in
            let t2 = t * t
            let t3 = t2 * t
            let point = b0 * t3 + b1 * t2 + b2 * t + b3

            let s: CGFloat
            if end.x - begin.x != 0 {
                s = (point.x - begin.x) / (end.x - begin.x)
            } else {
                s = (point.y - begin.y) / (end.y - begin.y)
            }
            return s >= 0 && s <= 1
        }.sorted()
    }
}
