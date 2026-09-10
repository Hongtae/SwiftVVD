//
//  File: Serializable.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol Serializable {
    func serialize(to encoder: any Encoder) throws
    static func deserialize(from decoder: any Decoder) throws -> Self
}

protocol CodableSerializable: Serializable, Codable {}

extension CodableSerializable {
    func serialize(to encoder: any Encoder) throws {
        try encode(to: encoder)
    }

    static func deserialize(from decoder: any Decoder) throws -> Self {
        try Self(from: decoder)
    }
}

protocol EmptySerializable: Serializable {
    init()
}

extension EmptySerializable {
    func serialize(to encoder: any Encoder) throws {}

    static func deserialize(from decoder: any Decoder) throws -> Self {
        Self()
    }
}

protocol CodableByProxy: Serializable {
    associatedtype CodingProxy: Codable
    var codingProxy: CodingProxy { get }
    static func unwrap(codingProxy: CodingProxy) -> Self
}

extension CodableByProxy {
    func serialize(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(codingProxy)
    }

    static func deserialize(from decoder: any Decoder) throws -> Self {
        let container = try decoder.singleValueContainer()
        return unwrap(codingProxy: try container.decode(CodingProxy.self))
    }
}

protocol CodableProxy: Codable {
    associatedtype Base
    var base: Base { get }
}

extension CodableByProxy where CodingProxy: CodableProxy, CodingProxy.Base == Self {
    static func unwrap(codingProxy: CodingProxy) -> Self {
        codingProxy.base
    }
}

extension Optional: Serializable, CodableByProxy where Wrapped: CodableByProxy {
    var codingProxy: CodableOptional<Wrapped> {
        CodableOptional(self)
    }
}

struct CodableOptional<T: CodableByProxy>: CodableProxy {
    var base: T?

    init(_ base: T?) {
        self.base = base
    }

    private enum CodingKeys: CodingKey {
        case value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        base = try container.decodeIfPresent(T.CodingProxy.self, forKey: .value)
            .map { T.unwrap(codingProxy: $0) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let base {
            try container.encode(base.codingProxy, forKey: .value)
        }
    }
}

extension RawRepresentable where RawValue: Codable {
    var codingProxy: RawRepresentableProxy<Self> {
        RawRepresentableProxy(base: self)
    }
}

struct RawRepresentableProxy<Base: RawRepresentable>: CodableProxy where Base.RawValue: Codable {
    let base: Base

    init(base: Base) {
        self.base = base
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Base.RawValue.self)
        guard let base = Base(rawValue: rawValue) else {
            throw Error.unarchivingError
        }
        self.base = base
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(base.rawValue)
    }
}

@propertyWrapper
struct CodableRawRepresentable<Value: RawRepresentable>: Codable where Value.RawValue: Codable {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    init(_ value: Value) {
        self.wrappedValue = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Value.RawValue.self)
        guard let value = Value(rawValue: rawValue) else {
            throw Error.unarchivingError
        }
        wrappedValue = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.rawValue)
    }
}

extension CodableRawRepresentable: Equatable where Value: Equatable {}
extension CodableRawRepresentable: Hashable where Value: Hashable {}

private enum Error: Swift.Error {
    case unarchivingError
}

@propertyWrapper
struct ProxyCodable<Value: Serializable>: Codable {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    init(_ value: Value) {
        self.wrappedValue = value
    }

    var projectedValue: Self { self }

    init(from decoder: any Decoder) throws {
        wrappedValue = try Value.deserialize(from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        try wrappedValue.serialize(to: encoder)
    }
}

extension ProxyCodable: Equatable where Value: Equatable {}
extension ProxyCodable: Hashable where Value: Hashable {}

protocol AnyCodableBox<Box> {
    associatedtype Box where Box == Tag.Box, Tag == Box.Tag
    associatedtype Tag: CodableBoxTag
    var tag: Tag { get }
}

protocol CodableBox<Box>: AnyCodableBox, Serializable {}

protocol CodableBoxTag: Codable {
    associatedtype Box: AnyCodableBox
    var box: any CodableBox<Box>.Type { get }
}

enum CodableBoxCodingKeys: Int, CodingKey {
    case tag
    case value
}

extension AnyCodableBox {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodableBoxCodingKeys.self)
        try container.encode(tag, forKey: .tag)
        try tag.box.encode(self, to: &container)
    }

    static func decode(from decoder: any Decoder) throws -> Box {
        let container = try decoder.container(keyedBy: CodableBoxCodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        return try tag.box.decode(from: container) as! Box
    }
}

extension CodableBox {
    static func decode(from container: KeyedDecodingContainer<CodableBoxCodingKeys>) throws -> any CodableBox<Box> {
        try container.decode(ProxyCodable<Self>.self, forKey: .value).wrappedValue
    }

    static func encode(_ value: Any, to container: inout KeyedEncodingContainer<CodableBoxCodingKeys>) throws {
        guard let value = value as? any CodableBox else {
            throw EncodingError.invalidValue(value, .init(
                codingPath: container.codingPath,
                debugDescription: "Encountered mismatched box value."
            ))
        }
        try value.serialize(into: &container)
    }

    func serialize(into container: inout KeyedEncodingContainer<CodableBoxCodingKeys>) throws {
        try container.encode(ProxyCodable(self), forKey: .value)
    }
}
