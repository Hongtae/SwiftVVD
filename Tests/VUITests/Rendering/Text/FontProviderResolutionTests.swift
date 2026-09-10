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
