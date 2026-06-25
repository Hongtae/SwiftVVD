//
//  File: AttributeGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// Single-threaded design: no internal synchronization.
// The caller is responsible for ensuring that all operations on a given
// AttributeGraph instance occur on a single thread (or equivalent serial context).
//
// All methods on AttributeGraph require that AttributeGraph.current is already bound
// to this instance (via AttributeGraph.$current.withValue(self) { ... }) before
// they are called. Violating this precondition causes a runtime assertion failure.

// MARK: - Protocols

/// Base protocol for all AG computed node bodies.
///
/// Marker protocol used to group computed node body types.
protocol _AttributeBody {}

/// A pure computed AG node: derives a single value from dependencies each evaluation.
/// Unlike StatefulRule, a Rule is stateless: `updateValue()` returns the value directly
/// and has no mutable stored state between evaluations.
///
/// Used for combiner nodes such as ExclusiveState, ExclusivePhase, SequenceEvents.
protocol Rule: _AttributeBody {
    associatedtype Value
    func updateValue() -> Value
}

/// An AG computed node that maintains mutable state between re-evaluations.
///
/// Unlike a plain `makeRule` closure, the conforming struct is stored inside the AG node
/// and reused on each evaluation, enabling lazy initialization and conditional output updates.
///
/// Implement `updateValue()` to recompute the output. Call `AttributeGraph.setStatefulOutput(_:)`
/// inside `updateValue()` to publish a new value. If `setStatefulOutput` is not called, the
/// previously cached output is retained unchanged.
/// Override `destroy()` to release deferred work tied to the node's lifetime.
///
/// Used by view-system filters (e.g. GestureFilter, ContentShapeResponderFilter) that own
/// a lazily-initialized responder object and update only its properties on re-evaluation.
protocol StatefulRule: _AttributeBody {
    associatedtype Value
    mutating func updateValue()
    mutating func destroy()
}

extension StatefulRule {
    mutating func destroy() {}
}

protocol RemovableAttribute: _AttributeBody {
    static func willRemove(attribute: AGAttribute)
    static func didReinsert(attribute: AGAttribute)
}

extension RemovableAttribute {
    static func willRemove(attribute: AGAttribute) {}
    static func didReinsert(attribute: AGAttribute) {}
}

private protocol _AnyStatefulBox: AnyObject {
    func callUpdate()
    func callDestroy()
    func callWillRemove(attribute: AGAttribute)
    func callDidReinsert(attribute: AGAttribute)
}

private class _StatefulBox<R: StatefulRule>: _AnyStatefulBox {
    var rule: R
    init(_ rule: R) { self.rule = rule }
    func callUpdate() { rule.updateValue() }
    func callDestroy() { rule.destroy() }
    func callWillRemove(attribute: AGAttribute) {
        guard let type = R.self as? any RemovableAttribute.Type else { return }
        type.willRemove(attribute: attribute)
    }
    func callDidReinsert(attribute: AGAttribute) {
        guard let type = R.self as? any RemovableAttribute.Type else { return }
        type.didReinsert(attribute: attribute)
    }
}

// MARK: - Core Node Types

/// The raw identifier for an AG node: an index into the graph's slot array.
struct AGAttribute: Hashable, CustomDebugStringConvertible, Sendable {
    let rawValue: UInt32
#if DEBUG
    /// The ObjectIdentifier of the AttributeGraph that owns this attribute.
    /// Set at creation time (makeInput/makeRule). Used to detect cross-graph access.
    private let _owningGraphID: ObjectIdentifier
    /// The generation seed of the slot when this strong handle was created.
    /// This catches stale strong handles when a removed slot is reused for a new node.
    private let _seedAtCreation: UInt32
    fileprivate var _debugSeedAtCreation: UInt32 { _seedAtCreation }
    fileprivate func _debugValidate() {
        guard let graph = AttributeGraph.current else {
            fatalError("AGAttribute(\(rawValue)) accessed outside an active AttributeGraph context.")
        }
        if _owningGraphID != ObjectIdentifier(graph) {
            fatalError(
                "AGAttribute(\(rawValue)) accessed from a different AttributeGraph than the one it was created in " +
                "(e.g. reading a ViewGraph attribute inside a GestureGraph rule). " +
                "Use the owning graph's cachedValue(for:) for cross-graph reads."
            )
        }
        guard graph._isValid(index: rawValue, seed: _seedAtCreation) else {
            let state = graph._debugSlotStateDescription(at: rawValue)
            fatalError(
                "AGAttribute(\(rawValue)) is stale or invalid in its owning AttributeGraph " +
                "(createdSeed=\(_seedAtCreation), \(state))."
            )
        }
    }
    init(rawValue: UInt32, owningGraph: ObjectIdentifier, seed: UInt32) {
        self.rawValue = rawValue
        self._owningGraphID = owningGraph
        self._seedAtCreation = seed
    }

    // AGAttribute.== is a same-graph comparison by contract. Cross-graph collections
    // (e.g. AGChangeSet) partition by AttributeGraph so this operator never runs across
    // graphs. The assert below is a tripwire if that invariant is ever broken.
    static func == (lhs: Self, rhs: Self) -> Bool {
        assert(lhs._owningGraphID == rhs._owningGraphID,
               "Comparing AGAttributes from different graphs.")
        return lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
#else
    fileprivate func _debugValidate() {}
#endif

    init(rawValue: UInt32) {
        self.rawValue = rawValue
        guard let graph = AttributeGraph.current else {
            fatalError("AGAttribute(\(rawValue)) created outside an active AttributeGraph context.")
        }
#if DEBUG
        self._owningGraphID = ObjectIdentifier(graph)
        guard let seed = graph._seedIfPresent(at: rawValue) else {
            fatalError("AGAttribute(\(rawValue)) created for a slot outside the current AttributeGraph.")
        }
        self._seedAtCreation = seed
#endif
    }

    var debugDescription: String {
        if let graph = AttributeGraph.current {
            return graph.debugDescription(for: self)
        }
        return "@\(rawValue)"
    }
}

/// A weak reference to an AG node.
/// Carries a seed (generation counter) to detect whether the slot at `identifier`
/// still holds the same node that was referenced when this value was created.
struct AGWeakAttribute: Hashable, Sendable {
    let identifier: UInt32
    let seed: UInt32

#if DEBUG
    private let _owningGraphID: ObjectIdentifier
    init(identifier: UInt32, seed: UInt32, owningGraph: ObjectIdentifier) {
        self.identifier = identifier
        self.seed = seed
        self._owningGraphID = owningGraph
    }
#endif

    func isValid(in graph: AttributeGraph) -> Bool {
        if graph._isValid(index: identifier, seed: seed) {
#if DEBUG
            guard _owningGraphID == ObjectIdentifier(graph) else {
                fatalError(
                    "AGWeakAttribute @\(identifier) with seed \(seed) is from a different AttributeGraph than the one it was validated against. " +
                    "This is a usage error: AGWeakAttributes must only be compared or converted to strong references within the same graph they were created from."
                )
            }
#endif
            return true
        }
        return false
    }

    func toStrong() -> AGAttribute {
#if DEBUG
        AGAttribute(rawValue: identifier, owningGraph: _owningGraphID, seed: seed)
#else
        AGAttribute(rawValue: identifier)
#endif
    }
}

/// A typed wrapper around an AGAttribute.
/// Marked @unchecked Sendable: stores only AGAttribute (a Sendable raw index).
/// Value type parameter is used only in method signatures. No Value is retained here.
struct Attribute<Value>: @unchecked Sendable {
    let identifier: AGAttribute

    fileprivate func _debugValidate() {
        identifier._debugValidate()
    }

    init(_ id: AGAttribute) {
        self.identifier = id
    }

    /// Pulls the latest value from the graph, triggering evaluation if needed,
    /// and implicitly recording a dependency if another node is currently evaluating.
    var value: Value {
        _debugValidate()
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to read an Attribute outside of an active AttributeGraph context.")
        }
        return graph.value(for: identifier) as! Value
    }

    // Primarily used for State/Input nodes to push new values.
    // Can also be used to inject an initial fallback value into a rule node
    // to resolve potential dependency cycles before it is first evaluated.
    func setValue(_ newValue: Value, transaction: Transaction = Transaction()) {
        _debugValidate()
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to write to an Attribute outside of an active AttributeGraph context.")
        }
        graph.setValue(for: self, to: newValue, transaction: transaction)
    }

    /// Creates a typed weak reference to this attribute, capturing the current generation seed.
    func asWeak() -> WeakAttribute<Value> {
        _debugValidate()
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to read an Attribute outside of an active AttributeGraph context.")
        }
#if DEBUG
        return WeakAttribute(AGWeakAttribute(identifier: identifier.rawValue,
                                             seed: graph._seed(at: identifier.rawValue),
                                             owningGraph: ObjectIdentifier(graph)))
#else
        return WeakAttribute(AGWeakAttribute(identifier: identifier.rawValue,
                                             seed: graph._seed(at: identifier.rawValue)))
#endif
    }
}

extension Attribute where Value: Equatable {
    func setValue(_ newValue: Value, transaction: Transaction = Transaction()) {
        _debugValidate()
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to write to an Attribute outside of an active AttributeGraph context.")
        }
        graph.setValue(for: self, to: newValue, transaction: transaction)
    }
}

/// Typed weak reference to an AG attribute.
/// The type parameter is used only for type-safe access via toStrong().
struct WeakAttribute<T>: Hashable, Sendable {
    let raw: AGWeakAttribute

    init(_ raw: AGWeakAttribute) { self.raw = raw }

    func isValid(in graph: AttributeGraph) -> Bool { raw.isValid(in: graph) }

    func toStrong() -> Attribute<T> { Attribute<T>(raw.toStrong()) }
}


// MARK: - Optional Attribute

/// Type-erased optional wrapper around an AG node identifier.
/// Used as the backing storage for `OptionalAttribute<T>` so that
/// `OptionalAttribute` can be stored in non-generic contexts.
struct AnyOptionalAttribute {
    let identifier: AGAttribute?

    init() { identifier = nil }
    init(_ id: AGAttribute) { identifier = id }
}

/// An optional typed reference to an AG node.
/// Used for fields that may or may not have an associated AG node
/// (e.g., `_layoutComputer`, `safeAreaInsets`, `containerSize`).
struct OptionalAttribute<Value> {
    let base: AnyOptionalAttribute

    init() { base = AnyOptionalAttribute() }
    init(_ attribute: Attribute<Value>) { base = AnyOptionalAttribute(attribute.identifier) }

    var attribute: Attribute<Value>? {
        guard let id = base.identifier else { return nil }
        return Attribute(id)
    }
}

// MARK: - Rule Contexts

/// Type-erased identity for the AG rule currently being evaluated.
struct AnyRuleContext: Equatable {
    var attribute: AGAttribute

    init(attribute: AGAttribute) {
        self.attribute = attribute
    }

    init<Value>(_ context: RuleContext<Value>) {
        self.attribute = context.attribute.identifier
    }

    func unsafeCast<Value>(to type: Value.Type) -> RuleContext<Value> {
        RuleContext(attribute: Attribute<Value>(attribute))
    }

    func update(body: () -> Void) {
        AttributeGraph.withRuleContext(attribute) {
            body()
        }
    }

    subscript<Value>(_ attribute: Attribute<Value>) -> Value {
        attribute.value
    }

    subscript<Value>(_ attribute: WeakAttribute<Value>) -> Value? {
        guard let graph = AttributeGraph.current,
              attribute.isValid(in: graph) else { return nil }
        return attribute.toStrong().value
    }

    subscript<Value>(_ attribute: OptionalAttribute<Value>) -> Value? {
        attribute.attribute?.value
    }
}

/// Typed identity and value accessor for the AG rule currently being evaluated.
struct RuleContext<Value>: Equatable {
    var attribute: Attribute<Value>

    init(attribute: Attribute<Value>) {
        self.attribute = attribute
    }

    static func == (lhs: RuleContext<Value>, rhs: RuleContext<Value>) -> Bool {
        lhs.attribute.identifier == rhs.attribute.identifier
    }

    var value: Value {
        get { attribute.value }
        nonmutating set { attribute.setValue(newValue) }
    }

    var hasValue: Bool {
        guard let graph = AttributeGraph.current else { return false }
        return graph.hasCachedValue(for: attribute.identifier)
    }

    func update(body: () -> Void) {
        AnyRuleContext(self).update(body: body)
    }

    subscript<OtherValue>(_ attribute: Attribute<OtherValue>) -> OtherValue {
        attribute.value
    }

    subscript<OtherValue>(_ attribute: WeakAttribute<OtherValue>) -> OtherValue? {
        AnyRuleContext(self)[attribute]
    }

    subscript<OtherValue>(_ attribute: OptionalAttribute<OtherValue>) -> OtherValue? {
        AnyRuleContext(self)[attribute]
    }
}

extension Rule {
    var context: RuleContext<Value> {
        guard let id = AttributeGraph.currentRuleContextAttribute else {
            fatalError("Rule.context accessed outside rule evaluation.")
        }
        return RuleContext(attribute: Attribute<Value>(id))
    }
}

extension StatefulRule {
    var context: RuleContext<Value> {
        guard let id = AttributeGraph.currentRuleContextAttribute else {
            fatalError("StatefulRule.context accessed outside rule evaluation.")
        }
        return RuleContext(attribute: Attribute<Value>(id))
    }
}

// MARK: - AGSubgraph

/// A group of AG nodes that are created and destroyed together.
///
/// Subgraph lifecycle handle for groups of AG nodes.
///
/// Must be created while an AttributeGraph context is active (`AttributeGraph.current != nil`).
/// The owning AttributeGraph is captured at creation time and validated on `invalidate()`.
///
/// Wrap node-creation code in `AGSubgraph.$current.withValue(subgraph) { ... }` to
/// automatically register every node created in that scope to this subgraph.
/// Call `invalidate()` to batch-remove all registered nodes at once.
///
/// Subgraphs form a parent/child tree: an AGSubgraph created while another is active
/// automatically becomes its child. `invalidate()` cascades depth-first,
/// so invalidating a parent also destroys all descendant subgraphs.
///
/// Typical use: ForEach item lifecycle:
/// ```swift
/// let subgraph = AGSubgraph()
/// AGSubgraph.$current.withValue(subgraph) {
///     Content._makeView(view: itemGraph, inputs: inputs)
/// }
/// itemSubgraphs[id] = subgraph
///
/// // item removed:
/// itemSubgraphs[id]?.invalidate()
/// itemSubgraphs[id]?.removeFromParent()
/// itemSubgraphs[id] = nil
/// ```
final class AGSubgraph: @unchecked Sendable {
    private(set) var nodes: [AGAttribute] = []
    private(set) var children: [AGSubgraph] = []
    private(set) weak var parent: AGSubgraph? = nil
    weak let graph: AttributeGraph?

    @TaskLocal static var current: AGSubgraph? = nil

    init() {
        guard let graph = AttributeGraph.current else {
            fatalError("AGSubgraph must be created within an active AttributeGraph context.")
        }
        self.graph = graph
        if let parent = AGSubgraph.current {
            parent.children.append(self)
            self.parent = parent
        }
    }

    func register(_ id: AGAttribute) {
        nodes.append(id)
    }

    func invalidate() {
        guard let graph = AttributeGraph.current else {
            fatalError("AGSubgraph.invalidate() called outside an active AttributeGraph context.")
        }
        guard graph === self.graph else {
            fatalError("AGSubgraph.invalidate() called from a different AttributeGraph than the one that owns this subgraph.")
        }

        children.forEach {
            $0.invalidate()
            $0.parent = nil
        }
        children.removeAll()

        nodes.forEach {
            graph.removeNode($0)
        }
        nodes.removeAll()
    }

    func removeFromParent() {
        parent?.children.removeAll { $0 === self }
        parent = nil
    }

    func update(flags: UInt32 = 1) {
        guard let graph = AttributeGraph.current else {
            fatalError("AGSubgraph.update() called outside an active AttributeGraph context.")
        }
        guard graph === self.graph else {
            fatalError("AGSubgraph.update() called from a different AttributeGraph than the one that owns this subgraph.")
        }
        graph.updateSubgraph(self, flags: flags)
    }

    func willRemove() {
        guard let graph = AttributeGraph.current else {
            fatalError("AGSubgraph.willRemove() called outside an active AttributeGraph context.")
        }
        guard graph === self.graph else {
            fatalError("AGSubgraph.willRemove() called from a different AttributeGraph than the one that owns this subgraph.")
        }
        graph.willRemoveSubgraph(self)
    }

    func didReinsert() {
        guard let graph = AttributeGraph.current else {
            fatalError("AGSubgraph.didReinsert() called outside an active AttributeGraph context.")
        }
        guard graph === self.graph else {
            fatalError("AGSubgraph.didReinsert() called from a different AttributeGraph than the one that owns this subgraph.")
        }
        graph.didReinsertSubgraph(self)
    }
}

// MARK: - AttributeGraphRef
// Reference wrapper used to bind an AttributeGraph to a host context.
//
// Multiple AttributeGraphRef instances can share the same underlying AttributeGraph core.
// Each GraphHost subclass (ViewGraph, GestureGraph) owns one AttributeGraphRef and registers
// itself as the `context`, enabling `GestureGraph.current` / `ViewGraph.current` resolution
// via the AG evaluation context.
//
// Usage:
//   let ref = AttributeGraphRef(graph: sharedCore)
//   ref.context = self   // register this GraphHost as the context
struct AttributeGraphRef: @unchecked Sendable {
    let graph: AttributeGraph       // shared graph core (one per window)
    weak var context: AnyObject?    // the GraphHost that owns this ref (ViewGraph, GestureGraph, ...)

    /// The currently active AttributeGraphRef for the running AG evaluation pass.
    /// Set by withCurrent(_:). Reading context gives the owning GraphHost subclass.
    @TaskLocal static var current: AttributeGraphRef? = nil

    init(graph: AttributeGraph, context: AnyObject? = nil) {
        self.graph = graph
        self.context = context
    }

    /// Establishes both AttributeGraphRef.current (self) and AttributeGraph.current (self.graph)
    /// for the duration of the closure. This is the canonical way to enter a GraphHost's AG context.
    func withCurrent<R>(_ body: () throws -> R) rethrows -> R {
        if let activeGraph = AttributeGraph.current, activeGraph !== graph {
            // Dependency tracking is graph-local. Cross-graph re-entry must not
            // inherit the outer graph's currently evaluating node.
            return try AttributeGraph.withoutTracking {
                try AttributeGraphRef.$current.withValue(self) {
                    try AttributeGraph.$current.withValue(graph) {
                        try body()
                    }
                }
            }
        }
        return try AttributeGraphRef.$current.withValue(self) {
            try AttributeGraph.$current.withValue(graph) {
                try body()
            }
        }
    }
}

// MARK: - AGChangeSet

/// Records attributes that were mutated during an `AttributeGraph.$changeSet.withValue(_:)`
/// scope, partitioned by owning AttributeGraph instance.
///
/// Storage is keyed by `ObjectIdentifier(graph)` so attributes from different graphs
/// never share a `Set<AGAttribute>` bucket. Without this partitioning, a hash collision
/// between equal `rawValue`s in different graphs would invoke cross-graph `AGAttribute.==`
/// (which is only a same-graph comparison by contract).
///
final class AGChangeSet: @unchecked Sendable {
    private var _byGraph: [ObjectIdentifier: Set<AGAttribute>] = [:]

    var isEmpty: Bool { _byGraph.values.allSatisfy { $0.isEmpty } }

    /// Attributes recorded for a specific graph during this AGChangeSet's lifetime.
    func ids(for graph: AttributeGraph) -> Set<AGAttribute> {
        _byGraph[ObjectIdentifier(graph)] ?? []
    }

    fileprivate func record(_ id: AGAttribute) {
        guard let graph = AttributeGraph.current else {
            fatalError("AGChangeSet.record called outside an active AttributeGraph context.")
        }
        _byGraph[ObjectIdentifier(graph), default: []].insert(id)
    }
}

// MARK: - AttributeGraph

class AttributeGraph: @unchecked Sendable {

    // MARK: Node Storage

    // Describes how a node computes its value.
    // Exactly one case is active per node. Mutual exclusion is guaranteed at the type level.
    private enum NodeKind {
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
        // Output is written by calling AttributeGraph.setStatefulOutput(_:) inside updateValue().
        // If setStatefulOutput is not called during a given evaluation, the previous value is kept.
        // The box receives destroy() once before node removal so stateful rules can release
        // pending deferred work associated with the node's lifetime.
        case stateful(any _AnyStatefulBox)

        // KeyPath-derived node. Value is projected from a parent node via a key path.
        // The dependency on parent is fixed at creation time and never changes.
        case keyPath(parent: AGAttribute, kp: AnyKeyPath)

        // Cross-graph mirror node. It reads its cached value from a node in another AttributeGraph.
        // Evaluated lazily via cachedValue(for:) on the source graph (no context switch needed).
        // Invalidated reactively: when the source node changes, the source graph enqueues a
        // markNeedsEvaluation call into this graph's inbox. This graph drains the inbox at
        // the start of each withCurrent block (e.g. GestureGraph.sendEvents).
        case crossGraphRef(sourceAttr: AGAttribute, sourceGraph: WeakObject<AttributeGraph>)

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

    private struct Node {
        var value: Any?
        var transaction: Transaction? = nil
        var kind: NodeKind
        var needsEvaluation: Bool = true
        var inputsChanged: Bool = true
        var isEvaluating: Bool = false  // for cycle detection

        // Dependency graph edges (stored as raw slot indices)
        var inputs: Set<UInt32> = []        // nodes this node depends on
        var outputs: Set<UInt32> = []       // nodes that depend on this node
        // Permanent deps registered via setIndirectDependency. They are never cleared on re-evaluation.
        var staticInputs: Set<UInt32> = []
    }

    private struct NodeSlot {
        var seed: UInt32    // generation counter incremented on each removal
        var node: Node?     // nil = free slot
    }

    private struct RelativePath: Hashable {
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
    private var slots: ContiguousArray<NodeSlot> = []
    // Freed slot indices available for reuse
    private var freeList: [UInt32] = []
    // Cache for KeyPath-derived child nodes
    private var pathIDs: [RelativePath: UInt32] = [:]
#if DEBUG
    private var removedNodeTombstones: [UInt32: RemovedNodeTombstone] = [:]
    private var removedNodeTombstoneOrder: [UInt32] = []
    private let removedNodeTombstoneLimit = 4096
#endif

    // MARK: Stored Properties

    // Thread-safe bridge for scheduling AG invalidations from arbitrary threads.
    let inbox: AGInbox = AGInbox()

    // Cross-graph observer registry.
    // When a crossGraphRef node in another graph mirrors a node in this graph, an entry is
    // registered here. On every setValue / markNeedsEvaluation for that source node, the
    // target graph is notified via its inbox so that it can invalidate the mirror node when
    // it next enters an AG context (e.g. GestureGraph.sendEvents -> data.withCurrent).
    private struct CrossGraphObserver {
        weak var targetGraph: AttributeGraph?
        var targetNodeID: UInt32
    }
    private var crossGraphObservers: [UInt32: [CrossGraphObserver]] = [:]

    // Deferred action outbox: closures to be executed OUTSIDE AG evaluation context.
    // Enqueue from within AG evaluation. WindowController drains after all AG work is done.
    var actionOutbox: [() -> Void] = []
    private var updateCounter: UInt = 0

    // MARK: Task Locals

    typealias ChangeSet = AGChangeSet

    @TaskLocal static var current: AttributeGraph?
    @TaskLocal static var changeSet: ChangeSet?
    @TaskLocal private static var currentlyEvaluatingNode: AGAttribute?
    @TaskLocal private static var currentlyUpdatingGraphs: Set<ObjectIdentifier>?

    init() {}

    func graphCounter(lane: UInt32) -> UInt {
        switch lane {
        case 1:
            return updateCounter
        default:
            return 0
        }
    }

    fileprivate func hasCachedValue(for id: AGAttribute) -> Bool {
        id._debugValidate()
        let index = Int(id.rawValue)
        guard index < slots.count else { return false }
        return slots[index].node?.value != nil
    }

    static var currentRuleContextAttribute: AGAttribute? {
        currentlyEvaluatingNode
    }

    fileprivate static func withRuleContext<T>(_ attribute: AGAttribute, body: () -> T) -> T {
        $currentlyEvaluatingNode.withValue(attribute) {
            body()
        }
    }

    // MARK: Node Factory

    fileprivate func _seed(at index: UInt32) -> UInt32 {
        slots[Int(index)].seed
    }

    fileprivate func _seedIfPresent(at index: UInt32) -> UInt32? {
        let i = Int(index)
        guard i < slots.count else { return nil }
        return slots[i].seed
    }

    fileprivate func _isValid(index: UInt32, seed: UInt32) -> Bool {
        let i = Int(index)
        guard i < slots.count else { return false }
        return slots[i].seed == seed && slots[i].node != nil
    }

    func weakAttributeIfValid(for id: AGAttribute) -> AGWeakAttribute? {
        let index = Int(id.rawValue)
        guard index < slots.count else { return nil }
#if DEBUG
        guard _isValid(index: id.rawValue, seed: id._debugSeedAtCreation) else { return nil }
        return AGWeakAttribute(identifier: id.rawValue,
                               seed: id._debugSeedAtCreation,
                               owningGraph: ObjectIdentifier(self))
#else
        guard slots[index].node != nil else { return nil }
        return AGWeakAttribute(identifier: id.rawValue, seed: slots[index].seed)
#endif
    }

#if DEBUG
    fileprivate func _debugSlotStateDescription(at index: UInt32) -> String {
        let i = Int(index)
        guard i < slots.count else { return "slot=missing, slots.count=\(slots.count)" }
        return "currentSeed=\(slots[i].seed), nodeExists=\(slots[i].node != nil), inFreeList=\(freeList.contains(index))"
    }
#endif

    private func allocateSlot() -> UInt32 {
        if let index = freeList.popLast() {
            // Reuse freed slot (seed was already incremented on removal)
#if DEBUG
            if _attributeGraphRecordRemovalTombstones {
                removedNodeTombstones.removeValue(forKey: index)
                removedNodeTombstoneOrder.removeAll { $0 == index }
            }
#endif
            return index
        }
        let index = UInt32(slots.count)
        slots.append(NodeSlot(seed: 0, node: nil))
        return index
    }

    /// Reads the current cached output of the executing StatefulRule node.
    ///
    /// Returns the value stored by the most recent setStatefulOutput call
    /// (i.e. the output from the previous evaluation).
    /// Returns nil if no output has been set yet (first evaluation).
    ///
    /// Must be called from within StatefulRule.updateValue(). Used by ResettableGestureRule
    /// to implement phaseValue.getter. This reads the previous phase without redundant storage.
    static func currentStatefulOutput<V>(_ type: V.Type = V.self) -> V? {
        guard let graph = AttributeGraph.current,
              let nodeID = AttributeGraph.currentlyEvaluatingNode else { return nil }
        return graph.slots[Int(nodeID.rawValue)].node?.value as? V
    }

    /// Reports whether the current StatefulRule evaluation was caused by an
    /// upstream input/dependency change.
    static func currentStatefulInputsChanged() -> Bool {
        guard let graph = AttributeGraph.current,
              let nodeID = AttributeGraph.currentlyEvaluatingNode else { return true }
        return graph.slots[Int(nodeID.rawValue)].node?.inputsChanged ?? true
    }

    /// Called from within `StatefulRule.updateValue()` to publish the node's output value.
    ///
    /// Must be called on `AttributeGraph.current` while `updateValue()` is executing.
    /// If not called during a given evaluation, the previously cached value is retained.
    static func setStatefulOutput<V>(_ value: V) {
        guard let graph = AttributeGraph.current else {
            fatalError("setStatefulOutput called outside of an AttributeGraph context.")
        }
        guard let nodeID = AttributeGraph.currentlyEvaluatingNode else {
            fatalError("setStatefulOutput called outside of a StatefulRule.updateValue() call.")
        }
        graph.slots[Int(nodeID.rawValue)].node!.value = value
    }

    /// Creates a source-of-truth input node (e.g., @State)
    func makeInput<Value>(value: Value) -> Attribute<Value> {
        assert(AttributeGraph.current === self)
        let index = allocateSlot()
        slots[Int(index)].node = Node(value: value, kind: .input, needsEvaluation: false)
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    /// Creates a computed node with a rule (e.g., a View's body or a derived property)
    func makeRule<Value>(rule: @escaping () -> Value) -> Attribute<Value> {
        assert(AttributeGraph.current === self)
        let index = allocateSlot()
        slots[Int(index)].node = Node(value: nil, kind: .rule(rule, isSideEffect: false))
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    /// Creates a computed node backed by a Rule struct (pure, stateless).
    func makeRule<R: Rule>(_ rule: R) -> Attribute<R.Value> {
        makeRule(rule: { rule.updateValue() })
    }

    /// Creates a computed AG node backed by a `StatefulRule`.
    ///
    /// The rule struct is stored inside the node and reused across re-evaluations.
    /// Use this instead of `makeRule` when the rule needs to lazily initialize a persistent
    /// object (e.g. a ViewResponder) and update only its properties on subsequent calls.
    func makeStatefulRule<R: StatefulRule>(_ rule: R) -> Attribute<R.Value> {
        assert(AttributeGraph.current === self)
        let index = allocateSlot()
        slots[Int(index)].node = Node(value: nil, kind: .stateful(_StatefulBox(rule)))
        let attr = Attribute<R.Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    func mutateStatefulRule<R: StatefulRule>(
        _ id: AGAttribute,
        as type: R.Type = R.self,
        invalidating: Bool = false,
        _ body: (inout R) -> Void
    ) {
        assert(AttributeGraph.current === self)
        let index = Int(id.rawValue)
        guard index < slots.count,
              let node = slots[index].node else {
            return
        }
        guard case .stateful(let box) = node.kind,
              let typedBox = box as? _StatefulBox<R> else {
            return
        }
        body(&typedBox.rule)
        if invalidating {
            markNeedsEvaluation(id)
        }
    }

    /// Creates a side-effect rule that is evaluated eagerly whenever any of its inputs change.
    ///
    /// Use this instead of `makeRule` when:
    ///   - The rule's return value is never read by another node (`let _ = makeRule { ... }`)
    ///   - The rule exists purely for its side effects: firing callbacks, updating external
    ///     objects, writing to non-AG state (e.g. gesture recognizers, @State mutations)
    ///
    /// The rule is evaluated once immediately upon creation to register its AG dependencies.
    /// After that it is re-evaluated synchronously inside `markNeedsEvaluation` whenever an
    /// input changes, i.e. within the same `setValue` call stack, not deferred to the next
    /// layout pass.
    ///
    /// The node is registered in the current AGSubgraph and removed when the AGSubgraph is
    /// invalidated (e.g. when the owning view is removed from the tree).
    @discardableResult
    func makeSideEffectRule<Value>(rule: @escaping () -> Value) -> Attribute<Value> {
        assert(AttributeGraph.current === self)
        let index = allocateSlot()
        slots[Int(index)].node = Node(value: nil, kind: .rule(rule, isSideEffect: true))
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        // Evaluate immediately so the rule body runs once and AG records which input
        // attributes it reads, establishing the dependency edges that will trigger
        // future eager re-evaluations.
        evaluateNodeForUpdate(AGAttribute(rawValue: index))
        return attr
    }

    // MARK: - Cross-Graph Reference
    // Allows a node in one AttributeGraph to reactively mirror a node from another.
    // Used by GestureGraph <- ViewGraph geometry nodes (GestureResponder hit-test)
    // and sheet WindowController <- parent ViewGraph content rule (makeContent reactivity).
    //
    // Flow: makeCrossGraphRef (target graph) -> addCrossGraphObserver (source graph)
    //       source setValue -> notifyCrossGraphObservers -> target inbox.enqueue(markNeedsEvaluation)
    //       target withCurrent -> inbox.drain() -> crossGraphRef node re-evaluates via cachedValue

    /// Returns the cached value of a node without requiring this graph to be current.
    ///
    /// Used exclusively by crossGraphRef node evaluation: a node in graph B reads a cached
    /// value from graph A while graph B is current. No evaluation is triggered. The source
    /// graph must have already evaluated and cached the value. fatalError if the node has
    /// never been evaluated (no cached value available yet).
    func cachedValue(for id: AGAttribute) -> Any? {
        let index = Int(id.rawValue)
        guard let node = slots[index].node else {
            fatalError("cachedValue: node @\(id.rawValue) does not exist in source graph.")
        }
        guard let cached = node.value else {
            fatalError("cachedValue: node @\(id.rawValue) has no cached value; source graph must evaluate first.")
        }
        return cached
    }

    func transaction(for id: AGAttribute) -> Transaction? {
        assert(AttributeGraph.current === self)
        let index = Int(id.rawValue)
        guard index < slots.count,
              let node = slots[index].node else {
            return nil
        }
        return node.transaction
    }

    /// Registers a cross-graph observer: when node `sourceAttr` in this graph changes,
    /// `targetNode` in `targetGraph` is marked dirty via the target graph's inbox.
    func addCrossGraphObserver(
        for sourceAttr: AGAttribute,
        notifying targetGraph: AttributeGraph,
        targetNode: AGAttribute
    ) {
        let entry = CrossGraphObserver(targetGraph: targetGraph, targetNodeID: targetNode.rawValue)
        crossGraphObservers[sourceAttr.rawValue, default: []].append(entry)
    }

    /// Removes the cross-graph observer entry for `targetNode` in `targetGraph`
    /// watching `sourceAttr` in this graph. Called when the crossGraphRef node is removed.
    func removeCrossGraphObserver(
        for sourceAttr: AGAttribute,
        targetGraph: AttributeGraph,
        targetNode: AGAttribute
    ) {
        crossGraphObservers[sourceAttr.rawValue]?.removeAll {
            $0.targetGraph === targetGraph && $0.targetNodeID == targetNode.rawValue
        }
        if crossGraphObservers[sourceAttr.rawValue]?.isEmpty == true {
            crossGraphObservers.removeValue(forKey: sourceAttr.rawValue)
        }
    }

    /// Notifies cross-graph observers of `sourceNodeID` by enqueueing a markNeedsEvaluation
    /// call into each target graph's inbox. Dead entries (target graph deallocated) are removed.
    private func notifyCrossGraphObservers(for sourceNodeID: UInt32) {
        guard var entries = crossGraphObservers[sourceNodeID] else { return }
        var hasDeadEntries = false
        for entry in entries {
            guard let targetGraph = entry.targetGraph else {
                hasDeadEntries = true
                continue
            }
            let targetNodeID = entry.targetNodeID
            targetGraph.inbox.enqueue { [weak targetGraph] in
                targetGraph?.markNeedsEvaluation(AGAttribute(rawValue: targetNodeID))
            }
        }
        if hasDeadEntries {
            entries.removeAll { $0.targetGraph == nil }
            crossGraphObservers[sourceNodeID] = entries.isEmpty ? nil : entries
        }
    }

    /// Creates a cross-graph mirror node in this graph that reflects a node from `sourceGraph`.
    ///
    /// Must be called within this graph's context (self == AttributeGraph.current).
    /// The source and target graphs must be different.
    ///
    /// The returned attribute is evaluated lazily: on first read, `cachedValue(for:)` is
    /// called on `sourceGraph`. The node is automatically invalidated whenever the source
    /// node changes, `sourceGraph` enqueues a `markNeedsEvaluation` into this graph's inbox,
    /// and the inbox is drained at the start of the next `withCurrent` block.
    func makeCrossGraphRef<V>(source: Attribute<V>, in sourceGraph: AttributeGraph) -> Attribute<V> {
        assert(AttributeGraph.current === self,
               "makeCrossGraphRef: must be called within the target graph's context")
        precondition(sourceGraph !== self,
                     "makeCrossGraphRef: source and target graph must be different")
        let index = allocateSlot()
        slots[Int(index)].node = Node(
            value: nil,
            kind: .crossGraphRef(
                sourceAttr: source.identifier,
                sourceGraph: WeakObject(sourceGraph)
            )
        )
        let attr = Attribute<V>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        sourceGraph.addCrossGraphObserver(
            for: source.identifier,
            notifying: self,
            targetNode: attr.identifier
        )
        return attr
    }

    // MARK: Node Lifecycle

    /// Completely removes a node and cleans up its dependencies.
    func removeNode(_ id: AGAttribute) {
        assert(AttributeGraph.current === self)
        let index = Int(id.rawValue)
        guard let removingNode = slots[index].node else {
            fatalError("removeNode called on @\(id.rawValue) which does not exist; double-remove is a usage error.")
        }
#if DEBUG
        recordRemovedNodeTombstone(id: id, node: removingNode)
#endif

        if case .stateful(let box) = removingNode.kind {
            box.callDestroy()
        }

        // 1. Break input connections (removes this node from its inputs' output sets)
        clearInputs(for: id, includingStatic: true)

        // 2. Collect outputs and clean up their back-references
        let outputs = slots[index].node!.outputs
        for outputIndex in outputs {
            slots[Int(outputIndex)].node?.inputs.remove(id.rawValue)
        }

        // 3. Remove from KeyPath cache / cross-graph observer registry if applicable
        switch slots[index].node?.kind {
        case .keyPath(let parent, let kp):
            pathIDs.removeValue(forKey: RelativePath(parentID: parent.rawValue, keyPath: kp))
        case .crossGraphRef(let sourceAttr, let sourceGraphRef):
            // Unregister from the source graph's observer list so it stops notifying us.
            sourceGraphRef.value?.removeCrossGraphObserver(
                for: sourceAttr, targetGraph: self, targetNode: id)
        default:
            break
        }
        // Remove any cross-graph observers that were watching this node (it was a source).
        crossGraphObservers.removeValue(forKey: id.rawValue)

        // 4. Invalidate: increment seed (all AGWeakAttributes pointing here are now stale),
        //    free the slot, and push index to freeList for reuse
        slots[index].seed &+= 1
        slots[index].node = nil
        freeList.append(id.rawValue)

        // 5. Mark former dependents as needing re-evaluation.
        // evaluateSideEffects:false because the node is gone. Side-effect rules that depended
        // on it must NOT fire now (they would crash reading a freed attribute).
        // They are simply marked dirty and will be removed or re-evaluated later.
        for outputIndex in outputs {
            markNeedsEvaluation(AGAttribute(rawValue: outputIndex), evaluateSideEffects: false)
        }
    }

    // MARK: Value Access

    func value(for id: AGAttribute) -> Any? {
        assert(AttributeGraph.current === self)
        let index = Int(id.rawValue)
        guard slots[index].node != nil else {
            fatalError("Invalid AGAttribute @\(id.rawValue): node does not exist.")
        }

        let node = slots[index].node!

        // Cycle detection
        if node.needsEvaluation && node.isEvaluating {
            guard node.value != nil else {
                fatalError("AttributeGraph: cycle detected at @\(id.rawValue) with no cached value. Call setValue(_:) on this attribute before it is first read to provide a fallback.")
            }
        }

        let shouldEvaluate = node.needsEvaluation && !node.isEvaluating

        // Implicit dependency tracking
        if let evaluator = AttributeGraph.currentlyEvaluatingNode, evaluator != id {
            addDependency(from: evaluator, dependsOn: id)
        }

        // Lazy evaluation
        if shouldEvaluate {
            slots[index].node!.isEvaluating = true
            evaluateNodeForUpdate(id)
        }

        return slots[index].node?.value
    }

    func setValue<Value: Equatable>(for attribute: Attribute<Value>, to newValue: Value, transaction: Transaction = Transaction()) {
        assert(AttributeGraph.current === self)
        let index = Int(attribute.identifier.rawValue)
        guard slots[index].node != nil else {
            fatalError("setValue called on AGAttribute @\(attribute.identifier.rawValue) that does not exist.")
        }
        if let oldValue = slots[index].node!.value as? Value, oldValue == newValue { return }
        slots[index].node!.value = newValue
        Transaction.ThreadStorage.markMutation(for: transaction)
        let transactionToPropagate = transaction.isEmpty ? nil : transaction
        slots[index].node!.transaction = transactionToPropagate
        let outputs = slots[index].node!.outputs
        for outputIndex in outputs {
            markNeedsEvaluation(
                AGAttribute(rawValue: outputIndex),
                transaction: transactionToPropagate,
                propagateTransaction: true
            )
        }
        notifyCrossGraphObservers(for: attribute.identifier.rawValue)
        AttributeGraph.changeSet?.record(attribute.identifier)
    }

    func setValue<Value>(for attribute: Attribute<Value>, to newValue: Value, transaction: Transaction = Transaction()) {
        assert(AttributeGraph.current === self)
        let index = Int(attribute.identifier.rawValue)
        guard slots[index].node != nil else {
            fatalError("setValue called on AGAttribute @\(attribute.identifier.rawValue) that does not exist.")
        }
        slots[index].node!.value = newValue
        Transaction.ThreadStorage.markMutation(for: transaction)
        let transactionToPropagate = transaction.isEmpty ? nil : transaction
        slots[index].node!.transaction = transactionToPropagate
        let outputs = slots[index].node!.outputs
        for outputIndex in outputs {
            markNeedsEvaluation(
                AGAttribute(rawValue: outputIndex),
                transaction: transactionToPropagate,
                propagateTransaction: true
            )
        }
        notifyCrossGraphObservers(for: attribute.identifier.rawValue)
        AttributeGraph.changeSet?.record(attribute.identifier)
    }

    func invalidateAttribute(_ id: AGAttribute) {
        assert(AttributeGraph.current === self)
        let index = Int(id.rawValue)
        guard let node = slots[index].node else { return }

        if case .input = node.kind {
            for outputIndex in node.outputs {
                markNeedsEvaluation(AGAttribute(rawValue: outputIndex))
            }
            notifyCrossGraphObservers(for: id.rawValue)
        } else {
            markNeedsEvaluation(id)
        }
    }

    // MARK: Dependency Graph

    private func evaluateNodeForUpdate(_ id: AGAttribute) {
        withGraphUpdateCounterIfNeeded {
            evaluateNode(id)
        }
    }

    fileprivate func updateSubgraph(_ subgraph: AGSubgraph, flags: UInt32) {
        assert(AttributeGraph.current === self)
        _ = flags
        inbox.drain()
        for node in subgraph.nodes {
            guard let liveNode = weakAttributeIfValid(for: node)?.toStrong() else {
                continue
            }
            _ = value(for: liveNode)
        }
        for child in subgraph.children {
            updateSubgraph(child, flags: flags)
        }
    }

    fileprivate func willRemoveSubgraph(_ subgraph: AGSubgraph) {
        assert(AttributeGraph.current === self)
        for node in subgraph.nodes {
            guard let liveNode = weakAttributeIfValid(for: node)?.toStrong() else {
                continue
            }
            if case .stateful(let box) = slots[Int(liveNode.rawValue)].node?.kind {
                box.callWillRemove(attribute: liveNode)
            }
        }
        for child in subgraph.children {
            willRemoveSubgraph(child)
        }
    }

    fileprivate func didReinsertSubgraph(_ subgraph: AGSubgraph) {
        assert(AttributeGraph.current === self)
        for node in subgraph.nodes {
            guard let liveNode = weakAttributeIfValid(for: node)?.toStrong() else {
                continue
            }
            if case .stateful(let box) = slots[Int(liveNode.rawValue)].node?.kind {
                box.callDidReinsert(attribute: liveNode)
            }
        }
        for child in subgraph.children {
            didReinsertSubgraph(child)
        }
    }

    private func withGraphUpdateCounterIfNeeded<R>(_ body: () -> R) -> R {
        let graphID = ObjectIdentifier(self)
        var activeGraphs = AttributeGraph.currentlyUpdatingGraphs ?? []
        guard !activeGraphs.contains(graphID) else {
            return body()
        }
        updateCounter &+= 1
        activeGraphs.insert(graphID)
        return AttributeGraph.$currentlyUpdatingGraphs.withValue(activeGraphs) {
            body()
        }
    }

    private func evaluateNode(_ id: AGAttribute) {
        let index = Int(id.rawValue)
        guard let node = slots[index].node else {
            fatalError("evaluateNode called on AGAttribute @\(id.rawValue) that does not exist.")
        }

        switch node.kind {
        case .input:
            fatalError("evaluateNode called on an input node @\(id.rawValue); input nodes must never be marked needsEvaluation.")

        case .stateful(let box):
            // StatefulRule node: re-evaluate the stored rule struct.
            // Dependency tracking works via currentlyEvaluatingNode (same as .rule).
            // Output is written only when updateValue() calls setStatefulOutput(_:).
            // If it doesn't, the previous cached value is retained unchanged.
            clearInputs(for: id)
            AttributeGraph.$currentlyEvaluatingNode.withValue(id) {
                box.callUpdate()
            }
            slots[index].node!.needsEvaluation = false
            slots[index].node!.inputsChanged = false
            slots[index].node!.isEvaluating = false

        case .keyPath(let parent, let kp):
            // KeyPath node: project value from parent via the stored key path.
            // clearInputs is intentionally omitted. The dependency on parent is fixed
            // at creation time in subscriptNode() and never changes.
            // Note: value(for: parent) runs while currentlyEvaluatingNode is still set to
            // the outer caller, so the caller also acquires a direct dependency on parent
            // (in addition to its dependency on this KeyPath node). The redundant edge is
            // cleaned up by clearInputs on the caller's next re-evaluation.
            let parentValue = value(for: parent)
            slots[index].node!.value = parentValue[keyPath: kp]
            slots[index].node!.needsEvaluation = false
            slots[index].node!.isEvaluating = false

        case .crossGraphRef(let sourceAttr, let sourceGraphRef):
            // Cross-graph mirror node: read the cached value from the source graph.
            // No context switch. cachedValue(for:) bypasses the current-graph assertion.
            // If the source graph has been deallocated, retain the last cached value.
            if let sourceGraph = sourceGraphRef.value {
                slots[index].node!.value = sourceGraph.cachedValue(for: sourceAttr)
            }
            // else: source graph gone, keep last cached value silently.
            slots[index].node!.needsEvaluation = false
            slots[index].node!.isEvaluating = false

        case .rule(let rule, _):
            // Regular computed rule: re-run the closure and store the result.
            clearInputs(for: id)
            let newValue = AttributeGraph.$currentlyEvaluatingNode.withValue(id) {
                rule()
            }
            slots[index].node!.value = newValue
            slots[index].node!.needsEvaluation = false
            slots[index].node!.isEvaluating = false

        case .indirect(let target):
            // Indirect node: clears old dynamic dep (preserves static deps), then re-reads target.
            // When target is nil, the stored default value is retained unchanged.
            clearInputs(for: id)
            if let target {
                let targetValue = AttributeGraph.$currentlyEvaluatingNode.withValue(id) {
                    value(for: target)
                }
                slots[index].node!.value = targetValue
            }
            slots[index].node!.needsEvaluation = false
            slots[index].node!.isEvaluating = false
        }
    }

    /// Marks `startID` and all its transitive dependents as needing re-evaluation.
    ///
    /// - Parameter evaluateSideEffects: When `true` (default, used by `setValue`),
    ///   side-effect nodes are evaluated eagerly within this call so that callbacks
    ///   fire synchronously. When `false` (used by `removeNode`), side-effect nodes
    ///   are only marked dirty. They must NOT be evaluated because an input node
    ///   they depend on may have already been freed.
    func markNeedsEvaluation(
        _ startID: AGAttribute,
        evaluateSideEffects: Bool = true,
        transaction: Transaction? = nil,
        propagateTransaction: Bool = false,
        inputsChanged: Bool = true
    ) {
        assert(AttributeGraph.current === self)
        // Iterative BFS to avoid stack overflow on deep dependency graphs.
        // Side-effect nodes are collected separately and evaluated after the BFS completes,
        // so that cascading setValue calls (from inside the side-effect rule) create their
        // own BFS + evaluation chain without interfering with the current traversal.
        var queue: [UInt32] = [startID.rawValue]
        var visited: Set<UInt32> = []
        var sideEffects: [UInt32] = []
        var sideEffectSet: Set<UInt32> = []
        var i = 0
        while i < queue.count {
            let rawID = queue[i]; i += 1
            guard visited.insert(rawID).inserted else { continue }
            let index = Int(rawID)
            guard var node = slots[index].node else { continue }  // freed slot, skip
            if propagateTransaction {
                node.transaction = transaction
            }
            if inputsChanged {
                node.inputsChanged = true
            }
            if !node.needsEvaluation {
                node.needsEvaluation = true
                slots[index].node = node
            } else if propagateTransaction || inputsChanged {
                slots[index].node = node
            }
            if node.kind.isSideEffect {
                if sideEffectSet.insert(UInt32(index)).inserted {
                    sideEffects.append(UInt32(index))
                }
            }
            // Even when a node is already dirty, keep walking its outputs.
            // Structural updates can leave intermediate preference/layout nodes
            // dirty. Later source changes still need to reach side-effect refresh
            // rules that may have been evaluated and cleared in the meantime.
            queue.append(contentsOf: node.outputs)
            // Propagate to cross-graph mirror nodes watching this node.
            notifyCrossGraphObservers(for: UInt32(index))
        }
        // Eagerly evaluate side-effect nodes in dependency order (parents before children).
        // Skipped when called from removeNode. Inputs may already be freed.
        guard evaluateSideEffects else { return }
        for id in sideEffects {
            let index = Int(id)
            guard slots[index].node != nil else { continue }  // may have been freed
            guard slots[index].node!.needsEvaluation else { continue }  // already evaluated by cascade
            evaluateNodeForUpdate(AGAttribute(rawValue: id))
        }
    }

    /// Executes `action` without recording any AG dependencies.
    /// Use when calling user-provided callbacks from inside a rule body to prevent
    /// the callback's side-reads (e.g. `@State` getter, `@Observable` access) from
    /// accidentally becoming inputs of the enclosing rule.
    static func withoutTracking<R>(_ action: () throws -> R) rethrows -> R {
        try Self.$currentlyEvaluatingNode.withValue(nil) { try action() }
    }

    private func addDependency(from parent: AGAttribute, dependsOn child: AGAttribute) {
        let parentIndex = Int(parent.rawValue)
        let childIndex = Int(child.rawValue)
        guard slots[parentIndex].node != nil else {
            fatalError("addDependency: parent node @\(parent.rawValue) does not exist.")
        }
        guard slots[childIndex].node != nil else {
            fatalError("addDependency: child node @\(child.rawValue) does not exist.")
        }
        slots[parentIndex].node!.inputs.insert(child.rawValue)
        slots[childIndex].node!.outputs.insert(parent.rawValue)
    }

    /// Clears dependency edges from `id` to its inputs.
    /// - Parameter includingStatic: When false (default, used during re-evaluation), static inputs
    ///   registered via `setIndirectDependency` are preserved. When true (used during `removeNode`),
    ///   all inputs, including static, are removed.
    private func clearInputs(for id: AGAttribute, includingStatic: Bool = false) {
        let index = Int(id.rawValue)
        guard slots[index].node != nil else {
            fatalError("clearInputs called on AGAttribute @\(id.rawValue) that does not exist.")
        }
        let toClear = includingStatic
            ? slots[index].node!.inputs
            : slots[index].node!.inputs.subtracting(slots[index].node!.staticInputs)
        if includingStatic {
            slots[index].node!.inputs.removeAll()
            slots[index].node!.staticInputs.removeAll()
        } else {
            slots[index].node!.inputs = slots[index].node!.staticInputs
        }
        for inputIndex in toClear {
            slots[Int(inputIndex)].node?.outputs.remove(id.rawValue)
        }
    }

    // MARK: Indirect Attributes
    // Indirect attributes provide placeholder output slots that can later point
    // at concrete attributes and retain permanent dependency edges.

    /// Creates an indirect (pointer) node whose initial value is `defaultValue`.
    /// Use `setIndirectTarget` to wire it to a concrete attribute later.
    func makeIndirectAttribute<V>(defaultValue: V) -> Attribute<V> {
        assert(AttributeGraph.current === self)
        let index = allocateSlot()
        // needsEvaluation: false because default value is already stored. Evaluation is triggered
        // only after setIndirectTarget is called (which calls markNeedsEvaluation).
        slots[Int(index)].node = Node(value: defaultValue, kind: .indirect(target: nil),
                                      needsEvaluation: false)
        let attr = Attribute<V>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    /// Points `indirect` at `concrete` (or nil to detach).
    /// Invalidates `indirect` and its downstream dependents.
    func setIndirectTarget(_ indirect: AGAttribute, to concrete: AGAttribute?) {
        assert(AttributeGraph.current === self)
        let index = Int(indirect.rawValue)
        guard case .indirect = slots[index].node?.kind else {
            fatalError("setIndirectTarget: @\(indirect.rawValue) is not an indirect node.")
        }
        slots[index].node!.kind = .indirect(target: concrete)
        markNeedsEvaluation(indirect)
    }

    /// Typed convenience wrapper around `setIndirectTarget(_:to:)`.
    func setIndirectTarget<V>(_ indirect: Attribute<V>, to concrete: Attribute<V>?) {
        setIndirectTarget(indirect.identifier, to: concrete?.identifier)
    }

    /// Registers a permanent dependency: when `dep` changes, `indirect` is invalidated.
    /// Unlike rule-computed inputs, this edge is NOT cleared on re-evaluation.
    func setIndirectDependency(_ indirect: AGAttribute, dependsOn dep: AGAttribute) {
        assert(AttributeGraph.current === self)
        let iIdx = Int(indirect.rawValue)
        let dIdx = Int(dep.rawValue)
        guard slots[iIdx].node != nil else {
            fatalError("setIndirectDependency: indirect node @\(indirect.rawValue) does not exist.")
        }
        guard slots[dIdx].node != nil else {
            fatalError("setIndirectDependency: dep node @\(dep.rawValue) does not exist.")
        }
        slots[iIdx].node!.inputs.insert(dep.rawValue)
        slots[iIdx].node!.staticInputs.insert(dep.rawValue)
        slots[dIdx].node!.outputs.insert(indirect.rawValue)
    }

    // MARK: KeyPath Nodes

    /// Dynamically creates or retrieves a child node representing a property accessed via KeyPath.
    func subscriptNode<T, U>(parent: Attribute<T>, keyPath: KeyPath<T, U>) -> Attribute<U> {
        assert(AttributeGraph.current === self)
        let rp = RelativePath(parentID: parent.identifier.rawValue, keyPath: keyPath)

        if let existingIndex = pathIDs[rp] {
            return Attribute(AGAttribute(rawValue: existingIndex))
        }

        let index = allocateSlot()
        slots[Int(index)].node = Node(value: nil, kind: .keyPath(parent: parent.identifier, kp: keyPath))
        pathIDs[rp] = index
        addDependency(from: AGAttribute(rawValue: index), dependsOn: parent.identifier)
        let attr = Attribute<U>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    func parent(of id: AGAttribute) -> AGAttribute? {
        if case .keyPath(let parent, _) = slots[Int(id.rawValue)].node?.kind { return parent }
        return nil
    }

    func keyPath(of id: AGAttribute) -> AnyKeyPath? {
        if case .keyPath(_, let kp) = slots[Int(id.rawValue)].node?.kind { return kp }
        return nil
    }

    // MARK: Action Queue

    // Closures enqueued here are executed during drainActions().
    // Use enqueue() from button handlers or event callbacks to defer state mutations
    // to the appropriate point in the frame loop.
    private var pendingActions: [() -> Void] = []

    func enqueue(_ action: @escaping () -> Void) {
        assert(AttributeGraph.current === self)
        pendingActions.append(action)
    }

    // Executes only the actions that are queued at the moment of the call, then returns.
    // Any actions enqueued during execution are deferred to the next drainActions() call.
    // Use this variant for a single, bounded flush, e.g. at the start of a frame update.
    func drainActions() {
        assert(AttributeGraph.current === self)
        let actions = pendingActions
        pendingActions.removeAll()
        actions.forEach { $0() }
    }

    // Keeps executing actions (including ones enqueued during execution) until the time
    // limit is reached, then stops. Remaining unexecuted actions stay in the queue.
    // Use this variant for a background drain loop that must yield within a deadline.
    func drainActions(timeLimit: Duration) {
        assert(AttributeGraph.current === self)
        let deadline = ContinuousClock.now + timeLimit
        var index = 0
        while index < pendingActions.count {
            if ContinuousClock.now >= deadline { break }
            pendingActions[index]()
            index += 1
        }
        pendingActions.removeFirst(index)
    }

    // MARK: Debug

    func debugDescription(for id: AGAttribute) -> String {
        let index = Int(id.rawValue)
        guard index < slots.count, let node = slots[index].node else {
            return "@\(id.rawValue)(invalid)"
        }
        switch node.kind {
        case .keyPath:
            var parts: [String] = []
            var currentIndex: Int? = index
            while let i = currentIndex, let n = slots[i].node {
                if case .keyPath(let parent, let kp) = n.kind {
                    parts.append("\(kp)")
                    currentIndex = Int(parent.rawValue)
                } else {
                    break
                }
            }
            let path = parts.reversed().joined(separator: " -> ")
            return "@\(id.rawValue)(path: \(path))"
        case .rule(_, let isSideEffect):
            return "@\(id.rawValue)(\(isSideEffect ? "sideEffect" : "rule"))"
        case .stateful:
            return "@\(id.rawValue)(stateful)"
        case .input:
            return "@\(id.rawValue)(input)"
        case .crossGraphRef(let sourceAttr, let sourceGraphRef):
            let srcDesc = sourceGraphRef.value != nil ? "@\(sourceAttr.rawValue)" : "@\(sourceAttr.rawValue)(dead)"
            return "@\(id.rawValue)(crossRef->\(srcDesc))"
        case .indirect(let target):
            if let target {
                return "@\(id.rawValue)(indirect->@\(target.rawValue))"
            }
            return "@\(id.rawValue)(indirect->nil)"
        }
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

#if DEBUG
// MARK: - Removal Tombstone Debugging

// Opt-in diagnostics for bugs where an AGAttribute outlives its node removal
// or a removed slot is reused before a stale strong handle is read. The usual
// symptom is an "AGAttribute(...) is stale or invalid" / "Invalid AGAttribute"
// fatal near a structural update such as conditional rows, ForEach removal, or
// preference-node invalidation.
//
// Run with VUI_AG_RECORD_REMOVAL_TOMBSTONES=1 to retain recently removed node
// metadata: old/new seed, node kind, cached value type, dependency edges, and
// currentlyEvaluating at removal time. This does not print logs. Inspect it
// from the debugger. Add VUI_AG_RECORD_REMOVAL_STACKS=1 only when the removal
// stack is needed. Thread.callStackSymbols is expensive enough to add visible
// latency when many nodes are removed in one structural update. It caused the
// context-menu live-refresh count-6 stall after the "Removed Live" row dropped.
// If a similar stall appears only with stack collection enabled, suspect this
// instrumentation first. Keep stack capture off by default.
//
// When debugging, evaluate:
//   expr -l Swift -- graph.debugRemovedNodeTombstone(forRawValue: rawID)
//   expr -l Swift -- graph.debugRemovedNodeTombstonesSnapshot()
private let _attributeGraphRecordRemovalTombstones =
    ProcessInfo.processInfo.environment["VUI_AG_RECORD_REMOVAL_TOMBSTONES"] == "1"
private let _attributeGraphRecordRemovalStacks =
    _attributeGraphRecordRemovalTombstones &&
    ProcessInfo.processInfo.environment["VUI_AG_RECORD_REMOVAL_STACKS"] == "1"

extension AttributeGraph {
    struct RemovedNodeTombstone: Sendable {
        let seedBeforeRemoval: UInt32
        let seedAfterRemoval: UInt32
        let kindDescription: String
        let valueTypeDescription: String
        let inputs: Set<UInt32>
        let outputs: Set<UInt32>
        let staticInputs: Set<UInt32>
        let currentlyEvaluating: UInt32?
        let stack: [String]?
    }

    var debugRecordsRemovedNodeTombstones: Bool {
        _attributeGraphRecordRemovalTombstones
    }

    func debugRemovedNodeTombstone(for id: AGAttribute) -> RemovedNodeTombstone? {
        debugRemovedNodeTombstone(forRawValue: id.rawValue)
    }

    func debugRemovedNodeTombstone(forRawValue rawValue: UInt32) -> RemovedNodeTombstone? {
        removedNodeTombstones[rawValue]
    }

    func debugRemovedNodeTombstonesSnapshot() -> [UInt32: RemovedNodeTombstone] {
        removedNodeTombstones
    }

    private func recordRemovedNodeTombstone(id: AGAttribute, node: Node) {
        guard _attributeGraphRecordRemovalTombstones else { return }
        let seedBeforeRemoval = slots[Int(id.rawValue)].seed
        let tombstone = RemovedNodeTombstone(
            seedBeforeRemoval: seedBeforeRemoval,
            seedAfterRemoval: seedBeforeRemoval &+ 1,
            kindDescription: debugDescription(for: node.kind),
            valueTypeDescription: debugValueTypeDescription(for: node.value),
            inputs: node.inputs,
            outputs: node.outputs,
            staticInputs: node.staticInputs,
            currentlyEvaluating: AttributeGraph.currentlyEvaluatingNode?.rawValue,
            stack: _attributeGraphRecordRemovalStacks ? Thread.callStackSymbols : nil
        )
        removedNodeTombstones[id.rawValue] = tombstone
        removedNodeTombstoneOrder.removeAll { $0 == id.rawValue }
        removedNodeTombstoneOrder.append(id.rawValue)
        while removedNodeTombstoneOrder.count > removedNodeTombstoneLimit {
            let expiredID = removedNodeTombstoneOrder.removeFirst()
            removedNodeTombstones.removeValue(forKey: expiredID)
        }
    }

    private func debugDescription(for kind: NodeKind) -> String {
        switch kind {
        case .input:
            return "input"
        case .rule(_, let isSideEffect):
            return isSideEffect ? "sideEffectRule" : "rule"
        case .stateful(let box):
            return "stateful(\(String(describing: type(of: box))))"
        case .keyPath(let parent, let keyPath):
            return "keyPath(parent: @\(parent.rawValue), keyPath: \(keyPath))"
        case .crossGraphRef(let sourceAttr, let sourceGraphRef):
            return "crossGraphRef(source: @\(sourceAttr.rawValue), sourceGraphAlive: \(sourceGraphRef.value != nil))"
        case .indirect(let target):
            return "indirect(target: \(debugAttributeDescription(target)))"
        }
    }

    private func debugValueTypeDescription(for value: Any?) -> String {
        guard let value else { return "nil" }
        return String(describing: type(of: value))
    }

    private func debugAttributeDescription(_ id: AGAttribute?) -> String {
        if let id { return "@\(id.rawValue)" }
        return "nil"
    }
}
#endif
