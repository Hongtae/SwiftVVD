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
    struct Options: OptionSet {
        let rawValue: UInt32

        static let singlePrecisionCGFloat = Options(rawValue: 1 << 0)
    }

    enum EncodingError: Error, Hashable {
        case failed
    }

    private var buffer: [UInt8] = []
    private var lengthDelimitedStarts: [Int] = []
    var options: Options
    let archiveVersion: UInt8

    init(archiveVersion: UInt8 = 4, options: Options = []) {
        self.archiveVersion = archiveVersion
        self.options = options
    }

    static func encoding<Message: ProtobufEncodableMessage>(
        _ message: Message,
        options: Options = []
    ) throws -> Data {
        var encoder = ProtobufEncoder(options: options)
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

    mutating func encodeSignedVarint(_ value: Int) {
        let bits = UInt(bitPattern: value)
        let sign = UInt(bitPattern: value >> (Int.bitWidth - 1))
        encodeVarint((bits << 1) ^ sign)
    }

    mutating func encodeFixed32(_ value: UInt32) {
        buffer.append(UInt8(value & 0xff))
        buffer.append(UInt8((value >> 8) & 0xff))
        buffer.append(UInt8((value >> 16) & 0xff))
        buffer.append(UInt8((value >> 24) & 0xff))
    }

    mutating func encodeFixed64(_ value: UInt64) {
        for shift in stride(from: 0, through: 56, by: 8) {
            buffer.append(UInt8((value >> UInt64(shift)) & 0xff))
        }
    }

    mutating func encodeFloatFieldAlways(_ fieldNumber: UInt, _ value: Float) {
        encodeVarint((fieldNumber << 3) | 5)
        encodeFixed32(value.bitPattern)
    }

    mutating func encodeDoubleFieldAlways(_ fieldNumber: UInt, _ value: Double) {
        encodeVarint((fieldNumber << 3) | 1)
        encodeFixed64(value.bitPattern)
    }

    mutating func encodeCGFloatFieldAlways(_ fieldNumber: UInt, _ value: CGFloat) {
        // Small coordinates intentionally trade precision for a shorter field.
        if options.contains(.singlePrecisionCGFloat) || abs(value) < 65_536 {
            encodeFloatFieldAlways(fieldNumber, Float(value))
        } else {
            encodeDoubleFieldAlways(fieldNumber, Double(value))
        }
    }

    mutating func encodeMessageField<Message: ProtobufEncodableMessage>(
        _ fieldNumber: UInt,
        _ message: Message
    ) throws {
        encodeVarint((fieldNumber << 3) | 2)
        try encodeMessage(message)
    }

    mutating func encodeDataField(_ fieldNumber: UInt, _ data: Data) {
        encodeVarint((fieldNumber << 3) | 2)
        encodeVarint(UInt(data.count))
        buffer.append(contentsOf: data)
    }

    mutating func encodeStringField(_ fieldNumber: UInt, _ value: String) {
        encodeDataField(fieldNumber, Data(value.utf8))
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

    mutating func encodeMessage<Message: ProtobufEncodableMessage>(_ message: Message) throws {
        startLengthDelimited()
        try message.encode(to: &self)
        endLengthDelimited()
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
    private var messageEnds: [Int] = []

    init(_ data: Data) {
        self.buffer = Array(data)
    }

    var position: Int {
        index
    }

    var isAtEnd: Bool {
        index >= currentEnd
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

    mutating func decodeSignedVarint() throws -> Int {
        let value = try decodeVarint()
        let signMask = UInt(bitPattern: -Int(value & 1))
        return Int(bitPattern: (value >> 1) ^ signMask)
    }

    mutating func decodeUIntField(wireType: UInt) throws -> UInt {
        switch wireType {
        case 0:
            return try decodeVarint()
        case 2:
            return try decodeLengthDelimited { decoder in
                var value: UInt?
                while !decoder.isAtEnd {
                    value = try decoder.decodeVarint()
                }
                guard let value else { throw DecodingError.failed }
                return value
            }
        default:
            throw DecodingError.failed
        }
    }

    mutating func decodeFixed32() throws -> UInt32 {
        try decodeFixed32(limitedBy: currentEnd)
    }

    mutating func decodeFixed32(limitedBy endIndex: Int) throws -> UInt32 {
        guard endIndex <= currentEnd, index <= endIndex - 4 else {
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

    mutating func decodeFixed64() throws -> UInt64 {
        try decodeFixed64(limitedBy: currentEnd)
    }

    mutating func decodeFixed64(limitedBy endIndex: Int) throws -> UInt64 {
        guard endIndex <= currentEnd, index <= endIndex - 8 else {
            throw DecodingError.failed
        }

        var value: UInt64 = 0
        for offset in 0..<8 {
            value |= UInt64(buffer[index + offset]) << UInt64(offset * 8)
        }
        index += 8
        return value
    }

    mutating func decodeFloatField(wireType: UInt) throws -> Float {
        switch wireType {
        case 5:
            return Float(bitPattern: try decodeFixed32())
        case 2:
            return try decodeLengthDelimited { decoder in
                var value: Float?
                while !decoder.isAtEnd {
                    value = Float(bitPattern: try decoder.decodeFixed32())
                }
                guard let value else { throw DecodingError.failed }
                return value
            }
        default:
            throw DecodingError.failed
        }
    }

    mutating func decodeDoubleField(wireType: UInt) throws -> Double {
        switch wireType {
        case 1:
            return Double(bitPattern: try decodeFixed64())
        case 2:
            return try decodeLengthDelimited { decoder in
                var value: Double?
                while !decoder.isAtEnd {
                    value = Double(bitPattern: try decoder.decodeFixed64())
                }
                guard let value else { throw DecodingError.failed }
                return value
            }
        default:
            throw DecodingError.failed
        }
    }

    mutating func decodeCGFloatField(wireType: UInt) throws -> CGFloat {
        switch wireType {
        case 1:
            return CGFloat(Double(bitPattern: try decodeFixed64()))
        case 5:
            return CGFloat(Float(bitPattern: try decodeFixed32()))
        case 2:
            return try decodeLengthDelimited { decoder in
                var value: CGFloat?
                while !decoder.isAtEnd {
                    value = CGFloat(Double(bitPattern: try decoder.decodeFixed64()))
                }
                guard let value else { throw DecodingError.failed }
                return value
            }
        default:
            throw DecodingError.failed
        }
    }

    func endIndexForLengthDelimitedField(byteCount: UInt) throws -> Int {
        guard byteCount <= UInt(Int.max) else {
            throw DecodingError.failed
        }

        let count = Int(byteCount)
        guard count <= currentEnd - index else {
            throw DecodingError.failed
        }
        return index + count
    }

    mutating func decodeLengthDelimited<Result>(
        _ body: (inout ProtobufDecoder) throws -> Result
    ) throws -> Result {
        let length = try decodeVarint()
        let endIndex = try endIndexForLengthDelimitedField(byteCount: length)
        messageEnds.append(endIndex)
        defer { messageEnds.removeLast() }

        let result = try body(&self)
        guard index == endIndex else {
            throw DecodingError.failed
        }
        return result
    }

    mutating func decodeMessage<Message: ProtobufDecodableMessage>(
        _ type: Message.Type = Message.self
    ) throws -> Message {
        try decodeLengthDelimited { decoder in
            try Message(from: &decoder)
        }
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
        guard index < currentEnd else {
            throw DecodingError.failed
        }

        defer { index += 1 }
        return buffer[index]
    }

    private mutating func skipBytes(_ count: Int) throws {
        guard count >= 0, count <= currentEnd - index else {
            throw DecodingError.failed
        }
        index += count
    }

    private var currentEnd: Int {
        messageEnds.last ?? buffer.count
    }
}

private func encodeProtobufCGFloatPair(
    _ first: CGFloat,
    _ second: CGFloat,
    to encoder: inout ProtobufEncoder
) {
    if first != 0 {
        encoder.encodeCGFloatFieldAlways(1, first)
    }
    if second != 0 {
        encoder.encodeCGFloatFieldAlways(2, second)
    }
}

private func decodeProtobufCGFloatPair(
    from decoder: inout ProtobufDecoder
) throws -> (CGFloat, CGFloat) {
    var first: CGFloat = 0
    var second: CGFloat = 0

    while !decoder.isAtEnd {
        let tag = try decoder.decodeVarint()
        guard tag >= 8 else { throw ProtobufDecoder.DecodingError.failed }
        let fieldNumber = tag >> 3
        let wireType = tag & 0x7

        switch fieldNumber {
        case 1:
            first = try decoder.decodeCGFloatField(wireType: wireType)
        case 2:
            second = try decoder.decodeCGFloatField(wireType: wireType)
        default:
            try decoder.skipField(wireType: wireType)
        }
    }
    return (first, second)
}

extension CGPoint: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        encodeProtobufCGFloatPair(x, y, to: &encoder)
    }

    init(from decoder: inout ProtobufDecoder) throws {
        let (x, y) = try decodeProtobufCGFloatPair(from: &decoder)
        self.init(x: x, y: y)
    }
}

extension CGSize: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        encodeProtobufCGFloatPair(width, height, to: &encoder)
    }

    init(from decoder: inout ProtobufDecoder) throws {
        let (width, height) = try decodeProtobufCGFloatPair(from: &decoder)
        self.init(width: width, height: height)
    }
}

extension CGRect: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        if origin.x != 0 {
            encoder.encodeCGFloatFieldAlways(1, origin.x)
        }
        if origin.y != 0 {
            encoder.encodeCGFloatFieldAlways(2, origin.y)
        }
        if size.width != 0 {
            encoder.encodeCGFloatFieldAlways(3, size.width)
        }
        if size.height != 0 {
            encoder.encodeCGFloatFieldAlways(4, size.height)
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            switch fieldNumber {
            case 1:
                x = try decoder.decodeCGFloatField(wireType: wireType)
            case 2:
                y = try decoder.decodeCGFloatField(wireType: wireType)
            case 3:
                width = try decoder.decodeCGFloatField(wireType: wireType)
            case 4:
                height = try decoder.decodeCGFloatField(wireType: wireType)
            default:
                try decoder.skipField(wireType: wireType)
            }
        }
        self.init(x: x, y: y, width: width, height: height)
    }
}

extension UnitPoint: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        encodeProtobufCGFloatPair(x, y, to: &encoder)
    }

    init(from decoder: inout ProtobufDecoder) throws {
        let (x, y) = try decodeProtobufCGFloatPair(from: &decoder)
        self.init(x: x, y: y)
    }
}
