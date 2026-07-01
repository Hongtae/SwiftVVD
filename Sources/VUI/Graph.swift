//
//  File: Graph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Pure marker type — carries no data.
/// Passed as the first argument to ViewModifier body closures and
/// _VariadicView_ViewRoot._makeLayoutView body closures to signal
/// that the call originates from a _makeView context.
public struct _Graph {}

/// A typed cursor into the _AGGraph, pointing at the AG node for `Value`.
///
/// `_makeView` receives a `_GraphValue<Self>` for the view being constructed.
/// Use the `subscript(keyPath:)` operator to navigate to child properties —
/// each access creates (or retrieves) a KeyPath-derived child node in the graph.
///
/// `_GraphValue` is a *cursor*, not a value container:
/// - Do NOT read `.value` on it inside `_makeView` (that would pull the value eagerly).
/// - Use `Attribute<T>.value` inside rule closures instead.
public struct _GraphValue<Value> {
    let _attribute: Attribute<Value>

    init(_attribute: Attribute<Value>) {
        self._attribute = _attribute
    }

    /// Returns a child `_GraphValue` for the given KeyPath, creating an AG node if needed.
    public subscript<U>(keyPath: KeyPath<Value, U>) -> _GraphValue<U> {
        guard let graph = _AGGraph.current else {
            fatalError("_GraphValue subscript called outside an active _AGGraph context.")
        }
        let child = graph.subscriptNode(parent: _attribute, keyPath: keyPath)
        return _GraphValue<U>(_attribute: child)
    }

    /// True if this node has no KeyPath parent (i.e., it is a root input node).
    var isRoot: Bool {
        guard let graph = _AGGraph.current else {
            fatalError("_GraphValue.isRoot accessed outside an active _AGGraph context.")
        }
        return graph.parent(of: _attribute.identifier) == nil
    }

    /// Reinterprets the type parameter without touching the underlying AG node.
    /// Use only when you statically know the cast is safe
    /// (e.g. type-erased _GraphValue<Any> → concrete type).
    func unsafeCast<U>(to type: U.Type) -> _GraphValue<U> {
        _GraphValue<U>(_attribute: Attribute<U>(_attribute.identifier))
    }
}

extension _GraphValue: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs._attribute.identifier == rhs._attribute.identifier
    }
}

