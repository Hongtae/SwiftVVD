import Foundation
import XCTest
@testable import VUI

final class ColorResolvedHDRProtobufTests: XCTestCase {
    // ASSERTIONS canvasColorResolvedHDRProtobufSchemaObserved
    // ASSERTIONS canvasMeshProtobufMalformedInputsObserved

    func testDefaultAndNondefaultComponentBytes() throws {
        let empty = try decode("")
        XCTAssertEqual(empty.base, .init(colorSpace: .sRGBLinear, red: 0, green: 0, blue: 0, opacity: 1))
        XCTAssertEqual(empty._headroom.bitPattern, 0x7fc00000)
        XCTAssertEqual(try encode(empty), "")
        let bytes = "0d0000803e15000000bf1d00000040250000403f2d00004040"
        let color = try decode(bytes)
        XCTAssertEqual(color.linearRed, 0.25)
        XCTAssertEqual(color.linearGreen, -0.5)
        XCTAssertEqual(color.linearBlue, 2)
        XCTAssertEqual(color.opacity, 0.75)
        XCTAssertEqual(color.headroom, 3)
        XCTAssertEqual(try encode(color), bytes)
    }

    func testDecoderRetainsRawFloatBitsAndEncodingElidesOnlyDefaults() throws {
        let values: [UInt32] = [0, 0x80000000, 0x3f800000, 0xbf800000, 0x7f800000, 0xff800000, 0x7fc12345, 0xffc12345]
        for field in 1...5 {
            for raw in values {
                let bytes = String(format: "%02x", field << 3 | 5) + littleEndian(raw)
                let color = try decode(bytes)
                let actual = [color.linearRed, color.linearGreen, color.linearBlue, color.opacity, color._headroom][field - 1]
                XCTAssertEqual(actual.bitPattern, raw)
                let omitted: Bool
                if field == 4 { omitted = raw == 0x3f800000 }
                else if field == 5 { omitted = actual == 0 || actual.isNaN }
                else { omitted = actual == 0 }
                XCTAssertEqual(try encode(color), omitted ? "" : bytes)
            }
        }
        XCTAssertTrue(try decode(encode(decode("2d00000000")))._headroom.isNaN)
        XCTAssertEqual(try decode(encode(decode("2500000080"))).opacity.bitPattern, 0x80000000)
    }

    func testDuplicateAndPackedComponentsUseTheLastValue() throws {
        let color = try decode("0d0000803f0d000000402a080000004000004040")
        XCTAssertEqual(color.linearRed, 2)
        XCTAssertEqual(color.headroom, 3)
        XCTAssertEqual(try encode(color), "0d000000402d00004040")
    }

    func testMalformedFieldsThrowAndUnknownSupportedWiresAreSkipped() throws {
        for bytes in ["00", "07", "80", "0801", "090000000000000000", "0a00", "0a03000000", "0d00", "2a0500000000", "7b", "7c", "7e", "7f"] {
            XCTAssertThrowsError(try decode(bytes), bytes)
        }
        for unknown in ["7801", "790000000000000000", "7a020000", "7d00000000"] {
            XCTAssertEqual(try encode(decode(unknown + "2d00004040")), "2d00004040")
        }
    }

    private func decode(_ text: String) throws -> Color.ResolvedHDR {
        let bytes = Array(text.utf8)
        var decoder = ProtobufDecoder(Data(stride(from: 0, to: bytes.count, by: 2).map {
            UInt8(String(decoding: bytes[$0..<$0+2], as: UTF8.self), radix: 16)!
        }))
        return try Color.ResolvedHDR(from: &decoder)
    }
    private func encode(_ value: Color.ResolvedHDR) throws -> String {
        try ProtobufEncoder.encoding(value).map { String(format: "%02x", $0) }.joined()
    }
    private func littleEndian(_ value: UInt32) -> String {
        (0..<4).map { String(format: "%02x", (value >> ($0 * 8)) & 255) }.joined()
    }
}
