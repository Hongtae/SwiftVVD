import Dispatch
import Foundation
import XCTest
import VVD

final class FontMetadataTests: XCTestCase {
    private static let roboto = "Roboto/Roboto-VariableFont_wdth,wght.ttf"
    private static let robotoMono = "RobotoMono/RobotoMono-VariableFont_wght.ttf"
    private static let nanum = "NanumSquareNeo/NanumSquareNeo-Variable.ttf"
    private static let weightTag: UInt32 = 0x7767_6874
    private static let widthTag: UInt32 = 0x7764_7468

    // ASSERTIONS fontRegisteredExtrasCache27Observed
    func testResourceFeatureMetadataOutlivesItsInspectionFaceAndSourceFile() throws {
        let source = Self.resource(Self.roboto)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ttf")
        try FileManager.default.copyItem(at: source, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = try XCTUnwrap(Font.resourceMetadata(path: url.path))
        XCTAssertEqual(snapshot.metadata, try XCTUnwrap(Font.metadata(path: source.path)))
        XCTAssertNil(Font.resourceMetadata(path: url.path, faceIndex: -1))
        XCTAssertNil(Font.resourceMetadata(path: url.path, faceIndex: 1))
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(Font.resourceMetadata(path: url.path))
        let settings = snapshot.features.select([
            Font.ShapingFeature(tag: "liga", value: 1)!,
            Font.ShapingFeature(tag: "tnum", value: 2)!,
            Font.ShapingFeature(tag: "ss01", value: 1)!
        ])
        XCTAssertEqual(settings.map(\.tag), [0x7373_3031, 0x746e_756d])
        XCTAssertEqual(settings.map(\.value), [1, 2])
        XCTAssertEqual(settings.map(\.type), [35, 6])
        XCTAssertEqual(settings.map(\.selector), [2, 0])
    }

    func testActiveFaceTraitsRetainVariationAndSizeWithoutReopeningMetadata() throws {
        for name in [Self.roboto, Self.nanum] {
            let url = Self.resource(name)
            let file = try XCTUnwrap(Font(path: url.path))
            let memory = try XCTUnwrap(Font(data: Data(contentsOf: url)))
            let original = file.faceTraits
            XCTAssertEqual(original, memory.faceTraits)
            for font in [file, memory] {
                font.setPointSize(15.625, dpi: (96, 144))
                XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: 780]))
                let selected = font.faceTraits
                XCTAssertEqual(selected.pixelSize, 31.25)
                XCTAssertEqual(selected.variationCoordinates[Self.weightTag], 780)
                XCTAssertEqual(selected.sfntStyle.weightClass, 400)
                XCTAssertTrue(font.setVariationCoordinates([:]))
                XCTAssertEqual(font.faceTraits.variationCoordinates, original.variationCoordinates)
                XCTAssertEqual(selected.variationCoordinates[Self.weightTag], 780)
            }
        }
    }

    private static func resource(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/VUI/Resources/Fonts")
            .appendingPathComponent(name)
    }

    func testNamedInstancesRetainNamesAndCompleteAxisCoordinates() throws {
        let value = try XCTUnwrap(Font.metadata(path: Self.resource(Self.roboto).path))
        XCTAssertEqual(value.faceIndex, 0)
        XCTAssertEqual(value.numFaces, 1)
        XCTAssertEqual(value.familyName, "Roboto")
        XCTAssertEqual(value.styleName, "Regular")
        XCTAssertEqual(value.postScriptName, "Roboto-Regular")
        XCTAssertEqual(value.variationAxes.map(\.tag), [Self.weightTag, Self.widthTag])
        XCTAssertEqual(value.variationAxes.map(\.minimumValue), [100, 75])
        XCTAssertEqual(value.variationAxes.map(\.defaultValue), [400, 100])
        XCTAssertEqual(value.variationAxes.map(\.maximumValue), [900, 100])
        XCTAssertEqual(value.defaultVariationInstanceIndex, 4)
        XCTAssertEqual(value.variationInstances.count, 18)
        let extraLight = value.variationInstances[1]
        XCTAssertEqual(extraLight.index, 2)
        XCTAssertEqual(extraLight.styleName, "ExtraLight")
        XCTAssertEqual(extraLight.postScriptName, "Roboto-ExtraLight")
        XCTAssertEqual(extraLight.coordinates, [200, 100])
        XCTAssertEqual(value.variationInstances[10].coordinates, [200, 75])
        XCTAssertEqual(value.sfntStyle.weightClass, 400)
        XCTAssertEqual(value.sfntStyle.widthClass, 5)
    }

    // ASSERTIONS fontResolvedTraits27Observed
    func testFixedWidthMetadataUsesTheSharedHorizontalAdvance() throws {
        let proportional = try XCTUnwrap(Font.metadata(path: Self.resource(Self.roboto).path))
        let monospaced = try XCTUnwrap(Font.metadata(path: Self.resource(Self.robotoMono).path))

        XCTAssertFalse(proportional.isFixedWidth)
        XCTAssertTrue(monospaced.isFixedWidth)
        XCTAssertEqual(monospaced.sfntStyle.fixedPitch, 0)
    }

    func testGeneratedInstanceNamesAndNonRegularDefaultRemainDistinct() throws {
        let value = try XCTUnwrap(Font.metadata(path: Self.resource(Self.nanum).path))
        XCTAssertEqual(value.styleName, "Regular")
        XCTAssertEqual(value.postScriptName, "NanumSquareNeo-Variable")
        XCTAssertEqual(value.variationAxes.map(\.defaultValue), [100])
        XCTAssertEqual(value.defaultVariationInstanceIndex, 1)
        XCTAssertEqual(value.variationInstances.map(\.styleName), ["Light", "Regular", "Bold", "ExtraBold", "Heavy"])
        XCTAssertEqual(value.variationInstances.map(\.coordinates), [[100], [300], [500], [700], [900]])
        XCTAssertEqual(value.variationInstances[0].postScriptName, "NanumSquareNeo-Variable")
        XCTAssertEqual(value.variationInstances[1].postScriptName, "NanumSquareNeovariable-Regular")
        XCTAssertTrue(value.variationInstances.allSatisfy { $0.postScriptName != nil })
    }

    func testSourceNameRecordsRemainIndependentOfResolvedInstanceNames() throws {
        let roboto = try XCTUnwrap(Font.metadata(path: Self.resource(Self.roboto).path))
        let fullNames = roboto.sfntNames.filter { $0.nameID == 4 }.compactMap(\.string)
        XCTAssertTrue(fullNames.contains("Roboto Regular"))
        XCTAssertFalse(fullNames.contains("Roboto Regular ExtraLight"))
        let extraLight = roboto.variationInstances[1]
        XCTAssertTrue(roboto.sfntNames.contains {
            $0.nameID == extraLight.styleNameID && $0.string == "ExtraLight"
        })
        XCTAssertTrue(roboto.sfntNames.contains {
            $0.nameID == extraLight.postScriptNameID && $0.string == "Roboto-ExtraLight"
        })
        let nanum = try XCTUnwrap(Font.metadata(path: Self.resource(Self.nanum).path))
        XCTAssertTrue(nanum.variationInstances.allSatisfy { $0.postScriptNameID == nil })
        XCTAssertNotNil(nanum.variationInstances[1].postScriptName)
        XCTAssertTrue(nanum.sfntNames.contains {
            $0.nameID == nanum.variationInstances[1].styleNameID && $0.string == "Regular"
        })
        let english = try XCTUnwrap(roboto.sfntNames.first {
            $0.platformID == 3 && $0.languageID == 1033 && $0.nameID == 4
        })
        XCTAssertEqual(english.data, "Roboto Regular".data(using: .utf16BigEndian))
    }

    func testSourceTablePresenceDoesNotFollowSynthesizedVariationMetadata() throws {
        var data = try Data(contentsOf: Self.resource(Self.roboto))
        let original = try XCTUnwrap(Font.metadata(data: data))
        XCTAssertTrue(original.sfntTableTags.contains(0x5354_4154))
        XCTAssertFalse(original.sfntTableTags.contains(0x7472_616b))
        let record = try tableRecord("STAT", in: data)
        data[record + 3] = 0x5f
        let changed = try XCTUnwrap(Font.metadata(data: data))
        XCTAssertFalse(changed.sfntTableTags.contains(0x5354_4154))
        XCTAssertTrue(changed.sfntTableTags.contains(0x5354_415f))
        XCTAssertEqual(changed.variationAxes, original.variationAxes)
        XCTAssertEqual(changed.variationInstances, original.variationInstances)
        data.resetBytes(in: data.startIndex..<data.endIndex)
        XCTAssertTrue(changed.sfntTableTags.contains(0x5354_415f))
        XCTAssertTrue(original.sfntTableTags.contains(0x5354_4154))
    }

    func testUnsupportedNameEncodingPreservesCopiedBytes() throws {
        var data = try Data(contentsOf: Self.resource(Self.roboto))
        let offset = Int(readUInt32(data, at: try tableRecord("name", in: data) + 8))
        let count = Int(readUInt16(data, at: offset + 2))
        let stringOffset = offset + Int(readUInt16(data, at: offset + 4))
        let record = try XCTUnwrap((0..<count).map { offset + 6 + $0 * 12 }.first {
            readUInt16(data, at: $0) == 3 && readUInt16(data, at: $0 + 6) == 0
        })
        let start = stringOffset + Int(readUInt16(data, at: record + 10))
        let length = Int(readUInt16(data, at: record + 8))
        let original = data.subdata(in: start..<start + length)
        writeUInt16(0xfffe, to: &data, at: record + 2)
        let metadata = try XCTUnwrap(Font.metadata(data: data))
        data.resetBytes(in: data.startIndex..<data.endIndex)
        let copied = try XCTUnwrap(metadata.sfntNames.first {
            $0.platformID == 3 && $0.encodingID == 0xfffe && $0.nameID == 0
        })
        XCTAssertEqual(copied.data, original)
        XCTAssertNil(copied.string)
    }

    func testAllBundledFacesAgreeBetweenFileAndMemoryInputs() throws {
        let fixtures: [(String, Int, Int)] = [
            ("LastResort/LastResort-Regular.ttf", 1, 0),
            (Self.nanum, 1, 5),
            ("NotoSansCJK/NotoSansCJK-VF.otf.ttc", 5, 35),
            ("NotoSansMonoCJK/NotoSansMonoCJK-VF.otf.ttc", 5, 15),
            (Self.roboto, 1, 18),
            ("Roboto/Roboto-Italic-VariableFont_wdth,wght.ttf", 1, 18),
            ("RobotoMono/RobotoMono-VariableFont_wght.ttf", 1, 7),
            ("RobotoMono/RobotoMono-Italic-VariableFont_wght.ttf", 1, 7),
        ]
        for (name, faceCount, instanceCount) in fixtures {
            let url = Self.resource(name)
            let data = try Data(contentsOf: url)
            var instances = 0
            for index in 0..<faceCount {
                let fromFile = try XCTUnwrap(Font.metadata(path: url.path, faceIndex: index), name)
                let fromMemory = try XCTUnwrap(Font.metadata(data: data, faceIndex: index), name)
                XCTAssertEqual(fromFile, fromMemory, "\(name) face \(index)")
                XCTAssertEqual(fromFile.faceIndex, index)
                XCTAssertEqual(fromFile.numFaces, faceCount)
                XCTAssertNotNil(fromFile.familyName)
                XCTAssertNotNil(fromFile.postScriptName)
                if let defaultIndex = fromFile.defaultVariationInstanceIndex {
                    XCTAssertEqual(fromFile.variationInstances[defaultIndex - 1].coordinates,
                                   fromFile.variationAxes.map(\.defaultValue))
                } else {
                    XCTAssertTrue(fromFile.variationAxes.isEmpty)
                    XCTAssertTrue(fromFile.variationInstances.isEmpty)
                }
                instances += fromFile.variationInstances.count
            }
            XCTAssertEqual(instances, instanceCount, name)
        }
    }

    func testInvalidCollectionIndicesDoNotSelectPackedNamedInstances() throws {
        let path = Self.resource(Self.roboto).path
        let data = try Data(contentsOf: Self.resource(Self.roboto))
        for index in [-1, Int.min, 1, 0xffff, 0x10000, 0x20000, Int.max] {
            XCTAssertNil(Font.metadata(path: path, faceIndex: index), "\(index)")
            XCTAssertNil(Font.metadata(data: data, faceIndex: index), "\(index)")
        }
        XCTAssertNil(Font.metadata(path: path + "\0ignored"))
        XCTAssertNil(Font.metadata(path: path + ".missing"))
    }

    func testUnreadableAndTruncatedInputsReturnNil() throws {
        let valid = try Data(contentsOf: Self.resource(Self.roboto))
        let cases = [Data(), Data(repeating: 0, count: 64), Data("invalid font".utf8)]
            + [4, 12, 127].map { Data(valid.prefix($0)) }
        for data in cases {
            XCTAssertNil(Font.metadata(data: data))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertNil(Font.metadata(path: url.path))
        }
        XCTAssertNotNil(Font.metadata(data: valid))
    }

    func testMissingOptionalTablesAreDifferentFromPresentZeroValues() throws {
        var data = try Data(contentsOf: Self.resource(Self.roboto))
        let original = try XCTUnwrap(Font.metadata(data: data))
        XCTAssertEqual(original.sfntStyle.italicAngle, 0)
        XCTAssertEqual(original.sfntStyle.fixedPitch, 0)
        XCTAssertNotNil(original.sfntStyle.weightClass)

        let postRecord = try tableRecord("post", in: data)
        data.replaceSubrange(postRecord..<postRecord + 4, with: "xxxx".utf8)
        let os2Record = try tableRecord("OS/2", in: data)
        data.replaceSubrange(os2Record..<os2Record + 4, with: "yyyy".utf8)
        let missing = try XCTUnwrap(Font.metadata(data: data))
        XCTAssertNil(missing.sfntStyle.italicAngle)
        XCTAssertNil(missing.sfntStyle.fixedPitch)
        XCTAssertNil(missing.sfntStyle.weightClass)
        XCTAssertNil(missing.sfntStyle.widthClass)
        XCTAssertNil(missing.sfntStyle.familyClass)
        XCTAssertNil(missing.sfntStyle.selection)
        XCTAssertNotNil(missing.sfntStyle.macStyle)
        XCTAssertEqual(missing.variationInstances.map(\.coordinates), original.variationInstances.map(\.coordinates))
    }

    func testShortPostTableDoesNotExposeZeroFilledParsedFields() throws {
        var data = try Data(contentsOf: Self.resource(Self.roboto))
        let record = try tableRecord("post", in: data)
        writeUInt32(16, to: &data, at: record + 12)
        let value = try XCTUnwrap(Font.metadata(data: data))
        XCTAssertNil(value.sfntStyle.italicAngle)
        XCTAssertNil(value.sfntStyle.fixedPitch)
        XCTAssertEqual(value.sfntStyle.weightClass, 400)
    }

    func testRawStyleFieldsPreserveSignedAnglesAndBitPatterns() throws {
        var data = try Data(contentsOf: Self.resource(Self.roboto))
        let os2 = Int(readUInt32(data, at: try tableRecord("OS/2", in: data) + 8))
        let head = Int(readUInt32(data, at: try tableRecord("head", in: data) + 8))
        let post = Int(readUInt32(data, at: try tableRecord("post", in: data) + 8))
        writeUInt16(777, to: &data, at: os2 + 4)
        writeUInt16(9, to: &data, at: os2 + 6)
        writeUInt16(0x9123, to: &data, at: os2 + 30)
        writeUInt16(0x0201, to: &data, at: os2 + 62)
        writeUInt16(0x0042, to: &data, at: head + 44)
        writeUInt32(UInt32(bitPattern: Int32(-12.5 * 65536)), to: &data, at: post + 4)
        writeUInt32(5, to: &data, at: post + 12)
        let value = try XCTUnwrap(Font.metadata(data: data)).sfntStyle
        XCTAssertEqual(value.weightClass, 777)
        XCTAssertEqual(value.widthClass, 9)
        XCTAssertEqual(value.familyClass, Int16(bitPattern: 0x9123))
        XCTAssertEqual(value.selection, 0x0201)
        XCTAssertEqual(value.macStyle, 0x0042)
        XCTAssertEqual(value.italicAngle, -12.5)
        XCTAssertEqual(value.fixedPitch, 5)
    }

    func testDuplicateAxisTagsAreRejected() throws {
        var data = try Data(contentsOf: Self.resource(Self.roboto))
        let fvar = Int(readUInt32(data, at: try tableRecord("fvar", in: data) + 8))
        let axes = fvar + Int(readUInt16(data, at: fvar + 4))
        let axisSize = Int(readUInt16(data, at: fvar + 10))
        XCTAssertEqual(readUInt16(data, at: fvar + 8), 2)
        writeUInt32(readUInt32(data, at: axes), to: &data, at: axes + axisSize)
        XCTAssertNil(Font.metadata(data: data))
    }

    func testMetadataDoesNotRequireACharacterMap() throws {
        var data = try Data(contentsOf: Self.resource(Self.roboto))
        let record = try tableRecord("cmap", in: data)
        data.replaceSubrange(record..<record + 4, with: "xxxx".utf8)
        let value = try XCTUnwrap(Font.metadata(data: data))
        XCTAssertEqual(value.postScriptName, "Roboto-Regular")
        XCTAssertEqual(value.variationInstances.count, 18)
    }

    func testSlicedAndMultipleRegionDataResolveTheSameFace() throws {
        let data = try Data(contentsOf: Self.resource(Self.roboto))
        let expected = try XCTUnwrap(Font.metadata(data: data))
        var padded = Data(repeating: 0xaa, count: 19)
        padded.append(data)
        padded.append(Data(repeating: 0xbb, count: 23))
        let slice = padded.dropFirst(19).dropLast(23)
        XCTAssertEqual(Font.metadata(data: slice), expected)

        let midpoint = data.count / 2
        var regions = data.prefix(midpoint).withUnsafeBytes { DispatchData(bytes: $0) }
        regions.append(data.suffix(from: midpoint).withUnsafeBytes { DispatchData(bytes: $0) })
        XCTAssertGreaterThan(regions.regions.count, 1)
        XCTAssertEqual(Font.metadata(data: regions), expected)
    }

    func testSnapshotOutlivesSourceStorageAndInspectionFaces() throws {
        weak var weakStorage: RawBufferStorage?
        let value = try { () throws -> Font.FaceMetadata in
            let storage = RawBufferStorage(try Data(contentsOf: Self.resource(Self.roboto)))
            weakStorage = storage
            return try XCTUnwrap(Font.metadata(data: storage))
        }()
        XCTAssertNil(weakStorage)
        for _ in 0..<8 {
            XCTAssertNotNil(Font.metadata(path: Self.resource(Self.nanum).path))
        }
        XCTAssertEqual(value.postScriptName, "Roboto-Regular")
        XCTAssertEqual(value.variationInstances[1].postScriptName, "Roboto-ExtraLight")
        var coordinates = value.variationInstances[1].coordinates
        coordinates[0] = 900
        XCTAssertEqual(value.variationInstances[1].coordinates, [200, 100])
    }

    func testConcurrentInspectionPreservesLiveRenderingState() async throws {
        let url = Self.resource(Self.roboto)
        let path = url.path
        let data = try Data(contentsOf: url)
        let font = try XCTUnwrap(Font(data: data))
        font.setPointSize(17.125, dpi: (96, 96))
        XCTAssertTrue(font.setVariationCoordinates([Self.weightTag: 537, Self.widthTag: 83]))
        let coordinates = font.variationCoordinates
        let metrics = font.baseMetrics
        let glyph = try XCTUnwrap(font.glyphMetrics(for: "A"))
        let expected = try XCTUnwrap(Font.metadata(data: data))
        let results = await withTaskGroup(of: Font.FaceMetadata?.self) { group in
            for index in 0..<24 {
                group.addTask {
                    index.isMultiple(of: 2) ? Font.metadata(path: path) : Font.metadata(data: data)
                }
            }
            var values: [Font.FaceMetadata?] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(results.count, 24)
        XCTAssertTrue(results.allSatisfy { $0 == expected })
        XCTAssertEqual(font.variationCoordinates, coordinates)
        XCTAssertEqual(font.pointSize, 17.125)
        XCTAssertEqual(font.dpi.x, 96)
        XCTAssertEqual(font.dpi.y, 96)
        XCTAssertEqual(font.baseMetrics.xScale, metrics.xScale)
        XCTAssertEqual(font.baseMetrics.yScale, metrics.yScale)
        XCTAssertEqual(font.baseMetrics.ascender, metrics.ascender)
        XCTAssertEqual(font.baseMetrics.descender, metrics.descender)
        XCTAssertEqual(font.baseMetrics.height, metrics.height)
        XCTAssertEqual(font.baseMetrics.maxAdvance, metrics.maxAdvance)
        let after = try XCTUnwrap(font.glyphMetrics(for: "A"))
        XCTAssertEqual(after.index, glyph.index)
        XCTAssertEqual(after.advance, glyph.advance)
        XCTAssertEqual(after.bearing, glyph.bearing)
        XCTAssertEqual(after.size, glyph.size)
    }

    func testNonSFNTBitmapFontHasNoInventedTableMetadata() throws {
        let bdf = """
        STARTFONT 2.1
        FONT -misc-Metadata-medium-r-normal--8-80-75-75-c-80-iso10646-1
        SIZE 8 75 75
        FONTBOUNDINGBOX 8 8 0 0
        STARTPROPERTIES 2
        FONT_ASCENT 8
        FONT_DESCENT 0
        ENDPROPERTIES
        CHARS 1
        STARTCHAR A
        ENCODING 65
        SWIDTH 1000 0
        DWIDTH 8 0
        BBX 8 8 0 0
        BITMAP
        18
        24
        42
        7E
        42
        42
        42
        00
        ENDCHAR
        ENDFONT

        """
        let value = try XCTUnwrap(Font.metadata(data: Data(bdf.utf8)))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bdf")
        try Data(bdf.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        for font in [try XCTUnwrap(Font(data: Data(bdf.utf8))), try XCTUnwrap(Font(path: file.path))] {
            font.setPointSize(8, dpi: (75, 75))
            let copy = try XCTUnwrap(font.copy(pointSize: 16))
            XCTAssertFalse(copy.isScalable)
            XCTAssertTrue(copy.source === font.source)
            XCTAssertEqual(copy.pointSize, 16)
            XCTAssertEqual(copy.glyphMetrics(for: "A")?.advance, font.glyphMetrics(for: "A")?.advance)
            XCTAssertEqual(copy.bitmapScale, font.bitmapScale * 2)
            XCTAssertEqual(font.pointSize, 8)
        }
        XCTAssertEqual(value.numFaces, 1)
        XCTAssertNil(value.postScriptName)
        XCTAssertTrue(value.variationAxes.isEmpty)
        XCTAssertTrue(value.variationInstances.isEmpty)
        XCTAssertNil(value.defaultVariationInstanceIndex)
        XCTAssertNil(value.sfntStyle.weightClass)
        XCTAssertNil(value.sfntStyle.widthClass)
        XCTAssertNil(value.sfntStyle.familyClass)
        XCTAssertNil(value.sfntStyle.selection)
        XCTAssertNil(value.sfntStyle.macStyle)
        XCTAssertNil(value.sfntStyle.italicAngle)
        XCTAssertNil(value.sfntStyle.fixedPitch)
        XCTAssertTrue(value.sfntNames.isEmpty)
    }
}

private func tableRecord(_ tag: String, in data: Data) throws -> Int {
    let count = Int(readUInt16(data, at: 4))
    return try XCTUnwrap((0..<count).map { 12 + $0 * 16 }.first {
        data[$0..<$0 + 4].elementsEqual(tag.utf8)
    })
}

private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
}

private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
    (offset..<offset + 4).reduce(0) { $0 << 8 | UInt32(data[$1]) }
}

private func writeUInt16(_ value: UInt16, to data: inout Data, at offset: Int) {
    data[offset] = UInt8(truncatingIfNeeded: value >> 8)
    data[offset + 1] = UInt8(truncatingIfNeeded: value)
}

private func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
    for index in 0..<4 {
        data[offset + index] = UInt8(truncatingIfNeeded: value >> (24 - index * 8))
    }
}
