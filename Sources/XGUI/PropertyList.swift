//
//  File: PropertyList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

protocol PropertyItem : CustomStringConvertible {
    associatedtype Item
    static var `default`: Item { get }
}

struct PropertyList : CustomStringConvertible {
    class _Element {
        let item: any PropertyItem
        var next: _Element?
        init(item: any PropertyItem, next: _Element? = nil) {
            self.item = item
            self.next = next
        }
    }

    var elements: _Element?

    init(_ item: (any PropertyItem)? = nil) {
        if let item {
            self.append(item)
        }
    }

    init(_ items: (any PropertyItem)...) {
        self.elements = nil
        items.forEach { self.append($0) }
    }

    var description: String {
        if self.isEmpty {
            return "PropertyList (empty)"
        }
        var desc = "PropertyList (\(self.count) items)"
        var next = elements
        while next != nil {
            desc += "\n    \(next!.item)"
            next = next!.next
        }
        return desc
    }

    var isEmpty: Bool {
        self.elements == nil
    }

    var count: Int {
        var num = 0
        var next = elements
        if next != nil {
            num += 1
            next = next!.next
        }
        return num
    }

    mutating func append(_ item: any PropertyItem) {
        if var list = elements {
            while let next = list.next {
                list = next
            }
            list.next = _Element(item: item)
        } else {
            elements = _Element(item: item)
        }
    }

    func forEach(_ body: (any PropertyItem)->Void) {
        if var list = elements {
            body(list.item)
            while let next = list.next {
                list = next
                body(list.item)
            }
        }
    }

    func find<T>(type: T.Type) -> T? where T : PropertyItem {
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
        func getElementNotMatching(_ element: _Element?) -> _Element? {
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

    mutating func replace<T>(item: T) where T : PropertyItem {
        if self.elements?.item is T {
            let next = self.elements!.next
            self.elements = _Element(item: item, next: next)
            return
        }
        var next = self.elements?.next
        var prev = self.elements
        while next != nil {
            if next!.item is T {
                prev!.next = _Element(item: item, next: next!.next)
                return
            }
            prev = next
            next = next!.next
        }
        if let prev {
            prev.next = _Element(item: item)
        } else {
            self.elements = _Element(item: item)
        }
    }
}

extension PropertyList : Sequence {
    struct Iterator : IteratorProtocol {
       typealias Element = PropertyItem
        var element: PropertyList._Element?
       mutating func next() -> (any PropertyItem)? {
           let item = element?.item
           self.element = element?.next
           return item
       }
   }

    func makeIterator() -> Iterator {
        Iterator(element: self.elements)
    }
}
