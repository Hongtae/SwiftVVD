//
//  File: LineHeight.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
#if canImport(CoreText)
import CoreText
#endif

#if !canImport(CoreText)
extension AttributedString {
    public struct LineHeight: Codable, Hashable, Sendable {
        enum BaselineInterval: Codable, Hashable, Sendable {
            case variable
            case multiple(factor: CGFloat)
            case leading(increase: CGFloat)
            case exact(points: CGFloat)
        }

        let baselineInterval: BaselineInterval

        public static var variable: Self {
            Self(baselineInterval: .variable)
        }

        public static var normal: Self {
            multiple(factor: 1.2)
        }

        public static var tight: Self {
            multiple(factor: 1)
        }

        public static var loose: Self {
            multiple(factor: 1.5)
        }

        public static func multiple(factor: CGFloat) -> Self {
            Self(baselineInterval: .multiple(factor: factor))
        }

        public static func leading(increase: CGFloat) -> Self {
            Self(baselineInterval: .leading(increase: increase))
        }

        public static func exact(points: CGFloat) -> Self {
            Self(baselineInterval: .exact(points: points))
        }
    }
}
#endif

enum TextLineHeightInterval {
    case variable
    case multiple(CGFloat)
    case leading(CGFloat)
    case exact(CGFloat)
}

private enum TextLineHeightIntervalKind {
    case multiple
    case leading
    case exact

    func interval(_ value: CGFloat) -> TextLineHeightInterval {
        switch self {
        case .multiple: .multiple(value)
        case .leading: .leading(value)
        case .exact: .exact(value)
        }
    }
}

private enum TextLineHeightEncodingContext {
    case root
    case baselineInterval
    case associatedValue(TextLineHeightIntervalKind)
    case scalar(TextLineHeightIntervalKind)
    case finished
}

// Keyed encoding containers are copied as they descend, so one reference
// collects the single semantic result without inspecting resilient storage.
private final class TextLineHeightEncodingResult {
    var interval: TextLineHeightInterval?

    func set(_ interval: TextLineHeightInterval) {
        guard case nil = self.interval else {
            _unsupported()
        }
        self.interval = interval
    }
}

private func _unsupported() -> Never {
    preconditionFailure("Unsupported line-height coding shape.")
}

// LineHeight has no public interval accessor. Its public Codable shape is the
// shared semantic boundary for both the SDK overlay and portable declaration.
private struct TextLineHeightIntervalEncoder: Encoder {
    let result: TextLineHeightEncodingResult
    let context: TextLineHeightEncodingContext

    var codingPath: [any CodingKey] { [] }
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key>(
        keyedBy type: Key.Type
    ) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        switch context {
        case .root, .baselineInterval:
            KeyedEncodingContainer(
                TextLineHeightKeyedEncodingContainer<Key>(
                    result: result,
                    context: context
                )
            )
        case .associatedValue, .scalar, .finished:
            _unsupported()
        }
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer { _unsupported() }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        guard case let .scalar(kind) = context else {
            _unsupported()
        }
        return TextLineHeightSingleValueEncodingContainer(
            result: result,
            kind: kind
        )
    }
}

private struct TextLineHeightKeyedEncodingContainer<Key: CodingKey>:
    KeyedEncodingContainerProtocol
{
    let result: TextLineHeightEncodingResult
    let context: TextLineHeightEncodingContext

    var codingPath: [any CodingKey] { [] }

    mutating func encodeNil(forKey: Key) throws { _unsupported() }
    mutating func encode(_: Bool, forKey: Key) throws { _unsupported() }
    mutating func encode(_: String, forKey: Key) throws { _unsupported() }
    mutating func encode(_: Double, forKey: Key) throws { _unsupported() }
    mutating func encode(_: Float, forKey: Key) throws { _unsupported() }
    mutating func encode(_: Int, forKey: Key) throws { _unsupported() }
    mutating func encode(_: Int8, forKey: Key) throws { _unsupported() }
    mutating func encode(_: Int16, forKey: Key) throws { _unsupported() }
    mutating func encode(_: Int32, forKey: Key) throws { _unsupported() }
    mutating func encode(_: Int64, forKey: Key) throws { _unsupported() }
    mutating func encode(_: UInt, forKey: Key) throws { _unsupported() }
    mutating func encode(_: UInt8, forKey: Key) throws { _unsupported() }
    mutating func encode(_: UInt16, forKey: Key) throws { _unsupported() }
    mutating func encode(_: UInt32, forKey: Key) throws { _unsupported() }
    mutating func encode(_: UInt64, forKey: Key) throws { _unsupported() }

    mutating func encode<T: Encodable>(
        _ value: T,
        forKey key: Key
    ) throws {
        let nextContext: TextLineHeightEncodingContext
        switch context {
        case .root:
            guard key.stringValue == "baselineInterval" else {
                _unsupported()
            }
            nextContext = .baselineInterval
        case let .associatedValue(kind):
            let expectedKey: String
            switch kind {
            case .multiple: expectedKey = "factor"
            case .leading: expectedKey = "increase"
            case .exact: expectedKey = "points"
            }
            guard key.stringValue == expectedKey else {
                _unsupported()
            }
            nextContext = .scalar(kind)
        case .baselineInterval, .scalar, .finished:
            _unsupported()
        }
        try value.encode(
            to: TextLineHeightIntervalEncoder(
                result: result,
                context: nextContext
            )
        )
    }

    mutating func nestedContainer<NestedKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        guard case .baselineInterval = context else {
            _unsupported()
        }

        let nextContext: TextLineHeightEncodingContext
        switch key.stringValue {
        case "variable":
            result.set(.variable)
            nextContext = .finished
        case "multiple":
            nextContext = .associatedValue(.multiple)
        case "leading":
            nextContext = .associatedValue(.leading)
        case "exact":
            nextContext = .associatedValue(.exact)
        default:
            _unsupported()
        }
        return KeyedEncodingContainer(
            TextLineHeightKeyedEncodingContainer<NestedKey>(
                result: result,
                context: nextContext
            )
        )
    }

    mutating func nestedUnkeyedContainer(forKey: Key) -> any UnkeyedEncodingContainer { _unsupported() }

    mutating func superEncoder() -> any Encoder { _unsupported() }
    mutating func superEncoder(forKey: Key) -> any Encoder { _unsupported() }
}

private struct TextLineHeightSingleValueEncodingContainer:
    SingleValueEncodingContainer
{
    let result: TextLineHeightEncodingResult
    let kind: TextLineHeightIntervalKind

    var codingPath: [any CodingKey] { [] }

    func encodeNil() throws { _unsupported() }
    func encode(_: Bool) throws { _unsupported() }
    func encode(_: String) throws { _unsupported() }

    func encode(_ value: Double) throws {
        result.set(kind.interval(CGFloat(value)))
    }

    func encode(_ value: Float) throws {
        result.set(kind.interval(CGFloat(value)))
    }

    func encode(_: Int) throws { _unsupported() }
    func encode(_: Int8) throws { _unsupported() }
    func encode(_: Int16) throws { _unsupported() }
    func encode(_: Int32) throws { _unsupported() }
    func encode(_: Int64) throws { _unsupported() }
    func encode(_: UInt) throws { _unsupported() }
    func encode(_: UInt8) throws { _unsupported() }
    func encode(_: UInt16) throws { _unsupported() }
    func encode(_: UInt32) throws { _unsupported() }
    func encode(_: UInt64) throws { _unsupported() }
    func encode<T: Encodable>(_: T) throws { _unsupported() }
}

extension AttributedString.LineHeight {
    var textLineHeightInterval: TextLineHeightInterval {
        let result = TextLineHeightEncodingResult()
        do {
            try encode(
                to: TextLineHeightIntervalEncoder(
                    result: result,
                    context: .root
                )
            )
        } catch { _unsupported() }
        guard let interval = result.interval else {
            _unsupported()
        }
        return interval
    }
}
