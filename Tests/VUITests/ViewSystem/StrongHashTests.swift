import Foundation
import XCTest
@testable import VUI

final class StrongHashTests: XCTestCase {
    func testStrongHasherUsesSHA1DigestWords() {
        var emptyHasher = StrongHasher()
        XCTAssertWordsEqual(
            emptyHasher.finalize().words,
            (0xeea339da, 0x0d4b6b5e, 0xefbf5532, 0x90186095, 0x0907d8af)
        )

        XCTAssertWordsEqual(
            StrongHash(of: "abc").words,
            (0x363e99a9, 0x6a810647, 0x71253eba, 0x6cc25078, 0x9dd8d09c)
        )
    }

    func testStringAndDataHashRawBytes() {
        let stringHash = StrongHash(of: "abc")
        let dataHash = StrongHash(of: Data([0x61, 0x62, 0x63]))
        XCTAssertEqual(stringHash, dataHash)
    }

    func testBitPatternAndBoolHashing() {
        var bitPatternHasher = StrongHasher()
        bitPatternHasher.combineBitPattern(UInt32(0x01020304))

        var byteHasher = StrongHasher()
        withUnsafeBytes(of: UInt32(0x01020304)) { bytes in
            byteHasher.combineBytes(bytes.baseAddress!, count: bytes.count)
        }
        XCTAssertEqual(bitPatternHasher.finalize(), byteHasher.finalize())

        var trueByteHasher = StrongHasher()
        var trueByte: UInt8 = 1
        withUnsafeBytes(of: &trueByte) { bytes in
            trueByteHasher.combineBytes(bytes.baseAddress!, count: bytes.count)
        }
        XCTAssertEqual(StrongHash(of: true), trueByteHasher.finalize())
    }

    func testOptionalHashingUsesWrappedValueWhenPresent() {
        let empty = StrongHash()
        var emptyHasher = StrongHasher()
        let emptyDigest = emptyHasher.finalize()

        XCTAssertEqual(empty, StrongHash(words: (0, 0, 0, 0, 0)))
        XCTAssertEqual(StrongHash(of: Optional<String>.none), emptyDigest)
        XCTAssertEqual(StrongHash(of: Optional.some("abc")), StrongHash(of: "abc"))
    }

    func testCombineTypeHashesAGTypeSignatureBytes() {
        assertCombineType(Int.self, produces: StrongHash(words: (
            0x52fb7a46, 0x48741f56, 0xc4085c41, 0xb665eaa4, 0x7a490d50
        )))
        assertCombineType(String.self, produces: StrongHash(words: (
            0x278cdbb2, 0x1299e557, 0x01bcc321, 0x80c3ba5a, 0xa55859f3
        )))
        assertCombineType(Optional<Int>.self, produces: StrongHash(words: (
            0x27bfda6f, 0x58bc5a13, 0x19bde475, 0xd7158a4a, 0xe680b642
        )))
        assertCombineType(Array<Int>.self, produces: StrongHash(words: (
            0x744e5be3, 0x4a974e8a, 0x54467057, 0x66bad7bd, 0xc0b84b80
        )))
        assertCombineType(Dictionary<String, Int>.self, produces: StrongHash(words: (
            0xa69e428c, 0x86294f4d, 0x566263e4, 0xd45a7884, 0x42ac3ad0
        )))
    }

    func testCombineTypeDistinguishesMetadataShapes() {
        let types: [Any.Type] = [
            StrongHashTestClass.self,
            StrongHashTestStruct.self,
            StrongHashTestEnum.self,
            Optional<Int>.self,
            (x: Int, String).self,
            ((Int) -> String).self,
            (any StrongHashTestProtocol).self,
            Int.Type.self,
        ]
        let hashes = types.map(combineTypeHash)

        XCTAssertEqual(Set(hashes).count, types.count)
        XCTAssertEqual(combineTypeHash(StrongHashTestStruct.self), hashes[1])
    }

    func testEncodableInitializerHashesStableJSONBytes() throws {
        let value = StrongHashEncodablePair(b: 2, a: 1)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"a\":1,\"b\":2}")
        XCTAssertEqual(try StrongHash(encodable: value), StrongHash(of: data))
        XCTAssertThrowsError(try StrongHash(encodable: Double.infinity))
    }

    func testCodableUsesFiveUnkeyedWords() throws {
        let hash = StrongHash(words: (1, 2, 3, 4, 5))
        let data = try JSONEncoder().encode(hash)

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[1,2,3,4,5]")
        XCTAssertEqual(try JSONDecoder().decode(StrongHash.self, from: data), hash)
    }

    func testProtobufUsesLengthDelimitedFiveWords() throws {
        let hash = StrongHash(words: (1, 2, 3, 4, 5))
        let expectedBytes: [UInt8] = [
            0x0a, 0x14,
            0x01, 0x00, 0x00, 0x00,
            0x02, 0x00, 0x00, 0x00,
            0x03, 0x00, 0x00, 0x00,
            0x04, 0x00, 0x00, 0x00,
            0x05, 0x00, 0x00, 0x00,
        ]

        let data = try ProtobufEncoder.encoding(hash)
        XCTAssertEqual(Array(data), expectedBytes)

        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try StrongHash(from: &decoder), hash)
    }

    func testProtobufDecodesFixed32RepeatedFieldAndDefaultsMissingWords() throws {
        let data = Data([
            0x0d, 0x01, 0x00, 0x00, 0x00,
            0x0d, 0x02, 0x00, 0x00, 0x00,
            0x0d, 0x03, 0x00, 0x00, 0x00,
        ])

        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(
            try StrongHash(from: &decoder),
            StrongHash(words: (1, 2, 3, 0, 0))
        )
    }

    func testProtobufSkipsUnknownFieldsAndRejectsMalformedPackedWords() throws {
        var decoder = ProtobufDecoder(Data([
            0x10, 0xff, 0x01,
            0x12, 0x02, 0xaa, 0xbb,
            0x0a, 0x04, 0x2a, 0x00, 0x00, 0x00,
        ]))
        XCTAssertEqual(try StrongHash(from: &decoder), StrongHash(words: (42, 0, 0, 0, 0)))

        var malformed = ProtobufDecoder(Data([0x0a, 0x03, 0x01, 0x00, 0x00]))
        XCTAssertThrowsError(try StrongHash(from: &malformed))
    }

    private func XCTAssertWordsEqual(
        _ lhs: (UInt32, UInt32, UInt32, UInt32, UInt32),
        _ rhs: (UInt32, UInt32, UInt32, UInt32, UInt32),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual([lhs.0, lhs.1, lhs.2, lhs.3, lhs.4], [rhs.0, rhs.1, rhs.2, rhs.3, rhs.4], file: file, line: line)
    }

    private func assertCombineType(
        _ type: Any.Type,
        produces expected: StrongHash,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(combineTypeHash(type), expected, file: file, line: line)
    }

    private func combineTypeHash(_ type: Any.Type) -> StrongHash {
        var hasher = StrongHasher()
        hasher.combineType(type)
        return hasher.finalize()
    }
}

private struct StrongHashEncodablePair: Encodable {
    var b: Int
    var a: Int
}

private final class StrongHashTestClass {
}

private struct StrongHashTestStruct {
}

private enum StrongHashTestEnum {
    case value
}

private protocol StrongHashTestProtocol {
}
