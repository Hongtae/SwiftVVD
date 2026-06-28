//
//  File: StrongHash.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

protocol StronglyHashable {
    func hash(into hasher: inout StrongHasher)
}

protocol StronglyHashableByBitPattern: StronglyHashable {
}

extension StronglyHashableByBitPattern {
    func hash(into hasher: inout StrongHasher) {
        hasher.combineBitPattern(self)
    }
}

struct StrongHasher {
    private var context = SHA1()

    init() {
    }

    mutating func combine<Value: StronglyHashable>(_ value: Value) {
        value.hash(into: &self)
    }

    mutating func combineBytes(_ bytes: UnsafeRawPointer, count: Int) {
        precondition(count >= 0 && count <= Int(UInt32.max))
        guard count > 0 else { return }
        context.update(bytes: UnsafeRawBufferPointer(start: bytes, count: count))
    }

    mutating func combineBitPattern<Value>(_ value: Value) {
        var copy = value
        withUnsafeBytes(of: &copy) { bytes in
            if let baseAddress = bytes.baseAddress {
                combineBytes(baseAddress, count: bytes.count)
            }
        }
    }

    mutating func combineType(_ type: Any.Type) {
        combine(StrongHash(stableTypeDataFor: type))
    }

    mutating func finalize() -> StrongHash {
        let digest = context.finalize().hash
        return StrongHash(words: (
            digest.0.byteSwapped,
            digest.1.byteSwapped,
            digest.2.byteSwapped,
            digest.3.byteSwapped,
            digest.4.byteSwapped
        ))
    }
}

struct StrongHash: Equatable, Hashable, CustomStringConvertible, Codable {
    var words: (UInt32, UInt32, UInt32, UInt32, UInt32)

    init() {
        self.words = (0, 0, 0, 0, 0)
    }

    init(words: (UInt32, UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)) {
        self.words = words
    }

    init<Value: StronglyHashable>(of value: Value) {
        var hasher = StrongHasher()
        value.hash(into: &hasher)
        self = hasher.finalize()
    }

    init<Value: Encodable>(encodable value: Value) throws {
        let data = try JSONEncoder.makeStable().encode(value)
        self.init(of: data)
    }

    static func random() -> StrongHash {
        StrongHash(of: UUID())
    }

    fileprivate init(stableTypeDataFor type: Any.Type) {
        self = StableTypeSignature.hash(for: type) ?? StrongHash()
    }

    static func == (lhs: StrongHash, rhs: StrongHash) -> Bool {
        lhs.words.0 == rhs.words.0 &&
        lhs.words.1 == rhs.words.1 &&
        lhs.words.2 == rhs.words.2 &&
        lhs.words.3 == rhs.words.3 &&
        lhs.words.4 == rhs.words.4
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(words.0)
        hasher.combine(words.1)
        hasher.combine(words.2)
        hasher.combine(words.3)
        hasher.combine(words.4)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(words.0)
        try container.encode(words.1)
        try container.encode(words.2)
        try container.encode(words.3)
        try container.encode(words.4)
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let word0 = try container.decode(UInt32.self)
        let word1 = try container.decode(UInt32.self)
        let word2 = try container.decode(UInt32.self)
        let word3 = try container.decode(UInt32.self)
        let word4 = try container.decode(UInt32.self)
        self.init(words: (word0, word1, word2, word3, word4))
    }

    var description: String {
        [words.0, words.1, words.2, words.3, words.4]
            .map { String($0, radix: 16) }
            .joined(separator: ":")
    }

}

private enum StableTypeSignature {
    static func hash(for type: Any.Type) -> StrongHash? {
        let name: TypeName
        if let mangledName = _mangledTypeName(type) {
            name = TypeName(encoding: .mangled, value: mangledName)
        } else {
            name = TypeName(encoding: .reflected, value: String(reflecting: type))
        }

        let rawKind = _getStableTypeMetadataKind(type)
        guard let metadataKind = UInt32(exactly: rawKind) else {
            return nil
        }
        return StrongHash(of: Record(metadataKind: metadataKind, name: name))
    }

    private struct Record: StronglyHashable {
        static let formatVersion: UInt8 = 1

        let metadataKind: UInt32
        let name: TypeName

        func hash(into hasher: inout StrongHasher) {
            // Serialize fields explicitly so value-layout padding and pointer
            // size never become part of the signature.
            hasher.combine("AGTypeSignature")
            hasher.combineBitPattern(Self.formatVersion)
            hasher.combineBitPattern(metadataKind.littleEndian)
            hasher.combineBitPattern(name.encoding.rawValue)
            combineLengthPrefixed(name.value, into: &hasher)
        }
    }

    private struct TypeName {
        let encoding: NameEncoding
        let value: String
    }

    private enum NameEncoding: UInt8 {
        case mangled
        case reflected
    }

    private static func combineLengthPrefixed(_ value: String, into hasher: inout StrongHasher) {
        let utf8 = value.utf8
        guard let count = UInt32(exactly: utf8.count) else {
            preconditionFailure("Type name exceeds the stable signature format limit")
        }
        hasher.combineBitPattern(count.littleEndian)
        hasher.combine(value)
    }
}

@_silgen_name("swift_getMetadataKind")
private func _getStableTypeMetadataKind(_ type: Any.Type) -> UInt

extension StrongHash: StronglyHashableByBitPattern {
}

extension StrongHash: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) {
        encoder.encodeVarint(0x0a)
        encoder.startLengthDelimited()
        encoder.encodeFixed32(words.0)
        encoder.encodeFixed32(words.1)
        encoder.encodeFixed32(words.2)
        encoder.encodeFixed32(words.3)
        encoder.encodeFixed32(words.4)
        encoder.endLengthDelimited()
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var word0: UInt32 = 0
        var word1: UInt32 = 0
        var word2: UInt32 = 0
        var word3: UInt32 = 0
        var word4: UInt32 = 0
        var decodedWordCount = 0

        func assign(_ word: UInt32) {
            switch decodedWordCount {
            case 0:
                word0 = word
            case 1:
                word1 = word
            case 2:
                word2 = word
            case 3:
                word3 = word
            case 4:
                word4 = word
            default:
                break
            }
            decodedWordCount += 1
        }

        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            guard tag >= 0x08 else {
                throw ProtobufDecoder.DecodingError.failed
            }

            let field = tag & ~UInt(0x07)
            let wireType = tag & 0x07

            if field == 0x08 {
                switch wireType {
                case 2:
                    let length = try decoder.decodeVarint()
                    let endIndex = try decoder.endIndexForLengthDelimitedField(byteCount: length)
                    while decoder.position < endIndex {
                        assign(try decoder.decodeFixed32(limitedBy: endIndex))
                    }
                case 5:
                    assign(try decoder.decodeFixed32())
                default:
                    throw ProtobufDecoder.DecodingError.failed
                }
            } else {
                try decoder.skipField(wireType: wireType)
            }
        }

        self.init(words: (word0, word1, word2, word3, word4))
    }
}

extension String: StronglyHashable {
    func hash(into hasher: inout StrongHasher) {
        guard !isEmpty else { return }
        utf8.withContiguousStorageIfAvailable { bytes in
            if let baseAddress = bytes.baseAddress {
                hasher.combineBytes(baseAddress, count: bytes.count)
            }
        } ?? Array(utf8).withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                hasher.combineBytes(baseAddress, count: bytes.count)
            }
        }
    }
}

extension Data: StronglyHashable {
    func hash(into hasher: inout StrongHasher) {
        guard !isEmpty else { return }
        withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                hasher.combineBytes(baseAddress, count: bytes.count)
            }
        }
    }
}

extension Bool: StronglyHashable {
    func hash(into hasher: inout StrongHasher) {
        var value = self
        withUnsafeBytes(of: &value) { bytes in
            if let baseAddress = bytes.baseAddress {
                hasher.combineBytes(baseAddress, count: 1)
            }
        }
    }
}

extension Optional: StronglyHashable where Wrapped: StronglyHashable {
    func hash(into hasher: inout StrongHasher) {
        switch self {
        case let .some(value):
            value.hash(into: &hasher)
        case .none:
            break
        }
    }
}

extension RawRepresentable where RawValue: StronglyHashable {
    func hash(into hasher: inout StrongHasher) {
        rawValue.hash(into: &hasher)
    }
}

extension Int: StronglyHashableByBitPattern {}
extension UInt: StronglyHashableByBitPattern {}
extension Int8: StronglyHashableByBitPattern {}
extension UInt8: StronglyHashableByBitPattern {}
extension Int16: StronglyHashableByBitPattern {}
extension UInt16: StronglyHashableByBitPattern {}
extension Int32: StronglyHashableByBitPattern {}
extension UInt32: StronglyHashableByBitPattern {}
extension Int64: StronglyHashableByBitPattern {}
extension UInt64: StronglyHashableByBitPattern {}
extension Float: StronglyHashableByBitPattern {}
extension Double: StronglyHashableByBitPattern {}
extension UUID: StronglyHashableByBitPattern {}

private extension JSONEncoder {
    static func makeStable() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
