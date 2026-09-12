import Foundation
import Testing
import VVD
@testable import VUI

// These tests share the process-wide font cache and install an app context for
// deferred font loading. Keep them serial without requiring a GPU or window.
@Suite(.serialized)
final class TextStyleConsumerTests {
    private let previousApp: AppContext?
    private var bundleURLs: [URL] = []

    init() {
        previousApp = appContext
        appContext = StyleTestAppContext()
    }

    deinit {
        appContext = previousApp
        for url in bundleURLs { try? FileManager.default.removeItem(at: url) }
    }

    private func style(_ text: Text, parent: Text.Style = .init()) -> Text.Style {
        var result = parent
        for modifier in text.modifiers.reversed() { modifier.modify(style: &result) }
        return result
    }
    private func environment() -> EnvironmentValues {
        var result = EnvironmentValues()
        result.font = .system(size: 23)
        result.defaultFontRenderingMode = .vector()
        return result
    }
    private func resolve(_ text: Text, environment: EnvironmentValues? = nil) throws -> GraphicsContext.ResolvedText {
        return try #require(text._resolve(context: GraphTextResolutionContext(
            environment: environment ?? self.environment(), sceneResources: SceneResources()), referenceDate: Date(timeIntervalSince1970: 0)))
    }
    private func attributes(_ resolved: GraphicsContext.ResolvedText) -> [_ResolvedTextRunAttributes] {
        resolved.runs.compactMap { if case let .styledText(_, _, _, attributes) = $0 { attributes } else { nil } }
    }

    private func localizationBundle(_ languages: [String], development: String) throws -> Bundle {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        bundleURLs.append(url)
        let info: [String: Any] = ["CFBundleIdentifier": "test." + UUID().uuidString,
            "CFBundleDevelopmentRegion": development, "CFBundleLocalizations": languages]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Info.plist"))
        for language in languages {
            let folder = url.appendingPathComponent(language + ".lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "\"greeting\" = \"\(language.uppercased()) greeting\";\n"
                .write(to: folder.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        }
        let bundle = try #require(Bundle(url: url))
        try #require(Set(languages).isSubset(of: Set(bundle.localizations)))
        try #require(bundle.developmentLocalization == development)
        return bundle
    }

    private func language(_ value: TypesettingLanguage, on text: Text) -> Text {
        Text(storage: text.storage, modifiers: text.modifiers + [.anyTextModifier(LanguageTextModifier(value))])
    }

    private func concatenating(_ first: Text, _ second: Text) -> Text {
        Text(storage: .anyTextStorage(ConcatenatedTextStorage(first: first, second: second)), modifiers: [])
    }

    private func typesettingEnvironment() -> EnvironmentValues {
        var result = environment()
        result.locale = Locale(identifier: "en_US")
        result.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "ja"))
        result.typesettingConfiguration.languageAwareLineHeightRatio = .legacy
        return result
    }

    // ASSERTIONS textTypesettingStorageInitializationObserved
    // ASSERTIONS textLocalizedBundleLanguageFallbackObserved
    @Test
    func testStorageInitializationSeparatesEnvironmentLanguageFromBundleFallback() throws {
        let bundle = try localizationBundle(["fr"], development: "fr")
        let environment = typesettingEnvironment()
        let cases: [(Text, [String?], [String?])] = [
            (Text(verbatim: "A"), ["ja-Jpan-JP"], ["ja-Jpan-JP"]),
            (Text(AttributedString("A")), ["ja-Jpan-JP"], ["ja-Jpan-JP"]),
            (Text("greeting", bundle: bundle), ["fr-Latn-FR"], [nil]),
            (concatenating(Text(verbatim: "A"), Text(verbatim: "B")), ["ja-Jpan-JP", "ja-Jpan-JP"], ["ja-Jpan-JP", "ja-Jpan-JP"]),
            (concatenating(Text("greeting", bundle: bundle), Text(verbatim: "B")), ["fr-Latn-FR", nil], [nil, nil]),
            (Text(12, format: .number), [nil], [nil])
        ]
        for (text, languages, fontLanguages) in cases {
            let runs = attributes(try resolve(text, environment: environment))
            #expect(runs.map(\.language) == languages)
            #expect(runs.map { $0.fontResource?.language } == fontLanguages)
            #expect(runs.map { $0.fontResource?.languageAwareLineHeightRatio } == Array(repeating: 0.33, count: runs.count))
        }
    }

    // ASSERTIONS textLocalizedBundleLanguageFallbackObserved
    @Test
    func testBundleLanguageTracksTranslationAndMissingResourceFallback() throws {
        let multi = try localizationBundle(["en", "fr", "ja"], development: "en")
        let french = try localizationBundle(["fr"], development: "fr")
        let empty = try localizationBundle([], development: "de")
        let sparse = try localizationBundle(["en", "fr"], development: "en")
        try FileManager.default.removeItem(at: sparse.bundleURL.appendingPathComponent("fr.lproj/Localizable.strings"))
        for (locale, expected) in [("en_US", "en"), ("fr_FR", "fr"), ("ja_JP", "ja"), ("de_DE", "en")] {
            var environment = typesettingEnvironment()
            environment.locale = Locale(identifier: locale)
            let result = try resolve(Text("greeting", bundle: multi), environment: environment)
            #expect(result.attributedStorage.string == expected.uppercased() + " greeting")
            #expect(attributes(result).map(\.language) == [Locale.Language(identifier: expected).maximalIdentifier])
            #expect(attributes(result).first?.fontResource?.language == nil)
        }
        for (text, expectedString, expectedLanguage) in [
            (Text("missing-key", bundle: french), "missing-key", "fr-Latn-FR"),
            (Text("greeting", tableName: "Absent", bundle: french), "greeting", "fr-Latn-FR"),
            (Text("greeting", bundle: empty), "greeting", "de-Latn-DE")
        ] {
            let result = try resolve(text, environment: typesettingEnvironment())
            #expect(result.attributedStorage.string == expectedString)
            #expect(attributes(result).map(\.language) == [expectedLanguage])
        }
        var environment = typesettingEnvironment()
        environment.locale = Locale(identifier: "fr_FR")
        let result = try resolve(Text("greeting", bundle: sparse), environment: environment)
        #expect(result.attributedStorage.string == "greeting")
        #expect(attributes(result).map(\.language) == ["en-Latn-US"])
        let compatibility = _StringLocalizationValue("greeting").resolvedAttributedString(bundle: sparse, locale: environment.locale)
        #expect(String(compatibility.characters) == "greeting")
        #expect(AnySequence(compatibility.runs).map(\.languageIdentifier) == ["en"])
    }

    // ASSERTIONS textTypesettingNestedLanguageIsolationObserved
    @Test
    func testLocalizedRunsDoNotSeedChildrenAndChildOverridesRestoreParent() throws {
        let french = try localizationBundle(["fr"], development: "fr")
        let english = try localizationBundle(["en"], development: "en")
        let child = Text("greeting", bundle: english)
        let cases: [(Text, [String?], [String?])] = [
            (Text("prefix \(Text(verbatim: "child")) suffix", bundle: french), ["fr-Latn-FR", nil, "fr-Latn-FR"], [nil, nil, nil]),
            (Text("prefix \(child) suffix", bundle: french), ["fr-Latn-FR", "en-Latn-US", "fr-Latn-FR"], [nil, nil, nil]),
            (Text("prefix \(language(.explicit(Locale.Language(identifier: "de")), on: child)) suffix", bundle: french), ["fr-Latn-FR", "de-Latn-DE", "fr-Latn-FR"], [nil, "de-Latn-DE", nil]),
            (language(.explicit(Locale.Language(identifier: "de")), on:
                Text("prefix \(child) suffix", bundle: french)), ["de-Latn-DE", "de-Latn-DE", "de-Latn-DE"], ["de-Latn-DE", "de-Latn-DE", "de-Latn-DE"]),
            (language(.explicit(Locale.Language(identifier: "de")), on:
                Text("prefix \(language(.automatic, on: child)) suffix", bundle: french)), ["de-Latn-DE", "en-Latn-US", "de-Latn-DE"], ["de-Latn-DE", nil, "de-Latn-DE"])
        ]
        for (text, languages, fontLanguages) in cases {
            let runs = attributes(try resolve(text, environment: typesettingEnvironment()))
            #expect(runs.map(\.language) == languages)
            #expect(runs.map { $0.fontResource?.language } == fontLanguages)
        }
    }

    // ASSERTIONS textLanguageModifierResetsRatioObserved
    @Test
    func testLanguageModifierResetsRatioOnlyWithinItsStyleScope() throws {
        let bundle = try localizationBundle(["fr"], development: "fr")
        let explicitChild = language(.explicit(Locale.Language(identifier: "de")), on: Text(verbatim: "child"))
        let result = try resolve(Text("prefix \(explicitChild) suffix", bundle: bundle), environment: typesettingEnvironment())
        #expect(attributes(result).map { $0.fontResource?.languageAwareLineHeightRatio } == [0.33, nil, 0.33])
        var style = Text.Style()
        style.typesettingConfiguration.languageAwareLineHeightRatio = .legacy
        LanguageTextModifier(.automatic).modify(style: &style)
        #expect(style.typesettingConfiguration.languageAwareLineHeightRatio == .automatic)
        LanguageAwareLineHeightRatioTextModifier(.disable).modify(style: &style)
        #expect(style.typesettingConfiguration.languageAwareLineHeightRatio == .disable)
    }

    // ASSERTIONS textLocalizedBundleLanguageFallbackObserved
    @Test
    func testCompatibilityLocalizationCarriesLanguageBeforeStyleTransfer() throws {
        let bundle = try localizationBundle(["en", "fr"], development: "en")
        for (locale, expected) in [("fr_FR", "fr"), ("de_DE", "en")] {
            let value = _StringLocalizationValue("greeting").resolvedAttributedString(bundle: bundle, locale: Locale(identifier: locale))
            #expect(String(value.characters) == expected.uppercased() + " greeting")
            #expect(AnySequence(value.runs).map(\.languageIdentifier) == [expected])
            let result = try resolve(language(.automatic, on: Text(value)), environment: typesettingEnvironment())
            #expect(attributes(result).map(\.language) == [Locale.Language(identifier: expected).maximalIdentifier])
            #expect(attributes(result).first?.fontResource?.language == nil)
        }
    }

#if canImport(Darwin)
    // ASSERTIONS textLocalizedResourceEnvironmentLocaleObserved
    @Test
    func testLocalizedResourceUsesEnvironmentLocaleForPlainAndRenderedText() throws {
        let bundle = try localizationBundle(["en", "fr"], development: "en")
        let resource = LocalizedStringResource("greeting", locale: Locale(identifier: "en_US"), bundle: .atURL(bundle.bundleURL))
        var environment = typesettingEnvironment()
        environment.locale = Locale(identifier: "fr_FR")
        for (text, expected) in [(Text(resource), "FR greeting"), (Text("prefix \(resource) suffix", bundle: bundle), "prefix FR greeting suffix")] {
            #expect(text._resolveText(in: environment) == expected)
            let result = try resolve(text, environment: environment)
            #expect(result.attributedStorage.string == expected)
            #expect(attributes(result).allSatisfy { $0.language == "fr-Latn-FR" && $0.fontResource?.language == nil })
        }
        #expect(resource.locale == Locale(identifier: "en_US"))
    }
#endif

    // ASSERTIONS foundationLocalizationReplacementRunsObserved
    // ASSERTIONS textLocalizedBundleLanguageFallbackObserved
    @Test
    func testCompatibilityInitializerCarriesTableLocaleAndReplacementLanguage() throws {
        let bundle = try localizationBundle(["en", "fr"], development: "en")
        for language in ["en", "fr"] {
            try "\"value %lld\" = \"\(language.uppercased()) value %lld\";\n"
                .write(to: bundle.bundleURL.appendingPathComponent("\(language).lproj/Numbers.strings"),
                       atomically: true, encoding: .utf8)
        }
        var interpolation = _StringLocalizationValue.StringInterpolation(literalCapacity: 6, interpolationCount: 1)
        interpolation.appendLiteral("value ")
        interpolation.appendInterpolation(placeholder: .int, specifier: "%lld")
        let value = _StringLocalizationValue(stringInterpolation: interpolation)

        for (locale, language, maximalLanguage) in [
            ("en_US", "en", "en-Latn-US"), ("fr_FR", "fr", "fr-Latn-FR")
        ] {
#if canImport(Darwin)
            let attributed = value.resolvedAttributedString(replacements: [Int64(42)],
                applyReplacementIndexAttribute: true,
                table: "Numbers", bundle: bundle, locale: Locale(identifier: locale))
#else
            // Exercise the installed Foundation-name bridge on these ports.
            let aliasedValue: String.LocalizationValue = value
            var options = AttributedString.LocalizationOptions()
            options.replacements = [Int64(42)]
            options.applyReplacementIndexAttribute = true
            let attributed = AttributedString(localized: aliasedValue, options: options,
                table: "Numbers", bundle: bundle, locale: Locale(identifier: locale))
#endif
            #expect(String(attributed.characters) == language.uppercased() + " value 42")
            #expect(AnySequence(attributed.runs).map(\.replacementIndex) == [nil, 1])
            #expect(AnySequence(attributed.runs).map(\.languageIdentifier) == [language, language])
            let rendered = try resolve(self.language(.automatic, on: Text(attributed)),
                                       environment: typesettingEnvironment())
            let runs = attributes(rendered)
            #expect(runs.map(\.language) == [maximalLanguage, maximalLanguage])
            #expect(runs.map { $0.fontResource?.pointSize } == [23, 23])
            #expect(runs.map { $0.fontResource?.language } == [nil, nil])
        }
    }

    // ASSERTIONS textTypesettingStorageInitializationObserved
    // ASSERTIONS textTypesettingNestedLanguageIsolationObserved
    // ASSERTIONS textLocalizedResourceEnvironmentLocaleObserved
    @Test
    func testLocalizedResourceFallbackUsesPlainRenderedAndInterpolatedConsumers() throws {
        // A missing key exercises the resource surface shared by every port.
        // Translated resource selection additionally needs main-bundle resources
        // on ports whose resource carrier has no explicit bundle member.
        let resource = LocalizedStringResource("portable-resource-missing-key")
        let original = resource
        let french = try localizationBundle(["fr"], development: "fr")
        for locale in ["en_US", "fr_FR"] {
            var environment = typesettingEnvironment()
            environment.locale = Locale(identifier: locale)
            for (text, expected, count) in [
                (Text(resource), "portable-resource-missing-key", 1),
                (Text("prefix \(resource) suffix", bundle: french), "prefix portable-resource-missing-key suffix", 3)
            ] {
                #expect(!text.allowsTypesettingLanguage())
                #expect(text._resolveText(in: environment) == expected)
                let result = try resolve(text, environment: environment)
                #expect(result.attributedStorage.string == expected)
                let runs = attributes(result)
                #expect(runs.count == count)
                #expect(runs.map { $0.fontResource?.pointSize } == Array(repeating: 23, count: count))
                #expect(runs.map { $0.fontResource?.language } == Array<String?>(repeating: nil, count: count))
                #expect(runs.map { $0.fontResource?.languageAwareLineHeightRatio } == Array(repeating: 0.33, count: count))
            }
            let explicit = language(.explicit(Locale.Language(identifier: "de")), on: Text(resource))
            let runs = attributes(try resolve(explicit, environment: environment))
            #expect(runs.map(\.language) == ["de-Latn-DE"])
            #expect(runs.map { $0.fontResource?.language } == ["de-Latn-DE"])
            #expect(runs.map { $0.fontResource?.languageAwareLineHeightRatio } == [nil])
        }
        #expect(resource == original)
    }

    // ASSERTIONS fontResolvedRetainedContextObserved
    // ASSERTIONS fontTextStyleDescriptorCopiesObserved
    // ASSERTIONS textTypesettingRatioFontInputsObserved
    @Test
    func testGlyphsRetainDistinctStyleRequestsWhileSharingTheSameTypeface() throws {
        let text = concatenating(Text(verbatim: "A").font(.system(.body)),
                                 Text(verbatim: "B").font(.system(size: 13)))
        let result = try resolve(text, environment: typesettingEnvironment())
        let resources = try attributes(result).map { try #require($0.fontResource) }
        try #require(resources.count == 2)
        #expect(resources[0] !== resources[1])
        #expect(resources[0].textStyle == .body)
        #expect(resources[1].textStyle == nil)
        let glyphs = result.makeGlyphs().flatMap(\.glyphs)
        try #require(glyphs.count == 2)
        #expect(glyphs[0].face.isEqual(to: glyphs[1].face))
        for index in glyphs.indices {
            #expect(glyphs[index].style.fontResource === resources[index])
            #expect(glyphs[index].style.fontResource?.language == "ja-Jpan-JP")
            #expect(glyphs[index].style.fontResource?.languageAwareLineHeightRatio == 0.33)
            #expect(glyphs[index].face.designMetrics?.unitsPerEM == 2048)
        }
    }

    // ASSERTIONS fontLeadingNativeMetricConsumerObserved
    // ASSERTIONS fontResolvedRetainedContextObserved
    @Test
    func testFallbackGlyphKeepsItsDesignMetricsAndTheOriginalFontRequest() throws {
        let result = try resolve(Text(verbatim: "A한").font(.system(.body)),
                                 environment: typesettingEnvironment())
        let resource = try #require(attributes(result).first?.fontResource)
        let glyphs = result.makeGlyphs().flatMap(\.glyphs)
        try #require(glyphs.count == 2)
        #expect(glyphs[0].style.fontResource === resource)
        #expect(glyphs[1].style.fontResource === resource)
        #expect(resource.textStyle == .body)
        #expect(!glyphs[0].face.isEqual(to: glyphs[1].face))
        #expect(glyphs[0].face.designMetrics?.unitsPerEM == 2048)
        #expect(glyphs[1].face.designMetrics?.unitsPerEM == 1000)
        #expect(glyphs[0].lineBoxAscender == glyphs[1].lineBoxAscender)
        #expect(glyphs[0].lineBoxDescender == glyphs[1].lineBoxDescender)
    }

    // ASSERTIONS fontResolvedRetainedContextObserved
    // ASSERTIONS fontLeadingExtraDataOwnershipObserved
    @Test
    func testWrappingAndTruncationRetainFontRequestsAndDesignInputs() throws {
        let result = try resolve(Text(verbatim: "ABCDE FGHIJ KLMNO").font(.system(.body)),
                                 environment: typesettingEnvironment())
        let resource = try #require(attributes(result).first?.fontResource)
        let wrapped = result.makeGlyphs(maxWidth: 40)
        try #require(wrapped.count > 1)
        for glyph in wrapped.flatMap(\.glyphs) {
            #expect(glyph.style.fontResource === resource)
            #expect(glyph.face.designMetrics?.unitsPerEM == 2048)
        }
        for mode: Text.TruncationMode in [.head, .middle, .tail] {
            let lines = result.makeGlyphs(maxWidth: 40, lineLimit: 1, truncationMode: mode)
            let line = try #require(lines.first)
            #expect(lines.count == 1)
            #expect(line.isTruncated)
            #expect(line.glyphs.filter(\.isTruncationToken).count == 1)
            for glyph in line.glyphs {
                #expect(glyph.style.fontResource === resource)
                #expect(glyph.face.designMetrics?.unitsPerEM == 2048)
                #expect(glyph.face.designMetrics?.lineGap == 0)
            }
        }
    }

    // ASSERTIONS textStyleInitializationAndNestedOwnersObserved
    // ASSERTIONS textFontModifierTraversalOrderObserved
    @Test
    func testBaseStatesAndReversedModifierOrderReachResources() throws {
        let environment = environment()
        let cases: [(Text, CGFloat)] = [
            (Text(verbatim: "A"), 23),
            (Text(verbatim: "A").font(nil), 13),
            (Text(verbatim: "A").font(.system(size: 31)).font(.system(size: 41)), 31),
            (Text(verbatim: "A").font(nil).font(.system(size: 31)), 13)
        ]
        for (text, size) in cases {
            let resolved = try resolve(text, environment: environment)
            #expect(attributes(resolved).first?.fontResource?.pointSize == size)
            #expect((resolved.measure().width) > 0)
        }
        #expect(Text.Style().baseFont.resolve(in: environment, includeDefaultAttributes: false) == nil)
        var defaults = environment
        defaults.defaultFont = .system(size: 19)
        #expect(try #require(style(Text(verbatim: "A").font(nil)).fontKey(in: defaults)).font == .system(size: 19))
        let ordered = style(Text(verbatim: "A").fontWeight(.heavy).fontWeight(.light))
        #expect(ordered.fontModifiers == [.dynamic(Font.WeightModifier(weight: .light)), .dynamic(Font.WeightModifier(weight: .heavy))])
    }

    // ASSERTIONS textFontInheritedModifierClearingObserved
    // ASSERTIONS textStyleFontTraitsDispatchObserved
    // ASSERTIONS textStyleFontAttributeCacheInputsObserved
    @Test
    func testFontCacheClearsInheritedTypesWhileTraitsKeepThem() throws {
        var environment = environment()
        environment.fontModifiers = [.dynamic(Font.WeightModifier(weight: .heavy)), .static(Font.ItalicModifier.self)]
        let cleared = style(Text(verbatim: "A").fontWeight(nil))
        let key = try #require(cleared.fontKey(in: environment))
        #expect(key.context.fontModifiers.isEmpty)
        #expect(key.modifiers == [.static(Font.ItalicModifier.self)])
        #expect(cleared.fontTraits(in: environment).weight == CGFloat(Float(Font.Weight.heavy.value)))
        var readded = cleared
        readded.addFontModifier(.dynamic(Font.WeightModifier(weight: .light)))
        #expect(readded.clearedFontModifiers.contains(ObjectIdentifier(Font.WeightModifier.self)))
        #expect(try #require(readded.fontKey(in: environment)).modifiers == [.static(Font.ItalicModifier.self), .dynamic(Font.WeightModifier(weight: .light))])
        let provider = style(Text(verbatim: "A").font(.system(size: 31).weight(.heavy)).fontWeight(nil))
        #expect((Font.FontCache.shared[try #require(provider.fontKey(in: environment))].provider as? SystemFontProvider)?.weight == .heavy)
    }

    // ASSERTIONS textFontNestedStyleIsolationObserved
    // ASSERTIONS textParagraphNestedRunCacheObserved
    @Test
    func testNestedTextCopiesStyleAndSharesParagraphUntilUTF16Boundary() throws {
        let first = Text(verbatim: "😀e\u{301}\n").font(nil).fontWeight(nil)
        let second = Text(verbatim: "B")
        let text = Text(storage: .anyTextStorage(ConcatenatedTextStorage(first: first, second: second)), modifiers: [])
            .font(.system(size: 41)).fontWeight(.heavy)
        let result = try resolve(text)
        let runs = attributes(result)
        #expect(runs.map { $0.fontResource?.pointSize } == [13, 41])
        #expect(runs.map { ($0.fontResource?.provider as? SystemFontProvider)?.weight } == [VUI.Font.Weight.regular, VUI.Font.Weight.heavy])
        #expect(!(runs[0].paragraphStyle === runs[1].paragraphStyle))
        #expect(result.resolvedProperties?.paragraph.startIndex == 6)
        #expect(result.resolvedProperties?.paragraph.cachedStyle == nil)
        let adjacent = try resolve(Text(storage: .anyTextStorage(ConcatenatedTextStorage(
            first: Text(verbatim: "A").font(.system(size: 31)), second: second)), modifiers: []).font(.system(size: 41)))
        let adjacentRuns = attributes(adjacent)
        #expect(adjacentRuns[0].paragraphStyle === adjacentRuns[1].paragraphStyle)
        #expect(adjacentRuns.map { $0.fontResource?.pointSize } == [31, 41])
    }

    // ASSERTIONS textAttributedStyleFontMergeObserved
    // ASSERTIONS textAttributedStyleIntentDispatchObserved
    // ASSERTIONS textAttributedStyleDictionaryTransferObserved
    @Test
    func testAttributedTransferReaddsIntentsAndKeepsSpacingAndLanguage() throws {
        var inherited = environment()
        inherited.fontModifiers = [.static(Font.BoldModifier.self)]
        var parent = style(Text(verbatim: "A").bold(false).tracking(11).font(.system(size: 41)))
        var dictionary: [NSAttributedString.Key: Any] = [
            .coreFont: VUI.Font.system(size: 31), .coreKern: CGFloat(3),
            .init("NSInlinePresentationIntent"): InlinePresentationIntent([.emphasized, .stronglyEmphasized, .code]),
            .init("NSLanguage"): "ja"
        ]
        dictionary.transferAttributedStringStyles(to: &parent)
        #expect(dictionary.count == 1)
        #expect(dictionary[.init("NSLanguage")] as? String == "ja")
        let key = try #require(parent.fontKey(in: inherited))
        #expect(key.modifiers == [.static(Font.ItalicModifier.self), .static(Font.BoldModifier.self), .static(Font.MonospacedModifier.self)])
        var properties = Text.ResolvedProperties()
        let attributes = parent.nsAttributes(in: inherited, properties: &properties)
        #expect(attributes.fontResource?.pointSize == 31)
        #expect(attributes.kern == 3)
        #expect(attributes.tracking == 11)
        #expect(attributes.language == "ja-Jpan-JP")
        #expect(properties.paragraph.compositionLanguage == 2)
    }

    // ASSERTIONS textAttributedStyleRunIsolationObserved
    @Test
    func testActualAttributedRunsKeepIndependentParentsAndDrawSpacing() throws {
        var a = AttributedString("A")
        a.font = VUI.Font.system(size: 31)
        a[AttributeScopes.CoreAttributes.KerningAttribute.self] = 3
        a.foregroundColor = VUI.Color.red
        var b = AttributedString("😀e\u{301}")
        b[AttributeScopes.CoreAttributes.TrackingAttribute.self] = 5
        b.inlinePresentationIntent = .stronglyEmphasized
        let rich = a + b + AttributedString("C")
        let resolved = try resolve(Text(rich).font(.system(size: 41)).tracking(11).bold(false))
        let runs = attributes(resolved)
        #expect(runs.map { $0.fontResource?.pointSize } == [31, 41, 41])
        #expect(runs.map(\.kern) == [3, nil, nil])
        #expect(runs.map(\.tracking) == [11, 5, 11])
        #expect((runs[1].fontResource?.provider as? SystemFontProvider)?.weight == .bold)
        #expect((runs[2].fontResource?.provider as? SystemFontProvider)?.weight == .regular)
        #expect(runs.allSatisfy { $0.paragraphStyle === runs[0].paragraphStyle })
        #expect(resolved.attributedStorage.length == 6)
        #expect((resolved.makeGlyphs().first?.width ?? 0) > 0)
    }

    // ASSERTIONS textTypesettingAttributeProducerObserved
    // ASSERTIONS textTypesettingRatioFontInputsObserved
    // ASSERTIONS fontModifierTagsAndCodingObserved
    @Test
    func testLanguageAndRatioFollowFontModifiersAndSurviveDescriptorCopies() throws {
        var style = Text.Style()
        style.fontModifiers = [.dynamic(Font.WeightModifier(weight: .heavy))]
        style.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "ja"))
        style.typesettingConfiguration.languageAwareLineHeightRatio = .custom(0.5)
        let key = try #require(style.fontKey(in: environment()))
        #expect(key.modifiers == [.dynamic(Font.WeightModifier(weight: .heavy)),
            .dynamic(LanguageFontModifier(identifier: "ja-Jpan-JP")),
            .dynamic(LanguageAwareLineHeightRatioFontModifier(ratio: 0.5))])
        let resource = Font.FontCache.shared[key]
        let descriptor = resource.descriptor().width(0.1).weight(.light).monospaced(true).adding(features: Font.MonospacedDigitModifier.shapingFeatures)
        #expect(descriptor.language == "ja-Jpan-JP")
        #expect(descriptor.languageAwareLineHeightRatio == 0.5)
        let fonts = [
            Font(provider: FontBox(Font.ModifierProvider(base: .system(size: 23),
                modifier: LanguageFontModifier(identifier: "ja-Jpan-JP")))),
            Font(provider: FontBox(Font.ModifierProvider(base: .system(size: 23),
                modifier: LanguageAwareLineHeightRatioFontModifier(ratio: 0.5))))
        ]
        for font in fonts {
            let encoded = try JSONEncoder().encode(font.codingProxy)
            let decoded = try JSONDecoder().decode(Font.CodingProxy.self, from: encoded).base
            #expect(decoded == font)
        }
        for (ratio, expected) in [(TypesettingLanguageAwareLineHeightRatio.disable, 0.0), (.legacy, 0.33), (.custom(-1), 0), (.custom(2), 1)] {
            style.typesettingConfiguration.languageAwareLineHeightRatio = ratio
            #expect(Font.FontCache.shared[try #require(style.fontKey(in: environment()))].languageAwareLineHeightRatio == expected)
        }
    }

    // ASSERTIONS textParagraphStyleCacheReuseObserved
    // ASSERTIONS textParagraphBoundaryCacheFinalizationObserved
    // ASSERTIONS textParagraphAlignmentAggregationObserved
    @Test
    func testParagraphCacheCopiesShareIdentityAndConflictsRemainAbsorbing() {
        var properties = Text.ResolvedProperties()
        let environment = environment()
        let first = properties.paragraph.style(environment: environment, alignment: .left, writingDirection: nil, lineHeight: .exact(points: 27))
        var copy = properties.paragraph
        let cached = copy.style(environment: environment, alignment: .right, writingDirection: .rightToLeft, lineHeight: .exact(points: 41))
        #expect(first === cached)
        #expect(cached.baselineInterval == .exact(points: 27))
        properties.markParagraphBoundary(at: 1, in: "A", environment: environment)
        #expect(properties.multilineTextAlignment == .leading)
        #expect(properties.paragraph.cachedStyle == nil)
        #expect(copy.cachedStyle === first)
        _ = properties.paragraph.style(environment: environment, alignment: .right, writingDirection: nil, lineHeight: nil)
        properties.markParagraphBoundary(at: 2, in: "AB", environment: environment)
        #expect(properties.multilineTextAlignment == nil)
        _ = properties.paragraph.style(environment: environment, alignment: .left, writingDirection: nil, lineHeight: nil)
        properties.markParagraphBoundary(at: 3, in: "ABC", environment: environment)
        #expect(properties.multilineTextAlignment == nil)
    }

    // ASSERTIONS textParagraphEnvironmentProducerObserved
    // ASSERTIONS textParagraphAlignmentWritingStrategiesObserved
    // ASSERTIONS textParagraphMetricsAndJustificationObserved
    // ASSERTIONS textParagraphRedactionPostprocessingObserved
    @Test
    func testParagraphProducerSeparatesConstructorAndPublication() {
        var environment = environment()
        environment.textAlignmentStrategy = .writingDirectionBased
        environment.multilineTextAlignment = .trailing
        environment.layoutDirection = .rightToLeft
        environment.writingMode = .verticalRightToLeft
        environment.lineHeight = .exact(points: 39)
        environment.lineSpacing = 3
        environment.hyphenationFactor = 0.8
        environment.paragraphTypesetting = .balanced
        environment.avoidsOrphans = false
        var context = ParagraphStyleResolutionContext(environment)
        let initial = makeParagraphStyle(context: context, alignment: nil, fallbackAlignment: .layoutBased,
            writingDirection: nil, fallbackWritingDirection: .contentBased, lineHeight: .variable)
        #expect(initial.horizontalAlignment == .trailing)
        #expect(initial.baseWritingDirection == .natural)
        #expect(initial.spansAllLines)
        #expect(initial.baselineInterval == .variable)
        #expect(initial.lineBreakStrategy == 65534)
        #expect(initial.hyphenationFactor == Float(0.8))
        context.bodyHeadOutdent = 2
        let outdent = makeParagraphStyle(context: context, alignment: nil, fallbackAlignment: .layoutBased,
            writingDirection: .rightToLeft, fallbackWritingDirection: .contentBased, lineHeight: nil)
        #expect(outdent.baseWritingDirection == .leftToRight)
        environment.shouldRedactContent = true
        var paragraph = Text.ResolvedProperties.Paragraph()
        paragraph.compositionLanguage = 2
        let redacted = paragraph.style(environment: environment, alignment: nil, writingDirection: nil, lineHeight: nil)
        #expect(redacted.compositionLanguage == 2)
        #expect(redacted.baseWritingDirection == .rightToLeft)
        #expect(redacted.lineBreakMode == 1)
        #expect(redacted.fullyJustified)
    }

    // ASSERTIONS textParagraphCompositionLanguageProducerObserved
    @Test
    func testCompositionResetsEveryRunButCacheRetainsFirstLanguage() {
        var properties = Text.ResolvedProperties()
        var style = Text.Style()
        style.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "ja"))
        let a = style.nsAttributes(in: environment(), properties: &properties)
        style.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        let b = style.nsAttributes(in: environment(), properties: &properties)
        #expect(a.paragraphStyle === b.paragraphStyle)
        #expect(properties.paragraph.compositionLanguage == 1)
        #expect(b.paragraphStyle?.compositionLanguage == 2)
        for (language, category) in [("ja", 2), ("zh", 3), ("zh-Hant", 4), ("wuu-Hans", 3), ("yue-Hant", 4), ("JA", 1), ("jargon", 1), ("ar", 1)] {
            #expect(textCompositionLanguage(language) == category, "\(language)")
        }
    }

    // ASSERTIONS textParagraphNaturalDirectionResolutionObserved
    @Test
    func testKnownLanguageAndEmptyRangeDirectionFinalization() {
        var environment = environment()
        environment.textAlignmentStrategy = .writingDirectionBased
        environment.layoutDirection = .rightToLeft
        var properties = Text.ResolvedProperties()
        var style = Text.Style()
        style.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "ar"))
        let attributes = style.nsAttributes(in: environment, properties: &properties)
        properties.markParagraphBoundary(at: 3, in: "ABC", environment: environment)
        #expect(attributes.paragraphStyle?.baseWritingDirection == .rightToLeft)
        let empty = properties.paragraph.style(environment: environment, alignment: nil, writingDirection: nil, lineHeight: nil)
        properties.markParagraphBoundary(at: 3, in: "ABC", environment: environment)
        #expect(empty.baseWritingDirection == .rightToLeft)
    }

    // ASSERTIONS textStylePayloadOwnerStructureObserved
    // ASSERTIONS textParagraphAndEncapsulationPayloadObserved
    // ASSERTIONS textSpeechAccessibilityPayloadObserved
    @Test
    func testTypedPayloadsReachActualAttributedRunsAndKeepSiblingIsolation() throws {
        #expect(Mirror(reflecting: Text.Style()).children.count == 24)
        let resource = VUI.Font.system(size: 23).platformFont(in: environment().fontResolutionContext)
        let info = TextGlyphInfo(font: resource, glyphIndex: 42, baseString: "A")
        var rich = AttributedString("A")
        rich[TextGlyphInfoAttribute.self] = info
        rich[TextLineHeightAttribute.self] = .exact(points: 27)
        rich[TextParagraphAlignmentAttribute.self] = .right
        rich[TextParagraphWritingDirectionAttribute.self] = .rightToLeft
        rich[TextScaleAttribute.self] = .secondary
        rich[TextAdaptiveImageGlyphAttribute.self] = .init(imageContent: Data([1, 2]), contentIdentifier: "fixture", contentDescription: "resource transport only")
        let resolved = try resolve(Text(rich + AttributedString("B")))
        let runs = attributes(resolved)
        #expect(runs[0].glyphInfo === info)
        #expect(runs[1].glyphInfo == nil)
        #expect(runs[0].textScale == .secondary)
        #expect(runs[1].textScale == nil)
        #expect(runs[0].adaptiveImageProvider != nil)
        #expect(runs[1].adaptiveImageProvider == nil)
        #expect(runs[0].paragraphStyle?.baselineInterval == .exact(points: 27))
        #expect(runs[0].paragraphStyle === runs[1].paragraphStyle)
        var style = Text.Style()
        SpeechModifier(.init(alwaysIncludesPunctuation: true, adjustedPitch: 0.75)).modify(style: &style)
        SpeechModifier(.init(spellsOutCharacters: true)).modify(style: &style)
        AccessibilityTextModifier(.init(headingLevel: .h2, label: Text(verbatim: "spoken"))).modify(style: &style)
        #expect(style.speech?.alwaysIncludesPunctuation == true)
        #expect(style.speech?.spellsOutCharacters == true)
        #expect(style.speech?.adjustedPitch == 0.75)
        #expect(style.accessibility?.headingLevel == .h2)
        style.encapsulation = .init(lineWeight: 2.5, minimumWidth: 33)
        var properties = Text.ResolvedProperties()
        let output = style.nsAttributes(in: environment(), properties: &properties)
        #expect(output.encapsulation?.lineWeight == 2.5)
        #expect(output.encapsulation?.minimumWidth == 33)
        #expect(!(output.nsAttributes.keys.contains { $0.rawValue.contains("Speech") }))
    }

    // ASSERTIONS textScaleAttributeOwnerObserved
    // ASSERTIONS textShadowProducerAndAttributeObserved
    // ASSERTIONS textTransitionOptionAndStorageObserved
    // ASSERTIONS textEffectModifierLifetimeObserved
    // ASSERTIONS textAdaptiveImagePayloadConsumerObserved
    @Test
    func testEffectResourcesAreRetainedAndTransitionPrecedenceIsSeparate() throws {
        var properties = Text.ResolvedProperties()
        var style = Text.Style()
        weak var weakShadow: TextShadowModifier?
        do {
            let shadow = TextShadowModifier(_ShadowEffect(color: .clear, radius: 3, offset: CGSize(width: 2, height: 4)))
            weakShadow = shadow
            shadow.modify(style: &style)
        }
        var copy: Text.Style? = style
        style.transition = TextTransitionModifier(.init(transition: .opacity))
        let a = style.nsAttributes(in: environment(), properties: &properties, options: .includeTransitions)
        #expect(a.shadow != nil)
        #expect(properties.transitions.isEmpty)
        #expect(abs(properties.insets.bottom - (-12.4)) <= 1e-8)
        style.shadow = nil
        withExtendedLifetime(copy) { #expect(weakShadow != nil) }
        copy = nil
        #expect(weakShadow == nil)
        let b = style.nsAttributes(in: environment(), properties: &properties, options: .includeTransitions)
        let c = style.nsAttributes(in: environment(), properties: &properties, options: .includeTransitions)
        #expect(b.transitionIndex == 0)
        #expect(c.transitionIndex == 1)
        style.scale = .default
        var environment = environment()
        environment.textScale = .secondary
        #expect(style.nsAttributes(in: environment, properties: &properties).textScale == nil)
        style.adaptiveImageGlyph = TextAdaptiveImageGlyph(imageContent: Data([1, 2, 3]), contentIdentifier: "fixture", contentDescription: "fixture")
        let d = style.nsAttributes(in: environment, properties: &properties)
        let e = style.nsAttributes(in: environment, properties: &properties)
        #expect(!(d.adaptiveImageProvider === e.adaptiveImageProvider))
        #expect(d.adaptiveImageProvider?.glyph == e.adaptiveImageProvider?.glyph)
        _ = copy
    }
}

final class StyleTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext?
    init(graphicsDeviceContext: GraphicsDeviceContext? = nil) { self.graphicsDeviceContext = graphicsDeviceContext }
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
