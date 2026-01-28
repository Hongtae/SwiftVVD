//
//  File: Graph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

protocol CustomInput {
}

public struct _Graph {
}

protocol _GraphInputResolve: Equatable {
    var isResolved: Bool { get }
    func apply(to: inout EnvironmentValues)
    func apply(to: inout PropertyList)
    mutating func resolve(container: some _GraphValueResolver)
    mutating func reset()
}

extension _GraphInputResolve {
    func isEqual(to: any _GraphInputResolve) -> Bool {
        if let other = to as? Self {
            return self == other
        }
        return false
    }
    
    func apply(to: inout EnvironmentValues) {
    }
    
    func apply(to: inout PropertyList) {
    }
}

public struct _GraphInputs {
    struct Options: OptionSet, Sendable {
        let rawValue: Int
        static var none: Options { Options(rawValue: 0) }
    }

    var customInputs: [CustomInput] = []
    var properties: PropertyList = .init()
    var environment: EnvironmentValues
    var options: Options = .none
    var mergedInputs: [_GraphInputs] = []
    var modifiers: [any _GraphInputResolve] = []
    var _modifierTypeGraphs: [ObjectIdentifier: _GraphValue<Any>] = [:]
    var styleContext: StyleContextProxy? = nil
    var viewStyleModifiers: [any ViewStyleModifier] = []
}

extension _GraphInputs {
    func resolveMergedInputs() -> _GraphInputs {
        if self.mergedInputs.isEmpty {
            return self
        }
        let mergedInputs = self.mergedInputs.map { $0.resolveMergedInputs() }
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

    mutating func resetModifiers() {
        self.viewStyleModifiers.updateEach { $0.reset() }
        self.modifiers.updateEach { $0.reset() }
        self.mergedInputs.updateEach { $0.resetModifiers() }
    }
    
    mutating func setModifierTypeGraph<T>(_ graph: _GraphValue<T>) where T: _SceneModifier {
        _modifierTypeGraphs[ObjectIdentifier(T.self)] = graph.unsafeCast(to: Any.self)
    }
    
    func modifierTypeGraph<T>(of: T.Type) -> _GraphValue<T>? where T: _SceneModifier {
        if let graph = _modifierTypeGraphs[ObjectIdentifier(T.self)] {
            return graph.unsafeCast(to: T.self)
        }
        return nil
    }
}

protocol AnyPreferenceKey {
}

struct LayoutInputs {
    var sourceWrites: [ObjectIdentifier: ViewProxy] = [:]

    var labelStyles: [LabelStyleProxy] = []
    var buttonStyles: [PrimitiveButtonStyleProxy] = []
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

    var valueType: any Any.Type {
        type(of: keyPath).valueType
    }

    var parent: _GraphValue<Any>? {
        if self.index > 0 {
            let rp = root.paths[self.index]
            return _GraphValue<Any>(self.root, rp.parent)
        }
        return nil
    }

    var isRoot: Bool {
        self.index == 0
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

    func nearestCommonAncestor<each T>(_ path: repeat _GraphValue<each T>?) -> _GraphValue<Any>? {
        var graph = self.unsafeCast(to: Any.self)
        for _path in repeat each path {
            if let _graph = graph.nearestAncestor(_path) {
                graph = _graph
            } else {
                return nil
            }
        }
        return graph
    }
}

extension _GraphValue: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.root === rhs.root
    }
    public static func == <U>(lhs: Self, rhs: _GraphValue<U>) -> Bool {
        lhs == rhs.unsafeCast(to: Value.self)
    }
}

extension _GraphValue: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self.root))
        hasher.combine(self.index)
    }
}

extension _GraphValue: CustomDebugStringConvertible {
    public var debugDescription: String {
        self.keyPath.debugDescription
    }
}

protocol _GraphValueResolver {
    func value<T>(atPath: _GraphValue<T>) -> T?
}
