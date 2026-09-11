import Dispatch
import Foundation
import Synchronization
import XCTest
import VVD

final class FontDesignMetricsTests: XCTestCase {
    private static let roboto = "Roboto/Roboto-VariableFont_wdth,wght.ttf"
    private static let weightTag: UInt32 = 0x7767_6874

    private static func resource(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/VUI/Resources/Fonts")
            .appendingPathComponent(name)
    }

    func testDesignUnitsPreserveFractionalLayoutInputsAndRoundedRasterMetrics() throws {
        let font = try XCTUnwrap(Font(path: Self.resource(Self.roboto).path))
        font.setPointSize(13, dpi: (72, 72))
        let glyph = try XCTUnwrap(font.glyphMetrics(for: "A"))
        let metrics = try XCTUnwrap(font.designMetrics)
        XCTAssertEqual(metrics.unitsPerEM, 2048)
        XCTAssertEqual([metrics.ascender, metrics.descender, metrics.height, metrics.lineGap],
                       [1900, -500, 2400, 0])
        let scale = CGFloat(13) / CGFloat(metrics.unitsPerEM)
        XCTAssertEqual(CGFloat(metrics.ascender) * scale, 12.060546875)
        XCTAssertEqual(CGFloat(metrics.descender) * scale, -3.173828125)
        XCTAssertEqual(CGFloat(metrics.height) * scale, 15.234375)
        XCTAssertEqual(font.baseMetrics.ascender, 13)
        XCTAssertEqual(font.baseMetrics.descender, -4)
        XCTAssertEqual(font.baseMetrics.height, 15)
        for _ in 0..<10 { XCTAssertEqual(font.designMetrics, metrics) }
        let after = try XCTUnwrap(font.glyphMetrics(for: "A"))
        XCTAssertEqual(after.index, glyph.index)
        XCTAssertEqual(after.advance, glyph.advance)
        XCTAssertEqual(after.bearing, glyph.bearing)
        XCTAssertEqual(after.size, glyph.size)
    }

    func testDesignMetricsAreIndependentOfPointSizeAndRasterDPI() throws {
        let font = try XCTUnwrap(Font(path: Self.resource(Self.roboto).path))
        let original = try XCTUnwrap(font.designMetrics)
        for size: CGFloat in [1, 11.25, 13.5, 24, 64] {
            for dpi: Font.DPI in [(72, 72), (96, 144), (144, 96)] {
                font.setPointSize(size, dpi: dpi)
                XCTAssertEqual(font.designMetrics, original)
            }
        }
    }

    func testBackendMetricSelectionAndSignedGap() throws {
        // Deliberately distinct tables prove which metrics the backend selects.
        let cases: [(Bool, [Int16], [Int16], [Int])] = [
            (false, [1800, -400, -100], [1600, -600, 50], [1800, -400, 2100, -100]),
            (true,  [1800, -400, -100], [1600, -600, 50], [1600, -600, 2250, 50]),
            (false, [0, 0, 0], [1600, -600, 50], [1600, -600, 2250, 50]),
            (false, [0, 0, 0], [0, 0, 0], [2100, -700, 2800, 0]),
        ]
        for (useTypographic, horizontal, typographic, expected) in cases {
            let data = try Self.fixture(horizontal: horizontal, typographic: typographic,
                                        useTypographic: useTypographic)
            let font = try XCTUnwrap(Font(data: data))
            let metrics = try XCTUnwrap(font.designMetrics)
            XCTAssertEqual([metrics.ascender, metrics.descender, metrics.height, metrics.lineGap], expected)
        }
        let data = try Self.fixture(removeOS2: true)
        let font = try XCTUnwrap(Font(data: data))
        let metrics = try XCTUnwrap(font.designMetrics)
        XCTAssertEqual([metrics.ascender, metrics.descender, metrics.height, metrics.lineGap],
                       [1800, -400, 2100, -100])
    }

    func testFreshVariationAdjustmentIsReflectedWithoutChangingEarlierSnapshot() throws {
        let data = try Self.fixture(variableMetrics: true)
        // Each independent face changes coordinates once; repeated MVAR changes
        // are a separate backend boundary.
        for (weight, expected): (CGFloat, [Int]) in [
            (650, [1850, -425, 2160, -115]),
            (900, [1900, -450, 2220, -130]),
        ] {
            let font = try XCTUnwrap(Font(data: data))
            let original = try XCTUnwrap(font.designMetrics)
            XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: weight]))
            let adjusted = try XCTUnwrap(font.designMetrics)
            XCTAssertEqual([adjusted.ascender, adjusted.descender, adjusted.height, adjusted.lineGap], expected)
            XCTAssertEqual([original.ascender, original.descender, original.height, original.lineGap],
                           [1800, -400, 2100, -100])
        }
    }

    func testSnapshotsOutliveFileAndMemoryFontOwners() throws {
        func snapshot(_ data: Data) throws -> Font.DesignMetrics {
            let font = try XCTUnwrap(Font(data: data))
            return try XCTUnwrap(font.designMetrics)
        }
        var data = try Data(contentsOf: Self.resource(Self.roboto))
        let fromMemory = try snapshot(data)
        data.resetBytes(in: data.startIndex..<data.endIndex)
        let fromFile: Font.DesignMetrics = try {
            let font = try XCTUnwrap(Font(path: Self.resource(Self.roboto).path))
            return try XCTUnwrap(font.designMetrics)
        }()
        XCTAssertEqual(fromMemory, fromFile)
        XCTAssertEqual(Set([fromMemory, fromFile]).count, 1)
    }

    func testColorBitmapAndScalableEmojiHaveDifferentMetricCapabilities() throws {
        let bitmap = try XCTUnwrap(Font(path: Self.resource("NotoColorEmoji/NotoColorEmoji.ttf").path))
        XCTAssertFalse(bitmap.isScalable)
        XCTAssertNil(bitmap.designMetrics)
        for size: CGFloat in [13, 32, 64] {
            bitmap.setPointSize(size, dpi: (72, 72))
            XCTAssertNil(bitmap.designMetrics)
            XCTAssertGreaterThan(bitmap.baseMetrics.height, 0)
            XCTAssertGreaterThan(bitmap.bitmapScale, 0)
        }
        for name in ["NotoColorEmoji/NotoColorEmoji-Regular.ttf", "NotoEmoji/NotoEmoji-VariableFont_wght.ttf"] {
            let font = try XCTUnwrap(Font(path: Self.resource(name).path))
            XCTAssertTrue(font.isScalable)
            XCTAssertGreaterThan(try XCTUnwrap(font.designMetrics).unitsPerEM, 0)
        }
    }

    func testSnapshotReadsShareTheSizeMutationLock() throws {
        let font = try XCTUnwrap(Font(path: Self.resource(Self.roboto).path))
        let original = try XCTUnwrap(font.designMetrics)
        let mismatches = Mutex(0)
        DispatchQueue.concurrentPerform(iterations: 128) { index in
            if index.isMultiple(of: 2) {
                font.setPointSize(CGFloat(9 + index % 24), dpi: (72, 144))
            } else if font.designMetrics != original {
                mismatches.withLock { $0 += 1 }
            }
        }
        XCTAssertEqual(mismatches.withLock { $0 }, 0)
    }

    private static func fixture(horizontal: [Int16] = [1800, -400, -100],
                                typographic: [Int16] = [1600, -600, 50],
                                useTypographic: Bool = false,
                                removeOS2: Bool = false,
                                variableMetrics: Bool = false) throws -> Data {
        let source = try Data(contentsOf: resource(roboto))
        var tables: [String: Data] = [:]
        for index in 0..<Int(read16(source, 4)) {
            let record = 12 + index * 16
            let tag = String(decoding: source[record..<record + 4], as: UTF8.self)
            let offset = Int(read32(source, record + 8))
            let length = Int(read32(source, record + 12))
            tables[tag] = source.subdata(in: offset..<offset + length)
        }
        for index in 0..<3 {
            write16(UInt16(bitPattern: horizontal[index]), &tables["hhea"]!, 4 + index * 2)
            write16(UInt16(bitPattern: typographic[index]), &tables["OS/2"]!, 68 + index * 2)
        }
        let flags = read16(tables["OS/2"]!, 62) & ~UInt16(128)
        write16(flags | (useTypographic ? 128 : 0), &tables["OS/2"]!, 62)
        write16(2100, &tables["OS/2"]!, 74)
        write16(700, &tables["OS/2"]!, 76)
        if removeOS2 { tables.removeValue(forKey: "OS/2") }
        if variableMetrics {
            // MVAR: three records, one two-axis region, one item-variation data block.
            var mvar = words([1, 0, 0, 8, 3, 36])
            for (index, tag) in ["hasc", "hdsc", "hlgp"].enumerated() {
                mvar.append(contentsOf: tag.utf8)
                mvar.append(words([0, UInt16(index)]))
            }
            mvar.append(words([1, 0, 12, 1, 0, 28]))
            mvar.append(words([2, 1, 0, 0x4000, 0x4000, 0, 0, 0]))
            mvar.append(words([3, 1, 1, 0, 100, UInt16(bitPattern: -50), UInt16(bitPattern: -30)]))
            tables["MVAR"] = mvar
            tables.removeValue(forKey: "avar")
        }
        write32(0, &tables["head"]!, 8)
        let count = tables.count
        var power = 1, selector = 0
        while power * 2 <= count { power *= 2; selector += 1 }
        var output = words([1, 0, UInt16(count), UInt16(power * 16), UInt16(selector), UInt16((count - power) * 16)])
        output.append(Data(repeating: 0, count: count * 16))
        var headOffset = 0
        for (index, tag) in tables.keys.sorted().enumerated() {
            let data = tables[tag]!
            let record = 12 + index * 16
            output.replaceSubrange(record..<record + 4, with: tag.utf8)
            write32(checksum(data), &output, record + 4)
            write32(UInt32(output.count), &output, record + 8)
            write32(UInt32(data.count), &output, record + 12)
            if tag == "head" { headOffset = output.count }
            output.append(data)
            while !output.count.isMultiple(of: 4) { output.append(0) }
        }
        write32(0xb1b0afba &- checksum(output), &output, headOffset + 8)
        return output
    }

    private static func words(_ values: [UInt16]) -> Data {
        Data(values.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] })
    }

    private static func read16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(read16(data, offset)) << 16 | UInt32(read16(data, offset + 2))
    }

    private static func write16(_ value: UInt16, _ data: inout Data, _ offset: Int) {
        data.replaceSubrange(offset..<offset + 2, with: words([value]))
    }

    private static func write32(_ value: UInt32, _ data: inout Data, _ offset: Int) {
        data.replaceSubrange(offset..<offset + 4, with: words([UInt16(value >> 16), UInt16(value & 65535)]))
    }

    private static func checksum(_ data: Data) -> UInt32 {
        var padded = data
        while !padded.count.isMultiple(of: 4) { padded.append(0) }
        return stride(from: 0, to: padded.count, by: 4).reduce(0) { $0 &+ read32(padded, $1) }
    }
}
