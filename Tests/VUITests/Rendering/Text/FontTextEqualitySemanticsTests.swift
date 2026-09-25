import Foundation
import XCTest
@testable import VVD
@testable import VUI

final class FontTextEqualitySemanticsTests: XCTestCase {
    // ASSERTIONS fontTextEqualityPublic27Observed
    func testPublicValueFamiliesAreReflexiveAndPairwiseDistinct() {
        assertReflexiveAndPairwiseDistinct(DynamicTypeSize.allCases)
        assertReflexiveAndPairwiseDistinct([
            LegibilityWeight.regular,
            .bold,
        ])
        assertReflexiveAndPairwiseDistinct([
            TextAlignment.leading,
            .center,
            .trailing,
        ])
        assertReflexiveAndPairwiseDistinct([
            Font.Design.default,
            .serif,
            .rounded,
            .monospaced,
        ])
        assertReflexiveAndPairwiseDistinct([
            Font.Leading.standard,
            .tight,
            .loose,
        ])
        assertReflexiveAndPairwiseDistinct(Font.TextStyle.allCases)
        assertReflexiveAndPairwiseDistinct([
            Font.Weight.ultraLight,
            .thin,
            .light,
            .regular,
            .medium,
            .semibold,
            .bold,
            .heavy,
            .black,
        ])
        assertReflexiveAndPairwiseDistinct([
            Font.Width.compressed,
            .condensed,
            .standard,
            .expanded,
        ])
        assertReflexiveAndPairwiseDistinct([
            Text.AlignmentStrategy.default,
            .layoutBased,
            .writingDirectionBased,
        ])
        assertReflexiveAndPairwiseDistinct([
            Text.Case.uppercase,
            .lowercase,
        ])
        assertReflexiveAndPairwiseDistinct([
            Text.DateStyle.time,
            .date,
            .relative,
            .offset,
            .timer,
        ])
        assertReflexiveAndPairwiseDistinct([
            Text.Scale.default,
            .secondary,
        ])
        assertReflexiveAndPairwiseDistinct([
            Text.TruncationMode.head,
            .tail,
            .middle,
        ])
        assertReflexiveAndPairwiseDistinct([
            Text.WritingDirectionStrategy.default,
            .layoutBased,
            .contentBased,
        ])
        assertReflexiveAndPairwiseDistinct([
            TypesettingLanguage.automatic,
            .explicit(Locale.Language(identifier: "en")),
            .explicit(Locale.Language(identifier: "ja")),
        ])
    }

    func testFloatingWidthAndCanonicalLanguageSemantics() {
        XCTAssertEqual(Font.Width.standard, Font.Width(0))
        XCTAssertEqual(Font.Width(-0.0), Font.Width(0.0))

        let nan = Font.Width(.nan)
        XCTAssertNotEqual(nan, nan)

        XCTAssertEqual(
            TypesettingLanguage.explicit(Locale.Language(identifier: "en-US")),
            TypesettingLanguage.explicit(Locale.Language(identifier: "en_US"))
        )
    }

    func testLineStyleComparesPatternAndOptionalColor() {
        XCTAssertEqual(Text.LineStyle.single, Text.LineStyle())
        XCTAssertEqual(
            Text.LineStyle.single,
            Text.LineStyle(pattern: .solid, color: nil)
        )
        XCTAssertNotEqual(
            Text.LineStyle(pattern: .solid),
            Text.LineStyle(pattern: .dash)
        )
        XCTAssertNotEqual(
            Text.LineStyle(pattern: .solid, color: .red),
            Text.LineStyle(pattern: .solid, color: .blue)
        )
    }

    func testTextComparesStorageAndOrderedModifiers() {
        XCTAssertEqual(Text(verbatim: "value"), Text(verbatim: "value"))
        XCTAssertNotEqual(Text(verbatim: "value"), Text(verbatim: "other"))
        XCTAssertNotEqual(Text(verbatim: "value"), Text("value"))
        XCTAssertEqual(
            Text(verbatim: "value").bold(),
            Text(verbatim: "value").bold()
        )
        XCTAssertNotEqual(
            Text(verbatim: "value").bold(),
            Text(verbatim: "value")
        )
        XCTAssertNotEqual(
            Text(verbatim: "value").bold(),
            Text(verbatim: "value").fontWeight(.bold)
        )
        let firstInterpolation = Text(
            "\(Text(verbatim: "A"))\(Text(verbatim: "B"))"
        )
        let secondInterpolation = Text(
            "\(Text(verbatim: "A"))\(Text(verbatim: "B"))"
        )
        XCTAssertEqual(firstInterpolation, secondInterpolation)
        XCTAssertNotEqual(firstInterpolation, Text(verbatim: "AB"))
    }

    func testLayoutValueEqualityComparesEveryOwnedField() {
        let firstLayout = makeLayout("AB")
        let secondLayout = makeLayout("C")
        let firstRun = firstLayout[0][0]
        let secondRun = secondLayout[0][0]

        XCTAssertEqual(firstRun[0..<1], firstRun[0..<1])
        XCTAssertNotEqual(firstRun[0..<1], firstRun[1..<2])
        XCTAssertNotEqual(firstRun[0..<1], secondRun[0..<1])

        let zero = Text.Layout.TypographicBounds()
        XCTAssertEqual(zero, zero)
        XCTAssertEqual(firstRun.typographicBounds, firstRun.typographicBounds)
        XCTAssertNotEqual(zero, firstRun.typographicBounds)
        XCTAssertNotEqual(firstRun.typographicBounds, secondRun.typographicBounds)

        var changed = zero
        changed.origin.x = 1
        XCTAssertNotEqual(zero, changed)
        changed = zero
        changed.origin.y = 1
        XCTAssertNotEqual(zero, changed)
        changed = zero
        changed.width = 1
        XCTAssertNotEqual(zero, changed)
        changed = zero
        changed.ascent = 1
        XCTAssertNotEqual(zero, changed)
        changed = zero
        changed.descent = 1
        XCTAssertNotEqual(zero, changed)
        changed = zero
        changed.leading = 1
        XCTAssertNotEqual(zero, changed)

        let origin = makeAnchor(.zero)
        let copy = Text.LayoutKey.AnchoredLayout(
            origin: origin,
            layout: firstLayout
        )
        XCTAssertEqual(copy, copy)
        XCTAssertNotEqual(
            copy,
            Text.LayoutKey.AnchoredLayout(
                origin: makeAnchor(CGPoint(x: 1, y: 0)),
                layout: firstLayout
            )
        )
        XCTAssertNotEqual(
            copy,
            Text.LayoutKey.AnchoredLayout(
                origin: origin,
                layout: secondLayout
            )
        )
    }

    private func assertReflexiveAndPairwiseDistinct<Value: Equatable>(
        _ values: [Value],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for index in values.indices {
            XCTAssertEqual(values[index], values[index], file: file, line: line)
            for otherIndex in values.indices where otherIndex != index {
                XCTAssertNotEqual(
                    values[index],
                    values[otherIndex],
                    file: file,
                    line: line
                )
            }
        }
    }

    private func makeLayout(_ string: String) -> Text.Layout {
        ResolvedTextSource(
            runs: [.text([FontTextEqualityTestTypeface()], string)],
            scaleFactor: 1
        ).makeLayout(
            in: CGSize(width: 100, height: 100),
            layoutDirection: .leftToRight
        )
    }

    private func makeAnchor(_ point: CGPoint) -> Anchor<CGPoint> {
        let graph = _AGGraph()
        return _AGGraph.withCurrent(graph) {
            let geometry = AnchorGeometry(
                _position: graph.makeInput(value: CGPoint.zero),
                _size: graph.makeInput(value: CGSize.zero),
                _transform: graph.makeInput(value: ViewTransform())
            )
            return Anchor(anchor: point, geometry: geometry)
        }
    }
}

private final class FontTextEqualityTestTypeface: Typeface {
    func glyph(for scalar: UnicodeScalar) -> TypefaceGlyph? {
        .texture(TextureFont.GlyphData(
            texture: nil,
            offset: CGPoint(x: 0, y: 8),
            advance: CGSize(width: 8, height: 10),
            frame: CGRect(x: 0, y: 0, width: 8, height: 10),
            ascender: 8,
            descender: -2
        ))
    }

    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        .zero
    }

    func hasGlyph(for scalar: UnicodeScalar) -> Bool { true }
    var lineHeight: CGFloat { 10 }
    var ascender: CGFloat { 8 }
    var descender: CGFloat { -2 }
    var identifier: String { "font-text-equality-test" }

    func isEqual(to other: any Typeface) -> Bool {
        self === (other as AnyObject)
    }

    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
