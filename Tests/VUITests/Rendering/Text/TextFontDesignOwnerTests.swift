import Foundation
import XCTest
@testable import VUI

// ASSERTIONS textFontDesignPublic27Observed

final class TextFontDesignOwnerTests: XCTestCase {
    func testTextDesignKeepsTypedOptionalOwnershipAndEquality() throws {
        let rounded = Text(verbatim: "A").fontDesign(.rounded)
        let none = Text(verbatim: "A").fontDesign(nil)
        let roundedOwner = try designOwner(in: rounded)
        let nilOwner = try designOwner(in: none)

        XCTAssertEqual(roundedOwner.design, .rounded)
        XCTAssertNil(nilOwner.design)
        XCTAssertEqual(rounded, Text(verbatim: "A").fontDesign(.rounded))
        XCTAssertNotEqual(rounded, Text(verbatim: "A").fontDesign(.serif))
        XCTAssertEqual(none, Text(verbatim: "A").fontDesign(nil))
        XCTAssertNotEqual(none, Text(verbatim: "A"))

        let repeated = rounded.fontDesign(.serif)
        XCTAssertEqual(repeated.modifiers.count, 2)
        XCTAssertEqual(try designOwner(in: repeated, at: 1).design, .serif)

        var first = Hasher()
        var second = Hasher()
        roundedOwner.hashResolution(into: &first)
        TextDesignModifier(design: .rounded).hashResolution(into: &second)
        XCTAssertEqual(first.finalize(), second.finalize())
    }

    func testViewDesignAppendsRequestsAndNilRemovesOnlyDesigns() throws {
        typealias Modified = ModifiedContent<
            EmptyView,
            _EnvironmentKeyTransformModifier<[AnyFontModifier]>
        >
        let rounded = try XCTUnwrap(
            EmptyView().fontDesign(.rounded) as? Modified
        )
        let none = try XCTUnwrap(EmptyView().fontDesign(nil) as? Modified)
        XCTAssertEqual(
            rounded.modifier.keyPath,
            \EnvironmentValues.fontModifiers
        )

        let italic = AnyFontModifier.static(Font.ItalicModifier.self)
        let digit = AnyFontModifier.static(Font.MonospacedDigitModifier.self)
        var modifiers: [AnyFontModifier] = [
            italic,
            .dynamic(Font.DesignModifier(design: .serif)),
            digit,
        ]
        rounded.modifier.transform(&modifiers)
        rounded.modifier.transform(&modifiers)
        XCTAssertEqual(
            modifiers.compactMap {
                ($0 as? AnyDynamicFontModifier<Font.DesignModifier>)?
                    .modifier.design
            },
            [.serif, .rounded, .rounded]
        )

        none.modifier.transform(&modifiers)
        XCTAssertEqual(modifiers, [italic, digit])
    }

    func testTextAndViewDesignOrderingMatchesDescriptorConsumption() throws {
        let base = Text(verbatim: "A")
        XCTAssertEqual(
            try resolvedDesign(base.fontDesign(.rounded).fontDesign(.serif)),
            .serif
        )
        XCTAssertEqual(
            try resolvedDesign(base.fontDesign(.serif).fontDesign(.rounded)),
            .rounded
        )
        XCTAssertEqual(
            try resolvedDesign(base.fontDesign(.rounded).fontDesign(nil)),
            .rounded
        )
        XCTAssertEqual(
            try resolvedDesign(base.fontDesign(nil).fontDesign(.rounded)),
            .default
        )

        var inherited = resolutionEnvironment()
        inherited.fontModifiers = [
            .dynamic(Font.DesignModifier(design: .serif)),
            .static(Font.ItalicModifier.self),
        ]
        XCTAssertEqual(
            try resolvedDesign(base.fontDesign(.rounded), in: inherited),
            .serif
        )
        XCTAssertEqual(
            try resolvedDesign(base.fontDesign(nil), in: inherited),
            .default
        )
        let cleared = try XCTUnwrap(style(base.fontDesign(nil)).fontKey(
            in: inherited
        ))
        XCTAssertEqual(cleared.context.fontModifiers, [])
        XCTAssertEqual(cleared.modifiers, [.static(Font.ItalicModifier.self)])

        XCTAssertEqual(
            try resolvedDesign(
                base.font(.system(size: 20, design: .serif))
                    .fontDesign(.rounded)
            ),
            .rounded
        )
        XCTAssertEqual(
            try resolvedDesign(
                base.font(.system(size: 20, design: .rounded))
                    .fontDesign(nil)
            ),
            .rounded
        )
    }

    func testDesignModifierKeepsTagCodingAndFirstRequestOwnership() throws {
        XCTAssertEqual(Font.DesignModifier(design: .rounded).tag, .design)
        XCTAssertEqual(
            Font.DesignModifier(design: .rounded).codingProxy,
            "NSCTFontUIFontDesignRounded"
        )
        XCTAssertEqual(
            Font.DesignModifier.unwrap(
                codingProxy: "NSCTFontUIFontDesignMonospaced"
            ).design,
            .monospaced
        )

        let context = resolutionEnvironment().fontResolutionContext
        var descriptor = Font.system(
            size: 20,
            design: .serif
        ).resolveDescriptor(in: context)
        Font.DesignModifier(design: .rounded).modify(
            descriptor: &descriptor,
            in: context
        )
        Font.DesignModifier(design: .monospaced).modify(
            descriptor: &descriptor,
            in: context
        )
        XCTAssertEqual(try descriptorDesign(descriptor), .rounded)

        let resource = FontResource(descriptor: descriptor, in: context)
        var copied = resource.descriptor()
        Font.DesignModifier(design: .serif).modify(
            descriptor: &copied,
            in: context
        )
        XCTAssertEqual(try descriptorDesign(copied), .rounded)
    }

    private func designOwner(
        in text: Text,
        at index: Int = 0
    ) throws -> TextDesignModifier {
        guard case let .anyTextModifier(owner) = text.modifiers[index] else {
            throw FontDesignTestError.missingOwner
        }
        return try XCTUnwrap(owner as? TextDesignModifier)
    }

    private func style(_ text: Text) -> Text.Style {
        var style = Text.Style()
        let environment = resolutionEnvironment()
        for modifier in text.modifiers.reversed() {
            modifier.modify(style: &style, environment: environment)
        }
        return style
    }

    private func resolvedDesign(
        _ text: Text,
        in environment: EnvironmentValues? = nil
    ) throws -> Font.Design {
        let environment = environment ?? resolutionEnvironment()
        let key = try XCTUnwrap(style(text).fontKey(in: environment))
        let resource = key.font.platformFont(
            in: key.context,
            modifiers: key.modifiers,
            overrideContextModifiers: true
        )
        return try XCTUnwrap(
            (resource.provider as? SystemFontProvider)?.design
        )
    }

    private func descriptorDesign(
        _ descriptor: FontDescriptor
    ) throws -> Font.Design {
        switch descriptor.source {
        case let .system(design, _, _, _, _):
            return design
        case let .typeface(provider):
            return try XCTUnwrap(
                (provider as? SystemFontProvider)?.design
            )
        default:
            throw FontDesignTestError.unexpectedDescriptor
        }
    }

    private func resolutionEnvironment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.font = .system(size: 23)
        environment.defaultFontRenderingMode = .vector()
        return environment
    }
}

private enum FontDesignTestError: Error {
    case missingOwner
    case unexpectedDescriptor
}
