//
//  File: Graph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

protocol CustomInput {
}

public struct _Graph {
}

protocol _GraphInputResolve {
    var isResolved: Bool { get }
    func apply(inputs: inout _GraphInputs)
    mutating func resolve<T>(encloser: T, graph: _GraphValue<T>)
}

public struct _GraphInputs {
    struct Options : OptionSet {
        let rawValue: Int
        static var none = Options(rawValue: 0)
    }

    var customInputs: [CustomInput] = []
    var properties: PropertyList = .init()
    var environment: EnvironmentValues
    var sharedContext: SharedContext
    var options: Options = .none
    var mergedInputs: [_GraphInputs] = []
    var modifiers: [_GraphInputResolve] = []
}

extension _GraphInputs {
    func resolveMergedInputs() -> _GraphInputs {
        if self.mergedInputs.isEmpty {
            return self
        }
        var mergedInputs = self.mergedInputs
        mergedInputs.indices.forEach { index in
            mergedInputs[index] = mergedInputs[index].resolveMergedInputs()
        }
        var inputs = self
        mergedInputs.forEach {
            inputs.environment.values.merge($0.environment.values) { $1 }
            inputs.modifiers.append(contentsOf: $0.modifiers)
        }
        inputs.mergedInputs = []
        return inputs
    }
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

    var viewList: any ViewListGenerator
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

    func trackRelativeGraphs<U>(to dest: _GraphValue<U>, _ callback: (_GraphValue<Any>)->Void) -> Bool {
        guard self.root === dest.root
        else { return false }

        var pathIndices: [Int] = []
        var idx = dest.index
        if idx == self.index { return true }
        while idx >= 0 {
            let rp = root.paths[idx]
            pathIndices.append(idx)
            idx = rp.parent
            if idx == self.index { break }
        }
        if idx >= 0 {
            pathIndices.reversed().forEach { index in
                callback(_GraphValue<Any>(self.root, index))
            }
            return true
        }
        return false
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
    public static func == <U>(lhs: Self, rhs: _GraphValue<U>) -> Bool {
        lhs == rhs.unsafeCast(to: Value.self)
    }
}
