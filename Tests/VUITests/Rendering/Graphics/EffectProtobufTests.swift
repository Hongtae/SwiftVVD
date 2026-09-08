import Foundation
import XCTest
@testable import VUI

final class EffectProtobufTests: XCTestCase {
    func testDefaultEffectValuesElideAllFields() throws {
        XCTAssertEqual(
            try ProtobufEncoder.encoding(_OpacityEffect(opacity: 1)),
            Data()
        )
        XCTAssertEqual(
            try ProtobufEncoder.encoding(_OffsetEffect(offset: .zero)),
            Data()
        )
        XCTAssertEqual(
            try ProtobufEncoder.encoding(
                _ScaleEffect(scale: CGSize(width: 1, height: 1), anchor: .center)
            ),
            Data()
        )
        XCTAssertEqual(
            try ProtobufEncoder.encoding(_RotationEffect(angle: .zero, anchor: .center)),
            Data()
        )
    }

    func testOpacityEffectUsesFloatFieldAndFloatDefaultComparison() throws {
        let effect = _OpacityEffect(opacity: 0.5)
        let data = try ProtobufEncoder.encoding(effect)

        XCTAssertEqual(data, Data([0x0d, 0x00, 0x00, 0x00, 0x3f]))
        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try _OpacityEffect(from: &decoder), effect)

        let roundsToFloatOne = _OpacityEffect(opacity: 1 - 1e-10)
        XCTAssertEqual(Float(roundsToFloatOne.opacity), 1)
        XCTAssertEqual(try ProtobufEncoder.encoding(roundsToFloatOne), Data())
    }

    func testOffsetEffectUsesNestedSizeField() throws {
        let effect = _OffsetEffect(offset: CGSize(width: 2, height: 3))
        let data = try ProtobufEncoder.encoding(effect)

        XCTAssertEqual(
            data,
            Data([
                0x0a, 0x0a,
                0x0d, 0x00, 0x00, 0x00, 0x40,
                0x15, 0x00, 0x00, 0x40, 0x40,
            ])
        )
        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try _OffsetEffect(from: &decoder), effect)
    }

    func testScaleEffectUsesScaleAndAnchorMessagesWithDistinctDefaults() throws {
        let effect = _ScaleEffect(
            scale: CGSize(width: 2, height: 3),
            anchor: .topLeading
        )
        let data = try ProtobufEncoder.encoding(effect)

        XCTAssertEqual(
            data,
            Data([
                0x0a, 0x0a,
                0x0d, 0x00, 0x00, 0x00, 0x40,
                0x15, 0x00, 0x00, 0x40, 0x40,
                0x12, 0x00,
            ])
        )
        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try _ScaleEffect(from: &decoder), effect)
    }

    func testRotationEffectUsesDoubleAngleAndAnchorMessage() throws {
        let effect = _RotationEffect(angle: .radians(1), anchor: .topLeading)
        let data = try ProtobufEncoder.encoding(effect)

        XCTAssertEqual(
            data,
            Data([
                0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf0, 0x3f,
                0x12, 0x00,
            ])
        )
        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try _RotationEffect(from: &decoder), effect)
    }

    func testGeometryScalarDecoderAcceptsObservedDirectAndPackedForms() throws {
        var sizeDecoder = ProtobufDecoder(
            Data([
                0x0d, 0x00, 0x00, 0x00, 0x3f,
                0x12, 0x10,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe0, 0x3f,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe8, 0x3f,
            ])
        )
        XCTAssertEqual(
            try CGSize(from: &sizeDecoder),
            CGSize(width: 0.5, height: 0.75)
        )

        var opacityDecoder = ProtobufDecoder(
            Data([
                0x0a, 0x08,
                0x00, 0x00, 0x80, 0x3e,
                0x00, 0x00, 0x40, 0x3f,
            ])
        )
        XCTAssertEqual(try _OpacityEffect(from: &opacityDecoder).opacity, 0.75)
    }
}
