//
//  File: AGGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

final class _AGUpdateContext {
    let predecessor: _AGUpdateContext?
    var isCancelled = false

    init(predecessor: _AGUpdateContext?) {
        self.predecessor = predecessor
    }
}

protocol _AnyOffsetProjection {
    var parent: AGAttribute { get }
    var byteOffset: Int { get }
    var valueType: ObjectIdentifier { get }
    var usesOffsetCache: Bool { get }

    func publishValue(to graph: _AGGraph, for attribute: AGAttribute)
}

// Single-threaded design: no internal synchronization.
// The caller is responsible for ensuring that all operations on a given
// _AGGraph instance occur on a single thread (or equivalent serial context).
//
// Evaluation and mutation entry points require _AGGraph.current to be bound
// to this instance. Read-only and cross-graph helpers document their exceptions.
// DEBUG builds validate the binding precondition.
// The unchecked Sendable conformance is not a thread-safety guarantee.

final class _AGGraph: Equatable, @unchecked Sendable {
    private struct WeakSeedRegistry {
        var nextSeed: UInt32 = 1
        var reservedSeeds: Set<UInt32> = []
        var owners: [UInt32: WeakObject<_AGGraph>] = [:]

        mutating func reserve() -> UInt32 {
            while nextSeed == 0 || reservedSeeds.contains(nextSeed) {
                nextSeed &+= 1
            }
            let seed = nextSeed
            reservedSeeds.insert(seed)
            nextSeed &+= 1
            return seed
        }
    }

    private static let weakSeedRegistry = Mutex(WeakSeedRegistry())

    // MARK: Node Storage

    struct InputEdge {
        static let identityMask: UInt8 = 0x0d
        static let deferredUpdate: UInt8 = 0x01
        static let permanent: UInt8 = 0x04
        static let indirectSource: UInt8 = 0x08
        static let changed: UInt8 = 0x10
        static let readThisEvaluation: UInt8 = 0x20

        var attribute: UInt32
        var flags: UInt8
        var valueVersion: UInt64
    }

    // Describes how a node computes its value.
    // Exactly one case is active per node. Mutual exclusion is guaranteed at the type level.
    enum NodeKind {
        // Source-of-truth node. Value is written externally via setValue(_:).
        case input

        // Computed node with a closure rule. Side-effect rules are scheduled for
        // eager evaluation after invalidation traversal. If a graph update is
        // already active, they join its pending work. Ordinary rules are pull-based.
        case rule(any _AnyRuleClosureBox)

        // A typed Rule body retained by the node. Unlike the closure form, the
        // body can be mutated after a dependent subtree has been constructed.
        // Evaluation remains pull-based.
        case ruleBody(any _AnyRuleBox)

        // StatefulRule node. The box owns the rule struct and is reused across evaluations.
        // Output is written by calling _AGGraph.setStatefulOutput(_:) inside updateValue().
        // If setStatefulOutput is not called during a given evaluation, the previous value is kept.
        // Bodies that also conform to ObservedAttribute receive destroy() once before node
        // removal so they can release work associated with the node's lifetime.
        case stateful(any _AnyStatefulBox)

        // Low-level Attribute(body:value:flags:update:) construction.
        // The box owns a stable Swift body allocation and invokes the supplied
        // update function when the node is evaluated.
        case lowLevelBody(any _AnyLowLevelAttributeBox)

        // Byte-offset-derived node. PointerOffset is the stored-property
        // counterpart to a key-path projection.
        case offset(any _AnyOffsetProjection)

        // Untyped body-offset handle returned by raw AGAttribute.unsafeOffset.
        // It participates in dependency invalidation but has no readable value
        // or body/value metadata of its own.
        case rawOffset(parent: AGAttribute, byteOffset: Int)

        // Cross-graph proxy node. It reads a cached value from a node in another graph.
        // Evaluated lazily via cachedValue(for:) on the source graph (no context switch needed).
        // Invalidated reactively: when the source node changes, the source graph enqueues a
        // markNeedsEvaluation call into this graph's inbox. The owning graph drains the
        // inbox before its next relevant update.
        case crossGraphRef(sourceAttr: AGAttribute, sourceGraph: WeakObject<_AGGraph>)

        // Indirect (pointer) node. Source handles retain their slot generation so a
        // removed source cannot resolve to a replacement node that reuses its slot.
        // A nil retarget restores `defaultSource`, or `defaultValue` when the node
        // was created from a value rather than an attribute.
        // Used for placeholder view outputs (_ViewOutputs), preference placeholders, and
        // per-child posAttr/sizeAttr in the static layout path.
        case indirect(
            source: AGWeakAttribute,
            defaultSource: AGWeakAttribute,
            defaultValue: Any?
        )

        var isSideEffect: Bool {
            if case .rule(let box) = self { return box.isSideEffect }
            return false
        }
    }

    final class Node {
        var value: (any _AnyAGValueStorage)?
        var makeValueStorage: (Any) -> any _AnyAGValueStorage
        private var valueComparator: (
            UnsafeRawPointer,
            UnsafeRawPointer
        ) -> Bool
        var flags: AGAttributeFlags = []
        var transaction: Transaction? = nil
        var kind: NodeKind
        var needsEvaluation: Bool = true
        // Explicit invalidation bypasses input-version validation. Ordinary
        // propagation can clear needsEvaluation without running this node when
        // every input retains the version recorded during the previous run.
        var forceEvaluation: Bool = false
        // Versions advance only when the cached output changes. Each input
        // edge retains the version recorded by this node's last completed
        // evaluation.
        var valueVersion: UInt64 = 0
        // Graph-local invalidation traversal marker. This avoids allocating a
        // hash set for every source mutation while preserving one output walk
        // per node in cyclic or diamond dependency graphs.
        var invalidationTraversal: UInt64 = 0
        // Dependency validation uses an explicit graph-local update stack.
        // These fields provide cycle and duplicate-path detection without a
        // temporary hash table for every pull.
        var updateTraversal: UInt64 = 0
        var updateTraversalState: UInt8 = 0
        var inputsChanged: Bool = true
        var isEvaluating: Bool = false  // for cycle detection
        var isBeingRemoved: Bool = false

        // Input records remain sorted by raw slot index. Their flag byte owns
        // permanent, changed, and current-evaluation read state. Reverse
        // outputs append one raw slot index per input record.
        var inputs: ContiguousArray<InputEdge> = []
        var outputs: ContiguousArray<UInt32> = []

        init(
            value: (any _AnyAGValueStorage)?,
            makeValueStorage: @escaping (Any) -> any _AnyAGValueStorage,
            valuesEqual: @escaping (
                UnsafeRawPointer,
                UnsafeRawPointer
            ) -> Bool,
            kind: NodeKind,
            needsEvaluation: Bool = true,
            forceEvaluation: Bool = false
        ) {
            self.value = value
            self.makeValueStorage = makeValueStorage
            self.valueComparator = valuesEqual
            self.kind = kind
            self.needsEvaluation = needsEvaluation
            self.forceEvaluation = forceEvaluation
        }

        @inline(__always)
        func valuesEqual(
            _ lhs: any _AnyAGValueStorage,
            _ rhs: any _AnyAGValueStorage
        ) -> Bool {
            valueComparator(lhs.rawPointer, rhs.rawPointer)
        }

        @inline(__always)
        func valuesEqual(
            _ lhs: UnsafeRawPointer,
            _ rhs: UnsafeRawPointer
        ) -> Bool {
            valueComparator(lhs, rhs)
        }

        @inline(__always)
        func updateErasedValue(
            _ value: Any,
            in storage: any _AnyAGValueStorage
        ) -> _AGValueStorageUpdateResult {
            storage.updateErasedValue(value, valuesEqual: valueComparator)
        }
    }

    struct NodeSlot {
        var seed: UInt32    // generation token replaced on each removal
        var node: Node?     // nil = free slot
    }

    struct AttributeInfo {
        var valueType: Any.Type
        var body: (any _AnyAttributeBodyBox)?
    }

    struct CachedRuleKey: Hashable {
        var subgraph: ObjectIdentifier?
        var ruleHashValue: Int
        var body: AnyHashable
    }

    protocol CachedRuleEntry: AnyObject {
        var attribute: AGWeakAttribute { get }
    }

    final class TypedCachedRuleEntry<Value>: CachedRuleEntry {
        let attribute: AGWeakAttribute
        private let storage: UnsafeMutablePointer<Value>

        init(attribute: AGWeakAttribute, value: Value) {
            self.attribute = attribute
            storage = .allocate(capacity: 1)
            storage.initialize(to: value)
        }

        deinit {
            storage.deinitialize(count: 1)
            storage.deallocate()
        }

        func store(_ value: Value) {
            storage.pointee = value
        }

        var pointer: UnsafePointer<Value> {
            UnsafePointer(storage)
        }
    }

    struct RelativeOffsetPath: Hashable {
        let parentID: UInt32
        let byteOffset: Int
        let valueType: ObjectIdentifier
    }

    struct RawOffsetPath: Hashable {
        let parentID: UInt32
        let byteOffset: Int
    }

    // Contiguous slot array: index == AGAttribute.rawValue
    var slots: ContiguousArray<NodeSlot> = []
    // Freed slot indices available for reuse
    var freeList: [UInt32] = []
    // Type/body metadata is kept beside the slot map so the hot Node record
    // does not grow merely to support infrequent raw metadata queries.
    var attributeInfos: [UInt32: AttributeInfo] = [:]
    // Hashable Rule cache entries are graph-owned storage. The key keeps
    // the selected subgraph and concrete rule identity separate.
    var cachedRuleEntries: [CachedRuleKey: any CachedRuleEntry] = [:]
    // Each cached rule owns one node. Keep the inverse association so
    // subgraph teardown can remove that entry without rebuilding the entire
    // cache table for every node in the subgraph.
    var cachedRuleKeysByAttribute: [UInt32: CachedRuleKey] = [:]
    // Cache for PointerOffset-derived child nodes
    var offsetPathIDs: [RelativeOffsetPath: UInt32] = [:]
    // Cache for untyped raw body-offset handles.
    var rawOffsetPathIDs: [RawOffsetPath: UInt32] = [:]
    // Optional permanent dependency slots for typed IndirectAttribute values.
    var indirectDependencies: [UInt32: AGAttribute] = [:]
    var nodeSubgraphs: [UInt32: WeakObject<AGSubgraphRef>] = [:]
#if DEBUG
    var removedNodeTombstones: [UInt32: RemovedNodeTombstone] = [:]
    var removedNodeTombstoneOrder: [UInt32] = []
    let removedNodeTombstoneLimit = 4096
#endif

    // MARK: Stored Properties

    // New slots in one graph share its initial weak generation. Reused slots
    // receive another process-unique generation so stale eight-byte weak
    // handles cannot resolve to a different graph or a replacement node.
    let initialWeakSeed: UInt32

    // Thread-safe bridge for scheduling AG invalidations from arbitrary threads.
    let inbox: AGInbox = AGInbox()

    // The graph carries one non-owning host context pointer. Keeping the
    // unretained storage explicit avoids a graph-host retain cycle.
    var context: Unmanaged<AnyObject>?

    // Cross-graph observer registry.
    // When a cross-graph proxy observes a node in this graph, an entry is
    // registered here. On every setValue / markNeedsEvaluation for that source node, the
    // target graph is notified via its inbox so that it can invalidate the proxy node when
    // it next enters an AG context (e.g. GestureGraph.sendEvents -> data.withCurrent).
    struct CrossGraphObserver {
        weak var targetGraph: _AGGraph?
        var targetNodeID: UInt32
    }
    var crossGraphObservers: [UInt32: [CrossGraphObserver]] = [:]

    // Deferred action outbox for closures executed after node evaluation.
    var actionOutbox: [() -> Void] = []

    // Side effects created while the graph is already updating join the same
    // graph-local work list and are drained before the outer update returns.
    var pendingSideEffectEvaluations: [UInt32] = []
    var pendingSideEffectEvaluationSet: Set<UInt32> = []

    // Subgraph destruction requested by a rule is delayed until the outer
    // graph update has finished. This keeps values in the active update stack
    // alive while their dependencies reconcile ownership.
    var pendingSubgraphInvalidations: [AGSubgraphRef] = []

    // Monotonic marker used by markNeedsEvaluation's iterative graph walk.
    // A nested invalidation starts only after the current walk has finished.
    var invalidationTraversal: UInt64 = 0

    // Monotonic marker used by the dependency update stack.
    var updateTraversal: UInt64 = 0

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
    private static let currentUpdateContextStorage = _AGThreadLocal<_AGUpdateContext?>(nil)

    static var changeSet: ChangeSet? {
        changeSetStorage.value
    }

    static var currentlyEvaluatingNode: AGAttribute? {
        currentlyEvaluatingNodeStorage.value
    }

    static var currentlyUpdatingGraphs: Set<ObjectIdentifier>? {
        currentlyUpdatingGraphsStorage.value
    }

    static var currentUpdateContext: _AGUpdateContext? {
        currentUpdateContextStorage.value
    }

    init() {
        let seed = Self.weakSeedRegistry.withLock { $0.reserve() }
        initialWeakSeed = seed
        Self.weakSeedRegistry.withLock {
            $0.owners[seed] = WeakObject(self)
        }
    }

    func makeWeakSeed() -> UInt32 {
        let seed = Self.weakSeedRegistry.withLock { $0.reserve() }
        Self.weakSeedRegistry.withLock {
            $0.owners[seed] = WeakObject(self)
        }
        return seed
    }

    static func graph(for attribute: AGWeakAttribute) -> _AGGraph? {
        guard !attribute.isInvalid else { return nil }
        let graph = weakSeedRegistry.withLock { registry -> _AGGraph? in
            guard let graph = registry.owners[attribute.seed]?.value else {
                registry.owners[attribute.seed] = nil
                return nil
            }
            return graph
        }
        guard let graph,
              graph._isValid(index: attribute.identifier, seed: attribute.seed) else {
            return nil
        }
        return graph
    }

    static func == (lhs: _AGGraph, rhs: _AGGraph) -> Bool {
        lhs === rhs
    }

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

    static func withCurrentUpdateContext<R>(
        _ context: _AGUpdateContext,
        _ body: () throws -> R
    ) rethrows -> R {
        try currentUpdateContextStorage.withValue(context) {
            try body()
        }
    }

    static func cancelCurrentUpdate() {
        guard var context = currentUpdateContext else {
            fatalError("cancelCurrentUpdate called outside of an attribute update.")
        }
        while true {
            context.isCancelled = true
            guard let predecessor = context.predecessor else { break }
            context = predecessor
        }
    }

    static func currentUpdateWasCancelled() -> Bool {
        guard let context = currentUpdateContext else {
            fatalError("currentUpdateWasCancelled called outside of an attribute update.")
        }
        return context.isCancelled
    }

    static func cancelCurrentUpdateIfNeeded() -> Bool {
        guard let context = currentUpdateContext else {
            fatalError("cancelCurrentUpdateIfNeeded called outside of an attribute update.")
        }
        // Automatic deadline cancellation is not configured by this graph.
        return context.isCancelled
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
