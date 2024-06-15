//
//  File: Graph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

protocol PropertyItem {
    associatedtype Item
    static var `default`: Item { get }
}

struct PropertyList {
    class Element {
        let item: any PropertyItem
        var next: Element?
        init(item: any PropertyItem, next: Element? = nil) {
            self.item = item
            self.next = next
        }
    }
    var elements: Element?
    init(_ item: (any PropertyItem)? = nil) {
        if let item {
            self.append(item)
        }
    }
    init(_ items: [any PropertyItem]) {
        self.elements = nil
        items.forEach { self.append($0) }
    }
    mutating func append(_ item: any PropertyItem) {
        if var list = elements {
            while let next = list.next {
                list = next
            }
            list.next = Element(item: item)
        } else {
            elements = Element(item: item)
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
    func find<T>(type: T.Type) -> (any PropertyItem)? where T : PropertyItem {
        if var list = elements {
            if list.item is T {
                return list.item
            }
            while let next = list.next {
                list = next
                if list.item is T {
                    return list.item
                }
            }
        }
        return nil
    }
}

protocol CustomInput {
}

public struct _Graph {
}

public struct _GraphInputs {
    struct Options : OptionSet {
        let rawValue: Int
        static var none = Options(rawValue: 0)
    }

    var customInputs: [CustomInput] = []
    var properties: PropertyList?
    var environment: EnvironmentValues
    var sharedContext: SharedContext
    var options: Options = .none
    var mergedInputs: [_GraphInputs] = []
}

protocol AnyPreferenceKey {
}

struct PreferenceInputs {
    struct KeyValue {
        let key: AnyPreferenceKey
        let value: Any
    }
    var preferences: [KeyValue]
}

struct PreferenceOutputs {
    struct KeyValue {
        let key: AnyPreferenceKey
        let value: Any
    }
    var preferences: [KeyValue]
}

struct ViewTraitKeys {
    var types: Set<ObjectIdentifier> = []
}

public struct _ViewInputs {
    var base: _GraphInputs
    var preferences: PreferenceInputs
    var traits: ViewTraitKeys = ViewTraitKeys()
}

public struct _ViewOutputs {
    var view: any ViewGenerator
    var preferences: PreferenceOutputs
}

public struct _ViewListInputs {
    struct Options : OptionSet {
        let rawValue: Int
        static var none = Options(rawValue: 0)
    }

    var base: _GraphInputs
    var preferences: PreferenceInputs
    var traits: ViewTraitKeys = ViewTraitKeys()
    var options: Options = .none
}

public struct _ViewListOutputs {
    struct Options : OptionSet {
        let rawValue: Int
        static var none = Options(rawValue: 0)
    }

    var view: any ViewGenerator
    var preferences: PreferenceOutputs
    var options: Options = .none
}

protocol _GraphPath {
    var keyPath: AnyKeyPath { get }
}

private class _GraphFamily {
    struct RelativePath: Hashable {
        let keyPath: AnyKeyPath
        let parent: Int
    }

    var pathIndices: [RelativePath: Int]
    var paths: [RelativePath]
    init(root: AnyKeyPath) {
        let path = RelativePath(keyPath: root, parent: -1)
        paths = [path]
        pathIndices = [path: 0]
    }
}

public struct _GraphValue<Value> : _GraphPath {
    private let family: _GraphFamily
    let index: Int

    private init(_ family: _GraphFamily, _ index: Int) {
        assert(index >= 0)
        self.family = family
        self.index = index
    }

    static func root() -> _GraphValue<Value> {
        _GraphValue(_GraphFamily(root: \Value.self), 0)
    }

    var keyPath: AnyKeyPath {
        family.paths[index].keyPath
    }

    func trackRelativePaths<U>(to dest: _GraphValue<U>, _ callback: (AnyKeyPath)->Void) -> Bool {
        guard self.family === dest.family
        else { return false }

        var paths: [AnyKeyPath] = []
        var idx = dest.index
        if idx == self.index { return true }
        while idx >= 0 {
            let rp = family.paths[idx]
            paths.append(rp.keyPath)
            idx = rp.parent
            if idx == self.index { break }
        }
        if idx >= 0 {
            paths.reversed().forEach {
                callback($0)
            }
            return true
        }
        return false
    }

    func unsafeCast<U>(to: U.Type) -> _GraphValue<U> {
        .init(family, index)
    }

    public subscript<U>(keyPath: KeyPath<Value, U>) -> _GraphValue<U> {
        let rp = _GraphFamily.RelativePath(keyPath: keyPath,
                                           parent: self.index)
        if let index = family.pathIndices[rp] {
            return .init(family, index)
        }
        let index = family.paths.count
        family.paths.append(rp)
        family.pathIndices[rp] = index
        return .init(family, index)
    }
}

extension _GraphValue : Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.family === rhs.family
    }
}
