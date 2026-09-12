import Foundation
import Testing
@testable import VUI

// XCTest discovery in the current supported Windows toolchain cannot enumerate
// @MainActor test methods. Keep this focused runtime smoke in Swift Testing so
// the compatibility path can be executed without weakening unrelated UI tests.
@Test
func portableLocalizationCompatibilityRuntimeSmoke() throws {
    // ASSERTIONS foundationLocalizationReplacementRunsObserved
    // ASSERTIONS foundationLocalizationLiteralFormatBoundaryObserved
    var interpolation = _StringLocalizationValue.StringInterpolation(
        literalCapacity: 6,
        interpolationCount: 1
    )
    interpolation.appendLiteral("value ")
    interpolation.appendInterpolation(placeholder: .int, specifier: "%lld")
    let value = _StringLocalizationValue(
        stringInterpolation: interpolation
    )

    let resolved = value.resolvedLocalization(
        replacements: [Int64(42)],
        applyReplacementIndexAttribute: true,
        locale: Locale(identifier: "en_US")
    )
    #expect(resolved.string == "value 42")
    #expect(resolved.runs.count == 2)

    let literalRun = try #require(resolved.runs.first)
    #expect(literalRun.text == "value ")
    #expect(literalRun.replacementIndex == nil)
    #expect(literalRun.presentationIntent == nil)

    let replacementRun = try #require(resolved.runs.last)
    #expect(replacementRun.text == "42")
    #expect(replacementRun.replacementIndex == 1)
    #expect(replacementRun.presentationIntent == nil)

    let attributed = value.resolvedAttributedString(
        replacements: [Int64(42)],
        applyReplacementIndexAttribute: true,
        locale: Locale(identifier: "en_US")
    )
    #expect(String(attributed.characters) == "value 42")

    #expect(
        _StringLocalizationValue("greeting").resolvedString(
            bundle: .module,
            locale: Locale(identifier: "en")
        ) == "Hello"
    )

    #expect(
        _StringLocalizationValue("greeting").resolvedString(
            bundle: .module,
            locale: Locale(identifier: "ko")
        ) == "안녕하세요"
    )

    for (language, expected) in [("en", "Hello"), ("ko", "안녕하세요")] {
        // ASSERTIONS textLocalizedBundleLanguageFallbackObserved
        let localized = _StringLocalizationValue("greeting").resolvedLocalization(
            bundle: .module, locale: Locale(identifier: language)
        )
        #expect(localized.string == expected)
        #expect(localized.languageIdentifier == language)
        #expect(AnySequence(localized.attributedString().runs).map(\.languageIdentifier) == [language])
    }

    #if !canImport(Darwin)
    let aliasedValue: String.LocalizationValue = "plain"
    #expect(aliasedValue == _StringLocalizationValue("plain"))
    let aliasedResource = LocalizedStringResource(aliasedValue)
    #expect(aliasedResource == _LocalizedStringResource(aliasedValue))
    #endif
}

@Test
func portableLocalizationPluralRuntimeSmoke() {
    // ASSERTIONS foundationLocalizationStringsDictionaryObserved
    var pluralInterpolation =
        _StringLocalizationValue.StringInterpolation(
            literalCapacity: 7,
            interpolationCount: 1
        )
    pluralInterpolation.appendLiteral("apples ")
    pluralInterpolation.appendInterpolation(
        placeholder: .int,
        specifier: "%lld"
    )
    let plural = _StringLocalizationValue(
        stringInterpolation: pluralInterpolation
    )
    #expect(
        plural.resolvedString(
            replacements: [Int64(1)],
            bundle: .module,
            locale: Locale(identifier: "en")
        ) == "1 apple"
    )
    let englishOther = plural.resolvedLocalization(
        replacements: [Int64(2)],
        applyReplacementIndexAttribute: true,
        bundle: .module,
        locale: Locale(identifier: "en")
    )
    #expect(englishOther.string == "2 apples")
    // ASSERTIONS textLocalizedBundleLanguageFallbackObserved
    #expect(englishOther.languageIdentifier == "en")
    #expect(englishOther.runs.count == 1)
    #expect(englishOther.runs.first?.replacementIndex == 1)
    #expect(AnySequence(englishOther.attributedString().runs).map(\.languageIdentifier) == ["en"])

    let koreanOther = plural.resolvedLocalization(
        replacements: [Int64(2)],
        applyReplacementIndexAttribute: true,
        bundle: .module,
        locale: Locale(identifier: "ko")
    )
    #expect(
        koreanOther.string == "사과 2개"
    )
    #expect(koreanOther.runs.count == 1)
    #expect(koreanOther.runs.first?.replacementIndex == 1)
    #expect(koreanOther.languageIdentifier == "ko")
    #expect(AnySequence(koreanOther.attributedString().runs).map(\.languageIdentifier) == ["ko"])
}
