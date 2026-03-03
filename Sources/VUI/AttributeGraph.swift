//
//  File: AttributeGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

//  Single-threaded design — no internal synchronization.
//  The caller is responsible for ensuring that all operations on a given
//  AttributeGraph instance occur on a single thread (or equivalent serial context).

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
struct Attribute<Value> {
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

    // Only used for State/Input nodes to push new values.
    func setValue(_ newValue: Value, transaction: Transaction = Transaction()) {
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to write to an Attribute outside of an active AttributeGraph context.")
        }
        graph.setValue(for: self, to: newValue, transaction: transaction)
    }

    /// Creates a weak reference to this attribute, capturing the current generation seed.
    func asWeak(in graph: AttributeGraph) -> AGWeakAttribute {
        AGWeakAttribute(identifier: identifier.rawValue, seed: graph._seed(at: identifier.rawValue))
    }
}

/// A group of AG nodes that are created and destroyed together.
///
/// Wrap node-creation code in `Subgraph.$current.withValue(subgraph) { ... }` to
/// automatically register every node created in that scope to this subgraph.
/// Call `invalidate(graph:)` to batch-remove all registered nodes at once.
///
/// Subgraphs form a parent/child tree: a Subgraph created while another is active
/// automatically becomes its child. `invalidate(graph:)` cascades depth-first,
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
/// itemSubgraphs[id]?.invalidate(graph: graph)
/// itemSubgraphs[id] = nil
/// ```
final class Subgraph: @unchecked Sendable {
    private(set) var nodes: [AGAttribute] = []
    private(set) var children: [Subgraph] = []
    private(set) weak var parent: Subgraph? = nil

    @TaskLocal static var current: Subgraph? = nil

    init() {
        if let parent = Subgraph.current {
            parent.children.append(self)
            self.parent = parent
        }
    }

    func register(_ id: AGAttribute) {
        nodes.append(id)
    }

    func invalidate(graph: AttributeGraph) {
        children.forEach { $0.invalidate(graph: graph) }
        children.removeAll()
        nodes.forEach { graph.removeNode($0) }
        nodes.removeAll()
    }
}

class AttributeGraph: @unchecked Sendable {

    private struct Node {
        var value: Any?
        var rule: (() -> Any)?
        var needsEvaluation: Bool = true
        var isEvaluating: Bool = false  // for cycle detection

        // KeyPath node info
        var parent: AGAttribute?
        var keyPath: AnyKeyPath?

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

    final class ChangeSet: @unchecked Sendable {
        private var _ids: Set<AGAttribute> = []
        var ids: Set<AGAttribute> { _ids }
        fileprivate func record(_ id: AGAttribute) { _ids.insert(id) }
    }

    @TaskLocal static var current: AttributeGraph?
    @TaskLocal static var _changeSet: ChangeSet?
    @TaskLocal private static var currentlyEvaluatingNode: AGAttribute?

    init() {}

    var _slotCount: Int { slots.count }

    func _seed(at index: UInt32) -> UInt32 {
        slots[Int(index)].seed
    }

    func _isValid(index: UInt32, seed: UInt32) -> Bool {
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

    /// Creates a source-of-truth input node (e.g., @State)
    func makeInput<Value>(value: Value) -> Attribute<Value> {
        let index = allocateSlot()
        slots[Int(index)].node = Node(value: value, rule: nil, needsEvaluation: false)
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        Subgraph.current?.register(attr.identifier)
        return attr
    }

    /// Creates a computed node with a rule (e.g., a View's body or a derived property)
    func makeRule<Value>(rule: @escaping () -> Value) -> Attribute<Value> {
        let index = allocateSlot()
        slots[Int(index)].node = Node(value: nil, rule: rule, needsEvaluation: true)
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        Subgraph.current?.register(attr.identifier)
        return attr
    }

    /// Completely removes a node and cleans up its dependencies.
    func removeNode(_ id: AGAttribute) {
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
        if let parent = slots[index].node?.parent,
           let keyPath = slots[index].node?.keyPath {
            pathIDs.removeValue(forKey: RelativePath(parentID: parent.rawValue, keyPath: keyPath))
        }

        // 4. Invalidate: increment seed (all AGWeakAttributes pointing here are now stale),
        //    free the slot, and push index to freeList for reuse
        slots[index].seed &+= 1
        slots[index].node = nil
        freeList.append(id.rawValue)

        // 5. Mark former dependents as needing re-evaluation
        for outputIndex in outputs {
            markNeedsEvaluation(AGAttribute(rawValue: outputIndex))
        }
    }

    func value(for id: AGAttribute) -> Any? {
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
        let index = Int(attribute.identifier.rawValue)
        guard slots[index].node != nil else {
            fatalError("setValue called on AGAttribute @\(attribute.identifier.rawValue) that does not exist.")
        }
        if let oldValue = slots[index].node!.value as? Value, oldValue == newValue { return }
        slots[index].node!.value = newValue
        let outputs = slots[index].node!.outputs
        for outputIndex in outputs { markNeedsEvaluation(AGAttribute(rawValue: outputIndex)) }
        AttributeGraph._changeSet?.record(attribute.identifier)
    }

    func setValue<Value>(for attribute: Attribute<Value>, to newValue: Value, transaction: Transaction = Transaction()) {
        let index = Int(attribute.identifier.rawValue)
        guard slots[index].node != nil else {
            fatalError("setValue called on AGAttribute @\(attribute.identifier.rawValue) that does not exist.")
        }
        slots[index].node!.value = newValue
        let outputs = slots[index].node!.outputs
        for outputIndex in outputs { markNeedsEvaluation(AGAttribute(rawValue: outputIndex)) }
        AttributeGraph._changeSet?.record(attribute.identifier)
    }

    private func evaluateNode(_ id: AGAttribute) {
        let index = Int(id.rawValue)
        guard slots[index].node != nil else {
            fatalError("evaluateNode called on AGAttribute @\(id.rawValue) that does not exist.")
        }

        // KeyPath node: no rule, compute from parent via KeyPath
        // clearInputs is intentionally omitted — the dependency on the parent is fixed at
        // creation time in subscriptNode() and never changes.
        if slots[index].node!.rule == nil,
           let parent = slots[index].node!.parent,
           let kp = slots[index].node!.keyPath {
            let parentValue = value(for: parent)
            slots[index].node!.value = parentValue[keyPath: kp]
            slots[index].node!.needsEvaluation = false
            slots[index].node!.isEvaluating = false
            return
        }

        guard let rule = slots[index].node?.rule else {
            fatalError("evaluateNode called on a node with no rule — setValue must not mark input nodes dirty.")
        }

        // Clear previous dynamic inputs before re-running the rule
        clearInputs(for: id)

        let newValue = AttributeGraph.$current.withValue(self) {
            AttributeGraph.$currentlyEvaluatingNode.withValue(id) {
                rule()
            }
        }

        slots[index].node!.value = newValue
        slots[index].node!.needsEvaluation = false
        slots[index].node!.isEvaluating = false
    }

    private func markNeedsEvaluation(_ startID: AGAttribute) {
        // Iterative BFS to avoid stack overflow on deep dependency graphs.
        var queue: [UInt32] = [startID.rawValue]
        var i = 0
        while i < queue.count {
            let index = Int(queue[i]); i += 1
            guard var node = slots[index].node else { continue }  // freed slot — skip
            guard !node.needsEvaluation else { continue }          // already marked — stop propagation
            node.needsEvaluation = true
            slots[index].node = node
            queue.append(contentsOf: node.outputs)
        }
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
        let rp = RelativePath(parentID: parent.identifier.rawValue, keyPath: keyPath)

        if let existingIndex = pathIDs[rp] {
            return Attribute(AGAttribute(rawValue: existingIndex))
        }

        let index = allocateSlot()
        var node = Node(value: nil, rule: nil, needsEvaluation: true)
        node.parent = parent.identifier
        node.keyPath = keyPath
        slots[Int(index)].node = node
        pathIDs[rp] = index
        addDependency(from: AGAttribute(rawValue: index), dependsOn: parent.identifier)
        let attr = Attribute<U>(AGAttribute(rawValue: index))
        Subgraph.current?.register(attr.identifier)
        return attr
    }

    func parent(of id: AGAttribute) -> AGAttribute? {
        slots[Int(id.rawValue)].node?.parent
    }

    func keyPath(of id: AGAttribute) -> AnyKeyPath? {
        slots[Int(id.rawValue)].node?.keyPath
    }

    // Deferred action queue — closures enqueued here are executed during drainActions().
    // Use enqueue() from button handlers or event callbacks to defer state mutations
    // to the appropriate point in the frame loop.
    private var pendingActions: [() -> Void] = []

    func enqueue(_ action: @escaping () -> Void) {
        pendingActions.append(action)
    }

    // Executes and removes all pending actions that were queued at the time of the call.
    // Actions enqueued during execution are deferred to the next drainActions() call.
    func drainActions() {
        let actions = pendingActions
        pendingActions.removeAll()
        actions.forEach { $0() }
    }

    // Executes pending actions up to the given time limit, then stops.
    func drainActions(timeLimit: Duration) {
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
        if node.keyPath != nil {
            var parts: [String] = []
            var currentIndex: Int? = index
            while let i = currentIndex, let n = slots[i].node {
                if let kp = n.keyPath { parts.append("\(kp)") }
                currentIndex = n.parent.map { Int($0.rawValue) }
            }
            let path = parts.reversed().joined(separator: " → ")
            return "@\(id.rawValue)(path: \(path))"
        }
        if node.rule != nil { return "@\(id.rawValue)(rule)" }
        return "@\(id.rawValue)(input)"
    }
}
