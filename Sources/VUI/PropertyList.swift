//
//  File: PropertyList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Stack<Element> is a LIFO linked list used as the Value type for PropertyKey
// conformers such as StyleInput, SourceInput, and BodyInput.
// push constructs .node(element, currentStack).
enum Stack<Element> {
    case empty
    indirect case node(Element, Stack<Element>)

    var top: Element? {
        guard case .node(let v, _) = self else { return nil }
        return v
    }

    var isEmpty: Bool {
        guard case .empty = self else { return false }
        return true
    }

    mutating func pop() -> Element? {
        guard case .node(let v, let rest) = self else { return nil }
        self = rest
        return v
    }

    func map<T>(_ transform: (Element) -> T) -> Stack<T> {
        switch self {
        case .empty: return .empty
        case .node(let v, let rest): return .node(transform(v), rest.map(transform))
        }
    }
}

extension Stack: IteratorProtocol {
    mutating func next() -> Element? { pop() }
}

// Bloom filter for fast negative lookup in PropertyList chains.
// 64-bit bit-array: if a key's bits are not set, it is definitely not in the chain.
// False positives are possible (full scan still needed on hit).
struct BloomFilter: CustomStringConvertible {
    var value: UInt64 = 0

    mutating func insert(_ key: any PropertyKey.Type) {
        let h = UInt64(UInt(bitPattern: ObjectIdentifier(key)))
        value |= (UInt64(1) << (h & 63)) | (UInt64(1) << ((h >> 6) & 63))
    }

    func mightContain(_ key: any PropertyKey.Type) -> Bool {
        let h = UInt64(UInt(bitPattern: ObjectIdentifier(key)))
        let bit1 = UInt64(1) << (h & 63)
        let bit2 = UInt64(1) << ((h >> 6) & 63)
        return (value & bit1 == bit1) && (value & bit2 == bit2)
    }

    var description: String { "BloomFilter(value: \(value))" }
}

// Property-list element identity uses AttributeGraph's unique-ID allocator.
struct UniqueID: Equatable, CustomStringConvertible {
    let value: UInt32
    init() {
        value = UInt32(truncatingIfNeeded: AGMakeUniqueID())
    }
    var description: String { "UniqueID(value: \(value))" }
}

// Placeholder for per-key change tracking integration. It remains empty until
// tracker support is wired into graph-managed environment reads.
class _PropertyListTracker {}

@usableFromInline
struct PropertyList: CustomStringConvertible {

    @usableFromInline
    var elements: Element?

    @inlinable init() {
        self.elements = nil
    }

    @inlinable var data: AnyObject? {
        elements
    }

    @inlinable var isEmpty: Bool {
        elements === nil
    }

    @inlinable func isIdentical(to other: PropertyList) -> Bool {
        elements === other.elements
    }

    @usableFromInline
    var description: String {
        if let elements {
            return "[\(elements.description)]"
        }
        return "[]"
    }
}

extension PropertyList {
    // Setting a value prepends a new node unless it equals the current value.
    // Older nodes for the same key remain shadowed by the head.
    @usableFromInline
    subscript<K: PropertyKey>(_ key: K.Type) -> K.Value {
        get { value(forKey: key) }
        mutating set {
            if let existing = nonDefaultValue(forKey: key), K.valuesEqual(existing, newValue) {
                return
            }
            elements = TypedElement(key: key, value: newValue, after: elements)
        }
    }

    // Unconditional prepend helper.
    mutating func prependValue<K: PropertyKey>(_ value: K.Value, for key: K.Type) {
        elements = TypedElement(key: key, value: value, after: elements)
    }

    // MARK: - Local helpers

    func nonDefaultValue<T: PropertyKey>(forKey key: T.Type) -> T.Value? {
        var element = self.elements
        while let current = element {
            if current.keyType == key {
                return (current as! TypedElement<T>).value
            }
            if !current.skipFilter.mightContain(key) { return nil }
            element = current.after
        }
        return nil
    }

    func value<T: PropertyKey>(forKey key: T.Type) -> T.Value {
        nonDefaultValue(forKey: key) ?? T.defaultValue
    }

    mutating func setValue<T: PropertyKey>(_ value: T.Value, forKey key: T.Type) {
        self[key] = value
    }
}

// Base protocol for PropertyList key types.
// PropertyKey is the root of the PropertyKey -> GraphInput -> ViewInput hierarchy.
@usableFromInline
protocol PropertyKey {
    associatedtype Value
    static var defaultValue: Value { get }
    static func valuesEqual(_ a: Value, _ b: Value) -> Bool
}

extension PropertyKey where Value: Equatable {
    static func valuesEqual(_ a: Value, _ b: Value) -> Bool { a == b }
}

extension PropertyList {
    @usableFromInline
    class Element: CustomStringConvertible {
        let keyType: any PropertyKey.Type
        let before: Element?               // set by init — caller passes nil in the persistent-list setter path
        let after: Element?                // next element in chain
        var skip: Unmanaged<Element>?      // skip-list pointer (nil = not used)
        let length: UInt32                 // chain length from this node to end
        var skipCount: UInt32              // number of elements the skip pointer jumps
        let skipFilter: BloomFilter        // bloom filter covering elements after this node
        let id: UniqueID

        init(keyType: any PropertyKey.Type, before: Element? = nil, after: Element? = nil) {
            self.keyType = keyType
            self.before = before
            self.after = after
            self.skip = nil
            self.length = 1 + (after?.length ?? 0)
            self.skipCount = 0
            if let after {
                var filter = after.skipFilter
                filter.insert(after.keyType)
                self.skipFilter = filter
            } else {
                self.skipFilter = BloomFilter()
            }
            self.id = UniqueID()
        }

        @usableFromInline
        var description: String {
            let desc = "\(keyType) = \(valueDescription)"
            if let after {
                return "\(desc), \(after.description)"
            }
            return desc
        }

        var valueDescription: String { fatalError("TypedElement must override valueDescription") }

        // Rebuild this node with `tail` at the end of the chain (subclass must override).
        func rebuilt(appending tail: Element?) -> Element { fatalError("TypedElement must override rebuilt(appending:)") }
    }

    // Typed subclass — value is stored with the concrete Value type rather than Any.
    final class TypedElement<T: PropertyKey>: Element {
        var value: T.Value

        init(key: T.Type, value: T.Value, after: Element? = nil) {
            self.value = value
            super.init(keyType: key, after: after)
        }

        override var valueDescription: String { "\(value)" }

        // Rebuild this node with `tail` appended at the end of the chain.
        // Used by PropertyList.merge to create a new chain where self's entries have
        // higher priority (appear first) and `tail` (other's chain) fills in the rest.
        override func rebuilt(appending tail: Element?) -> Element {
            TypedElement<T>(key: T.self, value: value,
                            after: after?.rebuilt(appending: tail) ?? tail)
        }
    }

    // Merge `other`'s entries into `self` at lower priority.
    // Self's existing entries remain at the head (higher priority);
    // other's entries are appended at the tail as fallbacks.
    mutating func merge(_ other: PropertyList) {
        guard !other.isEmpty else { return }
        guard !self.isEmpty else { self = other; return }
        elements = elements!.rebuilt(appending: other.elements)
    }

    init<Key: PropertyKey>(_ key: Key.Type, value: Key.Value) {
        self.elements = TypedElement(key: key, value: value)
    }
}
