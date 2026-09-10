import XCTest
@testable import VUI

final class OptionalSerializationTests: XCTestCase {
    func testOptionalUsesWrappedCodingProxyInsteadOfSerializableOverride() throws {
        let value = ProxyValue(number: 7)
        XCTAssertThrowsError(try encoded(ProxyCodable(value)))
        XCTAssertThrowsError(try JSONDecoder().decode(ProxyCodable<ProxyValue>.self, from: Data("8".utf8)))

        let optional = Optional.some(value)
        XCTAssertEqual(try encoded(ProxyCodable(optional)), #"{"value":8}"#)
        let decoded = try JSONDecoder().decode(ProxyCodable<ProxyValue?>.self,
            from: Data(#"{"value":8}"#.utf8)).wrappedValue
        XCTAssertEqual(decoded, value)
    }

    func testNilAndNestedOptionalPreserveEachPresenceLevel() throws {
        let samples: [(ProxyValue??, String)] = [
            (nil, "{}"),
            (.some(nil), #"{"value":{}}"#),
            (.some(.some(.init(number: 7))), #"{"value":{"value":8}}"#)
        ]
        for (value, json) in samples {
            XCTAssertEqual(try encoded(ProxyCodable(value)), json)
            let decoded = try JSONDecoder().decode(ProxyCodable<ProxyValue??>.self,
                from: Data(json.utf8)).wrappedValue
            XCTAssertEqual(decoded, value)
        }
        XCTAssertEqual(try encoded(ProxyCodable(ProxyValue?.none)), "{}")
    }

    func testMissingOrNullValueDecodesAsNoneAndUnknownFieldsAreIgnored() throws {
        for json in ["{}", #"{"ignored":1}"#, #"{"value":null}"#] {
            let decoded = try JSONDecoder().decode(ProxyCodable<ProxyValue?>.self,
                from: Data(json.utf8)).wrappedValue
            XCTAssertNil(decoded)
            XCTAssertEqual(try encoded(ProxyCodable(decoded)), "{}")
        }
        let decoded = try JSONDecoder().decode(ProxyCodable<ProxyValue?>.self,
            from: Data(#"{"ignored":1,"value":8}"#.utf8)).wrappedValue
        XCTAssertEqual(decoded, .init(number: 7))
    }

    func testDecoderPreservesContainerAndPayloadErrors() throws {
        let samples = [
            ("null", "valueNotFound", ["item"]),
            ("[]", "typeMismatch", ["item"]),
            ("8", "typeMismatch", ["item"]),
            ("true", "typeMismatch", ["item"]),
            (#"{"value":{}}"#, "typeMismatch", ["item", "value"]),
            (#"{"value":"bad"}"#, "typeMismatch", ["item", "value"])
        ]
        for (payload, expectedKind, expectedPath) in samples {
            let json = "{\"item\":\(payload)}"
            XCTAssertThrowsError(try JSONDecoder().decode([String: ProxyCodable<ProxyValue?>].self,
                from: Data(json.utf8))) { error in
                let kind: String
                let context: DecodingError.Context
                switch error {
                case DecodingError.typeMismatch(_, let value): (kind, context) = ("typeMismatch", value)
                case DecodingError.valueNotFound(_, let value): (kind, context) = ("valueNotFound", value)
                default: return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(kind, expectedKind)
                XCTAssertEqual(context.codingPath.map(\.stringValue), expectedPath)
            }
        }
    }

    func testProxyRetainsMutableBaseAndCopiesValueStorage() throws {
        var proxy = CodableOptional(ProxyValue(number: 7))
        let copy = proxy
        proxy.base?.number = 12
        XCTAssertEqual(try encoded(copy), #"{"value":8}"#)
        XCTAssertEqual(try encoded(proxy), #"{"value":13}"#)
        XCTAssertEqual(ProxyValue?.unwrap(codingProxy: copy), .init(number: 7))
        proxy.base = nil
        XCTAssertEqual(try encoded(proxy), "{}")
        XCTAssertEqual(Mirror(reflecting: copy).children.map(\.label), ["base"])
    }

    func testResolvedColorUsesItsPrivateProxyInsideOptional() throws {
        let color = Color.Resolved(colorSpace: .sRGBLinear, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.125)
        let json = try encoded(ProxyCodable(Optional.some(color)))
        let outer = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let payload = try JSONSerialization.data(withJSONObject: try XCTUnwrap(outer["value"]), options: .sortedKeys)
        XCTAssertEqual(String(decoding: payload, as: UTF8.self), try encoded(color.codingProxy))
        let decoded = try JSONDecoder().decode(ProxyCodable<Color.Resolved?>.self,
            from: Data(json.utf8)).wrappedValue
        XCTAssertEqual(decoded, color)
    }

    func testOptionalConformanceRequiresCodableByProxy() {
        func isSerializable(_ value: Any) -> Bool { value is any Serializable }
        func isCodableByProxy(_ value: Any) -> Bool { value is any CodableByProxy }
        XCTAssertTrue(isSerializable(ProxyValue?.none as Any))
        XCTAssertTrue(isCodableByProxy(ProxyValue??.some(nil) as Any))
        XCTAssertFalse(isSerializable(SerializableOnly?.none as Any))
        XCTAssertFalse(isCodableByProxy(SerializableOnly?.none as Any))
        XCTAssertFalse(isSerializable(Int?.none as Any))
    }

    func testOptionalPreservesEncodingFailureAtWrappedProxyField() {
        let color = Color.Resolved(colorSpace: .sRGBLinear, red: 0, green: .infinity, blue: 0)
        XCTAssertThrowsError(try JSONEncoder().encode(["item": ProxyCodable(Optional.some(color))])) { error in
            guard case let EncodingError.invalidValue(_, context) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["item", "value", "green"])
        }
    }

    private func encoded(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

private struct ProxyValue: CodableByProxy, Equatable {
    var number: Int
    var codingProxy: Int { number + 1 }
    static func unwrap(codingProxy: Int) -> Self { .init(number: codingProxy - 1) }
    func serialize(to encoder: any Encoder) throws { throw DirectCodingError.unexpected }
    static func deserialize(from decoder: any Decoder) throws -> Self { throw DirectCodingError.unexpected }
}

private enum DirectCodingError: Swift.Error {
    case unexpected
}

private struct SerializableOnly: CodableSerializable {
    var number: Int
}
