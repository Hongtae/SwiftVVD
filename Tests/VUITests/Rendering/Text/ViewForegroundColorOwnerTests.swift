import XCTest
@testable import VUI

// ASSERTIONS viewForegroundColorPublic27Observed

final class ViewForegroundColorOwnerTests: XCTestCase {
    func testViewProducerWritesTheSharedForegroundStyleOwner() throws {
        typealias Modifier = _EnvironmentKeyWritingModifier<Color?>
        typealias Once = ModifiedContent<EmptyView, Modifier>
        typealias Twice = ModifiedContent<Once, Modifier>

        let red = try XCTUnwrap(
            EmptyView().foregroundColor(.red) as? Once
        )
        XCTAssertEqual(red.modifier.keyPath, \.foregroundColor)
        XCTAssertEqual(red.modifier.value, .red)

        let cleared = try XCTUnwrap(
            EmptyView().foregroundColor(nil) as? Once
        )
        XCTAssertEqual(cleared.modifier.keyPath, \.foregroundColor)
        XCTAssertNil(cleared.modifier.value)

        var environment = EnvironmentValues()
        XCTAssertNil(environment.foregroundColor)
        XCTAssertNil(environment.foregroundStyleLevels)

        environment[keyPath: red.modifier.keyPath] = red.modifier.value
        XCTAssertEqual(environment.foregroundColor, .red)
        XCTAssertEqual(resolvedForeground(in: environment), resolved(.red))

        environment[keyPath: cleared.modifier.keyPath] =
            cleared.modifier.value
        XCTAssertNil(environment.foregroundColor)
        XCTAssertNil(environment.foregroundStyleLevels)

        let nested = try XCTUnwrap(
            EmptyView()
                .foregroundColor(.red)
                .foregroundColor(.blue) as? Twice
        )
        environment[keyPath: nested.modifier.keyPath] =
            nested.modifier.value
        environment[keyPath: nested.content.modifier.keyPath] =
            nested.content.modifier.value
        XCTAssertEqual(environment.foregroundColor, .red)
        XCTAssertEqual(resolvedForeground(in: environment), resolved(.red))

        let contentNearestNil = try XCTUnwrap(
            EmptyView()
                .foregroundColor(nil)
                .foregroundColor(.red) as? Twice
        )
        environment[keyPath: contentNearestNil.modifier.keyPath] =
            contentNearestNil.modifier.value
        environment[keyPath: contentNearestNil.content.modifier.keyPath] =
            contentNearestNil.content.modifier.value
        XCTAssertNil(environment.foregroundColor)
        XCTAssertNil(environment.foregroundStyleLevels)
    }

    func testForegroundColorAndStyleUseContentNearestSourceOrder() {
        var colorNearest = EnvironmentValues()
        colorNearest.foregroundStyleLevels = _ForegroundStyleLevels(
            primary: AnyShapeStyle(Color.blue)
        )
        colorNearest.foregroundColor = .red
        XCTAssertEqual(
            resolvedForeground(in: colorNearest),
            resolved(.red)
        )

        var styleNearest = EnvironmentValues()
        styleNearest.foregroundColor = .red
        styleNearest.foregroundStyleLevels = _ForegroundStyleLevels(
            primary: AnyShapeStyle(Color.blue)
        )
        XCTAssertEqual(styleNearest.foregroundColor, .blue)
        XCTAssertEqual(
            resolvedForeground(in: styleNearest),
            resolved(.blue)
        )
    }

    private func resolvedForeground(
        in environment: EnvironmentValues
    ) -> Color.ResolvedHDR? {
        guard let style = environment.currentForegroundStyle else {
            return nil
        }
        var shape = _ShapeStyle_Shape(
            operation: .fallbackColor(level: 0),
            environment: environment
        )
        style._apply(to: &shape)
        guard case let .color(color) = shape.result else { return nil }
        return color.resolveHDR(in: environment)
    }

    private func resolved(_ color: Color) -> Color.ResolvedHDR {
        color.resolveHDR(in: EnvironmentValues())
    }
}
