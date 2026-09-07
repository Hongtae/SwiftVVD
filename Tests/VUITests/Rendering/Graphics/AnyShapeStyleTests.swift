import XCTest
@testable import VUI

final class AnyShapeStyleTests: XCTestCase {
    private struct NumberStyle: ShapeStyle { var number: Int }
    private struct OtherNumberStyle: ShapeStyle { var number: Int }
    private struct AlwaysEqualStyle: ShapeStyle, Equatable {
        var number: Int
        static func == (lhs: Self, rhs: Self) -> Bool { true }
    }
    private final class Token: Sendable {}
    private struct ReferenceStyle: ShapeStyle { var token: Token }

    func testStorageEqualityUsesConcreteStoredValuesAndReferenceIdentity() {
        XCTAssertEqual(AnyShapeStyle(NumberStyle(number: 1)).storage,
                       AnyShapeStyle(NumberStyle(number: 1)).storage)
        XCTAssertNotEqual(AnyShapeStyle(NumberStyle(number: 1)).storage,
                          AnyShapeStyle(NumberStyle(number: 2)).storage)
        XCTAssertNotEqual(AnyShapeStyle(NumberStyle(number: 1)).storage,
                          AnyShapeStyle(OtherNumberStyle(number: 1)).storage)
        XCTAssertNotEqual(AnyShapeStyle(AlwaysEqualStyle(number: 1)).storage,
                          AnyShapeStyle(AlwaysEqualStyle(number: 2)).storage)
        let token = Token()
        XCTAssertEqual(AnyShapeStyle(ReferenceStyle(token: token)).storage,
                       AnyShapeStyle(ReferenceStyle(token: token)).storage)
        XCTAssertNotEqual(AnyShapeStyle(ReferenceStyle(token: Token())).storage,
                          AnyShapeStyle(ReferenceStyle(token: Token())).storage)
    }

    func testErasureReusesProviderBoxesAndBaseHasNoStoredStyle() {
        let color = Color(.sRGBLinear, red: 0.25, green: 0.5, blue: 0.75)
        let gradient = AnyGradient(Gradient(colors: [color, .white]))
        XCTAssertTrue(AnyShapeStyle(color).storage.box === color.provider)
        XCTAssertTrue(AnyShapeStyle(gradient).storage.box === gradient.provider)
        let box = AnyShapeStyle(NumberStyle(number: 1)).storage.box
        XCTAssertNotNil(box as? ShapeStyleBox<NumberStyle>)
        XCTAssertEqual(Mirror(reflecting: box).children.map(\.label), ["base"])
        XCTAssertTrue(Mirror(reflecting: box).superclassMirror!.children.isEmpty)
        let base = AnyShapeStyleBox()
        XCTAssertFalse(base.isEqual(to: base))
        var shape = _ShapeStyle_Shape(operation: .multiLevel,
                                     result: .bool(true), environment: EnvironmentValues())
        base.apply(to: &shape)
        guard case .bool(true) = shape.result else { return XCTFail("Base application must preserve the result.") }
    }

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
