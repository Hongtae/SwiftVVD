import Foundation
import XCTest
import VVD
@testable import VUI

final class TextStyleConsumerTests: XCTestCase {
    private var previousApp: AppContext?
    override func setUpWithError() throws {
        previousApp = appContext
        let device = try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        appContext = StyleTestAppContext(graphicsDeviceContext: device)
    }
    override func tearDown() { appContext = previousApp }

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
        return try XCTUnwrap(text._resolve(context: GraphTextResolutionContext(
            environment: environment ?? self.environment(), sceneResources: SceneResources()), referenceDate: Date(timeIntervalSince1970: 0)))
    }
    private func attributes(_ resolved: GraphicsContext.ResolvedText) -> [_ResolvedTextRunAttributes] {
        resolved.runs.compactMap { if case let .styledText(_, _, _, attributes) = $0 { attributes } else { nil } }
    }

    // ASSERTIONS textStyleInitializationAndNestedOwnersObserved
    // ASSERTIONS textFontModifierTraversalOrderObserved
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
            XCTAssertEqual(attributes(resolved).first?.fontResource?.pointSize, size)
            XCTAssertGreaterThan(resolved.measure().width, 0)
        }
        XCTAssertNil(Text.Style().baseFont.resolve(in: environment, includeDefaultAttributes: false))
        var defaults = environment
        defaults.defaultFont = .system(size: 19)
        XCTAssertEqual(try XCTUnwrap(style(Text(verbatim: "A").font(nil)).fontKey(in: defaults)).font, .system(size: 19))
        let ordered = style(Text(verbatim: "A").fontWeight(.heavy).fontWeight(.light))
        XCTAssertEqual(ordered.fontModifiers, [.dynamic(Font.WeightModifier(weight: .light)), .dynamic(Font.WeightModifier(weight: .heavy))])
    }

    // ASSERTIONS textFontInheritedModifierClearingObserved
    // ASSERTIONS textStyleFontTraitsDispatchObserved
    // ASSERTIONS textStyleFontAttributeCacheInputsObserved
    func testFontCacheClearsInheritedTypesWhileTraitsKeepThem() throws {
        var environment = environment()
        environment.fontModifiers = [.dynamic(Font.WeightModifier(weight: .heavy)), .static(Font.ItalicModifier.self)]
        let cleared = style(Text(verbatim: "A").fontWeight(nil))
        let key = try XCTUnwrap(cleared.fontKey(in: environment))
        XCTAssertTrue(key.context.fontModifiers.isEmpty)
        XCTAssertEqual(key.modifiers, [.static(Font.ItalicModifier.self)])
        XCTAssertEqual(cleared.fontTraits(in: environment).weight, CGFloat(Float(Font.Weight.heavy.value)))
        var readded = cleared
        readded.addFontModifier(.dynamic(Font.WeightModifier(weight: .light)))
        XCTAssertTrue(readded.clearedFontModifiers.contains(ObjectIdentifier(Font.WeightModifier.self)))
        XCTAssertEqual(try XCTUnwrap(readded.fontKey(in: environment)).modifiers, [.static(Font.ItalicModifier.self), .dynamic(Font.WeightModifier(weight: .light))])
        let provider = style(Text(verbatim: "A").font(.system(size: 31).weight(.heavy)).fontWeight(nil))
        XCTAssertEqual((Font.FontCache.shared[try XCTUnwrap(provider.fontKey(in: environment))].provider as? SystemFontProvider)?.weight, .heavy)
    }

    // ASSERTIONS textFontNestedStyleIsolationObserved
    // ASSERTIONS textParagraphNestedRunCacheObserved
    func testNestedTextCopiesStyleAndSharesParagraphUntilUTF16Boundary() throws {
        let first = Text(verbatim: "😀e\u{301}\n").font(nil).fontWeight(nil)
        let second = Text(verbatim: "B")
        let text = Text(storage: .anyTextStorage(ConcatenatedTextStorage(first: first, second: second)), modifiers: [])
            .font(.system(size: 41)).fontWeight(.heavy)
        let result = try resolve(text)
        let runs = attributes(result)
        XCTAssertEqual(runs.map { $0.fontResource?.pointSize }, [13, 41])
        XCTAssertEqual(runs.map { ($0.fontResource?.provider as? SystemFontProvider)?.weight }, [VUI.Font.Weight.regular, VUI.Font.Weight.heavy])
        XCTAssertFalse(runs[0].paragraphStyle === runs[1].paragraphStyle)
        XCTAssertEqual(result.resolvedProperties?.paragraph.startIndex, 6)
        XCTAssertNil(result.resolvedProperties?.paragraph.cachedStyle)
        let adjacent = try resolve(Text(storage: .anyTextStorage(ConcatenatedTextStorage(
            first: Text(verbatim: "A").font(.system(size: 31)), second: second)), modifiers: []).font(.system(size: 41)))
        let adjacentRuns = attributes(adjacent)
        XCTAssertTrue(adjacentRuns[0].paragraphStyle === adjacentRuns[1].paragraphStyle)
        XCTAssertEqual(adjacentRuns.map { $0.fontResource?.pointSize }, [31, 41])
    }

    // ASSERTIONS textAttributedStyleFontMergeObserved
    // ASSERTIONS textAttributedStyleIntentDispatchObserved
    // ASSERTIONS textAttributedStyleDictionaryTransferObserved
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
        XCTAssertEqual(dictionary.count, 1)
        XCTAssertEqual(dictionary[.init("NSLanguage")] as? String, "ja")
        let key = try XCTUnwrap(parent.fontKey(in: inherited))
        XCTAssertEqual(key.modifiers, [.static(Font.ItalicModifier.self), .static(Font.BoldModifier.self), .static(Font.MonospacedModifier.self)])
        var properties = Text.ResolvedProperties()
        let attributes = parent.nsAttributes(in: inherited, properties: &properties)
        XCTAssertEqual(attributes.fontResource?.pointSize, 31)
        XCTAssertEqual(attributes.kern, 3)
        XCTAssertEqual(attributes.tracking, 11)
        XCTAssertEqual(attributes.language, "ja-Jpan-JP")
        XCTAssertEqual(properties.paragraph.compositionLanguage, 2)
    }

    // ASSERTIONS textAttributedStyleRunIsolationObserved
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
        XCTAssertEqual(runs.map { $0.fontResource?.pointSize }, [31, 41, 41])
        XCTAssertEqual(runs.map(\.kern), [3, nil, nil])
        XCTAssertEqual(runs.map(\.tracking), [11, 5, 11])
        XCTAssertEqual((runs[1].fontResource?.provider as? SystemFontProvider)?.weight, .bold)
        XCTAssertEqual((runs[2].fontResource?.provider as? SystemFontProvider)?.weight, .regular)
        XCTAssertTrue(runs.allSatisfy { $0.paragraphStyle === runs[0].paragraphStyle })
        XCTAssertEqual(resolved.attributedStorage.length, 6)
        XCTAssertGreaterThan(resolved.makeGlyphs().first?.width ?? 0, 0)
    }

    // ASSERTIONS textTypesettingAttributeProducerObserved
    // ASSERTIONS textTypesettingRatioFontInputsObserved
    // ASSERTIONS fontModifierTagsAndCodingObserved
    func testLanguageAndRatioFollowFontModifiersAndSurviveDescriptorCopies() throws {
        var style = Text.Style()
        style.fontModifiers = [.dynamic(Font.WeightModifier(weight: .heavy))]
        style.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "ja"))
        style.typesettingConfiguration.languageAwareLineHeightRatio = .custom(0.5)
        let key = try XCTUnwrap(style.fontKey(in: environment()))
        XCTAssertEqual(key.modifiers, [.dynamic(Font.WeightModifier(weight: .heavy)),
            .dynamic(LanguageFontModifier(identifier: "ja-Jpan-JP")),
            .dynamic(LanguageAwareLineHeightRatioFontModifier(ratio: 0.5))])
        let resource = Font.FontCache.shared[key]
        let descriptor = resource.descriptor().width(0.1).weight(.light).monospaced(true).adding(features: Font.MonospacedDigitModifier.shapingFeatures)
        XCTAssertEqual(descriptor.language, "ja-Jpan-JP")
        XCTAssertEqual(descriptor.languageAwareLineHeightRatio, 0.5)
        let fonts = [
            Font(provider: FontBox(Font.ModifierProvider(base: .system(size: 23),
                modifier: LanguageFontModifier(identifier: "ja-Jpan-JP")))),
            Font(provider: FontBox(Font.ModifierProvider(base: .system(size: 23),
                modifier: LanguageAwareLineHeightRatioFontModifier(ratio: 0.5))))
        ]
        for font in fonts {
            let encoded = try JSONEncoder().encode(font.codingProxy)
            let decoded = try JSONDecoder().decode(Font.CodingProxy.self, from: encoded).base
            XCTAssertEqual(decoded, font)
        }
        for (ratio, expected) in [(TypesettingLanguageAwareLineHeightRatio.disable, 0.0), (.legacy, 0.33), (.custom(-1), 0), (.custom(2), 1)] {
            style.typesettingConfiguration.languageAwareLineHeightRatio = ratio
            XCTAssertEqual(Font.FontCache.shared[try XCTUnwrap(style.fontKey(in: environment()))].languageAwareLineHeightRatio, expected)
        }
    }

    // ASSERTIONS textParagraphStyleCacheReuseObserved
    // ASSERTIONS textParagraphBoundaryCacheFinalizationObserved
    // ASSERTIONS textParagraphAlignmentAggregationObserved
    func testParagraphCacheCopiesShareIdentityAndConflictsRemainAbsorbing() {
        var properties = Text.ResolvedProperties()
        let environment = environment()
        let first = properties.paragraph.style(environment: environment, alignment: .left, writingDirection: nil, lineHeight: .exact(points: 27))
        var copy = properties.paragraph
        let cached = copy.style(environment: environment, alignment: .right, writingDirection: .rightToLeft, lineHeight: .exact(points: 41))
        XCTAssertTrue(first === cached)
        XCTAssertEqual(cached.baselineInterval, .exact(points: 27))
        properties.markParagraphBoundary(at: 1, in: "A", environment: environment)
        XCTAssertEqual(properties.multilineTextAlignment, .leading)
        XCTAssertNil(properties.paragraph.cachedStyle)
        XCTAssertTrue(copy.cachedStyle === first)
        _ = properties.paragraph.style(environment: environment, alignment: .right, writingDirection: nil, lineHeight: nil)
        properties.markParagraphBoundary(at: 2, in: "AB", environment: environment)
        XCTAssertNil(properties.multilineTextAlignment)
        _ = properties.paragraph.style(environment: environment, alignment: .left, writingDirection: nil, lineHeight: nil)
        properties.markParagraphBoundary(at: 3, in: "ABC", environment: environment)
        XCTAssertNil(properties.multilineTextAlignment)
    }

    // ASSERTIONS textParagraphEnvironmentProducerObserved
    // ASSERTIONS textParagraphAlignmentWritingStrategiesObserved
    // ASSERTIONS textParagraphMetricsAndJustificationObserved
    // ASSERTIONS textParagraphRedactionPostprocessingObserved
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
        XCTAssertEqual(initial.horizontalAlignment, .trailing)
        XCTAssertEqual(initial.baseWritingDirection, .natural)
        XCTAssertTrue(initial.spansAllLines)
        XCTAssertEqual(initial.baselineInterval, .variable)
        XCTAssertEqual(initial.lineBreakStrategy, 65534)
        XCTAssertEqual(initial.hyphenationFactor, Float(0.8))
        context.bodyHeadOutdent = 2
        let outdent = makeParagraphStyle(context: context, alignment: nil, fallbackAlignment: .layoutBased,
            writingDirection: .rightToLeft, fallbackWritingDirection: .contentBased, lineHeight: nil)
        XCTAssertEqual(outdent.baseWritingDirection, .leftToRight)
        environment.shouldRedactContent = true
        var paragraph = Text.ResolvedProperties.Paragraph()
        paragraph.compositionLanguage = 2
        let redacted = paragraph.style(environment: environment, alignment: nil, writingDirection: nil, lineHeight: nil)
        XCTAssertEqual(redacted.compositionLanguage, 2)
        XCTAssertEqual(redacted.baseWritingDirection, .rightToLeft)
        XCTAssertEqual(redacted.lineBreakMode, 1)
        XCTAssertTrue(redacted.fullyJustified)
    }

    // ASSERTIONS textParagraphCompositionLanguageProducerObserved
    func testCompositionResetsEveryRunButCacheRetainsFirstLanguage() {
        var properties = Text.ResolvedProperties()
        var style = Text.Style()
        style.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "ja"))
        let a = style.nsAttributes(in: environment(), properties: &properties)
        style.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        let b = style.nsAttributes(in: environment(), properties: &properties)
        XCTAssertTrue(a.paragraphStyle === b.paragraphStyle)
        XCTAssertEqual(properties.paragraph.compositionLanguage, 1)
        XCTAssertEqual(b.paragraphStyle?.compositionLanguage, 2)
        for (language, category) in [("ja", 2), ("zh", 3), ("zh-Hant", 4), ("wuu-Hans", 3), ("yue-Hant", 4), ("JA", 1), ("jargon", 1), ("ar", 1)] {
            XCTAssertEqual(textCompositionLanguage(language), category, language)
        }
    }

    // ASSERTIONS textParagraphNaturalDirectionResolutionObserved
    func testKnownLanguageAndEmptyRangeDirectionFinalization() {
        var environment = environment()
        environment.textAlignmentStrategy = .writingDirectionBased
        environment.layoutDirection = .rightToLeft
        var properties = Text.ResolvedProperties()
        var style = Text.Style()
        style.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "ar"))
        let attributes = style.nsAttributes(in: environment, properties: &properties)
        properties.markParagraphBoundary(at: 3, in: "ABC", environment: environment)
        XCTAssertEqual(attributes.paragraphStyle?.baseWritingDirection, .rightToLeft)
        let empty = properties.paragraph.style(environment: environment, alignment: nil, writingDirection: nil, lineHeight: nil)
        properties.markParagraphBoundary(at: 3, in: "ABC", environment: environment)
        XCTAssertEqual(empty.baseWritingDirection, .rightToLeft)
    }

    // ASSERTIONS textStylePayloadOwnerStructureObserved
    // ASSERTIONS textParagraphAndEncapsulationPayloadObserved
    // ASSERTIONS textSpeechAccessibilityPayloadObserved
    func testTypedPayloadsReachActualAttributedRunsAndKeepSiblingIsolation() throws {
        XCTAssertEqual(Mirror(reflecting: Text.Style()).children.count, 24)
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
        XCTAssertTrue(runs[0].glyphInfo === info)
        XCTAssertNil(runs[1].glyphInfo)
        XCTAssertEqual(runs[0].textScale, .secondary)
        XCTAssertNil(runs[1].textScale)
        XCTAssertNotNil(runs[0].adaptiveImageProvider)
        XCTAssertNil(runs[1].adaptiveImageProvider)
        XCTAssertEqual(runs[0].paragraphStyle?.baselineInterval, .exact(points: 27))
        XCTAssertTrue(runs[0].paragraphStyle === runs[1].paragraphStyle)
        var style = Text.Style()
        SpeechModifier(.init(alwaysIncludesPunctuation: true, adjustedPitch: 0.75)).modify(style: &style)
        SpeechModifier(.init(spellsOutCharacters: true)).modify(style: &style)
        AccessibilityTextModifier(.init(headingLevel: .h2, label: Text(verbatim: "spoken"))).modify(style: &style)
        XCTAssertEqual(style.speech?.alwaysIncludesPunctuation, true)
        XCTAssertEqual(style.speech?.spellsOutCharacters, true)
        XCTAssertEqual(style.speech?.adjustedPitch, 0.75)
        XCTAssertEqual(style.accessibility?.headingLevel, .h2)
        style.encapsulation = .init(lineWeight: 2.5, minimumWidth: 33)
        var properties = Text.ResolvedProperties()
        let output = style.nsAttributes(in: environment(), properties: &properties)
        XCTAssertEqual(output.encapsulation?.lineWeight, 2.5)
        XCTAssertEqual(output.encapsulation?.minimumWidth, 33)
        XCTAssertFalse(output.nsAttributes.keys.contains { $0.rawValue.contains("Speech") })
    }

    // ASSERTIONS textScaleAttributeOwnerObserved
    // ASSERTIONS textShadowProducerAndAttributeObserved
    // ASSERTIONS textTransitionOptionAndStorageObserved
    // ASSERTIONS textEffectModifierLifetimeObserved
    // ASSERTIONS textAdaptiveImagePayloadConsumerObserved
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
        XCTAssertNotNil(a.shadow)
        XCTAssertTrue(properties.transitions.isEmpty)
        XCTAssertEqual(properties.insets.bottom, -12.4, accuracy: 1e-8)
        style.shadow = nil
        withExtendedLifetime(copy) { XCTAssertNotNil(weakShadow) }
        copy = nil
        XCTAssertNil(weakShadow)
        let b = style.nsAttributes(in: environment(), properties: &properties, options: .includeTransitions)
        let c = style.nsAttributes(in: environment(), properties: &properties, options: .includeTransitions)
        XCTAssertEqual(b.transitionIndex, 0)
        XCTAssertEqual(c.transitionIndex, 1)
        style.scale = .default
        var environment = environment()
        environment.textScale = .secondary
        XCTAssertNil(style.nsAttributes(in: environment, properties: &properties).textScale)
        style.adaptiveImageGlyph = TextAdaptiveImageGlyph(imageContent: Data([1, 2, 3]), contentIdentifier: "fixture", contentDescription: "fixture")
        let d = style.nsAttributes(in: environment, properties: &properties)
        let e = style.nsAttributes(in: environment, properties: &properties)
        XCTAssertFalse(d.adaptiveImageProvider === e.adaptiveImageProvider)
        XCTAssertEqual(d.adaptiveImageProvider?.glyph, e.adaptiveImageProvider?.glyph)
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
