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

    func isEqual(to other: PropertyList) -> Bool {
        switch (elements, other.elements) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.isListEqual(to: rhs)
        default:
            return false
        }
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

    func forEachValue<Value>(ofType valueType: Value.Type,
                             _ body: (any PropertyKey.Type, Value) -> Bool) -> Bool {
        var seenKeys = Set<ObjectIdentifier>()
        var element = self.elements
        while let current = element {
            // PropertyList keeps older nodes for the same key as shadowed tail
            // entries. Typed iteration must visit only the first live value per
            // key, otherwise a popped stack can still look non-empty through an
            // obsolete tail node.
            let keyID = ObjectIdentifier(current.keyType)
            if seenKeys.insert(keyID).inserted,
               current.visitValue(ofType: valueType, body) {
                return true
            }
            element = current.after
        }
        return false
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

protocol DerivedPropertyKey {
    associatedtype Value: Equatable
    static func value(in plist: PropertyList) -> Value
}

protocol PropertyKeyLookup {
    associatedtype Primary: PropertyKey
    associatedtype Secondary: PropertyKey

    static func lookup(in value: Secondary.Value) -> Primary.Value?
}

private protocol _AnyTrackedValue {
    func value<Value>(as type: Value.Type) -> Value?
    func hasMatchingValue(in plist: PropertyList) -> Bool
}

private struct TrackedValue<K: PropertyKey>: _AnyTrackedValue {
    var value: K.Value

    func value<Value>(as type: Value.Type) -> Value? {
        value as? Value
    }

    func hasMatchingValue(in plist: PropertyList) -> Bool {
        K.valuesEqual(value, plist[K.self])
    }
}

private struct DerivedValue<K: DerivedPropertyKey>: _AnyTrackedValue {
    var value: K.Value

    func value<Value>(as type: Value.Type) -> Value? {
        value as? Value
    }

    func hasMatchingValue(in plist: PropertyList) -> Bool {
        value == plist[K.self]
    }
}

private struct SecondaryLookupTrackedValue<K: PropertyKeyLookup>: _AnyTrackedValue {
    var value: K.Primary.Value

    func value<Value>(as type: Value.Type) -> Value? {
        value as? Value
    }

    func hasMatchingValue(in plist: PropertyList) -> Bool {
        K.Primary.valuesEqual(value, plist.valueWithSecondaryLookup(K.self))
    }
}

final class _PropertyListTracker {
    private var trackedID: UniqueID?
    private var trackedValues: [ObjectIdentifier: any _AnyTrackedValue] = [:]
    private var derivedValues: [ObjectIdentifier: any _AnyTrackedValue] = [:]
    private var pendingValues: [any _AnyTrackedValue] = []
    private var dirty = false

    func reset() {
        trackedID = nil
        trackedValues.removeAll()
        derivedValues.removeAll()
        pendingValues.removeAll()
        dirty = false
    }

    func initializeValues(from plist: PropertyList) {
        trackedID = plist.id
    }

    func value<K: PropertyKey>(_ plist: PropertyList, for key: K.Type) -> K.Value {
        guard trackedID == plist.id else {
            dirty = true
            return plist[key]
        }
        let id = ObjectIdentifier(key)
        if let value = trackedValues[id]?.value(as: K.Value.self) {
            return value
        }
        let value = plist[key]
        trackedValues[id] = TrackedValue<K>(value: value)
        return value
    }

    func derivedValue<K: DerivedPropertyKey>(_ plist: PropertyList, for key: K.Type) -> K.Value {
        guard trackedID == plist.id else {
            dirty = true
            return plist[key]
        }
        let id = ObjectIdentifier(key)
        if let value = derivedValues[id]?.value(as: K.Value.self) {
            return value
        }
        let value = plist[key]
        derivedValues[id] = DerivedValue<K>(value: value)
        return value
    }

    func valueWithSecondaryLookup<K: PropertyKeyLookup>(
        _ plist: PropertyList,
        secondaryLookupHandler lookup: K.Type
    ) -> K.Primary.Value {
        guard trackedID == plist.id else {
            dirty = true
            return plist.valueWithSecondaryLookup(lookup)
        }
        let id = ObjectIdentifier(K.Primary.self)
        if let value = trackedValues[id]?.value(as: K.Primary.Value.self) {
            return value
        }
        let value = plist.valueWithSecondaryLookup(lookup)
        trackedValues[id] = SecondaryLookupTrackedValue<K>(value: value)
        return value
    }

    func hasDifferentUsedValues(_ plist: PropertyList) -> Bool {
        if dirty { return true }
        if trackedID != plist.id {
            if trackedValues.values.contains(where: { !$0.hasMatchingValue(in: plist) }) {
                return true
            }
            if derivedValues.values.contains(where: { !$0.hasMatchingValue(in: plist) }) {
                return true
            }
        }
        return pendingValues.contains { !$0.hasMatchingValue(in: plist) }
    }

    func invalidateAllValues(from: PropertyList, to: PropertyList) {
        guard trackedID == from.id, trackedID != to.id else { return }
        pendingValues.append(contentsOf: trackedValues.values)
        pendingValues.append(contentsOf: derivedValues.values)
        trackedValues.removeAll()
        derivedValues.removeAll()
        trackedID = to.id
    }

    func invalidateValue<K: PropertyKey>(for key: K.Type, from: PropertyList, to: PropertyList) {
        guard trackedID == from.id, trackedID != to.id else { return }
        if let removed = trackedValues.removeValue(forKey: ObjectIdentifier(key)) {
            pendingValues.append(removed)
        }
        pendingValues.append(contentsOf: derivedValues.values)
        derivedValues.removeAll()
        trackedID = to.id
    }

    func formUnion(_ other: _PropertyListTracker) {
        guard let otherID = other.trackedID, trackedID != otherID else {
            return
        }
        if trackedID == nil {
            trackedID = otherID
            trackedValues = other.trackedValues
            derivedValues = other.derivedValues
            pendingValues = other.pendingValues
            dirty = other.dirty
            return
        }
        trackedID = otherID
        trackedValues.merge(other.trackedValues) { current, _ in current }
        derivedValues.merge(other.derivedValues) { current, _ in current }
        pendingValues.append(contentsOf: other.pendingValues)
        dirty = dirty || other.dirty
    }
}

extension PropertyList {
    fileprivate var id: UniqueID? {
        elements?.id
    }

    subscript<K: DerivedPropertyKey>(_ key: K.Type) -> K.Value {
        K.value(in: self)
    }

    func valueWithSecondaryLookup<K: PropertyKeyLookup>(_ lookup: K.Type) -> K.Primary.Value {
        findValueWithSecondaryLookup(lookup) ?? K.Primary.defaultValue
    }

    private func findValueWithSecondaryLookup<K: PropertyKeyLookup>(_ lookup: K.Type) -> K.Primary.Value? {
        var element = self.elements
        while let current = element {
            if current.keyType == K.Primary.self {
                return (current as! TypedElement<K.Primary>).value
            }
            if current.keyType == K.Secondary.self,
               let value = K.lookup(in: (current as! TypedElement<K.Secondary>).value) {
                return value
            }
            if !current.skipFilter.mightContain(K.Primary.self),
               !current.skipFilter.mightContain(K.Secondary.self) {
                return nil
            }
            element = current.after
        }
        return nil
    }
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

        func isValueEqual(to other: Element) -> Bool { false }

        func isListEqual(to other: Element) -> Bool {
            var ignoredTypes = Set<ObjectIdentifier>()
            return isListEqual(to: other, ignoredTypes: &ignoredTypes)
        }

        private func isListEqual(to other: Element, ignoredTypes: inout Set<ObjectIdentifier>) -> Bool {
            guard length == other.length else { return false }
            var lhs: Element? = self
            var rhs: Element? = other
            while let lhsElement = lhs, let rhsElement = rhs {
                if lhsElement === rhsElement {
                    return true
                }
                guard lhsElement.length == rhsElement.length,
                      lhsElement.matches(rhsElement, ignoredTypes: &ignoredTypes),
                      Element.optionalList(lhsElement.before, isEqualTo: rhsElement.before, ignoredTypes: &ignoredTypes) else {
                    return false
                }
                lhs = lhsElement.after
                rhs = rhsElement.after
            }
            return lhs == nil && rhs == nil
        }

        private func matches(_ other: Element, ignoredTypes: inout Set<ObjectIdentifier>) -> Bool {
            guard keyType == other.keyType else { return false }
            let typeID = ObjectIdentifier(keyType)
            if ignoredTypes.contains(typeID) {
                return true
            }
            guard isValueEqual(to: other) else { return false }
            ignoredTypes.insert(typeID)
            return true
        }

        private static func optionalList(
            _ lhs: Element?,
            isEqualTo rhs: Element?,
            ignoredTypes: inout Set<ObjectIdentifier>
        ) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil):
                return true
            case let (lhs?, rhs?):
                return lhs.isListEqual(to: rhs, ignoredTypes: &ignoredTypes)
            default:
                return false
            }
        }

        func visitValue<Value>(ofType valueType: Value.Type,
                               _ body: (any PropertyKey.Type, Value) -> Bool) -> Bool {
            false
        }
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

        override func isValueEqual(to other: Element) -> Bool {
            guard let other = other as? TypedElement<T> else { return false }
            return T.valuesEqual(value, other.value)
        }

        override func visitValue<Value>(ofType valueType: Value.Type,
                                        _ body: (any PropertyKey.Type, Value) -> Bool) -> Bool {
            guard let typedValue = value as? Value else { return false }
            return body(T.self, typedValue)
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
