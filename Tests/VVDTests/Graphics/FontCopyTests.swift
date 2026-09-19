import Dispatch
import Foundation
import Synchronization
import XCTest
import VVD

final class FontCopyTests: XCTestCase {
    private func resource(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/VUI/Resources/Fonts/\(name)")
    }

    // ASSERTIONS fontGraphicsRegistry27Observed fontGraphicsSizeCopy27Observed
    func testCopiesRetainLoadedSourceAfterFileReplacementAndParentRelease() throws {
        let url = resource("Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let originalData = try Data(contentsOf: url)
        let replacement = try Data(contentsOf: resource("RobotoMono/RobotoMono-VariableFont_wght.ttf"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for memory in [false, true] {
            let path = directory.appendingPathComponent("font.ttf")
            try originalData.write(to: path)
            weak var parent: Font?
            weak var source: Font.Source?
            var retained: Font?
            func makeCopy() throws {
                let font = try XCTUnwrap(memory ? Font(data: originalData) : Font(path: path.path))
                parent = font
                source = font.source
                font.setPointSize(23.375, dpi: (96, 144))
                XCTAssertTrue(font.setVariationCoordinates([0x77676874: 530.0013885498047, 0x77647468: 90]))
                font.isBitmapPreferred = true
                font.isKerningEnabled = false
                font.isColorEnabled = false
                let originalGlyph = try XCTUnwrap(font.glyphMetrics(for: "A"))
                let metadata = try XCTUnwrap(Font.metadata(data: originalData))
                // Read metadata and copy from the loaded stream after replacing the path.
                try replacement.write(to: path, options: .atomic)
                XCTAssertEqual(font.metadata(), metadata)
                XCTAssertEqual(font.metadata()?.familyName, "Roboto")
                retained = try XCTUnwrap(font.copy(pointSize: 31.375))
                XCTAssertFalse(retained === font)
                XCTAssertTrue(retained?.source === font.source)
                XCTAssertEqual(retained?.postScriptName, font.postScriptName)
                XCTAssertEqual(retained?.variationCoordinates, font.variationCoordinates)
                XCTAssertEqual(retained?.dpi.x, 96)
                XCTAssertEqual(retained?.dpi.y, 144)
                XCTAssertEqual(retained?.pointSize, 31.375)
                XCTAssertEqual(retained?.isBitmapPreferred, true)
                XCTAssertEqual(retained?.isKerningEnabled, false)
                XCTAssertEqual(retained?.isColorEnabled, false)
                XCTAssertEqual(font.pointSize, 23.375)
                XCTAssertEqual(font.glyphMetrics(for: "A")?.advance, originalGlyph.advance)
                XCTAssertNil(font.copy(pointSize: -.infinity))
                XCTAssertNil(font.copy(pointSize: .nan))
                XCTAssertNil(font.copy(pointSize: 0.001))
                XCTAssertNil(font.copy(pointSize: font.maxPointSize * 2))
            }
            try makeCopy()
            XCTAssertNil(parent)
            XCTAssertNotNil(source)
            try FileManager.default.removeItem(at: path)
            func checkRestored() throws {
                let restored = try XCTUnwrap(retained?.copy(pointSize: 23.375))
                XCTAssertTrue(restored.source === source)
                XCTAssertEqual(restored.familyName, "Roboto")
                XCTAssertNotNil(restored.glyphMetrics(for: "A"))
                XCTAssertEqual(restored.metadata()?.familyName, "Roboto")
                let sameSize = try XCTUnwrap(restored.copy())
                XCTAssertFalse(sameSize === restored)
                XCTAssertEqual(sameSize.pointSize, restored.pointSize)
                XCTAssertEqual(sameSize.fontData?.address, restored.fontData?.address)
                XCTAssertTrue(restored.setVariationCoordinates([0x77676874: 700]))
                XCTAssertEqual(retained?.variationCoordinates[0x77676874], 530.0013885498047)
                let independent = try XCTUnwrap(Font(data: originalData))
                XCTAssertFalse(independent.source === restored.source)
            }
            try checkRestored()
            retained = nil
            XCTAssertNil(source)
        }
    }

    // ASSERTIONS fontGraphicsRegistry27Observed fontGraphicsSizeCopy27Observed
    func testCollectionAndNamedInstanceCopiesKeepSelectedFaceAndShaping() throws {
        let cases = [
            ("NotoSansCJK/NotoSansCJK-VF.otf.ttc", 2, "漢字"),
            ("Roboto/Roboto-VariableFont_wdth,wght.ttf", 7 << 16, "AVfi")
        ]
        for (name, index, text) in cases {
            let data = try Data(contentsOf: resource(name))
            for memory in [false, true] {
                let original = try XCTUnwrap(memory ? Font(data: data, faceIndex: index) : Font(path: resource(name).path, faceIndex: index))
                original.setPointSize(23.375, dpi: (72, 72))
                let copy = try XCTUnwrap(original.copy(pointSize: 31.375))
                let originalCoordinates = original.variationCoordinates
                let metadata = try XCTUnwrap(original.metadata())
                XCTAssertEqual(metadata, Font.metadata(data: data, faceIndex: index & 0xffff))
                XCTAssertEqual(original.faceIndex, index)
                XCTAssertEqual(original.variationCoordinates, originalCoordinates)
                XCTAssertEqual(original.pointSize, 23.375)
                let expected = try XCTUnwrap(Font(data: data, faceIndex: index))
                expected.setPointSize(31.375, dpi: (72, 72))
                XCTAssertEqual(copy.faceIndex, original.faceIndex)
                XCTAssertEqual(copy.numFaces, original.numFaces)
                XCTAssertEqual(copy.postScriptName, original.postScriptName)
                XCTAssertEqual(copy.variationCoordinates, original.variationCoordinates)
                let actual = try XCTUnwrap(copy.shape(text))
                let reference = try XCTUnwrap(expected.shape(text))
                XCTAssertEqual(actual.glyphs.map(\.index), reference.glyphs.map(\.index))
                XCTAssertEqual(actual.glyphs.map(\.advance), reference.glyphs.map(\.advance))
                XCTAssertEqual(actual.glyphs.map(\.offset), reference.glyphs.map(\.offset))
            }
        }
    }

    func testConcurrentCopiesOwnIndependentFacesAndShareOnlySourceBytes() throws {
        let original = try XCTUnwrap(Font(path: resource("Roboto/Roboto-VariableFont_wdth,wght.ttf").path))
        original.pointSize = 23.375
        XCTAssertTrue(original.setVariationCoordinates([0x77676874: 700]))
        let copies = Mutex<[Font]>([])
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            guard let copy = original.copy(pointSize: CGFloat(index + 11)) else {
                return XCTFail("A concurrent copy lost its loaded face")
            }
            XCTAssertNotNil(copy.glyphMetrics(for: "A"))
            XCTAssertTrue(copy.source === original.source)
            copies.withLock { $0.append(copy) }
        }
        let result = copies.withLock { $0 }
        XCTAssertEqual(result.count, 12)
        XCTAssertEqual(Set(result.map(ObjectIdentifier.init)).count, 12)
        XCTAssertEqual(result.map(\.pointSize).sorted(), (11..<23).map(CGFloat.init))
        XCTAssertTrue(result.allSatisfy { $0.fontData?.address == result[0].fontData?.address })
        XCTAssertEqual(original.pointSize, 23.375)
    }
}
