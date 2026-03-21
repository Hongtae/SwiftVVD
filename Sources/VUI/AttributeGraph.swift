//
//  File: AttributeGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

//  Single-threaded design — no internal synchronization.
//  The caller is responsible for ensuring that all operations on a given
//  AttributeGraph instance occur on a single thread (or equivalent serial context).
//
//  All methods on AttributeGraph require that AttributeGraph.current is already bound
//  to this instance (via AttributeGraph.$current.withValue(self) { ... }) before
//  they are called. Violating this precondition causes a runtime assertion failure.

// StatefulRule

/// An AG computed node that maintains mutable state between re-evaluations.
///
/// Unlike a plain `makeRule` closure, the conforming struct is stored inside the AG node
/// and reused on each evaluation — enabling lazy initialization and conditional output updates.
///
/// Implement `updateValue()` to recompute the output. Call `AttributeGraph.setStatefulOutput(_:)`
/// inside `updateValue()` to publish a new value. If `setStatefulOutput` is not called, the
/// previously cached output is retained unchanged.
///
/// Used by view-system filters (e.g. GestureFilter, ContentShapeResponderFilter) that own
/// a lazily-initialized responder object and update only its properties on re-evaluation.
protocol StatefulRule {
    associatedtype Value
    mutating func updateValue()
}

private protocol _AnyStatefulBox: AnyObject {
    func callUpdate()
}

private class _StatefulBox<R: StatefulRule>: _AnyStatefulBox {
    var rule: R
    init(_ rule: R) { self.rule = rule }
    func callUpdate() { rule.updateValue() }
}

/// The raw identifier for an AG node — an index into the graph's slot array.
struct AGAttribute: Hashable, CustomDebugStringConvertible, Sendable {
    var rawValue: UInt32

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
    var identifier: UInt32
    var seed: UInt32

    func isValid(in graph: AttributeGraph) -> Bool {
        graph._isValid(index: identifier, seed: seed)
    }

    func toStrong() -> AGAttribute {
        AGAttribute(rawValue: identifier)
    }
}

/// A typed wrapper around an AGAttribute.
/// Marked @unchecked Sendable: stores only AGAttribute (a Sendable raw index).
/// Value type parameter is used only in method signatures; no Value is retained here.
struct Attribute<Value>: @unchecked Sendable {
    var identifier: AGAttribute

    init(_ id: AGAttribute) {
        self.identifier = id
    }

    /// Pulls the latest value from the graph, triggering evaluation if needed,
    /// and implicitly recording a dependency if another node is currently evaluating.
    var value: Value {
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to read an Attribute outside of an active AttributeGraph context.")
        }
        return graph.value(for: identifier) as! Value
    }

    // Primarily used for State/Input nodes to push new values.
    // Can also be used to inject an initial fallback value into a rule node
    // to resolve potential dependency cycles before it is first evaluated.
    func setValue(_ newValue: Value, transaction: Transaction = Transaction()) {
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to write to an Attribute outside of an active AttributeGraph context.")
        }
        graph.setValue(for: self, to: newValue, transaction: transaction)
    }

    /// Creates a weak reference to this attribute, capturing the current generation seed.
    func asWeak() -> AGWeakAttribute {
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to read an Attribute outside of an active AttributeGraph context.")
        }
        return AGWeakAttribute(identifier: identifier.rawValue, seed: graph._seed(at: identifier.rawValue))
    }
}

extension Attribute where Value: Equatable {
    func setValue(_ newValue: Value, transaction: Transaction = Transaction()) {
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to write to an Attribute outside of an active AttributeGraph context.")
        }
        graph.setValue(for: self, to: newValue, transaction: transaction)
    }
}

/// Type-erased optional wrapper around an AG node identifier.
/// Used as the backing storage for `OptionalAttribute<T>` so that
/// `OptionalAttribute` can be stored in non-generic contexts.
struct AnyOptionalAttribute {
    var identifier: AGAttribute?

    init() { identifier = nil }
    init(_ id: AGAttribute) { identifier = id }
}

/// An optional typed reference to an AG node.
/// Used for fields that may or may not have an associated AG node
/// (e.g., `_layoutComputer`, `safeAreaInsets`, `containerSize`).
struct OptionalAttribute<Value> {
    var base: AnyOptionalAttribute

    init() { base = AnyOptionalAttribute() }
    init(_ attribute: Attribute<Value>) { base = AnyOptionalAttribute(attribute.identifier) }

    var attribute: Attribute<Value>? {
        guard let id = base.identifier else { return nil }
        return Attribute(id)
    }
}

/// A group of AG nodes that are created and destroyed together.
///
/// Must be created while an AttributeGraph context is active (`AttributeGraph.current != nil`).
/// The owning AttributeGraph is captured at creation time and validated on `invalidate()`.
///
/// Wrap node-creation code in `Subgraph.$current.withValue(subgraph) { ... }` to
/// automatically register every node created in that scope to this subgraph.
/// Call `invalidate()` to batch-remove all registered nodes at once.
///
/// Subgraphs form a parent/child tree: a Subgraph created while another is active
/// automatically becomes its child. `invalidate()` cascades depth-first,
/// so invalidating a parent also destroys all descendant Subgraphs.
///
/// Typical use — ForEach item lifecycle:
/// ```swift
/// let subgraph = Subgraph()
/// Subgraph.$current.withValue(subgraph) {
///     Content._makeView(view: itemGraph, inputs: inputs)
/// }
/// itemSubgraphs[id] = subgraph
///
/// // item removed:
/// itemSubgraphs[id]?.invalidate()
/// itemSubgraphs[id]?.removeFromParent()
/// itemSubgraphs[id] = nil
/// ```
final class Subgraph: @unchecked Sendable {
    private(set) var nodes: [AGAttribute] = []
    private(set) var children: [Subgraph] = []
    private(set) weak var parent: Subgraph? = nil
    weak let graph: AttributeGraph?

    @TaskLocal static var current: Subgraph? = nil

    init() {
        guard let graph = AttributeGraph.current else {
            fatalError("Subgraph must be created within an active AttributeGraph context.")
        }
        self.graph = graph
        if let parent = Subgraph.current {
            parent.children.append(self)
            self.parent = parent
        }
    }

    func register(_ id: AGAttribute) {
        nodes.append(id)
    }

    func invalidate() {
        guard let graph = AttributeGraph.current else {
            fatalError("Subgraph.invalidate() called outside an active AttributeGraph context.")
        }
        guard graph === self.graph else {
            fatalError("Subgraph.invalidate() called from a different AttributeGraph than the one that owns this subgraph.")
        }
        children.forEach { $0.invalidate() }
        children.removeAll()
        nodes.forEach { graph.removeNode($0) }
        nodes.removeAll()
    }

    func removeFromParent() {
        parent?.children.removeAll { $0 === self }
        parent = nil
    }
}

class AttributeGraph: @unchecked Sendable {

    // Describes how a node computes its value.
    // Exactly one case is active per node — mutual exclusion is guaranteed at the type level.
    private enum NodeKind {
        // Source-of-truth node — value is written externally via setValue(_:).
        case input

        // Computed node with a plain closure rule.
        // isSideEffect = true → re-evaluated eagerly inside markNeedsEvaluation
        //   (i.e. synchronously when any input changes via setValue).
        //   Used for gesture callbacks and other fire-and-forget side effects.
        // isSideEffect = false → pull-based, evaluated lazily on first .value read.
        //
        // Cascade example (gesture callbacks):
        //   eventsAttr.setValue(events)
        //     → markNeedsEvaluation(eventRule)   [isSideEffect]
        //       → evaluateNode(eventRule)          immediately
        //         → recognizer.processEvents()
        //         → phaseAttr.setValue(.ended)
        //           → markNeedsEvaluation(callbackRule) [isSideEffect]
        //             → evaluateNode(callbackRule)       immediately
        //               → endedCallback()                ← fires here, inside setValue call stack
        case rule(() -> Any, isSideEffect: Bool)

        // StatefulRule node — the box owns the rule struct and is reused across evaluations.
        // Output is written by calling AttributeGraph.setStatefulOutput(_:) inside updateValue().
        // If setStatefulOutput is not called during a given evaluation, the previous value is kept.
        case stateful(any _AnyStatefulBox)

        // KeyPath-derived node — value is projected from a parent node via a key path.
        // The dependency on parent is fixed at creation time and never changes.
        case keyPath(parent: AGAttribute, kp: AnyKeyPath)

        var isSideEffect: Bool {
            if case .rule(_, let se) = self { return se }
            return false
        }
    }

    private struct Node {
        var value: Any?
        var kind: NodeKind
        var needsEvaluation: Bool = true
        var isEvaluating: Bool = false  // for cycle detection

        // Dependency graph edges (stored as raw slot indices)
        var inputs: Set<UInt32> = []   // Nodes this node depends on
        var outputs: Set<UInt32> = []  // Nodes that depend on this node
    }

    private struct NodeSlot {
        var seed: UInt32    // Generation counter — incremented on each removal
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

    // Contiguous slot array — index == AGAttribute.rawValue
    private var slots: ContiguousArray<NodeSlot> = []
    // Freed slot indices available for reuse
    private var freeList: [UInt32] = []
    // Cache for KeyPath-derived child nodes
    private var pathIDs: [RelativePath: UInt32] = [:]

    // Thread-safe bridge for scheduling AG invalidations from arbitrary threads.
    let inbox: AGInbox = AGInbox()

    final class ChangeSet: @unchecked Sendable {
        private var _ids: Set<AGAttribute> = []
        var ids: Set<AGAttribute> { _ids }
        fileprivate func record(_ id: AGAttribute) { _ids.insert(id) }
    }

    @TaskLocal static var current: AttributeGraph?
    @TaskLocal static var changeSet: ChangeSet?
    @TaskLocal private static var currentlyEvaluatingNode: AGAttribute?

    init() {}

    //var _slotCount: Int { slots.count }

    fileprivate func _seed(at index: UInt32) -> UInt32 {
        slots[Int(index)].seed
    }

    fileprivate func _isValid(index: UInt32, seed: UInt32) -> Bool {
        let i = Int(index)
        guard i < slots.count else { return false }
        return slots[i].seed == seed && slots[i].node != nil
    }

    private func allocateSlot() -> UInt32 {
        if let index = freeList.popLast() {
            // Reuse freed slot (seed was already incremented on removal)
            return index
        }
        let index = UInt32(slots.count)
        slots.append(NodeSlot(seed: 0, node: nil))
        return index
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
        Subgraph.current?.register(attr.identifier)
        return attr
    }

    /// Creates a source-of-truth input node (e.g., @State)
    func makeInput<Value>(value: Value) -> Attribute<Value> {
        assert(AttributeGraph.current === self)
        let index = allocateSlot()
        slots[Int(index)].node = Node(value: value, kind: .input, needsEvaluation: false)
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        Subgraph.current?.register(attr.identifier)
        return attr
    }

    /// Creates a computed node with a rule (e.g., a View's body or a derived property)
    func makeRule<Value>(rule: @escaping () -> Value) -> Attribute<Value> {
        assert(AttributeGraph.current === self)
        let index = allocateSlot()
        slots[Int(index)].node = Node(value: nil, kind: .rule(rule, isSideEffect: false))
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        Subgraph.current?.register(attr.identifier)
        return attr
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
    /// input changes — i.e. within the same `setValue` call stack, not deferred to the next
    /// layout pass.
    ///
    /// The node is registered in the current Subgraph and removed when the Subgraph is
    /// invalidated (e.g. when the owning view is removed from the tree).
    @discardableResult
    func makeSideEffectRule<Value>(rule: @escaping () -> Value) -> Attribute<Value> {
        assert(AttributeGraph.current === self)
        let index = allocateSlot()
        slots[Int(index)].node = Node(value: nil, kind: .rule(rule, isSideEffect: true))
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        Subgraph.current?.register(attr.identifier)
        // Evaluate immediately so the rule body runs once and AG records which input
        // attributes it reads — establishing the dependency edges that will trigger
        // future eager re-evaluations.
        evaluateNode(AGAttribute(rawValue: index))
        return attr
    }

    /// Completely removes a node and cleans up its dependencies.
    func removeNode(_ id: AGAttribute) {
        assert(AttributeGraph.current === self)
        let index = Int(id.rawValue)
        guard slots[index].node != nil else {
            fatalError("removeNode called on @\(id.rawValue) which does not exist — double-remove is a usage error.")
        }

        // 1. Break input connections (removes this node from its inputs' output sets)
        clearInputs(for: id)

        // 2. Collect outputs and clean up their back-references
        let outputs = slots[index].node!.outputs
        for outputIndex in outputs {
            slots[Int(outputIndex)].node?.inputs.remove(id.rawValue)
        }

        // 3. Remove from KeyPath cache if applicable
        if case .keyPath(let parent, let kp) = slots[index].node?.kind {
            pathIDs.removeValue(forKey: RelativePath(parentID: parent.rawValue, keyPath: kp))
        }

        // 4. Invalidate: increment seed (all AGWeakAttributes pointing here are now stale),
        //    free the slot, and push index to freeList for reuse
        slots[index].seed &+= 1
        slots[index].node = nil
        freeList.append(id.rawValue)

        // 5. Mark former dependents as needing re-evaluation.
        // evaluateSideEffects:false — the node is gone; side-effect rules that depended
        // on it must NOT fire now (they would crash reading a freed attribute).
        // They are simply marked dirty and will be removed or re-evaluated later.
        for outputIndex in outputs {
            markNeedsEvaluation(AGAttribute(rawValue: outputIndex), evaluateSideEffects: false)
        }
    }

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
            print("AttributeGraph: cycle detected at @\(id.rawValue), returning stale cached value.")
        }

        let shouldEvaluate = node.needsEvaluation && !node.isEvaluating

        // Implicit dependency tracking
        if let evaluator = AttributeGraph.currentlyEvaluatingNode, evaluator != id {
            addDependency(from: evaluator, dependsOn: id)
        }

        // Lazy evaluation
        if shouldEvaluate {
            slots[index].node!.isEvaluating = true
            evaluateNode(id)
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
        let outputs = slots[index].node!.outputs
        for outputIndex in outputs { markNeedsEvaluation(AGAttribute(rawValue: outputIndex)) }
        AttributeGraph.changeSet?.record(attribute.identifier)
    }

    func setValue<Value>(for attribute: Attribute<Value>, to newValue: Value, transaction: Transaction = Transaction()) {
        assert(AttributeGraph.current === self)
        let index = Int(attribute.identifier.rawValue)
        guard slots[index].node != nil else {
            fatalError("setValue called on AGAttribute @\(attribute.identifier.rawValue) that does not exist.")
        }
        slots[index].node!.value = newValue
        let outputs = slots[index].node!.outputs
        for outputIndex in outputs { markNeedsEvaluation(AGAttribute(rawValue: outputIndex)) }
        AttributeGraph.changeSet?.record(attribute.identifier)
    }

    private func evaluateNode(_ id: AGAttribute) {
        let index = Int(id.rawValue)
        guard let node = slots[index].node else {
            fatalError("evaluateNode called on AGAttribute @\(id.rawValue) that does not exist.")
        }

        switch node.kind {
        case .input:
            fatalError("evaluateNode called on an input node @\(id.rawValue) — input nodes must never be marked needsEvaluation.")

        case .stateful(let box):
            // StatefulRule node: re-evaluate the stored rule struct.
            // Dependency tracking works via currentlyEvaluatingNode (same as .rule).
            // Output is written only when updateValue() calls setStatefulOutput(_:);
            // if it doesn't, the previous cached value is retained unchanged.
            clearInputs(for: id)
            AttributeGraph.$currentlyEvaluatingNode.withValue(id) {
                box.callUpdate()
            }
            slots[index].node!.needsEvaluation = false
            slots[index].node!.isEvaluating = false

        case .keyPath(let parent, let kp):
            // KeyPath node: project value from parent via the stored key path.
            // clearInputs is intentionally omitted — the dependency on parent is fixed
            // at creation time in subscriptNode() and never changes.
            // Note: value(for: parent) runs while currentlyEvaluatingNode is still set to
            // the outer caller, so the caller also acquires a direct dependency on parent
            // (in addition to its dependency on this KeyPath node). The redundant edge is
            // cleaned up by clearInputs on the caller's next re-evaluation.
            let parentValue = value(for: parent)
            slots[index].node!.value = parentValue[keyPath: kp]
            slots[index].node!.needsEvaluation = false
            slots[index].node!.isEvaluating = false

        case .rule(let rule, _):
            // Regular computed rule — re-run the closure and store the result.
            clearInputs(for: id)
            let newValue = AttributeGraph.$currentlyEvaluatingNode.withValue(id) {
                rule()
            }
            slots[index].node!.value = newValue
            slots[index].node!.needsEvaluation = false
            slots[index].node!.isEvaluating = false
        }
    }

    /// Marks `startID` and all its transitive dependents as needing re-evaluation.
    ///
    /// - Parameter evaluateSideEffects: When `true` (default, used by `setValue`),
    ///   side-effect nodes are evaluated eagerly within this call so that callbacks
    ///   fire synchronously. When `false` (used by `removeNode`), side-effect nodes
    ///   are only marked dirty — they must NOT be evaluated because an input node
    ///   they depend on may have already been freed.
    func markNeedsEvaluation(_ startID: AGAttribute, evaluateSideEffects: Bool = true) {
        assert(AttributeGraph.current === self)
        // Iterative BFS to avoid stack overflow on deep dependency graphs.
        // Side-effect nodes are collected separately and evaluated after the BFS completes,
        // so that cascading setValue calls (from inside the side-effect rule) create their
        // own BFS + evaluation chain without interfering with the current traversal.
        var queue: [UInt32] = [startID.rawValue]
        var sideEffects: [UInt32] = []
        var i = 0
        while i < queue.count {
            let index = Int(queue[i]); i += 1
            guard var node = slots[index].node else { continue }  // freed slot — skip
            guard !node.needsEvaluation else { continue }          // already marked — stop propagation
            node.needsEvaluation = true
            slots[index].node = node
            if node.kind.isSideEffect {
                sideEffects.append(UInt32(index))
            }
            queue.append(contentsOf: node.outputs)
        }
        // Eagerly evaluate side-effect nodes in dependency order (parents before children).
        // Skipped when called from removeNode — inputs may already be freed.
        guard evaluateSideEffects else { return }
        for id in sideEffects {
            let index = Int(id)
            guard slots[index].node != nil else { continue }  // may have been freed
            guard slots[index].node!.needsEvaluation else { continue }  // already evaluated by cascade
            evaluateNode(AGAttribute(rawValue: id))
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

    private func clearInputs(for id: AGAttribute) {
        let index = Int(id.rawValue)
        guard slots[index].node != nil else {
            fatalError("clearInputs called on AGAttribute @\(id.rawValue) that does not exist.")
        }
        let oldInputs = slots[index].node!.inputs
        slots[index].node!.inputs.removeAll()
        for inputIndex in oldInputs {
            // Input node may have been removed already — optional chaining is intentional here.
            slots[Int(inputIndex)].node?.outputs.remove(id.rawValue)
        }
    }

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
        Subgraph.current?.register(attr.identifier)
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

    // Deferred action queue — closures enqueued here are executed during drainActions().
    // Use enqueue() from button handlers or event callbacks to defer state mutations
    // to the appropriate point in the frame loop.
    private var pendingActions: [() -> Void] = []

    func enqueue(_ action: @escaping () -> Void) {
        assert(AttributeGraph.current === self)
        pendingActions.append(action)
    }

    // Executes only the actions that are queued at the moment of the call, then returns.
    // Any actions enqueued during execution are deferred to the next drainActions() call.
    // Use this variant for a single, bounded flush — e.g., at the start of a frame update.
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
            let path = parts.reversed().joined(separator: " → ")
            return "@\(id.rawValue)(path: \(path))"
        case .rule(_, let isSideEffect):
            return "@\(id.rawValue)(\(isSideEffect ? "sideEffect" : "rule"))"
        case .stateful:
            return "@\(id.rawValue)(stateful)"
        case .input:
            return "@\(id.rawValue)(input)"
        }
    }
}
