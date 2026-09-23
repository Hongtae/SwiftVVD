import Dispatch
import Foundation
import Synchronization
import XCTest
@testable import VUI

private enum ObservedFontDefinition: FontDefinition {
    static let calls = Mutex<[String]>([])
    static func record(_ name: String) { calls.withLock { $0.append(name) } }
    static func resolveSystemFont(size: CGFloat, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> FontDescriptor {
        record("system")
        return FontDescriptor(source: .system(.default, .heavy, false), pointSize: size + 1)
    }
    static func resolveTextStyleFont(textStyle: Font.TextStyle, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> FontDescriptor {
        record("style")
        return FontDescriptor(source: .system(.default, .heavy, false), pointSize: 31)
    }
    static func resolveTextStyleFontInfo(textStyle: Font.TextStyle, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> Font.ResolvedTraits {
        record("style-info")
        return .init(pointSize: 29, weight: 0.23)
    }
    static func resolveCustomFont(name: String, size: CGFloat, textStyle: Font.TextStyle?, in context: Font.Context) -> FontDescriptor {
        record("named")
        return FontDescriptor(source: .system(.default, .heavy, false), pointSize: size + 2)
    }
}

final class FontProviderResolutionTests: XCTestCase {
    private func archive(_ font: Font) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(font.codingProxy), as: UTF8.self)
    }

    private func decode(_ json: String) throws -> Font {
        try JSONDecoder().decode(Font.CodingProxy.self, from: Data(json.utf8)).base
    }

    private func boxes(_ font: Font) -> [AnyFontBox] {
        if let wrapper = font.provider.baseProvider as? any FontWrapperProvider {
            return [font.provider] + boxes(wrapper.baseFont)
        }
        return [font.provider]
    }

    // ASSERTIONS fontProviderDescriptorDispatchObserved
    func testSystemTraitsBypassDefinitionWhileDescriptorsDispatchToIt() throws {
        ObservedFontDefinition.calls.withLock { $0.removeAll() }
        var context = EnvironmentValues().fontResolutionContext
        context.fontDefinition.base = ObservedFontDefinition.self
        let font = Font.system(size: 17.125, weight: .light)
        let traits = font.resolveTraits(in: context)
        XCTAssertEqual(traits.pointSize, 17.125)
        XCTAssertEqual(traits.weight, -0.4)
        XCTAssertNil(traits.width)
        XCTAssertTrue(ObservedFontDefinition.calls.withLock { $0.isEmpty })
        XCTAssertEqual(font.resolveDescriptor(in: context).pointSize, 18.125)
        XCTAssertEqual(ObservedFontDefinition.calls.withLock { $0 }, ["system"])
    }

    // ASSERTIONS fontProviderDescriptorDispatchObserved
    func testStyleInfoAndNamedDescriptorRoutesRemainDistinct() throws {
        ObservedFontDefinition.calls.withLock { $0.removeAll() }
        var context = EnvironmentValues().fontResolutionContext
        context.fontDefinition.base = ObservedFontDefinition.self
        let style = Font.system(.headline, design: .serif, weight: .light)
        XCTAssertEqual(style.resolveTraits(in: context).pointSize, 29)
        XCTAssertEqual(ObservedFontDefinition.calls.withLock { $0 }, ["style-info"])
        XCTAssertEqual(style.resolveDescriptor(in: context).pointSize, 31)
        let named = Font.custom("Request", fixedSize: 17.125).resolveTraits(in: context)
        XCTAssertEqual(named.pointSize, 19.125)
        XCTAssertEqual(named.weight, CGFloat(Float(0.56)))
        XCTAssertNil(named.width)
        XCTAssertEqual(ObservedFontDefinition.calls.withLock { $0 }, ["style-info", "style", "named"])
    }

    // ASSERTIONS fontRelativeSizeResolutionObserved
    func testRelativeRoundingAndAbsoluteCapBranches() throws {
        let context = EnvironmentValues().fontResolutionContext
        for (font, size) in [
            (Font.custom("Missing", fixedSize: 17.125), CGFloat(17.125)),
            (Font.custom("Missing", size: 17.125), 17),
            (Font.custom("Missing", size: 17.5, relativeTo: .title), 18)
        ] {
            XCTAssertEqual(font.resolveDescriptor(in: context).pointSize, size)
        }
        let relative = Font.SystemProvider(size: 17.5, weight: nil, design: nil, textStyle: .body, maximumSize: 17.25)
        let absolute = Font.SystemProvider(size: 17.5, weight: nil, design: nil, textStyle: nil, maximumSize: 10)
        XCTAssertEqual(relative.resolveTraits(in: context).pointSize, 17.25)
        XCTAssertEqual(absolute.resolveTraits(in: context).pointSize, 17.5)
        let medium = Font.system(size: 17, weight: .medium)
        XCTAssertEqual(medium.resolveTraits(in: context).weight, 0.23)
        XCTAssertEqual(medium.resolveDescriptor(in: context).resolvedWeight, CGFloat(Float(0.23)))
        XCTAssertEqual(Font.system(.caption2).resolveTraits(in: context).weight, CGFloat(Float(0.23)))
    }

    // ASSERTIONS fontProviderWrapperOwnershipObserved
    // ASSERTIONS fontProviderRecursiveRemovalObserved
    func testModifiersWrapAndRecursiveRemovalMakesFreshBoxesIncludingNoOps() throws {
        let base = Font.system(size: 17.125)
        let wrapped = base.bold().weight(.light).bold().bold(false)
        XCTAssertTrue(boxes(wrapped).last === base.provider)
        let removed = wrapped.removing(modifier: Font.BoldModifier.self)
        XCTAssertEqual(removed, base.weight(.light).bold(false))
        XCTAssertTrue(Set(boxes(removed).map(ObjectIdentifier.init)).intersection(boxes(wrapped).map(ObjectIdentifier.init)).isEmpty)
        let unchanged = wrapped.removing(modifier: Font.MonospacedDigitModifier.self)
        XCTAssertEqual(unchanged, wrapped)
        XCTAssertTrue(Set(boxes(unchanged).map(ObjectIdentifier.init)).intersection(boxes(wrapped).map(ObjectIdentifier.init)).isEmpty)
        XCTAssertEqual(wrapped.removing(modifier: Font.UndoModifier<Font.BoldModifier>.self),
                       base.bold().weight(.light).bold())
    }

    // ASSERTIONS fontProviderBoxEqualityHashObserved
    func testStaticHashDoesNotEraseStructuralEqualityOrNaNEquality() {
        let base = Font.system(size: 17)
        XCTAssertNotEqual(base.bold(), base.bold().bold())
        XCTAssertEqual(base.hashValue, base.bold().hashValue)
        XCTAssertEqual(base.bold().hashValue, base.italic().hashValue)
        let nan = base.weight(Font.Weight(value: .nan))
        XCTAssertFalse(nan == nan)
    }

    // ASSERTIONS fontProviderTagBoxDispatchObserved
    // ASSERTIONS fontModifierTagsAndCodingObserved
    func testFontArchivesUseProviderTagsAndSeparateProxyPayloads() throws {
        let system = #"{"tag":{"system":{}},"value":{"design":{},"size":17.125,"weight":{}}}"#
        XCTAssertEqual(try archive(.system(size: 17.125)), system)
        let style = #"{"tag":{"style":{}},"value":{"design":{},"style":{"headline":{}},"weight":{}}}"#
        XCTAssertEqual(try archive(.system(.headline)), style)
        let named = #"{"tag":{"named":{}},"value":{"name":" Font ","size":17.125,"textStyle":{"body":{}}}}"#
        XCTAssertEqual(try archive(.custom(" Font ", size: 17.125)), named)
        let weight = #"{"tag":{"modifier":{"_0":"weight"}},"value":{"font":\#(system),"modifier":0.56}}"#
        XCTAssertEqual(try archive(.system(size: 17.125).weight(.heavy)), weight)
        let bold = #"{"tag":{"staticModifier":{"_0":{"do":{"_0":{"bold":{}}}}}},"value":\#(system)}"#
        XCTAssertEqual(try archive(.system(size: 17.125).bold()), bold)
        for value in [system, style, named, weight, bold] {
            let decoded = try decode(value)
            XCTAssertEqual(try archive(decoded), value)
            XCTAssertEqual(decoded, try decode(value))
            XCTAssertFalse(decoded.provider === (try decode(value)).provider)
        }
        XCTAssertThrowsError(try decode(#"{"tag":{"unknown":{}},"value":{}}"#))
    }

    // ASSERTIONS fontContextAndTraitsContractObserved
    func testContextTracksBundleAndNativeInputsWithoutTrackingDisplayScale() throws {
        var original = EnvironmentValues()
        original.font = .system(size: 23)
        let environment = original.trackingCopy()
        let context = environment.fontResolutionContext
        let tracker = try XCTUnwrap(environment.tracker)
        XCTAssertEqual(context.sizeCategory, .large)
        XCTAssertNil(context.resourceBundle)
        XCTAssertTrue(context.fontDefinition.base == DefaultFontDefinition.self)
        var scaled = original
        scaled.displayScale = 3
        XCTAssertFalse(tracker.hasDifferentUsedValues(scaled._plist))
        var bundled = original
        bundled.resourceBundle = .main
        XCTAssertTrue(tracker.hasDifferentUsedValues(bundled._plist))
        var dynamic = original
        dynamic.dynamicTypeSize = .accessibility3
        XCTAssertEqual(dynamic.fontResolutionContext.sizeCategory, .accessibilityExtraLarge)
        XCTAssertTrue(tracker.hasDifferentUsedValues(dynamic._plist))
        var changed = context
        changed.legibilityWeight = .bold
        XCTAssertNotEqual(context, changed)
        changed = context
        changed.shouldRedactContent = true
        XCTAssertNotEqual(context, changed)
        XCTAssertEqual(context, original.fontResolutionContext)
        XCTAssertEqual(context.hashValue, original.fontResolutionContext.hashValue)
    }

    // ASSERTIONS fontStaticModifierCacheLockObserved
    // ASSERTIONS textStyleFontModifierSharingObserved
    // ASSERTIONS fontModifierDescriptorBranchesObserved
    func testStaticModifiersShareOnePublicationWhileDynamicPayloadsRemainSeparate() throws {
        let results = Mutex<[AnyFontModifier]>([])
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            let value = AnyFontModifier.static(Font.BoldModifier.self)
            results.withLock { $0.append(value) }
        }
        let modifiers = results.withLock { $0 }
        XCTAssertEqual(Set(modifiers.map(ObjectIdentifier.init)).count, 1)
        let first = AnyFontModifier.dynamic(Font.WeightModifier(weight: .heavy))
        let second = AnyFontModifier.dynamic(Font.WeightModifier(weight: .heavy))
        XCTAssertEqual(first, second)
        XCTAssertFalse(first === second)
        var context = EnvironmentValues().fontResolutionContext
        context.fontModifiers = [first]
        var copy = context
        copy.fontModifiers.append(second)
        XCTAssertEqual(context.fontModifiers.count, 1)
        XCTAssertTrue(context.fontModifiers[0] === copy.fontModifiers[0])
        let nan = AnyFontModifier.dynamic(Font.WeightModifier(weight: Font.Weight(value: .nan)))
        XCTAssertFalse(nan == nan)
        var traits = Font.ResolvedTraits(pointSize: 17.125, weight: 0.23)
        Font.BoldModifier.undo(traits: &traits)
        XCTAssertEqual(traits.weight, 0)
        traits.weight = 0.23
        AnyFontModifier.static(Font.UndoModifier<Font.BoldModifier>.self).modify(traits: &traits)
        XCTAssertEqual(traits.weight, 0.23)
        AnyFontModifier.static(Font.BoldModifier.self).modify(traits: &traits)
        XCTAssertEqual(traits.weight, 0.4)
        XCTAssertEqual(traits.pointSize, 17.125)
        XCTAssertNil(traits.width)
    }

    // ASSERTIONS fontWeightCoordinateDomainsObserved
    func testWeightCoordinatesAndBackendClassConversionRemainSeparate() {
        let weights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        XCTAssertEqual(weights.map(\.value), [-0.8, -0.6, -0.4, 0, 0.23, 0.3, 0.4, 0.56, 0.62])
        XCTAssertEqual(weights.map(\.weightClass), [33, 100, 200, 400, 530, 600, 700, 780, 810])
        XCTAssertEqual(Font.Weight(value: -0.3991).weightClass, 200)
        XCTAssertEqual(Font.Weight(value: -0.3989).weightClass, 201)
        XCTAssertEqual(Font.Weight(value: .nan).weightClass, 0)
        XCTAssertEqual(Font.Weight(value: -.infinity).weightClass, 0)
        XCTAssertEqual(Font.Weight(value: .infinity).weightClass, 1000)
    }

    // ASSERTIONS fontNamedWeightRequestObserved
    // ASSERTIONS fontCandidateTraitDistanceObserved
    // ASSERTIONS fontNamedInstanceTraitsObserved
    func testNamedRobotoSelectsInstancesByLogicalTraitsInsteadOfConvertedClass() throws {
        let environment = EnvironmentValues()
        let weights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        var coordinates: [CGFloat] = []
        for weight in weights {
            let resolved = Font.custom("Roboto-Regular", fixedSize: 17.125).weight(weight).resolved(in: environment)
            let provider = try XCTUnwrap(resolved.typefaceProvider as? BundledFontProvider)
            coordinates.append(try XCTUnwrap(provider.variations.first { $0.tag == 0x7767_6874 }?.value))
            XCTAssertFalse(provider.appliesSyntheticWeight)
        }
        XCTAssertEqual(coordinates, [100, 100, 200, 400, 500, 600, 700, 800, 800])
    }

    // ASSERTIONS fontRegisteredDefaultDescriptorTraitsObserved
    func testDefaultDescriptorTraitsDoNotReplaceDefaultGlyphCoordinates() throws {
        let font = Font.custom("NanumSquare Neo variable", fixedSize: 17.125)
        let environment = EnvironmentValues()
        XCTAssertEqual(font.resolveTraits(in: environment.fontResolutionContext).weight, 0)
        let provider = try XCTUnwrap(font.resolved(in: environment).typefaceProvider as? BundledFontProvider)
        XCTAssertEqual(provider.variations.first { $0.tag == 0x7767_6874 }?.value, 100)
        let named = Font.custom("NanumSquareNeovariable-Regular", fixedSize: 17.125)
        let regular = try XCTUnwrap(named.resolved(in: environment).typefaceProvider as? BundledFontProvider)
        XCTAssertEqual(regular.variations.first { $0.tag == 0x7767_6874 }?.value, 300)
    }

    // ASSERTIONS fontRegisteredNameAliasesObserved fontNamedCanonicalSuffixObserved
    // ASSERTIONS fontNamedDefaultInstanceLookupObserved fontParserNameSourcesObserved
    func testCanonicalAndAdditionalNamesSelectTheSameNamedInstances() throws {
        let resolver = BundledFontCatalog.shared.resources.resolver
        let names = [
            ("NanumSquareNeo-Variable_Regular", "NanumSquareNeovariable-Regular", CGFloat(300)),
            ("NanumSquareNeo-Variable_Heavy", "NanumSquareNeovariable-Heavy", CGFloat(900)),
            ("Roboto-ExtraLight", "Roboto Regular ExtraLight", CGFloat(200)),
            ("NotoSansCJKjp-Regular", "Noto Sans CJK JP Regular", CGFloat(400))
        ]
        for (canonical, alias, coordinate) in names {
            let a = try XCTUnwrap(resolver.named(canonical))
            let b = try XCTUnwrap(resolver.named(alias))
            XCTAssertEqual(a.instanceIndex, b.instanceIndex)
            XCTAssertEqual(a.face.resource, b.face.resource)
            XCTAssertEqual(a.postScriptName, canonical)
            XCTAssertEqual(a.variations.first { $0.tag == 0x7767_6874 }?.value, coordinate)
            XCTAssertEqual(resolver.named(canonical.uppercased())?.instanceIndex, a.instanceIndex)
            XCTAssertNil(resolver.named(" " + canonical))
        }
        XCTAssertNil(resolver.named("Roboto ExtraLight"))
        XCTAssertNil(resolver.named("Roboto Condensed Bold"))
    }

    // ASSERTIONS fontDefaultAndSystemSymbolicResolutionObserved
    func testDefaultForwardingAndSymbolicBoldPreserveNonBoldWeights() {
        let font = Font(provider: FontBox(Font.DefaultProvider()))
        var environment = EnvironmentValues()
        for size in [CGFloat(13), 41] {
            environment.font = .system(size: size)
            XCTAssertEqual(font.resolveTraits(in: environment.fontResolutionContext).pointSize, size)
        }
        let weights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        let enabled: [CGFloat] = [-0.8, -0.6, -0.4, 0.4, 0.23, 0.3, 0.4, 0.56, 0.62]
        let disabled: [CGFloat] = [-0.8, -0.6, -0.4, 0, 0.23, 0, 0, 0, 0]
        for index in weights.indices {
            let base = Font.system(size: 17, weight: weights[index])
            XCTAssertEqual(base.bold().resolveTraits(in: environment.fontResolutionContext).weight, enabled[index], accuracy: 0.000001)
            XCTAssertEqual(base.bold(false).resolveTraits(in: environment.fontResolutionContext).weight, disabled[index], accuracy: 0.000001)
        }
    }

    // ASSERTIONS fontItalicModifierResolutionOrderObserved fontStyleGlossaryTraitSourcesObserved
    // ASSERTIONS fontDescriptorRetainedRequestTraitsObserved
    func testOrderedDescriptorsRetainRequestTraitsAlongsideSelectedFaces() throws {
        let context = EnvironmentValues().fontResolutionContext
        let base = Font.custom("Roboto-Regular", fixedSize: 17.125)
        let first = base.weight(.light).italic().resolveDescriptor(in: context)
        let second = base.italic().weight(.light).resolveDescriptor(in: context)
        guard case let .selected(_, selected, traits) = first.source,
              case let .family(_, _, otherTraits) = second.source else {
            return XCTFail("The two modifier orders must retain different descriptor requests.")
        }
        XCTAssertEqual(selected.postScriptName, "Roboto-ExtraLightItalic")
        XCTAssertEqual(traits?.slant, 0)
        XCTAssertEqual(otherTraits.slant, CGFloat(Float(bitPattern: 0x3d8e38e3)))
        let a = try XCTUnwrap(first.weight(.heavy).typefaceProvider(in: EnvironmentValues()) as? BundledFontProvider)
        let b = try XCTUnwrap(second.weight(.heavy).typefaceProvider(in: EnvironmentValues()) as? BundledFontProvider)
        XCTAssertEqual(a.resource.url.lastPathComponent, "Roboto-VariableFont_wdth,wght.ttf")
        XCTAssertEqual(b.resource.url.lastPathComponent, "Roboto-Italic-VariableFont_wdth,wght.ttf")
        XCTAssertEqual(a.variations.first { $0.tag == 0x7767_6874 }?.value, 800)
        XCTAssertEqual(b.variations.first { $0.tag == 0x7767_6874 }?.value, 800)
    }

    // ASSERTIONS fontNamedSymbolicCopies27Observed
    func testNamedSymbolicCopiesPreserveFeaturesSizeAndLanguage() throws {
        let context = EnvironmentValues().fontResolutionContext
        let base = Font.custom("Roboto-Regular", fixedSize: 23).monospacedDigit()
            .resolveDescriptor(in: context).withTypesetting(language: "en")
        for (trait, name, weight) in [(UInt32(1), "Roboto-Italic", CGFloat(400)),
                                      (2, "Roboto-Bold", 700)] {
            let copy = base.symbolicTrait(trait, active: true)
            guard case let .selected(_, candidate, _) = copy.source else {
                return XCTFail("A supported symbolic copy must select its family variant.")
            }
            XCTAssertEqual(candidate.postScriptName, name)
            XCTAssertEqual(candidate.variations.first { $0.tag == 0x7767_6874 }?.value, weight)
            XCTAssertEqual(copy.pointSize, 23)
            XCTAssertEqual(copy.shapingFeatures, base.shapingFeatures)
            XCTAssertFalse(copy.shapingFeatures.isEmpty)
            XCTAssertEqual(copy.language, "en")
        }
        XCTAssertEqual(base.pointSize, 23)
        XCTAssertEqual(base.selectedWeight, 0)
    }

    // ASSERTIONS fontNamedSymbolicCopies27Observed
    func testUnsupportedNamedItalicPreservesTheOriginalDescriptor() throws {
        let context = EnvironmentValues().fontResolutionContext
        let original = Font.custom("NotoSansKR-Regular", fixedSize: 23).monospacedDigit()
            .resolveDescriptor(in: context).withTypesetting(language: "en")
        let copy = original.symbolicTrait(1, active: true)
        XCTAssertTrue(copy === original)
        let provider = try XCTUnwrap(copy.typefaceProvider(in: EnvironmentValues()) as? BundledFontProvider)
        XCTAssertEqual(provider.resource.url.lastPathComponent, "NotoSansKR-VariableFont_wght.ttf")
        XCTAssertEqual(provider.variations.first { $0.tag == 0x7767_6874 }?.value, 400)
        XCTAssertEqual(copy.pointSize, 23)
        XCTAssertEqual(copy.language, "en")
        XCTAssertFalse(copy.shapingFeatures.isEmpty)
    }

    // ASSERTIONS fontNamedSymbolicCopies27Observed
    func testSymbolicSelectionRequiresTheExistingCondensedTrait() throws {
        for italicWidth in [UInt16(5), 3] {
            let (bundle, fonts) = try symbolicFixtureBundle(italicWidthClass: italicWidth)
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            let original = Font.custom("Roboto-Regular", fixedSize: 23).monospacedDigit()
                .resolveDescriptor(in: environment.fontResolutionContext)
            let copy = original.symbolicTrait(1, active: true)
            let provider = try XCTUnwrap(copy.typefaceProvider(in: environment) as? BundledFontProvider)
            XCTAssertEqual(provider.resource.url.deletingLastPathComponent(), fonts)
            XCTAssertEqual(provider.resource.url.lastPathComponent, italicWidth == 3 ? "Italic.ttf" : "Font.ttf")
            XCTAssertEqual(copy === original, italicWidth != 3)
            XCTAssertEqual(copy.pointSize, 23)
            XCTAssertEqual(copy.shapingFeatures, original.shapingFeatures)
        }
    }

    // ASSERTIONS fontSymbolicCandidateScoring27Observed
    func testSymbolicSelectionAcceptsTheFirstWeightWithinTolerance() throws {
        let (bundle, _) = try scoringFixtureBundle("near")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        let original = Font.custom("Roboto-Regular", fixedSize: 23)
        let descriptor = original.italic().resolveDescriptor(in: environment.fontResolutionContext)
        guard case let .selected(_, candidate, _) = descriptor.source else {
            return XCTFail("A supported italic copy must select a family candidate.")
        }
        XCTAssertEqual(candidate.postScriptName, "P440bo-Italic")
        XCTAssertEqual(descriptor.pointSize, 23)
    }

    // ASSERTIONS fontSymbolicCandidateScoring27Observed
    func testSymbolicSelectionScoresTheRetainedWeightRequest() throws {
        let (bundle, _) = try scoringFixtureBundle("near")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        for (weight, expected) in [(Font.Weight.regular, "P440bo-Italic"), (.medium, "P450bo-Italic")] {
            let descriptor = Font.custom("Roboto-Regular", fixedSize: 23).weight(weight).italic()
                .resolveDescriptor(in: environment.fontResolutionContext)
            guard case let .selected(_, candidate, retained) = descriptor.source else {
                return XCTFail("The symbolic copy must preserve the explicit weight request.")
            }
            XCTAssertEqual(candidate.postScriptName, expected)
            XCTAssertEqual(retained?.weight, weight.value)
        }
    }

    // ASSERTIONS fontSymbolicCandidateScoring27Observed
    func testSymbolicSelectionUsesOpticalSizeOnlyWithinTheScoreTolerance() throws {
        for (fixture, expected) in [("optical-close", "P450bo-Italic"), ("optical-far", "P440bo-Italic")] {
            let (bundle, _) = try scoringFixtureBundle(fixture)
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            let descriptor = Font.custom("Roboto-Regular", fixedSize: 23).italic()
                .resolveDescriptor(in: environment.fontResolutionContext)
            guard case let .selected(_, candidate, _) = descriptor.source else {
                return XCTFail("The optical controls must select a family candidate.")
            }
            XCTAssertEqual(candidate.postScriptName, expected)
        }
    }

    // ASSERTIONS fontSymbolicCandidateScoring27Observed
    func testSymbolicSelectionPreservesTheNormalizedGradeCoordinate() throws {
        let (bundle, _) = try scoringFixtureBundle("grade")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        for (name, expected, grade) in [("Roboto-Regular", "Roboto-Italic", CGFloat(100)),
                                        ("Roboto-CandidateRegular", "Roboto-CandidateItalic", 75)] {
            let descriptor = Font.custom(name, fixedSize: 23).italic()
                .resolveDescriptor(in: environment.fontResolutionContext)
            guard case let .selected(_, candidate, _) = descriptor.source else {
                return XCTFail("The grade controls must select a family candidate.")
            }
            XCTAssertEqual(candidate.postScriptName, expected)
            XCTAssertEqual(candidate.variations.first { $0.tag == 0x4752_4144 }?.value, grade)
        }
    }

    // ASSERTIONS fontSymbolicWeightFallback27Observed
    func testMissingSymbolicCandidateCopiesTheWeightAxisWithoutSynthesizingItalic() throws {
        let (bundle, _) = try fixtureBundle(weightClass: 400)
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        let base = Font.custom("Roboto-Regular", fixedSize: 23)
        for (weight, coordinate, logical): (Font.Weight, CGFloat, CGFloat) in [
            (.medium, 530, CGFloat(Float(0.23))), (.heavy, 780, CGFloat(Float(0.56)))
        ] {
            let original = base.weight(weight).resolveDescriptor(in: context)
            let copied = original.symbolicTrait(1, active: true)
            let provider = try XCTUnwrap(copied.typefaceProvider(in: environment) as? BundledFontProvider)
            XCTAssertEqual(provider.variations.first { $0.tag == 0x7767_6874 }?.value, coordinate)
            XCTAssertEqual(copied.selectedWeight, logical)
            XCTAssertFalse(provider.appliesSyntheticWeight)
            XCTAssertFalse(copied === original)
            let face = try XCTUnwrap(provider.makeTypeface(StyleTestAppContext(), dpi: 72))
            XCTAssertEqual(face.selectedFont?.variation, [0x7767_6874: coordinate])
            XCTAssertEqual(face.selectedFont?.variationExtras, [0x7767_6874: coordinate])
            XCTAssertEqual(face.selectedFont?.descriptor.postScriptName,
                coordinate == 530 ? "Roboto-Regular_wght2120000_wdth" : "Roboto-Regular_wght30C0000_wdth")
        }
        let regular = base.resolveDescriptor(in: context)
        XCTAssertFalse(regular.symbolicTrait(1, active: true) === regular)
        let light = base.weight(.light).resolveDescriptor(in: context)
        XCTAssertTrue(light.symbolicTrait(1, active: true) === light)
    }

    // ASSERTIONS fontSymbolicVariationRetention27Observed
    func testSymbolicFallbackVariationSurvivesLaterFamilyAndSymbolicCopies() throws {
        let (bundle, _) = try fixtureBundle(weightClass: 400)
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let base = Font.custom("Roboto-Regular", fixedSize: 23).weight(.medium).italic()
        for (font, width) in [(base.weight(.heavy), CGFloat(100)), (base.weight(.regular), 100),
                              (base.bold(), 100), (base.italic(), 100), (base.width(.condensed), 75)] {
            let descriptor = font.resolveDescriptor(in: environment.fontResolutionContext)
            let provider = try XCTUnwrap(descriptor.typefaceProvider(in: environment) as? BundledFontProvider)
            let selected = try XCTUnwrap(provider.makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
            XCTAssertEqual(selected.variation[0x7767_6874], 530)
            XCTAssertEqual(selected.variation[0x7764_7468] ?? 100, width)
            XCTAssertEqual(descriptor.selectedWeight, CGFloat(Float(0.23)))
        }
        let condensed = Font.custom("Roboto-Regular", fixedSize: 23).width(.condensed)
            .weight(.medium).italic().weight(.heavy)
        let provider = try XCTUnwrap(condensed.resolved(in: environment).typefaceProvider as? BundledFontProvider)
        let selected = try XCTUnwrap(provider.makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
        XCTAssertEqual(selected.variation, [0x7767_6874: 530, 0x7764_7468: 75])
    }

    // ASSERTIONS fontSymbolicVariationRetention27Observed
    func testSymbolicFallbackVariationSurvivesResourceReconstructionAndResize() throws {
        let (bundle, _) = try fixtureBundle(weightClass: 400)
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        let base = Font.custom("Roboto-Regular", fixedSize: 23).weight(.medium).italic().monospacedDigit()
        let resource = FontResource(descriptor: base.resolveDescriptor(in: context)
            .withTypesetting(language: "en"), in: context)
        for resource in [resource, try XCTUnwrap(resource.fontWithSize(31))] {
            for copy in [resource.descriptor().weight(.heavy), resource.descriptor().clearFeatures(),
                         resource.descriptor().leading(.loose)] {
                let provider = try XCTUnwrap(copy.typefaceProvider(in: environment) as? BundledFontProvider)
                XCTAssertEqual(provider.variations.first { $0.tag == 0x7767_6874 }?.value, 530)
                XCTAssertEqual(copy.pointSize, resource.pointSize)
                XCTAssertEqual(copy.language, "en")
            }
        }
        let wrapped = base.resolved(in: environment).weight(.heavy).resolved(in: environment)
        let provider = try XCTUnwrap(wrapped.typefaceProvider as? BundledFontProvider)
        XCTAssertEqual(provider.variations.first { $0.tag == 0x7767_6874 }?.value, 530)
        XCTAssertFalse(wrapped.platformFont(in: context).shapingFeatures.isEmpty)
    }

    // ASSERTIONS fontSymbolicWeightFallback27Observed
    func testSymbolicWeightFallbackRequiresAnAxisAndAnInRangeCoordinate() throws {
        for kind in ["unnamed", "bounded", "static"] {
            let (bundle, _) = try fallbackFixtureBundle(kind)
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            environment.defaultFontRenderingMode = .vector()
            let original = Font.custom("Roboto-Regular", fixedSize: 23)
                .resolveDescriptor(in: environment.fontResolutionContext)
            let bold = original.symbolicTrait(2, active: true)
            let provider = try XCTUnwrap(bold.typefaceProvider(in: environment) as? BundledFontProvider)
            XCTAssertEqual(bold === original, kind != "unnamed")
            XCTAssertEqual(provider.variations.first { $0.tag == 0x7767_6874 }?.value,
                           kind == "static" ? nil : (kind == "unnamed" ? 700 : 400))
            if kind != "unnamed" {
                let medium = original.weight(.medium)
                XCTAssertTrue(medium.symbolicTrait(1, active: true) === medium)
            }
        }
    }

    // ASSERTIONS fontSymbolicWeightFallback27Observed
    func testSymbolicWeightFallbackUsesTheExistingCoordinateTolerance() throws {
        let (bundle, _) = try fixtureBundle(weightClass: 400)
        let catalog = try XCTUnwrap(BundledFontCatalog.catalog(in: bundle))
        let base = try XCTUnwrap(catalog.resources.resolver.named("Roboto-Regular"))
        for coordinate in [CGFloat(530), 530.0005] {
            let current = base.applying(variation: [0x7767_6874: coordinate])
            XCTAssertNil(FontResourceResolver.symbolicWeightVariation(from: current, weight: 0.23))
        }
        let changed = base.applying(variation: [0x7767_6874: 530.0015])
        XCTAssertEqual(FontResourceResolver.symbolicWeightVariation(from: changed, weight: 0.23),
                       [0x7767_6874: 530])
        XCTAssertEqual(FontResourceResolver.symbolicWeightVariation(from: base, weight: 0), [:])
    }

    // ASSERTIONS fontSymbolicVariationRetention27Observed
    func testLaterWeightFallbackReplacesTheRetainedCoordinate() throws {
        let (bundle, _) = try fallbackFixtureBundle("unnamed")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        let original = Font.custom("Roboto-Regular", fixedSize: 23).weight(.medium).italic()
            .resolveDescriptor(in: environment.fontResolutionContext)
        let copied = original.symbolicTrait(2, active: true)
        XCTAssertEqual(original.variation, [0x7767_6874: 530])
        XCTAssertEqual(copied.variation, [0x7767_6874: 700])
    }

    // ASSERTIONS fontGeneratedNameLookup27Observed
    func testGeneratedNamesResolveParserCoordinatesBeforeRasterClamping() throws {
        let (bundle, _) = try fallbackFixtureBundle("unnamed")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = StyleTestAppContext()
        let cases: [(String, String, [UInt32: CGFloat])] = [
            ("_wght2120000", "_wght2120000_wdth", [0x7767_6874: 530]),
            ("_wdth4b0000_wght2120000", "_wght2120000_wdth4B0000", [0x7767_6874: 530, 0x7764_7468: 75]),
            ("_wght", "", [:]),
            ("_wght0", "_wght0_wdth", [0x7767_6874: 100]),
            ("_wghtFFFF0000", "_wghtFFFF0000_wdth", [0x7767_6874: 100]),
            ("_wght3E80000", "_wght3E80000_wdth", [0x7767_6874: 900]),
            ("_wght1002120000", "_wght2120000_wdth", [0x7767_6874: 530]),
            ("_wght0000000002120000", "_wght2120000_wdth", [0x7767_6874: 530]),
            ("_wght2120000_wght2BC0000", "_wght2BC0000_wdth", [0x7767_6874: 700]),
            ("_wght2120000_wght", "", [:]),
            ("_%77%67%68%742120000", "_wght2120000_wdth", [0x7767_6874: 530]),
            ("_wdth2120000", "_wght_wdth2120000", [0x7764_7468: 100]),
            ("_wght80000000", "_wght80000000_wdth", [0x7767_6874: 100]),
            ("_wghtFFFFFFFF", "_wghtFFFFFFFF_wdth", [0x7767_6874: 100]),
            ("_wght100000000", "_wght0_wdth", [0x7767_6874: 100]),
        ]
        for (input, output, variation) in cases {
            let resource = Font.custom("Roboto-Regular" + input, fixedSize: 23).resolved(in: environment)
            let provider = try XCTUnwrap(resource.typefaceProvider as? BundledFontProvider)
            XCTAssertTrue(provider.resource.url.path.hasPrefix(bundle.bundleURL.path), input)
            let selected = try XCTUnwrap(provider.makeTypeface(context, dpi: 72)?.selectedFont)
            XCTAssertEqual(selected.descriptor.postScriptName, "Roboto-Regular" + output, input)
            XCTAssertEqual(selected.variation, variation, input)
            XCTAssertNil(selected.variationExtras, input)
            XCTAssertEqual(selected.pointSize, 23)
        }
    }

    // ASSERTIONS fontGeneratedNameLookup27Observed
    func testGeneratedNameLookupRejectsUnknownAxesAndMalformedSuffixes() throws {
        let (bundle, _) = try fallbackFixtureBundle("unnamed")
        let catalog = try XCTUnwrap(BundledFontCatalog.catalog(in: bundle))
        for suffix in ["_XXXX2120000", "_wg", "_", "_wght2120000_", "_wght+2120000",
                       "_wght-2120000", "_wght2120000G", "_WGHT2120000", "_%7Gght2120000",
                       "_wght2120000 wdth", "_wght2120000\t", "_wght2120000_XXXX"] {
            XCTAssertNil(catalog.resources.resolver.named("Roboto-Regular" + suffix), suffix)
        }
        XCTAssertNil(catalog.resources.resolver.named("Roboto_wght2120000"))
        let registered = BundledFontCatalog.shared.resources.resolver
        XCTAssertNotNil(registered.named("NanumSquareNeo-Variable_Heavy"))
    }

    // ASSERTIONS fontGeneratedNameLookup27Observed fontGeneratedNameRematching27Observed
    func testDescriptorCopyRematchesGeneratedNameAndRetainsNearParserCoordinate() throws {
        let (bundle, _) = try fallbackFixtureBundle("unnamed")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let original = FontDescriptor(source: .named("Roboto-Regular", bundle), pointSize: 23,
                                      variation: [0x7767_6874: 530.0015])
        let descriptor = original.symbolicTrait(1, active: true)
        XCTAssertEqual(descriptor.variation, [0x7767_6874: 530])
        let provider = try XCTUnwrap(descriptor.typefaceProvider(in: environment) as? BundledFontProvider)
        let selected = try XCTUnwrap(provider.makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
        XCTAssertEqual(selected.descriptor.postScriptName, "Roboto-Regular_wght2120062_wdth")
        XCTAssertEqual(selected.variation, [0x7767_6874: 530])
        XCTAssertEqual(selected.variationExtras, [0x7767_6874: 530])
    }

    // ASSERTIONS fontGeneratedNameRematching27Observed
    func testRepeatedSymbolicFallbackUsesDefaultResourceAfterFamilyNameMiss() throws {
        let (bundle, _) = try fallbackFixtureBundle("unnamed")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let descriptor = Font.custom("Roboto-Regular", fixedSize: 23).weight(.medium).italic().bold()
            .resolveDescriptor(in: environment.fontResolutionContext)
        XCTAssertEqual(descriptor.variation, [0x7767_6874: 700])
        let provider = try XCTUnwrap(descriptor.typefaceProvider(in: environment) as? BundledFontProvider)
        let fallback = try XCTUnwrap(Font.custom("NoSuchFont_Reentry", fixedSize: 23)
            .resolved(in: environment).typefaceProvider as? BundledFontProvider)
        XCTAssertEqual(provider.resource, fallback.resource)
        let selected = try XCTUnwrap(provider.makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
        let ordinary = try XCTUnwrap(fallback.makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
        XCTAssertEqual(selected.descriptor, ordinary.descriptor)
        XCTAssertEqual(selected.variation, ordinary.variation)
        XCTAssertEqual(selected.variationExtras, [0x7767_6874: 700])
        let retained = FontResource(descriptor: FontDescriptor(source: .typeface(provider), pointSize: 23),
                                    in: environment.fontResolutionContext)
        let resized = try XCTUnwrap(retained.fontWithSize(31))
        let resizedProvider = try XCTUnwrap(resized.provider as? BundledFontProvider)
        let resizedSelection = try XCTUnwrap(resizedProvider.makeTypeface(StyleTestAppContext(), dpi: 144)?.selectedFont)
        XCTAssertEqual(resizedSelection.descriptor, ordinary.descriptor)
        XCTAssertEqual(resizedSelection.variation, ordinary.variation)
        XCTAssertEqual(resizedSelection.variationExtras, [0x7767_6874: 700])
        XCTAssertEqual(resizedSelection.pointSize, 31)
    }

    // ASSERTIONS fontNameCacheURLPrecision27Observed
    func testRepeatedGeneratedNamesUseTheSerializedCoordinatePrecision() throws {
        let cases = [
            ("2120062", "2120041"), ("640001", "640000"), ("3E80062", "3E80000"),
            ("10000", "10000"), ("1", "1"), ("FFFFFFFF", "FFFFFFFF"),
            ("80000000", "80000000"), ("7FFFFFFF", "7FFFFFFF"),
            ("75BCD15", "75BCCCC"), ("186A1", "186A0"),
            ("211FFFF", "2120000"), ("2120021", "2120000")
        ]
        for named in [false, true] {
            let (bundle, _) = try named ? fixtureBundle(weightClass: 400) : fallbackFixtureBundle("unnamed")
            let resolver = try XCTUnwrap(BundledFontCatalog.catalog(in: bundle)).resources.resolver
            for (cold, warm) in cases {
                let request = "Roboto-Regular_wght" + cold + "_wdth4B1F9A"
                let first = try XCTUnwrap(resolver.named(request)).variationSelection
                let second = try XCTUnwrap(resolver.named(request)).variationSelection
                XCTAssertEqual(first.postScriptName, request)
                XCTAssertEqual(second.postScriptName, "Roboto-Regular_wght" + warm + "_wdth4B1F97", request)
                XCTAssertEqual(first.coordinates[1], CGFloat(0x4B1F9A) / 65536)
                XCTAssertEqual(second.coordinates[1], 75.1234)
            }
        }
    }

    // ASSERTIONS fontNameCacheLifetime27Observed
    func testGeneratedNameCacheIncludesBaseRequestsAndPromotesHits() throws {
        let (bundle, _) = try fallbackFixtureBundle("unnamed")
        let resolver = try XCTUnwrap(BundledFontCatalog.catalog(in: bundle)).resources.resolver
        func name(_ value: Int) -> String {
            "Roboto-Regular_wght" + String(value << 16 | 98, radix: 16, uppercase: true) + "_wdth"
        }
        for value in 530..<545 {
            XCTAssertEqual(resolver.named(name(value))?.variationSelection.postScriptName, name(value))
        }
        let warm = "Roboto-Regular_wght2120041_wdth"
        XCTAssertEqual(resolver.named(name(530))?.variationSelection.postScriptName, warm)
        XCTAssertEqual(resolver.named(name(545))?.variationSelection.postScriptName, name(545))
        XCTAssertEqual(resolver.named(name(530))?.variationSelection.postScriptName, warm)
        XCTAssertEqual(resolver.named(name(531))?.variationSelection.postScriptName, name(531))
        XCTAssertEqual(resolver.named(name(532))?.variationSelection.postScriptName, name(532))
    }

    // ASSERTIONS fontNameCacheLifetime27Observed
    func testGeneratedNameCacheSeparatesExactKeysCatalogsAndThreads() throws {
        let (bundle, _) = try fallbackFixtureBundle("unnamed")
        let resolver = try XCTUnwrap(BundledFontCatalog.catalog(in: bundle)).resources.resolver
        let name = "Roboto-Regular_wght2120062_wdth"
        let warm = "Roboto-Regular_wght2120041_wdth"
        XCTAssertEqual(resolver.named(name)?.variationSelection.postScriptName, name)
        XCTAssertEqual(resolver.named(name.lowercased())?.variationSelection.postScriptName, name)
        XCTAssertEqual(resolver.named(name)?.variationSelection.postScriptName, warm)
        let (otherBundle, _) = try fallbackFixtureBundle("unnamed")
        let other = try XCTUnwrap(BundledFontCatalog.catalog(in: otherBundle)).resources.resolver
        XCTAssertEqual(other.named(name)?.variationSelection.postScriptName, name)
        XCTAssertEqual(other.named(name)?.variationSelection.postScriptName, warm)
        let values = Mutex<[String?]>([])
        for _ in 0..<2 {
            let done = DispatchSemaphore(value: 0)
            let thread = Thread {
                let first = resolver.named(name)?.variationSelection.postScriptName
                let second = resolver.named(name)?.variationSelection.postScriptName
                values.withLock { $0.append(contentsOf: [first, second]) }
                done.signal()
            }
            thread.start()
            done.wait()
        }
        XCTAssertEqual(values.withLock { $0 }, [name, warm, name, warm])
        XCTAssertEqual(resolver.named(name)?.variationSelection.postScriptName, warm)
    }

    // ASSERTIONS fontNameCacheCopyRetention27Observed fontDescriptorCopyConstruction27Observed
    func testResolvedGeneratedNameCopiesRetainSelectionAndOriginalVariation() throws {
        let (bundle, _) = try fallbackFixtureBundle("unnamed")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let name = "Roboto-Regular_wght2120062_wdth"
        let warm = "Roboto-Regular_wght2120041_wdth"
        let original = Font.custom(name, fixedSize: 23).platformFont(in: environment.fontResolutionContext)
        let context = StyleTestAppContext()
        func selected(_ resource: FontResource, dpi: UInt32 = 72) throws -> SelectedFont {
            try XCTUnwrap(resource.provider.makeTypeface(context, dpi: dpi)?.selectedFont)
        }
        XCTAssertEqual(try selected(original).descriptor.postScriptName, name)
        XCTAssertEqual(original.descriptor().variation, [0x7767_6874: 530.0014])
        let fresh = Font.custom(name, fixedSize: 31).platformFont(in: environment.fontResolutionContext)
        XCTAssertEqual(try selected(fresh).descriptor.postScriptName, warm)
        XCTAssertEqual(try selected(fresh).variation, [0x7767_6874: 530.001])
        let resized = try XCTUnwrap(original.fontWithSize(31))
        for resource in [original, resized] {
            let descriptor = resource.descriptor()
            let copied = FontResource(descriptor: descriptor, in: environment.fontResolutionContext)
            XCTAssertEqual(try selected(copied, dpi: 144).descriptor.postScriptName, name)
            XCTAssertEqual(try selected(copied).variation, [0x7767_6874: 530.0014])
            XCTAssertEqual(try selected(copied).pointSize, resource.pointSize)
            let cleared = FontResource(descriptor: descriptor.clearFeatures(), in: environment.fontResolutionContext)
            XCTAssertEqual(try selected(cleared).descriptor.postScriptName, name)
        }
        let wrapped = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
        let feature = wrapped.monospacedDigit().platformFont(in: environment.fontResolutionContext)
        XCTAssertEqual(try selected(feature).descriptor.postScriptName, warm)
        XCTAssertEqual(try selected(feature).variation, [0x7767_6874: 530.0014])
        XCTAssertEqual(feature.shapingFeatures, [TypefaceShapingFeature(tag: 0x746e_756d)])
        let italic = wrapped.italic().platformFont(in: environment.fontResolutionContext)
        XCTAssertEqual(try selected(italic).descriptor.postScriptName, warm)
        XCTAssertEqual(try selected(italic).variation, [0x7767_6874: 530])
    }

    // ASSERTIONS fontDescriptorCopyConstruction27Observed
    func testVariationConstructedCopiesKeepTheBaseAndUnclampedOriginalAttribute() throws {
        let (bundle, _) = try fallbackFixtureBundle("unnamed")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let original = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
            pointSize: 23, variation: [0x7767_6874: 1000]), in: environment.fontResolutionContext)
        let wrapped = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
        let modified = wrapped.monospacedDigit().platformFont(in: environment.fontResolutionContext)
        for resource in [original, modified, try XCTUnwrap(modified.fontWithSize(31))] {
            let selected = try XCTUnwrap(resource.provider.makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
            XCTAssertEqual(selected.descriptor.postScriptName, "Roboto-Regular_wght3E80000_wdth")
            XCTAssertEqual(selected.variation, [0x7767_6874: 900])
            XCTAssertEqual(selected.variationExtras, [0x7767_6874: 1000])
            XCTAssertEqual(resource.descriptor().variation, [0x7767_6874: 1000])
            XCTAssertEqual(selected.pointSize, resource.pointSize)
        }
        let (named, _) = try fixtureBundle(weightClass: 400)
        environment.resourceBundle = named
        let bold = Font.custom("Roboto-Regular", fixedSize: 23).weight(.bold)
            .platformFont(in: environment.fontResolutionContext)
        XCTAssertNil(bold.descriptor().variation)
    }

    // ASSERTIONS fontLeadingCopyConstruction27Observed
    func testLeadingCopiesKeepOriginalVariationThroughOrderedSelection() throws {
        for leading in [Font.Leading.standard, .tight, .loose] {
            let (bundle, _) = try fallbackFixtureBundle("unnamed")
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            environment.defaultFontRenderingMode = .vector()
            let context = StyleTestAppContext()
            let original = Font.custom("Roboto-Regular_wght2120062_wdth", fixedSize: 23)
                .platformFont(in: environment.fontResolutionContext)
            let wrapped = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
            let resource = wrapped.leading(leading).platformFont(in: environment.fontResolutionContext)
            let selected = try XCTUnwrap(resource.provider.makeTypeface(context, dpi: 72)?.selectedFont)
            let suffix = leading == .standard ? "2120041" : "212005B"
            XCTAssertEqual(selected.descriptor.postScriptName, "Roboto-Regular_wght" + suffix + "_wdth")
            XCTAssertEqual(selected.variation, [0x7767_6874: 530.0014])
            XCTAssertEqual(resource.descriptor().variation, [0x7767_6874: 530.0014])
            XCTAssertEqual(selected.pointSize, 23)

            let explicit = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                pointSize: 23, variation: [0x7767_6874: 1000]), in: environment.fontResolutionContext)
            let explicitCopy = Font(provider: FontBox(Font.PlatformFontProvider(font: explicit)))
                .leading(leading).platformFont(in: environment.fontResolutionContext)
            let explicitSelected = try XCTUnwrap(explicitCopy.provider.makeTypeface(context, dpi: 72)?.selectedFont)
            XCTAssertEqual(explicitSelected.descriptor.postScriptName, "Roboto-Regular_wght3E80000_wdth")
            XCTAssertEqual(explicitSelected.variation, [0x7767_6874: 900])
            XCTAssertEqual(explicitSelected.variationExtras, [0x7767_6874: 1000])
            XCTAssertEqual(explicitCopy.descriptor().variation, [0x7767_6874: 1000])

            let (named, _) = try fixtureBundle(weightClass: 400)
            environment.resourceBundle = named
            let bold = Font.custom("Roboto-Regular", fixedSize: 23).weight(.bold)
                .platformFont(in: environment.fontResolutionContext)
            let namedCopy = Font(provider: FontBox(Font.PlatformFontProvider(font: bold)))
                .leading(leading).platformFont(in: environment.fontResolutionContext)
            let namedSelected = try XCTUnwrap(namedCopy.provider.makeTypeface(context, dpi: 72)?.selectedFont)
            XCTAssertEqual(namedSelected.descriptor.postScriptName, "Roboto-Bold")
            XCTAssertEqual(namedSelected.variation, [0x7767_6874: 700])
            XCTAssertNil(namedCopy.descriptor().variation)
        }
    }

    // ASSERTIONS fontLeadingCopyConstruction27Observed
    func testCustomLeadingReselectsFamilyWithoutInventingOriginalVariation() throws {
        for named in [false, true] {
            for leading in [Font.Leading.standard, .tight, .loose] {
                let (bundle, _) = try named ? fixtureBundle(weightClass: 400) : fallbackFixtureBundle("unnamed")
                var environment = EnvironmentValues()
                environment.resourceBundle = bundle
                environment.defaultFontRenderingMode = .vector()
                let resource = Font.custom("Roboto-Regular_wght2120062_wdth", fixedSize: 23)
                    .leading(leading).platformFont(in: environment.fontResolutionContext)
                let selected = try XCTUnwrap(resource.provider.makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
                let expectedName = leading == .standard ? "Roboto-Regular_wght2120041_wdth"
                    : named ? "Roboto-Medium" : "Roboto-Regular"
                let expectedVariation: [UInt32: CGFloat] = leading == .standard ? [0x7767_6874: 530.001]
                    : named ? [0x7767_6874: 500] : [:]
                XCTAssertEqual(selected.descriptor.postScriptName, expectedName)
                XCTAssertEqual(selected.variation, expectedVariation)
                XCTAssertNil(selected.variationExtras)
            }
        }
    }

    func testAppCatalogMissContinuesToModuleBeforeDefaultFallback() throws {
        let (bundle, _) = try fixtureBundle(weightClass: 400)
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        let moduleFont = Font.custom("NanumSquareNeo-Variable_Heavy", fixedSize: 17)
        let provider = try XCTUnwrap(moduleFont.resolved(in: environment).typefaceProvider as? BundledFontProvider)
        XCTAssertTrue(provider.resource.url.path.hasPrefix(BundledFontCatalog.shared.resources.resourceDirectory.path))
        XCTAssertEqual(provider.variations.first { $0.tag == 0x7767_6874 }?.value, 900)
        let missing = Font.custom("NoSuchFont_BundleScope_167", fixedSize: 17)
        XCTAssertEqual(missing.resolved(in: environment), missing.resolved(in: EnvironmentValues()))
    }

    // ASSERTIONS fontCandidateOrderAndTieObserved
    func testCandidateTieUsesInputOrderAndSingletonSkipsDistance() throws {
        let resolver = BundledFontCatalog.shared.resources.resolver
        let regular = try XCTUnwrap(resolver.named("Roboto-Regular"))
        let medium = try XCTUnwrap(resolver.named("Roboto-Medium"))
        var request = regular.traits
        request.weight = (regular.traits.weight + medium.traits.weight) / 2
        XCTAssertEqual(FontResourceResolver.select([regular, medium], matching: request)?.postScriptName, "Roboto-Regular")
        XCTAssertEqual(FontResourceResolver.select([medium, regular], matching: request)?.postScriptName, "Roboto-Medium")
        request.weight = .nan
        XCTAssertEqual(FontResourceResolver.select([medium], matching: request)?.postScriptName, "Roboto-Medium")
        XCTAssertNil(FontResourceResolver.select([], matching: request))
    }

    func testConsumingBundleControlsNamesTraitsAndResolvedCacheIdentity() throws {
        let (firstBundle, firstFonts) = try fixtureBundle(weightClass: 400)
        let (secondBundle, secondFonts) = try fixtureBundle(weightClass: 700)
        let request = Font.custom("Roboto-Regular", fixedSize: 17.125)
        var first = EnvironmentValues()
        var second = EnvironmentValues()
        first.resourceBundle = firstBundle
        second.resourceBundle = secondBundle
        let a = request.resolved(in: first)
        let b = request.resolved(in: second)
        let pa = try XCTUnwrap(a.typefaceProvider as? BundledFontProvider)
        let pb = try XCTUnwrap(b.typefaceProvider as? BundledFontProvider)
        XCTAssertEqual(pa.resource.url, firstFonts.appendingPathComponent("Font.ttf"))
        XCTAssertEqual(pb.resource.url, secondFonts.appendingPathComponent("Font.ttf"))
        XCTAssertEqual(request.resolveTraits(in: first.fontResolutionContext).weight, 0)
        XCTAssertEqual(request.resolveTraits(in: second.fontResolutionContext).weight, CGFloat(Float(0.4)))
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(SceneResources.TypefaceKey(font: a, dpi: 72), SceneResources.TypefaceKey(font: b, dpi: 72))
        XCTAssertEqual(a, request.resolved(in: first))
        XCTAssertNotEqual(first.fontResolutionContext, second.fontResolutionContext)
    }

    // ASSERTIONS fontDescriptorOwnershipObserved
    // ASSERTIONS fontNamedLookupRequestPreservedObserved
    func testNamedDescriptorRetainsScopeAfterProviderAndEnvironmentLeaveScope() throws {
        let (bundle, fonts) = try fixtureBundle(weightClass: 400)
        weak var original: AnyFontBox?
        let descriptor: FontDescriptor = {
            let font = Font.custom("Roboto-Regular", fixedSize: 17.125)
            original = font.provider
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            return font.resolveDescriptor(in: environment.fontResolutionContext)
        }()
        XCTAssertNil(original)
        let provider = try XCTUnwrap(descriptor.typefaceProvider(in: EnvironmentValues()) as? BundledFontProvider)
        XCTAssertEqual(provider.resource.url, fonts.appendingPathComponent("Font.ttf"))
        XCTAssertEqual(descriptor.pointSize, 17.125)
    }

    func testIndependentResolutionThreadsKeepTheirBundleSources() throws {
        let (firstBundle, firstFonts) = try fixtureBundle(weightClass: 400)
        let (secondBundle, secondFonts) = try fixtureBundle(weightClass: 700)
        let font = Font.custom("Roboto-Regular", fixedSize: 17.125)
        let results = Mutex<[(Int, URL?, CGFloat)]>([])
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            var environment = EnvironmentValues()
            environment.resourceBundle = index.isMultiple(of: 2) ? firstBundle : secondBundle
            let descriptor = font.resolveDescriptor(in: environment.fontResolutionContext)
            let provider = descriptor.typefaceProvider(in: environment) as? BundledFontProvider
            results.withLock { $0.append((index, provider?.resource.url, descriptor.resolvedWeight)) }
        }
        for (index, url, weight) in results.withLock({ $0 }) {
            XCTAssertEqual(url, (index.isMultiple(of: 2) ? firstFonts : secondFonts).appendingPathComponent("Font.ttf"))
            XCTAssertEqual(weight, index.isMultiple(of: 2) ? 0 : CGFloat(Float(0.4)))
        }
    }

    private func scoringFixtureBundle(_ fixture: String) throws -> (Bundle, URL) {
        let (bundle, fonts) = try fixtureBundle(weightClass: 400)
        let directory = BundledFontCatalog.shared.resources.resourceDirectory.appendingPathComponent("Roboto")
        let regular = directory.appendingPathComponent("Roboto-VariableFont_wdth,wght.ttf")
        let italic = directory.appendingPathComponent("Roboto-Italic-VariableFont_wdth,wght.ttf")
        let specs: [(URL, String, Int, Int)]
        if fixture == "grade" {
            specs = [(regular, "Font.ttf", 400, 100), (italic, "Roboto-Italic.ttf", 400, 100)]
        } else {
            let last = fixture == "optical-far" ? 460 : 450
            specs = [(regular, "Font.ttf", fixture == "near" ? 450 : 440, 100),
                     (italic, "P440bo-Italic.ttf", 440, 75), (italic, "P\(last)bo-Italic.ttf", last, 100)]
        }
        for (source, name, weight, optical) in specs {
            var data = try Data(contentsOf: source)
            func uint16(_ offset: Int) -> Int { Int(data[offset]) << 8 | Int(data[offset + 1]) }
            func uint32(_ offset: Int) -> Int { uint16(offset) << 16 | uint16(offset + 2) }
            func write16(_ value: Int, at offset: Int) {
                data[offset] = UInt8((value >> 8) & 255)
                data[offset + 1] = UInt8(value & 255)
            }
            func write32(_ value: Int, at offset: Int) {
                write16(value >> 16, at: offset)
                write16(value, at: offset + 2)
            }
            for index in 0..<uint16(4) {
                let record = 12 + index * 16
                let tag = String(bytes: data[record..<record + 4], encoding: .ascii)
                let offset = uint32(record + 8)
                if tag == "OS/2" { write16(weight, at: offset + 4) }
                else if tag == "STAT" && fixture == "grade" { data[record + 3] = 0x5f }
                else if tag == "fvar" {
                    let axes = offset + uint16(offset + 4)
                    if fixture == "near" { data[record + 3] = 0x5f }
                    else if fixture == "grade" {
                        data.replaceSubrange(axes + 20..<axes + 24, with: "GRAD".utf8)
                    } else {
                        write16(0, at: offset + 12)
                        write32(weight * 65536, at: axes + 8)
                        data.replaceSubrange(axes + 20..<axes + 24, with: "opsz".utf8)
                        write32(65536, at: axes + 24)
                        write32(optical * 65536, at: axes + 28)
                        write32(200 * 65536, at: axes + 32)
                    }
                }
            }
            let oldName = fixture == "grade" ? "Condensed" : "Roboto-Italic"
            let newName = fixture == "grade" ? "Candidate" : String(name.dropLast(4))
            if fixture == "grade" || source == italic {
                let old = try XCTUnwrap(oldName.data(using: .utf16BigEndian))
                let new = try XCTUnwrap(newName.data(using: .utf16BigEndian))
                XCTAssertEqual(old.count, new.count)
                while let range = data.range(of: old) { data.replaceSubrange(range, with: new) }
            }
            // Only descriptor metadata is exercised; these derivatives are never raster fixtures.
            try data.write(to: fonts.appendingPathComponent(name))
        }
        let configURL = fonts.appendingPathComponent("font-config.json")
        var config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        var descriptors = try XCTUnwrap(config["fonts"] as? [String: [String: Any]])
        var primary = try XCTUnwrap(descriptors["Primary"])
        primary["sources"] = specs.map {
            ["file": $0.1, "faceIndex": 0, "weight": $0.2, "italic": $0.0 == italic] as [String: Any]
        }
        descriptors["Primary"] = primary
        config["fonts"] = descriptors
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)
        let catalog = try XCTUnwrap(BundledFontCatalog.catalog(in: bundle))
        XCTAssertEqual(catalog.resources.resourceDirectory, fonts)
        return (bundle, fonts)
    }

    private func symbolicFixtureBundle(italicWidthClass: UInt16) throws -> (Bundle, URL) {
        let (bundle, fonts) = try fixtureBundle(weightClass: 400)
        func writeStaticFace(from source: URL, to destination: URL, width: UInt16) throws {
            var data = try Data(contentsOf: source)
            func uint16(_ offset: Int) -> Int { Int(data[offset]) << 8 | Int(data[offset + 1]) }
            func uint32(_ offset: Int) -> Int { uint16(offset) << 16 | uint16(offset + 2) }
            for index in 0..<uint16(4) {
                let record = 12 + index * 16
                let tag = String(bytes: data[record..<record + 4], encoding: .ascii)
                if tag == "OS/2" {
                    let offset = uint32(record + 8) + 6
                    data[offset] = UInt8(width >> 8)
                    data[offset + 1] = UInt8(width & 255)
                } else if tag == "fvar" {
                    // Hide the axis directory to keep this metadata-only fixture static.
                    data[record + 3] = 0x5f
                }
            }
            try data.write(to: destination)
        }
        let regular = fonts.appendingPathComponent("Font.ttf")
        let italic = BundledFontCatalog.shared.resources.resourceDirectory
            .appendingPathComponent("Roboto/Roboto-Italic-VariableFont_wdth,wght.ttf")
        try writeStaticFace(from: regular, to: regular, width: 3)
        try writeStaticFace(from: italic, to: fonts.appendingPathComponent("Italic.ttf"), width: italicWidthClass)
        let configURL = fonts.appendingPathComponent("font-config.json")
        var config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        var descriptors = try XCTUnwrap(config["fonts"] as? [String: [String: Any]])
        var primary = try XCTUnwrap(descriptors["Primary"])
        var sources = try XCTUnwrap(primary["sources"] as? [[String: Any]])
        sources.append(["file": "Italic.ttf", "faceIndex": 0, "weight": 400])
        primary["sources"] = sources
        descriptors["Primary"] = primary
        config["fonts"] = descriptors
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)
        return (bundle, fonts)
    }

    private func fallbackFixtureBundle(_ kind: String) throws -> (Bundle, URL) {
        let (bundle, fonts) = try fixtureBundle(weightClass: 400)
        let url = fonts.appendingPathComponent("Font.ttf")
        var data = try Data(contentsOf: url)
        func uint16(_ offset: Int) -> Int { Int(data[offset]) << 8 | Int(data[offset + 1]) }
        func uint32(_ offset: Int) -> Int { uint16(offset) << 16 | uint16(offset + 2) }
        let records = (0..<uint16(4)).map { 12 + $0 * 16 }
        let record = try XCTUnwrap(records.first { String(bytes: data[$0..<$0 + 4], encoding: .ascii) == "fvar" })
        if kind == "static" {
            data[record + 3] = 0x5f
        } else {
            let table = uint32(record + 8)
            data[table + 12] = 0
            data[table + 13] = 0
            if kind == "bounded" {
                let maximum = table + uint16(table + 4) + 12
                let value = UInt32(450 * 65536)
                for index in 0..<4 { data[maximum + index] = UInt8(truncatingIfNeeded: value >> (24 - index * 8)) }
            }
        }
        try data.write(to: url)
        return (bundle, fonts)
    }

    private func fixtureBundle(weightClass: UInt16) throws -> (Bundle, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle", isDirectory: true)
        let fonts = directory.appendingPathComponent("Contents/Resources/Fonts", isDirectory: true)
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>font-scope.\(UUID().uuidString)</string>
        <key>CFBundlePackageType</key><string>BNDL</string></dict></plist>
        """.utf8).write(to: directory.appendingPathComponent("Contents/Info.plist"))
        #if !canImport(Darwin)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("Fonts"), withDestinationURL: fonts)
        #endif
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        try Data("""
        {"version":2,"fonts":{
          "Primary":{"sources":[{"file":"Font.ttf","faceIndex":0,"weightAxis":{"tag":"wght","minimum":100,"maximum":900}}],"syntheticWeight":false},
          "Terminal":{"sources":[{"file":"Font.ttf","faceIndex":0,"weight":400}],"syntheticWeight":false}},
         "defaultLocale":"en","designs":{"default":{"systemFont":"Primary","locales":{"en":["Primary"]}}},"missingGlyphFont":"Terminal"}
        """.utf8).write(to: fonts.appendingPathComponent("font-config.json"))
        let source = BundledFontCatalog.shared.resources.resourceDirectory.appendingPathComponent("Roboto/Roboto-VariableFont_wdth,wght.ttf")
        var data = try Data(contentsOf: source)
        func uint16(_ offset: Int) -> Int { Int(data[offset]) << 8 | Int(data[offset + 1]) }
        func uint32(_ offset: Int) -> Int { uint16(offset) << 16 | uint16(offset + 2) }
        let records = (0..<uint16(4)).map { 12 + $0 * 16 }
        let record = try XCTUnwrap(records.first { String(bytes: data[$0..<$0 + 4], encoding: .ascii) == "OS/2" })
        let offset = uint32(record + 8) + 4
        // Distinct resource revisions keep their names while exposing different source traits.
        data[offset] = UInt8(weightClass >> 8)
        data[offset + 1] = UInt8(weightClass & 255)
        try data.write(to: fonts.appendingPathComponent("Font.ttf"))
        return (try XCTUnwrap(Bundle(url: directory)), fonts)
    }
}
