import XCTest
import VVD
import VUI

final class CGMathTests: XCTestCase {
    private func assertBits(
        _ actual: CGFloat, _ expected: CGFloat,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.native.bitPattern, expected.native.bitPattern,
                       file: file, line: line)
    }

    private func assertPoint(
        _ actual: CGPoint, _ x: CGFloat, _ y: CGFloat,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        assertBits(actual.x, x, file: file, line: line)
        assertBits(actual.y, y, file: file, line: line)
    }

    private func assertSize(
        _ actual: CGSize, _ width: CGFloat, _ height: CGFloat,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        assertBits(actual.width, width, file: file, line: line)
        assertBits(actual.height, height, file: file, line: line)
    }

    func testPointOperatorsPreserveComponentArithmetic() {
        for index in 1...100 {
            let value = CGFloat(index) * 0.317
            let a = CGPoint(x: sin(value) * 20, y: cos(value) * 30)
            let b = CGPoint(x: cos(value * 1.3) * 25, y: sin(value * 1.7) * 15)
            let scale = value - 0.5
            let inverse = 1.0 / scale
            assertPoint(a + b, a.x + b.x, a.y + b.y)
            assertPoint(-a, -a.x, -a.y)
            assertPoint(a - b, a.x - b.x, a.y - b.y)
            assertPoint(a * scale, a.x * scale, a.y * scale)
            assertPoint(scale * a, scale * a.x, scale * a.y)
            assertPoint(a * b, a.x * b.x, a.y * b.y)
            assertPoint(a / b, a.x / b.x, a.y / b.y)
            assertPoint(scale / a, scale / a.x, scale / a.y)
            // Point/scalar division deliberately multiplies by the reciprocal.
            assertPoint(a / scale, a.x * inverse, a.y * inverse)

            var result = a
            result += b
            assertPoint(result, a.x + b.x, a.y + b.y)
            result = a
            result -= b
            assertPoint(result, a.x - b.x, a.y - b.y)
            result = a
            result *= b
            assertPoint(result, a.x * b.x, a.y * b.y)
            result = a
            result *= scale
            assertPoint(result, a.x * scale, a.y * scale)
            result = a
            result /= b
            assertPoint(result, a.x / b.x, a.y / b.y)
            result = a
            result /= scale
            assertPoint(result, a.x * inverse, a.y * inverse)
        }
    }

    func testSizeOperatorsPreserveComponentArithmetic() {
        for index in 1...100 {
            let value = CGFloat(index) * 0.317
            let a = CGSize(width: sin(value) * 20, height: cos(value) * 30)
            let b = CGSize(width: cos(value * 1.3) * 25, height: sin(value * 1.7) * 15)
            let scale = value - 0.5
            assertSize(a * scale, a.width * scale, a.height * scale)
            assertSize(scale * a, scale * a.width, scale * a.height)
            assertSize(a * b, a.width * b.width, a.height * b.height)
            assertSize(a / b, a.width / b.width, a.height / b.height)
            assertSize(scale / a, scale / a.width, scale / a.height)
            // Size/scalar division retains direct division, unlike CGPoint.
            assertSize(a / scale, a.width / scale, a.height / scale)
            var result = a
            result *= scale
            assertSize(result, a.width * scale, a.height * scale)
            result = a
            result *= b
            assertSize(result, a.width * b.width, a.height * b.height)
            result = a
            result /= scale
            assertSize(result, a.width / scale, a.height / scale)
            result = a
            result /= b
            assertSize(result, a.width / b.width, a.height / b.height)
        }
    }

    func testPointGeometryMethodsPreserveEvaluationOrder() {
        for index in 0..<100 {
            let value = CGFloat(index) * 0.173
            let a = CGPoint(x: sin(value) * 20, y: cos(value) * 30)
            let b = CGPoint(x: cos(value * 1.3) * 25, y: sin(value * 1.7) * 15)
            assertBits(CGPoint.dot(a, b), a.x * b.x + a.y * b.y)
            assertBits(CGPoint.cross(a, b), a.x * b.y - a.y * b.x)
            let lengthSquared = a.x * a.x + a.y * a.y
            assertBits(a.magnitudeSquared, lengthSquared)
            assertBits(a.magnitude, lengthSquared.squareRoot())
            let inverse = 1.0 / lengthSquared.squareRoot()
            assertPoint(a.normalized(), a.x * inverse, a.y * inverse)
            var normalized = a
            normalized.normalize()
            assertPoint(normalized, a.x * inverse, a.y * inverse)
            let t = value * 0.0317
            let x = a.x * (1.0 - t) + b.x * t
            let y = a.y * (1.0 - t) + b.y * t
            assertPoint(CGPoint.lerp(a, b, t), x, y)
            assertPoint(lerp(a, b, t), x, y)
            assertPoint(.minimum(a, b), min(a.x, b.x), min(a.y, b.y))
            assertPoint(.maximum(a, b), max(a.x, b.x), max(a.y, b.y))
            assertPoint(.clamp(a, min: CGPoint(x: -5, y: -7), max: CGPoint(x: 3, y: 4)),
                        min(max(-5, a.x), 3), min(max(-7, a.y), 4))
        }
        let zero = CGPoint(x: -0.0, y: 0.0)
        assertPoint(zero.normalized(), zero.x, zero.y)
    }

    func testApplyingMethodsPreserveAffineAndProjectiveMath() {
        let matrix2 = Matrix2(1.25, -0.375, 0.625, 0.875)
        let matrix3 = Matrix3(1.25, -0.375, 0.0075,
                             0.625, 0.875, 0.0125,
                             13.0, -7.0, 2.0)
        let transform = CGAffineTransform(a: 1.25, b: -0.375, c: 0.625,
                                          d: 0.875, tx: 13, ty: -7)
        for index in 0..<100 {
            let value = CGFloat(index) * 0.173
            let point = CGPoint(x: sin(value) * 20, y: cos(value) * 30)
            let x2 = point.x * CGFloat(matrix2.m11) + point.y * CGFloat(matrix2.m21)
            let y2 = point.x * CGFloat(matrix2.m12) + point.y * CGFloat(matrix2.m22)
            assertPoint(point.applying(matrix2), x2, y2)
            var result = point
            result.apply(matrix2)
            assertPoint(result, x2, y2)
            let x3 = point.x * CGFloat(matrix3.m11) + point.y * CGFloat(matrix3.m21) + CGFloat(matrix3.m31)
            let y3 = point.x * CGFloat(matrix3.m12) + point.y * CGFloat(matrix3.m22) + CGFloat(matrix3.m32)
            let w = point.x * CGFloat(matrix3.m13) + point.y * CGFloat(matrix3.m23) + CGFloat(matrix3.m33)
            let inverse = 1.0 / w
            assertPoint(point.applying(matrix3), x3 * inverse, y3 * inverse)
            result = point
            result.apply(matrix3)
            assertPoint(result, x3 * inverse, y3 * inverse)

            let vector = Vector2(point).applying(transform)
            assertBits(CGFloat(vector.x), point.x * transform.a + point.y * transform.c + transform.tx)
            assertBits(CGFloat(vector.y), point.x * transform.b + point.y * transform.d + transform.ty)
        }
        XCTAssertEqual(transform.matrix3,
                       Matrix3(1.25, -0.375, 0.0, 0.625, 0.875, 0.0, 13.0, -7.0, 1.0))
    }

    func testConversionsAndScalarVectorArithmeticPreserveComponents() {
        let point = CGPoint(x: -3.25, y: 7.125)
        let size = CGSize(width: point.x, height: point.y)
        assertPoint(CGPoint(point), point.x, point.y)
        assertPoint(CGPoint(Vector2(point)), point.x, point.y)
        assertPoint(CGPoint(Vector2(size)), point.x, point.y)
        assertSize(CGSize(Vector2(point)), point.x, point.y)
        assertSize(CGSize(point), point.x, point.y)
        assertSize(CGSize(size), point.x, point.y)
        assertPoint(size.cgPoint, point.x, point.y)
        assertSize(.minimum(size, .zero), min(size.width, 0), min(size.height, 0))
        assertSize(.maximum(size, .zero), max(size.width, 0), max(size.height, 0))
        assertSize(.clamp(size, min: .zero, max: CGSize(width: 2, height: 5)), 0, 5)

        var float: Float = 3.125
        var double: Double = -7.25
        var cgFloat: CGFloat = 4.875
        XCTAssertEqual(float.magnitudeSquared, Double(float * float))
        XCTAssertEqual(double.magnitudeSquared, double * double)
        XCTAssertEqual(cgFloat.magnitudeSquared, cgFloat * cgFloat)
        float.scale(by: 0.317)
        double.scale(by: 0.317)
        cgFloat.scale(by: 0.317)
        XCTAssertEqual(float, Float(3.125) * Float(0.317))
        XCTAssertEqual(double, Double(-7.25) * 0.317)
        assertBits(cgFloat, CGFloat(4.875) * 0.317)
    }
}
