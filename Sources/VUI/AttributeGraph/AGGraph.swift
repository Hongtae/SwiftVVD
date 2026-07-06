//
//  File: AGGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

// Single-threaded design: no internal synchronization.
// The caller is responsible for ensuring that all operations on a given
// _AGGraph instance occur on a single thread (or equivalent serial context).
//
// All methods on _AGGraph require that _AGGraph.current is already bound
// to this instance (via _AGGraph.withCurrent(self) { ... }) before
// they are called. Violating this precondition causes a runtime assertion failure.
// The unchecked Sendable conformance is not a thread-safety guarantee.

final class _AGGraph: @unchecked Sendable {
    // MARK: Node Storage

    // Describes how a node computes its value.
    // Exactly one case is active per node. Mutual exclusion is guaranteed at the type level.
    enum NodeKind {
        // Source-of-truth node. Value is written externally via setValue(_:).
        case input

        // Computed node with a plain closure rule.
        // isSideEffect = true -> re-evaluated eagerly inside markNeedsEvaluation
        //   (i.e. synchronously when any input changes via setValue).
        //   Used for gesture callbacks and other fire-and-forget side effects.
        // isSideEffect = false -> pull-based, evaluated lazily on first .value read.
        //
        // Cascade example (gesture callbacks):
        //   eventsAttr.setValue(events)
        //     -> markNeedsEvaluation(eventRule)   [isSideEffect]
        //       -> evaluateNode(eventRule)          immediately
        //         -> recognizer.processEvents()
        //         -> phaseAttr.setValue(.ended)
        //           -> markNeedsEvaluation(callbackRule) [isSideEffect]
        //             -> evaluateNode(callbackRule)       immediately
        //               -> endedCallback() fires here, inside setValue call stack
        case rule(() -> Any, isSideEffect: Bool)

        // StatefulRule node. The box owns the rule struct and is reused across evaluations.
        // Output is written by calling _AGGraph.setStatefulOutput(_:) inside updateValue().
        // If setStatefulOutput is not called during a given evaluation, the previous value is kept.
        // The box receives destroy() once before node removal so stateful rules can release
        // pending deferred work associated with the node's lifetime.
        case stateful(any _AnyStatefulBox)

        // KeyPath-derived node. Value is projected from a parent node via a key path.
        // The dependency on parent is fixed at creation time and never changes.
        case keyPath(parent: AGAttribute, kp: AnyKeyPath)

        // Cross-graph mirror node. It reads its cached value from a node in another _AGGraph.
        // Evaluated lazily via cachedValue(for:) on the source graph (no context switch needed).
        // Invalidated reactively: when the source node changes, the source graph enqueues a
        // markNeedsEvaluation call into this graph's inbox. This graph drains the inbox at
        // the start of each withCurrent block (e.g. GestureGraph.sendEvents).
        case crossGraphRef(sourceAttr: AGAttribute, sourceGraph: WeakObject<_AGGraph>)

        // Indirect (pointer) node. It forwards reads to `target` when set and returns
        // the stored default value when target is nil.
        // Used for placeholder view outputs (_ViewOutputs), preference placeholders, and
        // per-child posAttr/sizeAttr in the static layout path.
        case indirect(target: AGAttribute?)

        var isSideEffect: Bool {
            if case .rule(_, let se) = self { return se }
            return false
        }
    }

    struct Node {
        var value: Any?
        var transaction: Transaction? = nil
        var kind: NodeKind
        var needsEvaluation: Bool = true
        var inputsChanged: Bool = true
        var changedInputs: Set<UInt32> = []
        var isEvaluating: Bool = false  // for cycle detection

        // Dependency graph edges (stored as raw slot indices)
        var inputs: Set<UInt32> = []        // nodes this node depends on
        var outputs: Set<UInt32> = []       // nodes that depend on this node
        // Permanent deps registered via setIndirectDependency. They are never cleared on re-evaluation.
        var staticInputs: Set<UInt32> = []
    }

    struct NodeSlot {
        var seed: UInt32    // generation counter incremented on each removal
        var node: Node?     // nil = free slot
    }

    struct RelativePath: Hashable {
        let parentID: UInt32
        let keyPath: AnyKeyPath

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.parentID == rhs.parentID && lhs.keyPath == rhs.keyPath
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(parentID)
            hasher.combine(keyPath)
        }
    }

    // Contiguous slot array: index == AGAttribute.rawValue
    var slots: ContiguousArray<NodeSlot> = []
    // Freed slot indices available for reuse
    var freeList: [UInt32] = []
    // Cache for KeyPath-derived child nodes
    var pathIDs: [RelativePath: UInt32] = [:]
#if DEBUG
    var removedNodeTombstones: [UInt32: RemovedNodeTombstone] = [:]
    var removedNodeTombstoneOrder: [UInt32] = []
    let removedNodeTombstoneLimit = 4096
#endif

    // MARK: Stored Properties

    // Thread-safe bridge for scheduling AG invalidations from arbitrary threads.
    let inbox: AGInbox = AGInbox()

    // Cross-graph observer registry.
    // When a crossGraphRef node in another graph mirrors a node in this graph, an entry is
    // registered here. On every setValue / markNeedsEvaluation for that source node, the
    // target graph is notified via its inbox so that it can invalidate the mirror node when
    // it next enters an AG context (e.g. GestureGraph.sendEvents -> data.withCurrent).
    struct CrossGraphObserver {
        weak var targetGraph: _AGGraph?
        var targetNodeID: UInt32
    }
    var crossGraphObservers: [UInt32: [CrossGraphObserver]] = [:]

    // Deferred action outbox: closures to be executed OUTSIDE AG evaluation context.
    // Enqueue from within AG evaluation. WindowController drains after all AG work is done.
    var actionOutbox: [() -> Void] = []

    func drainActionOutbox() {
        while !actionOutbox.isEmpty {
            let actions = actionOutbox
            actionOutbox.removeAll()
            actions.forEach { $0() }
        }
    }

    var updateCounter: UInt = 0

    // Closures enqueued here are executed during drainActions().
    // Use enqueue() from button handlers or event callbacks to defer state mutations
    // to the appropriate point in the frame loop.
    var pendingActions: [() -> Void] = []

    // MARK: Thread Locals

    typealias ChangeSet = _AGChangeSet

    private static let currentStorage = _AGThreadLocal<_AGGraph?>(nil)
    private static let changeSetStorage = _AGThreadLocal<ChangeSet?>(nil)
    private static let currentlyEvaluatingNodeStorage = _AGThreadLocal<AGAttribute?>(nil)
    private static let currentlyUpdatingGraphsStorage = _AGThreadLocal<Set<ObjectIdentifier>?>(nil)

    static var changeSet: ChangeSet? {
        changeSetStorage.value
    }

    static var currentlyEvaluatingNode: AGAttribute? {
        currentlyEvaluatingNodeStorage.value
    }

    static var currentlyUpdatingGraphs: Set<ObjectIdentifier>? {
        currentlyUpdatingGraphsStorage.value
    }

    init() {}

#if DEBUG
    private let debugExecutionState = Mutex(AGExecutionState())
#endif
}

extension _AGGraph {
    static var current: _AGGraph? {
        guard let graph = currentStorage.value else { return nil }
#if DEBUG
        graph._debugValidateCurrentContext()
#endif
        return graph
    }

    // Binds the raw graph. DEBUG builds also validate nested binding ownership.
    static func withCurrent<R>(_ graph: _AGGraph, _ body: () throws -> R) rethrows -> R {
#if DEBUG
        return try graph._debugWithCurrentExecutionContext {
            try _AGGraph.currentStorage.withValue(graph) {
                try body()
            }
        }
#else
        return try _AGGraph.currentStorage.withValue(graph) {
            try body()
        }
#endif
    }

    static func withChangeSet<R>(_ changeSet: ChangeSet?, _ body: () throws -> R) rethrows -> R {
        try changeSetStorage.withValue(changeSet) {
            try body()
        }
    }

    static func withCurrentlyEvaluatingNode<R>(_ attribute: AGAttribute?, _ body: () throws -> R) rethrows -> R {
        try currentlyEvaluatingNodeStorage.withValue(attribute) {
            try body()
        }
    }

    static func withCurrentlyUpdatingGraphs<R>(_ graphs: Set<ObjectIdentifier>?, _ body: () throws -> R) rethrows -> R {
        try currentlyUpdatingGraphsStorage.withValue(graphs) {
            try body()
        }
    }

    static func compareValues<Value>(_ lhs: Value, _ rhs: Value, options: AGComparisonOptions) -> Bool {
        _ = options
        if let lhs = lhs as? String,
           let rhs = rhs as? String {
            return lhs == rhs
        }
        return withUnsafeBytes(of: lhs) { lhsBytes in
            withUnsafeBytes(of: rhs) { rhsBytes in
                lhsBytes.elementsEqual(rhsBytes)
            }
        }
    }
}

#if DEBUG
extension _AGGraph {
    // Reference identity for one active graph-current binding generation.
    private final class AGExecutionToken: @unchecked Sendable {}

    // Stored on the graph so different thread-local bindings contend on one state.
    private struct AGExecutionState {
        var token: AGExecutionToken?
        var depth: Int = 0
        var threadID: Platform.ThreadID?
    }

    private func _debugWithCurrentExecutionContext<R>(_ body: () throws -> R) rethrows -> R {
        let token = _debugEnterCurrentContext()
        defer { _debugLeaveCurrentContext(token) }

        return try body()
    }

    // Allows same-thread re-entry, but rejects independent concurrent binding.
    private func _debugEnterCurrentContext() -> AGExecutionToken {
        let threadID = Platform.currentThreadID()
        return debugExecutionState.withLock { state in
            if let activeToken = state.token {
                guard state.threadID == threadID else {
                    fatalError("_AGGraph entered outside its active thread-local execution context.")
                }
                state.depth += 1
                return activeToken
            }

            let token = AGExecutionToken()
            state.token = token
            state.depth = 1
            state.threadID = threadID
            return token
        }
    }

    // Balances re-entry depth and retires the token at the outermost exit.
    private func _debugLeaveCurrentContext(_ token: AGExecutionToken) {
        debugExecutionState.withLock { state in
            guard state.token === token, state.depth > 0 else {
                fatalError("_AGGraph execution context state is corrupted.")
            }
            state.depth -= 1
            if state.depth == 0 {
                state.token = nil
                state.threadID = nil
            }
        }
    }

    private func _debugValidateCurrentContext() {
        let threadID = Platform.currentThreadID()
        debugExecutionState.withLock { state in
            guard state.token != nil, state.depth > 0, state.threadID == threadID else {
                fatalError("_AGGraph.current used outside its active thread-local execution context.")
            }
        }
    }
}
#endif
