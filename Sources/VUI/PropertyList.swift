//
//  File: PropertyList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

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

// Monotonic counter for PropertyList element IDs.
private nonisolated(unsafe) var _uniqueIDCounter: UInt32 = 0
struct UniqueID: Equatable, CustomStringConvertible {
    let value: UInt32
    init() {
        _uniqueIDCounter &+= 1
        value = _uniqueIDCounter
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

    @usableFromInline
    var description: String {
        if let elements {
            return "[\(elements.description)]"
        }
        return "[]"
    }
}

extension PropertyList {
    mutating func setValue<T: PropertyKey>(_ value: T.Value, forKey key: T.Type) {
        self.makeUnique()
        // Update in-place if key already exists.
        var element = self.elements
        while let current = element {
            if current.keyType == key {
                (current as! TypedElement<T>).value = value
                return
            }
            element = current.after
        }
        // Not found, prepend new element at head.
        self.prepend(TypedElement(key: key, value: value))
    }

    mutating func setValue<T: PropertyKey>(_ value: T.Value, forKey key: T.Type) where T.Value: Equatable {
        if let existing = self.nonDefaultValue(forKey: key) {
            if existing == value { return }
            if value == T.defaultValue {
                self.removeValue(forKey: key)
                return
            }
            self.makeUnique()
            var element = self.elements
            while let current = element {
                if current.keyType == key {
                    (current as! TypedElement<T>).value = value
                    return
                }
                element = current.after
            }
        } else {
            if value == T.defaultValue { return }
            self.makeUnique()
            self.prepend(TypedElement(key: key, value: value))
        }
    }

    mutating func removeValue<T: PropertyKey>(forKey key: T.Type) {
        if self.nonDefaultValue(forKey: key) != nil {
            self.makeUnique()

            if let head = self.elements, head.keyType == key {
                self.elements = head.after
                return
            }
            var next = elements?.after
            var prev = elements
            while let current = next {
                if current.keyType == key {
                    prev!.after = current.after
                    break
                }
                prev = current
                next = current.after
            }
            // BloomFilter false positives for the removed key are acceptable because
            // they cause at most one extra scan step, not incorrect results.
        }
    }

    func nonDefaultValue<T: PropertyKey>(forKey key: T.Type) -> T.Value? {
        var element = self.elements
        while let current = element {
            if current.keyType == key {
                return (current as! TypedElement<T>).value
            }
            // skipFilter covers all elements after current.
            // If key is definitely absent in the remaining chain, stop early.
            if !current.skipFilter.mightContain(key) {
                return nil
            }
            element = current.after
        }
        return nil
    }

    func value<T: PropertyKey>(forKey key: T.Type) -> T.Value {
        nonDefaultValue(forKey: key) ?? T.defaultValue
    }

    // Insert newElem at the head of the chain, updating length and skipFilter.
    // skipFilter on each node covers all elements AFTER that node.
    // Invariant: node.skipFilter = bloom(node.after.key) | node.after.skipFilter
    private mutating func prepend(_ newElem: Element) {
        let oldHead = self.elements
        newElem.after = oldHead
        newElem.length = 1 + (oldHead?.length ?? 0)
        if let oldHead {
            var filter = oldHead.skipFilter
            filter.insert(oldHead.keyType)
            newElem.skipFilter = filter
        }
        self.elements = newElem
    }

    private mutating func makeUnique() {
        if isKnownUniquelyReferenced(&self.elements) == false {
            self.elements = elements?.clone()
        }
    }
}

// Base protocol for PropertyList key types.
// PropertyKey is the root of the PropertyKey to GraphInput to ViewInput hierarchy.
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
        var before: Element?               // doubly-linked (currently unused)
        var after: Element?                // next element in chain
        var skip: Unmanaged<Element>?      // skip-list pointer (nil = not used)
        var length: UInt32                 // chain length from this node to end
        var skipCount: UInt32              // number of elements the skip pointer jumps
        var skipFilter: BloomFilter        // bloom filter covering elements after this node
        let id: UniqueID

        init(keyType: any PropertyKey.Type, after: Element? = nil) {
            self.keyType = keyType
            self.before = nil
            self.after = after
            self.skip = nil
            self.length = 1 + (after?.length ?? 0)
            self.skipCount = 0
            self.skipFilter = BloomFilter()
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

        func clone() -> Element { fatalError("TypedElement must override clone()") }
    }

    // Typed subclass stores the value with the concrete Value type rather than Any.
    final class TypedElement<T: PropertyKey>: Element {
        var value: T.Value

        init(key: T.Type, value: T.Value, after: Element? = nil) {
            self.value = value
            super.init(keyType: key, after: after)
        }

        override var valueDescription: String { "\(value)" }

        override func clone() -> Element {
            let copy = TypedElement(key: T.self, value: value, after: after?.clone())
            // skipFilter covers the same keys after cloning (structure is identical).
            copy.skipFilter = skipFilter
            copy.length = length
            copy.skipCount = skipCount
            // skip pointers reference old elements, so do not copy.
            return copy
        }
    }

    init<Key: PropertyKey>(_ key: Key.Type, value: Key.Value) {
        self.elements = TypedElement(key: key, value: value)
    }
}
