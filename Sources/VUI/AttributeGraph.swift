//
//  File: AttributeGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

//  Single-threaded design — no internal synchronization.
//  The caller is responsible for ensuring that all operations on a given
//  AttributeGraph instance occur on a single thread (or equivalent serial context).

struct AttributeID: Hashable, CustomDebugStringConvertible, Sendable {
    let identifier: UInt64

    var debugDescription: String {
        if let graph = AttributeGraph.current {
            return graph.debugDescription(for: self)
        }
        return "@\(identifier)"
    }
}

/// A typed wrapper around an AttributeID, providing a safe way to interact with the untyped graph engine.
struct Attribute<Value> {
    let id: AttributeID

    init(_ id: AttributeID) {
        self.id = id
    }

    /// Pulls the latest value from the graph, triggering evaluation if needed,
    /// and implicitly recording a dependency if another node is currently evaluating.
    var value: Value {
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to read an Attribute outside of an active AttributeGraph context.")
        }
        return graph.value(for: id) as! Value
    }

    // Only used for State/Input nodes to push new values.
    func setValue(_ newValue: Value, transaction: Transaction = Transaction()) {
        guard let graph = AttributeGraph.current else {
            fatalError("Attempted to write to an Attribute outside of an active AttributeGraph context.")
        }
        graph.setValue(for: self, to: newValue, transaction: transaction)
    }
}

class AttributeGraph: @unchecked Sendable {
    // This structure merges the array-index idea of _GraphRoot with the dependency tracking of the old AttributeGraph.
    private struct Node {
        var id: AttributeID

        // Data & Evaluation
        var value: Any?
        var rule: (() -> Any)?
        var needsEvaluation: Bool = true
        var isEvaluating: Bool = false  // for cycle detection

        // Tree / Path info (inherited from _GraphRoot concept)
        // If this node represents a property, it knows its parent and KeyPath.
        var parent: AttributeID?
        var keyPath: AnyKeyPath?

        // Dependency Graph Edges
        var inputs: Set<UInt64> = []   // Nodes this node depends on (to compute its rule)
        var outputs: Set<UInt64> = []  // Nodes that depend on this node
    }

    // To support `subscript(KeyPath)` caching similar to _GraphRoot
    private struct RelativePath: Hashable {
        let parentID: UInt64
        let keyPath: AnyKeyPath
    }

    // The core memory pool. Fast O(1) dictionary access by UInt64 ID.
    private var nodes: [UInt64: Node] = [:]
    private var pathIDs: [RelativePath: UInt64] = [:]

    private var _nextIDCounter: UInt64 = 0
    private var _nextID: UInt64 {
        defer { _nextIDCounter += 1 }
        return _nextIDCounter
    }

    /// Collects AttributeIDs of input nodes whose values changed during a graph update pass.
    /// Bind this via `$_changeSet.withValue(...)` alongside `$current` before triggering updates.
    final class ChangeSet: @unchecked Sendable {
        private var _ids: Set<AttributeID> = []
        var ids: Set<AttributeID> { _ids }
        fileprivate func record(_ id: AttributeID) { _ids.insert(id) }
    }

    @TaskLocal static var current: AttributeGraph?
    @TaskLocal static var _changeSet: ChangeSet?

    // Implicit tracking context
    @TaskLocal private static var currentlyEvaluatingNode: AttributeID?

    init() {
    }

    /// Creates a source-of-truth input node (e.g., @State)
    func makeInput<Value>(value: Value) -> Attribute<Value> {
        let id = AttributeID(identifier: _nextID)
        nodes[id.identifier] = Node(id: id, value: value, rule: nil, needsEvaluation: false)
        return Attribute(id)
    }

    /// Creates a computed node with a rule (e.g., a View's body or a derived property)
    func makeRule<Value>(rule: @escaping () -> Value) -> Attribute<Value> {
        let id = AttributeID(identifier: _nextID)
        nodes[id.identifier] = Node(id: id, value: nil, rule: rule, needsEvaluation: true)
        return Attribute(id)
    }

    /// Completely removes a node and cleans up its dependencies.
    func removeNode(_ id: AttributeID) {
        let idValue = id.identifier
        guard nodes[idValue] != nil else { return }

        // 1. Break connections (inputs & outputs)
        clearInputs(for: id)

        // 2. Collect outputs, clean up their back-references, and remove the node.
        guard let node = nodes[idValue] else {
            fatalError("Node @\(idValue) disappeared during removal — removeNode called twice is a usage error.")
        }
        let outputs = node.outputs
        for outputID in outputs {
            nodes[outputID]?.inputs.remove(idValue)
        }
        // If this is a KeyPath node, also remove it from the pathIDs cache
        if let parent = node.parent, let keyPath = node.keyPath {
            let rp = RelativePath(parentID: parent.identifier, keyPath: keyPath)
            pathIDs.removeValue(forKey: rp)
        }
        nodes.removeValue(forKey: idValue)

        // 3. Mark former outputs as needing re-evaluation — their dependency is now gone.
        for outputID in outputs {
            markNeedsEvaluation(AttributeID(identifier: outputID))
        }
    }

    func setValue<Value: Equatable>(for attribute: Attribute<Value>, to newValue: Value, transaction: Transaction = Transaction()) {
        let idValue = attribute.id.identifier
        guard let node = nodes[idValue] else {
            fatalError("setValue called on an AttributeID @\(idValue) that does not exist in this graph.")
        }
        if let oldValue = node.value as? Value, oldValue == newValue { return }
        nodes[idValue]!.value = newValue
        let outputs = node.outputs
        for outputID in outputs { markNeedsEvaluation(AttributeID(identifier: outputID)) }
        AttributeGraph._changeSet?.record(attribute.id)
    }

    func setValue<Value>(for attribute: Attribute<Value>, to newValue: Value, transaction: Transaction = Transaction()) {
        let idValue = attribute.id.identifier
        guard nodes[idValue] != nil else {
            fatalError("setValue called on an AttributeID @\(idValue) that does not exist in this graph.")
        }
        nodes[idValue]!.value = newValue
        let outputs = nodes[idValue]!.outputs
        for outputID in outputs { markNeedsEvaluation(AttributeID(identifier: outputID)) }
        AttributeGraph._changeSet?.record(attribute.id)
    }

    func value(for id: AttributeID) -> Any? {
        let idValue = id.identifier
        guard let node = nodes[idValue] else {
            fatalError("Invalid AttributeID")
        }

        // Cycle detection
        if node.needsEvaluation && node.isEvaluating {
            print("AttributeGraph: cycle detected through attribute @\(id.identifier)")
        }

        let shouldEvaluate = node.needsEvaluation && !node.isEvaluating

        // 1. Implicit Dependency Tracking
        if let evaluator = AttributeGraph.currentlyEvaluatingNode, evaluator != id {
            addDependency(from: evaluator, dependsOn: id)
        }

        // 2. Lazy Evaluation
        if shouldEvaluate {
            nodes[idValue]?.isEvaluating = true
            evaluateNode(id)
        }

        return nodes[idValue]?.value
    }

    private func evaluateNode(_ id: AttributeID) {
        let idValue = id.identifier

        guard let node = nodes[idValue] else {
            fatalError("evaluateNode called on an AttributeID @\(idValue) that does not exist in this graph.")
        }

        // If it's a structural KeyPath node without a direct rule, compute from parent
        if node.rule == nil, let parent = node.parent, let kp = node.keyPath {
            let parentValue = value(for: parent)
            nodes[idValue]?.value = parentValue[keyPath: kp]
            nodes[idValue]?.needsEvaluation = false
            nodes[idValue]?.isEvaluating = false
            return
        }

        guard let rule = node.rule else {
            fatalError("evaluateNode called on a node with no rule — setValue must not mark input nodes dirty.")
        }

        // Clear previous inputs before running the rule, as branches might have changed
        clearInputs(for: id)

        // Execute the rule within the task-local context.
        // Any `value(for:)` called inside here will be tracked.
        // `$current` is explicitly propagated so rules can access the graph without relying on the caller's context.
        let newValue = AttributeGraph.$current.withValue(self) {
            AttributeGraph.$currentlyEvaluatingNode.withValue(id) {
                rule()
            }
        }

        nodes[idValue]?.value = newValue
        nodes[idValue]?.needsEvaluation = false
        nodes[idValue]?.isEvaluating = false
    }

    private func markNeedsEvaluation(_ id: AttributeID) {
        let idValue = id.identifier
        guard let node = nodes[idValue] else { return }  // Node already removed — skip silently
        guard !node.needsEvaluation else { return }      // Already marked — stop propagation
        nodes[idValue]!.needsEvaluation = true

        // Recurse to dependents
        for outputID in node.outputs {
            markNeedsEvaluation(AttributeID(identifier: outputID))
        }
    }

    private func addDependency(from parent: AttributeID, dependsOn child: AttributeID) {
        let parentIDValue = parent.identifier
        let childIDValue = child.identifier

        guard nodes[parentIDValue] != nil else {
            fatalError("addDependency: parent node @\(parentIDValue) does not exist in this graph.")
        }
        guard nodes[childIDValue] != nil else {
            fatalError("addDependency: child node @\(childIDValue) does not exist in this graph.")
        }
        nodes[parentIDValue]!.inputs.insert(childIDValue)
        nodes[childIDValue]!.outputs.insert(parentIDValue)
    }

    private func clearInputs(for id: AttributeID) {
        let idValue = id.identifier
        guard let node = nodes[idValue] else {
            fatalError("clearInputs called on an AttributeID @\(idValue) that does not exist in this graph.")
        }
        let oldInputs = node.inputs
        nodes[idValue]!.inputs.removeAll()
        for inputIDValue in oldInputs {
            // Input node may have been removed already — optional chaining is intentional here.
            nodes[inputIDValue]?.outputs.remove(idValue)
        }
    }

    /// Dynamically creates or retrieves a child node representing a property accessed via KeyPath
    func subscriptNode<T, U>(parent: Attribute<T>, keyPath: KeyPath<T, U>) -> Attribute<U> {
        let rp = RelativePath(parentID: parent.id.identifier, keyPath: keyPath)

        if let existingIDValue = pathIDs[rp] {
            return Attribute(AttributeID(identifier: existingIDValue))
        }

        let newID = AttributeID(identifier: _nextID)
        var node = Node(id: newID, value: nil, rule: nil, needsEvaluation: true)
        node.parent = parent.id
        node.keyPath = keyPath
        nodes[newID.identifier] = node
        pathIDs[rp] = newID.identifier
        addDependency(from: newID, dependsOn: parent.id)
        return Attribute(newID)
    }

    /// Returns the parent AttributeID of the given node, or nil if it has no parent.
    func parent(of id: AttributeID) -> AttributeID? {
        nodes[id.identifier]?.parent
    }

    /// Returns the KeyPath from the parent node to this node, or nil if it has no parent.
    func keyPath(of id: AttributeID) -> AnyKeyPath? {
        nodes[id.identifier]?.keyPath
    }

    // Deferred action queue — closures enqueued here are executed during drainActions().
    // Use enqueue() from button handlers or event callbacks to defer state mutations
    // to the appropriate point in the frame loop.
    private var pendingActions: [() -> Void] = []

    // Appends a closure to the pending action queue.
    func enqueue(_ action: @escaping () -> Void) {
        pendingActions.append(action)
    }

    // Executes and removes all pending actions.
    // Actions enqueued during execution are also drained in the same call.
    func drainActions() {
        let actions = pendingActions
        pendingActions.removeAll()
        actions.forEach { $0() }
    }

    // Executes pending actions up to the given time limit, then stops.
    // Useful for spreading heavy deferred work across frames.
    func drainActions(timeLimit: Duration) {
        let deadline = ContinuousClock.now + timeLimit
        while !pendingActions.isEmpty {
            if ContinuousClock.now >= deadline { return }
            pendingActions.removeFirst()()
        }
    }

    // Returns a debug string for the given node without triggering evaluation.
    func debugDescription(for id: AttributeID) -> String {
        guard let node = nodes[id.identifier] else {
            return "@\(id.identifier)(invalid)"
        }
        if node.keyPath != nil {
            // Build absolute path by walking up the parent chain
            var parts: [String] = []
            var current: Node? = node
            while let n = current {
                if let kp = n.keyPath {
                    parts.append("\(kp)")
                }
                current = n.parent.flatMap { nodes[$0.identifier] }
            }
            let path = parts.reversed().joined(separator: " → ")
            return "@\(id.identifier)(path: \(path))"
        }
        if node.rule != nil {
            return "@\(id.identifier)(rule)"
        }
        return "@\(id.identifier)(input)"
    }
}
