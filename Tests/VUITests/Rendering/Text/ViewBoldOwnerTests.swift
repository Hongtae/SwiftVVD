import XCTest
@testable import VUI

// ASSERTIONS viewBoldPublic27Observed

final class ViewBoldOwnerTests: XCTestCase {
    private typealias Transform =
        _EnvironmentKeyTransformModifier<[AnyFontModifier]>
    private typealias Modified = ModifiedContent<EmptyView, Transform>

    func testViewProducerUsesTheFontModifierEnvironmentAndDefaultsActive() throws {
        let omitted = try XCTUnwrap(EmptyView().bold() as? Modified)
        let active = try XCTUnwrap(EmptyView().bold(true) as? Modified)
        let inactive = try XCTUnwrap(EmptyView().bold(false) as? Modified)

        XCTAssertEqual(omitted.modifier.keyPath, \EnvironmentValues.fontModifiers)
        XCTAssertEqual(active.modifier.keyPath, \EnvironmentValues.fontModifiers)
        XCTAssertEqual(inactive.modifier.keyPath, \EnvironmentValues.fontModifiers)

        var omittedModifiers: [AnyFontModifier] = []
        omitted.modifier.transform(&omittedModifiers)
        XCTAssertEqual(omittedModifiers, [.static(Font.BoldModifier.self)])

        var activeModifiers: [AnyFontModifier] = []
        active.modifier.transform(&activeModifiers)
        active.modifier.transform(&activeModifiers)
        XCTAssertEqual(activeModifiers, [
            .static(Font.BoldModifier.self),
            .static(Font.BoldModifier.self),
        ])
    }

    func testInactiveRemovesEveryStaticBoldAndPreservesOtherModifierTypes() throws {
        let inactive = try XCTUnwrap(EmptyView().bold(false) as? Modified)
        let weight = AnyFontModifier.dynamic(Font.WeightModifier(weight: .light))
        let italic = AnyFontModifier.static(Font.ItalicModifier.self)
        let undo = AnyFontModifier.static(
            Font.UndoModifier<Font.BoldModifier>.self
        )
        var modifiers: [AnyFontModifier] = [
            .static(Font.BoldModifier.self),
            weight,
            .static(Font.BoldModifier.self),
            italic,
            undo,
        ]

        inactive.modifier.transform(&modifiers)

        XCTAssertEqual(modifiers, [weight, italic, undo])
    }

    func testNestedViewTransformsRunFromOuterWrapperTowardContent() throws {
        typealias Once = ModifiedContent<EmptyView, Transform>
        typealias Twice = ModifiedContent<Once, Transform>

        let activeThenInactive = try XCTUnwrap(
            EmptyView().bold(true).bold(false) as? Twice
        )
        var activeThenInactiveModifiers: [AnyFontModifier] = []
        activeThenInactive.modifier.transform(&activeThenInactiveModifiers)
        activeThenInactive.content.modifier.transform(
            &activeThenInactiveModifiers
        )
        XCTAssertEqual(
            activeThenInactiveModifiers,
            [.static(Font.BoldModifier.self)]
        )

        let inactiveThenActive = try XCTUnwrap(
            EmptyView().bold(false).bold(true) as? Twice
        )
        var inactiveThenActiveModifiers: [AnyFontModifier] = []
        inactiveThenActive.modifier.transform(&inactiveThenActiveModifiers)
        inactiveThenActive.content.modifier.transform(
            &inactiveThenActiveModifiers
        )
        XCTAssertTrue(inactiveThenActiveModifiers.isEmpty)

        let repeated = try XCTUnwrap(
            EmptyView().bold(true).bold(true) as? Twice
        )
        var repeatedModifiers: [AnyFontModifier] = []
        repeated.modifier.transform(&repeatedModifiers)
        repeated.content.modifier.transform(&repeatedModifiers)
        XCTAssertEqual(repeatedModifiers, [
            .static(Font.BoldModifier.self),
            .static(Font.BoldModifier.self),
        ])
    }

    func testTextLocalBoldClearsOrExtendsTheInheritedArray() throws {
        let inheritedActive = try environment(afterViewBold: true)
        let inheritedInactive = try environment(afterViewBold: false)

        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").bold(false),
                          in: inheritedActive),
            []
        )
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").bold(true),
                          in: inheritedInactive),
            [.static(Font.BoldModifier.self)]
        )
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").bold(true),
                          in: inheritedActive),
            [
                .static(Font.BoldModifier.self),
                .static(Font.BoldModifier.self),
            ]
        )
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").bold(false),
                          in: inheritedInactive),
            []
        )
    }

    func testDynamicWeightOrderAndExplicitFontRemainIndependent() throws {
        let light = AnyFontModifier.dynamic(
            Font.WeightModifier(weight: .light)
        )
        var inheritedLight = try environment(
            afterViewBold: true,
            startingWith: [light]
        )
        XCTAssertEqual(inheritedLight.fontModifiers, [
            light,
            .static(Font.BoldModifier.self),
        ])
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").fontWeight(.light),
                          in: try environment(afterViewBold: true)),
            [
                .static(Font.BoldModifier.self),
                .dynamic(Font.WeightModifier(weight: .light)),
            ]
        )

        inheritedLight = try environment(
            afterViewBold: false,
            startingWith: [
                .static(Font.BoldModifier.self),
                .dynamic(Font.WeightModifier(weight: .bold)),
            ]
        )
        XCTAssertEqual(inheritedLight.fontModifiers, [
            .dynamic(Font.WeightModifier(weight: .bold)),
        ])

        var explicit = try environment(afterViewBold: false)
        explicit.font = .system(size: 20, weight: .bold)
        let key = try XCTUnwrap(Text.Style().fontKey(in: explicit))
        XCTAssertTrue(key.modifiers.isEmpty)
        XCTAssertEqual(key.font, .system(size: 20, weight: .bold))
    }

    private func environment(
        afterViewBold isActive: Bool,
        startingWith modifiers: [AnyFontModifier] = []
    ) throws -> EnvironmentValues {
        let owner = try XCTUnwrap(EmptyView().bold(isActive) as? Modified)
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
