import XCTest
@testable import VUI

final class AnyShapeStyleTests: XCTestCase {
    private struct BooleanStyle: ShapeStyle {
        var value: Bool

        func _apply(to shape: inout _ShapeStyle_Shape) {
            shape.result = .bool(value)
        }

        static func _apply(to type: inout _ShapeStyle_ShapeType) {
            type.result = .bool(false)
        }
    }

    func testRepeatedErasureRetainsOriginalBoxAndApplication() {
        let original = AnyShapeStyle(BooleanStyle(value: true))
        var erased = original
        for _ in 0..<32 {
            erased = AnyShapeStyle(erased)
            XCTAssertTrue(erased.storage.box === original.storage.box)
        }

        var shape = _ShapeStyle_Shape(
            operation: .multiLevel,
            environment: EnvironmentValues()
        )
        erased._apply(to: &shape)
        guard case .bool(true) = shape.result else {
            return XCTFail("Repeated erasure must preserve the original application.")
        }
    }

    func testErasedTypeQueryUnconditionallyReportsBackgroundModification() {
        for initial: _ShapeStyle_ShapeType.Result in [.none, .bool(false), .bool(true)] {
            var type = _ShapeStyle_ShapeType(result: initial)
            AnyShapeStyle._apply(to: &type)
            guard case .bool(true) = type.result else {
                return XCTFail("The erased type query must overwrite the prior result.")
            }
        }
    }
}
