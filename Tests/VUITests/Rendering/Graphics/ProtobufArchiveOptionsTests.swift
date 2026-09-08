import Foundation
import XCTest
@testable import VUI

final class ProtobufArchiveOptionsTests: XCTestCase {
    private let key = ArchivedViewCore.archiveOptionsKey

    // ASSERTIONS protobufArchiveOptionsLookupObserved
    func testArchiveOptionsReadTypedValueAndUseDefaultForMissingOrWrongTypes() {
        var encoder = ProtobufEncoder(options: .init(rawValue: 0x400))
        let expected = ArchivedViewInput.Value(
            flags: .init(rawValue: 0xff), deploymentVersion: .init(rawValue: -1)
        )
        XCTAssertEqual(encoder.archiveOptions, ArchivedViewInput.Value())
        encoder.userInfo[CodingUserInfoKey(rawValue: "archiveOptions")!] = expected
        XCTAssertEqual(encoder.archiveOptions, ArchivedViewInput.Value())

        for wrongValue: Any in [
            1024, NSNumber(value: 1024), "1024",
            ["flags": 255, "version": -1],
            SimilarValue(flags: 255, version: -1),
            Optional<ArchivedViewInput.Value>.none as Any,
        ] {
            encoder.userInfo[key] = wrongValue
            XCTAssertEqual(encoder.archiveOptions, ArchivedViewInput.Value())
        }
        encoder.userInfo[key] = expected
        XCTAssertEqual(encoder.archiveOptions, expected)
        encoder.userInfo[key] = Optional.some(expected) as Any
        XCTAssertEqual(encoder.archiveOptions, expected)
        encoder.userInfo[key] = nil
        XCTAssertEqual(encoder.archiveOptions, ArchivedViewInput.Value())
    }

    // ASSERTIONS protobufArchiveOptionsOwnershipObserved
    func testEncoderCopiesSeparateUserInfoWhileSharingReferenceValues() {
        let tokenKey = CodingUserInfoKey(rawValue: "token")!
        let token = Token()
        let originalValue = ArchivedViewInput.Value(
            flags: .init(rawValue: 3), deploymentVersion: .v5
        )
        let copiedValue = ArchivedViewInput.Value(
            flags: .init(rawValue: 5), deploymentVersion: .v7_4
        )
        var original = ProtobufEncoder()
        original.userInfo = [key: originalValue, tokenKey: token]
        var copy = original
        (copy.userInfo[tokenKey] as! Token).count = 7
        copy.userInfo[key] = copiedValue
        copy.userInfo[tokenKey] = nil

        XCTAssertEqual(original.archiveOptions, originalValue)
        XCTAssertEqual(copy.archiveOptions, copiedValue)
        XCTAssertEqual(original.userInfo.count, 2)
        XCTAssertEqual(copy.userInfo.count, 1)
        XCTAssertEqual((original.userInfo[tokenKey] as! Token).count, 7)
    }

    // ASSERTIONS protobufArchiveOptionsNestedPropagationObserved
    func testNestedMessageUpdatesOptionsForFollowingMessages() throws {
        let result = try ProtobufEncoder.encoding(options: .singlePrecisionCGFloat) { encoder in
            encoder.userInfo[key] = ArchivedViewInput.Value(
                flags: .init(rawValue: 3), deploymentVersion: .v5
            )
            try encoder.encodeMessageField(11, UpdatingMessage())
            XCTAssertEqual(encoder.archiveOptions, ArchivedViewInput.Value(
                flags: .init(rawValue: 5), deploymentVersion: .v7_4
            ))
            XCTAssertEqual(encoder.options, .singlePrecisionCGFloat)
            try RepeatAnimation(repeatCount: 4, autoreverses: true).encode(to: &encoder)
        }
        XCTAssertEqual(result, Data([
            0x5a, 0x14,
            0x21, 0, 0, 0, 0, 0, 0, 0, 0x40,
            0x42, 0x09, 0x19, 0, 0, 0, 0, 0, 0, 0x08, 0x40,
            0x42, 0x06, 0x12, 0x04, 0x08, 0x08, 0x10, 0x01,
        ]))
    }

    // ASSERTIONS protobufArchiveOptionsOwnershipObserved
    func testEncodingReleasesUserInfoOnThrowAndStartsFreshForEachCall() throws {
        weak var releasedToken: Token?
        XCTAssertThrowsError(try ProtobufEncoder.encoding { encoder in
            let token = Token()
            releasedToken = token
            encoder.userInfo[key] = ArchivedViewInput.Value(
                flags: .init(rawValue: 255), deploymentVersion: .init(rawValue: -1)
            )
            encoder.userInfo[CodingUserInfoKey(rawValue: "token")!] = token
            throw BodyError.failed
        }) { error in
            XCTAssertTrue(error is BodyError)
        }
        XCTAssertNil(releasedToken)

        let empty = try ProtobufEncoder.encoding { encoder in
            XCTAssertTrue(encoder.userInfo.isEmpty)
            XCTAssertEqual(encoder.archiveOptions, ArchivedViewInput.Value())
            XCTAssertEqual(encoder.options, [])
        }
        XCTAssertEqual(empty, Data())
        XCTAssertEqual(
            try ProtobufEncoder.encoding(DelayAnimation(delay: 2)),
            Data([0x42, 0x09, 0x09, 0, 0, 0, 0, 0, 0, 0, 0x40])
        )
    }

    private struct SimilarValue {
        let flags: UInt8
        let version: Int8
    }

    private final class Token {
        var count = 1
    }

    private enum BodyError: Error {
        case failed
    }

    private struct UpdatingMessage: ProtobufEncodableMessage {
        func encode(to encoder: inout ProtobufEncoder) throws {
            XCTAssertEqual(encoder.archiveOptions, ArchivedViewInput.Value(
                flags: .init(rawValue: 3), deploymentVersion: .v5
            ))
            XCTAssertEqual(encoder.options, .singlePrecisionCGFloat)
            try DelayAnimation(delay: 2).encode(to: &encoder)
            encoder.userInfo[ArchivedViewCore.archiveOptionsKey] = ArchivedViewInput.Value(
                flags: .init(rawValue: 5), deploymentVersion: .v7_4
            )
            try SpeedAnimation(speed: 3).encode(to: &encoder)
        }
    }
}
