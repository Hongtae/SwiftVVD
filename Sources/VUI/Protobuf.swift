//
//  File: Protobuf.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol ProtobufEncodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws
}

protocol ProtobufDecodableMessage {
    init(from decoder: inout ProtobufDecoder) throws
}

struct ProtobufEncoder {
    enum EncodingError: Error, Hashable {
        case failed
    }

    private var buffer: [UInt8] = []
    private var lengthDelimitedStarts: [Int] = []

    init() {
    }

    static func encoding<Message: ProtobufEncodableMessage>(_ message: Message) throws -> Data {
        var encoder = ProtobufEncoder()
        try message.encode(to: &encoder)
        return encoder.data
    }

    var data: Data {
        Data(buffer)
    }

    mutating func encodeVarint(_ value: UInt) {
        var value = value
        while value >= 0x80 {
            buffer.append(UInt8(value & 0x7f) | 0x80)
            value >>= 7
        }
        buffer.append(UInt8(value))
    }

    mutating func encodeFixed32(_ value: UInt32) {
        buffer.append(UInt8(value & 0xff))
        buffer.append(UInt8((value >> 8) & 0xff))
        buffer.append(UInt8((value >> 16) & 0xff))
        buffer.append(UInt8((value >> 24) & 0xff))
    }

    mutating func startLengthDelimited() {
        lengthDelimitedStarts.append(buffer.count)
        buffer.append(0)
    }

    mutating func endLengthDelimited() {
        guard let start = lengthDelimitedStarts.popLast() else {
            preconditionFailure("Unbalanced length-delimited field")
        }

        let length = buffer.count - start - 1
        buffer.replaceSubrange(start..<(start + 1), with: Self.varintBytes(UInt(length)))
    }

    private static func varintBytes(_ value: UInt) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        while value >= 0x80 {
            bytes.append(UInt8(value & 0x7f) | 0x80)
            value >>= 7
        }
        bytes.append(UInt8(value))
        return bytes
    }
}

struct ProtobufDecoder {
    enum DecodingError: Error, Hashable {
        case failed
    }

    private var buffer: [UInt8]
    private var index: Int = 0

    init(_ data: Data) {
        self.buffer = Array(data)
    }

    var position: Int {
        index
    }

    var isAtEnd: Bool {
        index >= buffer.count
    }

    mutating func decodeVarint() throws -> UInt {
        var result: UInt = 0
        var shift = 0

        for _ in 0..<10 {
            let byte = try readByte()
            let payload = UInt(byte & 0x7f)
            if shift >= UInt.bitWidth || (shift == UInt.bitWidth - 1 && payload > 1) {
                throw DecodingError.failed
            }
            result |= payload << UInt(shift)

            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }

        throw DecodingError.failed
    }

    mutating func decodeFixed32() throws -> UInt32 {
        try decodeFixed32(limitedBy: buffer.count)
    }

    mutating func decodeFixed32(limitedBy endIndex: Int) throws -> UInt32 {
        guard endIndex <= buffer.count, index <= endIndex - 4 else {
            throw DecodingError.failed
        }

        let value =
            UInt32(buffer[index]) |
            (UInt32(buffer[index + 1]) << 8) |
            (UInt32(buffer[index + 2]) << 16) |
            (UInt32(buffer[index + 3]) << 24)
        index += 4
        return value
    }

    func endIndexForLengthDelimitedField(byteCount: UInt) throws -> Int {
        guard byteCount <= UInt(Int.max) else {
            throw DecodingError.failed
        }

        let count = Int(byteCount)
        guard count <= buffer.count - index else {
            throw DecodingError.failed
        }
        return index + count
    }

    mutating func skipField(wireType: UInt) throws {
        switch wireType {
        case 0:
            _ = try decodeVarint()
        case 1:
            try skipBytes(8)
        case 2:
            let length = try decodeVarint()
            guard length <= UInt(Int.max) else {
                throw DecodingError.failed
            }
            try skipBytes(Int(length))
        case 5:
            try skipBytes(4)
        default:
            throw DecodingError.failed
        }
    }

    private mutating func readByte() throws -> UInt8 {
        guard index < buffer.count else {
            throw DecodingError.failed
        }

        defer { index += 1 }
        return buffer[index]
    }

    private mutating func skipBytes(_ count: Int) throws {
        guard count >= 0, count <= buffer.count - index else {
            throw DecodingError.failed
        }
        index += count
    }
}
