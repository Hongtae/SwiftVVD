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

    func testRawRepresentableProxyUsesRawValueWithoutRequiringBaseCodable() throws {
        let proxy = RawChoice.high.codingProxy
        let data = try JSONEncoder().encode(proxy)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "7")
        XCTAssertEqual(try JSONDecoder().decode(RawRepresentableProxy<RawChoice>.self, from: data).base, .high)
        let serialized = try JSONEncoder().encode(ProxyCodable(RawChoice.low))
        XCTAssertEqual(String(decoding: serialized, as: UTF8.self), "2")
        XCTAssertEqual(try JSONDecoder().decode(ProxyCodable<RawChoice>.self, from: serialized).wrappedValue, .low)
    }

    func testRawPropertyWrapperEncodesScalarAndCopiesWrappedValue() throws {
        var value = RawRecord(choice: .low)
        let copy = value
        value.choice = .high
        XCTAssertEqual(copy.choice, .low)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"choice":7}"#)
        XCTAssertEqual(try JSONDecoder().decode(RawRecord.self, from: data).choice, .high)
        XCTAssertEqual(CodableRawRepresentable(RawChoice.low).wrappedValue, .low)
    }

    func testRawWrapperEqualityAndHashingUseValueConformance() {
        let first = CodableRawRepresentable(GroupedRaw(rawValue: .init(number: 2)))
        let equivalent = CodableRawRepresentable(GroupedRaw(rawValue: .init(number: 12)))
        let other = CodableRawRepresentable(GroupedRaw(rawValue: .init(number: 3)))
        XCTAssertEqual(first, equivalent)
        XCTAssertNotEqual(first, other)
        XCTAssertEqual(Set([first, equivalent, other]).count, 2)
        XCTAssertEqual(ProxyCodable(first.wrappedValue), ProxyCodable(equivalent.wrappedValue))
        XCTAssertEqual(Set([ProxyCodable(first.wrappedValue), ProxyCodable(equivalent.wrappedValue),
                            ProxyCodable(other.wrappedValue)]).count, 2)
    }

    func testInvalidRawValueThrowsSharedUnarchivingError() throws {
        var errors: [any Swift.Error] = []
        for decode in rawDecoders {
            do {
                try decode(Data(#"{"choice":127}"#.utf8))
                XCTFail("An unknown raw value must fail")
            } catch {
                errors.append(error)
                XCTAssertFalse(error is DecodingError)
                XCTAssertEqual(String(describing: error), "unarchivingError")
                XCTAssertEqual(Mirror(reflecting: error).displayStyle, .enum)
                XCTAssertTrue(Mirror(reflecting: error).children.isEmpty)
            }
        }
        XCTAssertEqual(errors.count, 3)
        XCTAssertTrue(errors.dropFirst().allSatisfy { type(of: $0) == type(of: errors[0]) })
    }

    func testRawDecoderPreservesTypeMismatchAndMissingKeyErrors() throws {
        for decode in rawDecoders {
            XCTAssertThrowsError(try decode(Data(#"{"choice":"bad"}"#.utf8))) {
                guard case let DecodingError.typeMismatch(type, context) = $0 else {
                    return XCTFail("Unexpected error: \($0)")
                }
                XCTAssertTrue(type == Int8.self)
                XCTAssertEqual(context.codingPath.map(\.stringValue), ["choice"])
            }
        }
        XCTAssertThrowsError(try JSONDecoder().decode(RawRecord.self, from: Data("{}".utf8))) {
            guard case let DecodingError.keyNotFound(key, _) = $0 else {
                return XCTFail("Unexpected error: \($0)")
            }
            XCTAssertEqual(key.stringValue, "choice")
        }
    }

    private var rawDecoders: [(Data) throws -> Void] {
        [
            { _ = try JSONDecoder().decode([String: RawRepresentableProxy<RawChoice>].self, from: $0) },
            { _ = try JSONDecoder().decode(RawRecord.self, from: $0) },
            { _ = try JSONDecoder().decode([String: ProxyCodable<RawChoice>].self, from: $0) }
        ]
    }
}

private enum RawChoice: Int8, CodableByProxy {
    case low = 2
    case high = 7
}

private struct RawRecord: Codable {
    @CodableRawRepresentable var choice: RawChoice
}

private struct GroupedRaw: RawRepresentable, Hashable, CodableByProxy {
    struct RawValue: Codable {
        var number: Int
    }
    var rawValue: RawValue
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.number % 10 == rhs.rawValue.number % 10
    }
    func hash(into hasher: inout Hasher) { hasher.combine(rawValue.number % 10) }
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
