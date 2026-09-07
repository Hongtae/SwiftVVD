import XCTest
@testable import VUI

final class ColorSerializationTests: XCTestCase {
    private var color: Color.Resolved {
        .init(colorSpace: .sRGBLinear, red: -0.25, green: 0.5, blue: 2, opacity: 0.625)
    }

    func testPrivateSerializationPreservesLinearComponentsExactly() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(ProxyCodable(color))
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"blue":2,"green":0.5,"opacity":0.625,"red":-0.25}"#)
        let decoded = try JSONDecoder().decode(ProxyCodable<Color.Resolved>.self, from: data)
        XCTAssertEqual(decoded.wrappedValue, color)
    }

    func testPublicCodingUsesSRGBArrayAndAllowsConversionRounding() throws {
        let data = try JSONEncoder().encode(color)
        let components = try JSONDecoder().decode([Float].self, from: data)
        XCTAssertEqual(components.count, 4)
        for (actual, expected) in zip(components, [-0.5370987, 0.7353569, 1.353256, 0.625] as [Float]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000001)
        }
        let decoded = try JSONDecoder().decode(Color.Resolved.self, from: data)
        XCTAssertEqual(decoded.linearRed, color.linearRed, accuracy: 0.000001)
        XCTAssertEqual(decoded.linearGreen, color.linearGreen, accuracy: 0.000001)
        XCTAssertEqual(decoded.linearBlue, color.linearBlue, accuracy: 0.000001)
        XCTAssertEqual(decoded.opacity, color.opacity)
    }

    func testPublicCodingPreservesSignedUnitComponentsExactly() throws {
        let color = Color.Resolved(colorSpace: .sRGBLinear, red: -1, green: 0, blue: 1)
        let data = try JSONEncoder().encode(color)
        XCTAssertEqual(try JSONDecoder().decode([Float].self, from: data), [-1, 0, 1, 1])
        XCTAssertEqual(try JSONDecoder().decode(Color.Resolved.self, from: data), color)
    }

    func testPublicDecodingRequiresFourComponentsAndLeavesTrailingValues() throws {
        for (json, index) in [("[]", 0), ("[0.25,0.5,0.75]", 3)] {
            XCTAssertThrowsError(try JSONDecoder().decode(Color.Resolved.self, from: Data(json.utf8))) {
                guard case let DecodingError.valueNotFound(_, context) = $0 else {
                    return XCTFail("Unexpected error: \($0)")
                }
                XCTAssertEqual(context.codingPath.last?.intValue, index)
            }
        }
        let decoded = try JSONDecoder().decode(Color.Resolved.self,
            from: Data("[0.25,0.5,0.75,0.625,123]".utf8))
        XCTAssertEqual(decoded.linearRed, 0.05087609, accuracy: 0.000001)
        XCTAssertEqual(decoded.linearGreen, 0.21404114, accuracy: 0.000001)
        XCTAssertEqual(decoded.linearBlue, 0.5225216, accuracy: 0.000001)
        XCTAssertEqual(decoded.opacity, 0.625)
        XCTAssertThrowsError(try JSONDecoder().decode(Color.Resolved.self, from: Data("{}".utf8)))
    }

    func testPrivateDecodeErrorsKeepNestedCodingPath() throws {
        let missing = Data(#"{"color":{"red":0,"green":0,"blue":0}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([String: ProxyCodable<Color.Resolved>].self, from: missing)) {
            guard case let DecodingError.keyNotFound(key, context) = $0 else {
                return XCTFail("Unexpected error: \($0)")
            }
            XCTAssertEqual(key.stringValue, "opacity")
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["color"])
        }
        let wrong = Data(#"{"color":{"red":"red","green":0,"blue":0,"opacity":1}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([String: ProxyCodable<Color.Resolved>].self, from: wrong)) {
            guard case let DecodingError.typeMismatch(_, context) = $0 else {
                return XCTFail("Unexpected error: \($0)")
            }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["color", "red"])
        }
    }

    func testPrivateEncodingReportsNonfiniteComponentAtItsField() throws {
        var color = color
        color.linearGreen = .infinity
        XCTAssertThrowsError(try JSONEncoder().encode(["color": ProxyCodable(color)])) {
            guard case let EncodingError.invalidValue(_, context) = $0 else {
                return XCTFail("Unexpected error: \($0)")
            }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["color", "green"])
        }
    }
}
