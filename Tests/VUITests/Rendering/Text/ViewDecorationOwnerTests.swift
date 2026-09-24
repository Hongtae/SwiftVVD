import Foundation
import XCTest
@testable import VUI

// ASSERTIONS viewDecorationPublic27Observed

final class ViewDecorationOwnerTests: XCTestCase {
    func testViewProducersWriteDistinctOptionalLineStyleKeys() throws {
        typealias Modifier = _EnvironmentKeyWritingModifier<Text.LineStyle?>
        typealias Once = ModifiedContent<EmptyView, Modifier>
        typealias Twice = ModifiedContent<Once, Modifier>

        let underline = try XCTUnwrap(EmptyView().underline(
            pattern: .dash,
            color: .red
        ) as? Once)
        XCTAssertEqual(underline.modifier.keyPath, \.underlineStyle)
        XCTAssertNotEqual(underline.modifier.keyPath, \.strikethroughStyle)
        XCTAssertEqual(
            underline.modifier.value,
            Text.LineStyle(pattern: .dash, color: .red)
        )

        let inactiveUnderline = try XCTUnwrap(EmptyView().underline(
            false,
            pattern: .dot,
            color: .blue
        ) as? Once)
        XCTAssertEqual(inactiveUnderline.modifier.keyPath, \.underlineStyle)
        XCTAssertNil(inactiveUnderline.modifier.value)

        let strikethrough = try XCTUnwrap(EmptyView().strikethrough(
            pattern: .dot,
            color: .blue
        ) as? Once)
        XCTAssertEqual(strikethrough.modifier.keyPath, \.strikethroughStyle)
        XCTAssertNotEqual(strikethrough.modifier.keyPath, \.underlineStyle)
        XCTAssertEqual(
            strikethrough.modifier.value,
            Text.LineStyle(pattern: .dot, color: .blue)
        )

        let inactiveStrikethrough = try XCTUnwrap(
            EmptyView().strikethrough(
                false,
                pattern: .dash,
                color: .red
            ) as? Once
        )
        XCTAssertEqual(
            inactiveStrikethrough.modifier.keyPath,
            \.strikethroughStyle
        )
        XCTAssertNil(inactiveStrikethrough.modifier.value)

        var environment = EnvironmentValues()
        XCTAssertNil(environment.underlineStyle)
        XCTAssertNil(environment.strikethroughStyle)

        let nested = try XCTUnwrap(
            EmptyView()
                .underline(pattern: .dash, color: .red)
                .underline(pattern: .dot, color: .blue) as? Twice
        )
        environment[keyPath: nested.modifier.keyPath] =
            nested.modifier.value
        environment[keyPath: nested.content.modifier.keyPath] =
            nested.content.modifier.value
        XCTAssertEqual(
            environment.underlineStyle,
            Text.LineStyle(pattern: .dash, color: .red)
        )

        let cleared = try XCTUnwrap(
            EmptyView()
                .strikethrough(pattern: .dash, color: .red)
                .strikethrough(false) as? Twice
        )
        environment[keyPath: cleared.modifier.keyPath] =
            cleared.modifier.value
        environment[keyPath: cleared.content.modifier.keyPath] =
            cleared.content.modifier.value
        XCTAssertEqual(
            environment.strikethroughStyle,
            Text.LineStyle(pattern: .dash, color: .red)
        )

        let contentNearestInactive = try XCTUnwrap(
            EmptyView()
                .strikethrough(false, pattern: .dot, color: .blue)
                .strikethrough(pattern: .dash, color: .red) as? Twice
        )
        environment[keyPath: contentNearestInactive.modifier.keyPath] =
            contentNearestInactive.modifier.value
        environment[
            keyPath: contentNearestInactive.content.modifier.keyPath
        ] = contentNearestInactive.content.modifier.value
        XCTAssertNil(environment.strikethroughStyle)
    }

    func testTextStylesOverrideOrClearInheritedDecorationsIndependently() {
        var environment = EnvironmentValues()
        environment.underlineStyle = Text.LineStyle(
            pattern: .dash,
            color: .red
        )
        environment.strikethroughStyle = Text.LineStyle(
            pattern: .dot,
            color: .blue
        )

        let inherited = resolved(Text.Style(), in: environment)
        XCTAssertEqual(
            inherited.underlineStyle,
            Text.LineStyle(pattern: .dash, color: .red)
        )
        XCTAssertEqual(
            inherited.strikethroughStyle,
            Text.LineStyle(pattern: .dot, color: .blue)
        )

        var localUnderline = Text.Style()
        UnderlineTextModifier(lineStyle: Text.LineStyle(
            pattern: .dot,
            color: .green
        )).modify(style: &localUnderline, environment: environment)
        let local = resolved(localUnderline, in: environment)
        XCTAssertEqual(
            local.underlineStyle,
            Text.LineStyle(pattern: .dot, color: .green)
        )
        XCTAssertEqual(
            local.strikethroughStyle,
            Text.LineStyle(pattern: .dot, color: .blue)
        )

        var clearedUnderline = Text.Style()
        UnderlineTextModifier(lineStyle: nil).modify(
            style: &clearedUnderline,
            environment: environment
        )
        let clearedUnderlineAttributes = resolved(
            clearedUnderline,
            in: environment
        )
        XCTAssertNil(clearedUnderlineAttributes.underlineStyle)
        XCTAssertEqual(
            clearedUnderlineAttributes.strikethroughStyle,
            Text.LineStyle(pattern: .dot, color: .blue)
        )

        var clearedStrikethrough = Text.Style()
        StrikethroughTextModifier(lineStyle: nil).modify(
            style: &clearedStrikethrough,
            environment: environment
        )
        let clearedStrikethroughAttributes = resolved(
            clearedStrikethrough,
            in: environment
        )
        XCTAssertEqual(
            clearedStrikethroughAttributes.underlineStyle,
            Text.LineStyle(pattern: .dash, color: .red)
        )
        XCTAssertNil(clearedStrikethroughAttributes.strikethroughStyle)
    }

    func testAttributedRunsOverrideTheirCopiedParentIndependently() {
        var environment = EnvironmentValues()
        environment.underlineStyle = Text.LineStyle(
            pattern: .dash,
            color: .red
        )
        environment.strikethroughStyle = Text.LineStyle(
            pattern: .dot,
            color: .blue
        )

        var parent = Text.Style()
        UnderlineTextModifier(lineStyle: Text.LineStyle(color: .blue)).modify(
            style: &parent,
            environment: environment
        )

        var first = parent
        var firstRun: [NSAttributedString.Key: Any] = [
            .coreUnderlineStyle: Text.LineStyle(
                pattern: .dot,
                color: .green
            )
        ]
        firstRun.transferAttributedStringStyles(to: &first)
        XCTAssertNil(firstRun[.coreUnderlineStyle])

        let second = parent
        let firstAttributes = resolved(first, in: environment)
        let secondAttributes = resolved(second, in: environment)
        XCTAssertEqual(
            firstAttributes.underlineStyle,
            Text.LineStyle(pattern: .dot, color: .green)
        )
        XCTAssertEqual(
            firstAttributes.strikethroughStyle,
            Text.LineStyle(pattern: .dot, color: .blue)
        )
        XCTAssertEqual(
            secondAttributes.underlineStyle,
            Text.LineStyle(color: .blue)
        )
        XCTAssertEqual(
            secondAttributes.strikethroughStyle,
            Text.LineStyle(pattern: .dot, color: .blue)
        )

        var both = parent
        var bothRun: [NSAttributedString.Key: Any] = [
            .coreUnderlineStyle: Text.LineStyle(
                pattern: .dashDot,
                color: .green
            ),
            .coreStrikethroughStyle: Text.LineStyle(
                pattern: .dash,
                color: .red
            )
        ]
        bothRun.transferAttributedStringStyles(to: &both)
        let bothAttributes = resolved(both, in: environment)
        XCTAssertEqual(
            bothAttributes.underlineStyle,
            Text.LineStyle(pattern: .dashDot, color: .green)
        )
        XCTAssertEqual(
            bothAttributes.strikethroughStyle,
            Text.LineStyle(pattern: .dash, color: .red)
        )
    }

    private func resolved(
        _ style: Text.Style,
        in environment: EnvironmentValues
    ) -> _ResolvedTextRunAttributes {
        var properties = Text.ResolvedProperties()
        return style.nsAttributes(
            in: environment,
            properties: &properties,
            includeDefaultAttributes: false
        )
    }
}
