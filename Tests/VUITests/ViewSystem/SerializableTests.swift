import XCTest
@testable import VUI

final class SerializableTests: XCTestCase {
    func testTagDispatchRestoresConcreteBoxAndUsesPayloadSerialization() throws {
        let box = NumberBox(base: .init(number: 42))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(BoxRecord(box: box))
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"tag":{"number":{}},"value":{"number":42}}"#)
        XCTAssertEqual(box.tagReads, 2)
        let decoded = try JSONDecoder().decode(BoxRecord.self, from: data)
        XCTAssertEqual((decoded.box as? NumberBox)?.base.number, 42)
    }

    func testBoxDecodeReportsMissingTagAndValueAtContainingPath() throws {
        for (json, missingKey) in [
            (#"{"item":{"value":{"number":42}}}"#, "tag"),
            (#"{"item":{"tag":{"number":{}}}}"#, "value")
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode([String: BoxRecord].self, from: Data(json.utf8))) {
                guard case let DecodingError.keyNotFound(key, context) = $0 else {
                    return XCTFail("Unexpected error: \($0)")
                }
                XCTAssertEqual(key.stringValue, missingKey)
                XCTAssertEqual(context.codingPath.map(\.stringValue), ["item"])
            }
        }
        let unknown = Data(#"{"tag":{"unknown":{}},"value":{"number":42}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(BoxRecord.self, from: unknown))
    }

    func testBoxEncodeRejectsNonconformingValueWithOriginalPayloadAndPath() throws {
        let value = BoxPayload(value: "invalid")
        XCTAssertThrowsError(try JSONEncoder().encode(["item": value])) {
            guard case let EncodingError.invalidValue(value, context) = $0 else {
                return XCTFail("Unexpected error: \($0)")
            }
            XCTAssertEqual(value as? String, "invalid")
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["item"])
            XCTAssertEqual(context.debugDescription, "Encountered mismatched box value.")
            XCTAssertNil(context.underlyingError)
        }
    }

    func testStaticBoxEncoderUsesActualConformingValueWitness() throws {
        let data = try JSONEncoder().encode(BoxPayload(value: TextBox()))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"value":"actual-box"}"#)
    }

    func testBoxKeysPreserveStringAndIntegerRepresentations() {
        XCTAssertEqual(CodableBoxCodingKeys.tag.stringValue, "tag")
        XCTAssertEqual(CodableBoxCodingKeys.tag.intValue, 0)
        XCTAssertEqual(CodableBoxCodingKeys.value.stringValue, "value")
        XCTAssertEqual(CodableBoxCodingKeys.value.intValue, 1)
        XCTAssertEqual(CodableBoxCodingKeys(intValue: 0), .tag)
        XCTAssertEqual(CodableBoxCodingKeys(intValue: 1), .value)
        XCTAssertNil(CodableBoxCodingKeys(intValue: 2))
        XCTAssertNil(CodableBoxCodingKeys(stringValue: "unknown"))
    }

    func testProxyWrapperUsesValueSemanticsAndEmptyDecodeDoesNotConsumeAContainer() throws {
        var original = ProxyCodable(Number(number: 7))
        let copy = original.projectedValue
        original.wrappedValue.number = 9
        XCTAssertEqual(copy.wrappedValue.number, 7)
        XCTAssertEqual(original.wrappedValue.number, 9)
        _ = try JSONDecoder().decode(ProxyCodable<Empty>.self, from: Data("42".utf8))
    }
}

private struct Number: CodableSerializable {
    var number: Int
}

private struct Empty: EmptySerializable {}

private enum NumberTag: CodableBoxTag {
    case number
    var box: any CodableBox<AnyNumberBox>.Type { NumberBox.self }
}

private class AnyNumberBox: AnyCodableBox {
    typealias Box = AnyNumberBox
    var tag: NumberTag { fatalError("Abstract box") }
}

private final class NumberBox: AnyNumberBox, CodableBox {
    let base: Number
    var tagReads = 0
    init(base: Number) { self.base = base }
    override var tag: NumberTag {
        tagReads += 1
        return .number
    }
    func serialize(to encoder: any Encoder) throws { try base.serialize(to: encoder) }
    static func deserialize(from decoder: any Decoder) throws -> NumberBox {
        .init(base: try Number.deserialize(from: decoder))
    }
}

private final class TextBox: AnyNumberBox, CodableBox {
    override var tag: NumberTag { .number }
    func serialize(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("actual-box")
    }
    static func deserialize(from decoder: any Decoder) throws -> TextBox { TextBox() }
}

private struct BoxRecord: Codable {
    var box: AnyNumberBox
    init(box: AnyNumberBox) { self.box = box }
    init(from decoder: any Decoder) throws { box = try AnyNumberBox.decode(from: decoder) }
    func encode(to encoder: any Encoder) throws { try box.encode(to: encoder) }
}

private struct BoxPayload: Encodable {
    var value: Any
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodableBoxCodingKeys.self)
        try NumberBox.encode(value, to: &container)
    }
}
