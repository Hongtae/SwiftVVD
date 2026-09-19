import Foundation
import XCTest
import VVD

final class FontShapingPrecisionTests: XCTestCase {
    private var file: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
    }

    private func font(_ size: CGFloat, dpi: Font.DPI = (72, 72)) throws -> Font {
        let value = try XCTUnwrap(Font(data: Data(contentsOf: file)))
        value.setPointSize(size, dpi: dpi)
        return value
    }

    func testLogicalSizesAndAdvancesRetainFractionalPrecision() throws {
        for factor: CGFloat in [1, 0.958984375] {
            let first = try font(23 * factor)
            let second = try font(31 * factor)
            XCTAssertEqual(first.pointSize, 23 * factor)
            XCTAssertEqual(second.pointSize, 31 * factor)
            let a = try XCTUnwrap(first.shape("AAA AAA "))
            let b = try XCTUnwrap(second.shape("BBB BBB"))
            XCTAssertEqual(a.glyphs.map(\.index), [37, 37, 37, 4, 37, 37, 37, 4])
            XCTAssertEqual(b.glyphs.map(\.index), [38, 38, 38, 4, 38, 38, 38])
            XCTAssertEqual(a.glyphs.map(\.advance.width), [1336,1336,1336,508,1336,1336,1336,508].map {
                CGFloat($0) * 23 * factor / 2048
            })
            XCTAssertEqual(b.glyphs.map(\.advance.width), [1276,1276,1276,508,1276,1276,1276].map {
                CGFloat($0) * 31 * factor / 2048
            })
            let width = (a.glyphs + b.glyphs).reduce(CGFloat.zero) { $0 + $1.advance.width }
            XCTAssertEqual(width, 225.009765625 * factor)
            if factor != 1 {
                XCTAssertEqual(b.glyphs.reduce(CGFloat.zero) { $0 + $1.advance.width }, 118.50761795043945)
            }
        }
    }

    func testSizeChangesWithinOneRasterStepDoNotReuseShapingSize() throws {
        let value = try font(23)
        let original = try XCTUnwrap(value.shape("A"))
        for size: CGFloat in [23 + 1.0 / 1024, 23 + 2.0 / 1024, 23] {
            value.pointSize = size
            XCTAssertEqual(value.pointSize, size)
            XCTAssertEqual(value.faceTraits.pixelSize, size)
            XCTAssertEqual(try XCTUnwrap(value.shape("A")).glyphs[0].advance.width, 1336 * size / 2048)
        }
        XCTAssertEqual(try XCTUnwrap(value.shape("A")), original)
    }

    func testShapedAdvancesAndOffsetsFollowIndependentDPIAxes() throws {
        let base = try font(23.00390625)
        let scaled = try font(23.00390625, dpi: (144, 216))
        let first = try XCTUnwrap(base.shape("q\u{301}"))
        let second = try XCTUnwrap(scaled.shape("q\u{301}"))
        XCTAssertTrue(first.glyphs.contains { $0.offset != .zero })
        XCTAssertEqual(first.glyphs.map(\.index), second.glyphs.map(\.index))
        XCTAssertEqual(first.glyphs.map(\.sourceRange), second.glyphs.map(\.sourceRange))
        for (a,b) in zip(first.glyphs, second.glyphs) {
            XCTAssertEqual(b.advance.width, a.advance.width * 2)
            XCTAssertEqual(b.advance.height, a.advance.height * 3)
            XCTAssertEqual(b.offset.x, a.offset.x * 2)
            XCTAssertEqual(b.offset.y, a.offset.y * 3)
        }
    }

    func testVariationAndKerningChangesRestoreShapingState() throws {
        let value = try font(23.00390625)
        let original = try XCTUnwrap(value.shape("AV ffi"))
        value.isKerningEnabled = false
        let unkerned = try XCTUnwrap(value.shape("AV ffi"))
        XCTAssertGreaterThan(unkerned.glyphs.reduce(CGFloat.zero) { $0 + $1.advance.width },
                             original.glyphs.reduce(CGFloat.zero) { $0 + $1.advance.width })
        value.isKerningEnabled = true
        XCTAssertEqual(try XCTUnwrap(value.shape("AV ffi")), original)
        let coordinates: [UInt32: CGFloat] = [0x7767_6874: 900, 0x7764_7468: 75]
        XCTAssertTrue(value.setVariationCoordinates(coordinates))
        let varied = try XCTUnwrap(value.shape("AV ffi"))
        XCTAssertNotEqual(varied, original)
        let fresh = try font(value.pointSize)
        XCTAssertTrue(fresh.setVariationCoordinates(coordinates))
        XCTAssertEqual(try XCTUnwrap(fresh.shape("AV ffi")), varied)
        XCTAssertTrue(value.setVariationCoordinates([:]))
        XCTAssertEqual(try XCTUnwrap(value.shape("AV ffi")), original)
    }

}
