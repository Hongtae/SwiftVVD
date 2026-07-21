//
//  File: AttributeGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Synchronization

typealias AGGraphRef = _AGGraph

/// Comparison policy used when storing and comparing attribute values.
struct AGComparisonMode: RawRepresentable, Equatable, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// Flags describing an attribute body type.
struct AGAttributeTypeFlags: OptionSet, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

struct AGComparisonOptions: RawRepresentable, Equatable, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(mode: AGComparisonMode) {
        self.rawValue = mode.rawValue
    }
}

/// Options applied when reading an attribute value.
struct AGValueOptions: OptionSet, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// Raw options accepted by the Hashable Rule cached-value surface.
///
/// The native runtime interprets these bits while consulting its subgraph
/// cache. The Swift graph keeps the raw value as part of its cache identity;
/// no unobserved bit-specific behavior is assigned here.
struct AGCachedValueOptions: OptionSet, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// Swift carrier for flags returned with an input value.
struct AGChangedValueFlags: OptionSet, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// Swift carriers for the option and state values imported from the native
/// attribute runtime. The graph engine interprets only the
/// values whose behavior is implemented by its Swift storage layer.
struct AGInputOptions: OptionSet, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

struct AGSearchOptions: OptionSet, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

struct AGAttributeFlags: OptionSet, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    static let transactional = AGAttributeFlags(rawValue: 1)
    static let removable = AGAttributeFlags(rawValue: 2)
    static let invalidatable = AGAttributeFlags(rawValue: 4)
    static let scrapeable = AGAttributeFlags(rawValue: 8)
}

struct AGValueState: RawRepresentable, Equatable, Sendable {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

struct _AGAttributeInfo {
    let bodyType: Any.Type
    let valueType: Any.Type
    let bodyPointer: UnsafeRawPointer
}

// MARK: - PointerOffset

/// A typed byte offset between a root value and one of its stored values.
///
/// Field closures form an address from a synthetic root and must not read the
/// root value.
struct PointerOffset<Root, Value> {
    let byteOffset: Int

    init(byteOffset: Int) {
        self.byteOffset = byteOffset
    }

    static func invalidScenePointer() -> UnsafeMutablePointer<Root> {
        UnsafeMutablePointer<Root>(bitPattern: 1)!
    }

    static func offset(
        _ body: (inout Root) -> PointerOffset<Root, Value>
    ) -> PointerOffset<Root, Value> {
        guard MemoryLayout<Root>.size != 0 else {
            return PointerOffset(byteOffset: 0)
        }
        return body(&invalidScenePointer().pointee)
    }

    static func of(_ value: inout Value) -> PointerOffset<Root, Value> {
        withUnsafePointer(to: &value) { pointer in
            let address = Int(bitPattern: UnsafeRawPointer(pointer))
            return PointerOffset(byteOffset: address - 1)
        }
    }

    static func + <Member>(
        lhs: PointerOffset<Root, Value>,
        rhs: PointerOffset<Value, Member>
    ) -> PointerOffset<Root, Member> {
        PointerOffset<Root, Member>(byteOffset: lhs.byteOffset + rhs.byteOffset)
    }
}

extension PointerOffset where Root == Value {
    init() {
        self.init(byteOffset: 0)
    }
}

extension UnsafePointer {
    static func + <Value>(
        lhs: UnsafePointer<Pointee>,
        rhs: PointerOffset<Pointee, Value>
    ) -> UnsafePointer<Value> {
        UnsafeRawPointer(lhs)
            .advanced(by: rhs.byteOffset)
            .assumingMemoryBound(to: Value.self)
    }

    subscript<Value>(offset: PointerOffset<Pointee, Value>) -> Value {
        (self + offset).pointee
    }
}

extension UnsafeMutablePointer {
    static func + <Value>(
        lhs: UnsafeMutablePointer<Pointee>,
        rhs: PointerOffset<Pointee, Value>
    ) -> UnsafeMutablePointer<Value> {
        UnsafeMutableRawPointer(lhs)
            .advanced(by: rhs.byteOffset)
            .assumingMemoryBound(to: Value.self)
    }

    subscript<Value>(offset: PointerOffset<Pointee, Value>) -> Value {
        get { (self + offset).pointee }
        set { (self + offset).pointee = newValue }
    }
}

func compareValues<Value>(_ lhs: Value, _ rhs: Value, mode: AGComparisonMode) -> Bool {
    _AGGraph.compareValues(
        lhs,
        rhs,
        options: AGComparisonOptions(rawValue: mode.rawValue)
    )
}

func compareValues<Value>(_ lhs: Value, _ rhs: Value, options: AGComparisonOptions) -> Bool {
    _AGGraph.compareValues(lhs, rhs, options: options)
}

func _AGCompareValues<Value>(_ lhs: Value, _ rhs: Value, options: AGComparisonOptions) -> Bool {
    compareValues(lhs, rhs, options: options)
}

func _AGGraphAnyInputsChanged() -> Bool {
    _AGGraph._currentStatefulInputsChanged()
}

func _AGGraphCancelUpdate() {
    _AGGraph.cancelCurrentUpdate()
}

func _AGGraphCancelUpdateIfNeeded() -> Bool {
    _AGGraph.cancelCurrentUpdateIfNeeded()
}

func _AGGraphUpdateWasCancelled() -> Bool {
    _AGGraph.currentUpdateWasCancelled()
}

func _AGGraphGetAttributeGraph(_ attribute: AGAttribute) -> AGGraphRef {
    attribute._debugValidate()
    guard let graph = _AGGraph.current, graph.hasNode(attribute) else {
        fatalError("AGGraphGetAttributeGraph requires a live attribute in the active _AGGraph context.")
    }
    return graph
}

func AGGraphGetAttributeGraph(_ attribute: AGAttribute) -> AGGraphRef {
    _AGGraphGetAttributeGraph(attribute)
}

func _AGGraphGetValue<Value>(
    _ attribute: Attribute<Value>,
    options: AGValueOptions
) -> (value: Value, flags: AGChangedValueFlags) {
    let graph = _AGGraphGetAttributeGraph(attribute.identifier)
    return graph.valueAndFlags(
        for: attribute,
        relativeTo: _AGGraph.currentlyEvaluatingNode,
        options: options
    )
}

func AGGraphGetValue<Value>(
    _ attribute: Attribute<Value>,
    options: AGValueOptions
) -> (value: Value, flags: AGChangedValueFlags) {
    _AGGraphGetValue(attribute, options: options)
}

func _AGGraphGetInputValue<Value>(
    _ attribute: Attribute<Value>,
    relativeTo context: AGAttribute,
    options: AGValueOptions
) -> (value: Value, flags: AGChangedValueFlags) {
    let graph = _AGGraphGetAttributeGraph(attribute.identifier)
    return graph.valueAndFlags(
        for: attribute,
        relativeTo: context,
        options: options
    )
}

func AGGraphGetInputValue<Value>(
    _ attribute: Attribute<Value>,
    relativeTo context: AGAttribute,
    options: AGValueOptions
) -> (value: Value, flags: AGChangedValueFlags) {
    _AGGraphGetInputValue(attribute, relativeTo: context, options: options)
}

func _AGGraphGetWeakValue<Value>(
    _ attribute: WeakAttribute<Value>,
    options: AGValueOptions
) -> (value: Value, flags: AGChangedValueFlags)? {
    guard let strong = attribute.attribute else { return nil }
    return _AGGraphGetValue(strong, options: options)
}

func AGGraphGetWeakValue<Value>(
    _ attribute: WeakAttribute<Value>,
    options: AGValueOptions
) -> (value: Value, flags: AGChangedValueFlags)? {
    _AGGraphGetWeakValue(attribute, options: options)
}

func _AGGraphHasValue(_ attribute: AGAttribute) -> Bool {
    _AGGraphGetAttributeGraph(attribute).hasCachedValue(for: attribute)
}

func AGGraphHasValue(_ attribute: AGAttribute) -> Bool {
    _AGGraphHasValue(attribute)
}

func _AGGraphGetValueState(_ attribute: AGAttribute) -> AGValueState {
    _AGGraphGetAttributeGraph(attribute).valueState(for: attribute)
}

func AGGraphGetValueState(_ attribute: AGAttribute) -> AGValueState {
    _AGGraphGetValueState(attribute)
}

func _AGGraphGetAttributeInfo(_ attribute: AGAttribute) -> _AGAttributeInfo {
    let graph = _AGGraphGetAttributeGraph(attribute)
    return _AGAttributeInfo(
        bodyType: graph.bodyType(for: attribute),
        valueType: graph.valueType(for: attribute),
        bodyPointer: graph.bodyPointer(for: attribute)
    )
}

func AGGraphGetAttributeInfo(_ attribute: AGAttribute) -> _AGAttributeInfo {
    _AGGraphGetAttributeInfo(attribute)
}

func _AGGraphCreateOffsetAttribute(
    _ attribute: AGAttribute,
    at byteOffset: Int
) -> AGAttribute {
    _AGGraphGetAttributeGraph(attribute).rawOffsetNode(
        parent: attribute,
        byteOffset: byteOffset
    )
}

func AGGraphCreateOffsetAttribute(
    _ attribute: AGAttribute,
    at byteOffset: Int
) -> AGAttribute {
    _AGGraphCreateOffsetAttribute(attribute, at: byteOffset)
}

func _AGGraphCreateOffsetAttribute2<Root, Value>(
    _ attribute: Attribute<Root>,
    offset: PointerOffset<Root, Value>
) -> Attribute<Value> {
    _AGGraphGetAttributeGraph(attribute.identifier).subscriptNode(
        parent: attribute,
        offset: offset
    )
}

func AGGraphCreateOffsetAttribute2<Root, Value>(
    _ attribute: Attribute<Root>,
    offset: PointerOffset<Root, Value>
) -> Attribute<Value> {
    _AGGraphCreateOffsetAttribute2(attribute, offset: offset)
}

func _AGGraphInvalidateValue(_ attribute: AGAttribute) {
    _AGGraphGetAttributeGraph(attribute).invalidateAttribute(attribute)
}

func AGGraphInvalidateValue(_ attribute: AGAttribute) {
    _AGGraphInvalidateValue(attribute)
}

func _AGGraphUpdateValue(_ attribute: AGAttribute) {
    _ = _AGGraphGetAttributeGraph(attribute).value(for: attribute)
}

func AGGraphUpdateValue(_ attribute: AGAttribute) {
    _AGGraphUpdateValue(attribute)
}

func _AGGraphPrefetchValue(_ attribute: AGAttribute) {
    _AGGraphUpdateValue(attribute)
}

func AGGraphPrefetchValue(_ attribute: AGAttribute) {
    _AGGraphPrefetchValue(attribute)
}

@discardableResult
func _AGGraphSetValue<Value>(
    _ attribute: Attribute<Value>,
    _ value: Value
) -> Bool {
    _AGGraphGetAttributeGraph(attribute.identifier).setValue(
        for: attribute,
        to: value,
        transaction: Transaction()
    )
}

@discardableResult
func AGGraphSetValue<Value>(
    _ attribute: Attribute<Value>,
    _ value: Value
) -> Bool {
    _AGGraphSetValue(attribute, value)
}

func _AGGraphMutateAttribute<Body>(
    _ attribute: AGAttribute,
    as type: Body.Type,
    invalidating: Bool,
    _ body: (inout Body) -> Void
) {
    _AGGraphGetAttributeGraph(attribute).mutateBody(
        attribute,
        as: type,
        invalidating: invalidating,
        body
    )
}

func _AGCreateWeakAttribute(_ attribute: AGAttribute) -> AGWeakAttribute {
    let graph = _AGGraphGetAttributeGraph(attribute)
#if DEBUG
    return AGWeakAttribute(
        identifier: attribute.rawValue,
        seed: graph._seed(at: attribute.rawValue),
        owningGraph: ObjectIdentifier(graph)
    )
#else
    return AGWeakAttribute(
        identifier: attribute.rawValue,
        seed: graph._seed(at: attribute.rawValue)
    )
#endif
}

func _AGGraphSetContext(_ graph: AGGraphRef, _ context: AnyObject?) {
    graph.context = context.map(Unmanaged.passUnretained)
}

func AGGraphSetContext(_ graph: AGGraphRef, _ context: AnyObject?) {
    _AGGraphSetContext(graph, context)
}

func _AGGraphGetContext(_ graph: AGGraphRef) -> AnyObject? {
    graph.context?.takeUnretainedValue()
}

func AGGraphGetContext(_ graph: AGGraphRef) -> AnyObject? {
    _AGGraphGetContext(graph)
}

func _AGGraphAddInput(
    _ attribute: AGAttribute,
    _ input: AGAttribute,
    _ options: AGInputOptions
) {
    guard let graph = _AGGraph.current else {
        fatalError("AGGraphAddInput requires an active _AGGraph context.")
    }
    graph.addInput(to: attribute, input: input, options: options)
}

func AGGraphAddInput(
    _ attribute: AGAttribute,
    _ input: AGAttribute,
    _ options: AGInputOptions
) {
    _AGGraphAddInput(attribute, input, options)
}

func _AGGraphSearch(
    _ attribute: AGAttribute,
    _ options: AGSearchOptions,
    _ predicate: (AGAttribute) -> Bool
) -> Bool {
    guard let graph = _AGGraph.current else {
        fatalError("AGGraphSearch requires an active _AGGraph context.")
    }
    return graph.breadthFirstSearch(
        from: attribute,
        options: options,
        predicate
    )
}

func AGGraphSearch(
    _ attribute: AGAttribute,
    _ options: AGSearchOptions,
    _ predicate: (AGAttribute) -> Bool
) -> Bool {
    _AGGraphSearch(attribute, options, predicate)
}

// MARK: - _AGGraphContext
// Evaluation-scope wrapper. Host identity is stored on the graph and
// read through AGGraphGetContext rather than carried independently by this
// scope value.
struct _AGGraphContext: @unchecked Sendable {
    let graph: AGGraphRef

    var context: AnyObject? {
        AGGraphGetContext(graph)
    }

    /// The currently active _AGGraphContext for the running AG evaluation pass.
    /// Set by withCurrent(_:). Reading context gives the owning GraphHost subclass.
    private static let currentStorage = _AGThreadLocal<_AGGraphContext?>(nil)

    static var current: _AGGraphContext? {
        currentStorage.value
    }

    init(graph: AGGraphRef) {
        self.graph = graph
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
        return try _AGGraphContext.currentStorage.withValue(self) {
            try _AGGraph.withCurrent(graph) {
                try body()
            }
        }
    }
}

// MARK: - _AGChangeSet

/// Records attributes that were mutated during an `_AGGraph.withChangeSet(_:)`
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
