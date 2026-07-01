//
//  File: AttributeGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Synchronization

struct AGComparisonOptions: RawRepresentable, Equatable, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

func _AGCompareValues<Value>(_ lhs: Value, _ rhs: Value, options: AGComparisonOptions) -> Bool {
    _AGGraph.compareValues(lhs, rhs, options: options)
}

func _AGGraphAnyInputsChanged() -> Bool {
    _AGGraph._currentStatefulInputsChanged()
}

// MARK: - _AGGraphContext
// Reference wrapper used to bind an _AGGraph to a host context.
//
// Multiple _AGGraphContext instances can share the same underlying _AGGraph core.
// Each GraphHost subclass (ViewGraph, GestureGraph) owns one _AGGraphContext and registers
// itself as the `context`, enabling `GestureGraph.current` / `ViewGraph.current` resolution
// via the AG evaluation context.
//
// Usage:
//   let ref = _AGGraphContext(graph: sharedCore)
//   ref.context = self   // register this GraphHost as the context
struct _AGGraphContext: @unchecked Sendable {
    let graph: _AGGraph       // shared graph core (one per window)
    weak var context: AnyObject?    // the GraphHost that owns this ref (ViewGraph, GestureGraph, ...)

    /// The currently active _AGGraphContext for the running AG evaluation pass.
    /// Set by withCurrent(_:). Reading context gives the owning GraphHost subclass.
    @TaskLocal static var current: _AGGraphContext? = nil

    init(graph: _AGGraph, context: AnyObject? = nil) {
        self.graph = graph
        self.context = context
    }

    /// Establishes both _AGGraphContext.current (self) and _AGGraph.current (self.graph)
    /// for the duration of the closure. This is the canonical way to enter a GraphHost's AG context.
    func withCurrent<R>(_ body: () throws -> R) rethrows -> R {
        if let activeGraph = _AGGraph.current, activeGraph !== graph {
            // Dependency tracking is graph-local. Cross-graph re-entry must not
            // inherit the outer graph's currently evaluating node.
            return try _AGGraph.withoutTracking {
                try withCurrentBinding(body)
            }
        }
        return try withCurrentBinding(body)
    }

    private func withCurrentBinding<R>(_ body: () throws -> R) rethrows -> R {
        return try _AGGraphContext.$current.withValue(self) {
            try _AGGraph.withCurrent(graph) {
                try body()
            }
        }
    }
}

// MARK: - _AGChangeSet

/// Records attributes that were mutated during an `_AGGraph.$changeSet.withValue(_:)`
/// scope, partitioned by owning _AGGraph instance.
///
/// Storage is keyed by `ObjectIdentifier(graph)` so attributes from different graphs
/// never share a `Set<AGAttribute>` bucket. Without this partitioning, a hash collision
/// between equal `rawValue`s in different graphs would invoke cross-graph `AGAttribute.==`
/// (which is only a same-graph comparison by contract).
///
final class _AGChangeSet: @unchecked Sendable {
    private var _byGraph: [ObjectIdentifier: Set<AGAttribute>] = [:]

    var isEmpty: Bool { _byGraph.values.allSatisfy { $0.isEmpty } }

    /// Attributes recorded for a specific graph during this _AGChangeSet's lifetime.
    func ids(for graph: _AGGraph) -> Set<AGAttribute> {
        _byGraph[ObjectIdentifier(graph)] ?? []
    }

    func record(_ id: AGAttribute) {
        guard let graph = _AGGraph.current else {
            fatalError("_AGChangeSet.record called outside an active _AGGraph context.")
        }
        _byGraph[ObjectIdentifier(graph), default: []].insert(id)
    }
}

// MARK: - AGMakeUniqueID

// Global unique ID counter used by Namespace and other AG-backed identities.
// Atomic fetch-add returns the previous value. The counter starts at 1 so callers
// never receive 0, which is reserved as the uninitialized namespace value.
private let _agUniqueIDCounter: Atomic<Int> = Atomic(1)

func AGMakeUniqueID() -> Int {
    let (old, _) = _agUniqueIDCounter.add(1, ordering: .relaxed)
    return old
}
