import Foundation
import XCTest
@testable import VUI

final class ProtobufDecoderTests: XCTestCase {
    func testFieldRepresentationAndInvalidFieldNumbers() throws {
        // ASSERTIONS protobufFormatFieldIterationObserved
        let field = ProtobufFormat.Field(7, wireType: .fixed32)
        XCTAssertEqual(field.rawValue, 61)
        XCTAssertEqual(field.tag, 7)
        XCTAssertEqual(field.wireType, .fixed32)
        XCTAssertFalse(field._isEmpty)
        XCTAssertTrue(ProtobufFormat.Field(rawValue: 0)._isEmpty)
        for tag in UInt8(0)...7 {
            var decoder = ProtobufDecoder(Data([tag, 8, 1]))
            XCTAssertThrowsError(try decoder.nextField())
            XCTAssertEqual(cursor(decoder), 1)
            XCTAssertEqual(try decoder.nextField()?.rawValue, 8)
            XCTAssertEqual(try decoder.uintField(.init(rawValue: 8)), 1)
        }
        var decoder = ProtobufDecoder(Data([11]))
        let unsupported = try XCTUnwrap(decoder.nextField())
        XCTAssertEqual(unsupported.wireType.rawValue, 3)
        XCTAssertThrowsError(try decoder.skipField(unsupported))
    }

    func testCopiesShareImmutableBytesAndSeparateCursorStackAndUserInfo() throws {
        // ASSERTIONS protobufDecoderStorageOwnershipObserved
        final class Token { var value = 17 }
        let token = Token()
        let key = CodingUserInfoKey(rawValue: "token")!
        var source = Data([1, 0, 8, 1])
        var original = ProtobufDecoder(source)
        original.userInfo[key] = token
        source[0] = 255
        var copy = original
        XCTAssertTrue(original.data === copy.data)
        XCTAssertEqual(original.data as Data, Data([1, 0, 8, 1]))
        try copy.beginMessage()
        XCTAssertEqual(cursor(original), 0)
        XCTAssertTrue(original.stack.isEmpty)
        XCTAssertEqual(cursor(copy), 1)
        XCTAssertEqual(copy.data.bytes.distance(to: copy.end), 2)
        XCTAssertEqual(copy.stack, [original.end])
        (copy.userInfo[key] as! Token).value = 23
        copy.userInfo.removeAll()
        XCTAssertEqual(original.userInfo.count, 1)
        XCTAssertEqual((original.userInfo[key] as! Token).value, 23)
    }

    func testPackedFieldYieldsOneValueAtATimeAndPreservesItsEnd() throws {
        // ASSERTIONS protobufFormatFieldIterationObserved
        // ASSERTIONS protobufDecoderPackedScalarObserved
        var decoder = ProtobufDecoder(Data([10, 2, 1, 2, 16, 3]))
        let first = try XCTUnwrap(decoder.nextField())
        XCTAssertEqual(first.rawValue, 10)
        XCTAssertEqual(try decoder.uintField(first), 1)
        XCTAssertEqual(cursor(decoder), 3)
        XCTAssertEqual(decoder.packedField.rawValue, 8)
        XCTAssertEqual(decoder.data.bytes.distance(to: decoder.packedEnd), 4)
        let second = try XCTUnwrap(decoder.nextField())
        XCTAssertEqual(second.rawValue, 8)
        XCTAssertEqual(cursor(decoder), 3)
        try decoder.skipField(second)
        let following = try XCTUnwrap(decoder.nextField())
        XCTAssertEqual(following.rawValue, 16)
        XCTAssertEqual(try decoder.uintField(following), 3)
        XCTAssertNil(try decoder.nextField())
        XCTAssertTrue(decoder.packedField._isEmpty)
        XCTAssertEqual(decoder.data.bytes.distance(to: decoder.packedEnd), 4)
    }

    func testPackedOverrunFailsOnNextFieldExceptAtEnclosingEOF() throws {
        // ASSERTIONS protobufDecoderPackedScalarObserved
        for length in UInt8(0)...3 {
            for suffix in [Data(), Data([16, 3])] {
                var decoder = ProtobufDecoder(Data([10, length, 0, 0, 128, 63]) + suffix)
                let field = try XCTUnwrap(decoder.nextField())
                XCTAssertEqual(try decoder.floatField(field), 1)
                XCTAssertEqual(cursor(decoder), 6)
                XCTAssertEqual(decoder.packedField.rawValue, 13)
                if suffix.isEmpty {
                    XCTAssertNil(try decoder.nextField())
                    XCTAssertTrue(decoder.packedField._isEmpty)
                } else {
                    XCTAssertThrowsError(try decoder.nextField())
                    XCTAssertEqual(decoder.packedField.rawValue, 13)
                    XCTAssertEqual(cursor(decoder), 6)
                }
            }
        }
    }

    func testShortPackedReadRetainsPreparedStateWithoutAdvancingTheScalar() throws {
        // ASSERTIONS protobufDecoderPackedScalarObserved
        var decoder = ProtobufDecoder(Data([10, 3, 0, 0, 0]))
        let field = try XCTUnwrap(decoder.nextField())
        XCTAssertThrowsError(try decoder.fixed32Field(field))
        XCTAssertEqual(cursor(decoder), 2)
        XCTAssertEqual(decoder.packedField.rawValue, 13)
        XCTAssertEqual(decoder.data.bytes.distance(to: decoder.packedEnd), 5)
        XCTAssertEqual(try decoder.nextField()?.rawValue, 13)
    }

    func testDoubleAcceptsFixed32WhilePackedDoubleUsesFixed64() throws {
        // ASSERTIONS protobufDecoderPackedScalarObserved
        var direct = ProtobufDecoder(Data([0, 0, 128, 63]))
        XCTAssertEqual(try direct.doubleField(.init(rawValue: 13)), 1)
        var packed = ProtobufDecoder(Data([8, 0, 0, 0, 0, 0, 0, 240, 63]))
        XCTAssertEqual(try packed.cgFloatField(.init(rawValue: 10)), 1)
        XCTAssertEqual(packed.packedField.rawValue, 9)
        var wrong = ProtobufDecoder(Data(repeating: 0, count: 8))
        XCTAssertThrowsError(try wrong.floatField(.init(rawValue: 9)))
        XCTAssertEqual(cursor(wrong), 0)
    }

    func testVarintConsumesOverlongEncodingsAndTruncatesHighPayloadBits() throws {
        // ASSERTIONS protobufDecoderVarintOverflowObserved
        for (count, terminal, expected): (Int, UInt8, UInt) in [
            (9, 1, .max), (9, 2, UInt.max >> 1), (9, 3, .max),
            (10, 0, .max), (20, 127, .max)
        ] {
            var decoder = ProtobufDecoder(Data(repeating: 255, count: count) + Data([terminal]))
            XCTAssertEqual(try decoder.decodeVarint(), expected)
            XCTAssertEqual(cursor(decoder), count + 1)
        }
        var unfinished = ProtobufDecoder(Data(repeating: 255, count: 20))
        XCTAssertThrowsError(try unfinished.decodeVarint())
        XCTAssertEqual(cursor(unfinished), 20)
    }

    func testIntegerFieldsUseSignedShiftAndTruncateNarrowResults() throws {
        // ASSERTIONS protobufDecoderVarintOverflowObserved
        for (raw, expected): (UInt, Int) in [(0, 0), (1, -1), (2, 1), (.max, 0), (1 << 63, Int.min >> 1)] {
            var encoder = ProtobufEncoder()
            encoder.encodeVarint(raw)
            var decoder = ProtobufDecoder(encoder.data)
            XCTAssertEqual(try decoder.intField(.init(rawValue: 8)), expected)
        }
        var narrow = ProtobufDecoder(Data([129, 2]))
        XCTAssertEqual(try narrow.uint8Field(.init(rawValue: 8)), 1)
        var boolean = ProtobufDecoder(Data([2]))
        XCTAssertTrue(try boolean.boolField(.init(rawValue: 8)))
    }

    func testMessageEarlyReturnRestoresEndWithoutConsumingRemainingBytes() throws {
        // ASSERTIONS protobufDecoderNestedMessageStateObserved
        struct Empty: ProtobufDecodableMessage { init(from decoder: inout ProtobufDecoder) {} }
        var decoder = ProtobufDecoder(Data([2, 8, 1, 16, 2]))
        let _: Empty = try decoder.decodeMessage()
        XCTAssertEqual(cursor(decoder), 1)
        XCTAssertEqual(decoder.data.bytes.distance(to: decoder.end), 5)
        XCTAssertTrue(decoder.stack.isEmpty)
        XCTAssertEqual(try decoder.nextField()?.rawValue, 8)
        XCTAssertEqual(try decoder.uintField(.init(rawValue: 8)), 1)
    }

    func testMessageBodyFailureAndLengthFailureLeaveDifferentStackStates() throws {
        // ASSERTIONS protobufDecoderNestedMessageStateObserved
        enum BodyError: Error { case failed }
        var body = ProtobufDecoder(Data([1, 1, 16, 2]))
        XCTAssertThrowsError(try body.decodeMessage { nested in
            XCTAssertEqual(try nested.decodeVarint(), 1)
            throw BodyError.failed
        } as Void)
        XCTAssertEqual(cursor(body), 2)
        XCTAssertEqual(body.data.bytes.distance(to: body.end), 4)
        XCTAssertTrue(body.stack.isEmpty)

        var length = ProtobufDecoder(Data([5, 1]))
        XCTAssertThrowsError(try length.decodeMessage { _ in } as Void)
        XCTAssertEqual(cursor(length), 1)
        XCTAssertEqual(length.stack, [length.end])

        var nested = ProtobufDecoder(Data([1, 128, 16, 1]))
        XCTAssertThrowsError(try nested.decodeMessage { child in
            try child.beginMessage()
        } as Void)
        XCTAssertEqual(cursor(nested), 2)
        XCTAssertEqual(nested.data.bytes.distance(to: nested.end), 2)
        XCTAssertEqual(nested.stack, [nested.data.bytes + 4])
    }

    func testMessageExitDoesNotRestorePackedState() throws {
        // ASSERTIONS protobufDecoderNestedMessageStateObserved
        var decoder = ProtobufDecoder(Data([3, 2, 1, 2, 16, 3]))
        let value = try decoder.decodeMessage { nested in
            try nested.uintField(.init(rawValue: 10))
        }
        XCTAssertEqual(value, 1)
        XCTAssertEqual(cursor(decoder), 3)
        XCTAssertEqual(decoder.packedField.rawValue, 8)
        XCTAssertEqual(decoder.data.bytes.distance(to: decoder.packedEnd), 4)
        XCTAssertEqual(try decoder.nextField()?.rawValue, 8)
        XCTAssertEqual(try decoder.uintField(.init(rawValue: 8)), 2)
        XCTAssertEqual(try decoder.nextField()?.rawValue, 16)
    }

    func testDataBuffersBorrowOwnerWithoutChangingMessageStack() throws {
        // ASSERTIONS protobufDecoderStorageOwnershipObserved
        var decoder = ProtobufDecoder(Data([2, 8, 1, 16, 3]))
        let bytes = try decoder.dataBufferField(.init(rawValue: 10))
        XCTAssertEqual(bytes.baseAddress, decoder.data.bytes + 1)
        XCTAssertEqual(Array(bytes), [8, 1])
        XCTAssertEqual(cursor(decoder), 3)
        XCTAssertTrue(decoder.stack.isEmpty)
        XCTAssertEqual(decoder.data.bytes.distance(to: decoder.end), 5)
        XCTAssertEqual(try decoder.nextField()?.rawValue, 16)
    }

    func testUnrepresentableLengthsKeepBoundedFailure() throws {
        var encoder = ProtobufEncoder()
        encoder.encodeVarint(.max)
        var decoder = ProtobufDecoder(encoder.data)
        XCTAssertThrowsError(try decoder.beginMessage())
        XCTAssertEqual(cursor(decoder), 10)
        XCTAssertEqual(decoder.stack, [decoder.end])
    }

    private func cursor(_ decoder: ProtobufDecoder) -> Int {
        decoder.data.bytes.distance(to: decoder.ptr)
    }
}
