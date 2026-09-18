import Foundation
import XCTest
import VVD
@testable import VUI

final class ResolvedFontAggregationTests: XCTestCase {
    private var previousContext: (any AppContext)?

    override func setUp() {
        previousContext = appContext
        appContext = StyleTestAppContext()
    }

    override func tearDown() { appContext = previousContext }

    private var environment: EnvironmentValues {
        var value = EnvironmentValues()
        value.defaultFontRenderingMode = .vector()
        value.locale = Locale(identifier: "en")
        return value
    }

    private func resource(_ size: CGFloat) -> FontResource {
        FontResource(descriptor: VUI.Font.system(size: size).resolveDescriptor(in: environment.fontResolutionContext),
                     in: environment.fontResolutionContext)
    }

    // ASSERTIONS textResolvedFontsIdentityAndMetricsObserved textResolvedProperties27StructureObserved
    func testFontIdentityCollectionPreservesCopiesAndIndependentIterators() {
        let first = resource(23)
        let equal = resource(23)
        XCTAssertEqual(first, equal)
        XCTAssertFalse(first === equal)
        var fonts = Text.ResolvedProperties.Fonts()
        XCTAssertTrue(Array(fonts.storage).isEmpty)
        fonts.storage.insert(first)
        fonts.storage.insert(first)
        XCTAssertEqual(Array(fonts.storage).count, 1)
        let copy = fonts
        fonts.storage.insert(equal)
        fonts.storage.insert(first)
        XCTAssertEqual(Set(fonts.storage.map(ObjectIdentifier.init)), [ObjectIdentifier(first), ObjectIdentifier(equal)])
        XCTAssertEqual(Array(copy.storage).count, 1)
        var iterator = copy.storage.makeIterator()
        var other = iterator
        XCTAssertTrue(iterator.next() === first)
        XCTAssertNil(iterator.next())
        XCTAssertTrue(other.next() === first)
        XCTAssertNil(other.next())
        fonts.purgeResources(reason: .lowMemory)
        XCTAssertEqual(Array(fonts.storage).count, 2)
        let retained = fonts
        fonts.purgeResources(reason: .appTermination)
        XCTAssertTrue(Array(retained.storage).isEmpty)
        XCTAssertEqual(Array(copy.storage).count, 1)
    }

    // ASSERTIONS textResolvedFontsIdentityAndMetricsObserved
    func testAttributedReconstructionUsesTheResolvedFontObjects() {
        let first = resource(23)
        let second = resource(31)
        let text = NSMutableAttributedString(string: "AABB")
        for (resource, range) in [(first, NSRange(location: 0, length: 2)),
                                  (second, NSRange(location: 2, length: 2))] {
            text.addAttribute(.coreFont, value: VUI.Font(provider: FontBox(Font.PlatformFontProvider(font: resource))), range: range)
        }
        let fonts = Text.ResolvedProperties.Fonts(text)
        XCTAssertEqual(Set(fonts.storage.map(ObjectIdentifier.init)), [ObjectIdentifier(first), ObjectIdentifier(second)])
    }

    // ASSERTIONS textResolvedFontsIdentityAndMetricsObserved
    func testMetricsReduceEachComponentAndPreserveLogicalPointSizeAndNegativeLeading() {
        let inputs: [(ResolvedFontMetrics, CGFloat)] = [
            (.init(capHeight: 20, ascender: 30, descender: -4, leading: -2,
                   outsets: .init(top: 2, leading: 0, bottom: 4, trailing: 0)), 23),
            (.init(capHeight: 14, ascender: 22, descender: -12, leading: -4,
                   outsets: .init(top: 0, leading: 6, bottom: 0, trailing: 8)), 31)
        ]
        let source = ResolvedTextSource(runs: [], scaleFactor: 2)
        for values in [inputs, inputs.reversed().map { $0 }] {
            var fonts = Text.ResolvedProperties.Fonts()
            for (metrics, size) in values {
                let descriptor = FontDescriptor(source: .typeface(FixedFontProvider(AggregationTypeface(metrics))), pointSize: size)
                fonts.storage.insert(FontResource(descriptor: descriptor, in: environment.fontResolutionContext))
            }
            let result = fonts.maxMetrics(for: source)
            XCTAssertEqual(result.capHeight, 10)
            XCTAssertEqual(result.ascender, 15)
            XCTAssertEqual(result.descender, -6)
            XCTAssertEqual(result.leading, -1)
            XCTAssertEqual(result.pointSize, 31)
            XCTAssertEqual(result.outsets, EdgeInsets(top: 1, leading: 3, bottom: 2, trailing: 4))
        }
        let empty = Text.ResolvedProperties.Fonts().maxMetrics(for: source)
        XCTAssertEqual(empty.resolvedMetrics, .init(capHeight: 0, ascender: 0, descender: 0, leading: 0))
        XCTAssertEqual(empty.pointSize, 0)
    }

    // ASSERTIONS textResolvedFontsIdentityAndMetricsObserved
    func testEmptyTextRegistersItsFontAndBothOwnersStoreMetricsAtConstruction() throws {
        let context = GraphTextResolutionContext(environment: environment, sceneResources: SceneResources())
        for text in ["", "AA"] {
            for features: Text.ResolvedProperties.Features in [[], .produceTextLayout] {
                let owner = try XCTUnwrap(Text(verbatim: text).font(.system(size: 23))._resolveStyledText(
                    context: context, referenceDate: Date(timeIntervalSince1970: 0), archiveOptions: .init(),
                    features: features, sizeFitting: false))
                XCTAssertEqual(owner is ResolvedStyledText.TextLayoutManager, features.contains(.produceTextLayout))
                XCTAssertEqual(Array(owner.fonts.storage).count, 1)
                XCTAssertEqual(owner.maxFontMetrics.pointSize, 23)
                XCTAssertGreaterThan(owner.maxFontMetrics.capHeight, 0)
                XCTAssertEqual(owner.resolvedText?.runs.isEmpty, text.isEmpty)
                let metrics = owner.maxFontMetrics
                owner.purgeResources(reason: .appTermination)
                XCTAssertTrue(Array(owner.fonts.storage).isEmpty)
                XCTAssertEqual(owner.maxFontMetrics.resolvedMetrics, metrics.resolvedMetrics)
                XCTAssertEqual(owner.maxFontMetrics.pointSize, metrics.pointSize)
                XCTAssertNil(owner.storage)
            }
        }
    }

    // ASSERTIONS textResolvedFontsIdentityAndMetricsObserved
    func testEmptyFontMetricsKeepTheLocaleDependency() throws {
        let original = environment
        let tracked = original.trackingCopy()
        let tracker = try XCTUnwrap(tracked.tracker)
        let context = GraphTextResolutionContext(environment: tracked, sceneResources: SceneResources())
        let owner = try XCTUnwrap(Text(verbatim: "").font(.system(size: 23))._resolveStyledText(
            context: context, referenceDate: Date(timeIntervalSince1970: 0), archiveOptions: .init(),
            features: [], sizeFitting: false))
        XCTAssertGreaterThan(owner.maxFontMetrics.ascender, 0)
        var changed = original
        changed.locale = Locale(identifier: "ko")
        XCTAssertTrue(tracker.hasDifferentUsedValues(changed._plist))
    }

    // ASSERTIONS textResolvedFontsIdentityAndMetricsObserved
    func testFontResizingUpdatesTheCollectionWithoutMutatingTheOriginal() throws {
        var environment = environment
        environment._contentScaleFactor = 2
        let context = GraphTextResolutionContext(environment: environment, sceneResources: SceneResources())
        let source = try XCTUnwrap(Text(verbatim: "AA").font(.system(size: 23))._resolve(
            context: context, referenceDate: Date(timeIntervalSince1970: 0)))
        for scaled in [source.scalingFonts(by: 0.5, toMultipleOf: nil),
                       try XCTUnwrap(source.resizingUniformFont(to: 11.5))] {
            let owner = ResolvedStyledText.StringDrawing(resolvedText: scaled)
            XCTAssertEqual(owner.maxFontMetrics.pointSize, 11.5)
            let resource = try XCTUnwrap(Array(owner.fonts.storage).first)
            guard case let .styledText(_, _, _, attributes) = scaled.runs.first else { return XCTFail("Missing styled run") }
            XCTAssertTrue(attributes.fontResource === resource)
            let original = ResolvedStyledText.StringDrawing(resolvedText: source)
            XCTAssertEqual(original.maxFontMetrics.pointSize, 23)
            XCTAssertEqual(owner.maxFontMetrics.ascender, original.maxFontMetrics.ascender / 2, accuracy: 0.000001)
        }
        let empty = try XCTUnwrap(Text(verbatim: "").font(.system(size: 23))._resolve(
            context: context, referenceDate: Date(timeIntervalSince1970: 0)))
        let scaledEmpty = ResolvedStyledText.StringDrawing(resolvedText: empty.scalingFonts(by: 0.5))
        XCTAssertEqual(scaledEmpty.maxFontMetrics.pointSize, 11.5)
        XCTAssertEqual(ResolvedStyledText.StringDrawing(resolvedText: empty).maxFontMetrics.pointSize, 23)
    }
}

private final class AggregationTypeface: Typeface {
    let resolvedMetrics: ResolvedFontMetrics
    init(_ metrics: ResolvedFontMetrics) { resolvedMetrics = metrics }
    var lineHeight: CGFloat { ascender - descender + resolvedMetrics.leading }
    var ascender: CGFloat { resolvedMetrics.ascender }
    var descender: CGFloat { resolvedMetrics.descender }
    var identifier: String { "aggregation-fixture" }
    func glyph(for scalar: UnicodeScalar) -> TypefaceGlyph? { nil }
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint { .zero }
    func hasGlyph(for scalar: UnicodeScalar) -> Bool { false }
    func isEqual(to other: any Typeface) -> Bool { (other as? Self) === self }
    func hashIdentity(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
