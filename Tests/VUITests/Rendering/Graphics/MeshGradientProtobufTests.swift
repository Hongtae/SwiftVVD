import Foundation
import XCTest
@testable import VUI

final class MeshGradientProtobufTests: XCTestCase {
    // ASSERTIONS canvasMeshLocationsProtobufSchemaObserved
    // ASSERTIONS canvasMeshConcretePaintProtobufSchemaObserved
    // ASSERTIONS canvasMeshProtobufMalformedInputsObserved

    func testEmptyLocationsLoseTheEmptyBezierDiscriminator() throws {
        XCTAssertEqual(try encode(MeshGradient.Locations.points([])), "")
        XCTAssertEqual(try encode(MeshGradient.Locations.bezierPoints([])), "")
        XCTAssertEqual(try decode("") as MeshGradient.Locations, .points([]))
        XCTAssertEqual(try decode("0a00") as MeshGradient.Locations, .points([.zero]))
        guard case let .bezierPoints(points) = try decode("1200") as MeshGradient.Locations else {
            return XCTFail("A present empty Bezier record must retain its case")
        }
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].bottomControlPoint, .zero)
    }

    func testMixedRecordsChooseOrderedBezierPoints() throws {
        let point = "0a050d0000803f"
        let firstBezier = "12051500000040"
        let secondBezier = "12055500004040"
        for bytes in [point + firstBezier + point + secondBezier,
                      firstBezier + secondBezier + point] {
            let locations: MeshGradient.Locations = try decode(bytes)
            guard case let .bezierPoints(points) = locations else { return XCTFail() }
            XCTAssertEqual(points.count, 2)
            XCTAssertEqual(points[0].position, SIMD2(0, 2))
            XCTAssertEqual(points[1].bottomControlPoint, SIMD2(0, 3))
            XCTAssertEqual(try encode(locations), firstBezier + secondBezier)
        }
        XCTAssertEqual(try decode(point + point) as MeshGradient.Locations, .points([SIMD2(1, 0), SIMD2(1, 0)]))
    }

    func testLocationFieldsKeepFloatBitsAndUseStoredComponentOrder() throws {
        XCTAssertEqual(MemoryLayout<MeshGradient.BezierPoint>.size, 10 * MemoryLayout<Float>.stride)
        let bits: [UInt32] = [0, 0x80000000, 0x3f800000, 0xbf800000, 0x7f800000, 0xff800000, 0x7fc12345]
        for record in [1, 2] {
            for field in 1...(record == 1 ? 2 : 10) {
                for raw in bits {
                    let scalar = String(format: "%02x", field << 3 | 5) + littleEndian(raw)
                    let input = String(format: "%02x05", record << 3 | 2) + scalar
                    let locations: MeshGradient.Locations = try decode(input)
                    let values: [Float]
                    switch locations {
                    case let .points(points): values = [points[0].x, points[0].y]
                    case let .bezierPoints(points):
                        let p = points[0]
                        values = [p.position.x, p.position.y, p.leadingControlPoint.x, p.leadingControlPoint.y,
                                  p.topControlPoint.x, p.topControlPoint.y, p.trailingControlPoint.x,
                                  p.trailingControlPoint.y, p.bottomControlPoint.x, p.bottomControlPoint.y]
                    }
                    XCTAssertEqual(values[field - 1].bitPattern, raw, input)
                    let expected = raw & 0x7fffffff == 0 ? String(format: "%02x00", record << 3 | 2) : input
                    XCTAssertEqual(try encode(locations), expected)
                }
            }
        }
        let points: MeshGradient.Locations = try decode("0a0f0d0000803f0a080000004000004040")
        XCTAssertEqual(points, .points([SIMD2(3, 0)]))
    }

    func testPaintHasDistinctAbsentAndPresentBackgroundDefaults() throws {
        let absent: MeshGradient._Paint = try decode("")
        XCTAssertEqual(absent.locations, .points([]))
        XCTAssertEqual(absent.colors, [])
        XCTAssertEqual(absent.background.opacity, 0)
        XCTAssertTrue(absent.background._headroom.isNaN)
        XCTAssertEqual(absent.width, 0)
        XCTAssertEqual(absent.height, 0)
        XCTAssertEqual(absent.flags.rawValue, 0)
        XCTAssertEqual(absent.allowedDynamicRange, .standard)
        XCTAssertEqual(try encode(absent), "0a00")

        let present: MeshGradient._Paint = try decode("1a00")
        XCTAssertEqual(present.background.opacity, 1)
        XCTAssertEqual(try encode(present), "0a001a00")
        let explicitClear: MeshGradient._Paint = try decode("1a052500000000")
        XCTAssertEqual(try encode(explicitClear), "0a00")
        let clearZeroHeadroom: MeshGradient._Paint = try decode("1a0a25000000002d00000000")
        XCTAssertEqual(clearZeroHeadroom.background._headroom, 0)
        XCTAssertEqual(try encode(clearZeroHeadroom), "0a001a052500000000")
        let restored: MeshGradient._Paint = try decode(encode(clearZeroHeadroom))
        XCTAssertTrue(restored.background._headroom.isNaN)
    }

    func testRepeatedMessagesReplaceLocationsAndBackgroundButAppendColors() throws {
        let bytes = "0a070a050d0000803f0a02120012050d0000803f12001a0a0d000000402d000040401a00"
        let paint: MeshGradient._Paint = try decode(bytes)
        guard case let .bezierPoints(points) = paint.locations else { return XCTFail() }
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(paint.colors.map(\.linearRed), [1, 0])
        XCTAssertEqual(paint.colors.map(\.opacity), [1, 1])
        XCTAssertEqual(paint.background.linearRed, 0)
        XCTAssertEqual(paint.background.opacity, 1)
        XCTAssertTrue(paint.background._headroom.isNaN)
        XCTAssertEqual(try encode(paint), "0a02120012050d0000803f12001a00")
        let replaced: MeshGradient._Paint = try decode(bytes + "0a00")
        XCTAssertEqual(replaced.locations, .points([]))
    }

    func testDimensionsIgnoreEachUnrepresentablePackedElement() throws {
        for field in [4, 5] {
            for raw: UInt in [0, 1, 3, UInt(Int.max), UInt(Int.max) + 1, .max] {
                var value = ProtobufEncoder()
                value.encodeVarint(raw)
                let scalar = hex(value.data)
                let direct = String(format: "%02x03%02x", field << 3, field << 3) + scalar
                let packed = String(format: "%02x%02x03", field << 3 | 2, value.data.count + 1) + scalar
                for bytes in [direct, packed] {
                    let paint: MeshGradient._Paint = try decode(bytes)
                    XCTAssertEqual(field == 4 ? paint.width : paint.height, Int(exactly: raw) ?? 3, bytes)
                }
            }
        }
        var paint: MeshGradient._Paint = try decode("2003280430133802")
        XCTAssertEqual(try encode(paint), "0a002003280430133802")
        paint.width = -1
        paint.height = .min
        XCTAssertEqual(try encode(paint), "0a0030133802")
    }

    func testFlagsTruncateButDynamicRangeUsesTheFullRawValue() throws {
        for raw: UInt in [0, 1, 2, 3, 0xffffffff, 0x100000001, .max] {
            var value = ProtobufEncoder()
            value.encodeVarint(raw)
            let scalar = hex(value.data)
            let paint: MeshGradient._Paint = try decode("30" + scalar + "38" + scalar)
            XCTAssertEqual(paint.flags.rawValue, UInt32(truncatingIfNeeded: raw))
            XCTAssertEqual(paint.allowedDynamicRange, raw == 1 ? .constrainedHigh : raw == 2 ? .high : .standard)
        }
        let packed: MeshGradient._Paint = try decode("320203103a020201")
        XCTAssertEqual(packed.flags.rawValue, 16)
        XCTAssertEqual(packed.allowedDynamicRange, .constrainedHigh)
    }

    func testEncodingKeepsSharedLocationAndColorBuffers() throws {
        let locations = [SIMD2<Float>(1, 2), SIMD2<Float>(3, 4)]
        let colors = [Color.Resolved(colorSpace: .sRGBLinear, red: 1, green: 0, blue: 0)]
        let paint = MeshGradient._Paint(locations: .points(locations), colors: colors,
                                       background: .init(.init(colorSpace: .sRGBLinear, red: 0, green: 0, blue: 0, opacity: 0)),
                                       width: 2, height: 1, allowedDynamicRange: .high, flags: .init(rawValue: 0x80000013))
        let locationAddress = locations.withUnsafeBufferPointer { $0.baseAddress }
        let colorAddress = colors.withUnsafeBufferPointer { $0.baseAddress }
        _ = try encode(paint)
        guard case let .points(after) = paint.locations else { return XCTFail() }
        XCTAssertEqual(after.withUnsafeBufferPointer { $0.baseAddress }, locationAddress)
        XCTAssertEqual(paint.colors.withUnsafeBufferPointer { $0.baseAddress }, colorAddress)
        XCTAssertEqual(paint.flags.rawValue, 0x80000013)
    }

    func testMalformedTagsWiresAndNestedLengthsThrow() throws {
        for bytes in ["00", "07", "80", "7b", "7c", "7e", "7f", "0a0500", "0a0100"] {
            XCTAssertThrowsError(try decode(bytes) as MeshGradient.Locations, bytes)
            XCTAssertThrowsError(try decode(bytes) as MeshGradient._Paint, bytes)
        }
        for bytes in ["0801", "110000000000000000", "0a020d00", "0a020a00", "12050a03000000"] {
            XCTAssertThrowsError(try decode(bytes) as MeshGradient.Locations, bytes)
        }
        for bytes in ["0801", "1001", "1801", "210000000000000000", "2200", "220180", "3200", "3a0501"] {
            XCTAssertThrowsError(try decode(bytes) as MeshGradient._Paint, bytes)
        }
        for unknown in ["7801", "790000000000000000", "7a020000", "7d00000000"] {
            XCTAssertEqual(try decode(unknown) as MeshGradient.Locations, .points([]))
            XCTAssertEqual((try decode(unknown + "2003") as MeshGradient._Paint).width, 3)
        }
    }

    private func decode<T: ProtobufDecodableMessage>(_ text: String) throws -> T {
        var decoder = ProtobufDecoder(data(text))
        return try T(from: &decoder)
    }
    private func encode<T: ProtobufEncodableMessage>(_ value: T) throws -> String {
        hex(try ProtobufEncoder.encoding(value))
    }
    private func data(_ text: String) -> Data {
        let bytes = Array(text.utf8)
        return Data(stride(from: 0, to: bytes.count, by: 2).map {
            UInt8(String(decoding: bytes[$0..<$0+2], as: UTF8.self), radix: 16)!
        })
    }
    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    private func littleEndian(_ value: UInt32) -> String {
        (0..<4).map { String(format: "%02x", (value >> ($0 * 8)) & 255) }.joined()
    }
}
