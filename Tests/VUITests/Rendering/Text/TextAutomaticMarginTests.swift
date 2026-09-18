import Foundation
import XCTest
import VVD
@testable import VUI

final class TextAutomaticMarginTests: XCTestCase {
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

    private func fixture(leading: CGFloat = 0) -> ResolvedTextSource {
        let face = MarginTypeface(leading: leading)
        let descriptor = FontDescriptor(source: .typeface(FixedFontProvider(face)), pointSize: 23)
        let resource = FontResource(descriptor: descriptor, in: environment.fontResolutionContext)
        var properties = Text.ResolvedProperties()
        properties.fonts.storage.insert(resource)
        var source = ResolvedTextSource(runs: [], scaleFactor: 1)
        source.resolvedProperties = properties
        return source
    }

    private func assertMargins(_ actual: EdgeInsets, _ expected: EdgeInsets,
                               file: StaticString = #filePath, line: UInt = #line) {
        for (a, b) in [(actual.top, expected.top), (actual.leading, expected.leading),
                       (actual.bottom, expected.bottom), (actual.trailing, expected.trailing)] {
            XCTAssertEqual(a, b, accuracy: 1e-10, file: file, line: line)
        }
    }

    // ASSERTIONS textAutomaticMargins27SizingObserved textAutomaticMargins27BaselineObserved
    func testUniformAndBalancedMarginsKeepSignedSubpixelValuesInBothOwners() {
        let source = fixture()
        let cases: [(CGFloat, Text.Sizing, Text.Baseline, Text.ResolvedProperties.LineHeightMetrics, CGFloat, CGFloat)] = [
            (1, .standard, .standard, .init(leading: 7), 0, 0),
            (1, .uniformLineHeight, .standard, .init(), 0, 0),
            (1, .uniformLineHeight, .standard, .init(leading: 7), 3.4765625, 3.4765625),
            (1.5, .uniformLineHeight, .standard, .init(leading: 7), 3.309895833333334, 3.309895833333334),
            (2, .uniformLineHeight, .standard, .init(leading: -5), -2.5234375, -2.5234375),
            (1, .uniformLineHeight, .balanced, .init(leading: 7), 5, 1.953125),
            (1, .standard, .balanced, .init(multiple: 1.2, exact: 40), 6.5234375, -6.5234375),
            (1, .standard, .balanced, .init(multiple: 2, exact: 40, leading: 30), 13.0234375, -13.0234375),
            (1, .standard, .balanced, .init(multiple: 2, exact: 40, leading: 7), 9.5234375, -9.5234375),
            (1, .standard, .balanced, .init(), 0, 0)
        ]
        for ownerType: ResolvedStyledText.Type in [ResolvedStyledText.StringDrawing.self, ResolvedStyledText.TextLayoutManager.self] {
            for (scale, sizing, baseline, heights, top, bottom) in cases {
                for vertical in [false, true] {
                    var layout = TextLayoutProperties()
                    layout.pixelLength = 1 / scale
                    layout.textSizing = sizing
                    layout.textBaseline = baseline
                    layout.writingMode = vertical ? .verticalRightToLeft : .horizontalTopToBottom
                    let owner = ownerType.init(layoutProperties: layout, lineHeightMetrics: heights, resolvedText: source)
                    let expected = vertical ? EdgeInsets(top: 0, leading: bottom, bottom: 0, trailing: top)
                        : EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0)
                    assertMargins(owner.layoutMargins, expected)
                }
            }
        }
        var layout = TextLayoutProperties()
        layout.textSizing = .uniformLineHeight
        assertMargins(ResolvedStyledText.StringDrawing(layoutProperties: layout, resolvedText: fixture(leading: 2)).layoutMargins,
                      EdgeInsets(top: 0.9765625, leading: 0, bottom: 0.9765625, trailing: 0))
        assertMargins(ResolvedStyledText.StringDrawing(layoutProperties: layout, lineHeightMetrics: .init(leading: 0),
                      resolvedText: fixture(leading: 2)).layoutMargins, .init())
    }

    // ASSERTIONS textAutomaticMargins27SizingObserved textAutomaticMargins27BaselineObserved
    func testRotationPrecedesReverseModifiersAndBaselineWhileExplicitAndMissingContentBypassThem() {
        var calls: [Int] = []
        var layout = TextLayoutProperties()
        layout.textSizing = .uniformLineHeight
        layout.textSizing.modifiers = [MarginModifier {
            calls.append(1)
            $0.top *= 2; $0.leading *= 2; $0.bottom *= 2; $0.trailing *= 2
        }, MarginModifier {
            calls.append(2)
            $0.top += 2; $0.leading += 1
        }]
        layout.textBaseline = .balanced
        layout.writingMode = .verticalRightToLeft
        let owner = ResolvedStyledText.StringDrawing(layoutProperties: layout,
            lineHeightMetrics: .init(leading: 7), resolvedText: fixture())
        assertMargins(owner.layoutMargins, EdgeInsets(top: 4, leading: 7.4296875, bottom: 0, trailing: 8.4765625))
        XCTAssertEqual(calls, [2, 1])
        calls.removeAll()
        for explicit: EdgeInsets in [.init(), .init(top: -3, leading: 2, bottom: 1, trailing: 4)] {
            let copy = ResolvedStyledText.StringDrawing(layoutProperties: layout, layoutMargins: explicit,
                lineHeightMetrics: .init(leading: 7), resolvedText: fixture())
            XCTAssertEqual(copy.layoutMargins, explicit)
        }
        XCTAssertEqual(ResolvedStyledText.StringDrawing(layoutProperties: layout).layoutMargins, .init())
        XCTAssertTrue(calls.isEmpty)
    }

    // ASSERTIONS textAutomaticMargins27OversizedRoundingObserved textAutomaticMargins27CharacterSetsObserved
    func testOversizedMarginsExcludeEmojiAndAggregateEverySelectedFontWithoutClippingFallback() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        var fonts = Text.ResolvedProperties.Fonts()
        var runs: [ResolvedTextSource.Run] = []
        for size: CGFloat in [23, 13] {
            let font = try XCTUnwrap(VVD.Font(path: url.path))
            font.setPointSize(size, dpi: (72, 72))
            let face = VectorTypeface(font: font, layoutFont: font)
            let resource = VUI.Font.file(url, size: size).platformFont(in: environment.fontResolutionContext)
            fonts.storage.insert(resource)
            var attributes = _ResolvedTextRunAttributes()
            attributes.fontResource = resource
            runs.append(.styledText([face], "AA", .init(), attributes))
        }
        for text in ["AA", "😀", "\u{fe0f}", "\u{030d}"] {
            guard case let .styledText(faces, _, attributes, style) = runs[1] else { return XCTFail() }
            runs[1] = .styledText(faces, text, attributes, style)
            for data in [BundledFontCatalog.shared.outsetData, nil] {
                var source = ResolvedTextSource(runs: runs, scaleFactor: 1, outsetData: data, preferredLanguages: ["en"])
                source.resolvedProperties = .init(fonts: fonts)
                for scale: CGFloat in [1, 1.5, 2] {
                    var layout = TextLayoutProperties()
                    layout.textSizing = .adjustsForOversizedCharacters
                    layout.pixelLength = 1 / scale
                    let owner = ResolvedStyledText.StringDrawing(layoutProperties: layout, resolvedText: source)
                    if text == "\u{030d}", data != nil {
                        let expected: EdgeInsets = switch scale {
                        case 1: .init(top: 4, leading: 5, bottom: 7, trailing: 3)
                        case 1.5: .init(top: 10 / 3, leading: 14 / 3, bottom: 20 / 3, trailing: 8 / 3)
                        default: .init(top: 3.5, leading: 4.5, bottom: 6.5, trailing: 2.5)
                        }
                        assertMargins(owner.layoutMargins, expected)
                    } else {
                        XCTAssertEqual(owner.layoutMargins, .init())
                        XCTAssertGreaterThan(owner.drawingMargins.top, 0)
                    }
                }
            }
        }
    }

    // ASSERTIONS textAutomaticMargins27CanvasObserved textAutomaticMargins27ShadowPaddingObserved
    func testFactoryKeepsShadowPaddingSeparateAndPublishesAutomaticMarginsToMeasurement() throws {
        var env = environment
        env.displayScale = 1.5
        env.textSizing = .uniformLineHeight
        env.textBaseline = .balanced
        env.lineHeight = .leading(increase: 7)
        let context = GraphTextResolutionContext(environment: env, sceneResources: SceneResources())
        let plain = Text(verbatim: "AA").font(.system(size: 23))
        let shadow = plain.modified(with: .anyTextModifier(TextShadowModifier(
            _ShadowEffect(color: .red, radius: 3, offset: CGSize(width: 2, height: 4)))))
        for features: Text.ResolvedProperties.Features in [[], .produceTextLayout] {
            let resolve = { (text: Text) in
                text._resolveStyledText(context: context, referenceDate: Date(timeIntervalSince1970: 0),
                    archiveOptions: .init(), features: features, sizeFitting: false)
            }
            let owner = try XCTUnwrap(resolve(plain))
            let styled = try XCTUnwrap(resolve(shadow))
            XCTAssertNotEqual(owner.layoutMargins, .init())
            assertMargins(styled.layoutMargins, owner.layoutMargins)
            assertMargins(styled.stylePadding, EdgeInsets(top: 4.4, leading: 6.4, bottom: 12.4, trailing: 10.4))
            let proposal = CGSize(width: 300, height: 200)
            let measured = owner.metrics(in: proposal, layoutMargins: nil)
            XCTAssertEqual(styled.metrics(in: proposal, layoutMargins: nil).size, measured.size)
            XCTAssertEqual(owner.metrics(in: proposal, layoutMargins: nil), measured)
            let originalMargins = owner.layoutMargins
            let unpaddedOwner = type(of: owner).init(layoutProperties: owner.layoutProperties, layoutMargins: .init(),
                fonts: owner.fonts, lineHeightMetrics: owner.lineHeightMetrics, resolvedText: owner.resolvedText)
            let unpadded = unpaddedOwner.metrics(in: proposal, layoutMargins: nil)
            XCTAssertEqual(measured.size.height, unpadded.size.height + originalMargins.top + originalMargins.bottom, accuracy: 1e-10)
        }
    }
}

private final class MarginModifier: AnyTextSizingModifier {
    let operation: (inout EdgeInsets) -> Void
    init(_ operation: @escaping (inout EdgeInsets) -> Void) { self.operation = operation }
    override func updateLayoutMargins(_ margins: inout EdgeInsets) { operation(&margins) }
    override func isEqual(to other: AnyTextSizingModifier) -> Bool { self === other }
}

private final class MarginTypeface: Typeface {
    let resolvedMetrics: ResolvedFontMetrics
    init(leading: CGFloat) {
        resolvedMetrics = .init(capHeight: 16.3515625, ascender: 21.337890625,
            descender: -5.615234375, leading: leading)
    }
    var lineHeight: CGFloat { ascender - descender + resolvedMetrics.leading }
    var ascender: CGFloat { resolvedMetrics.ascender }
    var descender: CGFloat { resolvedMetrics.descender }
    var identifier: String { "margin-fixture" }
    func glyph(for scalar: UnicodeScalar) -> TypefaceGlyph? { nil }
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint { .zero }
    func hasGlyph(for scalar: UnicodeScalar) -> Bool { false }
    func isEqual(to other: any Typeface) -> Bool { (other as? Self) === self }
    func hashIdentity(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
