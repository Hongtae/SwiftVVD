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

struct ArchivedViewCore {
    static let archiveOptionsKey = CodingUserInfoKey(rawValue: "VUI.ArchivedViewInput")!
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
    var userInfo: [CodingUserInfoKey: Any] = [:]
    var options: Options

    init(options: Options = []) {
        self.options = options
    }

    var archiveOptions: ArchivedViewInput.Value {
        userInfo[ArchivedViewCore.archiveOptionsKey] as? ArchivedViewInput.Value
            ?? ArchivedViewInput.Value()
    }

    static func encoding(
        options: Options = [],
        _ body: (inout ProtobufEncoder) throws -> Void
    ) throws -> Data {
        var encoder = ProtobufEncoder(options: options)
        try body(&encoder)
        return encoder.data
    }

    static func encoding<Message: ProtobufEncodableMessage>(
        _ message: Message,
        options: Options = []
    ) throws -> Data {
        try encoding(options: options) { encoder in
            try message.encode(to: &encoder)
        }
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

enum ProtobufFormat {
    struct WireType: Equatable {
        let rawValue: UInt

        static let varint = WireType(rawValue: 0)
        static let fixed64 = WireType(rawValue: 1)
        static let lengthDelimited = WireType(rawValue: 2)
        static let fixed32 = WireType(rawValue: 5)
    }

    struct Field: Equatable {
        var rawValue: UInt

        init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        init(_ tag: UInt, wireType: WireType) {
            self.rawValue = (tag << 3) | wireType.rawValue
        }

        var tag: UInt { rawValue >> 3 }
        var wireType: WireType { WireType(rawValue: rawValue & 7) }
        var _isEmpty: Bool { rawValue == 0 }
    }
}

struct ProtobufDecoder {
    enum DecodingError: Error, Hashable {
        case failed
    }

    // The retained immutable owner keeps every cursor and borrowed buffer alive.
    var data: NSData
    var ptr: UnsafeRawPointer
    var end: UnsafeRawPointer
    var packedField: ProtobufFormat.Field
    var packedEnd: UnsafeRawPointer
    var stack: [UnsafeRawPointer] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    init(_ data: Data) {
        let owner = data as NSData
        self.data = owner
        self.ptr = owner.bytes
        self.end = owner.bytes + owner.length
        self.packedField = .init(rawValue: 0)
        self.packedEnd = owner.bytes
    }

    mutating func nextField() throws -> ProtobufFormat.Field? {
        // Enclosing EOF takes precedence even if a scalar crossed its packed end.
        if ptr >= end {
            packedField.rawValue = 0
            return nil
        }
        if !packedField._isEmpty {
            if ptr < packedEnd { return packedField }
            if ptr > packedEnd { throw DecodingError.failed }
            packedField.rawValue = 0
        }
        let tag = try decodeVarint()
        guard tag >= 8 else { throw DecodingError.failed }
        return .init(rawValue: tag)
    }

    mutating func decodeVarint() throws -> UInt {
        var value: UInt = 0
        var shift = 0
        while ptr < end {
            let byte = ptr.load(as: UInt8.self)
            ptr += 1
            // Continue consuming overlong encodings after the result is full.
            value |= UInt(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        throw DecodingError.failed
    }

    mutating func uintField(_ field: ProtobufFormat.Field) throws -> UInt {
        try prepareScalar(field, wireType: .varint)
        return try decodeVarint()
    }

    mutating func uint64Field(_ field: ProtobufFormat.Field) throws -> UInt64 {
        UInt64(try uintField(field))
    }

    mutating func uint32Field(_ field: ProtobufFormat.Field) throws -> UInt32 {
        UInt32(truncatingIfNeeded: try uintField(field))
    }

    mutating func uint16Field(_ field: ProtobufFormat.Field) throws -> UInt16 {
        UInt16(truncatingIfNeeded: try uintField(field))
    }

    mutating func uint8Field(_ field: ProtobufFormat.Field) throws -> UInt8 {
        UInt8(truncatingIfNeeded: try uintField(field))
    }

    mutating func intField(_ field: ProtobufFormat.Field) throws -> Int {
        let value = Int(bitPattern: try uintField(field))
        return (value >> 1) ^ -(value & 1)
    }

    mutating func boolField(_ field: ProtobufFormat.Field) throws -> Bool {
        try uintField(field) != 0
    }

    mutating func fixed32Field(_ field: ProtobufFormat.Field) throws -> UInt32 {
        try prepareScalar(field, wireType: .fixed32)
        return try readFixed(UInt32.self)
    }

    mutating func fixed64Field(_ field: ProtobufFormat.Field) throws -> UInt64 {
        try prepareScalar(field, wireType: .fixed64)
        return try readFixed(UInt64.self)
    }

    mutating func floatField(_ field: ProtobufFormat.Field) throws -> Float {
        Float(bitPattern: try fixed32Field(field))
    }

    mutating func doubleField(_ field: ProtobufFormat.Field) throws -> Double {
        if field.wireType == .fixed32 {
            return Double(try floatField(field))
        }
        return Double(bitPattern: try fixed64Field(field))
    }

    mutating func cgFloatField(_ field: ProtobufFormat.Field) throws -> CGFloat {
        CGFloat(try doubleField(field))
    }

    mutating func beginMessage() throws {
        // A failed length read retains the pushed enclosing boundary.
        stack.append(end)
        end = try decodeLengthEnd()
    }

    mutating func decodeMessage<Message: ProtobufDecodableMessage>() throws -> Message {
        try beginMessage()
        defer { end = stack.removeLast() }
        return try Message(from: &self)
    }

    mutating func decodeMessage<Result>(
        _ body: (inout ProtobufDecoder) throws -> Result
    ) throws -> Result {
        try beginMessage()
        defer { end = stack.removeLast() }
        return try body(&self)
    }

    mutating func messageField<Message: ProtobufDecodableMessage>(
        _ field: ProtobufFormat.Field
    ) throws -> Message {
        guard field.wireType == .lengthDelimited else { throw DecodingError.failed }
        return try decodeMessage()
    }

    mutating func messageField<Result>(
        _ field: ProtobufFormat.Field,
        _ body: (inout ProtobufDecoder) throws -> Result
    ) throws -> Result {
        guard field.wireType == .lengthDelimited else { throw DecodingError.failed }
        return try decodeMessage(body)
    }

    mutating func decodeDataBuffer() throws -> UnsafeRawBufferPointer {
        let stop = try decodeLengthEnd()
        defer { ptr = stop }
        return UnsafeRawBufferPointer(start: ptr, count: ptr.distance(to: stop))
    }

    mutating func dataBufferField(_ field: ProtobufFormat.Field) throws -> UnsafeRawBufferPointer {
        guard field.wireType == .lengthDelimited else { throw DecodingError.failed }
        return try decodeDataBuffer()
    }

    mutating func skipField(_ field: ProtobufFormat.Field) throws {
        switch field.wireType {
        case .varint: _ = try decodeVarint()
        case .lengthDelimited: _ = try decodeDataBuffer()
        case .fixed64, .fixed32:
            let count = field.wireType == .fixed64 ? 8 : 4
            guard count <= ptr.distance(to: end) else { throw DecodingError.failed }
            ptr += count
        default: throw DecodingError.failed
        }
    }

    private mutating func prepareScalar(
        _ field: ProtobufFormat.Field, wireType: ProtobufFormat.WireType
    ) throws {
        if field.wireType == .lengthDelimited {
            let stop = try decodeLengthEnd()
            packedField = .init(field.tag, wireType: wireType)
            packedEnd = stop
        } else if field.wireType != wireType {
            throw DecodingError.failed
        }
    }

    private mutating func readFixed<Value: FixedWidthInteger>(_ type: Value.Type) throws -> Value {
        let count = MemoryLayout<Value>.size
        guard count <= ptr.distance(to: end) else { throw DecodingError.failed }
        defer { ptr += count }
        return Value(littleEndian: ptr.loadUnaligned(as: Value.self))
    }

    private mutating func decodeLengthEnd() throws -> UnsafeRawPointer {
        let length = try decodeVarint()
        guard let count = Int(exactly: length), count <= ptr.distance(to: end) else {
            throw DecodingError.failed
        }
        return ptr + count
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

    while let field = try decoder.nextField() {
        let fieldNumber = field.tag

        switch fieldNumber {
        case 1:
            first = try decoder.cgFloatField(field)
        case 2:
            second = try decoder.cgFloatField(field)
        default:
            try decoder.skipField(field)
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
        while let field = try decoder.nextField() {
            let fieldNumber = field.tag
            switch fieldNumber {
            case 1:
                x = try decoder.cgFloatField(field)
            case 2:
                y = try decoder.cgFloatField(field)
            case 3:
                width = try decoder.cgFloatField(field)
            case 4:
                height = try decoder.cgFloatField(field)
            default:
                try decoder.skipField(field)
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
