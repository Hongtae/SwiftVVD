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

    private func fontURL(_ name: String) -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Sources/VUI/Resources/Fonts").appendingPathComponent(name)
    }

    // ASSERTIONS fontCustomNamedOutsetTraitBoundaryObserved
    // ASSERTIONS fontSelectedWeightCopiesObserved
    @Test func namedFontSelectionSurvivesResolvedCopiesAndReachesDrawingMargins() throws {
        var env = environment()
        env.displayScale = 2
        let font = Font.custom("NanumSquareNeo-Variable", fixedSize: 23)
        let resolvedFont = font.resolved(in: env)
        for request in [font, resolvedFont, resolvedFont.resolved(in: env), resolvedFont.monospacedDigit()] {
            let source = try resolve(Text(verbatim: "Ågj").font(request), environment: env)
            let resource = try #require(attributes(source).first?.fontResource)
            #expect(resource.descriptor().resolvedWeight == 0)
            for (language, edges): (String, [CGFloat]) in [
                ("en", [4.290052, 3.279317, 2.576023, 6.487472]),
                ("ur", [0.831082, 4.756745, 2.576023, 7.574843])
            ] {
                let text = GraphicsContext.ResolvedText(runs: source.runs, scaleFactor: source.scaleFactor,
                    displayScale: 2, preferredLanguages: [language])
                let metrics = try #require(text.maximumFontMetrics)
                let observed = [metrics.outsets.leading, metrics.outsets.top, metrics.outsets.trailing, metrics.outsets.bottom]
                for (actual, expected) in zip(observed, edges) { #expect(abs(actual - expected) < 1e-10) }
                #expect(abs(metrics.ascender - 19.550140380859375) < 1e-10)
                #expect(abs(metrics.descender + 5.8651123046875) < 1e-10)
                let styled = ResolvedStyledText(resolvedText: text)
                let margins = styled.drawingMargins
                #expect(margins.leading == (language == "en" ? 4.5 : 1))
                #expect(margins.trailing == 3)
                let frame = styled.frame(in: text.measure(), renderer: nil)
                #expect(frame.minX == -margins.leading)
                #expect(frame.minY == -margins.top)
                let layout = text.makeLayout(in: .init(width: 300, height: 100), layoutDirection: .leftToRight,
                    origin: .init(x: margins.leading, y: margins.top))
                #expect(layout.count == 1)
                let line = try #require(layout.first)
                #expect(line.typographicBounds.ascent == 20)
                #expect(line.typographicBounds.descent == 6)
                #expect(line.origin.x == margins.leading)
                #expect(line.origin.y == 20 + margins.top)
            }
        }
    }

    // ASSERTIONS fontSelectedWeightCopiesObserved
    @Test func namedFontModifiersUseSelectedWeightsForOutsetRows() throws {
        let nanum = Font.custom("NanumSquareNeo-Variable", fixedSize: 23)
        let roboto = Font.custom("Roboto-Regular", fixedSize: 23)
        let cases: [(VUI.Font, Float, [CGFloat])] = [
            (nanum.weight(.regular), 0, [4.290052, 3.279317, 2.576023, 6.487472]),
            (.custom("NanumSquareNeo-Variable_Regular", fixedSize: 23), -0.23,
                [4.166542, 3.144560, 2.415023, 6.395449]),
            (nanum.weight(.heavy), 0.4, [4.709319, 3.279317, 3.289023, 6.809472]),
            (.custom("NanumSquareNeo-Variable_Heavy", fixedSize: 23), 0.8,
                [5.098663, 3.316692, 3.542023, 7.062472]),
            (roboto.weight(.heavy), 0.6, [4.888995, 3.523692, 3.657023, 7.177472]),
            (roboto.weight(.heavy).italic(), 0.6, [4.888995, 3.523692, 3.657023, 7.177472]),
            (roboto.weight(.light).italic().weight(.heavy), 0.6,
                [4.888995, 3.523692, 3.657023, 7.177472]),
            (roboto.italic().weight(.light).weight(.heavy), 0.6,
                [4.888995, 3.523692, 3.657023, 7.177472])
        ]
        for (font, weight, expected) in cases {
            for copy in [font, font.resolved(in: environment()).monospacedDigit()] {
                let source = try resolve(Text(verbatim: "Ågj").font(copy))
                let resource = try #require(attributes(source).first?.fontResource)
                #expect(resource.selectedWeight == CGFloat(weight))
                let text = GraphicsContext.ResolvedText(runs: source.runs, scaleFactor: source.scaleFactor,
                    preferredLanguages: ["en"])
                let edges = try #require(text.maximumFontMetrics).outsets
                let actual = [edges.leading, edges.top, edges.trailing, edges.bottom]
                for (value, target) in zip(actual, expected) { #expect(abs(value - target) < 1e-10) }
            }
        }
    }

    // ASSERTIONS fontCustomNamedOutsetTraitBoundaryObserved
    @Test func suppliedFontWeightsRetainTheirPhysicalOutsetFallback() throws {
        let url = fontURL("NanumSquareNeo/NanumSquareNeo-Variable.ttf")
        let bytes = try Data(contentsOf: url)
        let fixedCandidate = VVD.Font(path: url.path)
        let fixed = try #require(fixedCandidate)
        fixed.setPointSize(23, dpi: (72, 72))
        let cases: [(VUI.Font, Float, [CGFloat])] = [
            (.file(url, size: 23), 0, [4.290052, 3.279317, 2.576023, 6.487472]),
            (.data(bytes, size: 23), 0, [4.290052, 3.279317, 2.576023, 6.487472]),
            (.file(url, size: 23, weight: .thin), -0.6, [4.009291, 3.144560, 2.392023, 6.326472]),
            (.data(bytes, size: 23, weight: .thin), -0.6, [4.009291, 3.144560, 2.392023, 6.326472]),
            (.init(vector: fixed), -0.6, [4.009291, 3.144560, 2.392023, 6.326472])
        ]
        for (font, weight, expected) in cases {
            for copy in [font, font.resolved(in: environment()).monospacedDigit()] {
                let source = try resolve(Text(verbatim: "Ågj").font(copy))
                let resource = try #require(attributes(source).first?.fontResource)
                #expect(resource.selectedWeight == nil)
                guard case let .styledText(faces, _, _, _) = source.runs.first else {
                    Issue.record("Expected a styled text run")
                    continue
                }
                #expect(faces.first?.outsetAttributes?.weight == CGFloat(weight))
                let text = GraphicsContext.ResolvedText(runs: source.runs, scaleFactor: source.scaleFactor,
                    preferredLanguages: ["en"])
                let edges = try #require(text.maximumFontMetrics).outsets
                let actual = [edges.leading, edges.top, edges.trailing, edges.bottom]
                for (value, target) in zip(actual, expected) { #expect(abs(value - target) < 1e-10) }
            }
        }
    }

    // ASSERTIONS fontSelectedWeightCopiesObserved
    // ASSERTIONS fontResolvedResourceEqualityObserved
    // ASSERTIONS fontResolvedLazyCacheBoundaryObserved
    @Test func selectedFontCopiesShareGlyphResourcesWithoutChangingFaceTraits() throws {
        let env = environment()
        let font = Font.custom("NanumSquareNeo-Variable", fixedSize: 23)
        let resource = font.platformFont(in: env.fontResolutionContext)
        let scene = SceneResources()
        let context = GraphTextResolutionContext(environment: env, sceneResources: scene)
        var firstFace: VectorTypeface?
        var firstShape: TypefaceShapedText?
        let resolved = font.resolved(in: env)
        for request in [font, resolved, resolved.resolved(in: env)] {
            let text = try #require(Text(verbatim: "Hg한글").font(request)._resolve(context: context,
                referenceDate: Date(timeIntervalSince1970: 0)))
            guard case let .styledText(faces, _, _, style) = text.runs.first else {
                Issue.record("Expected a styled text run")
                continue
            }
            let face = try #require(faces.first as? VectorTypeface)
            let shape = try #require(face.shape("Hg한글", direction: .leftToRight, language: nil, features: []))
            #expect(style.fontResource?.selectedWeight == 0)
            #expect(face.outsetAttributes?.weight == CGFloat(Float(-0.6)))
            if let firstFace, let firstShape {
                #expect(face === firstFace)
                #expect(shape.glyphs.map(\.index) == firstShape.glyphs.map(\.index))
                #expect(shape.glyphs.map(\.advance) == firstShape.glyphs.map(\.advance))
                #expect(shape.glyphs.map(\.offset) == firstShape.glyphs.map(\.offset))
            } else {
                firstFace = face
                firstShape = shape
            }
            _ = text.maximumFontMetrics
            #expect(face.outsetAttributes?.weight == CGFloat(Float(-0.6)))
        }
        #expect(resource === font.platformFont(in: env.fontResolutionContext))
        let copy = font.resolved(in: env).platformFont(in: env.fontResolutionContext)
        #expect(resource == copy)
        #expect(resource.hashValue == copy.hashValue)
        let changed = copy.descriptor().weight(.heavy)
        #expect(changed.selectedWeight == CGFloat(Float(0.4)))
        #expect(resource.selectedWeight == 0)
        #expect(resource.descriptor().resolvedWeight == 0)
    }

    private func metricFontData(units: UInt16, ascent: Int16, descent: Int16, gap: Int16,
                                clipping: (UInt16, UInt16)? = nil, removeOS2: Bool = false) throws -> Data {
        var data = try Data(contentsOf: fontURL("Roboto/Roboto-VariableFont_wdth,wght.ttf"))
        func read16(_ offset: Int) -> UInt16 { UInt16(data[offset]) << 8 | UInt16(data[offset + 1]) }
        func read32(_ offset: Int) -> Int {
            Int(data[offset]) << 24 | Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
        }
        func write16(_ offset: Int, _ value: UInt16) {
            data[offset] = UInt8(truncatingIfNeeded: value >> 8)
            data[offset + 1] = UInt8(truncatingIfNeeded: value)
        }
        var tables: [String: Int] = [:]
        for index in 0..<Int(read16(4)) {
            let record = 12 + index * 16
            tables[String(decoding: data[record..<record + 4], as: UTF8.self)] = read32(record + 8)
            if removeOS2, String(decoding: data[record..<record + 4], as: UTF8.self) == "OS/2" {
                data.replaceSubrange(record..<record + 4, with: "ZZZZ".utf8)
            }
        }
        let head = try #require(tables["head"])
        let hhea = try #require(tables["hhea"])
        let os2 = try #require(tables["OS/2"])
        write16(head + 18, units)
        write16(os2 + 62, read16(os2 + 62) & ~128)
        if let clipping {
            write16(os2 + 74, clipping.0)
            write16(os2 + 76, clipping.1)
        }
        for (index, value) in [ascent, descent, gap].enumerated() {
            write16(hhea + 4 + index * 2, UInt16(bitPattern: value))
        }
        return data
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
    // ASSERTIONS fontRawMetricFormatQuantizationObserved
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
        #expect(glyphs[0].face.designMetrics?.outlineFormat == .trueType)
        #expect(glyphs[1].face.designMetrics?.outlineFormat == .compactFontFormat)
        #expect(glyphs[0].lineBoxAscender == glyphs[1].lineBoxAscender)
        #expect(glyphs[0].lineBoxDescender == glyphs[1].lineBoxDescender)
        #expect(glyphs[0].lineBoxAscender == 12)
        #expect(glyphs[0].lineBoxDescender == -3)
        #expect(glyphs[0].ascender == 12.060546875)
        #expect(abs(glyphs[1].ascender - 15.08003056049347) < 1e-9)
        #expect(abs(glyphs[1].descender + 3.7440075874328613) < 1e-9)
    }

    // ASSERTIONS fontResolvedRetainedContextObserved
    // ASSERTIONS fontLeadingExtraDataOwnershipObserved
    // ASSERTIONS fontRawMetricFormatQuantizationObserved
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
            #expect(glyph.face.designMetrics?.outlineFormat == .trueType)
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
                #expect(glyph.face.designMetrics?.outlineFormat == .trueType)
            }
        }
    }

    // ASSERTIONS fontStyleFallbackMetricsObserved
    // ASSERTIONS fontSystemStylePolicyCopyObserved
    @Test
    func testLeadingUsesPrimaryLineMetricsWithoutChangingFallbackRunsOrGlyphResources() throws {
        var env = environment()
        env.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        let context = GraphTextResolutionContext(environment: env, sceneResources: SceneResources())
        func resolve(_ font: VUI.Font) throws -> GraphicsContext.ResolvedText {
            try #require(Text(verbatim: "A한").font(font)._resolve(context: context,
                referenceDate: Date(timeIntervalSince1970: 0)))
        }
        let ordinary = try resolve(.system(size: 13))
        let original = ordinary.makeGlyphs().flatMap(\.glyphs)
        try #require(original.count == 2)
        for leading: VUI.Font.Leading in [.standard, .tight, .loose] {
            let font = Font.body.leading(leading)
            for copy in [font, font.resolved(in: env)] {
                let source = try resolve(copy)
                let glyphs = source.makeGlyphs().flatMap(\.glyphs)
                try #require(glyphs.count == 2)
                for index in glyphs.indices {
                    #expect(glyphs[index].face.isEqual(to: original[index].face))
                    #expect(glyphs[index].glyphIndex == original[index].glyphIndex)
                    #expect(glyphs[index].advance == original[index].advance)
                    #expect(glyphs[index].ascender == original[index].ascender)
                    #expect(glyphs[index].descender == original[index].descender)
                }
                #expect(glyphs[1].leading == original[1].leading)
                #expect(glyphs[0].leading != original[0].leading)
                #expect(glyphs[0].fontLineMetrics == glyphs[1].fontLineMetrics)
                #expect(glyphs[0].style.fontResource?.stylePolicy?.leading == leading)
            }
        }
    }

    // ASSERTIONS fontRawMetricFormatQuantizationObserved
    // ASSERTIONS fontLeadingBaseHeightConsumerObserved
    // ASSERTIONS fontLeadingLineBoundsStorageObserved
    @Test
    func testNaturalFontMetricsReachRunBoundsAndSeparateHostLineBounds() throws {
        let cases: [(String, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            ("Roboto/Roboto-VariableFont_wdth,wght.ttf", 13, 12.060546875, 3.173828125, 12, 3),
            ("Roboto/Roboto-VariableFont_wdth,wght.ttf", 15.625, 14.495849609375, 3.814697265625, 14, 4),
            ("NanumSquareNeo/NanumSquareNeo-Variable.ttf", 13, 11.050079345703125, 3.3150634765625, 11, 3),
            ("NanumSquareNeo/NanumSquareNeo-Variable.ttf", 15.625, 13.28134536743164, 3.9844512939453125, 13, 4),
            ("NotoSansCJK/NotoSansCJK-VF.otf.ttc", 13, 15.08003056049347, 3.7440075874328613, 15, 4),
            ("NotoSansCJK/NotoSansCJK-VF.otf.ttc", 15.625, 18.125036731362343, 4.500009119510651, 18, 5)
        ]
        let proposal = CGSize(width: 300, height: 1000)
        for (name, pointSize, rawA, rawD, lineA, lineD) in cases {
            let url = fontURL(name)
            let data = try Data(contentsOf: url)
            for font in [VUI.Font.file(url, size: pointSize), .data(data, size: pointSize)] {
                for scale: CGFloat in [1, 1.5, 2] {
                    var environment = self.environment()
                    environment._contentScaleFactor = scale
                    environment.displayScale = 2
                    let resolved = try resolve(Text(verbatim: "Hg\nHg\nHg").font(font), environment: environment)
                    let layout = resolved.makeLayout(in: proposal, layoutDirection: .leftToRight)
                    try #require(layout.count == 3)
                    #expect(resolved.measure(in: proposal).height == (lineA + lineD) * 3)
                    #expect(TextProxy(resolved).sizeThatFits(.init(width: proposal.width)).height == (lineA + lineD) * 3)
                    let maximum = try #require(resolved.maximumFontMetrics)
                    #expect(abs(maximum.ascender - rawA) < 1e-9)
                    #expect(abs(maximum.descender + rawD) < 1e-9)
                    for (index, line) in layout.enumerated() {
                        #expect(line.typographicBounds.ascent == lineA)
                        #expect(line.typographicBounds.descent == lineD)
                        #expect(line.typographicBounds.leading == 0)
                        #expect(line.origin.y - layout[0].origin.y == CGFloat(index) * (lineA + lineD))
                        try #require(line.count == 1)
                        #expect(abs(line[0].typographicBounds.ascent - rawA) < 1e-9)
                        #expect(abs(line[0].typographicBounds.descent - rawD) < 1e-9)
                        #expect(line[0].typographicBounds.leading == 0)
                    }
                }
            }
        }
    }

    // ASSERTIONS fontRawMetricRoundingBoundaryObserved
    // ASSERTIONS fontLeadingNativeMetricConsumerObserved
    @Test
    func testQuantizedDescentSelectsTheHostHeightBeforeRenderScaling() throws {
        let data = try metricFontData(units: 1000, ascent: 712, descent: -288, gap: 200)
        let font = VUI.Font.data(data, size: 15.625)
        for scale: CGFloat in [1, 1.5, 2] {
            var environment = self.environment()
            environment._contentScaleFactor = scale
            environment.displayScale = 2
            let resolved = try resolve(Text(verbatim: "Hg\nHg\nHg").font(font), environment: environment)
            let layout = resolved.makeLayout(in: .init(width: 300, height: 1000), layoutDirection: .leftToRight)
            try #require(layout.count == 3)
            #expect(resolved.measure().height == 45)
            for line in layout {
                #expect(line.typographicBounds.ascent == 11)
                #expect(line.typographicBounds.descent == 4)
                #expect(line.typographicBounds.leading == 0)
                #expect(abs(line[0].typographicBounds.descent - 4.499912261962891) < 1e-9)
                #expect(abs(line[0].typographicBounds.leading - 3.1249523162841797) < 1e-9)
            }
            #expect(resolved.makeGlyphs(maxHeight: Int(30 * scale)).count == 2)
            #expect(resolved.makeGlyphs(maxHeight: Int(30 * scale) - 1).count == 1)
            let long = try resolve(Text(verbatim: "ABCDE FGHIJ KLMNO").font(font), environment: environment)
            for mode: Text.TruncationMode in [.head, .middle, .tail] {
                let lines = long.makeGlyphs(maxWidth: Int(40 * scale), lineLimit: 1, truncationMode: mode)
                let tokenCandidate = lines.first?.glyphs.first(where: \.isTruncationToken)
                let token = try #require(tokenCandidate)
                #expect(abs(token.leading / scale - 3.1249523162841797) < 1e-9)
                #expect(abs(token.descender / scale + 4.499912261962891) < 1e-9)
            }
        }
    }

    // ASSERTIONS fontRawMetricSignedConsumerObserved
    // ASSERTIONS fontLeadingSignedMetricsAndMultilineObserved
    @Test
    func testNegativeNaturalLeadingSurvivesRunBoundsWithoutExpandingHostLines() throws {
        for (units, ascent, descent, leading, height): (UInt16, Int16, Int16, CGFloat, CGFloat) in [
            (2048, 1900, -500, -0.634765625, 15),
            (1000, 712, -288, -1.300079345703125, 13)
        ] {
            let data = try metricFontData(units: units, ascent: ascent, descent: descent, gap: -100)
            for scale: CGFloat in [1, 2] {
                var environment = self.environment()
                environment._contentScaleFactor = scale
                let text = Text(verbatim: "Hg\nHg\nHg").font(.data(data, size: 13))
                let resolved = try resolve(text, environment: environment)
                let layout = resolved.makeLayout(in: .init(width: 300, height: 1000), layoutDirection: .leftToRight)
                try #require(layout.count == 3)
                #expect(resolved.measure().height == height * 3)
                #expect(abs(try #require(resolved.maximumFontMetrics).leading - leading) < 1e-9)
                for line in layout {
                    #expect(line.typographicBounds.leading == 0)
                    #expect(abs(line[0].typographicBounds.leading - leading) < 1e-9)
                }
            }
        }
    }

    // ASSERTIONS fontLeadingMixedRunAggregationObserved
    // ASSERTIONS fontLeadingLineBoundsStorageObserved
    @Test
    func testOrdinaryMixedMetricsPreserveUnshiftedExtentsAndRawRunValues() throws {
        let first = VUI.Font.file(fontURL("Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 13)
        let second = VUI.Font.file(fontURL("NanumSquareNeo/NanumSquareNeo-Variable.ttf"), size: 13)
        for (offset, ascent, descent): (CGFloat, CGFloat, CGFloat) in [(0, 12, 3), (4, 15, 3), (-4, 12, 7)] {
            let text = concatenating(Text(verbatim: "Hg").font(first), Text(verbatim: "Xg").font(second).baselineOffset(offset))
            let resolved = try resolve(text)
            let layout = resolved.makeLayout(in: .init(width: 300, height: 1000), layoutDirection: .leftToRight)
            let line = try #require(layout.first)
            #expect(resolved.measure().height == ascent + descent)
            #expect(line.typographicBounds.ascent == ascent)
            #expect(line.typographicBounds.descent == descent)
            try #require(line.count == 2)
            #expect(line[0].typographicBounds.ascent == 12.060546875)
            #expect(abs(line[1].typographicBounds.ascent - 11.050079345703125) < 1e-9)
            #expect(line[1].typographicBounds.origin.y == line.origin.y - offset)
        }
    }

    // ASSERTIONS fontMinimumLineHeightObserved
    @Test
    func testSmallFontHeightRemainsPositiveBeforeBaselineOffsetAndScale() throws {
        let data = try metricFontData(units: 1000, ascent: 712, descent: -288, gap: 200)
        for scale: CGFloat in [1, 1.5, 2] {
            for offset: CGFloat in [0, 4] {
                var environment = self.environment()
                environment._contentScaleFactor = scale
                environment.displayScale = 2
                let text = Text(verbatim: "Hg\nHg\nHg").font(.data(data, size: 0.1)).baselineOffset(offset)
                let resolved = try resolve(text, environment: environment)
                let layout = resolved.makeLayout(in: .init(width: 300, height: 1000), layoutDirection: .leftToRight)
                try #require(layout.count == 3)
                #expect(resolved.measure().height == (offset == 0 ? 0.5 : 12.5))
                for line in layout {
                    #expect(line.typographicBounds.ascent == offset)
                    #expect(abs(line.typographicBounds.descent - 0.0001) < 1e-12)
                    #expect(abs(line[0].typographicBounds.ascent - 0.0712005615234375) < 1e-12)
                }
            }
        }
    }

    // ASSERTIONS fontLeadingLineBoundsStorageObserved
    // ASSERTIONS fontRawMetricFormatQuantizationObserved
    @Test
    func testResolvedMetricsDrivePreparedGeometryAndTruncation() throws {
        var string = AttributedString("H\nH\nH")
        string._setCoreAttributes(_ResolvedTextRunAttributes(backgroundColor: .yellow, underlineStyle: .init()))
        for scale: CGFloat in [1, 2] {
            var environment = self.environment()
            environment.font = .system(size: 13)
            environment._contentScaleFactor = scale
            environment.displayScale = 2
            let resolved = try resolve(Text(string), environment: environment)
            let size = CGSize(width: 300, height: 1000)
            let drawing = resolved.makeDrawing(in: size)
            let atoms = resolved.glyphAtoms(in: size)
            let lines = resolved.makeGlyphs()
            try #require(lines.count == 3 && drawing.backgrounds.count == 3 && atoms.count == 3)
            #expect(resolved.measure(in: size).height == 45)
            for index in 0..<3 {
                let baseline = CGFloat(12 + 15 * index)
                #expect(lines[index].baseline == baseline * scale)
                #expect(abs(drawing.backgrounds[index].frame.minY / scale - (baseline - 12.060546875)) < 1e-9)
                #expect(abs(drawing.backgrounds[index].frame.height / scale - 15.234375) < 1e-9)
                #expect(atoms[index].bounds.height == 15)
                #expect(atoms[index].bounds.minY == CGFloat(index * 15))
            }
            for mode: Text.TruncationMode in [.head, .middle, .tail] {
                let long = try resolve(Text(verbatim: "ABCDE FGHIJ KLMNO"), environment: environment)
                let truncated = long.makeGlyphs(maxWidth: Int(40 * scale), lineLimit: 1, truncationMode: mode)
                let line = try #require(truncated.first)
                let tokenCandidate = line.glyphs.first(where: \.isTruncationToken)
                let token = try #require(tokenCandidate)
                #expect(line.height == 15 * scale)
                #expect(token.ascender == 12.060546875 * scale)
                #expect(token.descender == -3.173828125 * scale)
                #expect(token.leading == 0)
            }
        }
    }

    @Test
    func testSuppliedTypefaceKeepsItsMetricsWithoutAnIndependentPointSize() throws {
        let candidate = VVD.Font(path: fontURL("Roboto/Roboto-VariableFont_wdth,wght.ttf").path)
        let font = try #require(candidate)
        font.setPointSize(13, dpi: (72, 72))
        let text = Text(verbatim: "Hg").font(VUI.Font(vector: font))
        let resolved = try resolve(text)
        let layout = resolved.makeLayout(in: .init(width: 300, height: 1000), layoutDirection: .leftToRight)
        #expect(resolved.measure().height == 17)
        #expect(layout[0][0].typographicBounds.ascent == 13)
        #expect(layout[0][0].typographicBounds.descent == 4)
    }

    // ASSERTIONS textDrawingMarginClippingOutsetsObserved
    // ASSERTIONS textDrawingFrameCompensationObserved
    @Test
    func testClippingMarginsExpandDrawingFramesWithoutChangingTypographicMetrics() throws {
        let names = ["Roboto/Roboto-VariableFont_wdth,wght.ttf",
                     "NanumSquareNeo/NanumSquareNeo-Variable.ttf",
                     "NotoSansCJK/NotoSansCJK-VF.otf.ttc"]
        for (fontIndex, name) in names.enumerated() {
            for pointSize: CGFloat in [13, 15.625, 23] {
                for displayScale: CGFloat in [1, 2] {
                    for renderScale: CGFloat in [1, 2] {
                        var environment = self.environment()
                        environment.displayScale = displayScale
                        environment._contentScaleFactor = renderScale
                        let source = try resolve(Text(verbatim: "Hg\nHg").font(.file(fontURL(name), size: pointSize)),
                                                 environment: environment)
                        let metrics = try #require(source.maximumFontMetrics)
                        let styled = ResolvedStyledText(resolvedText: source)
                        let measured = source.measure()
                        let baseline = source.firstBaseline(in: measured)
                        let rawTop = fontIndex == 0 ? 46 * pointSize / 2048 : 0
                        let rawBottom = fontIndex == 0 ? 12 * pointSize / 2048 : 0
                        #expect(abs(metrics.outsets.top - rawTop) < 1e-12)
                        #expect(abs(metrics.outsets.bottom - rawBottom) < 1e-12)
                        let top: CGFloat = fontIndex != 0 ? 0 : (displayScale == 1 || pointSize == 23 ? 1 : 0.5)
                        let bottom: CGFloat = fontIndex != 0 ? 0 : 1 / displayScale
                        #expect(styled.drawingMargins == EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
                        let frame = styled.frame(in: measured, renderer: nil)
                        #expect(frame == CGRect(x: 0, y: -top, width: measured.width, height: measured.height + top + bottom))
                        let layout = source.makeLayout(in: measured, layoutDirection: .leftToRight,
                                                       origin: CGPoint(x: 0, y: top))
                        #expect(layout[0].origin.y == baseline + top)
                        #expect(layout[0].origin.y + frame.minY == baseline)
                        #expect(styled.sizeThatFits(_ProposedSize(measured)) == measured)
                        #expect(styled.firstBaseline(in: measured) == baseline)
                        #expect(layout[0][0].typographicBounds.ascent == metrics.ascender)
                    }
                }
            }
        }
    }

    // ASSERTIONS textDrawingMarginClippingOutsetsObserved
    // ASSERTIONS fontClippingVariationMetricsObserved
    @Test
    func testAbsentZeroAndQuantizedClippingInputsRemainDistinct() throws {
        for remove in [false, true] {
            let data = try metricFontData(units: 2048, ascent: 1900, descent: -500, gap: 0,
                                          clipping: (0, 0), removeOS2: remove)
            let source = try resolve(Text(verbatim: "Hg").font(.data(data, size: 13)))
            let metrics = try #require(source.maximumFontMetrics)
            #expect(metrics.ascender == 12.060546875)
            #expect(metrics.descender == -3.173828125)
            #expect(metrics.outsets == EdgeInsets())
            #expect(ResolvedStyledText(resolvedText: source).drawingMargins == EdgeInsets())
        }
        // A half-design-unit difference can cross a half-point ceiling. Retain
        // the integer snapshot's actual result instead of hiding that boundary.
        let data = try metricFontData(units: 2048, ascent: 1800, descent: -400, gap: -100,
                                      clipping: (2151, 675))
        var environment = self.environment()
        environment.displayScale = 2
        let size: CGFloat = 1024 / 350.5
        let source = try resolve(Text(verbatim: "Hg").font(.data(data, size: size)), environment: environment)
        let metrics = try #require(source.maximumFontMetrics)
        #expect(metrics.outsets.top > 0.5 && metrics.outsets.top < 0.501)
        #expect(ResolvedStyledText(resolvedText: source).drawingMargins.top == 1)
        #expect(350.5 * size / 2048 == 0.5)
    }

    // ASSERTIONS textDrawingFrameCompensationObserved
    @Test
    func testDrawingOriginPreservesSelectionBackgroundAndDecorationPlacement() throws {
        var string = AttributedString("Hg\nHg")
        string._setCoreAttributes(_ResolvedTextRunAttributes(backgroundColor: .yellow, strikethroughStyle: .init(),
                                                             underlineStyle: .init()))
        for scale: CGFloat in [1, 2] {
            var environment = self.environment()
            environment.font = .system(size: 13)
            environment.displayScale = 2
            environment._contentScaleFactor = scale
            let source = try resolve(Text(string), environment: environment)
            let styled = ResolvedStyledText(stylePadding: EdgeInsets(top: 0.3, leading: 1.2, bottom: 0.6, trailing: 0.2),
                                             resolvedText: source)
            #expect(styled.drawingMargins == EdgeInsets(top: 1, leading: 1.5, bottom: 1, trailing: 0.5))
            let size = source.measure()
            let frame = styled.frame(in: size, renderer: nil)
            let value = DisplayList.Content.TextValue(
                view: StyledTextContentView(text: styled, renderer: nil), size: size, frame: frame,
                shading: .color(.black), transform: .identity, command: .closure(bounds: nil))
            let drawing = try #require(value.makeDrawing())
            #expect(drawing.origin == CGPoint(x: 1.5, y: 1))
            #expect(frame.origin + drawing.origin == .zero)
            let atoms = try #require(value.glyphAtoms())
            #expect(atoms.map(\.bounds) == source.glyphAtoms(in: size).map(\.bounds))
            let original = source.makeDrawing(in: size)
            #expect(drawing.backgrounds.map(\.frame) == original.backgrounds.map(\.frame))
            #expect(drawing.decorations.map(\.start) == original.decorations.map(\.start))
            #expect(drawing.vectorBatches.map { $0.path.boundingRect } == original.vectorBatches.map { $0.path.boundingRect })
            #expect(drawing.backgrounds.count == 2 && drawing.decorations.count == 4)
        }
    }

    // ASSERTIONS textLineSpacingPlacementObserved
    // ASSERTIONS textLineSpacingMeasurementAndLimitObserved
    @Test
    func testLineSpacingMovesLayoutBaselinesAndMeasurementTogether() throws {
        let proposal = CGSize(width: 90, height: 1000)
        let scales: [(CGFloat, CGFloat)] = [(1, 1), (1, 2), (2, 1), (2, 2)]
        for (scale, displayScale) in scales {
            var environment = self.environment()
            environment.font = .system(size: 13)
            environment._contentScaleFactor = scale
            environment.displayScale = displayScale
            for string in ["Hg", "Hg\nHg", "Hg\nHg\nHg", "Hg Hg Hg Hg Hg Hg Hg Hg Hg Hg Hg Hg"] {
                environment.lineSpacing = 0
                let original = try resolve(Text(verbatim: string), environment: environment)
                let originalLayout = original.makeLayout(in: proposal, layoutDirection: .leftToRight)
                let originalSize = original.measure(in: proposal)
                try #require(!originalLayout.isEmpty)
                for spacing: CGFloat in [-7, 2.5, 7] {
                    environment.lineSpacing = spacing
                    let resolved = try resolve(Text(verbatim: string), environment: environment)
                    let layout = resolved.makeLayout(in: proposal, layoutDirection: .leftToRight)
                    let gap = max(spacing, 0)
                    try #require(layout.count == originalLayout.count)
                    let expectedHeight = ceil((originalSize.height + CGFloat(layout.count - 1) * gap) * displayScale) / displayScale
                    #expect(resolved.measure(in: proposal).height == expectedHeight)
                    #expect(resolved.measure(maxWidth: proposal.width) == resolved.measure(in: proposal))
                    #expect(TextProxy(resolved).sizeThatFits(.init(width: proposal.width)) == resolved.measure(in: proposal))
                    for index in layout.indices {
                        #expect(layout[index].origin.y == originalLayout[index].origin.y + CGFloat(index) * gap)
                        #expect(layout[index].typographicBounds.ascent == originalLayout[index].typographicBounds.ascent)
                        #expect(layout[index].typographicBounds.descent == originalLayout[index].typographicBounds.descent)
                        #expect(layout[index].typographicBounds.leading == 0)
                        for (run, baseRun) in zip(layout[index], originalLayout[index]) {
                            #expect(run.typographicBounds.ascent == baseRun.typographicBounds.ascent)
                            #expect(run.typographicBounds.descent == baseRun.typographicBounds.descent)
                            #expect(run.typographicBounds.leading == baseRun.typographicBounds.leading)
                        }
                    }
                    #expect(resolved.firstBaseline(in: proposal) == layout.first?.origin.y)
                    #expect(resolved.lastBaseline(in: proposal) == layout.last?.origin.y)
                }
            }
        }
    }

    // ASSERTIONS textEmptyParagraphSpacingBoundsObserved
    // ASSERTIONS textLineSpacingMeasurementAndLimitObserved
    @Test
    func testEmptyParagraphSpacingAndTrailingLineAreRetained() throws {
        let proposal = CGSize(width: 90, height: 1000)
        for string in ["\n", "\n\n"] {
            var environment = self.environment()
            let base = try resolve(Text(verbatim: string), environment: environment)
            environment.lineSpacing = 7
            let spaced = try resolve(Text(verbatim: string), environment: environment)
            #expect(spaced.measure(in: proposal) == base.measure(in: proposal))
            #expect(spaced.lastBaseline(in: proposal) == base.lastBaseline(in: proposal))
        }
        let cases: [(String, Int, Set<Int>)] = [("Hg\n", 2, []),
            ("Hg\n\nHg", 3, [1]), ("\nHg\nHg", 3, []), ("Hg\n\n\nHg", 4, [1, 2])]
        for scale: CGFloat in [1, 2] {
            var environment = self.environment()
            environment.font = .system(size: 13)
            environment._contentScaleFactor = scale
            environment.displayScale = scale
            for (string, count, expandedDescents) in cases {
                environment.lineSpacing = 0
                let original = try resolve(Text(verbatim: string), environment: environment)
                let base = original.makeLayout(in: proposal, layoutDirection: .leftToRight)
                try #require(base.count == count)
                for spacing: CGFloat in [2.5, 7] {
                    environment.lineSpacing = spacing
                    let resolved = try resolve(Text(verbatim: string), environment: environment)
                    let layout = resolved.makeLayout(in: proposal, layoutDirection: .leftToRight)
                    try #require(layout.count == count)
                    let expectedHeight = ceil((original.measure(in: proposal).height + CGFloat(count - 1) * spacing) * scale) / scale
                    #expect(resolved.measure(in: proposal).height == expectedHeight)
                    for index in layout.indices {
                        let hasIncomingEmptyGap = expandedDescents.contains(index)
                        let shift = CGFloat(index - (hasIncomingEmptyGap ? 1 : 0)) * spacing
                        #expect(layout[index].origin.y == base[index].origin.y + shift)
                        #expect(layout[index].typographicBounds.ascent == base[index].typographicBounds.ascent)
                        #expect(layout[index].typographicBounds.descent == base[index].typographicBounds.descent + (hasIncomingEmptyGap ? spacing : 0))
                    }
                    #expect(resolved.lastBaseline(in: proposal) == layout.last?.origin.y)
                }
            }
        }
    }

    // ASSERTIONS textLineSpacingMeasurementAndLimitObserved
    @Test
    func testLineSpacingParticipatesInHeightLimitsAndTruncation() throws {
        var environment = self.environment()
        environment.font = .system(size: 13)
        environment.lineSpacing = 7
        environment._contentScaleFactor = 1
        let resolved = try resolve(Text(verbatim: "Hg\nHg\nHg"), environment: environment)
        let line = try #require(resolved.makeGlyphs().first)
        let twoLineHeight = line.height * 2 + 7
        #expect(resolved.makeGlyphs(maxHeight: Int(twoLineHeight)).count == 2)
        #expect(resolved.makeGlyphs(maxHeight: Int(twoLineHeight - 1)).count == 1)
        #expect(resolved.measure(maxHeight: twoLineHeight).height == twoLineHeight)
        for mode: Text.TruncationMode in [.head, .middle, .tail] {
            var properties = TextLayoutProperties(from: environment)
            properties.lineLimit = 2
            properties.truncationMode = mode
            let size = CGSize(width: 90, height: 1000)
            let metrics = resolved.layoutMetrics(in: size, layoutProperties: properties)
            let layout = resolved.makeLayout(in: size, layoutDirection: .leftToRight, layoutProperties: properties)
            #expect(metrics.size.height == twoLineHeight)
            #expect(layout.count == 2)
            #expect(metrics.lastBaseline == layout.last?.origin.y)
        }
        let empty = try resolve(Text(verbatim: "Hg\n\nHg"), environment: environment)
        let lines = empty.makeGlyphs(lineLimit: 2)
        try #require(lines.count == 2)
        #expect(lines[1].glyphs.isEmpty)
        #expect(lines[1].height == line.height + 7)
    }

    // ASSERTIONS textLineSpacingPlacementObserved
    // ASSERTIONS fontLeadingLineBoundsStorageObserved
    @Test
    func testLineSpacingDrivesPreparedDrawingAndGlyphAtoms() throws {
        var string = AttributedString("A\nB\nC")
        string._setCoreAttributes(_ResolvedTextRunAttributes(backgroundColor: .yellow, underlineStyle: .init()))
        for (letter, color) in [("A", VUI.Color.red), ("B", .green), ("C", .blue)] {
            if let range = string.range(of: letter) { string[range].foregroundColor = color }
        }
        let text = Text(string)
        let size = CGSize(width: 200, height: 1000)
        for scale: CGFloat in [1, 2] {
            var environment = self.environment()
            environment._contentScaleFactor = scale
            environment.displayScale = scale
            let original = try resolve(text, environment: environment)
            let baseDrawing = original.makeDrawing(in: size)
            let baseAtoms = original.glyphAtoms(in: size)
            environment.lineSpacing = 7
            let resolved = try resolve(text, environment: environment)
            let drawing = resolved.makeDrawing(in: size)
            let atoms = resolved.glyphAtoms(in: size)
            try #require(baseDrawing.vectorBatches.count == 3 && drawing.vectorBatches.count == 3)
            try #require(baseDrawing.decorations.count == 3 && drawing.decorations.count == 3)
            try #require(baseDrawing.backgrounds.count == 3 && drawing.backgrounds.count == 3)
            try #require(baseAtoms.count == 3 && atoms.count == 3)
            for index in 0..<3 {
                let delta = CGFloat(index) * 7
                #expect(drawing.vectorBatches[index].path.boundingRect.minY == baseDrawing.vectorBatches[index].path.boundingRect.minY + delta * scale)
                #expect(drawing.decorations[index].start.y == baseDrawing.decorations[index].start.y + delta * scale)
                #expect(drawing.backgrounds[index].frame.minY == baseDrawing.backgrounds[index].frame.minY + delta * scale)
                #expect(atoms[index].bounds.minY == baseAtoms[index].bounds.minY + delta)
                #expect(atoms[index].bounds.height == baseAtoms[index].bounds.height)
            }
        }
    }

    // ASSERTIONS textLineSpacingPlacementObserved
    @Test
    func testMixedFontAndBaselineOffsetKeepLineSpacingIndependent() throws {
        let text = concatenating(Text(verbatim: "Hg\n").font(.system(size: 13)),
            concatenating(Text(verbatim: "Xg\n").font(.system(size: 23)).baselineOffset(4),
                Text(verbatim: "Hg").font(.system(size: 13))))
        let size = CGSize(width: 90, height: 1000)
        var environment = self.environment()
        let original = try resolve(text, environment: environment)
        let base = original.makeLayout(in: size, layoutDirection: .leftToRight)
        environment.lineSpacing = 7
        let resolved = try resolve(text, environment: environment)
        let layout = resolved.makeLayout(in: size, layoutDirection: .leftToRight)
        try #require(base.count == 3 && layout.count == 3)
        #expect(resolved.measure(in: size).height == original.measure(in: size).height + 14)
        for index in layout.indices {
            #expect(layout[index].origin.y == base[index].origin.y + CGFloat(index) * 7)
            #expect(layout[index].typographicBounds.ascent == base[index].typographicBounds.ascent)
            #expect(layout[index].typographicBounds.descent == base[index].typographicBounds.descent)
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

    // ASSERTIONS textComponentFontLanguageAndRatioObserved
    @Test
    func testLanguageModifierPreservesExistingDescriptorLanguage() {
        let context = environment().fontResolutionContext
        for initial: String? in [nil, "en-Latn-US", ""] {
            var descriptor = FontDescriptor(source: .system(.default, .regular, false), pointSize: 23,
                language: initial, languageAwareLineHeightRatio: 0.5)
            for request in ["ur-Aran-PK", "ja-Jpan-JP"] {
                let previous = descriptor
                LanguageFontModifier(identifier: request).modify(descriptor: &descriptor, in: context)
                #expect(descriptor.language == (initial ?? "ur-Aran-PK"))
                #expect(descriptor.languageAwareLineHeightRatio == 0.5)
                if previous.language != nil { #expect(descriptor === previous) }
            }
            LanguageAwareLineHeightRatioFontModifier(ratio: 0).modify(descriptor: &descriptor, in: context)
            #expect(descriptor.language == (initial ?? "ur-Aran-PK"))
            #expect(descriptor.languageAwareLineHeightRatio == 0)
        }
    }

    // ASSERTIONS textComponentFontLanguageAndRatioObserved
    @Test
    func testCachedFontRequestsPreserveTheFirstLanguageAndReplaceTheRatio() throws {
        let context = environment().fontResolutionContext
        let base = Font.system(size: 23)
        let first = base.platformFont(in: context, modifiers: [
            .dynamic(LanguageFontModifier(identifier: "en-Latn-US")),
            .dynamic(LanguageFontModifier(identifier: "ur-Aran-PK")),
            .dynamic(LanguageAwareLineHeightRatioFontModifier(ratio: 0.33)),
            .dynamic(LanguageAwareLineHeightRatioFontModifier(ratio: 0.5))])
        #expect(first.language == "en-Latn-US")
        #expect(first.languageAwareLineHeightRatio == 0.5)
        let resolved = Font(provider: FontBox(Font.PlatformFontProvider(font: first)))
        let second = resolved.platformFont(in: context, modifiers: [
            .dynamic(LanguageFontModifier(identifier: "ja-Jpan-JP")),
            .dynamic(LanguageAwareLineHeightRatioFontModifier(ratio: 0))])
        #expect(second.language == "en-Latn-US")
        #expect(second.languageAwareLineHeightRatio == 0)
        #expect(first.languageAwareLineHeightRatio == 0.5)
        #expect(second !== first)
    }

    // ASSERTIONS textComponentFontLanguageAndRatioObserved
    @Test
    func testResourceFontsDoNotAcquireComponentMetricsFromTypesettingRequests() throws {
        let url = fontURL("Roboto/Roboto-VariableFont_wdth,wght.ttf")
        for font in [Font.file(url, size: 23), .data(try Data(contentsOf: url), size: 23),
                     .custom("Roboto-Regular", fixedSize: 23), .system(size: 23)] {
            var env = environment()
            env.font = font
            let text = Text(verbatim: "Ågj\nÅgj")
            let baseline = try resolve(text, environment: env)
            let metrics = try #require(baseline.maximumFontMetrics)
            let size = baseline.measure()
            let styled = ResolvedStyledText(resolvedText: baseline)
            for language: String? in [nil, "en", "ur", "ja"] {
                for (ratio, retained): (TypesettingLanguageAwareLineHeightRatio, Double?) in [
                    (.automatic, nil), (.disable, 0), (.legacy, 0.33), (.custom(0.5), 0.5), (.custom(1), 1)
                ] {
                    env.typesettingConfiguration.language = language.map { .explicit(Locale.Language(identifier: $0)) } ?? .automatic
                    env.typesettingConfiguration.languageAwareLineHeightRatio = ratio
                    let result = try resolve(text, environment: env)
                    let actual = try #require(result.maximumFontMetrics)
                    #expect(actual.ascender == metrics.ascender)
                    #expect(actual.descender == metrics.descender)
                    #expect(actual.leading == metrics.leading)
                    #expect(actual.outsets == metrics.outsets)
                    #expect(result.measure() == size)
                    #expect(result.firstBaseline(in: size) == baseline.firstBaseline(in: size))
                    let actualStyled = ResolvedStyledText(resolvedText: result)
                    #expect(actualStyled.drawingMargins == styled.drawingMargins)
                    #expect(actualStyled.frame(in: size, renderer: nil) == styled.frame(in: size, renderer: nil))
                    for run in attributes(result) {
                        #expect(run.fontResource?.language == language.map { Locale.Language(identifier: $0).maximalIdentifier })
                        #expect(run.fontResource?.languageAwareLineHeightRatio == retained)
                    }
                }
            }
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
