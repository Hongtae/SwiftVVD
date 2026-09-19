import Foundation
import XCTest
@testable import VVD

final class FontCombiningShapingTests: XCTestCase {
    // ASSERTIONS textAttributedCharacterOwner27Observed textLinePublication27Observed
    func testLineOwnerRetainsRawSlotsWithoutChangingPublicShaping() throws {
        let font = try XCTUnwrap(Font(data: Self.robotoData()))
        font.setPointSize(23, dpi: (72, 72))
        let cases: [(String, [UInt32], [Int], [UInt32], [Int])] = [
            ("e\u{301}", [703, 65535], [0, 1], [703], [0]),
            ("e\u{301}\u{323}", [1107, 65535, 169], [0, 1, 2], [1107, 169], [0, 2]),
            ("e\u{323}\u{301}", [1107, 65535, 169], [0, 1, 2], [1107, 169], [0, 2]),
            ("x\u{34f}a", [92, 65535, 69], [0, 1, 2], [92, 69], [0, 2]),
            ("\u{34f}\u{34f}a", [65535, 65535, 69], [0, 1, 2], [65535, 69], [0, 2]),
            ("x \u{34f}a", [92, 4, 65535, 69], [0, 1, 2, 3], [92, 4, 69], [0, 1, 3]),
        ]
        for (text, rawIDs, rawSources, publicIDs, publicSources) in cases {
            let raw = try XCTUnwrap(font.shape(text, optionalLigatureBoundaries: [],
                                              retainsDeletedGlyphs: true))
            let projected = try XCTUnwrap(font.shape(text))
            XCTAssertEqual(raw.glyphs.map(\.index), rawIDs, text)
            XCTAssertEqual(raw.glyphs.map(\.sourceIndex), rawSources, text)
            XCTAssertEqual(projected.glyphs.map(\.index), publicIDs, text)
            XCTAssertEqual(projected.glyphs.map(\.sourceIndex), publicSources, text)
            for glyph in raw.glyphs where glyph.index == 65535 {
                XCTAssertEqual(glyph.advance, .zero, text)
                XCTAssertEqual(glyph.offset, .zero, text)
                XCTAssertTrue(glyph.sourceRange.contains(glyph.sourceIndex), text)
            }
            XCTAssertEqual(raw.glyphs.filter { $0.index != 65535 },
                           projected.glyphs.filter { $0.index != 65535 }, text)
        }
    }

    // ASSERTIONS textAttributedShapingContext27Observed
    func testRequiredSubstitutionKeepsConsumedSourceRunSlot() throws {
        let font = try XCTUnwrap(Font(data: Self.robotoData()))
        font.setPointSize(23, dpi: (72, 72))
        let text = "a\u{34f}\u{301}"
        let raw = try XCTUnwrap(font.shape(text,
            optionalLigatureBoundaries: [1, 2], sourceRunBoundaries: [1, 2],
            retainsDeletedGlyphs: true))
        XCTAssertEqual(raw.glyphs.map(\.index), [695, 65535, 65535])
        XCTAssertEqual(raw.glyphs.map(\.sourceIndex), [0, 1, 2])
        XCTAssertEqual(raw.glyphs.map(\.sourceRange), [0..<3, 0..<3, 0..<3])
        for glyph in raw.glyphs.dropFirst() {
            XCTAssertEqual(glyph.advance, .zero)
            XCTAssertEqual(glyph.offset, .zero)
        }

        let unowned = try XCTUnwrap(font.shape(text,
            optionalLigatureBoundaries: [1, 2], retainsDeletedGlyphs: true))
        XCTAssertEqual(unowned.glyphs.map(\.index), [695, 65535])
        XCTAssertEqual(unowned.glyphs.map(\.sourceIndex), [0, 1])
        XCTAssertEqual(font.shape("fi", optionalLigatureBoundaries: [],
                                  sourceRunBoundaries: [], retainsDeletedGlyphs: true)?.glyphs.map(\.index), [471])
    }

    // ASSERTIONS textAttributedCharacterOwner27Observed
    func testCharacterPreparationRetainsDeletedAndTrailingSourceSlots() throws {
        let mapped: Set<UInt32> = [0x65, 0x78, 0xe9, 0x1eb9, 0x301, 0x323, 0x20]
        let cases: [(String, [UInt32], [Int])] = [
            ("e\u{301}", [0xe9, 0x301], [1]),
            ("e\u{301}\u{323}", [0x1eb9, 0x301, 0x301], [1]),
            ("e\u{323}\u{301}", [0x1eb9, 0x323, 0x301], [1]),
            ("x e\u{301}\u{323} x", [0x78, 0x20, 0x1eb9, 0x301, 0x301, 0x20, 0x78], [3]),
            ("e\u{301}\u{323}e\u{323}\u{301}", [0x1eb9, 0x301, 0x301, 0x1eb9, 0x323, 0x301], [1, 4]),
        ]
        func prepare(_ text: String, hasGlyph: (UInt32) -> Bool,
                     lastResort: Bool = false) -> CharacterComposer.Input? {
            let scalars = text.unicodeScalars.map(\.value)
            var ranges: [Range<Int>] = []
            for character in text {
                let range = ranges.count..<(ranges.count + character.unicodeScalars.count)
                ranges.append(contentsOf: repeatElement(range, count: range.count))
            }
            return CharacterComposer.prepare(scalars, range: 0..<scalars.count,
                graphemes: ranges, isLastResort: lastResort, hasGlyph: hasGlyph)
        }
        for (text, scalars, deleted) in cases {
            let result = try XCTUnwrap(prepare(text, hasGlyph: mapped.contains))
            XCTAssertEqual(result.scalars, scalars, text)
            XCTAssertEqual(result.deletedSources, deleted, text)
            XCTAssertEqual(result.scalars.count, text.unicodeScalars.count, text)
        }
        XCTAssertNil(prepare("e\u{301}", hasGlyph: { $0 != 0xe9 }))
        XCTAssertNil(prepare("e\u{301}\u{323}", hasGlyph: { $0 != 0x1eb9 }))
        XCTAssertNil(prepare("x\u{301}\u{323}", hasGlyph: mapped.contains))
        XCTAssertNil(prepare("e\u{301}", hasGlyph: mapped.contains, lastResort: true))
    }

    // ASSERTIONS textAttributedCharacterOwner27Observed
    func testCanonicalDeletionDoesNotChangeOtherCharacterEncoding() throws {
        let original = try Self.robotoData()
        let withoutSpace = try Self.variant(original,
            characterMap: [0x65: 73, 0xe9: 703, 0x78: 92, 0x301: 169])
        for data in [original, withoutSpace] {
            let font = try XCTUnwrap(Font(data: data))
            font.setPointSize(23, dpi: (72, 72))
            let control = try XCTUnwrap(font.shape("\u{e9}x\u{fe0f}"))
            let composed = try XCTUnwrap(font.shape("e\u{301}x\u{fe0f}"))
            XCTAssertEqual(composed.glyphs.map(\.index), control.glyphs.map(\.index))
            XCTAssertEqual(composed.glyphs.map(\.sourceIndex),
                           control.glyphs.map { $0.sourceIndex == 0 ? 0 : $0.sourceIndex + 1 })
            XCTAssertEqual(composed.glyphs.map(\.advance), control.glyphs.map(\.advance))
            XCTAssertEqual(composed.glyphs.map(\.offset), control.glyphs.map(\.offset))
        }
    }

    // ASSERTIONS textAttributedShapingContext27Observed
    func testAttributeBoundariesConstrainOptionalLigaturesWithoutSplittingShaping() throws {
        let font = try XCTUnwrap(Font(data: Self.robotoData()))
        let cases: [(String, [Int], [UInt32], [Int], [Double], [(Double, Double)])] = [
            ("fi", [1], [74, 77], [0, 1], [7.99609375, 5.5927734375], [(0, 0), (7.99609375, 0)]),
            ("a\u{34f}\u{301}", [1, 2], [695], [0], [12.5107421875], [(0, 0)]),
            ("e\u{301}", [1], [703], [0], [12.1962890625], [(0, 0)]),
            ("AV", [1], [37, 58], [0, 1], [14.02685546875, 14.64453125], [(0, 0), (14.02685546875, 0)]),
            ("x\u{301}\u{323}", [1, 2], [92, 169, 173], [0, 1, 2], [11.41015625, 0, 0],
                [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ("\u{34f}\u{34f}a", [1, 2], [65535, 69], [0, 2], [0, 12.5107421875], [(0, 0), (0, 0)]),
        ]
        for dpi: UInt32 in [72, 144] {
            font.setPointSize(23, dpi: (dpi, dpi))
            for (text, boundaries, glyphs, indices, advances, positions) in cases {
                let result = try XCTUnwrap(font.shape(text, optionalLigatureBoundaries: boundaries))
                XCTAssertEqual(result.glyphs.map(\.index), glyphs, text)
                XCTAssertEqual(result.glyphs.map(\.sourceIndex), indices, text)
                Self.check(result, scale: Double(dpi) / 72, advances: advances, positions: positions)
                XCTAssertEqual(Set(result.glyphs.flatMap { Array($0.sourceRange) }), Set(0..<text.unicodeScalars.count), text)
            }
            XCTAssertEqual(font.shape("fi")?.glyphs.map(\.index), [471])
        }
    }

    // ASSERTIONS textAttributedShapingContext27Observed
    func testPositioningBoundariesKeepSubstitutionContextAndSplitGPOSInputs() throws {
        let font = try XCTUnwrap(Font(data: Self.robotoData()))
        for dpi: UInt32 in [72, 144] {
            font.setPointSize(23, dpi: (dpi, dpi))
            let scale = Double(dpi) / 72
            let control = try XCTUnwrap(font.shape("x\u{301}\u{323}",
                optionalLigatureBoundaries: [1, 2]))
            XCTAssertEqual(control.glyphs.map(\.index), [92, 169, 173])
            XCTAssertEqual(control.glyphs.map(\.sourceIndex), [0, 1, 2])
            Self.check(control, scale: scale,
                advances: [11.41015625, 0, 0],
                positions: [(0, 0), (12.0615234375, -0.1123046875),
                            (12.443359375, 0.1123046875)])

            let split = try XCTUnwrap(font.shape("x\u{301}\u{323}",
                optionalLigatureBoundaries: [1, 2], positioningRunBoundaries: [1, 2]))
            XCTAssertEqual(split.glyphs.map(\.index), [92, 169, 173])
            XCTAssertEqual(split.glyphs.map(\.sourceIndex), [0, 1, 2])
            Self.check(split, scale: scale,
                advances: [12.471435546875, 0, 0],
                positions: [(0, 0), (10.753173828125, 0.6333984375),
                            (12.471435546875, -0.48291015625)])

            let pair = try XCTUnwrap(font.shape("AV", optionalLigatureBoundaries: [1],
                positioningRunBoundaries: [1]))
            XCTAssertEqual(pair.glyphs.map(\.index), [37, 58])
            XCTAssertEqual(pair.glyphs.map(\.sourceIndex), [0, 1])
            Self.check(pair, scale: scale,
                advances: [15.00390625, 14.64453125],
                positions: [(0, 0), (15.00390625, 0)])
        }
        XCTAssertNil(font.shape("x\u{301}\u{323}", optionalLigatureBoundaries: [1, 2],
                                positioningRunBoundaries: [2, 1]))
    }

    // ASSERTIONS textAttributedShapingContext27Observed
    func testPreparedCrossFontCompositionUsesPerGlyphGeometry() throws {
        let data = try Self.robotoData()
        let regular = try XCTUnwrap(Font(data: data))
        let large = try XCTUnwrap(Font(data: data))
        for dpi: UInt32 in [72, 144] {
            regular.setPointSize(23, dpi: (dpi, dpi))
            large.setPointSize(46, dpi: (dpi, dpi))
            let sources: [(Font, String, UInt32, Int)] = [
                (regular, "x", 0x78, 0),
                (large, "\u{301}", 0x301, 1),
                (regular, "\u{323}", 0x323, 2),
            ]
            var glyphs = try sources.map { font, text, scalar, source in
                let shaped = try XCTUnwrap(font.shape(text))
                let glyph = try XCTUnwrap(shaped.glyphs.first)
                let design = try XCTUnwrap(font.designMetrics)
                let bounds = try XCTUnwrap(font.designGlyphBounds(at: glyph.index))
                let scale = font.pointSize * CGFloat(dpi) / 72 /
                    CGFloat(design.unitsPerEM)
                return GlyphComposer.Glyph(
                    scalar: scalar,
                    sourceIndex: source,
                    bounds: bounds.applying(CGAffineTransform(scaleX: scale, y: scale)),
                    isPresent: true,
                    allowsMarkComposition: font.allowsMarkComposition(at: glyph.index),
                    hasResolvedMarkPosition: glyph.hasResolvedMarkPosition,
                    metrics: font.glyphCompositionMetrics,
                    advance: glyph.advance,
                    offset: glyph.offset
                )
            }
            GlyphComposer.compose(&glyphs, sourceUpperBound: 3)

            let scale = CGFloat(dpi) / 72
            XCTAssertEqual(glyphs.map { $0.advance.width / scale },
                           [15.80126953125, 0, 0])
            var origin = CGFloat.zero
            var positions: [CGPoint] = []
            for glyph in glyphs {
                positions.append(CGPoint(x: origin + glyph.offset.x, y: glyph.offset.y))
                origin += glyph.advance.width
            }
            let expected: [(CGFloat, CGFloat)] = [
                (0, 0),
                (15.80126953125, -10.8845703125),
                (12.471435546875, -0.48291015625),
            ]
            for (position, expected) in zip(positions, expected) {
                XCTAssertEqual(position.x / scale, expected.0, accuracy: 1e-8)
                XCTAssertEqual(position.y / scale, expected.1, accuracy: 1e-8)
            }
        }
    }

    // ASSERTIONS textOptionalLookupRanges27Observed
    func testOptionalLookupInputsKeepContextAndSharedRequiredLookups() throws {
        let original = try Self.robotoData()
        let names = ["liga", "ccmp", "rlig", "calt", "shared", "lookahead", "backtrack", "context-input"]
        for name in names {
            let font = try XCTUnwrap(Font(data: Self.variant(original, removePositioning: true,
                substitutions: Self.lookupFixture(name))))
            font.setPointSize(23, dpi: (72, 72))
            for text in ["fi", "Afi", "f\u{34f}i"] {
                let count = text.unicodeScalars.count
                for selected in -1..<count {
                    let boundaries = selected < 0 ? [] : [selected, selected + 1].filter { $0 > 0 && $0 < count }
                    let result = try XCTUnwrap(font.shape(text, optionalLigatureBoundaries: boundaries))
                    var expected: [UInt32]
                    if name == "backtrack" { expected = text == "Afi" ? [37, 38, 77] : [74, 77] }
                    else if name == "lookahead" { expected = text == "Afi" ? [37, 38, 77] : [38, 77] }
                    else {
                        let crosses = selected >= 0 && !(text == "Afi" && selected == 0)
                        let optional = name == "liga" || name == "context-input"
                        expected = optional && crosses ? [74, 77] : [38]
                        if text == "Afi" { expected.insert(37, at: 0) }
                    }
                    XCTAssertEqual(result.glyphs.map(\.index), expected, "\(name) \(text) \(selected)")
                    let source = text == "Afi" ? (expected.count == 2 ? [0, 1] : [0, 1, 2])
                        : (expected.count == 1 ? [0] : [0, count - 1])
                    XCTAssertEqual(result.glyphs.map(\.sourceIndex), source, "\(name) \(text) \(selected)")
                }
            }
        }
    }

    private static func lookupFixture(_ name: String) -> Data {
        func words(_ values: [Int]) -> Data { Data(values.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] }) }
        func coverage(_ glyph: Int) -> Data { words([1, 1, glyph]) }
        func lookup(_ type: Int, _ body: Data) -> Data { words([type, 0, 1, 8]) + body }
        let ligature = lookup(4, words([1, 18, 1, 8, 1, 4, 38, 2, 77]) + coverage(74))
        let single = lookup(1, words([2, 8, 1, 38]) + coverage(74))
        let lookups: [Data]
        switch name {
        case "lookahead": lookups = [lookup(6, words([3, 0, 1, 18, 1, 24, 1, 0, 1]) + coverage(74) + coverage(77)), single]
        case "backtrack": lookups = [lookup(6, words([3, 1, 18, 1, 24, 0, 1, 0, 1]) + coverage(37) + coverage(74)), single]
        case "context-input": lookups = [lookup(5, words([3, 2, 1, 14, 20, 0, 1]) + coverage(74) + coverage(77)), ligature]
        default: lookups = [ligature]
        }
        let tags = name == "shared" ? ["ccmp", "liga"]
            : (["liga", "ccmp", "rlig", "calt"].contains(name) ? [name] : ["clig"])
        let script = words([4, 0, 0, 65535, tags.count] + Array(tags.indices))
        let scripts = words([2]) + Data("DFLT".utf8) + words([14]) + Data("latn".utf8) + words([14 + script.count]) + script + script
        var features = words([tags.count])
        for (index, tag) in tags.enumerated() { features += Data(tag.utf8) + words([2 + 6 * tags.count + 6 * index]) }
        for _ in tags { features += words([0, 1, 0]) }
        var offsets: [Int] = [], position = 2 + 2 * lookups.count
        for value in lookups { offsets.append(position); position += value.count }
        let list = words([lookups.count] + offsets) + lookups.reduce(Data(), +)
        return words([1, 0, 10, 10 + scripts.count, 10 + scripts.count + features.count]) + scripts + features + list
    }

    // ASSERTIONS textDefaultIgnorableEncoding27Observed
    func testDefaultIgnorableEncodingKeepsFontGlyphsAndDeletedSourceSlots() throws {
        let original = try Self.robotoData()
        let controls: [UInt32] = [0x034f, 0x200b, 0x200c, 0x200d, 0x2060, 0xfeff,
                                  0xfe0e, 0xfe0f, 0xe0100, 0x00ad, 0x2061]
        let mappedControls: Set<UInt32> = [0x034f, 0x200c, 0x200d, 0xfe0e, 0xfe0f, 0xe0100]
        let selectedControls: Set<UInt32> = [0x034f, 0x200b, 0x2060, 0xfeff, 0xfe0e, 0xe0100, 0x00ad, 0x2061]
        var map: [UInt32: UInt32] = [0x20: 4, 0x61: 69, 0x71: 85, 0x66: 74, 0x69: 77,
                                    0x78: 92, 0x301: 169, 0x323: 173, 0xe1: 695]
        for control in controls { map[control] = 70 }
        let mapped = try Self.variant(original, characterMap: map)
        for control in controls { map[control] = 4 }
        let mappedSpace = try Self.variant(original, characterMap: map)
        typealias Expected = ([UInt32], [Int], [Double], [(Double, Double)])
        let hidden: [Expected] = [
            ([695], [0], [12.5107421875], [(0, 0)]),
            ([85, 169], [0, 2], [13.072265625, 0], [(0, 0), (12.38720703125, 0)]),
            ([471], [0], [12.74658203125], [(0, 0)]),
            ([65535, 69], [0, 1], [0, 12.5107421875], [(0, 0), (0, 0)]),
            ([69], [0], [12.5107421875], [(0, 0)]),
            ([65535], [0], [0], [(0, 0)]),
            ([92, 169, 173], [0, 2, 3], [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)]),
            ([695, 173], [0, 3], [12.5107421875, 0], [(0, 0), (12.34228515625, 0)]),
        ]
        let visible: [Expected] = [
            ([69, 70, 169], [0, 1, 2], [12.5107421875, 12.9150390625, 0], [(0, 0), (12.5107421875, 0), (25.9873046875, 3.60498046875)]),
            ([85, 70, 169], [0, 1, 2], [13.072265625, 12.9150390625, 0], [(0, 0), (13.072265625, 0), (26.548828125, 3.60498046875)]),
            ([74, 70, 77], [0, 1, 2], [7.99609375, 12.9150390625, 5.5927734375], [(0, 0), (7.99609375, 0), (20.9111328125, 0)]),
            ([70, 69], [0, 1], [12.9150390625, 12.5107421875], [(0, 0), (12.9150390625, 0)]),
            ([69, 70], [0, 1], [12.5107421875, 12.9150390625], [(0, 0), (12.5107421875, 0)]),
            ([70], [0], [12.9150390625], [(0, 0)]),
            ([92, 70, 169, 173], [0, 1, 2, 3], [11.41015625, 12.9150390625, 0, 0], [(0, 0), (11.41015625, 0), (24.88671875, 3.60498046875), (24.83056640625, -0.1123046875)]),
            ([695, 1219], [0, 2], [12.5107421875, 12.9150390625], [(0, 0), (12.5107421875, 0)]),
        ]
        let space: [Expected] = [
            ([69, 4, 169], [0, 1, 2], [12.5107421875, 5.705078125, 0], [(0, 0), (12.5107421875, 0), (18.2158203125, 0)]),
            ([85, 4, 169], [0, 1, 2], [13.072265625, 5.705078125, 0], [(0, 0), (13.072265625, 0), (18.77734375, 0)]),
            ([74, 4, 77], [0, 1, 2], [7.99609375, 5.705078125, 5.5927734375], [(0, 0), (7.99609375, 0), (13.701171875, 0)]),
            ([4, 69], [0, 1], [5.705078125, 12.5107421875], [(0, 0), (5.705078125, 0)]),
            ([69, 4], [0, 1], [12.5107421875, 5.705078125], [(0, 0), (12.5107421875, 0)]),
            ([4], [0], [5.705078125], [(0, 0)]),
            ([92, 4, 169, 173], [0, 1, 2, 3], [11.41015625, 5.705078125, 0, 0], [(0, 0), (11.41015625, 0), (17.115234375, 0), (17.115234375, 0)]),
            ([695, 4, 173], [0, 2, 3], [12.5107421875, 5.705078125, 0], [(0, 0), (12.5107421875, 0), (18.2158203125, 0)]),
        ]
        for (mapping, data) in [(0, original), (70, mapped), (4, mappedSpace)] {
            let font = try XCTUnwrap(Font(data: data))
            for dpi: UInt32 in [72, 144] {
                font.setPointSize(23, dpi: (dpi, dpi))
                for control in controls where mapping != 0 || selectedControls.contains(control) {
                    let marker = String(Unicode.Scalar(control)!)
                    let inputs = ["a" + marker + "\u{301}", "q" + marker + "\u{301}",
                                  "f" + marker + "i", marker + "a", "a" + marker, marker,
                                  "x" + marker + "\u{301}\u{323}", "a\u{301}" + marker + "\u{323}"]
                    var expected = mapping != 0 && mappedControls.contains(control)
                        ? (mapping == 4 ? space : visible) : hidden
                    if mapping == 4 && control == 0x200c {
                        expected[0] = ([69, 4, 169], [0, 1, 2], [12.5107421875, 7.900634765625, 0],
                            [(0, 0), (12.5107421875, 0), (20.411376953125, 0)])
                        expected[1] = ([85, 4, 169], [0, 1, 2], [13.072265625, 7.900634765625, 0],
                            [(0, 0), (13.072265625, 0), (20.972900390625, 0)])
                        expected[6] = ([92, 4, 169, 173], [0, 1, 2, 3], [11.41015625, 9.618896484375, 0, 0],
                            [(0, 0), (11.41015625, 0), (19.310791015625, 0), (21.029052734375, -0.48291015625)])
                    }
                    for pair in zip(inputs, expected) {
                        let (text, value) = pair
                        let shaped = try XCTUnwrap(font.shape(text))
                        XCTAssertEqual(shaped.glyphs.map(\.index), value.0, text)
                        XCTAssertEqual(shaped.glyphs.map(\.sourceIndex), value.1, text)
                        Self.check(shaped, scale: Double(dpi) / 72,
                                   advances: value.2, positions: value.3)
                        let covered = Set(shaped.glyphs.flatMap { Array($0.sourceRange) })
                        XCTAssertEqual(covered, Set(0..<text.unicodeScalars.count), text)
                    }
                }
            }
        }
    }

    // ASSERTIONS textDefaultIgnorableEncoding27Observed
    func testUncombinedRangeCursorAdmitsVisibleNonJoinerBase() throws {
        let original = try Self.robotoData()
        let controls: [UInt32] = [0x200c, 0x200d]
        var map: [UInt32: UInt32] = [
            0x20: 4, 0x61: 69, 0x71: 85, 0x78: 92, 0x301: 169,
            0x323: 173, 0xe1: 695,
        ]
        for control in controls { map[control] = 4 }
        let font = try XCTUnwrap(Font(data: Self.variant(original, characterMap: map)))
        typealias Expected = (String, [UInt32], [Int], [Double], [(Double, Double)])
        let cases: [Expected] = [
            ("a\u{200c}\u{301}", [69, 4, 169], [0, 1, 2],
             [12.5107421875, 7.900634765625, 0],
             [(0, 0), (12.5107421875, 0), (20.411376953125, 0)]),
            ("q\u{200c}\u{301}", [85, 4, 169], [0, 1, 2],
             [13.072265625, 7.900634765625, 0],
             [(0, 0), (13.072265625, 0), (20.972900390625, 0)]),
            ("x\u{200c}\u{301}\u{323}", [92, 4, 169, 173], [0, 1, 2, 3],
             [11.41015625, 9.618896484375, 0, 0],
             [(0, 0), (11.41015625, 0), (19.310791015625, 0),
              (21.029052734375, -0.48291015625)]),
            ("a\u{200d}\u{301}", [69, 4, 169], [0, 1, 2],
             [12.5107421875, 5.705078125, 0],
             [(0, 0), (12.5107421875, 0), (18.2158203125, 0)]),
            ("a\u{301}\u{200c}\u{323}", [695, 4, 173], [0, 2, 3],
             [12.5107421875, 5.705078125, 0],
             [(0, 0), (12.5107421875, 0), (18.2158203125, 0)]),
        ]
        for dpi: UInt32 in [72, 144] {
            font.setPointSize(23, dpi: (dpi, dpi))
            for (text, glyphs, sources, advances, positions) in cases {
                let shaped = try XCTUnwrap(font.shape(text))
                XCTAssertEqual(shaped.glyphs.map(\.index), glyphs, text)
                XCTAssertEqual(shaped.glyphs.map(\.sourceIndex), sources, text)
                Self.check(shaped, scale: Double(dpi) / 72,
                           advances: advances, positions: positions)
                XCTAssertEqual(Set(shaped.glyphs.flatMap { Array($0.sourceRange) }),
                               Set(0..<text.unicodeScalars.count), text)
            }
        }
    }

    // ASSERTIONS textCanonicalMarks27Observed
    func testLeadingMarksRetainNominalAdvanceAndOrigin() throws {
        let original = try Self.robotoData()
        typealias Expected = (String, [UInt32], [Int], [Double], [(Double, Double)])
        let positioned: [Expected] = [
            ("\u{301}", [169], [0], [7.3896484375],
             [(7.3896484375, 0)]),
            ("\u{301}\u{300}", [169, 168], [0, 1], [7.3896484375, 0],
             [(7.3896484375, 0), (6.9853515625, 3.94189453125)]),
            ("\u{301}a", [169, 69], [0, 1], [7.3896484375, 12.5107421875],
             [(7.3896484375, 0), (7.3896484375, 0)]),
            ("\u{301}\u{323}", [169, 173], [0, 1], [10.461181640625, 0],
             [(7.3896484375, 0), (10.461181640625, 13.46533203125)]),
            ("\u{301}\u{323}e\u{301}\u{323}", [169, 173, 1107, 169], [0, 1, 2, 4],
             [7.3896484375, 0, 12.1962890625, 0],
             [(7.3896484375, 0), (10.461181640625, 13.46533203125),
              (7.3896484375, 0), (20.09130859375, 0)]),
        ]
        let geometric: [Expected] = [
            ("\u{301}\u{300}", [169, 168], [0, 1], [10.9833984375, 0],
             [(7.3896484375, 0), (10.9833984375, 5.345703125)]),
            ("\u{301}\u{323}", [169, 173], [0, 1], [10.461181640625, 0],
             [(7.3896484375, 0), (10.461181640625, 13.46533203125)]),
        ]
        let fonts = [
            (try XCTUnwrap(Font(data: original)), positioned),
            (try XCTUnwrap(Font(data: Self.variant(original, removePositioning: true))), geometric),
        ]
        for (font, cases) in fonts {
            for dpi: UInt32 in [72, 144] {
                font.setPointSize(23, dpi: (dpi, dpi))
                let embedded = try XCTUnwrap(font.shape(
                    "\u{301}", optionalLigatureBoundaries: [],
                    allowsLeadingMarkBase: false
                ))
                Self.check(embedded, scale: Double(dpi) / 72,
                           advances: [0], positions: [(0, 0)])
                for (text, glyphs, sources, advances, positions) in cases {
                    let shaped = try XCTUnwrap(font.shape(text))
                    XCTAssertEqual(shaped.glyphs.map(\.index), glyphs, text)
                    XCTAssertEqual(shaped.glyphs.map(\.sourceIndex), sources, text)
                    Self.check(shaped, scale: Double(dpi) / 72,
                               advances: advances, positions: positions)
                }
            }
        }
    }

    // ASSERTIONS textCanonicalMarks27Observed
    func testAlphabeticCompositionPreservesGreekAndCyrillicGlyphSources() throws {
        let font = try XCTUnwrap(Font(data: Self.robotoData()))
        font.setPointSize(23, dpi: (72, 72))
        let cases: [(String, [UInt32], [Int])] = [
            ("\u{393}\u{301}\u{323}", [177, 169, 173], [0, 1, 2]),
            ("\u{393}\u{323}\u{301}", [177, 173, 169], [0, 1, 2]),
            ("\u{393}\u{300}\u{301}", [177, 168, 169], [0, 1, 2]),
            ("\u{393}\u{301}\u{300}", [177, 169, 168], [0, 1, 2]),
            ("\u{3b1}\u{301}\u{323}", [954, 173], [0, 2]),
            ("\u{3b1}\u{323}\u{301}", [954, 173], [0, 2]),
            ("\u{3b1}\u{300}\u{301}", [187, 168, 169], [0, 1, 2]),
            ("\u{3b1}\u{301}\u{300}", [954, 168], [0, 2]),
            ("\u{3c9}\u{301}\u{323}", [968, 173], [0, 2]),
            ("\u{3c9}\u{323}\u{301}", [968, 173], [0, 2]),
            ("\u{3c9}\u{300}\u{301}", [206, 168, 169], [0, 1, 2]),
            ("\u{3c9}\u{301}\u{300}", [968, 168], [0, 2]),
            ("\u{3b9}\u{301}\u{323}", [957, 173], [0, 2]),
            ("\u{3b9}\u{323}\u{301}", [957, 173], [0, 2]),
            ("\u{3b9}\u{300}\u{301}", [195, 168, 169], [0, 1, 2]),
            ("\u{3b9}\u{301}\u{300}", [957, 168], [0, 2]),
            ("\u{3b5}\u{301}\u{323}", [955, 173], [0, 2]),
            ("\u{3b5}\u{323}\u{301}", [955, 173], [0, 2]),
            ("\u{3b5}\u{300}\u{301}", [191, 168, 169], [0, 1, 2]),
            ("\u{3b5}\u{301}\u{300}", [955, 168], [0, 2]),
            ("\u{418}\u{301}\u{323}", [220, 169, 173], [0, 1, 2]),
            ("\u{418}\u{323}\u{301}", [220, 173, 169], [0, 1, 2]),
            ("\u{418}\u{300}\u{301}", [1025, 169], [0, 2]),
            ("\u{418}\u{301}\u{300}", [220, 169, 168], [0, 1, 2]),
            ("\u{438}\u{301}\u{323}", [240, 169, 173], [0, 1, 2]),
            ("\u{438}\u{323}\u{301}", [240, 173, 169], [0, 1, 2]),
            ("\u{438}\u{300}\u{301}", [1027, 169], [0, 2]),
            ("\u{438}\u{301}\u{300}", [240, 169, 168], [0, 1, 2]),
            ("\u{415}\u{301}\u{323}", [981, 169, 173], [0, 1, 2]),
            ("\u{415}\u{323}\u{301}", [981, 173, 169], [0, 1, 2]),
            ("\u{415}\u{300}\u{301}", [1024, 169], [0, 2]),
            ("\u{415}\u{301}\u{300}", [981, 169, 168], [0, 1, 2]),
            ("\u{435}\u{301}\u{323}", [992, 169, 173], [0, 1, 2]),
            ("\u{435}\u{323}\u{301}", [992, 173, 169], [0, 1, 2]),
            ("\u{435}\u{300}\u{301}", [1026, 169], [0, 2]),
            ("\u{435}\u{301}\u{300}", [992, 169, 168], [0, 1, 2]),
            ("\u{419}\u{301}\u{323}", [982, 169, 173], [0, 1, 2]),
            ("\u{419}\u{323}\u{301}", [982, 173, 169], [0, 1, 2]),
            ("\u{419}\u{300}\u{301}", [982, 168, 169], [0, 1, 2]),
            ("\u{419}\u{301}\u{300}", [982, 169, 168], [0, 1, 2]),
            ("\u{439}\u{301}\u{323}", [993, 169, 173], [0, 1, 2]),
            ("\u{439}\u{323}\u{301}", [993, 173, 169], [0, 1, 2]),
            ("\u{439}\u{300}\u{301}", [993, 168, 169], [0, 1, 2]),
            ("\u{439}\u{301}\u{300}", [993, 169, 168], [0, 1, 2]),
        ]
        for (text, glyphs, indices) in cases {
            let shaped = try XCTUnwrap(font.shape(text))
            XCTAssertEqual(shaped.glyphs.map(\.index), glyphs, text)
            XCTAssertEqual(shaped.glyphs.map(\.sourceIndex), indices, text)
            XCTAssertTrue(shaped.glyphs.allSatisfy { $0.sourceRange == 0..<3 }, text)
        }
    }

    // ASSERTIONS textCanonicalMarks27Observed
    func testCompositionRetainsFeatureRangesAndSupplementarySourceContext() throws {
        let font = try XCTUnwrap(Font(data: Self.robotoData()))
        font.setPointSize(23, dpi: (72, 72))
        let text = "e\u{301}\u{323}fifi"
        let original = try XCTUnwrap(font.shape(text))
        XCTAssertEqual(original.glyphs.map(\.index), [1107, 169, 471, 471])
        XCTAssertEqual(original.glyphs.map(\.sourceIndex), [0, 2, 3, 5])
        XCTAssertEqual(original.glyphs.map(\.sourceRange), [0..<3, 0..<3, 3..<5, 5..<7])
        let selected = try XCTUnwrap(font.shape(text, features: [
            .init(tag: 0x6c69_6761, value: 0, range: 4..<5)
        ]))
        XCTAssertEqual(selected.glyphs.map(\.index), [1107, 169, 74, 77, 471])
        XCTAssertEqual(selected.glyphs.map(\.sourceIndex), [0, 2, 3, 4, 5])
        XCTAssertEqual(selected.glyphs.map(\.sourceRange), [0..<3, 0..<3, 3..<4, 4..<5, 5..<7])
        XCTAssertEqual(try XCTUnwrap(font.shape(text)), original)
        let prefix = try XCTUnwrap(font.shape("\u{1f600}" + text))
        XCTAssertEqual(prefix.glyphs.dropFirst().map(\.index), original.glyphs.map(\.index))
        XCTAssertEqual(prefix.glyphs.dropFirst().map(\.sourceIndex), [1, 3, 4, 6])
        XCTAssertEqual(prefix.glyphs.dropFirst().map(\.sourceRange), [1..<4, 1..<4, 4..<6, 6..<8])
    }

    // ASSERTIONS textCanonicalMarks27Observed
    func testCanonicalCompositionKeepsOriginalIndicesAndFontGates() throws {
        typealias Row = (String, [UInt32], [Int], [Double], [(Double, Double)], [Range<Int>])
        let groups: [(Bool, Bool, [Row])] = [
            (false, false, [
                ("x\u{301}\u{323}", [92, 169, 173], [0, 1, 2],
                 [11.41015625, 0, 0], [(0, 0), (12.0615234375, -0.1123046875), (12.443359375, 0.1123046875)],
                 [0..<3, 0..<3, 0..<3]),
                ("e\u{301}\u{323}", [1107, 169], [0, 2],
                 [12.1962890625, 0], [(0, 0), (12.70166015625, 0)],
                 [0..<3, 0..<3]),
                ("q\u{301}\u{323}", [85, 169, 173], [0, 1, 2],
                 [13.072265625, 0, 0], [(0, 0), (12.38720703125, 0), (16.99169921875, -4.57080078125)],
                 [0..<3, 0..<3, 0..<3]),
                ("q\u{323}\u{301}", [85, 173, 169], [0, 1, 2],
                 [13.072265625, 0, 0], [(0, 0), (16.99169921875, -4.57080078125), (12.38720703125, 0)],
                 [0..<3, 0..<3, 0..<3]),
                ("e\u{323}\u{301}", [1107, 169], [0, 2],
                 [12.1962890625, 0], [(0, 0), (12.70166015625, 0)],
                 [0..<3, 0..<3]),
                ("\u{e9}\u{323}", [703, 173], [0, 1],
                 [12.1962890625, 0], [(0, 0), (13.08349609375, 0)],
                 [0..<2, 0..<2]),
                ("\u{1eb9}\u{301}", [1107, 169], [0, 1],
                 [12.1962890625, 0], [(0, 0), (12.70166015625, 0)],
                 [0..<2, 0..<2]),
                ("e\u{301}\u{323}\u{300}", [1107, 169, 168], [0, 2, 3],
                 [12.1962890625, 0, 0], [(0, 0), (12.70166015625, 0), (12.29736328125, 3.94189453125)],
                 [0..<4, 0..<4, 0..<4]),
                ("e\u{323}\u{301}\u{300}", [1107, 169, 168], [0, 2, 3],
                 [12.1962890625, 0, 0], [(0, 0), (12.70166015625, 0), (12.29736328125, 3.94189453125)],
                 [0..<4, 0..<4, 0..<4]),
                ("\u{ea}\u{301}", [1113], [0],
                 [12.1962890625], [(0, 0)],
                 [0..<2]),
                ("\u{e9}\u{323}x", [703, 173, 92], [0, 1, 2],
                 [12.1962890625, 0, 11.41015625], [(0, 0), (13.08349609375, 0), (12.1962890625, 0)],
                 [0..<2, 0..<2, 2..<3]),
                ("x e\u{301}\u{323} z", [92, 4, 1107, 169, 4, 94], [0, 1, 2, 4, 5, 6],
                 [11.41015625, 5.705078125, 12.1962890625, 0, 5.705078125, 11.41015625], [(0, 0), (11.41015625, 0), (17.115234375, 0), (29.81689453125, 0), (29.3115234375, 0), (35.0166015625, 0)],
                 [0..<1, 1..<2, 2..<5, 2..<5, 5..<6, 6..<7]),
                ("e\u{301}\u{323}e\u{301}\u{323}", [1107, 169, 1107, 169], [0, 2, 3, 5],
                 [12.1962890625, 0, 12.1962890625, 0], [(0, 0), (12.70166015625, 0), (12.1962890625, 0), (24.89794921875, 0)],
                 [0..<3, 0..<3, 3..<6, 3..<6]),
                ("e\u{301}\u{323} q\u{301}\u{323}", [1107, 169, 4, 85, 169, 173], [0, 2, 3, 4, 5, 6],
                 [12.1962890625, 0, 5.705078125, 13.072265625, 0, 0], [(0, 0), (12.70166015625, 0), (12.1962890625, 0), (17.9013671875, 0), (30.28857421875, 0), (34.89306640625, -4.57080078125)],
                 [0..<3, 0..<3, 3..<4, 4..<7, 4..<7, 4..<7]),
                ("x\u{323}\u{301}e\u{301}\u{323}", [92, 173, 169, 1107, 169], [0, 1, 2, 3, 5],
                 [11.185546875, 0, 0, 12.1962890625, 0], [(0, 0), (12.443359375, 0.1123046875), (12.0615234375, -0.1123046875), (11.185546875, 0), (23.88720703125, 0)],
                 [0..<3, 0..<3, 0..<3, 3..<6, 3..<6]),
                ("\u{e9}\u{300}\u{323}", [703, 168, 173], [0, 1, 2],
                 [12.1962890625, 0, 0], [(0, 0), (12.29736328125, 3.94189453125), (13.08349609375, 0)],
                 [0..<3, 0..<3, 0..<3]),
                ("\u{1eb9}\u{301}\u{323}", [1107, 169, 173], [0, 1, 2],
                 [12.1962890625, 0, 0], [(0, 0), (12.70166015625, 0), (13.08349609375, -3.9755859375)],
                 [0..<3, 0..<3, 0..<3]),
            ]),
            (true, false, [
                ("x\u{301}\u{323}", [92, 169, 173], [0, 1, 2],
                 [12.471435546875, 0, 0], [(0, 0), (10.753173828125, 0.6333984374999999), (12.471435546875, -0.48291015625)],
                 [0..<3, 0..<3, 0..<3]),
                ("e\u{301}\u{323}", [1107, 169], [0, 2],
                 [12.1962890625, 0], [(0, 0), (11.146240234375, -23.6109375)],
                 [0..<3, 0..<3]),
                ("q\u{301}\u{323}", [85, 169, 173], [0, 1, 2],
                 [13.302490234375, 0, 0], [(0, 0), (11.584228515625, 0.8580078124999999), (13.302490234375, -5.15478515625)],
                 [0..<3, 0..<3, 0..<3]),
                ("q\u{323}\u{301}", [85, 173, 169], [0, 1, 2],
                 [13.302490234375, 0, 0], [(0, 0), (13.302490234375, -5.54111328125), (11.584228515625, 0.8580078124999981)],
                 [0..<3, 0..<3, 0..<3]),
                ("e\u{323}\u{301}", [1107, 169], [0, 2],
                 [12.1962890625, 0], [(0, 0), (11.146240234375, 0.8580078124999999)],
                 [0..<3, 0..<3]),
                ("\u{e9}\u{323}", [703, 173], [0, 1],
                 [12.864501953125, 0], [(0, 0), (12.864501953125, -0.70751953125)],
                 [0..<2, 0..<2]),
                ("\u{1eb9}\u{301}", [1107, 169], [0, 1],
                 [12.1962890625, 0], [(0, 0), (11.146240234375, 0.8580078124999999)],
                 [0..<2, 0..<2]),
                ("e\u{301}\u{323}\u{300}", [1107, 169, 168], [0, 2, 3],
                 [13.38671875, 0, 0], [(0, 0), (11.146240234375, -23.6109375), (13.38671875, 0.8580078124999999)],
                 [0..<4, 0..<4, 0..<4]),
                ("e\u{323}\u{301}\u{300}", [1107, 169, 168], [0, 2, 3],
                 [13.38671875, 0, 0], [(0, 0), (11.146240234375, 0.8580078124999999), (13.38671875, 6.203710937499999)],
                 [0..<4, 0..<4, 0..<4]),
                ("\u{ea}\u{301}", [1113], [0],
                 [12.1962890625], [(0, 0)],
                 [0..<2]),
                ("\u{e9}\u{323}x", [703, 173, 92], [0, 1, 2],
                 [12.1962890625, 0, 11.41015625], [(0, 0), (12.864501953125, -0.70751953125), (12.1962890625, 0)],
                 [0..<2, 0..<2, 2..<3]),
                ("x e\u{301}\u{323} z", [92, 4, 1107, 169, 4, 94], [0, 1, 2, 4, 5, 6],
                 [11.41015625, 5.705078125, 12.1962890625, 0, 5.705078125, 11.41015625], [(0, 0), (11.41015625, 0), (17.115234375, 0), (28.261474609375, -23.6109375), (29.3115234375, 0), (35.0166015625, 0)],
                 [0..<1, 1..<2, 2..<5, 2..<5, 5..<6, 6..<7]),
                ("e\u{301}\u{323}e\u{301}\u{323}", [1107, 169, 1107, 169], [0, 2, 3, 5],
                 [12.1962890625, 0, 12.1962890625, 0], [(0, 0), (11.146240234375, -23.6109375), (12.1962890625, 0), (23.342529296875, -23.6109375)],
                 [0..<3, 0..<3, 3..<6, 3..<6]),
                ("e\u{301}\u{323} q\u{301}\u{323}", [1107, 169, 4, 85, 169, 173], [0, 2, 3, 4, 5, 6],
                 [12.1962890625, 0, 5.705078125, 13.302490234375, 0, 0], [(0, 0), (11.146240234375, -23.6109375), (12.1962890625, 0), (17.9013671875, 0), (29.485595703125, 0.8580078124999999), (31.203857421875, -5.15478515625)],
                 [0..<3, 0..<3, 3..<4, 4..<7, 4..<7, 4..<7]),
                ("x\u{323}\u{301}e\u{301}\u{323}", [92, 173, 169, 1107, 169], [0, 1, 2, 3, 5],
                 [11.41015625, 0, 0, 12.1962890625, 0], [(0, 0), (12.471435546875, -0.8692382812499999), (10.753173828125, 0.6333984374999981), (11.41015625, 0), (22.556396484375, -23.6109375)],
                 [0..<3, 0..<3, 0..<3, 3..<6, 3..<6]),
                ("\u{e9}\u{300}\u{323}", [703, 168, 173], [0, 1, 2],
                 [13.38671875, 0, 0], [(0, 0), (13.38671875, 5.345703125), (12.864501953125, -0.70751953125)],
                 [0..<3, 0..<3, 0..<3]),
                ("\u{1eb9}\u{301}\u{323}", [1107, 169, 173], [0, 1, 2],
                 [12.864501953125, 0, 0], [(0, 0), (11.146240234375, 0.8580078124999999), (12.864501953125, -4.41357421875)],
                 [0..<3, 0..<3, 0..<3]),
            ]),
            (true, true, [
                ("x\u{301}\u{323}", [92, 169, 173], [0, 1, 2],
                 [12.471435546875, 0, 0], [(0, 0), (10.753173828125, 0.6333984374999999), (12.471435546875, -0.48291015625)],
                 [0..<3, 0..<3, 0..<3]),
                ("e\u{301}\u{323}", [703, 173], [0, 2],
                 [12.864501953125, 0], [(0, 0), (12.864501953125, -0.70751953125)],
                 [0..<3, 0..<3]),
                ("q\u{301}\u{323}", [85, 169, 173], [0, 1, 2],
                 [13.302490234375, 0, 0], [(0, 0), (11.584228515625, 0.8580078124999999), (13.302490234375, -5.15478515625)],
                 [0..<3, 0..<3, 0..<3]),
                ("q\u{323}\u{301}", [85, 173, 169], [0, 1, 2],
                 [13.302490234375, 0, 0], [(0, 0), (13.302490234375, -5.54111328125), (11.584228515625, 0.8580078124999981)],
                 [0..<3, 0..<3, 0..<3]),
                ("e\u{323}\u{301}", [1107, 169], [0, 2],
                 [12.1962890625, 0], [(0, 0), (11.146240234375, 0.8580078124999999)],
                 [0..<3, 0..<3]),
                ("\u{e9}\u{323}", [703, 173], [0, 1],
                 [12.864501953125, 0], [(0, 0), (12.864501953125, -0.70751953125)],
                 [0..<2, 0..<2]),
                ("e\u{301}\u{323}\u{300}", [703, 173, 168], [0, 2, 3],
                 [13.38671875, 0, 0], [(0, 0), (12.864501953125, -0.70751953125), (13.38671875, 5.345703125)],
                 [0..<4, 0..<4, 0..<4]),
                ("e\u{323}\u{301}\u{300}", [1107, 169, 168], [0, 2, 3],
                 [13.38671875, 0, 0], [(0, 0), (11.146240234375, 0.8580078124999999), (13.38671875, 6.203710937499999)],
                 [0..<4, 0..<4, 0..<4]),
                ("\u{e9}\u{323}x", [703, 173, 92], [0, 1, 2],
                 [12.1962890625, 0, 11.41015625], [(0, 0), (12.864501953125, -0.70751953125), (12.1962890625, 0)],
                 [0..<2, 0..<2, 2..<3]),
                ("e\u{301}\u{323}e\u{301}\u{323}", [703, 173, 703, 173], [0, 2, 3, 5],
                 [12.1962890625, 0, 12.864501953125, 0], [(0, 0), (12.864501953125, -0.70751953125), (12.1962890625, 0), (25.060791015625, -0.70751953125)],
                 [0..<3, 0..<3, 3..<6, 3..<6]),
                ("x\u{323}\u{301}e\u{301}\u{323}", [92, 173, 169, 703, 173], [0, 1, 2, 3, 5],
                 [11.41015625, 0, 0, 12.864501953125, 0], [(0, 0), (12.471435546875, -0.8692382812499999), (10.753173828125, 0.6333984374999981), (11.41015625, 0), (24.274658203125, -0.70751953125)],
                 [0..<3, 0..<3, 0..<3, 3..<6, 3..<6]),
                ("\u{e9}\u{300}\u{323}", [703, 168, 173], [0, 1, 2],
                 [13.38671875, 0, 0], [(0, 0), (13.38671875, 5.345703125), (12.864501953125, -0.70751953125)],
                 [0..<3, 0..<3, 0..<3]),
            ]),
        ]
        for (removePositioning, omitComposedMapping, rows) in groups {
            let cmap: [UInt32: UInt32]? = omitComposedMapping ?
                [0x61: 69, 0x65: 73, 0x71: 85, 0x78: 92,
                 0x301: 169, 0x300: 168, 0x323: 173, 0xe9: 703] : nil
            let data = try Self.variant(Self.robotoData(), removePositioning: removePositioning,
                                        characterMap: cmap)
            let font = try XCTUnwrap(Font(data: data))
            for dpi: UInt32 in [72, 144] {
                font.setPointSize(23, dpi: (dpi, dpi))
                for (text, indices, source, advances, positions, ranges) in rows {
                    let shaped = try XCTUnwrap(font.shape(text))
                    XCTAssertEqual(shaped.glyphs.map(\.index), indices, text)
                    XCTAssertEqual(shaped.glyphs.map(\.sourceIndex), source, text)
                    XCTAssertEqual(shaped.glyphs.map(\.sourceRange), ranges, text)
                    Self.check(shaped, scale: Double(dpi) / 72,
                               advances: advances, positions: positions)
                }
            }
        }
    }

    // ASSERTIONS textCombiningGeometry27Observed
    func testTableAttachmentsPreserveConnectedMarkGroups() throws {
        let original = try Self.robotoData()
        let cases: [(Bool, Bool, [Double], [(Double, Double)])] = [
            (false, false, [13.072265625, 0, 0],
             [(0, 0), (12.38720703125, 0), (11.98291015625, 3.94189453125)]),
            (true, false, [13.072265625, 0, 0],
             [(0, 0), (13.072265625, 0), (12.66796875, 3.94189453125)]),
            (false, true, [13.82470703125, 0, 0],
             [(0, 0), (11.584228515625, 0.8580078125), (13.82470703125, 6.2037109375)]),
        ]
        for (removeMark, removePositioning, advances, positions) in cases {
            let data = try Self.variant(original, removeMark: removeMark, removePositioning: removePositioning)
            let font = try XCTUnwrap(Font(data: data))
            for dpi: UInt32 in [72, 144] {
                font.setPointSize(23, dpi: (dpi, dpi))
                let shaped = try XCTUnwrap(font.shape("q\u{301}\u{300}"))
                Self.check(shaped, scale: Double(dpi) / 72, advances: advances, positions: positions)
            }
        }
    }

    // ASSERTIONS textCombiningGeometry27Observed
    func testMissingHeightMetricsUseCharacterPairsBeforeComposition() throws {
        let original = try Self.robotoData()
        let cases: [(Bool, Bool, Double, Double)] = [
            (true, false, 0.88046875, 6.226171875),
            (false, true, 0.8580078125, 6.2177490234375),
            (true, true, 0.88046875, 6.2402099609375),
        ]
        for (zeroX, zeroCap, acuteY, graveY) in cases {
            let data = try Self.variant(original, removePositioning: true, zeroX: zeroX, zeroCap: zeroCap)
            let font = try XCTUnwrap(Font(data: data))
            for dpi: UInt32 in [72, 144] {
                font.setPointSize(23, dpi: (dpi, dpi))
                for suffix in ["", "x"] {
                    let shaped = try XCTUnwrap(font.shape("q\u{301}\u{300}" + suffix))
                    let advance = suffix.isEmpty ? 13.82470703125 : 13.072265625
                    let advances = [advance, 0, 0] + (suffix.isEmpty ? [] : [11.41015625])
                    let positions = [(0.0, 0.0), (11.584228515625, acuteY), (13.82470703125, graveY)] +
                        (suffix.isEmpty ? [] : [(13.072265625, 0)])
                    Self.check(shaped, scale: Double(dpi) / 72, advances: advances, positions: positions)
                }
            }
        }
    }

    // ASSERTIONS textCombiningGeometry27Observed
    func testPartialAndMissingHeightCharactersKeepTheirMetricOwners() throws {
        let original = try Self.robotoData()
        let cases: [(Bool, Bool, Double, Double)] = [
            (true, false, 1.27802734375, 6.62373046875),
            (false, true, -1.1595458984375, 2.554931640625),
        ]
        for (mapsX, zeroAscent, acuteY, graveY) in cases {
            var characters: [UInt32: UInt32] = [0x71: 85, 0x301: 169, 0x300: 168]
            if mapsX { characters[0x78] = 92 }
            let data = try Self.variant(original, removePositioning: true, zeroX: true,
                                        zeroCap: true, zeroAscent: zeroAscent, characterMap: characters)
            let font = try XCTUnwrap(Font(data: data))
            for dpi: UInt32 in [72, 144] {
                font.setPointSize(23, dpi: (dpi, dpi))
                Self.check(try XCTUnwrap(font.shape("q\u{301}\u{300}")), scale: Double(dpi) / 72,
                    advances: [13.82470703125, 0, 0],
                    positions: [(0, 0), (11.584228515625, acuteY), (13.82470703125, graveY)])
            }
        }
    }

    // ASSERTIONS fontCapHeight27Observed textCombiningGeometry27Observed
    func testDesignCapHeightRetainsTableAndMissingCharacterOwners() throws {
        let original = try Self.robotoData()
        let cases: [(Bool, Bool, Bool, [UInt32: UInt32]?, Int)] = [
            (false, false, false, nil, 1456),
            (false, true, false, nil, 1466),
            (true, true, false, nil, 1466),
            (true, true, false, [0x78: 92], 1456),
            (true, true, false, [:], 1688),
            (true, true, true, [:], 0),
        ]
        for (zeroX, zeroCap, zeroAscent, characters, expected) in cases {
            let data = try Self.variant(original, zeroX: zeroX, zeroCap: zeroCap,
                                        zeroAscent: zeroAscent, characterMap: characters)
            let font = try XCTUnwrap(Font(data: data))
            for dpi: Font.DPI in [(72, 72), (96, 144), (216, 96)] {
                for size: CGFloat in [13, 23.375, 31.375] {
                    font.setPointSize(size, dpi: dpi)
                    let before = font.baseMetrics
                    let snapshot = try XCTUnwrap(font.designMetrics)
                    XCTAssertEqual(snapshot.capHeight, expected)
                    for _ in 0..<3 { XCTAssertEqual(font.designMetrics, snapshot) }
                    XCTAssertEqual(font.baseMetrics.ascender, before.ascender)
                    XCTAssertEqual(font.baseMetrics.descender, before.descender)
                    XCTAssertEqual(font.baseMetrics.height, before.height)
                    XCTAssertEqual(font.pointSize, size)
                }
            }
        }
    }

    private static func check(_ shaped: Font.ShapedText, scale: Double,
                              advances: [Double], positions: [(Double, Double)],
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(shaped.glyphs.count, positions.count, file: file, line: line)
        var pen = 0.0
        for (index, glyph) in shaped.glyphs.enumerated() where index < positions.count {
            XCTAssertEqual(glyph.advance.width / scale, advances[index], accuracy: 1e-8, file: file, line: line)
            XCTAssertEqual((pen + glyph.offset.x) / scale, positions[index].0, accuracy: 1e-8, file: file, line: line)
            XCTAssertEqual(glyph.offset.y / scale, positions[index].1, accuracy: 1e-8, file: file, line: line)
            pen += glyph.advance.width
        }
    }

    private static func robotoData() throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"))
    }

    private static func variant(_ original: Data, removeMark: Bool = false,
                                removePositioning: Bool = false, zeroX: Bool = false,
                                zeroCap: Bool = false, zeroAscent: Bool = false,
                                characterMap: [UInt32: UInt32]? = nil,
                                substitutions: Data? = nil) throws -> Data {
        var data = original
        func read(_ offset: Int, _ count: Int) -> Int {
            data[offset..<(offset + count)].reduce(0) { ($0 << 8) | Int($1) }
        }
        func write(_ value: UInt32, _ offset: Int) {
            for index in 0..<4 { data[offset + index] = UInt8(truncatingIfNeeded: value >> ((3 - index) * 8)) }
        }
        let records = stride(from: 12, to: 12 + read(4, 2) * 16, by: 16)
        var tables: [String: Int] = [:]
        for record in records { tables[String(decoding: data[record..<(record + 4)], as: UTF8.self)] = record }
        let os2 = read(try XCTUnwrap(tables["OS/2"]) + 8, 4)
        if zeroX { data[os2 + 86] = 0; data[os2 + 87] = 0 }
        if zeroCap { data[os2 + 88] = 0; data[os2 + 89] = 0 }
        if zeroAscent {
            let hhea = read(try XCTUnwrap(tables["hhea"]) + 8, 4)
            for offset in [os2 + 68, os2 + 74, hhea + 4] { data[offset] = 0; data[offset + 1] = 0 }
        }
        if let characterMap {
            let record = try XCTUnwrap(tables["cmap"])
            let offset = read(record + 8, 4), length = read(record + 12, 4)
            XCTAssertGreaterThanOrEqual(length, 28 + characterMap.count * 12)
            data.replaceSubrange(offset..<(offset + length), with: repeatElement(UInt8(0), count: length))
            write(1, offset)
            write(0x0003_000a, offset + 4)
            write(12, offset + 8)
            write(0x000c_0000, offset + 12)
            write(UInt32(16 + characterMap.count * 12), offset + 16)
            write(UInt32(characterMap.count), offset + 24)
            for (index, pair) in characterMap.sorted(by: { $0.key < $1.key }).enumerated() {
                let entry = offset + 28 + index * 12
                write(pair.key, entry); write(pair.key, entry + 4); write(pair.value, entry + 8)
            }
        }
        let gposRecord = try XCTUnwrap(tables["GPOS"])
        let gpos = read(gposRecord + 8, 4)
        if removeMark {
            let features = gpos + read(gpos + 6, 2)
            for index in 0..<read(features, 2) {
                let offset = features + 2 + index * 6
                if String(decoding: data[offset..<(offset + 4)], as: UTF8.self) == "mark" {
                    data.replaceSubrange(offset..<(offset + 4), with: "xxxx".utf8)
                }
            }
        }
        if removePositioning { data.replaceSubrange(gposRecord..<(gposRecord + 4), with: "GPOR".utf8) }
        if let substitutions {
            let record = try XCTUnwrap(tables["GSUB"])
            let offset = read(record + 8, 4), length = read(record + 12, 4)
            XCTAssertLessThanOrEqual(substitutions.count, length)
            data.replaceSubrange(offset..<(offset + length),
                with: substitutions + Data(repeating: 0, count: length - substitutions.count))
        }
        let head = read(try XCTUnwrap(tables["head"]) + 8, 4)
        write(0, head + 8)
        func checksum(_ offset: Int, _ count: Int) -> UInt32 {
            var result: UInt32 = 0
            for start in stride(from: 0, to: count, by: 4) {
                var word: UInt32 = 0
                for byte in 0..<4 {
                    word = (word << 8) | (start + byte < count ? UInt32(data[offset + start + byte]) : 0)
                }
                result &+= word
            }
            return result
        }
        for record in records { write(checksum(read(record + 8, 4), read(record + 12, 4)), record + 4) }
        write(0xb1b0_afba &- checksum(0, data.count), head + 8)
        return data
    }

    // ASSERTIONS textCombiningGeometry27Observed
    func testUnattachedCombiningMarksUseBaseGeometry() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/NotoSansKR/NotoSansKR-VariableFont_wght.ttf")
        let font = try XCTUnwrap(Font(data: Data(contentsOf: file)))
        XCTAssertTrue(font.setVariationCoordinates([0x7767_6874: 100]))
        let cases: [(String, [Double], [(Double, Double)])] = [
            ("q\u{301}\u{300}", [13.685, 0, 0], [(0, 0), (-0.0575, 4.8438), (-0.0575, 14.771175)]),
            ("q\u{300}\u{301}", [13.685, 0, 0], [(0, 0), (-0.0575, 5.5108), (-0.0575, 13.437175)]),
            ("q\u{301}x", [13.685, 0, 9.982], [(0, 0), (-0.0575, 4.8438), (13.685, 0)]),
            ("q\u{301}", [13.685, 0], [(0, 0), (-0.0575, 4.8438)]),
            ("가\u{301}\u{300} 나", [21.16, 0, 0, 5.06, 21.16],
             [(0, 0), (3.68, 10.801375), (3.68, 20.72875), (21.16, 0), (26.22, 0)]),
            ("a\u{20dd}", [23.23, 0], [(4.692, 0), (22.08, -2.6795)]),
            ("f\u{301}fi", [6.417, 0, 12.052], [(0, 0), (-3.6915, 10.594375), (6.417, 0)]),
            ("A\u{301}x", [13.202, 9.982], [(0, 0), (13.202, 0)]),
        ]
        for dpi: UInt32 in [72, 144] {
            font.setPointSize(23, dpi: (dpi, dpi))
            let scale = Double(dpi) / 72
            for (text, advances, positions) in cases {
                let shaped = try XCTUnwrap(font.shape(text))
                XCTAssertEqual(shaped.glyphs.count, positions.count, text)
                var pen = 0.0
                for (index, glyph) in shaped.glyphs.enumerated() where index < positions.count {
                    XCTAssertEqual(glyph.advance.width / scale, advances[index], accuracy: 1e-8, text)
                    XCTAssertEqual((pen + glyph.offset.x) / scale, positions[index].0, accuracy: 1e-8, text)
                    XCTAssertEqual(glyph.offset.y / scale, positions[index].1, accuracy: 1e-8, text)
                    pen += glyph.advance.width
                }
            }
        }
    }

    // ASSERTIONS textCombiningRunSlices27Observed
    func testIndividualGlyphIndicesRetainAtomicSourceRanges() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let file = root.appendingPathComponent("Sources/VUI/Resources/Fonts/NotoSansKR/NotoSansKR-VariableFont_wght.ttf")
        let font = try XCTUnwrap(Font(data: Data(contentsOf: file)))
        XCTAssertTrue(font.setVariationCoordinates([0x7767_6874: 100]))
        let cases: [(String, [UInt32], [Int], [Range<Int>])] = [
            ("가\u{301} 나", [10255, 253, 1, 11431], [0, 1, 2, 3], [0..<2, 0..<2, 2..<3, 3..<4]),
            ("가\u{301} 나", [10255, 253, 1, 11431], [0, 2, 3, 4], [0..<3, 0..<3, 3..<4, 4..<5]),
            ("가\u{301}\u{300} 나", [10255, 253, 252, 1, 11431], [0, 1, 2, 3, 4],
             [0..<3, 0..<3, 0..<3, 3..<4, 4..<5]),
            ("q\u{301}x", [82, 253, 89], [0, 1, 2], [0..<2, 0..<2, 2..<3]),
            ("e\u{301}x", [167, 89], [0, 2], [0..<2, 2..<3]),
            ("ffi", [21582], [0], [0..<3]),
            ("ffi\u{301}", [21579, 171], [0, 2], [0..<2, 2..<4]),
            ("f\u{301}fi", [71, 253, 21580], [0, 1, 2], [0..<2, 0..<2, 2..<4]),
        ]
        for dpi: UInt32 in [72, 144] {
            font.setPointSize(23, dpi: (dpi, dpi))
            for (text, glyphs, indices, ranges) in cases {
                let shaped = try XCTUnwrap(font.shape(text))
                XCTAssertEqual(shaped.glyphs.map(\.index), glyphs, text)
                XCTAssertEqual(shaped.glyphs.map(\.sourceIndex), indices, text)
                XCTAssertEqual(shaped.glyphs.map(\.sourceRange), ranges, text)
                XCTAssertTrue(shaped.glyphs.allSatisfy { $0.sourceRange.contains($0.sourceIndex) }, text)
            }
        }
    }
}
