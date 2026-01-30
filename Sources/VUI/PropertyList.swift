//
//  File: PropertyList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

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
    mutating func setValue<T: PropertyItem>(_ value: T.Item, forKey  key: T.Type) {
        self.makeUnique()
        var element = self.elements
        if var last = element {
            while let current = element {
                if current.item == key {
                    current.value = value
                    return
                }
                last = current
                element = current.next
            }
            last.next = Element(item: key, value: value)
        } else {
            self.elements = Element(item: key, value: value)
        }
    }

    mutating func setValue<T: PropertyItem>(_ value: T.Item, forKey key: T.Type) where T.Item: Equatable {
        if let item = self.nonDefaultValue(forKey: key), item == value {
            return
        }
        if value == T.defaultValue {
            self.removeValue(forKey: key)
            return
        }

        self.makeUnique()
        var element = self.elements
        if var last = element {
            while let current = element {
                if current.item == key {
                    current.value = value
                    return
                }
                last = current
                element = current.next
            }
            last.next = Element(item: key, value: value)
        } else {
            self.elements = Element(item: key, value: value)
        }
    }

    mutating func removeValue<T: PropertyItem>(forKey key: T.Type) {
        if self.nonDefaultValue(forKey: key) != nil {
            self.makeUnique()

            if let elements, elements.item is T {
                self.elements = elements.next
                return
            }
            var next = elements?.next
            var prev = elements
            while next != nil {
                if next!.item == key {
                    prev!.next = next!.next
                    break
                }
                prev = next
                next = next!.next
            }
        }
    }

    func nonDefaultValue<T: PropertyItem>(forKey key: T.Type) -> T.Item? {
        var element = self.elements
        while let current = element {
            if current.item == key {
                return (current.value as! T.Item)
            }
            element = current.next
        }
        return nil
    }

    func value<T: PropertyItem>(forKey key: T.Type) -> T.Item {
        if let value = self.nonDefaultValue(forKey: key) {
            return value
        }
        return T.defaultValue
    }

    private mutating func makeUnique() {
        if isKnownUniquelyReferenced(&self.elements) == false {
            self.elements = elements?.clone()
        }
    }
}

protocol PropertyItem: TransactionKey, CustomStringConvertible {
    associatedtype Item
    static var defaultValue: Item { get }
}

extension PropertyList {
    @usableFromInline
    class Element: CustomStringConvertible {
        let item: any PropertyItem.Type
        var value: Any
        var next: Element?
        init<T: PropertyItem>(item: T.Type, value: T.Item, next: Element? = nil) {
            self.item = item
            self.value = value
            self.next = next
        }
        @usableFromInline
        var description: String {
            let desc = "\(item):\(value)"
            if let next {
                return "\(desc), \(next.description)"
            }
            return desc
        }

        func clone() -> Element {
            func _dup<T: PropertyItem>(_ item: T.Type, value: Any, next: Element?) -> Element {
                Element(item: item, value: value as! T.Item, next: next)
            }
            return _dup(item, value: value, next: next?.clone())
        }
    }

    init<Item: PropertyItem>(_ item: Item.Type, value: Item.Item) {
        self.elements = Element(item: item, value: value)
    }
}
