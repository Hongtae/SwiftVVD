//
//  File: AGStorage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

private struct _AGUpdateFrame {
    var id: UInt32
    var afterInputs: Bool
}

private final class _AGUpdateWorkList {
    var frames: [_AGUpdateFrame]

    init() {
        frames = []
        frames.reserveCapacity(64)
    }

    func popLast() -> _AGUpdateFrame? {
        frames.popLast()
    }

    func append(_ id: UInt32, afterInputs: Bool) {
        frames.append(_AGUpdateFrame(id: id, afterInputs: afterInputs))
    }
}

private enum _AGUpdateAction {
    case none
    case evaluate(AGAttribute, Int)
    case finish(AGAttribute, Int)
}

extension _AGGraph {
    private static func valueStorageFactory<Value>(
        for type: Value.Type
    ) -> (Any) -> any _AnyAGValueStorage {
        { value in
            guard let value = value as? Value else {
                fatalError("Attribute value type changed after node creation.")
            }
            return _AGValueStorage(value)
        }
    }

    private static func valueComparator<Value>(
        for type: Value.Type,
        mode: AGComparisonMode = AGComparisonMode(rawValue: 3)
    ) -> (any _AnyAGValueStorage, any _AnyAGValueStorage) -> Bool {
        let options = AGComparisonOptions(mode: mode)
        return { lhs, rhs in
            guard let lhs = lhs as? _AGValueStorage<Value>,
                  let rhs = rhs as? _AGValueStorage<Value> else {
                return false
            }
            return compareStoredValues(lhs.pointer, rhs.pointer, options: options)
        }
    }

    private func makeValueStorage<Value>(
        _ value: Value,
        for id: AGAttribute
    ) -> any _AnyAGValueStorage {
        let expectedType = attributeInfos[id.rawValue]?.valueType
        if let expectedType,
           ObjectIdentifier(expectedType) == ObjectIdentifier(Value.self) {
            return _AGValueStorage(value)
        }
        guard let node = slots[Int(id.rawValue)].node else {
            fatalError("makeValueStorage called on AGAttribute @\(id.rawValue) that does not exist.")
        }
        return node.makeValueStorage(value)
    }

    @discardableResult
    func publishComputedValue<Value>(_ value: Value, for id: AGAttribute) -> Bool {
        let index = Int(id.rawValue)
        guard let node = slots[index].node else {
            fatalError("publishComputedValue called on AGAttribute @\(id.rawValue) that does not exist.")
        }
        let newValue = makeValueStorage(value, for: id)
        let changed = node.value.map { !node.valuesEqual($0, newValue) } ?? true
        slots[index].node!.value = newValue
        if changed {
            slots[index].node!.valueVersion &+= 1
        }
        return changed
    }

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

    func valueState(for id: AGAttribute) -> AGValueState {
        assert(_AGGraph.current === self)
        id._debugValidate()
        let index = Int(id.rawValue)
        guard index < slots.count, let node = slots[index].node else {
            fatalError("valueState(for:) called on AGAttribute @\(id.rawValue) that does not exist.")
        }

        var rawValue: UInt32 = 0
        if node.needsEvaluation { rawValue |= 1 << 0 }
        if node.isEvaluating { rawValue |= 1 << 1 }
        if node.inputsChanged { rawValue |= 1 << 2 }
        if node.value != nil { rawValue |= 1 << 3 }
        if node.forceEvaluation { rawValue |= 1 << 4 }
        if node.inputs.contains(where: {
            $0.flags & InputEdge.changed != 0
        }) {
            rawValue |= 1 << 5
        }
        if node.transaction != nil { rawValue |= 1 << 6 }
        return AGValueState(rawValue: rawValue)
    }

    func hasNode(_ id: AGAttribute) -> Bool {
        let index = Int(id.rawValue)
        return slots.indices.contains(index) && slots[index].node != nil
    }

    func setSubgraph(_ subgraph: AGSubgraphRef, for id: AGAttribute) {
        nodeSubgraphs[id.rawValue] = WeakObject(subgraph)
        let index = Int(id.rawValue)
        if slots.indices.contains(index),
           let node = slots[index].node,
           node.needsEvaluation {
            subgraph.markPending(flags: node.flags.rawValue)
        }
    }

    func subgraph(for id: AGAttribute) -> AGSubgraphRef? {
        nodeSubgraphs[id.rawValue]?.value
    }

    func flags(for id: AGAttribute) -> AGAttributeFlags {
        assert(_AGGraph.current === self)
        guard let node = slots[Int(id.rawValue)].node else {
            fatalError("flags(for:) called on AGAttribute @\(id.rawValue) that does not exist.")
        }
        return node.flags
    }

    func setFlags(
        _ flags: AGAttributeFlags,
        mask: AGAttributeFlags,
        for id: AGAttribute
    ) {
        assert(_AGGraph.current === self)
        let index = Int(id.rawValue)
        guard slots[index].node != nil else {
            fatalError("setFlags(_:mask:for:) called on AGAttribute @\(id.rawValue) that does not exist.")
        }
        let old = slots[index].node!.flags.rawValue
        let newFlags = (old & ~mask.rawValue) | (flags.rawValue & mask.rawValue)
        slots[index].node!.flags = AGAttributeFlags(rawValue: newFlags)
        if slots[index].node!.needsEvaluation {
            subgraph(for: id)?.markPending(flags: newFlags)
        }
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

    private func registerAttributeInfo<Value>(
        at index: UInt32,
        valueType: Value.Type,
        body: (any _AnyAttributeBodyBox)? = nil
    ) {
        attributeInfos[index] = AttributeInfo(valueType: valueType, body: body)
    }

    func bodyType(for id: AGAttribute) -> Any.Type {
        assert(_AGGraph.current === self)
        guard let body = attributeInfos[id.rawValue]?.body else {
            fatalError("AGAttribute @\(id.rawValue) does not have a stored attribute body.")
        }
        return body.bodyType
    }

    func bodyPointer(for id: AGAttribute) -> UnsafeRawPointer {
        assert(_AGGraph.current === self)
        guard let body = attributeInfos[id.rawValue]?.body else {
            fatalError("AGAttribute @\(id.rawValue) does not have a stored attribute body.")
        }
        return UnsafeRawPointer(body.bodyPointer)
    }

    func valueType(for id: AGAttribute) -> Any.Type {
        assert(_AGGraph.current === self)
        guard let valueType = attributeInfos[id.rawValue]?.valueType else {
            fatalError("AGAttribute @\(id.rawValue) does not have registered value metadata.")
        }
        return valueType
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
        return graph.slots[Int(nodeID.rawValue)].node?.value?.anyValue as? V
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
        return graph.inputChanged(
            attribute.rawValue,
            forNodeAt: Int(nodeID.rawValue)
        )
    }

    func valueAndFlags<Value>(
        for input: Attribute<Value>,
        relativeTo context: AGAttribute?,
        options: AGValueOptions
    ) -> (value: Value, flags: AGChangedValueFlags) {
        assert(_AGGraph.current === self)

        // Native option bit 2 routes a context read through the direct-value
        // path instead of installing an input edge. The Swift graph uses the
        // same boundary for dependency-isolated reads.
        if options.rawValue & 0x4 != 0 {
            let value = _AGGraph.withoutTracking {
                self.value(for: input.identifier) as! Value
            }
            return (value, AGChangedValueFlags(rawValue: 0))
        }

        let result: (Value, Bool)
        if context == nil || _AGGraph.currentlyEvaluatingNode == context {
            let value = self.value(for: input.identifier) as! Value
            let changed = context.map {
                self.inputChanged(
                    input.identifier.rawValue,
                    forNodeAt: Int($0.rawValue)
                )
            } ?? true
            result = (value, changed)
        } else {
            result = _AGGraph.withRuleContext(context!) {
                let value = self.value(for: input.identifier) as! Value
                let changed = self.inputChanged(
                    input.identifier.rawValue,
                    forNodeAt: Int(context!.rawValue)
                )
                return (value, changed)
            }
        }
        return (
            result.0,
            AGChangedValueFlags(rawValue: result.1 ? 1 : 0)
        )
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
        graph.publishComputedValue(value, for: nodeID)
    }

    /// Creates a source-of-truth input node (e.g., @State)
    func makeInput<Value>(value: Value) -> Attribute<Value> {
        assert(_AGGraph.current === self)
        let index = allocateSlot()
        let body = _LowLevelAttributeBox(
            body: _External(),
            flags: _External.flags,
            update: { _, _ in }
        )
        slots[Int(index)].node = Node(
            value: _AGValueStorage(value),
            makeValueStorage: Self.valueStorageFactory(for: Value.self),
            valuesEqual: Self.valueComparator(
                for: Value.self,
                mode: _External.comparisonMode
            ),
            kind: .input,
            needsEvaluation: false
        )
        registerAttributeInfo(at: index, valueType: Value.self, body: body)
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    /// Creates an external input slot without an initialized value.
    func makeInput<Value>(type: Value.Type) -> Attribute<Value> {
        assert(_AGGraph.current === self)
        let index = allocateSlot()
        let body = _LowLevelAttributeBox(
            body: _External(),
            flags: _External.flags,
            update: { _, _ in }
        )
        slots[Int(index)].node = Node(
            value: nil,
            makeValueStorage: Self.valueStorageFactory(for: Value.self),
            valuesEqual: Self.valueComparator(
                for: Value.self,
                mode: _External.comparisonMode
            ),
            kind: .input,
            needsEvaluation: false
        )
        registerAttributeInfo(at: index, valueType: Value.self, body: body)
        let attribute = Attribute<Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attribute.identifier)
        return attribute
    }

    /// Creates a computed node with a rule (e.g., a View's body or a derived property)
    func makeRule<Value>(rule: @escaping () -> Value) -> Attribute<Value> {
        assert(_AGGraph.current === self)
        let index = allocateSlot()
        let box = _RuleClosureBox(rule: rule, isSideEffect: false)
        slots[Int(index)].node = Node(
            value: nil,
            makeValueStorage: Self.valueStorageFactory(for: Value.self),
            valuesEqual: Self.valueComparator(for: Value.self),
            kind: .rule(box)
        )
        registerAttributeInfo(at: index, valueType: Value.self)
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    /// Creates a computed node backed by a Rule struct (pure, stateless).
    func makeRule<R: Rule>(_ rule: R) -> Attribute<R.Value> {
        makeRule(rule, initialValue: R.initialValue)
    }

    func makeRule<R: Rule>(
        _ rule: R,
        initialValue: R.Value
    ) -> Attribute<R.Value> {
        makeRule(rule, initialValue: Optional(initialValue))
    }

    func cachedRuleValue<R: Rule & Hashable>(
        for rule: R,
        options: AGCachedValueOptions,
        owner: AGAttribute?,
        hashValue: Int,
        createIfMissing: Bool
    ) -> UnsafePointer<R.Value>? {
        assert(_AGGraph.current === self)
        _ = options
        // A supplied owner selects its subgraph. Otherwise the active update's
        // attribute subgraph wins, followed by the explicitly current subgraph.
        // Options affect the read/input edge and are not part of cache identity.
        let cacheSubgraph = owner.flatMap(subgraph(for:))
            ?? Self.currentlyEvaluatingNode.flatMap(subgraph(for:))
            ?? AGSubgraphRef.current
        let key = CachedRuleKey(
            subgraph: cacheSubgraph.map(ObjectIdentifier.init),
            ruleHashValue: hashValue,
            body: AnyHashable(rule)
        )

        if let entry = cachedRuleEntries[key] {
            if !entry.attribute.isValid(in: self) {
                cachedRuleEntries.removeValue(forKey: key)
            } else {
                guard let typedEntry = entry as? TypedCachedRuleEntry<R.Value> else {
                    fatalError("Cached Rule value type changed for an identical cache key.")
                }
                let attribute = Attribute<R.Value>(identifier: entry.attribute.toStrong())
                guard createIfMissing || hasCachedValue(for: attribute.identifier) else {
                    return nil
                }
                typedEntry.store(attribute.value)
                return typedEntry.pointer
            }
        }

        guard createIfMissing else { return nil }
        let attribute = AGSubgraphRef.withCurrent(cacheSubgraph) {
            makeRule(rule)
        }
        let value = attribute.value
        let entry = TypedCachedRuleEntry(
            attribute: attribute.asWeak().base,
            value: value
        )
        cachedRuleEntries[key] = entry
        return entry.pointer
    }

    private func makeRule<R: Rule>(
        _ rule: R,
        initialValue: R.Value?
    ) -> Attribute<R.Value> {
        assert(_AGGraph.current === self)
        let index = allocateSlot()
        let box = _RuleBox(rule)
        slots[Int(index)].node = Node(
            value: initialValue.map(_AGValueStorage.init),
            makeValueStorage: Self.valueStorageFactory(for: R.Value.self),
            valuesEqual: Self.valueComparator(
                for: R.Value.self,
                mode: R.comparisonMode
            ),
            kind: .ruleBody(box),
            forceEvaluation: initialValue != nil
        )
        registerAttributeInfo(at: index, valueType: R.Value.self, body: box)
        let attr = Attribute<R.Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    func makeLowLevelAttribute<Body: _AttributeBody, Value>(
        body: Body,
        value: Value?,
        flags: AGAttributeTypeFlags,
        update: @escaping (UnsafeMutableRawPointer, AGAttribute) -> Void
    ) -> Attribute<Value> {
        assert(_AGGraph.current === self)
        let index = allocateSlot()
        let box = _LowLevelAttributeBox(
            body: body,
            flags: flags,
            update: update
        )
        slots[Int(index)].node = Node(
            value: value.map(_AGValueStorage.init),
            makeValueStorage: Self.valueStorageFactory(for: Value.self),
            valuesEqual: Self.valueComparator(
                for: Value.self,
                mode: Body.comparisonMode
            ),
            kind: .lowLevelBody(box),
            forceEvaluation: value != nil
        )
        registerAttributeInfo(at: index, valueType: Value.self, body: box)
        let attribute = Attribute<Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attribute.identifier)
        return attribute
    }

    func mutateRule<R: Rule>(
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
        guard case .ruleBody(let box) = node.kind,
              let typedBox = box as? _RuleBox<R> else {
            return
        }
        typedBox.mutateRule(body)
        if invalidating {
            markNeedsEvaluation(id)
        }
    }

    func mutateBody<Body>(
        _ id: AGAttribute,
        as type: Body.Type,
        invalidating: Bool,
        _ body: (inout Body) -> Void
    ) {
        assert(_AGGraph.current === self)
        let index = Int(id.rawValue)
        guard index < slots.count,
              slots[index].node != nil else {
            fatalError("mutateBody called on AGAttribute @\(id.rawValue) that does not exist.")
        }

        let didMutate = attributeInfos[id.rawValue]?.body?.mutateBody(
            as: type,
            body
        ) ?? false
        guard didMutate else {
            fatalError("mutateBody type mismatch for AGAttribute @\(id.rawValue).")
        }
        if invalidating {
            invalidateAttribute(id)
        }
    }

    func visitBody<Visitor: AttributeBodyVisitor>(
        _ id: AGAttribute,
        visitor: inout Visitor
    ) {
        assert(_AGGraph.current === self)
        let index = Int(id.rawValue)
        guard index < slots.count, slots[index].node != nil else {
            fatalError("visitBody called on AGAttribute @\(id.rawValue) that does not exist.")
        }
        guard let body = attributeInfos[id.rawValue]?.body else {
            fatalError("visitBody requires an attribute backed by a stored Swift body.")
        }
        body.visitBody(&visitor)
    }

    /// Creates a computed AG node backed by a `StatefulRule`.
    ///
    /// The rule struct is stored inside the node and reused across re-evaluations.
    /// Use this instead of `makeRule` when the rule needs to lazily initialize a persistent
    /// object (e.g. a ViewResponder) and update only its properties on subsequent calls.
    func makeStatefulRule<R: StatefulRule>(_ rule: R) -> Attribute<R.Value> {
        makeStatefulRule(rule, initialValue: R.initialValue)
    }

    func makeStatefulRule<R: StatefulRule>(
        _ rule: R,
        initialValue: R.Value
    ) -> Attribute<R.Value> {
        makeStatefulRule(rule, initialValue: Optional(initialValue))
    }

    private func makeStatefulRule<R: StatefulRule>(
        _ rule: R,
        initialValue: R.Value?
    ) -> Attribute<R.Value> {
        assert(_AGGraph.current === self)
        let index = allocateSlot()
        let box = _StatefulBox(rule)
        slots[Int(index)].node = Node(
            value: initialValue.map(_AGValueStorage.init),
            makeValueStorage: Self.valueStorageFactory(for: R.Value.self),
            valuesEqual: Self.valueComparator(
                for: R.Value.self,
                mode: R.comparisonMode
            ),
            kind: .stateful(box),
            forceEvaluation: initialValue != nil
        )
        registerAttributeInfo(at: index, valueType: R.Value.self, body: box)
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
        typedBox.mutateRule(body)
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
    /// The rule is evaluated once upon creation to register its AG dependencies. If creation
    /// occurs during an active graph update, it joins that graph-local update work list.
    ///
    /// The node is registered in the current AGSubgraph and removed when the AGSubgraph is
    /// invalidated (e.g. when the owning view is removed from the tree).
    @discardableResult
    func makeSideEffectRule<Value>(rule: @escaping () -> Value) -> Attribute<Value> {
        assert(_AGGraph.current === self)
        let index = allocateSlot()
        let box = _RuleClosureBox(rule: rule, isSideEffect: true)
        slots[Int(index)].node = Node(
            value: nil,
            makeValueStorage: Self.valueStorageFactory(for: Value.self),
            valuesEqual: Self.valueComparator(for: Value.self),
            kind: .rule(box)
        )
        registerAttributeInfo(at: index, valueType: Value.self)
        let attr = Attribute<Value>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        scheduleSideEffectEvaluation(AGAttribute(rawValue: index))
        return attr
    }

    private func enqueuePendingSideEffectEvaluation(_ id: AGAttribute) {
        if pendingSideEffectEvaluationSet.insert(id.rawValue).inserted {
            pendingSideEffectEvaluations.append(id.rawValue)
        }
    }

    private func drainPendingSideEffectEvaluations() {
        while !pendingSideEffectEvaluations.isEmpty {
            let pending = pendingSideEffectEvaluations
            pendingSideEffectEvaluations.removeAll(keepingCapacity: true)
            pendingSideEffectEvaluationSet.removeAll(keepingCapacity: true)

            for rawID in pending {
                let index = Int(rawID)
                guard index < slots.count,
                      slots[index].node?.kind.isSideEffect == true,
                      slots[index].node?.needsEvaluation == true else {
                    continue
                }
                evaluateSideEffectIfNeeded(AGAttribute(rawValue: rawID))
            }
        }
    }

    func requestSubgraphInvalidation(_ subgraph: AGSubgraphRef) {
        guard subgraph._beginInvalidation() else {
            return
        }
        if isUpdatingOnCurrentThread {
            pendingSubgraphInvalidations.append(subgraph)
        } else {
            subgraph._finishInvalidation()
        }
    }

    @discardableResult
    private func drainPendingSubgraphInvalidations() -> Bool {
        var didInvalidate = false
        while !pendingSubgraphInvalidations.isEmpty {
            let pending = pendingSubgraphInvalidations
            pendingSubgraphInvalidations.removeAll(keepingCapacity: true)
            for subgraph in pending {
                subgraph._finishInvalidation()
                didInvalidate = true
            }
        }
        return didInvalidate
    }

    private func evaluateSideEffectIfNeeded(_ id: AGAttribute) {
        withGraphUpdateCounterIfNeeded {
            evaluateNodeForUpdate(id)
        }
    }

    private func scheduleSideEffectEvaluation(_ id: AGAttribute) {
        // Do not start a second graph's first evaluation from inside another
        // graph's update stack. Its next top-level update drains this queue.
        let hasActiveGraphUpdate = _AGGraph.currentlyUpdatingGraphs?.isEmpty == false
        if hasActiveGraphUpdate {
            enqueuePendingSideEffectEvaluation(id)
        } else {
            evaluateSideEffectIfNeeded(id)
        }
    }

    // MARK: - Cross-Graph Reference
    // Allows a node in one graph to reactively observe a node from another.
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
    func cachedValue(for id: AGAttribute) -> Any {
        let index = Int(id.rawValue)
        guard let node = slots[index].node else {
            fatalError("cachedValue: node @\(id.rawValue) does not exist in source graph.")
        }
        guard let cached = node.value else {
            fatalError("cachedValue: node @\(id.rawValue) has no cached value; source graph must evaluate first.")
        }
        return cached.anyValue
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
    private func notifyCrossGraphObservers(
        for sourceNodeID: UInt32,
        transaction: Transaction? = nil
    ) {
        guard var entries = crossGraphObservers[sourceNodeID] else { return }
        var hasDeadEntries = false
        for entry in entries {
            guard let targetGraph = entry.targetGraph else {
                hasDeadEntries = true
                continue
            }
            let targetNodeID = entry.targetNodeID
            let transactionBox = transaction.map(UnsafeBox.init)
            targetGraph.inbox.enqueue(transaction: transaction) { [weak targetGraph] in
                let transaction = transactionBox?.value
                targetGraph?.markNeedsEvaluation(
                    AGAttribute(rawValue: targetNodeID),
                    transaction: transaction,
                    propagateTransaction: transaction != nil
                )
            }
        }
        if hasDeadEntries {
            entries.removeAll { $0.targetGraph == nil }
            crossGraphObservers[sourceNodeID] = entries.isEmpty ? nil : entries
        }
    }

    /// Creates a cross-graph proxy node that observes a node from `sourceGraph`.
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
            makeValueStorage: Self.valueStorageFactory(for: V.self),
            valuesEqual: Self.valueComparator(for: V.self),
            kind: .crossGraphRef(
                sourceAttr: source.identifier,
                sourceGraph: WeakObject(sourceGraph)
            )
        )
        registerAttributeInfo(at: index, valueType: V.self)
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

        attributeInfos[id.rawValue]?.body?.callDestroy()

        // 1. Break input connections (removes one reverse output record for
        // each input record).
        clearInputs(for: id, includingPermanent: true)

        // 2. Collect outputs and clean up their back-references.
        let outputs = Set(slots[index].node!.outputs)
        for outputIndex in outputs {
            removeInputEdges(
                fromNodeAt: Int(outputIndex),
                matching: id.rawValue
            )
        }

        // 3. Remove from KeyPath cache / cross-graph observer registry if applicable
        switch slots[index].node?.kind {
        case .keyPath(let parent, let kp):
            pathIDs.removeValue(forKey: RelativePath(parentID: parent.rawValue, keyPath: kp))
        case .offset(let parent, let byteOffset, let valueType, _):
            offsetPathIDs.removeValue(forKey: RelativeOffsetPath(
                parentID: parent.rawValue,
                byteOffset: byteOffset,
                valueType: valueType
            ))
        case .rawOffset(let parent, let byteOffset):
            rawOffsetPathIDs.removeValue(forKey: RawOffsetPath(
                parentID: parent.rawValue,
                byteOffset: byteOffset
            ))
        case .crossGraphRef(let sourceAttr, let sourceGraphRef):
            // Unregister from the source graph's observer list so it stops notifying us.
            sourceGraphRef.value?.removeCrossGraphObserver(
                for: sourceAttr, targetGraph: self, targetNode: id)
        default:
            break
        }
        indirectDefaultSources.removeValue(forKey: id.rawValue)
        indirectDependencies.removeValue(forKey: id.rawValue)
        nodeSubgraphs.removeValue(forKey: id.rawValue)
        attributeInfos.removeValue(forKey: id.rawValue)
        cachedRuleEntries = cachedRuleEntries.filter {
            $0.value.attribute.identifier != id.rawValue
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

    func value(for id: AGAttribute) -> Any {
        assert(_AGGraph.current === self)
        let evaluator = _AGGraph.currentlyEvaluatingNode
        let preparedRead = prepareValueRead(
            id,
            evaluator: evaluator,
            recordsDynamicInput: true
        )
        if preparedRead.needsUpdate {
            updateValueForRead(id)
        }
        recordValueRead(
            id,
            evaluator: evaluator,
            edgeIndex: preparedRead.edgeIndex
        )
        return cachedValueAfterRead(id)
    }

    private func valueForPermanentInput(
        _ id: AGAttribute,
        evaluator: AGAttribute
    ) -> Any {
        let preparedRead = prepareValueRead(
            id,
            evaluator: evaluator,
            recordsDynamicInput: false
        )
        if preparedRead.needsUpdate {
            updateValueForRead(id)
        }
        recordValueRead(
            id,
            evaluator: evaluator,
            edgeIndex: preparedRead.edgeIndex
        )
        return cachedValueAfterRead(id)
    }

    @inline(never)
    private func prepareValueRead(
        _ id: AGAttribute,
        evaluator: AGAttribute?,
        recordsDynamicInput: Bool
    ) -> (needsUpdate: Bool, edgeIndex: Int?) {
        let index = Int(id.rawValue)
        guard slots.indices.contains(index), slots[index].node != nil else {
            fatalError("Invalid AGAttribute @\(id.rawValue): node does not exist.")
        }
        if slots[index].node!.needsEvaluation
            && slots[index].node!.isEvaluating
            && slots[index].node!.value == nil {
            fatalError("_AGGraph: cycle detected at @\(id.rawValue) with no cached value. Call setValue(_:) on this attribute before it is first read to provide a fallback.")
        }
        let edgeIndex: Int?
        if let evaluator, evaluator != id {
            if recordsDynamicInput {
                edgeIndex = markDynamicInputRead(
                    from: evaluator,
                    dependsOn: id
                )
            } else {
                edgeIndex = matchingInputEdgeIndex(
                    inNodeAt: Int(evaluator.rawValue),
                    attribute: id.rawValue,
                    identityFlags: InputEdge.permanent
                )
                guard edgeIndex != nil else {
                    fatalError(
                        "Missing permanent input edge from " +
                        "@\(evaluator.rawValue) to @\(id.rawValue)."
                    )
                }
            }
        } else {
            edgeIndex = nil
        }
        return (
            slots[index].node!.needsEvaluation
                && !slots[index].node!.isEvaluating,
            edgeIndex
        )
    }

    @inline(never)
    private func updateValueForRead(_ id: AGAttribute) {
        if isUpdatingOnCurrentThread {
            // A value read during evaluation enters its own update traversal
            // and returns to the preceding traversal afterward.
            updateNodeIfNeeded(id)
        } else {
            withGraphUpdateCounterIfNeeded {
                updateNodeIfNeeded(id)
            }
        }
    }

    @inline(never)
    private func recordValueRead(
        _ id: AGAttribute,
        evaluator: AGAttribute?,
        edgeIndex: Int?
    ) {
        guard let evaluator,
              evaluator != id,
              let edgeIndex else {
            return
        }
        let evaluatorIndex = Int(evaluator.rawValue)
        let inputIndex = Int(id.rawValue)
        guard slots.indices.contains(evaluatorIndex),
              slots[evaluatorIndex].node != nil,
              slots.indices.contains(inputIndex),
              slots[inputIndex].node != nil else {
            return
        }
        guard slots[evaluatorIndex].node!.inputs.indices.contains(edgeIndex),
              slots[evaluatorIndex].node!.inputs[edgeIndex].attribute
                == id.rawValue else {
            fatalError(
                "Missing input edge from @\(evaluator.rawValue) to @\(id.rawValue)."
            )
        }
        slots[evaluatorIndex].node!.inputs[edgeIndex].valueVersion =
            slots[inputIndex].node!.valueVersion
    }

    @inline(never)
    private func cachedValueAfterRead(_ id: AGAttribute) -> Any {
        guard let value = slots[Int(id.rawValue)].node?.value else {
            fatalError("AGAttribute @\(id.rawValue) has no value after evaluation.")
        }
        return value.anyValue
    }

    @discardableResult
    func setValue<Value: Equatable>(
        for attribute: Attribute<Value>,
        to newValue: Value,
        transaction: Transaction = Transaction(),
        evaluateSideEffects: Bool = true
    ) -> Bool {
        assert(_AGGraph.current === self)
        let index = Int(attribute.identifier.rawValue)
        guard slots[index].node != nil else {
            fatalError("setValue called on AGAttribute @\(attribute.identifier.rawValue) that does not exist.")
        }
        let storedValue = makeValueStorage(newValue, for: attribute.identifier)
        if let oldValue = slots[index].node!.value,
           slots[index].node!.valuesEqual(oldValue, storedValue) {
            return false
        }
        slots[index].node!.value = storedValue
        slots[index].node!.valueVersion &+= 1
        Transaction.ThreadStorage.markMutation(for: transaction)
        let transactionToPropagate = transaction.isEmpty ? nil : transaction
        slots[index].node!.transaction = transactionToPropagate
        let outputs = slots[index].node!.outputs
        // Mark every outgoing edge before an eager side effect can pull a
        // shared downstream node. Otherwise a diamond path can evaluate that
        // node before its direct changed-input edge has been recorded.
        markOutputsNeedEvaluation(
            outputs,
            evaluateSideEffects: evaluateSideEffects,
            transaction: transactionToPropagate,
            propagateTransaction: true,
            changedInput: attribute.identifier.rawValue,
            forceStarts: false
        )
        notifyCrossGraphObservers(
            for: attribute.identifier.rawValue,
            transaction: transactionToPropagate
        )
        _AGGraph.changeSet?.record(attribute.identifier)
        return true
    }

    @discardableResult
    func setValue<Value>(
        for attribute: Attribute<Value>,
        to newValue: Value,
        transaction: Transaction = Transaction(),
        evaluateSideEffects: Bool = true
    ) -> Bool {
        assert(_AGGraph.current === self)
        let index = Int(attribute.identifier.rawValue)
        guard let node = slots[index].node else {
            fatalError("setValue called on AGAttribute @\(attribute.identifier.rawValue) that does not exist.")
        }
        let storedValue = makeValueStorage(newValue, for: attribute.identifier)
        if let oldValue = node.value,
           node.valuesEqual(oldValue, storedValue) {
            return false
        }
        slots[index].node!.value = storedValue
        slots[index].node!.valueVersion &+= 1
        Transaction.ThreadStorage.markMutation(for: transaction)
        let transactionToPropagate = transaction.isEmpty ? nil : transaction
        slots[index].node!.transaction = transactionToPropagate
        let outputs = slots[index].node!.outputs
        markOutputsNeedEvaluation(
            outputs,
            evaluateSideEffects: evaluateSideEffects,
            transaction: transactionToPropagate,
            propagateTransaction: true,
            changedInput: attribute.identifier.rawValue,
            forceStarts: false
        )
        notifyCrossGraphObservers(
            for: attribute.identifier.rawValue,
            transaction: transactionToPropagate
        )
        _AGGraph.changeSet?.record(attribute.identifier)
        return true
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
            markOutputsNeedEvaluation(
                node.outputs,
                transaction: transaction,
                propagateTransaction: propagateTransaction,
                changedInput: id.rawValue,
                forceStarts: true
            )
            notifyCrossGraphObservers(for: id.rawValue, transaction: transaction)
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
        let index = Int(id.rawValue)
        guard slots[index].node != nil else { return }
        // Eager side effects can be invalidated by a dependency that mutates
        // while the side effect is still reading it. The current evaluation
        // already observes that dependency's completed value, so do not enter
        // the same side effect recursively.
        guard !slots[index].node!.isEvaluating else { return }
        slots[index].node!.isEvaluating = true
        if isUpdatingOnCurrentThread {
            evaluateNode(id)
        } else {
            withGraphUpdateCounterIfNeeded {
                evaluateNode(id)
            }
        }
    }

    private func updateNodeIfNeeded(_ rootID: AGAttribute) {
        let traversal = beginUpdateTraversal()
        let workList = _AGUpdateWorkList()
        let context = _AGUpdateContext(
            predecessor: _AGGraph.currentUpdateContext
        )

        _AGGraph.withCurrentUpdateContext(context) {
            updateNodeIfNeeded(
                rootID,
                traversal: traversal,
                workList: workList,
                context: context
            )
        }
    }

    private func updateNodeIfNeeded(
        _ rootID: AGAttribute,
        traversal: UInt64,
        workList: _AGUpdateWorkList,
        context: _AGUpdateContext
    ) {
        workList.append(rootID.rawValue, afterInputs: false)
        while !context.isCancelled, let frame = workList.popLast() {
            switch nextUpdateAction(
                for: frame,
                traversal: traversal,
                workList: workList
            ) {
            case .none:
                continue
            case .evaluate(let id, let index):
                evaluateNodeForUpdate(id)
                completeUpdateTraversal(index: index, traversal: traversal)
            case .finish(let id, let index):
                finishEvaluationWithoutUpdating(id)
                completeUpdateTraversal(index: index, traversal: traversal)
            }
        }
    }

    private func updateSubgraphNodeBatch(
        _ nodes: ContiguousArray<AGAttribute>
    ) {
        guard !nodes.isEmpty else { return }
        let traversal = beginUpdateTraversal()
        let workList = _AGUpdateWorkList()
        let context = _AGUpdateContext(
            predecessor: _AGGraph.currentUpdateContext
        )

        _AGGraph.withCurrentUpdateContext(context) {
            for node in nodes {
                guard !context.isCancelled else { break }
                updateNodeIfNeeded(
                    node,
                    traversal: traversal,
                    workList: workList,
                    context: context
                )
            }
        }
    }

    @inline(never)
    private func beginUpdateTraversal() -> UInt64 {
        updateTraversal &+= 1
        if updateTraversal == 0 {
            for index in slots.indices where slots[index].node != nil {
                slots[index].node!.updateTraversal = 0
                slots[index].node!.updateTraversalState = 0
            }
            updateTraversal = 1
        }
        return updateTraversal
    }

    @inline(never)
    private func nextUpdateAction(
        for frame: _AGUpdateFrame,
        traversal: UInt64,
        workList: _AGUpdateWorkList
    ) -> _AGUpdateAction {
        let index = Int(frame.id)
        guard slots.indices.contains(index), slots[index].node != nil else {
            return .none
        }

        if frame.afterInputs {
            guard slots[index].node!.needsEvaluation else {
                completeUpdateTraversal(index: index, traversal: traversal)
                return .none
            }
            if nodeRequiresEvaluation(index: index) {
                return .evaluate(AGAttribute(rawValue: frame.id), index)
            }
            return .finish(AGAttribute(rawValue: frame.id), index)
        }

        guard slots[index].node!.needsEvaluation else {
            completeUpdateTraversal(index: index, traversal: traversal)
            return .none
        }
        if slots[index].node!.isEvaluating
            || (slots[index].node!.updateTraversal == traversal
                && slots[index].node!.updateTraversalState == 1) {
            guard slots[index].node!.value != nil else {
                fatalError("_AGGraph: cycle detected at @\(frame.id) with no cached value. Call setValue(_:) on this attribute before it is first read to provide a fallback.")
            }
            return .none
        }

        slots[index].node!.updateTraversal = traversal
        slots[index].node!.updateTraversalState = 1
        workList.append(frame.id, afterInputs: true)
        for input in slots[index].node!.inputs {
            workList.append(input.attribute, afterInputs: false)
        }
        return .none
    }

    @inline(never)
    private func nodeRequiresEvaluation(index: Int) -> Bool {
        if slots[index].node!.forceEvaluation
            || slots[index].node!.value == nil {
            return true
        }
        for input in slots[index].node!.inputs {
            guard let currentVersion =
                    slots[Int(input.attribute)].node?.valueVersion,
                  input.valueVersion == currentVersion else {
                return true
            }
        }
        return false
    }

    @inline(never)
    private func completeUpdateTraversal(index: Int, traversal: UInt64) {
        guard slots.indices.contains(index), slots[index].node != nil else {
            return
        }
        slots[index].node!.updateTraversal = traversal
        slots[index].node!.updateTraversalState = 2
    }

    private func finishEvaluationWithoutUpdating(_ id: AGAttribute) {
        let index = Int(id.rawValue)
        guard slots[index].node != nil else { return }
        slots[index].node!.needsEvaluation = false
        slots[index].node!.forceEvaluation = false
        slots[index].node!.inputsChanged = false
        clearChangedInputFlags(forNodeAt: index)
        slots[index].node!.isEvaluating = false
    }

    func updateSubgraph(_ subgraph: AGSubgraph, flags: UInt32) {
        assert(_AGGraph.current === self)
        guard flags != 0, subgraph.isValid else { return }
        withGraphUpdateCounterIfNeeded {
            repeat {
                updatePendingSubgraphs(from: subgraph, flags: flags)
            } while subgraph.hasPending(flags: flags)
        }
    }

    private func updatePendingSubgraphs(
        from root: AGSubgraph,
        flags: UInt32
    ) {
        var work: [AGSubgraph] = [root]
        var visited: Set<ObjectIdentifier> = []

        while let subgraph = work.popLast() {
            guard subgraph.isValid,
                  visited.insert(ObjectIdentifier(subgraph)).inserted else {
                continue
            }

            inbox.drain()
            while subgraph.consumeLocalPendingFlags(matching: flags) != 0 {
                // Registration appends locally, while update work consumes the
                // newest registered node first.
                var selectedNodes: ContiguousArray<AGAttribute> = []
                for node in subgraph.nodes.reversed() {
                    guard let liveNode = weakAttributeIfValid(for: node)?.toStrong() else {
                        continue
                    }
                    guard let liveStorage = slots[Int(liveNode.rawValue)].node,
                          liveStorage.flags.rawValue & flags != 0,
                          liveStorage.needsEvaluation else {
                        continue
                    }
                    selectedNodes.append(liveNode)
                }
                updateSubgraphNodeBatch(selectedNodes)
                guard subgraph.isValid else { break }
            }

            guard subgraph.isValid,
                  subgraph.consumeDescendantPendingFlags(matching: flags) != 0 else {
                continue
            }
            for child in subgraph.children {
                if child.hasPending(flags: flags) {
                    work.append(child)
                }
            }
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
        let result = _AGGraph.withCurrentlyUpdatingGraphs(activeGraphs) {
            let result = body()
            drainPendingSideEffectEvaluations()
            return result
        }
        if drainPendingSubgraphInvalidations() {
            drainActionOutbox()
        }
        return result
    }

    var isUpdatingOnCurrentThread: Bool {
        _AGGraph.currentlyUpdatingGraphs?.contains(ObjectIdentifier(self)) == true
    }

    private func evaluateNode(_ id: AGAttribute) {
        let index = Int(id.rawValue)
        guard slots[index].node != nil else {
            fatalError("evaluateNode called on AGAttribute @\(id.rawValue) that does not exist.")
        }

        if case .input = slots[index].node!.kind {
            fatalError("evaluateNode called on an input node @\(id.rawValue); input nodes must never be marked needsEvaluation.")
        }

        beginInputEvaluation(forNodeAt: index)
        _AGGraph.withCurrentlyEvaluatingNode(id) {
            evaluateNodeBody(id, index: index)
        }
    }

    private func evaluateNodeBody(_ id: AGAttribute, index: Int) {
        switch slots[index].node!.kind {
        case .input:
            preconditionFailure("input evaluation was rejected before entering the rule context")

        case .stateful(let box):
            evaluateStatefulNode(id, index: index, box: box)

        case .lowLevelBody(let box):
            evaluateLowLevelBodyNode(id, index: index, box: box)

        case .keyPath(let parent, let kp):
            evaluateKeyPathNode(id, index: index, parent: parent, keyPath: kp)

        case .offset(let parent, _, _, let project):
            evaluateOffsetNode(id, index: index, parent: parent, project: project)

        case .rawOffset(let parent, _):
            evaluateRawOffsetNode(id, index: index, parent: parent)

        case .crossGraphRef(let sourceAttr, let sourceGraphRef):
            evaluateCrossGraphNode(
                id,
                index: index,
                source: sourceAttr,
                sourceGraph: sourceGraphRef
            )

        case .ruleBody(let box):
            evaluateRuleBodyNode(id, index: index, box: box)

        case .rule(let box):
            evaluateRuleNode(id, index: index, box: box)

        case .indirect(let target, let defaultValue):
            evaluateIndirectNode(
                id,
                index: index,
                target: target,
                defaultValue: defaultValue
            )
        }
    }

    @inline(never)
    private func evaluateStatefulNode(
        _ id: AGAttribute,
        index: Int,
        box: any _AnyStatefulBox
    ) {
        // A stateful body publishes output explicitly. If it does not publish,
        // the previous cached value remains unchanged.
        Update.begin()
        box.callUpdate()
        finishNodeEvaluation(index: index)
        Update.end()
    }

    @inline(never)
    private func evaluateLowLevelBodyNode(
        _ id: AGAttribute,
        index: Int,
        box: any _AnyLowLevelAttributeBox
    ) {
        Update.begin()
        box.callUpdate(attribute: id)
        finishNodeEvaluation(index: index)
        Update.end()
    }

    @inline(never)
    private func evaluateKeyPathNode(
        _ id: AGAttribute,
        index: Int,
        parent: AGAttribute,
        keyPath: AnyKeyPath
    ) {
        // The parent edge is fixed at construction and is not cleared here.
        let parentValue = valueForPermanentInput(parent, evaluator: id)
        publishComputedValue(parentValue[keyPath: keyPath], for: id)
        finishNodeEvaluation(index: index)
    }

    @inline(never)
    private func evaluateOffsetNode(
        _ id: AGAttribute,
        index: Int,
        parent: AGAttribute,
        project: (Any) -> Any
    ) {
        let parentValue = valueForPermanentInput(parent, evaluator: id)
        publishComputedValue(project(parentValue), for: id)
        finishNodeEvaluation(index: index)
    }

    @inline(never)
    private func evaluateRawOffsetNode(
        _ id: AGAttribute,
        index: Int,
        parent: AGAttribute
    ) {
        _ = valueForPermanentInput(parent, evaluator: id)
        // Raw offsets carry dependency state but no readable cached value.
        slots[index].node!.valueVersion &+= 1
        finishNodeEvaluation(index: index)
    }

    @inline(never)
    private func evaluateCrossGraphNode(
        _ id: AGAttribute,
        index: Int,
        source: AGAttribute,
        sourceGraph: WeakObject<_AGGraph>
    ) {
        if let graph = sourceGraph.value {
            publishComputedValue(graph.cachedValue(for: source), for: id)
        }
        finishNodeEvaluation(index: index)
    }

    @inline(never)
    private func evaluateRuleBodyNode(
        _ id: AGAttribute,
        index: Int,
        box: any _AnyRuleBox
    ) {
        box.publishValue(to: self, for: id)
        finishNodeEvaluation(index: index)
    }

    @inline(never)
    private func evaluateRuleNode(
        _ id: AGAttribute,
        index: Int,
        box: any _AnyRuleClosureBox
    ) {
        box.publishValue(to: self, for: id)
        finishNodeEvaluation(index: index)
    }

    @inline(never)
    private func evaluateIndirectNode(
        _ id: AGAttribute,
        index: Int,
        target: AGAttribute?,
        defaultValue: Any?
    ) {
        if let target {
            publishComputedValue(value(for: target), for: id)
        } else if let defaultValue {
            publishComputedValue(defaultValue, for: id)
        } else {
            slots[index].node!.value = nil
        }
        finishNodeEvaluation(index: index)
    }

    @inline(__always)
    private func finishNodeEvaluation(index: Int) {
        if _AGGraph.currentUpdateContext?.isCancelled == true {
            // A cancelled body may still publish a cached value, but its
            // evaluation is not final. Preserve input-change state and force
            // the next pull to retry the body before downstream work resumes.
            slots[index].node!.needsEvaluation = true
            slots[index].node!.forceEvaluation = true
            slots[index].node!.isEvaluating = false
            let id = AGAttribute(rawValue: UInt32(index))
            subgraph(for: id)?.markPending(
                flags: slots[index].node!.flags.rawValue
            )
            return
        }
        finishInputEvaluation(forNodeAt: index)
        slots[index].node!.needsEvaluation = false
        slots[index].node!.forceEvaluation = false
        slots[index].node!.inputsChanged = false
        slots[index].node!.isEvaluating = false
    }

    /// Marks `startID` and all its transitive dependents as needing re-evaluation.
    ///
    /// - Parameter evaluateSideEffects: When `true`, side-effect nodes are evaluated
    ///   eagerly within this call so that callbacks fire synchronously. When `false`,
    ///   side-effect nodes are only marked dirty for later graph evaluation. Node
    ///   removal also uses the deferred form because an input may already be freed.
    func markNeedsEvaluation(
        _ startID: AGAttribute,
        evaluateSideEffects: Bool = true,
        transaction: Transaction? = nil,
        propagateTransaction: Bool = false,
        inputsChanged: Bool = true,
        changedInput: UInt32? = nil,
        forceStart: Bool = true
    ) {
        assert(_AGGraph.current === self)
        var queue: [(id: UInt32, changedInput: UInt32?)] = [
            (startID.rawValue, changedInput)
        ]
        markNeedsEvaluation(
            queue: &queue,
            forcedStart: forceStart ? startID.rawValue : nil,
            forcedStarts: nil,
            evaluateSideEffects: evaluateSideEffects,
            transaction: transaction,
            propagateTransaction: propagateTransaction,
            inputsChanged: inputsChanged
        )
    }

    private func markOutputsNeedEvaluation(
        _ startIDs: ContiguousArray<UInt32>,
        evaluateSideEffects: Bool = true,
        transaction: Transaction? = nil,
        propagateTransaction: Bool = false,
        inputsChanged: Bool = true,
        changedInput: UInt32? = nil,
        forceStarts: Bool
    ) {
        guard !startIDs.isEmpty else { return }
        var queue: [(id: UInt32, changedInput: UInt32?)] = []
        queue.reserveCapacity(max(64, startIDs.count))
        for startID in startIDs {
            queue.append((startID, changedInput))
        }
        let forcedStartIDs = forceStarts ? Set(startIDs) : nil
        markNeedsEvaluation(
            queue: &queue,
            forcedStart: nil,
            forcedStarts: forcedStartIDs,
            evaluateSideEffects: evaluateSideEffects,
            transaction: transaction,
            propagateTransaction: propagateTransaction,
            inputsChanged: inputsChanged
        )
    }

    private func markNeedsEvaluation(
        queue: inout [(id: UInt32, changedInput: UInt32?)],
        forcedStart: UInt32?,
        forcedStarts: Set<UInt32>?,
        evaluateSideEffects: Bool,
        transaction: Transaction?,
        propagateTransaction: Bool,
        inputsChanged: Bool
    ) {
        // Iterative BFS to avoid stack overflow on deep dependency graphs.
        // Side-effect nodes are collected separately and evaluated after the BFS completes,
        // so that cascading setValue calls (from inside the side-effect rule) create their
        // own BFS + evaluation chain without interfering with the current traversal.
        queue.reserveCapacity(64)
        var sideEffects: [UInt32] = []
        invalidationTraversal &+= 1
        if invalidationTraversal == 0 {
            for index in slots.indices where slots[index].node != nil {
                slots[index].node!.invalidationTraversal = 0
            }
            invalidationTraversal = 1
        }
        let traversal = invalidationTraversal
        let initialCount = queue.count
        var readIndex = 0
        var writeIndex = 0
        while readIndex < initialCount {
            let (rawID, incomingChangedInput) = queue[readIndex]
            readIndex += 1
            let index = Int(rawID)
            guard slots.indices.contains(index),
                  slots[index].node != nil else {
                continue
            }
            if inputsChanged, let incomingChangedInput {
                markInputChanged(
                    incomingChangedInput,
                    forNodeAt: index
                )
            }
            guard slots[index].node!.invalidationTraversal != traversal else {
                continue
            }
            slots[index].node!.invalidationTraversal = traversal
            queue[writeIndex] = (rawID, nil)
            writeIndex += 1
        }
        if writeIndex < queue.count {
            queue.removeSubrange(writeIndex...)
        }

        var i = 0
        while i < queue.count {
            let rawID = queue[i].id
            i += 1
            let index = Int(rawID)
            guard slots.indices.contains(index), slots[index].node != nil else {
                continue
            }
            if propagateTransaction {
                slots[index].node!.transaction = transaction
            }
            if inputsChanged {
                slots[index].node!.inputsChanged = true
            }
            if !slots[index].node!.needsEvaluation {
                slots[index].node!.needsEvaluation = true
            }
            if let subgraph = subgraph(for: AGAttribute(rawValue: rawID)) {
                subgraph.markPending(flags: slots[index].node!.flags.rawValue)
            }
            if rawID == forcedStart || forcedStarts?.contains(rawID) == true {
                slots[index].node!.forceEvaluation = true
            }
            if slots[index].node!.kind.isSideEffect {
                sideEffects.append(UInt32(index))
            }
            // Even when a node is already dirty, keep walking its outputs.
            // Structural updates can leave intermediate preference/layout nodes
            // dirty. Later source changes still need to reach side-effect refresh
            // rules that may have been evaluated and cleared in the meantime.
            for output in slots[index].node!.outputs {
                let outputIndex = Int(output)
                guard slots.indices.contains(outputIndex),
                      slots[outputIndex].node != nil else {
                    continue
                }
                if inputsChanged {
                    markInputChanged(
                        UInt32(index),
                        forNodeAt: outputIndex
                    )
                }
                guard slots[outputIndex].node!.invalidationTraversal
                        != traversal else {
                    continue
                }
                slots[outputIndex].node!.invalidationTraversal = traversal
                queue.append((output, nil))
            }
            // Propagate to cross-graph proxy nodes watching this node.
            notifyCrossGraphObservers(
                for: UInt32(index),
                transaction: propagateTransaction ? transaction : nil
            )
        }
        // Eagerly evaluate side-effect nodes in dependency order (parents before children).
        // Skipped when called from removeNode. Inputs may already be freed.
        guard evaluateSideEffects else { return }
        for id in sideEffects {
            let index = Int(id)
            guard slots[index].node != nil else { continue }  // may have been freed
            guard slots[index].node!.needsEvaluation else { continue }  // already evaluated by cascade
            scheduleSideEffectEvaluation(AGAttribute(rawValue: id))
        }
    }

    /// Executes `action` without recording any AG dependencies.
    /// Use when calling user-provided callbacks from inside a rule body to prevent
    /// the callback's side-reads (e.g. `@State` getter, `@Observable` access) from
    /// accidentally becoming inputs of the enclosing rule.
    static func withoutTracking<R>(_ action: () throws -> R) rethrows -> R {
        try _AGGraph.withCurrentlyEvaluatingNode(nil) { try action() }
    }

    private func lowerBoundInputEdgeIndex(
        inNodeAt nodeIndex: Int,
        attribute: UInt32
    ) -> Int {
        guard slots.indices.contains(nodeIndex),
              slots[nodeIndex].node != nil else {
            fatalError("Input-edge lookup requires a live node.")
        }
        var lower = 0
        var upper = slots[nodeIndex].node!.inputs.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if slots[nodeIndex].node!.inputs[middle].attribute < attribute {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func matchingInputEdgeIndex(
        inNodeAt nodeIndex: Int,
        attribute: UInt32,
        identityFlags: UInt8
    ) -> Int? {
        guard slots.indices.contains(nodeIndex),
              slots[nodeIndex].node != nil else {
            return nil
        }
        var index = lowerBoundInputEdgeIndex(
            inNodeAt: nodeIndex,
            attribute: attribute
        )
        let identity = identityFlags & InputEdge.identityMask
        while index < slots[nodeIndex].node!.inputs.count,
              slots[nodeIndex].node!.inputs[index].attribute == attribute {
            if slots[nodeIndex].node!.inputs[index].flags
                & InputEdge.identityMask == identity {
                return index
            }
            index += 1
        }
        return nil
    }

    @discardableResult
    private func insertInputEdge(
        from parent: AGAttribute,
        dependsOn child: AGAttribute,
        flags: UInt8
    ) -> Int {
        let parentIndex = Int(parent.rawValue)
        let childIndex = Int(child.rawValue)
        guard slots[parentIndex].node != nil else {
            fatalError("insertInputEdge: parent node @\(parent.rawValue) does not exist.")
        }
        guard slots[childIndex].node != nil else {
            fatalError("insertInputEdge: child node @\(child.rawValue) does not exist.")
        }
        let insertionIndex = lowerBoundInputEdgeIndex(
            inNodeAt: parentIndex,
            attribute: child.rawValue
        )
        let edge = InputEdge(
            attribute: child.rawValue,
            flags: flags,
            valueVersion: slots[childIndex].node!.valueVersion
        )
        slots[parentIndex].node!.inputs.insert(edge, at: insertionIndex)
        slots[childIndex].node!.outputs.append(parent.rawValue)
        return insertionIndex
    }

    @discardableResult
    private func markDynamicInputRead(
        from parent: AGAttribute,
        dependsOn child: AGAttribute
    ) -> Int {
        let parentIndex = Int(parent.rawValue)
        if let edgeIndex = matchingInputEdgeIndex(
            inNodeAt: parentIndex,
            attribute: child.rawValue,
            identityFlags: 0
        ) {
            slots[parentIndex].node!.inputs[edgeIndex].flags |=
                InputEdge.readThisEvaluation
            return edgeIndex
        }
        return insertInputEdge(
            from: parent,
            dependsOn: child,
            flags: InputEdge.readThisEvaluation
        )
    }

    private func addPermanentDependency(
        from parent: AGAttribute,
        dependsOn child: AGAttribute
    ) {
        _ = insertInputEdge(
            from: parent,
            dependsOn: child,
            flags: InputEdge.permanent
        )
    }

    private func inputChanged(
        _ input: UInt32,
        forNodeAt nodeIndex: Int
    ) -> Bool {
        guard slots.indices.contains(nodeIndex),
              slots[nodeIndex].node != nil else {
            return true
        }
        var index = lowerBoundInputEdgeIndex(
            inNodeAt: nodeIndex,
            attribute: input
        )
        while index < slots[nodeIndex].node!.inputs.count,
              slots[nodeIndex].node!.inputs[index].attribute == input {
            if slots[nodeIndex].node!.inputs[index].flags
                & InputEdge.changed != 0 {
                return true
            }
            index += 1
        }
        return false
    }

    private func markInputChanged(
        _ input: UInt32,
        forNodeAt nodeIndex: Int
    ) {
        guard slots.indices.contains(nodeIndex),
              slots[nodeIndex].node != nil else {
            return
        }
        var index = lowerBoundInputEdgeIndex(
            inNodeAt: nodeIndex,
            attribute: input
        )
        while index < slots[nodeIndex].node!.inputs.count,
              slots[nodeIndex].node!.inputs[index].attribute == input {
            slots[nodeIndex].node!.inputs[index].flags |= InputEdge.changed
            index += 1
        }
    }

    private func clearChangedInputFlags(forNodeAt nodeIndex: Int) {
        guard slots.indices.contains(nodeIndex),
              slots[nodeIndex].node != nil else {
            return
        }
        for index in slots[nodeIndex].node!.inputs.indices {
            slots[nodeIndex].node!.inputs[index].flags &=
                ~InputEdge.changed
        }
    }

    private func beginInputEvaluation(forNodeAt nodeIndex: Int) {
        guard slots.indices.contains(nodeIndex),
              slots[nodeIndex].node != nil else {
            return
        }
        for index in slots[nodeIndex].node!.inputs.indices {
            slots[nodeIndex].node!.inputs[index].flags &=
                ~InputEdge.readThisEvaluation
        }
    }

    private func finishInputEvaluation(forNodeAt nodeIndex: Int) {
        guard slots.indices.contains(nodeIndex),
              slots[nodeIndex].node != nil else {
            return
        }
        var index = 0
        while index < slots[nodeIndex].node!.inputs.count {
            let flags = slots[nodeIndex].node!.inputs[index].flags
            if flags & (InputEdge.permanent | InputEdge.readThisEvaluation) != 0 {
                slots[nodeIndex].node!.inputs[index].flags &=
                    ~(InputEdge.readThisEvaluation | InputEdge.changed)
                index += 1
            } else {
                removeInputEdge(fromNodeAt: nodeIndex, at: index)
            }
        }
    }

    private func removeOutputEdge(
        fromNodeAt nodeIndex: Int,
        matching output: UInt32
    ) {
        guard slots.indices.contains(nodeIndex),
              slots[nodeIndex].node != nil,
              let outputIndex =
                slots[nodeIndex].node!.outputs.firstIndex(of: output) else {
            return
        }
        let lastIndex = slots[nodeIndex].node!.outputs.index(
            before: slots[nodeIndex].node!.outputs.endIndex
        )
        if outputIndex != lastIndex {
            slots[nodeIndex].node!.outputs[outputIndex] =
                slots[nodeIndex].node!.outputs[lastIndex]
        }
        slots[nodeIndex].node!.outputs.removeLast()
    }

    private func removeInputEdge(
        fromNodeAt nodeIndex: Int,
        at edgeIndex: Int
    ) {
        let input = slots[nodeIndex].node!.inputs[edgeIndex].attribute
        let output = UInt32(nodeIndex)
        slots[nodeIndex].node!.inputs.remove(at: edgeIndex)
        removeOutputEdge(fromNodeAt: Int(input), matching: output)
    }

    private func removeInputEdges(
        fromNodeAt nodeIndex: Int,
        matching input: UInt32,
        identityFlags: UInt8? = nil
    ) {
        guard slots.indices.contains(nodeIndex),
              slots[nodeIndex].node != nil else {
            return
        }
        var index = lowerBoundInputEdgeIndex(
            inNodeAt: nodeIndex,
            attribute: input
        )
        let identity = identityFlags.map { $0 & InputEdge.identityMask }
        while index < slots[nodeIndex].node!.inputs.count,
              slots[nodeIndex].node!.inputs[index].attribute == input {
            let matches = identity.map {
                slots[nodeIndex].node!.inputs[index].flags
                    & InputEdge.identityMask == $0
            } ?? true
            if matches {
                removeInputEdge(fromNodeAt: nodeIndex, at: index)
            } else {
                index += 1
            }
        }
    }

    /// Registers an explicit input edge without reading the input value.
    func addInput(
        to attribute: AGAttribute,
        input: AGAttribute,
        options: AGInputOptions
    ) {
        assert(_AGGraph.current === self)
        guard attribute != input else {
            fatalError("An attribute cannot add itself as an input.")
        }
        _ = insertInputEdge(
            from: attribute,
            dependsOn: input,
            flags: UInt8(truncatingIfNeeded: options.rawValue)
                & InputEdge.identityMask
        )
    }

    /// Searches dependency edges in breadth-first order.
    ///
    /// The owner filter is inert because every local node has the same owner.
    func breadthFirstSearch(
        from start: AGAttribute,
        options: AGSearchOptions,
        _ predicate: (AGAttribute) -> Bool
    ) -> Bool {
        assert(_AGGraph.current === self)
        guard hasNode(start) else {
            fatalError("breadthFirstSearch called on AGAttribute @\(start.rawValue) that does not exist.")
        }

        var visited: Set<UInt32> = [start.rawValue]
        var queue: [UInt32] = [start.rawValue]
        var index = 0

        while index < queue.count {
            let rawValue = queue[index]
            index += 1
            let attribute = AGAttribute(rawValue: rawValue)
            guard hasNode(attribute) else { continue }
            if predicate(attribute) {
                return true
            }

            let node = slots[Int(rawValue)].node!
            if options.rawValue & 1 != 0 {
                for input in node.inputs
                where visited.insert(input.attribute).inserted {
                    queue.append(input.attribute)
                }
            }
            if options.rawValue & 2 != 0 {
                for output in node.outputs.sorted() where visited.insert(output).inserted {
                    queue.append(output)
                }
            }
        }
        return false
    }


    /// Clears dependency edges from `id` to its inputs.
    private func clearInputs(
        for id: AGAttribute,
        includingPermanent: Bool = false
    ) {
        let index = Int(id.rawValue)
        guard slots[index].node != nil else {
            fatalError("clearInputs called on AGAttribute @\(id.rawValue) that does not exist.")
        }
        var edgeIndex = 0
        while edgeIndex < slots[index].node!.inputs.count {
            let isPermanent =
                slots[index].node!.inputs[edgeIndex].flags
                    & InputEdge.permanent != 0
            if includingPermanent || !isPermanent {
                removeInputEdge(fromNodeAt: index, at: edgeIndex)
            } else {
                edgeIndex += 1
            }
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
        slots[Int(index)].node = Node(
            value: _AGValueStorage(defaultValue),
            makeValueStorage: Self.valueStorageFactory(for: V.self),
            valuesEqual: Self.valueComparator(for: V.self),
            kind: .indirect(target: nil, defaultValue: defaultValue),
            needsEvaluation: false
        )
        registerAttributeInfo(at: index, valueType: V.self)
        let attr = Attribute<V>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    func makeIndirectAttribute<V>(source: Attribute<V>) -> Attribute<V> {
        assert(_AGGraph.current === self)
        let index = allocateSlot()
        slots[Int(index)].node = Node(
            value: nil,
            makeValueStorage: Self.valueStorageFactory(for: V.self),
            valuesEqual: Self.valueComparator(for: V.self),
            kind: .indirect(target: source.identifier, defaultValue: nil)
        )
        registerAttributeInfo(at: index, valueType: V.self)
        let attribute = Attribute<V>(AGAttribute(rawValue: index))
        indirectDefaultSources[attribute.identifier.rawValue] = source.identifier
        AGSubgraph.current?.register(attribute.identifier)
        return attribute
    }

    /// Points `indirect` at `concrete` (or nil to detach).
    /// Invalidates `indirect` and its downstream dependents.
    func setIndirectTarget(_ indirect: AGAttribute, to concrete: AGAttribute?) {
        assert(_AGGraph.current === self)
        let index = Int(indirect.rawValue)
        guard case let .indirect(_, defaultValue) = slots[index].node?.kind else {
            fatalError("setIndirectTarget: @\(indirect.rawValue) is not an indirect node.")
        }
        slots[index].node!.kind = .indirect(
            target: concrete,
            defaultValue: defaultValue
        )
        markNeedsEvaluation(indirect)
    }

    /// Typed convenience wrapper around `setIndirectTarget(_:to:)`.
    func setIndirectTarget<V>(_ indirect: Attribute<V>, to concrete: Attribute<V>?) {
        setIndirectTarget(indirect.identifier, to: concrete?.identifier)
    }

    func indirectTarget(_ indirect: AGAttribute) -> AGAttribute? {
        guard case let .indirect(target, _) = slots[Int(indirect.rawValue)].node?.kind else {
            fatalError("indirectTarget: @\(indirect.rawValue) is not an indirect node.")
        }
        return target
    }

    func resetIndirectTarget(_ indirect: AGAttribute) {
        setIndirectTarget(indirect, to: indirectDefaultSources[indirect.rawValue])
    }

    /// Registers a permanent dependency: when `dep` changes, `indirect` is invalidated.
    /// Unlike rule-computed inputs, this edge is NOT cleared on re-evaluation.
    func setIndirectDependency(_ indirect: AGAttribute, dependsOn dep: AGAttribute?) {
        assert(_AGGraph.current === self)
        let iIdx = Int(indirect.rawValue)
        guard slots[iIdx].node != nil else {
            fatalError("setIndirectDependency: indirect node @\(indirect.rawValue) does not exist.")
        }
        if let previous = indirectDependencies.removeValue(forKey: indirect.rawValue) {
            removeInputEdges(
                fromNodeAt: iIdx,
                matching: previous.rawValue,
                identityFlags: InputEdge.permanent
            )
        }
        guard let dep else {
            markNeedsEvaluation(indirect)
            return
        }
        let dIdx = Int(dep.rawValue)
        guard slots[dIdx].node != nil else {
            fatalError("setIndirectDependency: dep node @\(dep.rawValue) does not exist.")
        }
        indirectDependencies[indirect.rawValue] = dep
        addPermanentDependency(from: indirect, dependsOn: dep)
        markNeedsEvaluation(indirect)
    }

    func indirectDependency(_ indirect: AGAttribute) -> AGAttribute? {
        indirectDependencies[indirect.rawValue]
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
        slots[Int(index)].node = Node(
            value: nil,
            makeValueStorage: Self.valueStorageFactory(for: U.self),
            valuesEqual: Self.valueComparator(
                for: U.self,
                mode: Focus<T, U>.comparisonMode
            ),
            kind: .keyPath(parent: parent.identifier, kp: keyPath)
        )
        registerAttributeInfo(at: index, valueType: U.self)
        pathIDs[rp] = index
        addPermanentDependency(
            from: AGAttribute(rawValue: index),
            dependsOn: parent.identifier
        )
        let attr = Attribute<U>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attr.identifier)
        return attr
    }

    func subscriptNode<T, U>(
        parent: Attribute<T>,
        offset: PointerOffset<T, U>
    ) -> Attribute<U> {
        assert(_AGGraph.current === self)
        let path = RelativeOffsetPath(
            parentID: parent.identifier.rawValue,
            byteOffset: offset.byteOffset,
            valueType: ObjectIdentifier(U.self)
        )
        if let existingIndex = offsetPathIDs[path] {
            return Attribute(AGAttribute(rawValue: existingIndex))
        }

        let index = allocateSlot()
        slots[Int(index)].node = Node(
            value: nil,
            makeValueStorage: Self.valueStorageFactory(for: U.self),
            valuesEqual: Self.valueComparator(for: U.self),
            kind: .offset(
                parent: parent.identifier,
                byteOffset: offset.byteOffset,
                valueType: ObjectIdentifier(U.self),
                project: { parentValue in
                    var value = parentValue as! T
                    return withUnsafePointer(to: &value) { pointer in
                        (pointer + offset).pointee
                    }
                }
            )
        )
        registerAttributeInfo(at: index, valueType: U.self)
        offsetPathIDs[path] = index
        addPermanentDependency(
            from: AGAttribute(rawValue: index),
            dependsOn: parent.identifier
        )
        let attribute = Attribute<U>(AGAttribute(rawValue: index))
        AGSubgraph.current?.register(attribute.identifier)
        return attribute
    }

    func rawOffsetNode(parent: AGAttribute, byteOffset: Int) -> AGAttribute {
        assert(_AGGraph.current === self)
        let path = RawOffsetPath(
            parentID: parent.rawValue,
            byteOffset: byteOffset
        )
        if let existingIndex = rawOffsetPathIDs[path] {
            return AGAttribute(rawValue: existingIndex)
        }

        let index = allocateSlot()
        slots[Int(index)].node = Node(
            value: nil,
            makeValueStorage: { _ in
                fatalError("Raw offset attributes do not store readable values.")
            },
            valuesEqual: { _, _ in false },
            kind: .rawOffset(parent: parent, byteOffset: byteOffset)
        )
        rawOffsetPathIDs[path] = index
        addPermanentDependency(
            from: AGAttribute(rawValue: index),
            dependsOn: parent
        )
        let attribute = AGAttribute(rawValue: index)
        AGSubgraph.current?.register(attribute)
        return attribute
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
        case .offset(let parent, let byteOffset, _, _):
            return "@\(id.rawValue)(offset: @\(parent.rawValue) + \(byteOffset))"
        case .rawOffset(let parent, let byteOffset):
            return "@\(id.rawValue)(rawOffset: @\(parent.rawValue) + \(byteOffset))"
        case .rule(let box):
            return "@\(id.rawValue)(\(box.isSideEffect ? "sideEffect" : "rule"))"
        case .ruleBody:
            return "@\(id.rawValue)(ruleBody)"
        case .stateful:
            return "@\(id.rawValue)(stateful)"
        case .lowLevelBody:
            return "@\(id.rawValue)(lowLevelBody)"
        case .input:
            return "@\(id.rawValue)(input)"
        case .crossGraphRef(let sourceAttr, let sourceGraphRef):
            let srcDesc = sourceGraphRef.value != nil ? "@\(sourceAttr.rawValue)" : "@\(sourceAttr.rawValue)(dead)"
            return "@\(id.rawValue)(crossRef->\(srcDesc))"
        case .indirect(let target, _):
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
// latency when many nodes are removed in one structural update. Keep stack
// capture off by default.
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
            valueTypeDescription: debugValueTypeDescription(for: node.value?.anyValue),
            inputs: Set(node.inputs.map(\.attribute)),
            outputs: Set(node.outputs),
            staticInputs: Set(
                node.inputs.lazy
                    .filter { $0.flags & InputEdge.permanent != 0 }
                    .map(\.attribute)
            ),
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
        case .rule(let box):
            return box.isSideEffect ? "sideEffectRule" : "rule"
        case .ruleBody(let box):
            return "ruleBody(\(String(describing: type(of: box))))"
        case .stateful(let box):
            return "stateful(\(String(describing: type(of: box))))"
        case .lowLevelBody(let box):
            return "lowLevelBody(\(String(describing: type(of: box))))"
        case .keyPath(let parent, let keyPath):
            return "keyPath(parent: @\(parent.rawValue), keyPath: \(keyPath))"
        case .offset(let parent, let byteOffset, _, _):
            return "offset(parent: @\(parent.rawValue), byteOffset: \(byteOffset))"
        case .rawOffset(let parent, let byteOffset):
            return "rawOffset(parent: @\(parent.rawValue), byteOffset: \(byteOffset))"
        case .crossGraphRef(let sourceAttr, let sourceGraphRef):
            return "crossGraphRef(source: @\(sourceAttr.rawValue), sourceGraphAlive: \(sourceGraphRef.value != nil))"
        case .indirect(let target, _):
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
