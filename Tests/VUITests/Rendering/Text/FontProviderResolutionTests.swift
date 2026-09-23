import Dispatch
import Foundation
import Synchronization
import XCTest
import func VVD.makeGraphicsDeviceContext
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
    // ASSERTIONS fontMetadataWeightPrecision27Observed
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
        XCTAssertEqual(candidate.traits.weight, 0.0800000011920929)
        XCTAssertEqual(descriptor.pointSize, 23)
    }

    // ASSERTIONS fontMetadataWeightPrecision27Observed
    func testRegisteredMetadataWeightRetainsDoublePrecisionThroughFontResolution() throws {
        let controls: [(UInt16, CGFloat)] = [
            (0, -0.8999999761581421), (1, -0.6000000238418579), (4, 0), (10, 1),
            (11, -0.8669999814033509), (99, -0.6030000233650208),
            (100, -0.6000000238418579), (199, -0.4020000061392784),
            (200, -0.4000000059604645), (299, -0.23170000419020653),
            (300, -0.23000000417232513), (399, -0.0023000000417232533), (400, 0),
            (401, 0.0020000000298023225), (440, 0.0800000011920929),
            (450, 0.10000000149011612), (499, 0.1980000029504299),
            (500, 0.20000000298023224), (530, 0.23000000566244125),
            (599, 0.299000011831522), (600, 0.30000001192092896),
            (699, 0.39900000602006913), (700, 0.4000000059604645),
            (780, 0.5600000202655793), (899, 0.7980000120401383),
            (900, 0.800000011920929), (999, 0.9980000001192093), (1000, 1)
        ]
        for (weightClass, expected) in controls {
            let (bundle, _) = try metadataWeightFixtureBundle(weightClass: weightClass, kind: "static")
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            let font = Font.custom("Roboto-Regular", fixedSize: 23)
            let descriptor = font.resolveDescriptor(in: environment.fontResolutionContext)
            let provider = try XCTUnwrap(descriptor.typefaceProvider(in: environment) as? BundledFontProvider)
            XCTAssertEqual(descriptor.resolvedWeight, expected, "class \(weightClass)")
            XCTAssertEqual(provider.weight.value, expected, "class \(weightClass)")
            XCTAssertEqual(font.resolveTraits(in: environment.fontResolutionContext).weight, expected,
                           "class \(weightClass)")
            XCTAssertEqual(provider.resource.url.lastPathComponent, "Font.ttf")
            XCTAssertEqual(descriptor.pointSize, 23)
        }
    }

    // ASSERTIONS fontMetadataWeightPrecision27Observed
    func testRegisteredVariationWeightKeepsItsProducerThroughSelectionAndCopies() throws {
        let tag: UInt32 = 0x7767_6874
        for kind in ["default", "instance"] {
            for (weightClass, registered, active, changed): (UInt16, CGFloat, CGFloat, CGFloat) in [
                (440, 0.0800000011920929, 0.08000000566244125, 0.0820000022649765),
                (699, 0.39900000602006913, 0.39900001883506775, 0.4000000059604645)
            ] {
                let (bundle, _) = try metadataWeightFixtureBundle(weightClass: weightClass, kind: kind)
                var environment = EnvironmentValues()
                environment.resourceBundle = bundle
                let catalog = try XCTUnwrap(BundledFontCatalog.catalog(in: bundle))
                let name = kind == "instance" ? "Roboto-Thin" : "Roboto-Regular"
                let candidate = try XCTUnwrap(catalog.resources.resolver.named(name))
                let descriptor = Font.custom(name, fixedSize: 23)
                    .resolveDescriptor(in: environment.fontResolutionContext)
                XCTAssertEqual(candidate.traits.weight, registered)
                XCTAssertEqual(descriptor.resolvedWeight, registered)
                XCTAssertEqual(candidate.applying(variation: [:]).traits.weight, registered)
                XCTAssertEqual(candidate.applying(variation: [tag: CGFloat(weightClass)]).traits.weight, registered)
                let changedCandidate = candidate.applying(variation: [tag: CGFloat(weightClass + 1)])
                XCTAssertEqual(changedCandidate.traits.weight, changed)
                XCTAssertEqual(changedCandidate.variations.first { $0.tag == tag }?.value, CGFloat(weightClass + 1))
                XCTAssertEqual(FontWeightScale.logicalWeight(forClass: CGFloat(weightClass)), active)
                let resource = FontResource(descriptor: descriptor, in: environment.fontResolutionContext)
                XCTAssertEqual(try XCTUnwrap(resource.fontWithSize(31.375)).selectedWeight, registered)
                XCTAssertEqual(descriptor.adding(features: [TypefaceShapingFeature(tag: 0x746e_756d)]).resolvedWeight, registered)
            }
        }
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

    // ASSERTIONS fontGradeRetention27Observed
    func testRegisteredGradeDefaultsSurviveResourceAndModifierCopies() throws {
        let (bundle, _) = try scoringFixtureBundle("grade")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        let appContext = StyleTestAppContext()
        let grade: UInt32 = 0x4752_4144
        for name in ["Roboto-Regular", "Roboto-CandidateRegular"] {
            let descriptor = FontDescriptor(source: .named(name, bundle), pointSize: 23,
                                            variation: [grade: 100])
            let original = FontResource(descriptor: descriptor, in: context)
            for resource in [original, try XCTUnwrap(original.fontWithSize(31.375))] {
                let face = try XCTUnwrap(resource.provider.makeTypeface(appContext, dpi: 72))
                XCTAssertEqual(face.selectedFont?.variation, [:])
                XCTAssertEqual(face.selectedFont?.variationExtras, [grade: 100])
                XCTAssertEqual(resource.descriptor().variation, [grade: 100])
                let wrapped = Font(provider: FontBox(Font.PlatformFontProvider(font: resource)))
                for font in [wrapped.weight(.heavy), wrapped.weight(.heavy).italic(),
                             wrapped.monospacedDigit().weight(.heavy)] {
                    let resolved = font.resolve(in: context)
                    let selected = try XCTUnwrap(resolved.resource.provider.makeTypeface(appContext, dpi: 72)?.selectedFont)
                    XCTAssertEqual(selected.variation, [0x7767_6874: 800])
                    XCTAssertEqual(selected.variationExtras, [grade: 100])
                    XCTAssertEqual(selected.pointSize, resource.pointSize)
                }
            }
        }
    }

    // ASSERTIONS fontGradeRetention27Observed
    func testGeneratedGradeSeparatesNameRequestsFromResourceCopies() throws {
        let (bundle, _) = try scoringFixtureBundle("grade")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        let appContext = StyleTestAppContext()
        let grade: UInt32 = 0x4752_4144
        let custom = Font.custom("Roboto-Regular_wght_GRAD550000", fixedSize: 23)
        let original = custom.resolve(in: context).resource
        let originalFace = try XCTUnwrap(original.provider.makeTypeface(appContext, dpi: 72)?.selectedFont)
        XCTAssertEqual(originalFace.variation, [grade: 85])
        XCTAssertNil(originalFace.variationExtras)
        let namedItalic = try XCTUnwrap(custom.italic().resolve(in: context).resource.provider
            .makeTypeface(appContext, dpi: 72)?.selectedFont)
        XCTAssertEqual(namedItalic.variation, [grade: 75])
        XCTAssertNil(namedItalic.variationExtras)
        let supplied = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
        let suppliedItalic = try XCTUnwrap(supplied.italic().resolve(in: context).resource.provider
            .makeTypeface(appContext, dpi: 72)?.selectedFont)
        XCTAssertEqual(suppliedItalic.variation, [grade: 85])
        XCTAssertEqual(suppliedItalic.variationExtras, [grade: 85])
        let resized = try XCTUnwrap(original.fontWithSize(31.375))
        let resizedFace = try XCTUnwrap(resized.provider.makeTypeface(appContext, dpi: 72)?.selectedFont)
        XCTAssertEqual(resizedFace.variation, [grade: 85])
        XCTAssertEqual(resizedFace.variationExtras, [grade: 85])
        XCTAssertEqual(resizedFace.pointSize, 31.375)
        XCTAssertNil(original.provider.makeTypeface(appContext, dpi: 72)?.selectedFont?.variationExtras)
    }

    // ASSERTIONS fontGradeRetention27Observed fontSymbolicCandidateScoring27Observed
    func testSymbolicGradeScoringUsesConvertedCoordinates() throws {
        let (bundle, _) = try scoringFixtureBundle("grade-sparse")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        let grade: UInt32 = 0x4752_4144
        for (value, suffix) in [(CGFloat(70), "460000"), (75, "4B0000"), (85, "550000")] {
            let descriptor = FontDescriptor(source: .named("Roboto-Regular", bundle), pointSize: 23,
                                            variation: [grade: value])
            let resource = FontResource(descriptor: descriptor, in: context)
            let supplied = Font(provider: FontBox(Font.PlatformFontProvider(font: resource)))
            let copied = supplied.weight(.heavy).italic().resolve(in: context).resource
            let face = try XCTUnwrap(copied.provider.makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
            XCTAssertEqual(face.descriptor.postScriptName, "Roboto-Italic_wght_GRAD" + suffix)
            XCTAssertEqual(face.variation, [grade: max(75, value)])
            XCTAssertEqual(face.variationExtras, [grade: value])
        }
    }

    // ASSERTIONS fontGradeRetention27Observed
    func testRegisteredGradeRequestsRemainSeparateFromSelectedCoordinates() throws {
        let appContext = StyleTestAppContext()
        let grade: UInt32 = 0x4752_4144, weight: UInt32 = 0x7767_6874
        for value: CGFloat in [70, 75, 85, 90, 99.99999, 100, 110] {
            // Each construction starts with an independent resource identity.
            // Equivalent requests otherwise reuse the first cached originals.
            let (bundle, _) = try scoringFixtureBundle("grade")
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            environment.defaultFontRenderingMode = .vector()
            let context = environment.fontResolutionContext
            let descriptor = FontDescriptor(source: .named("Roboto-Regular", bundle), pointSize: 23,
                                            variation: [grade: value])
            let original = FontResource(descriptor: descriptor, in: context)
            let supplied = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
            let expectedGrade: CGFloat? = value >= 100 ? nil : max(75, (value * 10000).rounded(.towardZero) / 10000)
            for (font, expectedWeight) in [(supplied, CGFloat(400)), (supplied.italic(), 400),
                                           (supplied.weight(.heavy), 800),
                                           (supplied.weight(.heavy).italic(), 800),
                                           (supplied.monospacedDigit(), 400)] {
                let resolved = font.resolve(in: context).resource
                let selected = try XCTUnwrap(resolved.provider.makeTypeface(appContext, dpi: 72)?.selectedFont)
                XCTAssertEqual(selected.variation[grade], expectedGrade)
                XCTAssertEqual(selected.variation[weight] ?? 400, expectedWeight)
                XCTAssertEqual(selected.variationExtras, [grade: value])
            }
        }
        for request: [UInt32: CGFloat] in [[:], [weight: 400], [grade: 85, weight: 400], [grade: 85, weight: 530]] {
            let (bundle, _) = try scoringFixtureBundle("grade")
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            environment.defaultFontRenderingMode = .vector()
            let context = environment.fontResolutionContext
            let descriptor = FontDescriptor(source: .named("Roboto-Regular", bundle), pointSize: 23,
                                            variation: request)
            let resource = FontResource(descriptor: descriptor, in: context)
            XCTAssertEqual(resource.descriptor().variation, request)
            let supplied = Font(provider: FontBox(Font.PlatformFontProvider(font: resource)))
            for font in [supplied, supplied.italic(), supplied.weight(.heavy), supplied.monospacedDigit()] {
                let selected = try XCTUnwrap(font.resolve(in: context).resource.provider
                    .makeTypeface(appContext, dpi: 72)?.selectedFont)
                XCTAssertEqual(selected.variationExtras, request)
                if let requested = request[weight] { XCTAssertEqual(selected.variation[weight] ?? 400, requested) }
                if let requested = request[grade] { XCTAssertEqual(selected.variation[grade], requested) }
            }
        }
    }

    // ASSERTIONS fontGradeRetention27Observed fontSymbolicVariationRetention27Observed
    func testGradeFallbackCopiesTheComparisonDictionaryBeforeReentry() throws {
        let (bundle, _) = try scoringFixtureBundle("grade-upright")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        let grade: UInt32 = 0x4752_4144
        for (value, expected, name) in [
            (CGFloat(70), CGFloat(75), "Roboto-Regular_wght_GRAD460000"),
            (99.99999, 99.9999, "Roboto-Regular")
        ] {
            let descriptor = FontDescriptor(source: .named("Roboto-Regular", bundle), pointSize: 23,
                                            variation: [grade: value])
            let resource = FontResource(descriptor: descriptor, in: context)
            let supplied = Font(provider: FontBox(Font.PlatformFontProvider(font: resource)))
            let copied = supplied.italic().resolve(in: context).resource
            let selected = try XCTUnwrap(copied.provider.makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
            XCTAssertEqual(selected.descriptor.postScriptName, name)
            XCTAssertEqual(selected.variation, [grade: expected])
            XCTAssertEqual(selected.variationExtras, [grade: expected])
            XCTAssertEqual(selected.pointSize, 23)
            XCTAssertEqual(resource.descriptor().variation, [grade: value])
        }
    }

    // ASSERTIONS fontRegisteredCopyHistory27Observed
    func testRegisteredVariationCopySelectsSizeFromItsRetainedConstruction() throws {
        let (bundle, _) = try scoringFixtureBundle("grade-upright")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        let appContext = StyleTestAppContext()
        let grade: UInt32 = 0x4752_4144
        for (request, size): (CGFloat, CGFloat) in [(75, 12), (85, 12), (90, 12), (70, 23), (100, 23), (99.99999, 23)] {
            let original = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                pointSize: 23, variation: [grade: request]), in: context)
            let supplied = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
            let copied = supplied.italic().platformFont(in: context)
            XCTAssertEqual(copied.pointSize, size, "request \(request)")
            let face = try XCTUnwrap(copied.provider.makeTypeface(appContext, dpi: 72))
            XCTAssertEqual(face.selectedFont?.pointSize, size)
            XCTAssertEqual(try XCTUnwrap(face as? any VVDFontBackedTypeface).font.pointSize, size)
            XCTAssertEqual(original.pointSize, 23)
            let twice = supplied.italic().italic().platformFont(in: context)
            XCTAssertEqual(twice.pointSize, request == 99.99999 ? 12 : size)
        }
        let generated = Font.custom("Roboto-Regular_wght_GRAD550000", fixedSize: 23).platformFont(in: context)
        let supplied = Font(provider: FontBox(Font.PlatformFontProvider(font: generated)))
        XCTAssertEqual(supplied.italic().platformFont(in: context).pointSize, 23)
        XCTAssertEqual(supplied.weight(.regular).italic().platformFont(in: context).pointSize, 12)
        XCTAssertEqual(supplied.leading(.tight).italic().platformFont(in: context).pointSize, 12)
        XCTAssertEqual(supplied.italic().leading(.tight).platformFont(in: context).pointSize, 23)
    }

    // ASSERTIONS fontRegisteredCopyHistory27Observed
    func testRegisteredSymbolicCopyDropsOnlyTheUnmergedOriginalAttributes() throws {
        let (bundle, _) = try scoringFixtureBundle("grade-upright")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        let context = environment.fontResolutionContext
        let digits = TypefaceShapingFeature(tag: 0x746e_756d)
        for request: CGFloat in [85, 70, 99.99999, 100] {
            let original = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                pointSize: 23, shapingFeatures: [digits], language: "en", variation: [0x4752_4144: request]), in: context)
            let supplied = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
            let italic = supplied.italic().platformFont(in: context)
            XCTAssertEqual(italic.shapingFeatures, request == 85 ? [] : [digits])
            XCTAssertEqual(italic.language, request == 85 ? nil : "en")
            XCTAssertEqual(italic.pointSize, request == 85 ? 12 : 23)
            let after = supplied.italic().monospacedDigit().platformFont(in: context)
            XCTAssertFalse(after.shapingFeatures.isEmpty)
            let before = supplied.monospacedDigit().italic().platformFont(in: context)
            XCTAssertEqual(before.shapingFeatures.isEmpty, request == 85)
            XCTAssertEqual(original.shapingFeatures, [digits])
            XCTAssertEqual(original.language, "en")
        }
    }

    // ASSERTIONS fontRegisteredCopyHistory27Observed
    func testRegisteredAttributeCopyHistoryIsSeparateFromFeatureCopies() throws {
        let (bundle, _) = try scoringFixtureBundle("grade-upright")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        let context = environment.fontResolutionContext
        let original = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
            pointSize: 23, variation: [0x4752_4144: 85]), in: context)
        let descriptor = original.descriptor()
        let features = descriptor.adding(features: [TypefaceShapingFeature(tag: 0x746e_756d)])
        XCTAssertEqual(features.symbolicTrait(1, active: true).pointSize, 12)
        let cleared = descriptor.clearFeatures().symbolicTrait(1, active: true)
        XCTAssertEqual(cleared.pointSize, 23)
        XCTAssertEqual(cleared.symbolicTrait(1, active: true).pointSize, 23)
        XCTAssertTrue(cleared.shapingFeatures.isEmpty)
        let language = descriptor.withTypesetting(language: "en").symbolicTrait(1, active: true)
        XCTAssertEqual(language.pointSize, 23)
        XCTAssertNil(language.language)
        let supplied = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
        var redacted = context
        redacted.shouldRedactContent = true
        XCTAssertEqual(supplied.italic().platformFont(in: redacted).pointSize, 23)
        let near = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
            pointSize: 23, variation: [0x4752_4144: 99.99999]), in: context)
        let pending = near.descriptor().symbolicTrait(1, active: true)
        XCTAssertEqual(pending.clearFeatures().symbolicTrait(1, active: true).pointSize, 12)
        let realized = FontResource(descriptor: near.descriptor().symbolicTrait(1, active: true), in: context)
        XCTAssertEqual(realized.descriptor().clearFeatures().symbolicTrait(1, active: true).pointSize, 23)
    }

    // ASSERTIONS fontRegisteredCopyHistory27Observed
    func testRegisteredCopyOptionsSurviveResourceSizingAndLazySelection() throws {
        let (bundle, _) = try scoringFixtureBundle("grade-upright")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        let source = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
            pointSize: 23, variation: [0x4752_4144: 85]), in: context)
        let copied = FontResource(descriptor: source.descriptor().clearFeatures(), in: context)
        for (resource, expectedSize) in [(source, CGFloat(12)), (copied, 31.375)] {
            let resized = try XCTUnwrap(resource.fontWithSize(31.375))
            let selected = resized.descriptor().symbolicTrait(1, active: true)
            XCTAssertEqual(selected.pointSize, expectedSize)
            let face = try XCTUnwrap(selected.typefaceProvider(in: environment)
                .makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
            XCTAssertEqual(face.pointSize, expectedSize)
            XCTAssertEqual(face.variation, [0x4752_4144: 85])
            XCTAssertEqual(source.pointSize, 23)
        }
        let descriptor = source.descriptor()
        XCTAssertTrue(descriptor.withTypesetting() === descriptor)
        let ratio = descriptor.withTypesetting(lineHeightRatio: 1.2).symbolicTrait(1, active: true)
        XCTAssertEqual(ratio.pointSize, 23)
        XCTAssertEqual(ratio.languageAwareLineHeightRatio, 1.2)
    }

    // ASSERTIONS fontRegisteredCacheEquality27Observed
    func testRegisteredFontCacheReusesNearVariationInBothRequestOrders() throws {
        for reverse in [false, true] {
            let (bundle, _) = try scoringFixtureBundle("grade-upright")
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            let context = environment.fontResolutionContext
            let first = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                pointSize: 23, variation: [0x4752_4144: 99.99999]), in: context)
            let second = FontResource(descriptor: first.descriptor().symbolicTrait(1, active: true), in: context)
            let fonts = (reverse ? [second, first] : [first, second]).map {
                Font(provider: FontBox(Font.PlatformFontProvider(font: $0)))
            }
            XCTAssertEqual(fonts[0], fonts[1])
            XCTAssertEqual(fonts[0].hashValue, fonts[1].hashValue)
            XCTAssertFalse(first.provider.isEqual(to: second.provider))
            let selected = fonts.map { $0.italic().platformFont(in: context) }
            XCTAssertTrue(selected[0] === selected[1])
            XCTAssertEqual(selected.map(\.pointSize), reverse ? [12, 12] : [23, 23])
            XCTAssertEqual(first.pointSize, 23)
            if !reverse {
                let wrapped = Font(provider: FontBox(Font.PlatformFontProvider(font: selected[0])))
                XCTAssertTrue(wrapped.italic().platformFont(in: context) === selected[0])
            }
        }
    }

    // ASSERTIONS fontRegisteredCacheEquality27Observed
    func testRegisteredFontIdentityPreservesSelectedVariationAndDescriptorName() throws {
        let (bundle, _) = try scoringFixtureBundle("grade-upright")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        let context = environment.fontResolutionContext
        func resource(_ value: CGFloat) -> FontResource {
            FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                pointSize: 23, variation: [0x4752_4144: value]), in: context)
        }
        for (first, second, equal, hashEqual): (CGFloat, CGFloat, Bool, Bool) in [
            (99.99999, 99.9999, true, true), (85, 85.00000001, true, true),
            (85, 85.0002, false, false), (70, 71, false, false), (70, 75, false, false),
            (100, 110, true, true), (100, 99.99999, false, true)
        ] {
            let a = resource(first), b = resource(second)
            XCTAssertEqual(a == b, equal, "\(first), \(second)")
            XCTAssertEqual(a.hashValue == b.hashValue, hashEqual, "\(first), \(second)")
        }
        for value: CGFloat in [75, 85, 99.99999, 100] {
            let original = resource(value)
            let copied = FontResource(descriptor: original.descriptor().clearFeatures(), in: context)
            XCTAssertEqual(original, copied)
            XCTAssertEqual(original.hashValue, copied.hashValue)
            let ratio = FontResource(descriptor: original.descriptor().withTypesetting(lineHeightRatio: 1.2), in: context)
            XCTAssertEqual(original == ratio, value != 75)
            XCTAssertEqual(original.hashValue, ratio.hashValue)
        }
    }

    // ASSERTIONS fontRegisteredCacheEquality27Observed
    func testRegisteredFontCacheRetainsOriginalExtrasHashPartitions() throws {
        for reverse in [false, true] {
            let (bundle, _) = try scoringFixtureBundle("grade-upright")
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            let context = environment.fontResolutionContext
            for (variation, name): ([UInt32: CGFloat], String) in [
                ([0x4752_4144: 100], "Roboto-Regular"), ([:], "Roboto-Regular"),
                ([0x4752_4144: 85], "Roboto-Regular_wght_GRAD550000")
            ] {
                let original = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                    pointSize: 23, variation: variation), in: context)
                let named = FontResource(descriptor: FontDescriptor(source: .named(name, bundle), pointSize: 23), in: context)
                let fonts = (reverse ? [named, original] : [original, named]).map {
                    Font(provider: FontBox(Font.PlatformFontProvider(font: $0)))
                }
                // Lookup preserves extras presence independently of value comparison.
                XCTAssertEqual(fonts[0], fonts[1])
                XCTAssertNotEqual(fonts[0].hashValue, fonts[1].hashValue)
                let selected = fonts.map { $0.italic().platformFont(in: context) }
                XCTAssertFalse(selected[0] === selected[1])
                let expected: [CGFloat] = variation[0x4752_4144] == 85 ? [12, 23] : [23, 23]
                XCTAssertEqual(selected.map(\.pointSize), reverse ? expected.reversed() : expected)
            }
        }
    }

    // ASSERTIONS fontRegisteredCacheEquality27Observed
    func testRegisteredFontCacheKeepsAttributeHistoryOutsideValueComparison() throws {
        for value: CGFloat in [75, 85] {
            for ratio in [false, true] {
                for reverse in [false, true] {
                    let (bundle, _) = try scoringFixtureBundle("grade-upright")
                    var environment = EnvironmentValues()
                    environment.resourceBundle = bundle
                    let context = environment.fontResolutionContext
                    let original = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                        pointSize: 23, variation: [0x4752_4144: value]), in: context)
                    let descriptor = ratio ? original.descriptor().withTypesetting(lineHeightRatio: 1.2)
                        : original.descriptor().clearFeatures()
                    let copied = FontResource(descriptor: descriptor, in: context)
                    let resources = reverse ? [copied, original] : [original, copied]
                    let results = resources.map {
                        Font(provider: FontBox(Font.PlatformFontProvider(font: $0))).italic().platformFont(in: context)
                    }
                    let shares = value != 75 || !ratio
                    XCTAssertEqual(results[0] === results[1], shares)
                    let sizes: [CGFloat] = shares ? (reverse ? [23, 23] : [12, 12])
                        : (reverse ? [23, 12] : [12, 23])
                    XCTAssertEqual(results.map(\.pointSize), sizes)
                    XCTAssertEqual(original.pointSize, 23)
                }
            }
        }
    }

    // ASSERTIONS fontRegisteredExtrasCache27Observed
    func testRegisteredFontFeaturesCompareSelectedSettingsBeforeCacheLookup() throws {
        func f(_ tag: String, _ value: UInt32) -> TypefaceShapingFeature {
            TypefaceShapingFeature(tag: tag, value: value)!
        }
        let pairs: [([TypefaceShapingFeature], [TypefaceShapingFeature], Bool)] = [
            ([], [f("liga", 1)], true), ([], [f("ss01", 0)], true),
            ([f("tnum", 1)], [f("tnum", 2)], true),
            ([f("dnom", 1)], [f("dnom", 2)], false),
            ([f("tnum", 1), f("ss01", 1)], [f("ss01", 1), f("tnum", 1)], true),
            ([f("ss01", 1)], [f("ss01", 1), f("ss01", 0), f("ss01", 1)], true),
            ([], [f("liga", 0), f("liga", 1)], true),
            ([f("tnum", 1)], [f("tnum", 1), f("pnum", 0)], true)
        ]
        for (first, second, equal) in pairs {
            let (bundle, _) = try scoringFixtureBundle("grade-upright")
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            let context = environment.fontResolutionContext
            let fonts = [first, second].map {
                Font(provider: FontBox(Font.PlatformFontProvider(font: FontResource(
                    descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                        pointSize: 23, shapingFeatures: $0), in: context))))
            }
            XCTAssertEqual(fonts[0] == fonts[1], equal, "\(first), \(second)")
            XCTAssertEqual(fonts[0].hashValue, fonts[1].hashValue)
            let results = fonts.map { $0.italic().platformFont(in: context) }
            XCTAssertEqual(results[0] === results[1], equal)
        }
    }

    // ASSERTIONS fontRegisteredExtrasCache27Observed
    func testRegisteredFontPublishesAndCopiesItsSelectedFeatureRequests() throws {
        let (bundle, _) = try scoringFixtureBundle("grade-upright")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        let app = StyleTestAppContext()
        func selectedRequests(_ resource: FontResource) throws -> [TypefaceShapingFeature] {
            let base = try XCTUnwrap(resource.provider.makeTypeface(app, dpi: 72))
            let face = ShapingFeatureTypeface(base, features: resource.shapingFeatures)
            return try XCTUnwrap(face.selectedFont).features.map {
                TypefaceShapingFeature(tag: $0.tag, value: $0.value)
            }
        }
        let digits = TypefaceShapingFeature(tag: "tnum", value: 1)!
        let alternate = TypefaceShapingFeature(tag: "ss01", value: 1)!
        let original = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
            pointSize: 23, shapingFeatures: [digits, alternate]), in: context)
        XCTAssertEqual(try selectedRequests(original), [alternate, digits])
        XCTAssertEqual(original.descriptor().shapingFeatures, [alternate, digits])
        let font = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
        let italic = font.italic().platformFont(in: context)
        XCTAssertEqual(try selectedRequests(italic), [digits, alternate])
        XCTAssertEqual(italic.descriptor().shapingFeatures, [digits, alternate])
        for size: CGFloat in [0, 31.375] {
            let copy = try XCTUnwrap(original.fontWithSize(size))
            XCTAssertFalse(copy === original)
            XCTAssertEqual(copy.pointSize, size == 0 ? 23 : size)
            XCTAssertEqual(try selectedRequests(copy), [digits, alternate])
            XCTAssertEqual(copy.descriptor().shapingFeatures, [digits, alternate])
        }
        XCTAssertTrue(original.fontWithSize(23) === original)
        XCTAssertEqual(try selectedRequests(original), [alternate, digits])
        let defaultFeature = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
            pointSize: 23, shapingFeatures: [TypefaceShapingFeature(tag: "liga", value: 1)!]), in: context)
        XCTAssertTrue(try selectedRequests(defaultFeature).isEmpty)
        XCTAssertTrue(defaultFeature.descriptor().shapingFeatures.isEmpty)
    }

    // ASSERTIONS fontRegisteredExtrasCache27Observed
    func testRegisteredFeatureAliasesReuseNearVariationWithoutErasingLanguage() throws {
        for reverse in [false, true] {
            let (bundle, _) = try scoringFixtureBundle("grade-upright")
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            let context = environment.fontResolutionContext
            let originals = [(CGFloat(99.99999), UInt32(1)), (99.9999, 2)].map { value, feature in
                FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                    pointSize: 23, shapingFeatures: [TypefaceShapingFeature(tag: "tnum", value: feature)!],
                    variation: [0x4752_4144: value]), in: context)
            }
            let results = (reverse ? originals.reversed() : originals).map {
                Font(provider: FontBox(Font.PlatformFontProvider(font: $0))).italic().platformFont(in: context)
            }
            XCTAssertTrue(results[0] === results[1])
            XCTAssertEqual(results.map(\.pointSize), reverse ? [12, 12] : [23, 23])
            for (first, second, equal, hashEqual): (String?, String?, Bool, Bool) in [
                ("en", "en", true, true), ("en", "en-US", false, true),
                ("", nil, false, false), ("zh", "zh-CN", false, true)
            ] {
                let languages = [first, second].map {
                    FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                        pointSize: 23, language: $0), in: context)
                }
                XCTAssertEqual(languages[0] == languages[1], equal)
                XCTAssertEqual(languages[0].hashValue == languages[1].hashValue, hashEqual)
            }
        }
    }

    // ASSERTIONS fontOpticalRealization27Observed
    func testRegisteredOpticalSizeFollowsPointSizeAfterSymbolicSelection() throws {
        let (bundle, _) = try scoringFixtureBundle("optical-close")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = StyleTestAppContext()
        let optical: UInt32 = 0x6f70_737a
        for size: CGFloat in [0.5, 23, 23.375, 99.99999, 100, 300] {
            for italic in [false, true] {
                let font = Font.custom("Roboto-Regular", fixedSize: size)
                let descriptor = (italic ? font.italic() : font).resolveDescriptor(in: environment.fontResolutionContext)
                let resource = FontResource(descriptor: descriptor, in: environment.fontResolutionContext)
                let candidate = try XCTUnwrap(descriptor.resolvedConstruction.candidate)
                XCTAssertEqual(candidate.variations.first { $0.tag == optical }?.value, 100)
                let expectedName = italic ? "P450bo-Italic" : "Roboto-Regular"
                let value = min(max((size * 10000).rounded(.towardZero) / 10000, 1), 200)
                for dpi: UInt32 in [72, 216] {
                    let face = try XCTUnwrap(resource.provider.makeTypeface(context, dpi: dpi) as? VectorTypeface)
                    let selected = try XCTUnwrap(face.selectedFont)
                    XCTAssertEqual(selected.descriptor.postScriptName, expectedName)
                    XCTAssertEqual(selected.variation, value == 100 ? [:] : [optical: value])
                    XCTAssertNil(selected.variationExtras)
                    XCTAssertEqual(selected.pointSize, size)
                    let physical = size == 99.99999 ? 100 : min(max(size, 1), 200)
                    XCTAssertEqual(face.font.variationCoordinates[optical], physical)
                    XCTAssertEqual(face.outlineSource.font.variationCoordinates[optical], physical)
                }
                let resized = try XCTUnwrap(resource.fontWithSize(31.375))
                let copied = try XCTUnwrap(resized.provider.makeTypeface(context, dpi: 144)?.selectedFont)
                XCTAssertEqual(copied.variation, [optical: 31.375])
                XCTAssertEqual(copied.descriptor.postScriptName, expectedName)
                XCTAssertNil(copied.variationExtras)
            }
        }
    }

    // ASSERTIONS fontOpticalRealization27Observed
    func testExplicitOpticalDefaultsRemainRequestsThroughSizeAndFeatureCopies() throws {
        let (bundle, _) = try scoringFixtureBundle("optical-close")
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let context = StyleTestAppContext()
        let optical: UInt32 = 0x6f70_737a
        for value: CGFloat in [25, 100, 300, 0, 23.00000001] {
            let resource = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                pointSize: 23, variation: [optical: value]), in: environment.fontResolutionContext)
            let wrapped = Font(provider: FontBox(Font.PlatformFontProvider(font: resource)))
            let feature = wrapped.monospacedDigit().platformFont(in: environment.fontResolutionContext)
            for copy in [resource, feature, try XCTUnwrap(resource.fontWithSize(31.375))] {
                let selected = try XCTUnwrap(copy.provider.makeTypeface(context, dpi: 144)?.selectedFont)
                let bounded = min(max((value * 10000).rounded(.towardZero) / 10000, 1), 200)
                XCTAssertEqual(selected.variation, value == 100 ? [:] : [optical: bounded])
                XCTAssertEqual(selected.variationExtras, [optical: value])
                XCTAssertEqual(copy.descriptor().variation, [optical: value])
            }
        }
        let automatic = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
            pointSize: 100), in: environment.fontResolutionContext)
        let explicit = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
            pointSize: 100, variation: [optical: 100]), in: environment.fontResolutionContext)
        let a = try XCTUnwrap(automatic.provider.makeTypeface(context, dpi: 72)?.selectedFont)
        let b = try XCTUnwrap(explicit.provider.makeTypeface(context, dpi: 72)?.selectedFont)
        XCTAssertEqual(a.variation, b.variation)
        XCTAssertEqual(a.descriptor.postScriptName, b.descriptor.postScriptName)
        XCTAssertFalse(a.isEqual(to: b))
    }

    // ASSERTIONS fontOpticalRealization27Observed
    func testRegisteredOpticalEligibilityUsesTablesAndTheWholeNamedInstanceSet() throws {
        let optical: UInt32 = 0x6f70_737a
        for (family, names, automatic) in [
            ("Optica", ["Regular", "Thin", "CondensedRegular"], false),
            ("SameOp", ["Regular", "Thin"], true),
            ("NoStat", ["Regular"], false)
        ] {
            let (bundle, _) = try opticalFixtureBundle(family)
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            environment.defaultFontRenderingMode = .vector()
            for name in names {
                let resource = Font.custom(family + "-" + name, fixedSize: 23)
                    .platformFont(in: environment.fontResolutionContext)
                for copy in [resource, try XCTUnwrap(resource.fontWithSize(31.375))] {
                    let selected = try XCTUnwrap(copy.provider.makeTypeface(StyleTestAppContext(), dpi: 72)?.selectedFont)
                    var expected: [UInt32: CGFloat] = automatic ? [optical: copy.pointSize] : [:]
                    if name == "Thin" { expected[0x7767_6874] = 100 }
                    if name == "CondensedRegular" { expected[optical] = 75 }
                    XCTAssertEqual(selected.variation, expected, family + "-" + name)
                    XCTAssertEqual(selected.descriptor.postScriptName, family + "-" + name)
                }
            }
        }
    }

    // ASSERTIONS fontOpticalRealization27Observed
    func testGeneratedOpticalNamesAndSuppliedCopiesKeepAutomaticConstruction() throws {
        let (bundle, _) = try scoringFixtureBundle("optical-close")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let context = StyleTestAppContext()
        let optical: UInt32 = 0x6f70_737a
        let resource = Font.custom("Roboto-Regular_wght_opsz460000", fixedSize: 23)
            .platformFont(in: environment.fontResolutionContext)
        let wrapped = Font(provider: FontBox(Font.PlatformFontProvider(font: resource)))
        let feature = wrapped.monospacedDigit().platformFont(in: environment.fontResolutionContext)
        for original in [resource, feature] {
            for copy in [original, try XCTUnwrap(original.fontWithSize(31.375))] {
                let face = try XCTUnwrap(copy.provider.makeTypeface(context, dpi: 216) as? VectorTypeface)
                let selected = try XCTUnwrap(face.selectedFont)
                let suffix = copy.pointSize == 23 ? "170000" : "1F6000"
                XCTAssertEqual(selected.descriptor.postScriptName, "Roboto-Regular_wght_opsz" + suffix)
                XCTAssertEqual(selected.variation, [optical: copy.pointSize])
                XCTAssertNil(selected.variationExtras)
                let supplied = FixedFontProvider(face, pointSize: copy.pointSize)
                let resized = try XCTUnwrap(supplied.withSize(31.375)?.face as? VectorTypeface)
                XCTAssertEqual(resized.selectedFont?.variation, [optical: 31.375])
                XCTAssertEqual(resized.font.variationCoordinates[optical], 31.375)
                XCTAssertEqual(resized.outlineSource.font.variationCoordinates[optical], 31.375)
                XCTAssertEqual(face.font.variationCoordinates[optical], copy.pointSize)
            }
        }
    }

    // ASSERTIONS fontOpticalRealization27Observed
    func testGeneratedOpticalDefaultSeparatesRetainedSizeAndReconstructedFeatureCopies() throws {
        let (bundle, _) = try scoringFixtureBundle("optical-close")
        var environment = EnvironmentValues()
        environment.resourceBundle = bundle
        environment.defaultFontRenderingMode = .vector()
        let optical: UInt32 = 0x6f70_737a
        let context = StyleTestAppContext()
        let original = Font.custom("Roboto-Regular_wght_opsz460000", fixedSize: 100)
            .platformFont(in: environment.fontResolutionContext)
        let wrapped = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
        let feature = wrapped.monospacedDigit().platformFont(in: environment.fontResolutionContext)
        for (resource, comparison) in [(original, [optical: CGFloat(100)]), (feature, [:])] {
            let selected = try XCTUnwrap(resource.provider.makeTypeface(context, dpi: 72)?.selectedFont)
            XCTAssertEqual(selected.variation, comparison)
            XCTAssertEqual(selected.descriptor.postScriptName, "Roboto-Regular")
            XCTAssertTrue(selected.descriptor.derivesOpticalSize)
            XCTAssertNil(selected.variationExtras)
            let resized = try XCTUnwrap(resource.fontWithSize(31.375))
            let copied = try XCTUnwrap(resized.provider.makeTypeface(context, dpi: 72)?.selectedFont)
            XCTAssertEqual(copied.variation, [optical: 31.375])
            XCTAssertEqual(copied.descriptor.postScriptName,
                           resource === original ? "Roboto-Regular_wght_opsz1F6000" : "Roboto-Regular")
        }
    }

    // ASSERTIONS fontOpticalRealization27Observed
    func testOpticalConstructionPreservesIndependentRawWeightExtras() throws {
        let (bundle, _) = try scoringFixtureBundle("optical-close")
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let weight: UInt32 = 0x7767_6874
        let optical: UInt32 = 0x6f70_737a
        for value: CGFloat in [100, 700, 1000] {
            let original = FontResource(descriptor: FontDescriptor(source: .named("Roboto-Regular", bundle),
                pointSize: 23, variation: [weight: value]), in: environment.fontResolutionContext)
            let wrapped = Font(provider: FontBox(Font.PlatformFontProvider(font: original)))
            let feature = wrapped.monospacedDigit().platformFont(in: environment.fontResolutionContext)
            for resource in [original, feature, try XCTUnwrap(original.fontWithSize(31.375))] {
                let selected = try XCTUnwrap(resource.provider.makeTypeface(StyleTestAppContext(), dpi: 144)?.selectedFont)
                XCTAssertEqual(selected.variation, [weight: min(value, 900), optical: resource.pointSize])
                XCTAssertEqual(selected.variationExtras, [weight: value])
                XCTAssertEqual(resource.descriptor().variation, [weight: value])
                let weightSuffix = String(Int(min(value, 900) * 65536), radix: 16, uppercase: true)
                let opticalSuffix = resource.pointSize == 23 ? "170000" : "1F6000"
                XCTAssertEqual(selected.descriptor.postScriptName, "Roboto-Regular_wght" + weightSuffix + "_opsz" + opticalSuffix)
            }
        }
    }

    // ASSERTIONS fontOpticalRealization27Observed
    func testOpticalCopiesUpdateBitmapVectorAndIndependentLayoutFaces() throws {
        guard let device = makeGraphicsDeviceContext() else { throw XCTSkip("Graphics device unavailable") }
        let (bundle, _) = try scoringFixtureBundle("optical-close")
        let context = StyleTestAppContext(graphicsDeviceContext: device)
        let optical: UInt32 = 0x6f70_737a
        for rendering: Font.DefaultRenderingMode in [.bitmap(), .vector()] {
            var environment = EnvironmentValues()
            environment.resourceBundle = bundle
            environment.defaultFontRenderingMode = rendering
            let resource = Font.custom("Roboto-Regular", fixedSize: 23)
                .platformFont(in: environment.fontResolutionContext)
            for dpi: UInt32 in [72, 216] {
                let face = try XCTUnwrap(resource.provider.makeTypeface(context, dpi: dpi))
                let provider = FixedFontProvider(face, pointSize: 23)
                let copy = try XCTUnwrap(provider.withSize(31.375)?.face)
                for (value, size) in [(face, CGFloat(23)), (copy, 31.375)] {
                    let backed = try XCTUnwrap(value as? any VVDFontBackedTypeface)
                    let layout = (value as? VectorTypeface)?.outlineSource.font ?? (value as? TextureTypeface)?.outlineSource.font
                    XCTAssertEqual(backed.font.variationCoordinates[optical], size)
                    XCTAssertEqual(backed.font.pointSize, size)
                    XCTAssertEqual(layout?.variationCoordinates[optical], size)
                    XCTAssertEqual(layout?.pointSize, size)
                    XCTAssertEqual(value.selectedFont?.variation, [optical: size])
                    XCTAssertEqual(value.selectedFont?.descriptor.postScriptName, "Roboto-Regular")
                }
                let originalFont = try XCTUnwrap(face as? any VVDFontBackedTypeface).font
                let copiedFont = try XCTUnwrap(copy as? any VVDFontBackedTypeface).font
                XCTAssertFalse(originalFont === copiedFont)
                XCTAssertTrue(originalFont.source === copiedFont.source)
            }
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
        if fixture == "grade-upright" {
            specs = [(regular, "Font.ttf", 400, 100)]
        } else if fixture.hasPrefix("grade") {
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
                else if tag == "STAT" && fixture.hasPrefix("grade") { data[record + 3] = 0x5f }
                else if tag == "fvar" {
                    let axes = offset + uint16(offset + 4)
                    if fixture == "near" { data[record + 3] = 0x5f }
                    else if fixture.hasPrefix("grade") {
                        data.replaceSubrange(axes + 20..<axes + 24, with: "GRAD".utf8)
                        if fixture == "grade-sparse" {
                            let start = axes + uint16(offset + 8) * uint16(offset + 10)
                            let count = uint16(offset + 12), size = uint16(offset + 14)
                            let instances = (0..<count).compactMap { index -> Data? in
                                let position = start + index * size
                                let weight = uint32(position + 4), grade = uint32(position + 8)
                                guard (weight == 400 * 65536 && grade == 100 * 65536) ||
                                    (source == italic && weight == 100 * 65536 && grade == 75 * 65536) else { return nil }
                                return data.subdata(in: position..<position + size)
                            }
                            XCTAssertEqual(instances.count, source == italic ? 2 : 1)
                            write16(instances.count, at: offset + 12)
                            data.replaceSubrange(start..<start + instances.count * size,
                                                 with: instances.reduce(into: Data()) { $0.append($1) })
                        }
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
            let oldName = fixture.hasPrefix("grade") ? "Condensed" : "Roboto-Italic"
            let newName = fixture.hasPrefix("grade") ? "Candidate" : String(name.dropLast(4))
            if fixture.hasPrefix("grade") || source == italic {
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

    private func opticalFixtureBundle(_ family: String) throws -> (Bundle, URL) {
        let (bundle, fonts) = try fixtureBundle(weightClass: family == "NoStat" ? 440 : 400)
        let path = fonts.appendingPathComponent("Font.ttf")
        var data = try Data(contentsOf: path)
        func uint16(_ offset: Int) -> Int { Int(data[offset]) << 8 | Int(data[offset + 1]) }
        func uint32(_ offset: Int) -> Int { uint16(offset) << 16 | uint16(offset + 2) }
        func write32(_ value: Int, at offset: Int) {
            for index in 0..<4 { data[offset + index] = UInt8((value >> ((3 - index) * 8)) & 255) }
        }
        for index in 0..<uint16(4) {
            let record = 12 + index * 16
            let tag = String(bytes: data[record..<record + 4], encoding: .ascii)
            let offset = uint32(record + 8)
            if tag == "STAT", family == "NoStat" { data[record + 3] = 0x5f }
            if tag == "fvar" {
                let axes = offset + uint16(offset + 4)
                data.replaceSubrange(axes + 20..<axes + 24, with: "opsz".utf8)
                write32(65536, at: axes + 24)
                write32(100 * 65536, at: axes + 28)
                write32(200 * 65536, at: axes + 32)
                if family == "NoStat" {
                    data[offset + 12] = 0
                    data[offset + 13] = 0
                    write32(440 * 65536, at: axes + 8)
                } else if family == "SameOp" {
                    let start = axes + uint16(offset + 8) * uint16(offset + 10)
                    let size = uint16(offset + 14)
                    for instance in 0..<uint16(offset + 12) {
                        write32(100 * 65536, at: start + instance * size + 8)
                    }
                }
            }
        }
        let old = try XCTUnwrap("Roboto".data(using: .utf16BigEndian))
        let new = try XCTUnwrap(family.data(using: .utf16BigEndian))
        XCTAssertEqual(old.count, new.count)
        while let range = data.range(of: old) { data.replaceSubrange(range, with: new) }
        // These axis derivatives exercise metadata and construction, not visual design.
        try data.write(to: path)
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

    private func metadataWeightFixtureBundle(weightClass: UInt16, kind: String) throws -> (Bundle, URL) {
        let (bundle, fonts) = try fixtureBundle(weightClass: kind == "instance" ? 400 : weightClass)
        let url = fonts.appendingPathComponent("Font.ttf")
        var data = try Data(contentsOf: url)
        func u16(_ offset: Int) -> Int { Int(data[offset]) << 8 | Int(data[offset + 1]) }
        func u32(_ offset: Int) -> Int { u16(offset) << 16 | u16(offset + 2) }
        func put16(_ offset: Int, _ value: Int) {
            data[offset] = UInt8(truncatingIfNeeded: value >> 8)
            data[offset + 1] = UInt8(truncatingIfNeeded: value)
        }
        func put32(_ offset: Int, _ value: Int) {
            put16(offset, value >> 16); put16(offset + 2, value)
        }
        let record = try XCTUnwrap((0..<u16(4)).map { 12 + $0 * 16 }.first {
            String(bytes: data[$0..<$0 + 4], encoding: .ascii) == "fvar"
        })
        if kind == "static" {
            data[record + 3] = 0x5f
        } else {
            let offset = u32(record + 8)
            let axes = offset + u16(offset + 4)
            let instances = axes + u16(offset + 8) * u16(offset + 10)
            let size = u16(offset + 14)
            if kind == "default" {
                put32(axes + 8, Int(weightClass) * 65536)
                put16(offset + 12, 0)
            } else {
                let regular = Data(data[(instances + 3 * size)..<(instances + 4 * size)])
                data.replaceSubrange((instances + size)..<(instances + 2 * size), with: regular)
                put16(offset + 12, 2)
                put32(instances + 4, Int(weightClass) * 65536)
            }
        }
        // Descriptor-only derivatives retain the existing source and fixture lifetime.
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
