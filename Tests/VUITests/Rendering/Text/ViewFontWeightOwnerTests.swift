import XCTest
@testable import VUI

// ASSERTIONS viewFontWeightPublic27Observed

final class ViewFontWeightOwnerTests: XCTestCase {
    private typealias Transform =
        _EnvironmentKeyTransformModifier<[AnyFontModifier]>
    private typealias Modified = ModifiedContent<EmptyView, Transform>

    func testViewProducerUsesTheFontModifierEnvironmentAndAppendsWeights() throws {
        let light = try XCTUnwrap(
            EmptyView().fontWeight(.light) as? Modified
        )
        let heavy = try XCTUnwrap(
            EmptyView().fontWeight(.heavy) as? Modified
        )
        let cleared = try XCTUnwrap(
            EmptyView().fontWeight(nil) as? Modified
        )

        XCTAssertEqual(light.modifier.keyPath, \EnvironmentValues.fontModifiers)
        XCTAssertEqual(heavy.modifier.keyPath, \EnvironmentValues.fontModifiers)
        XCTAssertEqual(cleared.modifier.keyPath, \EnvironmentValues.fontModifiers)

        var modifiers: [AnyFontModifier] = []
        light.modifier.transform(&modifiers)
        light.modifier.transform(&modifiers)
        heavy.modifier.transform(&modifiers)
        XCTAssertEqual(modifiers, [
            .dynamic(Font.WeightModifier(weight: .light)),
            .dynamic(Font.WeightModifier(weight: .light)),
            .dynamic(Font.WeightModifier(weight: .heavy)),
        ])
    }

    func testNilRemovesEveryDynamicWeightAndPreservesOtherModifierTypes() throws {
        let cleared = try XCTUnwrap(
            EmptyView().fontWeight(nil) as? Modified
        )
        let bold = AnyFontModifier.static(Font.BoldModifier.self)
        let design = AnyFontModifier.dynamic(
            Font.DesignModifier(design: .rounded)
        )
        let italic = AnyFontModifier.static(Font.ItalicModifier.self)
        var modifiers: [AnyFontModifier] = [
            .dynamic(Font.WeightModifier(weight: .light)),
            bold,
            .dynamic(Font.WeightModifier(weight: .heavy)),
            design,
            italic,
        ]

        cleared.modifier.transform(&modifiers)

        XCTAssertEqual(modifiers, [bold, design, italic])
    }

    func testNestedViewTransformsRunFromOuterWrapperTowardContent() throws {
        typealias Once = ModifiedContent<EmptyView, Transform>
        typealias Twice = ModifiedContent<Once, Transform>

        let lightThenNil = try XCTUnwrap(
            EmptyView().fontWeight(.light).fontWeight(nil) as? Twice
        )
        var lightThenNilModifiers: [AnyFontModifier] = []
        lightThenNil.modifier.transform(&lightThenNilModifiers)
        lightThenNil.content.modifier.transform(&lightThenNilModifiers)
        XCTAssertEqual(lightThenNilModifiers, [
            .dynamic(Font.WeightModifier(weight: .light)),
        ])

        let nilThenLight = try XCTUnwrap(
            EmptyView().fontWeight(nil).fontWeight(.light) as? Twice
        )
        var nilThenLightModifiers: [AnyFontModifier] = []
        nilThenLight.modifier.transform(&nilThenLightModifiers)
        nilThenLight.content.modifier.transform(&nilThenLightModifiers)
        XCTAssertTrue(nilThenLightModifiers.isEmpty)

        let lightThenHeavy = try XCTUnwrap(
            EmptyView().fontWeight(.light).fontWeight(.heavy) as? Twice
        )
        var lightThenHeavyModifiers: [AnyFontModifier] = []
        lightThenHeavy.modifier.transform(&lightThenHeavyModifiers)
        lightThenHeavy.content.modifier.transform(&lightThenHeavyModifiers)
        XCTAssertEqual(lightThenHeavyModifiers, [
            .dynamic(Font.WeightModifier(weight: .heavy)),
            .dynamic(Font.WeightModifier(weight: .light)),
        ])
    }

    func testStaticBoldAndDynamicWeightRemainOrderedAndTyped() throws {
        typealias Once = ModifiedContent<EmptyView, Transform>
        typealias Twice = ModifiedContent<Once, Transform>

        let weightThenBold = try XCTUnwrap(
            EmptyView().fontWeight(.light).bold(true) as? Twice
        )
        var weightThenBoldModifiers: [AnyFontModifier] = []
        weightThenBold.modifier.transform(&weightThenBoldModifiers)
        weightThenBold.content.modifier.transform(
            &weightThenBoldModifiers
        )
        XCTAssertEqual(weightThenBoldModifiers, [
            .static(Font.BoldModifier.self),
            .dynamic(Font.WeightModifier(weight: .light)),
        ])

        let boldThenWeight = try XCTUnwrap(
            EmptyView().bold(true).fontWeight(.light) as? Twice
        )
        var boldThenWeightModifiers: [AnyFontModifier] = []
        boldThenWeight.modifier.transform(&boldThenWeightModifiers)
        boldThenWeight.content.modifier.transform(
            &boldThenWeightModifiers
        )
        XCTAssertEqual(boldThenWeightModifiers, [
            .dynamic(Font.WeightModifier(weight: .light)),
            .static(Font.BoldModifier.self),
        ])

        let clearWithBold = try XCTUnwrap(
            EmptyView().fontWeight(nil) as? Modified
        )
        var mixed: [AnyFontModifier] = [
            .dynamic(Font.WeightModifier(weight: .heavy)),
            .static(Font.BoldModifier.self),
        ]
        clearWithBold.modifier.transform(&mixed)
        XCTAssertEqual(mixed, [.static(Font.BoldModifier.self)])
    }

    func testTextLocalWeightClearsOrExtendsTheInheritedArray() throws {
        let inheritedLight = try environment(afterViewFontWeight: .light)
        let inheritedNil = try environment(afterViewFontWeight: nil)
        let inheritedHeavy = try environment(afterViewFontWeight: .heavy)

        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").fontWeight(nil),
                          in: inheritedLight),
            []
        )
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").fontWeight(.heavy),
                          in: inheritedNil),
            [.dynamic(Font.WeightModifier(weight: .heavy))]
        )
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").fontWeight(.heavy),
                          in: inheritedLight),
            [
                .dynamic(Font.WeightModifier(weight: .light)),
                .dynamic(Font.WeightModifier(weight: .heavy)),
            ]
        )
        XCTAssertEqual(
            try modifiers(for: Text(verbatim: "A").fontWeight(.light),
                          in: inheritedHeavy),
            [
                .dynamic(Font.WeightModifier(weight: .heavy)),
                .dynamic(Font.WeightModifier(weight: .light)),
            ]
        )
    }

    func testExplicitFontRemainsSeparateUntilDescriptorResolution() throws {
        var cleared = try environment(afterViewFontWeight: nil)
        cleared.font = .system(size: 20, weight: .heavy)
        let clearedKey = try XCTUnwrap(Text.Style().fontKey(in: cleared))
        XCTAssertTrue(clearedKey.modifiers.isEmpty)
        XCTAssertEqual(clearedKey.font, .system(size: 20, weight: .heavy))

        var light = try environment(afterViewFontWeight: .light)
        light.font = .system(size: 20, weight: .heavy)
        let lightKey = try XCTUnwrap(Text.Style().fontKey(in: light))
        XCTAssertEqual(lightKey.modifiers, [
            .dynamic(Font.WeightModifier(weight: .light)),
        ])
        XCTAssertEqual(lightKey.font, .system(size: 20, weight: .heavy))
    }

    private func environment(
        afterViewFontWeight weight: Font.Weight?,
        startingWith modifiers: [AnyFontModifier] = []
    ) throws -> EnvironmentValues {
        let owner = try XCTUnwrap(
            EmptyView().fontWeight(weight) as? Modified
        )
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
