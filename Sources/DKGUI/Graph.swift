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

    var _modifierBody: [ObjectIdentifier: (_Graph, _ViewInputs)->_ViewOutputs] = [:]
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

    var _modifierBody: [ObjectIdentifier: (_Graph, _ViewListInputs)->_ViewListOutputs] = [:]
}

public struct _ViewListOutputs {
    struct Options : OptionSet {
        let rawValue: Int
        static var none = Options(rawValue: 0)
    }

    var viewList: [any ViewGenerator]
    var preferences: PreferenceOutputs
    var options: Options = .none
}

private class _GraphRoot {
    struct RelativePath: Hashable {
        let keyPath: AnyKeyPath
        let parent: Int
    }

    var pathIndices: [RelativePath: Int]
    var paths: [RelativePath]
    init(_ root: AnyKeyPath) {
        let path = RelativePath(keyPath: root, parent: -1)
        paths = [path]
        pathIndices = [path: 0]
    }
}

public struct _GraphValue<Value> {
    private let root: _GraphRoot
    let index: Int

    private init(_ root: _GraphRoot, _ index: Int) {
        assert(index >= 0)
        self.root = root
        self.index = index
    }

    static func root() -> _GraphValue<Value> {
        _GraphValue(_GraphRoot(\Value.self), 0)
    }

    func isDescendant<U>(of graph: _GraphValue<U>) -> Bool {
        if graph.root === self.root {
            var idx = self.index
            if idx == graph.index {
                return true
            }
            while idx >= 0 {
                idx = self.root.paths[idx].parent
                if idx == graph.index {
                    return true
                }
            }
        }
        return false
    }

    var keyPath: AnyKeyPath {
        root.paths[index].keyPath
    }

    func trackRelativePaths<U>(to dest: _GraphValue<U>, _ callback: (AnyKeyPath)->Void) -> Bool {
        guard self.root === dest.root
        else { return false }

        var paths: [AnyKeyPath] = []
        var idx = dest.index
        if idx == self.index { return true }
        while idx >= 0 {
            let rp = root.paths[idx]
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
        .init(root, index)
    }

    func value<U>(atPath path: _GraphValue<U>, from source: Value) -> U? {
        var value: Any? = source
        let b = self.trackRelativePaths(to: path) {
            value = value[keyPath: $0]
        }
        if (b) {
            return value as? U
        }
        return nil
    }

    public subscript<U>(keyPath: KeyPath<Value, U>) -> _GraphValue<U> {
        let rp = _GraphRoot.RelativePath(keyPath: keyPath,
                                           parent: self.index)
        if let index = root.pathIndices[rp] {
            return .init(root, index)
        }
        let index = root.paths.count
        root.paths.append(rp)
        root.pathIndices[rp] = index
        return .init(root, index)
    }
}

extension _GraphValue : Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.root === rhs.root
    }
}
