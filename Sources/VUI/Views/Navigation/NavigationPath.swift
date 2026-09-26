//
//  File: NavigationPath.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

final class NavigationPathItemBox {
    struct Coding {
        var typeName: String
        var encode: () throws -> String
    }

    let value: AnyHashable
    let declaredType: Any.Type
    let coding: Coding?

    init<V>(_ value: V) where V: Hashable {
        self.value = AnyHashable(value)
        self.declaredType = V.self
        self.coding = nil
    }

    init<V>(codable value: V) where V: Codable & Hashable {
        self.value = AnyHashable(value)
        self.declaredType = V.self
        self.coding = Coding(
            typeName: String(reflecting: V.self),
            encode: {
                String(
                    decoding: try JSONEncoder().encode(value),
                    as: UTF8.self
                )
            }
        )
    }

    static func isEqual(
        lhs: NavigationPathItemBox,
        rhs: NavigationPathItemBox
    ) -> Bool {
        ObjectIdentifier(lhs.declaredType)
            == ObjectIdentifier(rhs.declaredType)
            && lhs.value == rhs.value
    }
}

struct NavigationPathLazyItem: Equatable {
    var typeName: String
    var payload: String

    var declaredType: Any.Type? {
        _typeByName(typeName)
    }

    var value: AnyHashable? {
        guard let declaredType,
              let decodableType = declaredType as? any Decodable.Type,
              let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(
                decodableType,
                from: data
              ),
              let hashable = decoded as? any Hashable else {
            return nil
        }
        return AnyHashable(hashable)
    }
}

enum NavigationPathItem {
    case eager(NavigationPathItemBox)
    case lazy(NavigationPathLazyItem)

    var count: Int { 1 }

    var declaredType: Any.Type? {
        switch self {
        case let .eager(item):
            item.declaredType
        case let .lazy(item):
            item.declaredType
        }
    }

    var value: AnyHashable? {
        switch self {
        case let .eager(item):
            item.value
        case let .lazy(item):
            item.value
        }
    }

    var coding: (typeName: String, payload: String)? {
        switch self {
        case let .eager(item):
            guard let coding = item.coding,
                  let payload = try? coding.encode() else {
                return nil
            }
            return (coding.typeName, payload)
        case let .lazy(item):
            return (item.typeName, item.payload)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.eager(lhs), .eager(rhs)):
            NavigationPathItemBox.isEqual(lhs: lhs, rhs: rhs)
        case let (.lazy(lhs), .lazy(rhs)):
            lhs == rhs
        case (.eager, .lazy), (.lazy, .eager):
            false
        }
    }
}

struct NavigationPathElement {
    var id: AnyHashable
    var declaredType: Any.Type?
    var value: AnyHashable?

    var typeID: ObjectIdentifier? {
        declaredType.map(ObjectIdentifier.init)
    }
}

private enum NavigationPathElementIdentity: Hashable {
    case eager(ObjectIdentifier, AnyHashable)
    case lazy(String, String)
}

public struct NavigationPath {
    private var items: [NavigationPathItem]
    private var subsequentItems: [NavigationPathItemBox]
    private var iterationIndex: Int

    public var count: Int {
        items.count + subsequentItems.count
    }

    public var isEmpty: Bool {
        count == 0
    }

    public var codable: CodableRepresentation? {
        let allItems = materializedItems
        guard allItems.allSatisfy({ $0.coding != nil }) else {
            return nil
        }
        return CodableRepresentation(items: allItems)
    }

    public init() {
        items = []
        subsequentItems = []
        iterationIndex = 0
    }

    public init<S>(_ elements: S) where S: Sequence, S.Element: Hashable {
        items = elements.map {
            .eager(NavigationPathItemBox($0))
        }
        subsequentItems = []
        iterationIndex = 0
    }

    public init<S>(_ elements: S)
    where S: Sequence, S.Element: Codable & Hashable {
        items = elements.map {
            .eager(NavigationPathItemBox(codable: $0))
        }
        subsequentItems = []
        iterationIndex = 0
    }

    public init(_ codable: CodableRepresentation) {
        items = codable.items
        subsequentItems = []
        iterationIndex = 0
    }

    public mutating func append<V>(_ value: V) where V: Hashable {
        materializeSubsequentItems()
        items.append(.eager(NavigationPathItemBox(value)))
    }

    public mutating func append<V>(_ value: V)
    where V: Codable & Hashable {
        materializeSubsequentItems()
        items.append(.eager(NavigationPathItemBox(codable: value)))
    }

    public mutating func removeLast(_ k: Int = 1) {
        precondition(k >= 0, "Can't remove a negative number of elements.")
        precondition(k <= count, "Can't remove more items than the path contains.")
        materializeSubsequentItems()
        items.removeLast(k)
        iterationIndex = min(iterationIndex, items.count)
    }

    private var materializedItems: [NavigationPathItem] {
        items + subsequentItems.map(NavigationPathItem.eager)
    }

    private mutating func materializeSubsequentItems() {
        guard !subsequentItems.isEmpty else { return }
        items.append(contentsOf: subsequentItems.map(NavigationPathItem.eager))
        subsequentItems.removeAll(keepingCapacity: true)
    }

    var navigationElements: [NavigationPathElement] {
        materializedItems.map {
            switch $0 {
            case let .eager(item):
                NavigationPathElement(
                    id: AnyHashable(NavigationPathElementIdentity.eager(
                        ObjectIdentifier(item.declaredType),
                        item.value
                    )),
                    declaredType: item.declaredType,
                    value: item.value
                )
            case let .lazy(item):
                NavigationPathElement(
                    id: AnyHashable(NavigationPathElementIdentity.lazy(
                        item.typeName,
                        item.payload
                    )),
                    declaredType: item.declaredType,
                    value: item.value
                )
            }
        }
    }

    mutating func append(_ item: NavigationPathItem) {
        materializeSubsequentItems()
        items.append(item)
    }

    static func item<V>(_ value: V) -> NavigationPathItem where V: Hashable {
        .eager(NavigationPathItemBox(value))
    }

    static func item<V>(_ value: V) -> NavigationPathItem
    where V: Codable & Hashable {
        .eager(NavigationPathItemBox(codable: value))
    }

    fileprivate struct CodableRepresentationStorage {
        var items: [NavigationPathItem]
    }

    public struct CodableRepresentation: Codable {
        private var storage: CodableRepresentationStorage

        fileprivate var items: [NavigationPathItem] {
            storage.items
        }

        fileprivate init(items: [NavigationPathItem]) {
            storage = CodableRepresentationStorage(items: items)
        }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.singleValueContainer().decode([String].self)
            guard values.count.isMultiple(of: 2) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Navigation path data must contain type and value pairs."
                )
            }

            var decoded: [NavigationPathItem] = []
            decoded.reserveCapacity(values.count / 2)
            for index in stride(from: 0, to: values.count, by: 2) {
                decoded.append(.lazy(NavigationPathLazyItem(
                    typeName: values[index],
                    payload: values[index + 1]
                )))
            }
            storage = CodableRepresentationStorage(items: decoded.reversed())
        }

        public func encode(to encoder: any Encoder) throws {
            var values: [String] = []
            values.reserveCapacity(items.count * 2)
            for item in items.reversed() {
                guard let coding = item.coding else {
                    throw EncodingError.invalidValue(
                        item,
                        EncodingError.Context(
                            codingPath: encoder.codingPath,
                            debugDescription: "Navigation path item is not Codable."
                        )
                    )
                }
                values.append(coding.typeName)
                values.append(coding.payload)
            }
            var container = encoder.singleValueContainer()
            try container.encode(values)
        }
    }
}

extension NavigationPath: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        let lhsItems = lhs.materializedItems
        let rhsItems = rhs.materializedItems
        return lhsItems.count == rhsItems.count
            && zip(lhsItems, rhsItems).allSatisfy(==)
    }
}

extension NavigationPath.CodableRepresentation: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.items.count == rhs.items.count
            && zip(lhs.items, rhs.items).allSatisfy(==)
    }
}

@available(*, unavailable)
extension NavigationPath: Sendable {
}

@available(*, unavailable)
extension NavigationPath.CodableRepresentation: Sendable {
}
