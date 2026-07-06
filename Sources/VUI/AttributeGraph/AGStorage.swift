//
//  File: AGStorage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

extension _AGGraph {
    func graphCounter(lane: UInt32) -> UInt {
        switch lane {
        case 1:
            return updateCounter
        default:
            return 0
        }
    }

    func hasCachedValue(for id: AGAttribute) -> Bool {
        id._debugValidate()
        let index = Int(id.rawValue)
        guard index < slots.count else { return false }
        return slots[index].node?.value != nil
    }

    static var currentRuleContextAttribute: AGAttribute? {
        currentlyEvaluatingNode
    }

    static func withRuleContext<T>(_ attribute: AGAttribute, body: () -> T) -> T {
        _AGGraph.withCurrentlyEvaluatingNode(attribute) {
            body()
        }
    }

    // MARK: Node Factory

    func _seed(at index: UInt32) -> UInt32 {
        slots[Int(index)].seed
    }

    func _seedIfPresent(at index: UInt32) -> UInt32? {
        let i = Int(index)
        guard i < slots.count else { return nil }
        return slots[i].seed
    }

    func _isValid(index: UInt32, seed: UInt32) -> Bool {
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
    func _debugSlotStateDescription(at index: UInt32) -> String {
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
        // Reserve the all-zero weak handle as the invalid sentinel.
        slots.append(NodeSlot(seed: 1, node: nil))
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
        guard let graph = _AGGraph.current,
              let nodeID = _AGGraph.currentlyEvaluatingNode else { return nil }
        return graph.slots[Int(nodeID.rawValue)].node?.value as? V
    }

    /// Reports whether the current StatefulRule evaluation was caused by an
    /// upstream input/dependency change.
    static func currentStatefulInputsChanged() -> Bool {
        _AGGraphAnyInputsChanged()
    }

    static func _currentStatefulInputsChanged() -> Bool {
        guard let graph = _AGGraph.current,
              let nodeID = _AGGraph.currentlyEvaluatingNode else { return true }
        return graph.slots[Int(nodeID.rawValue)].node?.inputsChanged ?? true
    }

    static func currentStatefulInputChanged(_ attribute: AGAttribute) -> Bool {
        guard let graph = _AGGraph.current,
              let nodeID = _AGGraph.currentlyEvaluatingNode else { return true }
        return graph.slots[Int(nodeID.rawValue)].node?.changedInputs.contains(attribute.rawValue) ?? true
    }

    /// Called from within `StatefulRule.updateValue()` to publish the node's output value.
    ///
    /// Must be called on `_AGGraph.current` while `updateValue()` is executing.
    /// If not called during a given evaluation, the previously cached value is retained.
    static func setStatefulOutput<V>(_ value: V) {
        guard let graph = _AGGraph.current else {
            fatalError("setStatefulOutput called outside of an _AGGraph context.")
        }
        guard let nodeID = _AGGraph.currentlyEvaluatingNode else {
            fatalError("setStatefulOutput called outside of a StatefulRule.updateValue() call.")
        }
        graph.slots[Int(nodeID.rawValue)].node!.value = value
    }

    /// Creates a source-of-truth input node (e.g., @State)
    func makeInput<Value>(value: Value) -> Attribute<Value> {
        assert(_AGGraph.current === self)
        let index = allocateSlot()
        slots[Int(index)].node = Node(value: value, kind: .input, needsEvaluation: false)
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    /// Creates a computed node with a rule (e.g., a View's body or a derived property)
    func makeRule<Value>(rule: @escaping () -> Value) -> Attribute<Value> {
        assert(_AGGraph.current === self)
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
        assert(_AGGraph.current === self)
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
        assert(_AGGraph.current === self)
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
        assert(_AGGraph.current === self)
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
    // Allows a node in one _AGGraph to reactively mirror a node from another.
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
        assert(_AGGraph.current === self)
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
        notifying targetGraph: _AGGraph,
        targetNode: AGAttribute
    ) {
        let entry = CrossGraphObserver(targetGraph: targetGraph, targetNodeID: targetNode.rawValue)
        crossGraphObservers[sourceAttr.rawValue, default: []].append(entry)
    }

    /// Removes the cross-graph observer entry for `targetNode` in `targetGraph`
    /// watching `sourceAttr` in this graph. Called when the crossGraphRef node is removed.
    func removeCrossGraphObserver(
        for sourceAttr: AGAttribute,
        targetGraph: _AGGraph,
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
    /// Must be called within this graph's context (self == _AGGraph.current).
    /// The source and target graphs must be different.
    ///
    /// The returned attribute is evaluated lazily: on first read, `cachedValue(for:)` is
    /// called on `sourceGraph`. The node is automatically invalidated whenever the source
    /// node changes, `sourceGraph` enqueues a `markNeedsEvaluation` into this graph's inbox,
    /// and the inbox is drained at the start of the next `withCurrent` block.
    func makeCrossGraphRef<V>(source: Attribute<V>, in sourceGraph: _AGGraph) -> Attribute<V> {
        assert(_AGGraph.current === self,
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
        assert(_AGGraph.current === self)
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
        assert(_AGGraph.current === self)
        let index = Int(id.rawValue)
        guard slots[index].node != nil else {
            fatalError("Invalid AGAttribute @\(id.rawValue): node does not exist.")
        }

        let node = slots[index].node!

        // Cycle detection
        if node.needsEvaluation && node.isEvaluating {
            guard node.value != nil else {
                fatalError("_AGGraph: cycle detected at @\(id.rawValue) with no cached value. Call setValue(_:) on this attribute before it is first read to provide a fallback.")
            }
        }

        let shouldEvaluate = node.needsEvaluation && !node.isEvaluating

        // Implicit dependency tracking
        if let evaluator = _AGGraph.currentlyEvaluatingNode, evaluator != id {
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
        assert(_AGGraph.current === self)
        let index = Int(attribute.identifier.rawValue)
        guard slots[index].node != nil else {
            fatalError("setValue called on AGAttribute @\(attribute.identifier.rawValue) that does not exist.")
        }
        if let oldValue = slots[index].node!.value as? Value,
           _AGGraph.compareValues(oldValue, newValue, options: AGComparisonOptions(rawValue: 3)) {
            return
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
                propagateTransaction: true,
                changedInput: attribute.identifier.rawValue
            )
        }
        notifyCrossGraphObservers(for: attribute.identifier.rawValue)
        _AGGraph.changeSet?.record(attribute.identifier)
    }

    func setValue<Value>(for attribute: Attribute<Value>, to newValue: Value, transaction: Transaction = Transaction()) {
        assert(_AGGraph.current === self)
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
                propagateTransaction: true,
                changedInput: attribute.identifier.rawValue
            )
        }
        notifyCrossGraphObservers(for: attribute.identifier.rawValue)
        _AGGraph.changeSet?.record(attribute.identifier)
    }

    func invalidateAttribute(
        _ id: AGAttribute,
        transaction: Transaction? = nil,
        propagateTransaction: Bool = false
    ) {
        assert(_AGGraph.current === self)
        let index = Int(id.rawValue)
        guard let node = slots[index].node else { return }

        if case .input = node.kind {
            for outputIndex in node.outputs {
                markNeedsEvaluation(
                    AGAttribute(rawValue: outputIndex),
                    transaction: transaction,
                    propagateTransaction: propagateTransaction,
                    changedInput: id.rawValue
                )
            }
            notifyCrossGraphObservers(for: id.rawValue)
        } else {
            markNeedsEvaluation(
                id,
                transaction: transaction,
                propagateTransaction: propagateTransaction,
                changedInput: id.rawValue
            )
        }
    }

    // MARK: Dependency Graph

    private func evaluateNodeForUpdate(_ id: AGAttribute) {
        withGraphUpdateCounterIfNeeded {
            evaluateNode(id)
        }
    }

    func updateSubgraph(_ subgraph: AGSubgraph, flags: UInt32) {
        assert(_AGGraph.current === self)
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

    func willRemoveSubgraph(_ subgraph: AGSubgraph) {
        assert(_AGGraph.current === self)
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

    func didReinsertSubgraph(_ subgraph: AGSubgraph) {
        assert(_AGGraph.current === self)
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
        var activeGraphs = _AGGraph.currentlyUpdatingGraphs ?? []
        guard !activeGraphs.contains(graphID) else {
            return body()
        }
        updateCounter &+= 1
        activeGraphs.insert(graphID)
        return _AGGraph.withCurrentlyUpdatingGraphs(activeGraphs) {
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
            Update.begin()
            _AGGraph.withCurrentlyEvaluatingNode(id) {
                box.callUpdate()
            }
            slots[index].node!.needsEvaluation = false
            slots[index].node!.inputsChanged = false
            slots[index].node!.changedInputs.removeAll()
            slots[index].node!.isEvaluating = false
            Update.end()

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
            slots[index].node!.inputsChanged = false
            slots[index].node!.changedInputs.removeAll()
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
            slots[index].node!.inputsChanged = false
            slots[index].node!.changedInputs.removeAll()
            slots[index].node!.isEvaluating = false

        case .rule(let rule, _):
            // Regular computed rule: re-run the closure and store the result.
            clearInputs(for: id)
            let newValue = _AGGraph.withCurrentlyEvaluatingNode(id) {
                rule()
            }
            slots[index].node!.value = newValue
            slots[index].node!.needsEvaluation = false
            slots[index].node!.inputsChanged = false
            slots[index].node!.changedInputs.removeAll()
            slots[index].node!.isEvaluating = false

        case .indirect(let target):
            // Indirect node: clears old dynamic dep (preserves static deps), then re-reads target.
            // When target is nil, the stored default value is retained unchanged.
            clearInputs(for: id)
            if let target {
                let targetValue = _AGGraph.withCurrentlyEvaluatingNode(id) {
                    value(for: target)
                }
                slots[index].node!.value = targetValue
            }
            slots[index].node!.needsEvaluation = false
            slots[index].node!.inputsChanged = false
            slots[index].node!.changedInputs.removeAll()
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
        inputsChanged: Bool = true,
        changedInput: UInt32? = nil
    ) {
        assert(_AGGraph.current === self)
        // Iterative BFS to avoid stack overflow on deep dependency graphs.
        // Side-effect nodes are collected separately and evaluated after the BFS completes,
        // so that cascading setValue calls (from inside the side-effect rule) create their
        // own BFS + evaluation chain without interfering with the current traversal.
        var queue: [(id: UInt32, changedInput: UInt32?)] = [(startID.rawValue, changedInput)]
        var visited: Set<UInt32> = []
        var sideEffects: [UInt32] = []
        var sideEffectSet: Set<UInt32> = []
        var i = 0
        while i < queue.count {
            let (rawID, incomingChangedInput) = queue[i]
            i += 1
            let firstVisit = visited.insert(rawID).inserted
            let index = Int(rawID)
            guard var node = slots[index].node else { continue }  // freed slot, skip
            if propagateTransaction {
                node.transaction = transaction
            }
            if inputsChanged {
                node.inputsChanged = true
                if let incomingChangedInput {
                    node.changedInputs.insert(incomingChangedInput)
                }
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
            guard firstVisit else { continue }
            // Even when a node is already dirty, keep walking its outputs.
            // Structural updates can leave intermediate preference/layout nodes
            // dirty. Later source changes still need to reach side-effect refresh
            // rules that may have been evaluated and cleared in the meantime.
            queue.append(contentsOf: node.outputs.map { ($0, UInt32(index)) })
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
        try _AGGraph.withCurrentlyEvaluatingNode(nil) { try action() }
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
        assert(_AGGraph.current === self)
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
        assert(_AGGraph.current === self)
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
        assert(_AGGraph.current === self)
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
        assert(_AGGraph.current === self)
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

    func enqueue(_ action: @escaping () -> Void) {
        assert(_AGGraph.current === self)
        pendingActions.append(action)
    }

    // Executes only the actions that are queued at the moment of the call, then returns.
    // Any actions enqueued during execution are deferred to the next drainActions() call.
    // Use this variant for a single, bounded flush, e.g. at the start of a frame update.
    func drainActions() {
        assert(_AGGraph.current === self)
        let actions = pendingActions
        pendingActions.removeAll()
        actions.forEach { $0() }
    }

    // Keeps executing actions (including ones enqueued during execution) until the time
    // limit is reached, then stops. Remaining unexecuted actions stay in the queue.
    // Use this variant for a background drain loop that must yield within a deadline.
    func drainActions(timeLimit: Duration) {
        assert(_AGGraph.current === self)
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

extension _AGGraph {
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
            currentlyEvaluating: _AGGraph.currentlyEvaluatingNode?.rawValue,
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
