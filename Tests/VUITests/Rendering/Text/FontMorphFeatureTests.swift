import Foundation
import XCTest
import VVD
@testable import VUI

final class FontMorphFeatureTests: XCTestCase {
    private func request(_ tag: String, _ value: UInt32) -> TypefaceShapingFeature {
        TypefaceShapingFeature(tag: tag, value: value)!
    }

    // ASSERTIONS fontFeatureMorph27Observed
    func testMorphSettingsUseSelectedDefaultsAndSparseSelectors() throws {
        for enabled in [false, true] {
            let font = try fixture(type: 37, selectors: [0, 1, 2], enabled: enabled)
            let catalog = font.featureCatalog
            XCTAssertEqual(catalog.select([request("smcp", 1)]).count, enabled ? 0 : 1)
            XCTAssertEqual(catalog.select([request("smcp", 0)]).count, enabled ? 1 : 0)
            XCTAssertEqual(catalog.select([request("smcp", 0)]).first?.selector, enabled ? 0 : nil)
            XCTAssertEqual(catalog.select([request("smcp", 1), request("smcp", 0)]).count, enabled ? 1 : 0)
            XCTAssertEqual(catalog.select([request("smcp", 0), request("smcp", 1)]).count, enabled ? 0 : 1)
            let alternate = try XCTUnwrap(catalog.select([request("pcap", 2)]).first)
            XCTAssertEqual(alternate.type, 37)
            XCTAssertEqual(alternate.selector, 2)
            XCTAssertEqual(alternate.value, 2)
            XCTAssertTrue(catalog.select([request("ss01", 1)]).isEmpty)

            let ligatures = try fixture(type: 1, selectors: [2], enabled: enabled).featureCatalog
            XCTAssertEqual(ligatures.select([request("liga", 1)]).count, enabled ? 0 : 1)
            XCTAssertEqual(ligatures.select([request("liga", 0)]).first?.selector, enabled ? 3 : nil)
        }
        let catalog = try fixture(type: 17, selectors: [0, 1, 3]).featureCatalog
        for value: UInt32 in [2, 4, 65535, .max] {
            XCTAssertTrue(catalog.select([request("aalt", value)]).isEmpty)
            XCTAssertEqual(catalog.select([request("aalt", 1), request("aalt", value)]).first?.selector, 1)
        }
        XCTAssertTrue(catalog.select([request("aalt", 1), request("aalt", 65536)]).isEmpty)
        let narrowed = try XCTUnwrap(catalog.select([request("aalt", 65539)]).first)
        XCTAssertEqual(narrowed.selector, 3)
        XCTAssertEqual(narrowed.value, 65539)
    }

    // ASSERTIONS fontFeatureMorph27Observed
    func testMorphSubstitutionsKeepSourceSlotsAndCallSiteOverrides() throws {
        let cases: [(UInt16, [UInt16], Bool, [(String, UInt32)], UInt32)] = [
            (37, [0, 1, 2], false, [("smcp", 1)], 37),
            (37, [0, 1, 2], false, [("smcp", 2)], 37),
            (37, [0, 1, 2], false, [("pcap", 1)], 38),
            (37, [0, 1, 2], false, [("smcp", 1), ("pcap", 1)], 38),
            (37, [0, 1, 2], true, [("smcp", 0)], 69),
            (37, [0, 1, 2], true, [("smcp", 0), ("smcp", 1)], 37),
            (37, [0, 1, 2], false, [("smcp", 1), ("smcp", 0)], 69),
            (17, [0, 1, 3], false, [("aalt", 1), ("aalt", 2)], 37),
            (17, [0, 1, 3], false, [("aalt", 3)], 38),
            (17, [0, 1, 3], false, [("aalt", 65539)], 38),
            (1, [2], false, [("liga", 1)], 37),
            (1, [2], true, [("liga", 0)], 69),
        ]
        for (type, selectors, enabled, values, glyph) in cases {
            let font = try fixture(type: type, selectors: selectors, enabled: enabled)
            let face = ShapingFeatureTypeface(VectorTypeface(font: font), features: values.map(request))
            let result = try XCTUnwrap(face.shape("aAffi123", direction: .leftToRight, language: nil, features: []))
            XCTAssertEqual(result.glyphs.map(\.index), [glyph, 37, 74, 74, 77, 21, 22, 23], "\(values)")
            XCTAssertEqual(result.glyphs.map(\.sourceIndex), Array(0..<8))
            XCTAssertEqual(result.glyphs.map(\.sourceRange), (0..<8).map { $0..<($0 + 1) })
        }
        let font = try fixture(type: 37, selectors: [0, 1, 2])
        let selected = ShapingFeatureTypeface(VectorTypeface(font: font), features: [request("smcp", 1)])
        let perCall = request("smcp", 0)
        XCTAssertEqual(selected.shape("a", direction: .leftToRight, language: nil, features: [perCall])?.glyphs.first?.index, 69)
        let ranged = TypefaceShapingFeature(tag: perCall.tag, value: 0, range: 0..<1)
        let partial = try XCTUnwrap(selected.shape("aa", direction: .leftToRight, language: nil, features: [ranged]))
        XCTAssertEqual(partial.glyphs.map(\.index), [69, 37])
        XCTAssertEqual(partial.glyphs.map(\.sourceIndex), [0, 1])
        let outer = TypefaceShapingFeature(tag: perCall.tag, value: 0, range: 0..<3)
        let inner = TypefaceShapingFeature(tag: perCall.tag, value: 1, range: 1..<2)
        let overlap = try XCTUnwrap(selected.shape("aaaa", direction: .leftToRight, language: nil, features: [outer, inner]))
        XCTAssertEqual(overlap.glyphs.map(\.index), [69, 37, 69, 37])
        XCTAssertEqual(overlap.glyphs.map(\.sourceIndex), [0, 1, 2, 3])
        let nested = ShapingFeatureTypeface(selected, features: [request("smcp", 0)])
        XCTAssertEqual(nested.shape("a", direction: .leftToRight, language: nil, features: [])?.glyphs.first?.index, 69)
    }

    // ASSERTIONS fontFeatureMorph27Observed
    func testMorphAndOpenTypeCatalogsKeepSelectedTableOwner() throws {
        let unused = try fixture(type: 37, selectors: [0, 1, 2], morph: false)
        XCTAssertTrue(unused.featureCatalog.select([request("smcp", 1)]).isEmpty)
        let openType = try fixture(type: 37, selectors: [0, 1, 2], morph: false, openType: true)
        XCTAssertEqual(openType.featureCatalog.select([request("ss01", 1)]).first?.type, 35)
        let mixed = try fixture(type: 37, selectors: [0, 1, 2], openType: true)
        XCTAssertTrue(mixed.featureCatalog.select([request("ss01", 1)]).isEmpty)
        XCTAssertEqual(mixed.featureCatalog.select([request("smcp", 1)]).first?.selector, 1)
    }

    private func fixture(type: UInt16, selectors: [UInt16], enabled: Bool = false,
                         morph: Bool = true, openType: Bool = false) throws -> VVD.Font {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let original = try Data(contentsOf: root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"))
        func u16(_ value: UInt16) -> Data { Data([UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]) }
        func u32(_ value: UInt32) -> Data { u16(UInt16(truncatingIfNeeded: value >> 16)) + u16(UInt16(truncatingIfNeeded: value)) }
        func read(_ offset: Int, _ count: Int) -> Int { original[offset..<(offset + count)].reduce(0) { $0 << 8 | Int($1) } }
        var tables: [String: Data] = [:]
        for at in stride(from: 12, to: 12 + 16 * read(4, 2), by: 16) {
            let tag = String(decoding: original[at..<(at + 4)], as: UTF8.self)
            let offset = read(at + 8, 4), count = read(at + 12, 4)
            if openType || (tag != "GSUB" && tag != "GPOS") { tables[tag] = Data(original[offset..<(offset + count)]) }
        }
        let exclusive = type != 1
        var feature = u32(0x10000) + u16(1) + u16(0) + u32(0)
        feature += u16(type) + u16(UInt16(selectors.count)) + u32(24) + u16(exclusive ? 0x8000 : 0) + u16(256)
        for (index, selector) in selectors.enumerated() { feature += u16(selector) + u16(UInt16(257 + index)) }
        tables["feat"] = feature
        if morph {
            var entries = Data(), subtables = Data()
            let active = exclusive ? Array(selectors.dropFirst()) : selectors
            let mask = UInt32(1 << active.count) - 1
            entries += u16(type) + u16(exclusive ? 0 : 3) + u32(0) + u32(~mask)
            for (index, selector) in active.enumerated() {
                let flag = UInt32(1 << index)
                entries += u16(type) + u16(selector) + u32(flag) + u32(~(mask & ~flag))
                subtables += u32(20) + u32(4) + u32(flag) + u16(8) + u16(69) + u16(1) + u16(UInt16(37 + index))
            }
            entries += u16(0) + u16(1) + u32(0) + u32(0)
            var table = u32(0x20000) + u32(1) + u32(enabled ? 1 : 0)
            table += u32(UInt32(16 + entries.count + subtables.count)) + u32(UInt32(active.count + 2)) + u32(UInt32(active.count))
            tables["morx"] = table + entries + subtables
        }
        tables["head"]!.replaceSubrange(8..<12, with: u32(0))
        func checksum(_ data: Data) -> UInt32 {
            stride(from: 0, to: data.count, by: 4).reduce(0) { total, at in
                total &+ (0..<4).reduce(UInt32(0)) { word, index in
                    word << 8 | (at + index < data.count ? UInt32(data[at + index]) : 0)
                }
            }
        }
        let power = 1 << (Int.bitWidth - tables.count.leadingZeroBitCount - 1)
        var data = u32(0x10000) + u16(UInt16(tables.count)) + u16(UInt16(power * 16))
        data += u16(UInt16(power.trailingZeroBitCount)) + u16(UInt16((tables.count - power) * 16))
        data += Data(repeating: 0, count: tables.count * 16)
        var head = 0
        for (index, pair) in tables.sorted(by: { $0.key < $1.key }).enumerated() {
            let record = Data(pair.key.utf8) + u32(checksum(pair.value)) + u32(UInt32(data.count)) + u32(UInt32(pair.value.count))
            data.replaceSubrange((12 + index * 16)..<(28 + index * 16), with: record)
            if pair.key == "head" { head = data.count }
            data += pair.value
            while data.count % 4 != 0 { data.append(0) }
        }
        data.replaceSubrange((head + 8)..<(head + 12), with: u32(0xb1b0_afba &- checksum(data)))
        let font = try XCTUnwrap(VVD.Font(data: data))
        font.setPointSize(23, dpi: (72, 72))
        return font
    }
}
