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

protocol _GraphInputResolve : Equatable {
    var isResolved: Bool { get }
    func apply(inputs: inout _GraphInputs)
    mutating func resolve<T>(encloser: T, graph: _GraphValue<T>)
}

extension _GraphInputResolve {
    func isEqual(to: any _GraphInputResolve) -> Bool {
        if let other = to as? Self {
            return self == other
        }
        return false
    }
}

struct ViewStyles {
    var foregroundStyle: (primary: AnyShapeStyle?,
                          secondary: AnyShapeStyle?,
                          tertiary: AnyShapeStyle?) = (nil, nil, nil)
}

protocol ViewStyleModifier : Equatable {
    var isResolved: Bool { get }
    func apply(to style: inout ViewStyles)
    mutating func resolve<T>(encloser: T, graph: _GraphValue<T>)
}

extension ViewStyleModifier {
    func isEqual(to: any ViewStyleModifier) -> Bool {
        if let other = to as? Self {
            return self == other
        }
        return false
    }
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
    var modifiers: [any _GraphInputResolve] = []
    var viewStyleModifiers: [any ViewStyleModifier] = []
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
            $0.modifiers.forEach { modifier in
                if inputs.modifiers.contains(where: { modifier.isEqual(to: $0) }) == false {
                    inputs.modifiers.append(modifier)
                }
            }
            $0.viewStyleModifiers.forEach { modifier in
                if inputs.viewStyleModifiers.contains(where: { modifier.isEqual(to: $0) }) == false {
                    inputs.viewStyleModifiers.append(modifier)
                }
            }
        }
        inputs.mergedInputs = []
        return inputs
    }
}

protocol AnyPreferenceKey {
}

struct LayoutInputs {
    var modifierViews: [ObjectIdentifier: (_Graph, _ViewInputs)->_ViewOutputs] = [:]
    var modifierViewLists: [ObjectIdentifier: (_Graph, _ViewListInputs)->_ViewListOutputs] = [:]

    var sourceWrites: [ObjectIdentifier: any ViewGenerator] = [:]

    var labelStyles: [any LabelStyle] = []
    var buttonStyles: [any PrimitiveButtonStyle] = []
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
    var layouts: LayoutInputs
    var preferences: PreferenceInputs = PreferenceInputs(preferences: [])
    var traits: ViewTraitKeys = ViewTraitKeys()

    var listInputs: _ViewListInputs {
        _ViewListInputs(base: self.base,
                        layouts: self.layouts,
                        preferences: self.preferences,
                        traits: self.traits)
    }

    static func inputs(with base: _GraphInputs) -> _ViewInputs {
        _ViewInputs(base: base,
                    layouts: LayoutInputs(),
                    preferences: PreferenceInputs(preferences: []),
                    traits: ViewTraitKeys())
    }
}

public struct _ViewOutputs {
    var view: (any ViewGenerator)?
    var preferences: PreferenceOutputs = PreferenceOutputs(preferences: [])
}

public struct _ViewListInputs {
    struct Options : OptionSet {
        let rawValue: Int
        static var none = Options(rawValue: 0)
    }

    var base: _GraphInputs
    var layouts: LayoutInputs
    var preferences: PreferenceInputs = PreferenceInputs(preferences: [])
    var traits: ViewTraitKeys = ViewTraitKeys()
    var options: Options = .none

    var inputs: _ViewInputs {
        _ViewInputs(base: self.base,
                    layouts: self.layouts,
                    preferences: self.preferences,
                    traits: self.traits)
    }
}

public struct _ViewListOutputs {
    struct Options : OptionSet {
        let rawValue: Int
        static var none = Options(rawValue: 0)
    }

    var viewList: any ViewListGenerator
    var preferences: PreferenceOutputs = PreferenceOutputs(preferences: [])
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

    var valueType: Value.Type {
        if let t = type(of: keyPath).valueType as? Value.Type {
            return t
        }
        fatalError("Invalid type!")
    }

    var parent: _GraphValue<Any>? {
        if self.index > 0 {
            let rp = root.paths[self.index]
            return _GraphValue<Any>(self.root, rp.parent)
        }
        return nil
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

extension _GraphValue {
    func nearestAncestor<T>(_ path: _GraphValue<T>?) -> _GraphValue<Any>? {
        var graph = self.unsafeCast(to: Any.self)
        if let path {
            while path.isDescendant(of: graph) == false {
                if let _graph = graph.parent {
                    graph = _graph
                } else {
                    return nil
                }
            }
        }
        return graph
    }

#if swift(>=6.0)
    func nearestCommonAncestor<each T>(_ path: repeat _GraphValue<each T>?) -> _GraphValue<Any>? {
        var graph = self.unsafeCast(to: Any.self)
        repeat if let _graph = graph.nearestAncestor(each path) {
            graph = _graph
        } else { return nil }
        return graph
    }
#else
    func nearestCommonAncestor<T, U>(_ path1: _GraphValue<T>?, _ path2: _GraphValue<U>?) -> _GraphValue<Any>? {
        if path1 == nil { return nearestAncestor(path2) }
        if path2 == nil { return nearestAncestor(path1) }
        var graph = self.unsafeCast(to: Any.self)
        if let path1, let path2 {
            while path1.isDescendant(of: graph) == false || path2.isDescendant(of: graph) == false {
                if let _graph = graph.parent {
                    graph = _graph
                } else {
                    return nil
                }
            }
        }
        return graph
    }
#endif
}

extension _GraphValue : Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.root === rhs.root
    }
    public static func == <U>(lhs: Self, rhs: _GraphValue<U>) -> Bool {
        lhs == rhs.unsafeCast(to: Value.self)
    }
}

extension _GraphValue : CustomDebugStringConvertible {
    public var debugDescription: String {
        self.keyPath.debugDescription
    }
}