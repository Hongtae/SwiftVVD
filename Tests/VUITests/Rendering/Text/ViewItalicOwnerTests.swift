import XCTest
@testable import VUI

// ASSERTIONS viewItalicPublic27Observed

final class ViewItalicOwnerTests: XCTestCase {
    private typealias Transform =
        _EnvironmentKeyTransformModifier<[AnyFontModifier]>
    private typealias Modified = ModifiedContent<EmptyView, Transform>

    func testViewProducerUsesTheFontModifierEnvironmentAndDefaultsActive() throws {
        let omitted = try XCTUnwrap(EmptyView().italic() as? Modified)
        let active = try XCTUnwrap(EmptyView().italic(true) as? Modified)
        let inactive = try XCTUnwrap(EmptyView().italic(false) as? Modified)

        XCTAssertEqual(omitted.modifier.keyPath, \EnvironmentValues.fontModifiers)
        XCTAssertEqual(active.modifier.keyPath, \EnvironmentValues.fontModifiers)
        XCTAssertEqual(inactive.modifier.keyPath, \EnvironmentValues.fontModifiers)

        var omittedModifiers: [AnyFontModifier] = []
        omitted.modifier.transform(&omittedModifiers)
        XCTAssertEqual(omittedModifiers, [.static(Font.ItalicModifier.self)])

        var activeModifiers: [AnyFontModifier] = []
        active.modifier.transform(&activeModifiers)
        active.modifier.transform(&activeModifiers)
        XCTAssertEqual(activeModifiers, [
            .static(Font.ItalicModifier.self),
            .static(Font.ItalicModifier.self),
        ])
    }

    func testInactiveRemovesEveryStaticItalicAndPreservesOtherModifierTypes() throws {
        let inactive = try XCTUnwrap(EmptyView().italic(false) as? Modified)
        let weight = AnyFontModifier.dynamic(
            Font.WeightModifier(weight: .light)
        )
        let bold = AnyFontModifier.static(Font.BoldModifier.self)
        let undo = AnyFontModifier.static(
            Font.UndoModifier<Font.ItalicModifier>.self
        )
        var modifiers: [AnyFontModifier] = [
            .static(Font.ItalicModifier.self),
            weight,
            .static(Font.ItalicModifier.self),
            bold,
            undo,
        ]

        inactive.modifier.transform(&modifiers)

        XCTAssertEqual(modifiers, [weight, bold, undo])
    }

    func testNestedViewTransformsRunFromOuterWrapperTowardContent() throws {
        typealias Once = ModifiedContent<EmptyView, Transform>
        typealias Twice = ModifiedContent<Once, Transform>

        let activeThenInactive = try XCTUnwrap(
            EmptyView().italic(true).italic(false) as? Twice
        )
        var activeThenInactiveModifiers: [AnyFontModifier] = []
        activeThenInactive.modifier.transform(&activeThenInactiveModifiers)
        activeThenInactive.content.modifier.transform(
            &activeThenInactiveModifiers
        )
        XCTAssertEqual(
            activeThenInactiveModifiers,
            [.static(Font.ItalicModifier.self)]
        )

        let inactiveThenActive = try XCTUnwrap(
            EmptyView().italic(false).italic(true) as? Twice
        )
        var inactiveThenActiveModifiers: [AnyFontModifier] = []
        inactiveThenActive.modifier.transform(&inactiveThenActiveModifiers)
        inactiveThenActive.content.modifier.transform(
            &inactiveThenActiveModifiers
        )
        XCTAssertTrue(inactiveThenActiveModifiers.isEmpty)

        let repeated = try XCTUnwrap(
            EmptyView().italic(true).italic(true) as? Twice
        )
        var repeatedModifiers: [AnyFontModifier] = []
        repeated.modifier.transform(&repeatedModifiers)
        repeated.content.modifier.transform(&repeatedModifiers)
        XCTAssertEqual(repeatedModifiers, [
            .static(Font.ItalicModifier.self),
            .static(Font.ItalicModifier.self),
        ])
    }

    func testTextBoolOverloadRetainsItsSeparateCarrier() throws {
        let noArgument = Text(verbatim: "A").italic()
        XCTAssertEqual(noArgument.modifiers, [.italic])

        for (text, expected) in [
            (Text(verbatim: "A").italic(true), true),
            (Text(verbatim: "A").italic(false), false),
        ] {
            let modifier = try XCTUnwrap(text.modifiers.first)
            guard case let .anyTextModifier(value) = modifier else {
                return XCTFail("Bool overload must retain ItalicTextModifier")
            }
            let italic = try XCTUnwrap(value as? ItalicTextModifier)
            XCTAssertEqual(italic.isActive, expected)
        }
    }

    func testTextLocalItalicClearsOrExtendsTheInheritedArray() throws {
        let inheritedActive = try environment(afterViewItalic: true)
        let inheritedInactive = try environment(afterViewItalic: false)

        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").italic(false),
                          in: inheritedActive),
            []
        )
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").italic(true),
                          in: inheritedInactive),
            [.static(Font.ItalicModifier.self)]
        )
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").italic(true),
                          in: inheritedActive),
            [
                .static(Font.ItalicModifier.self),
                .static(Font.ItalicModifier.self),
            ]
        )
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").italic(false),
                          in: inheritedInactive),
            []
        )
    }

    func testDynamicWeightOrderAndExplicitFontRemainIndependent() throws {
        let light = AnyFontModifier.dynamic(
            Font.WeightModifier(weight: .light)
        )
        var inheritedLight = try environment(
            afterViewItalic: true,
            startingWith: [light]
        )
        XCTAssertEqual(inheritedLight.fontModifiers, [
            light,
            .static(Font.ItalicModifier.self),
        ])
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").fontWeight(.light),
                          in: try environment(afterViewItalic: true)),
            [
                .static(Font.ItalicModifier.self),
                .dynamic(Font.WeightModifier(weight: .light)),
            ]
        )

        inheritedLight = try environment(
            afterViewItalic: false,
            startingWith: [
                .static(Font.ItalicModifier.self),
                .dynamic(Font.WeightModifier(weight: .bold)),
            ]
        )
        XCTAssertEqual(inheritedLight.fontModifiers, [
            .dynamic(Font.WeightModifier(weight: .bold)),
        ])

        var explicit = try environment(afterViewItalic: false)
        let explicitItalic = Font.system(size: 20).italic()
        explicit.font = explicitItalic
        let key = try XCTUnwrap(Text.Style().fontKey(in: explicit))
        XCTAssertTrue(key.modifiers.isEmpty)
        XCTAssertEqual(key.font, explicitItalic)
    }

    private func environment(
        afterViewItalic isActive: Bool,
        startingWith modifiers: [AnyFontModifier] = []
    ) throws -> EnvironmentValues {
        let owner = try XCTUnwrap(EmptyView().italic(isActive) as? Modified)
        var environment = EnvironmentValues()
        environment.font = .body
        environment.fontModifiers = modifiers
        owner.modifier.transform(&environment.fontModifiers)
        return environment
    }

    private func modifiers(
        for text: Text,
        in environment: EnvironmentValues
    ) throws -> [AnyFontModifier] {
        var style = Text.Style()
        for modifier in text.modifiers.reversed() {
            modifier.modify(style: &style, environment: environment)
        }
        return try XCTUnwrap(style.fontKey(in: environment)).modifiers
    }
}
