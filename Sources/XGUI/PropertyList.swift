//
//  File: PropertyList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
struct PropertyList : CustomStringConvertible {

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
    func value<T>(forKeyPath keyPath: KeyPath<T, T.Item>) -> T.Item where T: PropertyItem {
        if let item = find(type: T.self) {
            return item[keyPath: keyPath]
        }
        return T.defaultValue
    }
    
    func find<T>(type: T.Type) -> T? where T: PropertyItem {
        if var list = elements {
            if let item = list.item as? T {
                return item
            }
            while let next = list.next {
                list = next
                if let item = list.item as? T {
                    return item
                }
            }
        }
        return nil
    }

    mutating func replace<T>(item: T) where T: PropertyItem {
        if self.elements?.item is T {
            let next = self.elements!.next
            self.elements = Element(item: item, next: next)
            return
        }
        var next = self.elements?.next
        var prev = self.elements
        while next != nil {
            if next!.item is T {
                prev!.next = Element(item: item, next: next!.next)
                return
            }
            prev = next
            next = next!.next
        }
        if let prev {
            prev.next = Element(item: item)
        } else {
            self.elements = Element(item: item)
        }
    }

    mutating func remove<T>(type: T.Type) where T : PropertyItem {
        if let elements, elements.item is T {
            self.elements = elements.next
            return
        }
        var next = elements?.next
        var prev = elements
        while next != nil {
            if next!.item is T {
                prev!.next = next!.next
                break
            }
            prev = next
            next = next!.next
        }
    }

    mutating func removeAll<T>(type: T.Type) where T : PropertyItem {
        func getElementNotMatching(_ element: Element?) -> Element? {
            if let element, element.item is T {
                return getElementNotMatching(element.next)
            }
            return element
        }
        let root = getElementNotMatching(elements)
        var next = root
        while next != nil {
            next!.next = getElementNotMatching(next!.next)
            next = next!.next
        }
        self.elements = root
    }
}

extension PropertyList {
    @usableFromInline
    class Tracker {
    }
}

protocol PropertyItem : TransactionKey, CustomStringConvertible {
    associatedtype Item
    static var defaultValue: Item { get }
}

extension PropertyList {
    @usableFromInline
    class Element: CustomStringConvertible {
        let item: any PropertyItem
        var next: Element?
        init(item: any PropertyItem, next: Element? = nil) {
            self.item = item
            self.next = next
        }
        @usableFromInline
        var description: String {
            let desc = item.description
            if let next {
                return "\(desc), \(next.description)"
            }
            return desc
        }
    }

    init<Item: PropertyItem>(_ item: Item) {
        self.elements = Element(item: item)
    }

    init(_ item: any PropertyItem, _ rest: (any PropertyItem)...) {
        var restElements: Element?
        rest.reversed().forEach {
            restElements = Element(item: $0, next: restElements)
        }
        self.elements = Element(item: item, next: restElements)
    }
}
