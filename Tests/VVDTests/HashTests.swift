import Foundation
import XCTest
@testable import VVD

final class HashTests: XCTestCase {
    func testSHA1RawBufferUpdateMatchesDataProtocolUpdate() {
        let bytes = Data((0..<200).map { UInt8($0 & 0xff) })

        var dataHasher = SHA1()
        dataHasher.update(data: bytes)

        var rawHasher = SHA1()
        bytes.withUnsafeBytes { rawBuffer in
            rawHasher.update(bytes: rawBuffer)
        }

        var splitRawHasher = SHA1()
        bytes.withUnsafeBytes { rawBuffer in
            let baseAddress = rawBuffer.baseAddress!
            splitRawHasher.update(bytes: UnsafeRawBufferPointer(start: baseAddress, count: 17))
            splitRawHasher.update(bytes: UnsafeRawBufferPointer(start: baseAddress.advanced(by: 17), count: 47))
            splitRawHasher.update(bytes: UnsafeRawBufferPointer(start: baseAddress.advanced(by: 64), count: bytes.count - 64))
        }

        let dataDigest = dataHasher.finalize().string
        let rawDigest = rawHasher.finalize().string
        let splitRawDigest = splitRawHasher.finalize().string

        XCTAssertEqual(rawDigest, dataDigest)
        XCTAssertEqual(splitRawDigest, rawDigest)
    }

    func testSHA1RawBufferUpdateIgnoresEmptyBuffers() {
        var dataHasher = SHA1()
        dataHasher.update(data: Data())

        var rawHasher = SHA1()
        Data().withUnsafeBytes { rawBuffer in
            rawHasher.update(bytes: rawBuffer)
        }

        XCTAssertEqual(rawHasher.finalize().string, dataHasher.finalize().string)
    }
}
