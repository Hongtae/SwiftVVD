import Foundation
import XCTest
@testable import VUI

final class CodableAnimationTests: XCTestCase {
    func testLeafCarrierDefaultsElideAllPayloadFields() throws {
        let linear = UnitCurve.CubicSolver(
            startControlPoint: .zero,
            endControlPoint: UnitPoint(x: 1, y: 1)
        )

        XCTAssertEqual(try ProtobufEncoder.encoding(DefaultAnimation()), Data())
        XCTAssertEqual(
            try ProtobufEncoder.encoding(
                BezierAnimation(duration: 0, curve: linear)
            ),
            Data()
        )
        XCTAssertEqual(
            try ProtobufEncoder.encoding(
                SpringAnimation(
                    mass: 1,
                    stiffness: 100,
                    damping: 20,
                    initialVelocity: .zero
                )
            ),
            Data()
        )
        XCTAssertEqual(
            try ProtobufEncoder.encoding(
                FluidSpringAnimation(
                    response: 0,
                    dampingFraction: 0,
                    blendDuration: 0
                )
            ),
            Data()
        )
    }

    func testSpringAnimationUsesFourFixed64FieldsAndRoundTrips() throws {
        let value = SpringAnimation(
            mass: 2,
            stiffness: 3,
            damping: 4,
            initialVelocity: _Velocity(valuePerSecond: 5)
        )
        let data = try ProtobufEncoder.encoding(value)

        XCTAssertEqual(
            data,
            Data([
                0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40,
                0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x40,
                0x19, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x40,
                0x21, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x14, 0x40,
            ])
        )
        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try SpringAnimation(from: &decoder), value)
    }

    func testFluidSpringAnimationUsesThreeFixed64FieldsAndRoundTrips() throws {
        let value = FluidSpringAnimation(
            response: 0.5,
            dampingFraction: 0.75,
            blendDuration: 0.25
        )
        let data = try ProtobufEncoder.encoding(value)

        XCTAssertEqual(
            data,
            Data([
                0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe0, 0x3f,
                0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe8, 0x3f,
                0x19, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xd0, 0x3f,
            ])
        )
        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try FluidSpringAnimation(from: &decoder), value)
    }

    func testBezierAnimationUsesDurationAndControlPointMessage() throws {
        let curve = UnitCurve.CubicSolver(
            startControlPoint: UnitPoint(x: 0.25, y: 0),
            endControlPoint: UnitPoint(x: 0.75, y: 1)
        )
        let value = BezierAnimation(duration: 1, curve: curve)
        let data = try ProtobufEncoder.encoding(value)

        XCTAssertEqual(data.first, 0x09)
        XCTAssertEqual(data[9], 0x12)
        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try BezierAnimation(from: &decoder), value)
    }

    func testModifierMessagesUseArchiveVersionFourEnvelope() throws {
        XCTAssertEqual(
            try ProtobufEncoder.encoding(DelayAnimation(delay: 2)),
            Data([
                0x42, 0x09,
                0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40,
            ])
        )
        XCTAssertEqual(
            try ProtobufEncoder.encoding(SpeedAnimation(speed: 3)),
            Data([
                0x42, 0x09,
                0x19, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x40,
            ])
        )
        XCTAssertEqual(
            try ProtobufEncoder.encoding(
                RepeatAnimation(repeatCount: 4, autoreverses: true)
            ),
            Data([0x42, 0x06, 0x12, 0x04, 0x08, 0x08, 0x10, 0x01])
        )
    }

    func testModifierMessagesPreserveLegacyFieldsBeforeArchiveVersionFour() throws {
        XCTAssertEqual(
            try encode(DelayAnimation(delay: 2), archiveVersion: 3),
            Data([
                0x21, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40,
            ])
        )
        XCTAssertEqual(
            try encode(SpeedAnimation(speed: 3), archiveVersion: 3),
            Data([
                0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x40,
            ])
        )
        XCTAssertEqual(
            try encode(
                RepeatAnimation(repeatCount: 4, autoreverses: true),
                archiveVersion: 3
            ),
            Data([0x2a, 0x04, 0x08, 0x08, 0x10, 0x01])
        )
    }

    func testCodableAnimationWrapsLeavesAndOrderedModifiers() throws {
        XCTAssertEqual(
            try ProtobufEncoder.encoding(CodableAnimation(.default)),
            Data([0x3a, 0x00])
        )
        XCTAssertEqual(
            try ProtobufEncoder.encoding(
                CodableAnimation(
                    .interpolatingSpring(
                        mass: 1,
                        stiffness: 100,
                        damping: 20,
                        initialVelocity: 0
                    )
                )
            ),
            Data([0x12, 0x00])
        )

        let animation = Animation.default
            .delay(2)
            .speed(3)
            .repeatCount(4, autoreverses: true)
        let data = try ProtobufEncoder.encoding(CodableAnimation(animation))
        XCTAssertEqual(
            data,
            Data([
                0x3a, 0x00,
                0x42, 0x09,
                0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40,
                0x42, 0x09,
                0x19, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x40,
                0x42, 0x06, 0x12, 0x04, 0x08, 0x08, 0x10, 0x01,
            ])
        )

        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try CodableAnimation(from: &decoder).base, animation)
    }

    func testCodableAnimationDecodesLegacyModifierFields() throws {
        let data = Data([
            0x3a, 0x00,
            0x21, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40,
            0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x40,
            0x2a, 0x04, 0x08, 0x08, 0x10, 0x01,
        ])
        var decoder = ProtobufDecoder(data)

        XCTAssertEqual(
            try CodableAnimation(from: &decoder).base,
            Animation.default.delay(2).speed(3).repeatCount(4, autoreverses: true)
        )
    }

    func testCodableAnimationRejectsModifierWithoutLeaf() {
        var decoder = ProtobufDecoder(Data([0x42, 0x00]))
        XCTAssertThrowsError(try CodableAnimation(from: &decoder))
    }

    func testCodableAnimationFallsBackToDefaultForNonEncodableCustomBase() throws {
        let data = try ProtobufEncoder.encoding(
            CodableAnimation(Animation(NonEncodableAnimation()))
        )

        XCTAssertEqual(data, Data([0x3a, 0x00]))
    }

    private func encode<Message: ProtobufEncodableMessage>(
        _ message: Message,
        archiveVersion: UInt8
    ) throws -> Data {
        var encoder = ProtobufEncoder(archiveVersion: archiveVersion)
        try message.encode(to: &encoder)
        return encoder.data
    }
}

private struct NonEncodableAnimation: CustomAnimation {
    func animate<V>(
        value: V,
        time: TimeInterval,
        context: inout AnimationContext<V>
    ) -> V? where V: VectorArithmetic {
        value
    }
}
