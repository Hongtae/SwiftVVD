import Foundation
import XCTest
@testable import VUI

final class ResolvedGradientProtobufTests: XCTestCase {
    private let stopBytes = "0a140d0000803e15000000bf1d00000040250000403f150000c03e1a140d0000803e15000080bf1d0000403f2500000040"

    func testEmptyMessagesKeepDistinctColorAndColorSpaceDefaults() throws {
        let empty: ResolvedGradient.Stop = try decode("")
        XCTAssertEqual(empty.color.opacity, 0)
        XCTAssertEqual(empty.location, 0)
        XCTAssertNil(empty.interpolation)
        XCTAssertEqual(try encode(empty), "0a052500000000")

        let presentColor: ResolvedGradient.Stop = try decode("0a00")
        XCTAssertEqual(presentColor.color.opacity, 1)
        XCTAssertEqual(try encode(presentColor), "0a00")
        let presentCurve: ResolvedGradient.Stop = try decode("1a00")
        XCTAssertEqual(presentCurve.interpolation, .init(p1x: 0, p1y: 0, p2x: 1, p2y: 1))

        let gradient: ResolvedGradient = try decode("")
        XCTAssertEqual(gradient.stops, [])
        XCTAssertEqual(gradient.colorSpace, .perceptual)
        XCTAssertNil(gradient.headroom)
        XCTAssertEqual(try encode(gradient), "1002")
        let device: ResolvedGradient = try decode("1000")
        XCTAssertEqual(device.colorSpace, .device)
        XCTAssertEqual(try encode(device), "")
        let restored: ResolvedGradient = try decode(encode(device))
        XCTAssertEqual(restored.colorSpace, .perceptual)
    }

    func testStopStoresLinearComponentsAndOptionalCurveWithoutConversion() throws {
        let stop: ResolvedGradient.Stop = try decode(stopBytes)
        XCTAssertEqual(stop.color.linearRed, 0.25)
        XCTAssertEqual(stop.color.linearGreen, -0.5)
        XCTAssertEqual(stop.color.linearBlue, 2)
        XCTAssertEqual(stop.color.opacity, 0.75)
        XCTAssertEqual(stop.location, 0.375)
        XCTAssertEqual(stop.interpolation, .init(p1x: 0.25, p1y: -1, p2x: 0.75, p2y: 2))
        XCTAssertEqual(try encode(stop), stopBytes)
    }

    func testGradientRetainsOrderedStopsAndPresentZeroHeadroom() throws {
        let bytes = "0a31" + stopBytes + "0a00" + "0a31" + stopBytes + "10011d00000000"
        let gradient: ResolvedGradient = try decode(bytes)
        XCTAssertEqual(gradient.stops.map(\.location), [0.375, 0, 0.375])
        XCTAssertEqual(gradient.stops[0], gradient.stops[2])
        XCTAssertEqual(gradient.stops[1].color.opacity, 0)
        XCTAssertEqual(gradient.colorSpace, .linear)
        XCTAssertEqual(gradient.headroom, 0)
        let original = gradient
        let address = gradient.stops.withUnsafeBufferPointer { $0.baseAddress }
        XCTAssertEqual(try encode(gradient), "0a31" + stopBytes + "0a070a0525000000000a31" + stopBytes + "10011d00000000")
        XCTAssertEqual(gradient, original)
        XCTAssertEqual(gradient.stops.withUnsafeBufferPointer { $0.baseAddress }, address)
    }

    func testPaintMessagesKeepConcreteGeometryAndUseTheSameFieldSchema() throws {
        let gradient = "0a31" + stopBytes + "10011d00000040"
        let bytes = "0a3a" + gradient + "120a0d0000004015000040c01a0a0d0000a040150000e0402002"
        let unit: LinearGradient._Paint = try decode(bytes)
        let absolute: LinearGradient.AbsolutePaint = try decode(bytes)
        XCTAssertEqual(unit.gradient, absolute.gradient)
        XCTAssertEqual(unit.startPoint, UnitPoint(x: 2, y: -3))
        XCTAssertEqual(unit.endPoint, UnitPoint(x: 5, y: 7))
        XCTAssertEqual(absolute.startPoint, CGPoint(x: 2, y: -3))
        XCTAssertEqual(absolute.endPoint, CGPoint(x: 5, y: 7))
        XCTAssertEqual(unit.allowedDynamicRange, .high)
        XCTAssertEqual(absolute.allowedDynamicRange, .high)
        XCTAssertEqual(try encode(unit), bytes)
        XCTAssertEqual(try encode(absolute), bytes)

        let emptyUnit: LinearGradient._Paint = try decode("")
        let emptyAbsolute: LinearGradient.AbsolutePaint = try decode("")
        XCTAssertEqual(try encode(emptyUnit), "0a021002")
        XCTAssertEqual(try encode(emptyAbsolute), "0a021002")
        XCTAssertEqual(emptyUnit.startPoint, .init(x: 0, y: 0))
        XCTAssertEqual(emptyAbsolute.endPoint, .zero)
        XCTAssertEqual(emptyUnit.allowedDynamicRange, .standard)
    }

    func testDuplicateMessagesReplaceWholeValues() throws {
        let stop: ResolvedGradient.Stop = try decode(stopBytes + "0a001a00150000403f")
        XCTAssertEqual(stop.color, .init(colorSpace: .sRGBLinear, red: 0, green: 0, blue: 0))
        XCTAssertEqual(stop.interpolation, .init(p1x: 0, p1y: 0, p2x: 1, p2y: 1))
        XCTAssertEqual(stop.location, 0.75)
        let bytes = "0a0410011a00" // A zero-length packed headroom is malformed.
        XCTAssertThrowsError(try decode(bytes) as LinearGradient._Paint)

        let paintBytes = "0a0210010a00120a0d000000401500004040120515000080401a050d0000a0401a00"
        let unit: LinearGradient._Paint = try decode(paintBytes)
        let absolute: LinearGradient.AbsolutePaint = try decode(paintBytes)
        XCTAssertEqual(unit.gradient.colorSpace, .perceptual)
        XCTAssertEqual(unit.startPoint, .init(x: 0, y: 4))
        XCTAssertEqual(absolute.startPoint, .init(x: 0, y: 4))
        XCTAssertEqual(unit.endPoint, .init(x: 0, y: 0))
        XCTAssertEqual(absolute.endPoint, .zero)
    }

    func testEnumFieldsUseFullRawValuesAndPackedLastValue() throws {
        for raw: UInt in [0, 1, 2, 3, 255, 256, 257, .max] {
            var encoder = ProtobufEncoder()
            encoder.encodeVarint(raw)
            let suffix = hex(encoder.data)
            let gradient: ResolvedGradient = try decode("10" + suffix)
            let unit: LinearGradient._Paint = try decode("20" + suffix)
            let absolute: LinearGradient.AbsolutePaint = try decode("20" + suffix)
            XCTAssertEqual(gradient.colorSpace, raw == 1 ? .linear : raw == 2 ? .perceptual : .device)
            let range: Image.DynamicRange = raw == 1 ? .constrainedHigh : raw == 2 ? .high : .standard
            XCTAssertEqual(unit.allowedDynamicRange, range)
            XCTAssertEqual(absolute.allowedDynamicRange, range)
        }
        let gradient: ResolvedGradient = try decode("120202011a080000803f00004040")
        XCTAssertEqual(gradient.colorSpace, .linear)
        XCTAssertEqual(gradient.headroom, 3)
        XCTAssertEqual(try encode(gradient), "10011d00004040")
        let unit: LinearGradient._Paint = try decode("22020201")
        XCTAssertEqual(unit.allowedDynamicRange, .constrainedHigh)
    }

    func testPackedScalarsAndUnknownFields() throws {
        let stop: ResolvedGradient.Stop = try decode("0a0a0a080000803e0000403f1210000000000000d03f000000000000e83f1a0a1a080000803e0000403f")
        XCTAssertEqual(stop.color.linearRed, 0.75)
        XCTAssertEqual(stop.location, 0.75)
        XCTAssertEqual(stop.interpolation?.p2x, 0.75)
        for unknown in ["7807", "790000000000000000", "7a020000", "7d00000000"] {
            let gradient: ResolvedGradient = try decode(unknown + "1001")
            XCTAssertEqual(gradient.colorSpace, .linear)
        }
    }

    func testMalformedTagsWiresAndNestedLengthsThrow() throws {
        let common = (0...7).map { String(format: "%02x00", $0) } + ["80", "7b", "7c", "7e", "7f", "7a0400", "0a0900"]
        for bytes in common {
            XCTAssertThrowsError(try decode(bytes) as ResolvedGradient.Stop, bytes)
            XCTAssertThrowsError(try decode(bytes) as ResolvedGradient, bytes)
            XCTAssertThrowsError(try decode(bytes) as LinearGradient._Paint, bytes)
            XCTAssertThrowsError(try decode(bytes) as LinearGradient.AbsolutePaint, bytes)
        }
        for bytes in ["1200", "12020000", "0a020a00", "1a021a00"] {
            XCTAssertThrowsError(try decode(bytes) as ResolvedGradient.Stop, bytes)
        }
        for bytes in ["1200", "1a00", "1a0200001d00000040"] {
            XCTAssertThrowsError(try decode(bytes) as ResolvedGradient, bytes)
        }
        XCTAssertThrowsError(try decode("2200") as LinearGradient._Paint)
        XCTAssertThrowsError(try decode("2200") as LinearGradient.AbsolutePaint)
        for bytes in ["12020000", "1a020000"] {
            XCTAssertThrowsError(try decode(bytes) as LinearGradient._Paint)
            XCTAssertThrowsError(try decode(bytes) as LinearGradient.AbsolutePaint)
        }
    }

    func testCGFloatEncodingUsesMagnitudeThresholdAndPropagatesOptions() throws {
        struct Scalar: ProtobufEncodableMessage {
            let value: CGFloat
            func encode(to encoder: inout ProtobufEncoder) throws {
                encoder.encodeCGFloatFieldAlways(1, value)
            }
        }
        XCTAssertEqual(try encode(Scalar(value: 0.1)), "0dcdcccc3d")
        XCTAssertEqual(try encode(Scalar(value: 65_535.999999)), "0d00008047")
        XCTAssertEqual(try encode(Scalar(value: 65_536)), "09000000000000f040")
        XCTAssertEqual(try encode(Scalar(value: -65_536)), "09000000000000f0c0")
        XCTAssertEqual(try encode(Scalar(value: 1e-300)), "0d00000000")
        XCTAssertEqual(try encode(Scalar(value: .infinity)), "09000000000000f07f")
        XCTAssertEqual(hex(try ProtobufEncoder.encoding(Scalar(value: 65_536), options: .singlePrecisionCGFloat)), "0d00008047")
        let paint = LinearGradient._Paint(gradient: .init(stops: [], colorSpace: .device, headroom: nil), startPoint: .init(x: 65_536, y: 0), endPoint: .init(x: 0, y: 0), allowedDynamicRange: .standard)
        XCTAssertEqual(try encode(paint), "0a00120909000000000000f040")
        XCTAssertEqual(hex(try ProtobufEncoder.encoding(paint, options: .singlePrecisionCGFloat)), "0a0012050d00008047")
    }

    func testNonfiniteComponentsAndSignedZeroKeepScalarRules() throws {
        let stop: ResolvedGradient.Stop = try decode("0a0a0d0000c07f250000807f11000000000000f07f")
        XCTAssertTrue(stop.color.linearRed.isNaN)
        XCTAssertEqual(stop.color.opacity, .infinity)
        XCTAssertEqual(stop.location, .infinity)
        let zero: ResolvedGradient.Stop = try decode("0a050d00000080110000000000000080")
        XCTAssertEqual(zero.location.sign, .minus)
        XCTAssertEqual(try encode(zero), "0a00")
    }

    private func decode<T: ProtobufDecodableMessage>(_ bytes: String) throws -> T {
        let characters = Array(bytes)
        let data = Data(stride(from: 0, to: characters.count, by: 2).map {
            UInt8(String(characters[$0..<$0 + 2]), radix: 16)!
        })
        var decoder = ProtobufDecoder(data)
        return try T(from: &decoder)
    }

    private func encode<T: ProtobufEncodableMessage>(_ value: T) throws -> String {
        hex(try ProtobufEncoder.encoding(value))
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
