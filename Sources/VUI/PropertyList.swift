//
//  File: PropertyList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

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

extension Stack: Equatable where Element: Equatable {}

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

// Property-list element identity uses _AGGraph's unique-ID allocator.
struct UniqueID: Hashable, Sendable, CustomStringConvertible {
    let value: UInt32

    init() {
        value = UInt32(truncatingIfNeeded: AGMakeUniqueID())
    }

    init(value: UInt32) {
        self.value = value
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

    func isEqual(
        to other: PropertyList,
        ignoring ignoredTypes: [ObjectIdentifier]
    ) -> Bool {
        // Ignored keys are compared by their GraphReusable witnesses after
        // the remaining property-list structure has matched.
        switch (elements, other.elements) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            var ignoredTypes = Set(ignoredTypes)
            return lhs.isListEqual(
                to: rhs,
                ignoredTypes: &ignoredTypes
            )
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
            if let value: T.Value = current.before?.nonDefaultValue(forKey: key) {
                return value
            }
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
        return elements?.forEachValue(ofType: valueType, seenKeys: &seenKeys, body) ?? false
    }

    func forEachValue<T: PropertyKey>(forKey key: T.Type,
                                      _ body: (T.Value, inout Bool) -> Void) {
        var stop = false
        elements?.forEachValue(forKey: key, stop: &stop, body)
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

private final class AtomicBuffer<Value> {
    private let storage: Mutex<UnsafeBox<Value>>

    init(_ value: Value) {
        self.storage = Mutex(UnsafeBox(value))
    }

    func read<Result>(_ body: (Value) throws -> Result) rethrows -> Result {
        let snapshot = storage.withLock { box in
            box.value
        }
        return try body(snapshot)
    }

    func update<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try storage.withLock { box in
            var value = box.value
            defer { box = UnsafeBox(value) }
            return try body(&value)
        }
    }

    func updateWithLockedSource<Result>(
        _ source: AtomicBuffer<Value>,
        _ body: (Value, inout Value) throws -> Result
    ) rethrows -> Result {
        if source === self {
            return try update { value in
                let snapshot = value
                return try body(snapshot, &value)
            }
        }

        return try source.storage.withLock { sourceBox in
            return try storage.withLock { box in
                var value = box.value
                defer { box = UnsafeBox(value) }
                return try body(sourceBox.value, &value)
            }
        }
    }
}

final class _PropertyListTracker {
    private struct TrackerData {
        var trackedID: UniqueID?
        var trackedValues: [ObjectIdentifier: any _AnyTrackedValue] = [:]
        var derivedValues: [ObjectIdentifier: any _AnyTrackedValue] = [:]
        var pendingValues: [any _AnyTrackedValue] = []
        var dirty = false

        mutating func reset() {
            trackedID = nil
            trackedValues.removeAll()
            derivedValues.removeAll()
            pendingValues.removeAll()
            dirty = false
        }

        mutating func initializeValues(from plist: PropertyList) {
            trackedID = plist.id
        }

        mutating func value<K: PropertyKey>(_ plist: PropertyList, for key: K.Type) -> K.Value {
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

        mutating func derivedValue<K: DerivedPropertyKey>(
            _ plist: PropertyList,
            for key: K.Type
        ) -> K.Value {
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

        mutating func valueWithSecondaryLookup<K: PropertyKeyLookup>(
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

        mutating func invalidateAllValues(from: PropertyList, to: PropertyList) {
            guard trackedID == from.id, trackedID != to.id else { return }
            pendingValues.append(contentsOf: trackedValues.values)
            pendingValues.append(contentsOf: derivedValues.values)
            trackedValues.removeAll()
            derivedValues.removeAll()
            trackedID = to.id
        }

        mutating func invalidateValue<K: PropertyKey>(for key: K.Type, from: PropertyList, to: PropertyList) {
            guard trackedID == from.id, trackedID != to.id else { return }
            if let removed = trackedValues.removeValue(forKey: ObjectIdentifier(key)) {
                pendingValues.append(removed)
            }
            pendingValues.append(contentsOf: derivedValues.values)
            derivedValues.removeAll()
            trackedID = to.id
        }

        mutating func formUnion(_ other: TrackerData) {
            guard let otherID = other.trackedID, trackedID != otherID else {
                return
            }
            if trackedID == nil {
                self = other
                return
            }
            trackedID = otherID
            trackedValues.merge(other.trackedValues) { current, _ in current }
            derivedValues.merge(other.derivedValues) { current, _ in current }
            pendingValues.append(contentsOf: other.pendingValues)
            dirty = dirty || other.dirty
        }
    }

    private let data = AtomicBuffer(TrackerData())

    func reset() {
        data.update { $0.reset() }
    }

    func initializeValues(from plist: PropertyList) {
        data.update { $0.initializeValues(from: plist) }
    }

    func value<K: PropertyKey>(_ plist: PropertyList, for key: K.Type) -> K.Value {
        data.update { $0.value(plist, for: key) }
    }

    func derivedValue<K: DerivedPropertyKey>(_ plist: PropertyList, for key: K.Type) -> K.Value {
        data.update { $0.derivedValue(plist, for: key) }
    }

    func valueWithSecondaryLookup<K: PropertyKeyLookup>(
        _ plist: PropertyList,
        secondaryLookupHandler lookup: K.Type
    ) -> K.Primary.Value {
        data.update { $0.valueWithSecondaryLookup(plist, secondaryLookupHandler: lookup) }
    }

    func hasDifferentUsedValues(_ plist: PropertyList) -> Bool {
        data.read { $0.hasDifferentUsedValues(plist) }
    }

    func invalidateAllValues(from: PropertyList, to: PropertyList) {
        data.update { $0.invalidateAllValues(from: from, to: to) }
    }

    func invalidateValue<K: PropertyKey>(for key: K.Type, from: PropertyList, to: PropertyList) {
        data.update { $0.invalidateValue(for: key, from: from, to: to) }
    }

    func formUnion(_ other: _PropertyListTracker) {
        data.updateWithLockedSource(other.data) { otherData, data in
            data.formUnion(otherData)
        }
    }
}

extension PropertyList {
    typealias Tracker = _PropertyListTracker
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
            if let value = current.before?.findValueWithSecondaryLookup(lookup) {
                return value
            }
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

        // Rebuild this node as a merge head with a higher-priority before chain.
        func rebuilt(before: Element?) -> Element { fatalError("TypedElement must override rebuilt(before:)") }

        func isValueEqual(to other: Element) -> Bool { false }

        func isListEqual(to other: Element) -> Bool {
            var ignoredTypes = Set<ObjectIdentifier>()
            return isListEqual(to: other, ignoredTypes: &ignoredTypes)
        }

        fileprivate func isListEqual(
            to other: Element,
            ignoredTypes: inout Set<ObjectIdentifier>
        ) -> Bool {
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

        func forEachValue<Value>(
            ofType valueType: Value.Type,
            seenKeys: inout Set<ObjectIdentifier>,
            _ body: (any PropertyKey.Type, Value) -> Bool
        ) -> Bool {
            var element: Element? = self
            while let current = element {
                // The before chain has higher lookup priority than the current
                // node. Visit it first so shadowed fallback values stay hidden.
                if current.before?.forEachValue(
                    ofType: valueType,
                    seenKeys: &seenKeys,
                    body
                ) == true {
                    return true
                }

                let keyID = ObjectIdentifier(current.keyType)
                if seenKeys.insert(keyID).inserted,
                   current.visitValue(ofType: valueType, body) {
                    return true
                }
                element = current.after
            }
            return false
        }

        func forEachValue<T: PropertyKey>(
            forKey key: T.Type,
            stop: inout Bool,
            _ body: (T.Value, inout Bool) -> Void
        ) {
            var element: Element? = self
            while let current = element, !stop {
                current.before?.forEachValue(
                    forKey: key,
                    stop: &stop,
                    body
                )
                if stop {
                    return
                }
                if current.keyType == key {
                    body((current as! TypedElement<T>).value, &stop)
                }
                element = current.after
            }
        }

        func nonDefaultValue<T: PropertyKey>(forKey key: T.Type) -> T.Value? {
            var element: Element? = self
            while let current = element {
                if let value: T.Value = current.before?.nonDefaultValue(forKey: key) {
                    return value
                }
                if current.keyType == key {
                    return (current as! TypedElement<T>).value
                }
                if !current.skipFilter.mightContain(key) { return nil }
                element = current.after
            }
            return nil
        }

        func findValueWithSecondaryLookup<K: PropertyKeyLookup>(_ lookup: K.Type) -> K.Primary.Value? {
            var element: Element? = self
            while let current = element {
                if let value = current.before?.findValueWithSecondaryLookup(lookup) {
                    return value
                }
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

        func containsIdenticalTail(_ tail: Element?) -> Bool {
            guard let tail else { return true }
            var element: Element? = self
            while let current = element {
                if current === tail {
                    return true
                }
                element = current.after
            }
            return false
        }
    }

    // Typed subclass — value is stored with the concrete Value type rather than Any.
    final class TypedElement<T: PropertyKey>: Element {
        var value: T.Value

        init(key: T.Type, value: T.Value, before: Element? = nil, after: Element? = nil) {
            self.value = value
            super.init(keyType: key, before: before, after: after)
        }

        override var valueDescription: String { "\(value)" }

        override func rebuilt(before: Element?) -> Element {
            TypedElement<T>(key: T.self, value: value, before: before, after: after)
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
        if elements!.containsIdenticalTail(other.elements) {
            return
        }
        elements = other.elements!.rebuilt(before: elements)
    }

    init<Key: PropertyKey>(_ key: Key.Type, value: Key.Value) {
        self.elements = TypedElement(key: key, value: value)
    }
}
