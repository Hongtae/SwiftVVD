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
        let clipping = try XCTUnwrap(metrics.clipping)
        XCTAssertEqual([clipping.ascent, clipping.descent], [1946, 512])
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

    func testOutlineFormatUsesSelectedFileAndMemoryFace() throws {
        let cases: [(String, Int, Font.OutlineFormat, Int, [Double])] = [
            (Self.roboto, 0, .trueType, 2048, [1946, 512]),
            ("NanumSquareNeo/NanumSquareNeo-Variable.ttf", 0, .trueType, 1000, [850, 255]),
            ("NotoSansCJK/NotoSansCJK-VF.otf.ttc", 0, .compactFontFormat, 1000, [1160, 288]),
            ("NotoSansCJK/NotoSansCJK-VF.otf.ttc", 3, .compactFontFormat, 1000, [1160, 288]),
            ("NotoSansMonoCJK/NotoSansMonoCJK-VF.otf.ttc", 1, .compactFontFormat, 1000, [1160, 288])
        ]
        for (name, index, expected, units, expectedClipping) in cases {
            let url = Self.resource(name)
            let file = try XCTUnwrap(Font(path: url.path, faceIndex: index))
            let data = try Data(contentsOf: url)
            let memory = try XCTUnwrap(Font(data: data, faceIndex: index))
            let original = try XCTUnwrap(file.designMetrics)
            XCTAssertEqual(original.outlineFormat, expected)
            XCTAssertEqual(original.unitsPerEM, units)
            let clipping = try XCTUnwrap(original.clipping)
            XCTAssertEqual([clipping.ascent, clipping.descent], expectedClipping)
            for font in [file, memory] {
                XCTAssertEqual(font.designMetrics, original)
                for size: CGFloat in [13, 15.625] {
                    font.setPointSize(size, dpi: (144, 96))
                    XCTAssertEqual(font.designMetrics, original)
                }
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
            let clipping = try XCTUnwrap(metrics.clipping)
            XCTAssertEqual([clipping.ascent, clipping.descent], [2100, 700])
        }
        let data = try Self.fixture(removeOS2: true)
        let font = try XCTUnwrap(Font(data: data))
        let metrics = try XCTUnwrap(font.designMetrics)
        XCTAssertEqual([metrics.ascender, metrics.descender, metrics.height, metrics.lineGap],
                       [1800, -400, 2100, -100])
        XCTAssertNil(metrics.clipping)
    }

    func testClippingDistancesPreserveZeroUnsignedValuesAndValueIdentity() throws {
        let snapshots = try [[UInt16(0), 0], [2100, 700], [40000, 50000]].map { distances in
            let font = try XCTUnwrap(Font(data: Self.fixture(clipping: distances)))
            let metrics = try XCTUnwrap(font.designMetrics)
            let clipping = try XCTUnwrap(metrics.clipping)
            XCTAssertEqual([clipping.ascent, clipping.descent], distances.map(Double.init))
            XCTAssertEqual([metrics.ascender, metrics.descender, metrics.height], [1800, -400, 2100])
            return metrics
        }
        XCTAssertEqual(Set(snapshots).count, 3)
        XCTAssertEqual(Set(snapshots.compactMap(\.clipping)).count, 3)
    }

    func testClippingVariationRetainsFractionsAndEarlierSnapshots() throws {
        let data = try Self.fixture(variableMetrics: true)
        let font = try XCTUnwrap(Font(data: data))
        let original = try XCTUnwrap(font.designMetrics)
        let initial = try XCTUnwrap(original.clipping)
        for (weight, expected): (CGFloat, [Double]) in [
            (900, [2201, 649]), (650, [2150.5, 674.5]), (525, [2125.25, 687.25]),
            (400, [2100, 700]), (100, [2100, 700]), (650, [2150.5, 674.5]),
        ] {
            XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: weight]))
            let metrics = try XCTUnwrap(font.designMetrics)
            let clipping = try XCTUnwrap(metrics.clipping)
            XCTAssertEqual([clipping.ascent, clipping.descent], expected)
            XCTAssertEqual(original.clipping, initial)
            XCTAssertEqual([initial.ascent, initial.descent], [2100, 700])
        }
        XCTAssertTrue(font.setVariationCoordinates([:]))
        XCTAssertEqual(font.designMetrics, original)
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

    func testClippingRequiresReadableFieldsAndPreservesNegativeAdjustments() throws {
        for length in [0, 2, 68, 74, 76, 77, 78, 86] {
            let data = try Self.fixture { tables in tables["OS/2"] = tables["OS/2"]!.prefix(length) }
            let font = try XCTUnwrap(Font(data: data))
            if length < 78 {
                XCTAssertNil(font.designMetrics?.clipping)
            } else {
                XCTAssertEqual(font.designMetrics?.clipping?.ascent, 2100)
                XCTAssertEqual(font.designMetrics?.clipping?.descent, 700)
            }
        }
        for version: UInt16 in [0, 99, 65535] {
            let data = try Self.fixture { tables in Self.write16(version, &tables["OS/2"]!, 0) }
            XCTAssertEqual(try XCTUnwrap(Font(data: data)).designMetrics?.clipping?.ascent, 2100)
        }
        let font = try XCTUnwrap(Font(data: Self.fixture(clipping: [0, 0], variableMetrics: true)))
        XCTAssertEqual(font.designMetrics?.clipping?.ascent, 0)
        XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: 650]))
        XCTAssertEqual(font.designMetrics?.clipping?.ascent, 50.5)
        XCTAssertEqual(font.designMetrics?.clipping?.descent, -25.5)
    }

    func testInvalidClippingRecordRetainsTheIndependentValidEdge() throws {
        // The hcla record is second; hcld remains independently valid.
        for offset in [24, 26] {
            let data = try Self.fixture(variableMetrics: true) { tables in
                Self.write16(65535, &tables["MVAR"]!, offset)
            }
            let font = try XCTUnwrap(Font(data: data))
            XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: 650]))
            XCTAssertEqual(font.designMetrics?.clipping?.ascent, 2100)
            XCTAssertEqual(font.designMetrics?.clipping?.descent, 674.5)
        }
        let data = try Self.fixture(variableMetrics: true) { tables in tables["MVAR"]!.removeLast() }
        let font = try XCTUnwrap(Font(data: data))
        XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: 650]))
        // A missing last row invalidates this entire selected item, including row zero.
        XCTAssertEqual(font.designMetrics?.clipping?.ascent, 2100)
        XCTAssertEqual(font.designMetrics?.clipping?.descent, 700)
    }

    func testClippingReadPreservesSelectedCoordinatesAndLoadedGlyphs() throws {
        let data = try Self.fixture(variableMetrics: true)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("variable.ttf")
        try data.write(to: url)
        let file = try XCTUnwrap(Font(path: url.path)), memory = try XCTUnwrap(Font(data: data))
        for weight: CGFloat in [650, 900, 400, 525, 650] {
            for font in [file, memory] {
                XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: weight]))
                font.setPointSize(13, dpi: (144, 96))
                let coordinates = font.variationCoordinates
                let glyph = try XCTUnwrap(font.glyphMetrics(for: "H"))
                let metrics = try XCTUnwrap(font.designMetrics)
                for _ in 0..<4 { XCTAssertEqual(font.designMetrics, metrics) }
                XCTAssertEqual(font.variationCoordinates, coordinates)
                let after = try XCTUnwrap(font.glyphMetrics(for: "H"))
                XCTAssertEqual(after.advance, glyph.advance)
                XCTAssertEqual(after.bearing, glyph.bearing)
                XCTAssertEqual(after.size, glyph.size)
            }
            XCTAssertEqual(file.designMetrics, memory.designMetrics)
        }
    }

    // ASSERTIONS fontClippingAvarV2NormalizationObserved
    // ASSERTIONS fontClippingCheckedTablesObserved
    func testAvarCorrectionsPreserveHalfTiesAndSeparateSegmentFailure() throws {
        func mapping(_ delta: Int16) -> Data {
            var avar = Self.words([2, 0, 0, 2])
            for _ in 0..<2 { avar.append(Self.words([3, 0xc000, 0xc000, 0, 0, 0x4000, 0x4000])) }
            avar.append(Self.words([0, 0, 0, 44]))
            avar.append(Self.words([1, 0, 12, 1, 0, 28, 2, 1, 0, 16384, 16384, 0, 0, 0,
                                    2, 1, 1, 0, UInt16(bitPattern: delta), UInt16(bitPattern: -delta)]))
            return avar
        }
        for (delta, expected): (Int16, [Double]) in [
            (1, [2150.5061645507812, 674.4968872070312]),
            (-1, [2150.4938354492188, 674.5031127929688])
        ] {
            let data = try Self.fixture(variableMetrics: true) { $0["avar"] = mapping(delta) }
            let font = try XCTUnwrap(Font(data: data))
            let original = font.designMetrics
            XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: 650]))
            let clipping = try XCTUnwrap(font.designMetrics?.clipping)
            XCTAssertEqual([clipping.ascent, clipping.descent], expected)
            XCTAssertTrue(font.setVariationCoordinates([:]))
            XCTAssertEqual(font.designMetrics, original)
        }
        for length in [7, 8, 36, 40, 44] {
            let data = try Self.fixture(variableMetrics: true) { $0["avar"] = mapping(1).prefix(length) }
            let font = try XCTUnwrap(Font(data: data))
            XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: 650]))
            if length == 8 {
                XCTAssertNil(font.designMetrics?.clipping)
            } else {
                XCTAssertEqual(font.designMetrics?.clipping?.ascent, 2150.5)
                XCTAssertEqual(font.designMetrics?.clipping?.descent, 674.5)
            }
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

    func testVariationMetricsRestoreAcrossCoordinateHistory() throws {
        let sources: [(Bool, [Int16], [Int16])] = [
            (false, [1800, -400, -100], [1600, -600, 50]),
            (true, [1800, -400, -100], [1600, -600, 50]),
            (false, [0, 0, 0], [1600, -600, 50]),
            (false, [0, 0, 0], [0, 0, 0]),
        ]
        for (useTypographic, horizontal, typographic) in sources {
            let data = try Self.fixture(horizontal: horizontal, typographic: typographic,
                                        useTypographic: useTypographic, variableMetrics: true)
            let reused = try XCTUnwrap(Font(data: data))
            let initial = try XCTUnwrap(reused.designMetrics)
            for weight: CGFloat? in [900, 650, 900, 400, 100, nil, 650, 650, nil, 900, nil] {
                let coordinates = weight.map { [Self.weightTag: $0] } ?? [:]
                let fresh = try XCTUnwrap(Font(data: data))
                XCTAssertTrue(fresh.setVariationCoordinates(coordinates))
                XCTAssertTrue(reused.setVariationCoordinates(coordinates))
                XCTAssertEqual(reused.designMetrics, fresh.designMetrics)
                for size: CGFloat in [13, 24] {
                    fresh.setPointSize(size, dpi: (72, 144))
                    reused.setPointSize(size, dpi: (72, 144))
                    let a = fresh.baseMetrics, b = reused.baseMetrics
                    XCTAssertEqual([b.ascender, b.descender, b.height],
                                   [a.ascender, a.descender, a.height])
                    XCTAssertEqual(reused.designMetrics, fresh.designMetrics)
                }
            }
            XCTAssertEqual(reused.designMetrics, initial)
        }
    }

    func testNamedInstanceMetricsRestoreToExplicitCoordinates() throws {
        let data = try Self.fixture(variableMetrics: true)
        let metadata = try XCTUnwrap(Font.metadata(data: data))
        let weightIndex = try XCTUnwrap(metadata.variationAxes.firstIndex { $0.tag == Self.weightTag })
        let instance = try XCTUnwrap(metadata.variationInstances.first { $0.coordinates[weightIndex] == 900 })
        let coordinates = Dictionary(uniqueKeysWithValues:
            zip(metadata.variationAxes.map(\.tag), instance.coordinates))
        let named = try XCTUnwrap(Font(data: data, faceIndex: instance.index << 16))
        let explicit = try XCTUnwrap(Font(data: data))
        XCTAssertTrue(explicit.setVariationCoordinates(coordinates))
        XCTAssertEqual(named.designMetrics, explicit.designMetrics)
        for _ in 0..<3 {
            XCTAssertTrue(named.setVariationCoordinates([Self.weightTag: 650]))
            XCTAssertTrue(named.setVariationCoordinates(coordinates))
            XCTAssertEqual(named.designMetrics, explicit.designMetrics)
            XCTAssertEqual(named.baseMetrics.height, explicit.baseMetrics.height)
            XCTAssertTrue(named.setVariationCoordinates([Self.weightTag: 650]))
            XCTAssertTrue(named.setVariationCoordinates([:]))
            XCTAssertEqual(named.variationCoordinates, coordinates)
            XCTAssertEqual(named.designMetrics, explicit.designMetrics)
        }
    }

    func testConcurrentVariationReadsReturnCompleteSnapshots() throws {
        let data = try Self.fixture(variableMetrics: true)
        let weights: [CGFloat] = [400, 650, 900]
        let expected = try Set(weights.map { weight in
            let font = try XCTUnwrap(Font(data: data))
            XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: weight]))
            return try XCTUnwrap(font.designMetrics)
        })
        let font = try XCTUnwrap(Font(data: data))
        let failures = Mutex(0)
        DispatchQueue.concurrentPerform(iterations: 128) { index in
            if index.isMultiple(of: 4) {
                if let value = font.designMetrics, expected.contains(value) { return }
            } else if font.setVariationCoordinates([Self.weightTag: weights[index % weights.count]]) {
                return
            }
            failures.withLock { $0 += 1 }
        }
        XCTAssertEqual(failures.withLock { $0 }, 0)
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
                                clipping: [UInt16] = [2100, 700],
                                useTypographic: Bool = false,
                                removeOS2: Bool = false,
                                variableMetrics: Bool = false,
                                editTables: ((inout [String: Data]) -> Void)? = nil) throws -> Data {
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
        write16(clipping[0], &tables["OS/2"]!, 74)
        write16(clipping[1], &tables["OS/2"]!, 76)
        if removeOS2 { tables.removeValue(forKey: "OS/2") }
        if variableMetrics {
            // MVAR: five records, one two-axis region, one item-variation data block.
            var mvar = words([1, 0, 0, 8, 5, 52])
            for (index, tag) in ["hasc", "hcla", "hcld", "hdsc", "hlgp"].enumerated() {
                mvar.append(contentsOf: tag.utf8)
                mvar.append(words([0, UInt16(index)]))
            }
            mvar.append(words([1, 0, 12, 1, 0, 28]))
            mvar.append(words([2, 1, 0, 0x4000, 0x4000, 0, 0, 0]))
            mvar.append(words([5, 1, 1, 0, 100, 101, UInt16(bitPattern: -51),
                               UInt16(bitPattern: -50), UInt16(bitPattern: -30)]))
            tables["MVAR"] = mvar
            tables.removeValue(forKey: "avar")
        }
        editTables?(&tables)
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
