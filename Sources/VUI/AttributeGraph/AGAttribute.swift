//
//  File: AGAttribute.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - Core Node Types

/// The raw identifier for an AG node: an index into the graph's slot array.
struct AGAttribute: Hashable, CustomStringConvertible, Sendable {
    private static let invalidRawValue = UInt32.max
    static let invalid = AGAttribute(uncheckedRawValue: invalidRawValue)

    let rawValue: UInt32
    var isInvalid: Bool { rawValue == Self.invalidRawValue }

#if DEBUG
    /// The ObjectIdentifier of the _AGGraph that owns this attribute.
    /// Set at creation time (makeInput/makeRule). Used to detect cross-graph access.
    private let _owningGraphID: ObjectIdentifier
    /// The generation seed of the slot when this strong handle was created.
    /// This catches stale strong handles when a removed slot is reused for a new node.
    private let _seedAtCreation: UInt32
#endif

#if !DEBUG
    private init(uncheckedRawValue: UInt32) {
        self.rawValue = uncheckedRawValue
    }
#endif

    init(rawValue: UInt32) {
        self.rawValue = rawValue
        guard let graph = _AGGraph.current else {
            fatalError("AGAttribute(\(rawValue)) created outside an active _AGGraph context.")
        }
#if DEBUG
        self._owningGraphID = ObjectIdentifier(graph)
        guard let seed = graph._seedIfPresent(at: rawValue) else {
            fatalError("AGAttribute(\(rawValue)) created for a slot outside the current _AGGraph.")
        }
        self._seedAtCreation = seed
#endif
    }

    static var current: AGAttribute? {
        _AGGraph.currentRuleContextAttribute
    }

    init<Value>(_ attribute: Attribute<Value>) {
        self = attribute.identifier
    }

    func unsafeCast<Value>(to type: Value.Type) -> Attribute<Value> {
        Attribute(identifier: self)
    }

    func unsafeOffset(at byteOffset: Int) -> AGAttribute {
        _AGGraphCreateOffsetAttribute(self, at: byteOffset)
    }

    var _bodyType: Any.Type {
        _AGGraphGetAttributeInfo(self).bodyType
    }

    var _bodyPointer: UnsafeRawPointer {
        _AGGraphGetAttributeInfo(self).bodyPointer
    }

    var valueType: Any.Type {
        _AGGraphGetAttributeInfo(self).valueType
    }

    func mutateBody<Body>(
        as type: Body.Type,
        invalidating: Bool,
        _ body: (inout Body) -> Void
    ) {
        _AGGraphMutateAttribute(
            self,
            as: type,
            invalidating: invalidating,
            body
        )
    }

    func visitBody<Visitor: AttributeBodyVisitor>(_ visitor: inout Visitor) {
        guard let graph = _AGGraph.current else {
            fatalError("AGAttribute.visitBody(_:) requires an active _AGGraph context.")
        }
        graph.visitBody(self, visitor: &visitor)
    }

    func setFlags(_ flags: AGAttributeFlags, mask: AGAttributeFlags) {
        guard let graph = _AGGraph.current else {
            fatalError("AGAttribute.setFlags(_:mask:) requires an active _AGGraph context.")
        }
        graph.setFlags(flags, mask: mask, for: self)
    }

    func addInput<Input>(
        _ input: Attribute<Input>,
        options: AGInputOptions,
        token: Int
    ) {
        addInput(input.identifier, options: options, token: token)
    }

    func addInput(
        _ input: AGAttribute,
        options: AGInputOptions,
        token: Int
    ) {
        AGGraphAddInput(self, input, options)
        _ = token
    }

    func breadthFirstSearch(
        options: AGSearchOptions,
        _ predicate: (AGAttribute) -> Bool
    ) -> Bool {
        AGGraphSearch(self, options, predicate)
    }

    var indirectDependency: AGAttribute? {
        get {
            guard let graph = _AGGraph.current else {
                fatalError("AGAttribute.indirectDependency requires an active _AGGraph context.")
            }
            return graph.indirectDependency(self)
        }
        nonmutating set {
            guard let graph = _AGGraph.current else {
                fatalError("AGAttribute.indirectDependency requires an active _AGGraph context.")
            }
            graph.setIndirectDependency(self, dependsOn: newValue)
        }
    }

    var description: String {
        if isInvalid {
            return "nil"
        }
        if let graph = _AGGraph.current {
            return graph.debugDescription(for: self)
        }
        return "@\(rawValue)"
    }
}

/// A weak reference to an AG node.
/// Carries a seed (generation counter) to detect whether the slot at `identifier`
/// still holds the same node that was referenced when this value was created.
struct AGWeakAttribute: Hashable, CustomStringConvertible, Sendable {
    static let invalid = AGWeakAttribute(uncheckedIdentifier: 0, seed: 0)

    let identifier: UInt32
    let seed: UInt32
    var isInvalid: Bool { identifier == 0 && seed == 0 }

#if DEBUG
    private let _owningGraphID: ObjectIdentifier
#else
    init(identifier: UInt32, seed: UInt32) {
        self.identifier = identifier
        self.seed = seed
    }

    private init(uncheckedIdentifier: UInt32, seed: UInt32) {
        self.identifier = uncheckedIdentifier
        self.seed = seed
    }
#endif

    func isValid(in graph: _AGGraph) -> Bool {
        guard !isInvalid else { return false }
        if graph._isValid(index: identifier, seed: seed) {
#if DEBUG
            guard _owningGraphID == ObjectIdentifier(graph) else {
                fatalError(
                    "AGWeakAttribute @\(identifier) with seed \(seed) is from a different _AGGraph than the one it was validated against. " +
                    "This is a usage error: AGWeakAttributes must only be compared or converted to strong references within the same graph they were created from."
                )
            }
#endif
            return true
        }
        return false
    }

    init(_ attribute: AGAttribute?) {
        guard let attribute else {
            self = .invalid
            return
        }
        self = _AGCreateWeakAttribute(attribute)
    }

    init<Value>(_ attribute: WeakAttribute<Value>) {
        self = attribute.base
    }

    func unsafeCast<Value>(to type: Value.Type) -> WeakAttribute<Value> {
        WeakAttribute(base: self)
    }

    func toStrong() -> AGAttribute {
        guard !isInvalid else {
            fatalError("Invalid AGWeakAttribute sentinel cannot be converted to a strong attribute.")
        }
#if DEBUG
        return AGAttribute(rawValue: identifier, owningGraph: _owningGraphID, seed: seed)
#else
        return AGAttribute(rawValue: identifier)
#endif
    }

    var attribute: AGAttribute? {
        get {
            guard let graph = _AGGraph.current, isValid(in: graph) else {
                return nil
            }
            return toStrong()
        }
        set {
            guard let newValue else {
                self = .invalid
                return
            }
            guard let graph = _AGGraph.current else {
                fatalError("Attempted to create a weak attribute outside an active _AGGraph context.")
            }
#if DEBUG
            self = AGWeakAttribute(
                identifier: newValue.rawValue,
                seed: graph._seed(at: newValue.rawValue),
                owningGraph: ObjectIdentifier(graph)
            )
#else
            self = AGWeakAttribute(
                identifier: newValue.rawValue,
                seed: graph._seed(at: newValue.rawValue)
            )
#endif
        }
    }

    var description: String {
        attribute?.description ?? "nil"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        if lhs.isInvalid || rhs.isInvalid {
            return lhs.identifier == rhs.identifier && lhs.seed == rhs.seed
        }
#if DEBUG
        guard lhs._owningGraphID == rhs._owningGraphID else {
            return false
        }
#endif
        return lhs.identifier == rhs.identifier && lhs.seed == rhs.seed
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
        hasher.combine(seed)
#if DEBUG
        if !isInvalid {
            hasher.combine(_owningGraphID)
        }
#endif
    }
}

/// A typed wrapper around an AGAttribute.
/// Marked @unchecked Sendable: stores only AGAttribute (a Sendable raw index).
/// Value type parameter is used only in method signatures. No Value is retained here.
@dynamicMemberLookup
struct Attribute<Value>: Hashable, CustomStringConvertible, @unchecked Sendable {
    var identifier: AGAttribute

    init(identifier: AGAttribute) {
        self.identifier = identifier
    }

    init(value: Value) {
        guard let graph = _AGGraph.current else {
            fatalError("Attribute.init(value:) requires an active _AGGraph context.")
        }
        self = graph.makeInput(value: value)
    }

    init(type: Value.Type) {
        guard let graph = _AGGraph.current else {
            fatalError("Attribute.init(type:) requires an active _AGGraph context.")
        }
        self = graph.makeInput(type: type)
    }

    init<Body: _AttributeBody>(
        body: UnsafePointer<Body>,
        value: UnsafePointer<Value>?,
        flags: AGAttributeTypeFlags,
        update: () -> (UnsafeMutableRawPointer, AGAttribute) -> Void
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("Attribute.init(body:value:flags:update:) requires an active _AGGraph context.")
        }
        self = graph.makeLowLevelAttribute(
            body: body.pointee,
            value: value.map(\.pointee),
            flags: flags,
            update: update()
        )
    }

    init<R: Rule>(_ rule: R) where Value == R.Value {
        guard let graph = _AGGraph.current else {
            fatalError("Attribute.init(_:) requires an active _AGGraph context.")
        }
        self = graph.makeRule(rule)
    }

    init<R: Rule>(_ rule: R, initialValue: Value) where Value == R.Value {
        guard let graph = _AGGraph.current else {
            fatalError("Attribute.init(_:initialValue:) requires an active _AGGraph context.")
        }
        self = graph.makeRule(rule, initialValue: initialValue)
    }

    init<R: StatefulRule>(_ rule: R) where Value == R.Value {
        guard let graph = _AGGraph.current else {
            fatalError("Attribute.init(_:) requires an active _AGGraph context.")
        }
        self = graph.makeStatefulRule(rule)
    }

    init<R: StatefulRule>(_ rule: R, initialValue: Value) where Value == R.Value {
        guard let graph = _AGGraph.current else {
            fatalError("Attribute.init(_:initialValue:) requires an active _AGGraph context.")
        }
        self = graph.makeStatefulRule(rule, initialValue: initialValue)
    }

    init(_ id: AGAttribute) {
        self.identifier = id
    }

    init(_ attribute: Attribute<Value>) {
        self = attribute
    }

    func unsafeCast<Other>(to type: Other.Type) -> Attribute<Other> {
        Attribute<Other>(identifier: identifier)
    }

    func unsafeBitCast<Other>(to type: Other.Type) -> Attribute<Other> {
        unsafeOffset(at: 0, as: type)
    }

    var description: String {
        identifier.description
    }

    var graph: AGGraphRef {
        _AGGraphGetAttributeGraph(identifier)
    }

    var hasValue: Bool {
        _AGGraphHasValue(identifier)
    }

    var valueState: AGValueState {
        _AGGraphGetValueState(identifier)
    }

    var subgraphOrNil: AGSubgraphRef? {
        graph.subgraph(for: identifier)
    }

    var subgraph: AGSubgraphRef {
        guard let subgraphOrNil else {
            fatalError("Attribute.subgraph requires an owning subgraph.")
        }
        return subgraphOrNil
    }

    var flags: AGAttributeFlags {
        get { graph.flags(for: identifier) }
        nonmutating set { graph.setFlags(newValue, mask: .init(rawValue: .max), for: identifier) }
    }

    func setFlags(_ flags: AGAttributeFlags, mask: AGAttributeFlags) {
        graph.setFlags(flags, mask: mask, for: identifier)
    }

    func addInput<Input>(
        _ input: Attribute<Input>,
        options: AGInputOptions,
        token: Int
    ) {
        identifier.addInput(input, options: options, token: token)
    }

    func addInput(
        _ input: AGAttribute,
        options: AGInputOptions,
        token: Int
    ) {
        identifier.addInput(input, options: options, token: token)
    }

    func breadthFirstSearch(
        options: AGSearchOptions,
        _ predicate: (AGAttribute) -> Bool
    ) -> Bool {
        identifier.breadthFirstSearch(options: options, predicate)
    }

    func validate() {
        _debugValidate()
        guard graph.hasNode(identifier) else {
            fatalError("Attribute.validate() found no node for @\(identifier.rawValue).")
        }
    }

    var projectedValue: Attribute<Value> {
        get { self }
        set { self = newValue }
    }

    /// Pulls the latest value from the graph, triggering evaluation if needed,
    /// and implicitly recording a dependency if another node is currently evaluating.
    var value: Value {
        get {
            _AGGraphGetValue(
                self,
                options: AGValueOptions(rawValue: 0)
            ).value
        }
        nonmutating set {
            setValue(newValue)
        }
    }

    func valueAndFlags(
        options: AGValueOptions
    ) -> (value: Value, flags: AGChangedValueFlags) {
        _AGGraphGetValue(self, options: options)
    }

    func changedValue(
        options: AGValueOptions
    ) -> (value: Value, changed: Bool) {
        let result = valueAndFlags(options: options)
        return (result.value, result.flags.rawValue & 1 != 0)
    }

    var wrappedValue: Value {
        get { value }
        nonmutating set { value = newValue }
    }

    subscript<Member>(keyPath keyPath: KeyPath<Value, Member>) -> Attribute<Member> {
        _debugValidate()
        guard let graph = _AGGraph.current else {
            fatalError("Attempted to project an Attribute outside of an active _AGGraph context.")
        }
        return graph.subscriptNode(parent: self, keyPath: keyPath)
    }

    subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Attribute<Member> {
        self[keyPath: keyPath]
    }

    func unsafeOffset<Member>(at byteOffset: Int, as type: Member.Type) -> Attribute<Member> {
        applying(offset: PointerOffset<Value, Member>(byteOffset: byteOffset))
    }

    func applying<Member>(
        offset: PointerOffset<Value, Member>
    ) -> Attribute<Member> {
        _AGGraphCreateOffsetAttribute2(self, offset: offset)
    }

    subscript<Member>(
        offset body: (inout Value) -> PointerOffset<Value, Member>
    ) -> Attribute<Member> {
        applying(offset: PointerOffset.offset(body))
    }

    // Primarily used for State/Input nodes to push new values.
    // Can also be used to inject an initial fallback value into a rule node
    // to resolve potential dependency cycles before it is first evaluated.
    @discardableResult
    func setValue(_ newValue: Value) -> Bool {
        _AGGraphSetValue(self, newValue)
    }

    @discardableResult
    func setValue(_ newValue: Value, transaction: Transaction) -> Bool {
        _debugValidate()
        guard let graph = _AGGraph.current else {
            fatalError("Attempted to write to an Attribute outside of an active _AGGraph context.")
        }
        return graph.setValue(for: self, to: newValue, transaction: transaction)
    }

    func updateValue() {
        _AGGraphUpdateValue(identifier)
    }

    func prefetchValue() {
        _AGGraphPrefetchValue(identifier)
    }

    func invalidateValue() {
        _AGGraphInvalidateValue(identifier)
    }

    func mutateBody<Body>(
        as type: Body.Type,
        invalidating: Bool,
        _ body: (inout Body) -> Void
    ) {
        identifier.mutateBody(as: type, invalidating: invalidating, body)
    }

    func visitBody<Visitor: AttributeBodyVisitor>(_ visitor: inout Visitor) {
        identifier.visitBody(&visitor)
    }

    /// Creates a typed weak reference to this attribute, capturing the current generation seed.
    func asWeak() -> WeakAttribute<Value> {
        WeakAttribute(base: _AGCreateWeakAttribute(identifier))
    }
}

extension Attribute: GraphReusable {}

private struct ToOptional<Wrapped>: Rule, AsyncAttribute {
    typealias Value = Wrapped?

    let source: Attribute<Wrapped>

    var value: Wrapped? {
        source.value
    }
}

extension Attribute {
    var toOptional: Attribute<Value?> {
        Attribute<Value?>(ToOptional(source: self))
    }
}

@dynamicMemberLookup
struct IndirectAttribute<Value>: Hashable {
    private var base: Attribute<Value>

    var identifier: AGAttribute { base.identifier }
    var attribute: Attribute<Value> { base }

    init(source: Attribute<Value>) {
        guard let graph = _AGGraph.current else {
            fatalError("IndirectAttribute.init(source:) requires an active _AGGraph context.")
        }
        base = graph.makeIndirectAttribute(source: source)
    }

    var source: Attribute<Value> {
        get {
            guard let source = base.graph.indirectTarget(identifier) else {
                fatalError("IndirectAttribute.source requires a connected source.")
            }
            return Attribute(identifier: source)
        }
        nonmutating set {
            base.graph.setIndirectTarget(base, to: newValue)
        }
    }

    func resetSource() {
        base.graph.resetIndirectTarget(identifier)
    }

    var dependency: AGAttribute? {
        get { identifier.indirectDependency }
        nonmutating set { identifier.indirectDependency = newValue }
    }

    var value: Value {
        get { base.value }
        nonmutating set { base.value = newValue }
    }

    var wrappedValue: Value {
        get { value }
        nonmutating set { value = newValue }
    }

    var projectedValue: Attribute<Value> { base }

    subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Attribute<Member> {
        base[keyPath: keyPath]
    }

    func changedValue(
        options: AGValueOptions
    ) -> (value: Value, changed: Bool) {
        base.changedValue(options: options)
    }
}

/// Typed weak reference to an AG attribute.
/// The type parameter is used only for type-safe access via toStrong().
@dynamicMemberLookup
struct WeakAttribute<T>: Hashable, CustomStringConvertible, Sendable {
    var base: AGWeakAttribute

    init() { self.base = .invalid }
    init(base: AGWeakAttribute) { self.base = base }
    init(_ attribute: Attribute<T>) { self = attribute.asWeak() }
    init(_ attribute: Attribute<T>?) {
        self = attribute?.asWeak() ?? WeakAttribute()
    }

    var isInvalid: Bool { base.isInvalid }
    func isValid(in graph: _AGGraph) -> Bool { base.isValid(in: graph) }

    var attribute: Attribute<T>? {
        get {
            guard let identifier = base.attribute else { return nil }
            return Attribute<T>(identifier: identifier)
        }
        set { self = WeakAttribute(newValue) }
    }

    var projectedValue: Attribute<T>? {
        get { attribute }
        set { attribute = newValue }
    }

    var value: T? { attribute?.value }
    var wrappedValue: T? { value }

    subscript<Member>(dynamicMember keyPath: KeyPath<T, Member>) -> Attribute<Member>? {
        attribute?[keyPath: keyPath]
    }

    var description: String { base.description }

    func toStrong() -> Attribute<T> { Attribute<T>(base.toStrong()) }

    func changedValue(
        options: AGValueOptions
    ) -> (value: T, changed: Bool)? {
        guard let result = _AGGraphGetWeakValue(self, options: options) else {
            return nil
        }
        return (result.value, result.flags.rawValue & 1 != 0)
    }
}


// MARK: - Optional Attribute

/// Type-erased optional wrapper around an AG node identifier.
/// Used as the backing storage for `OptionalAttribute<T>` so that
/// `OptionalAttribute` can be stored in non-generic contexts.
struct AnyOptionalAttribute: Hashable, CustomStringConvertible {
    var identifier: AGAttribute

    init() { identifier = .invalid }
    init(_ id: AGAttribute) { identifier = id }
    init(_ id: AGAttribute?) { identifier = id ?? .invalid }
    init(_ id: AGWeakAttribute) { identifier = id.attribute ?? .invalid }
    init<Value>(_ attribute: OptionalAttribute<Value>) { self = attribute.base }

    static var current: AnyOptionalAttribute {
        AnyOptionalAttribute(AGAttribute.current)
    }

    var attribute: AGAttribute? {
        get { identifier.isInvalid ? nil : identifier }
        set { identifier = newValue ?? .invalid }
    }

    func unsafeCast<Value>(to type: Value.Type) -> OptionalAttribute<Value> {
        OptionalAttribute(base: self)
    }

    func map<Result>(_ body: (AGAttribute) -> Result) -> Result? {
        attribute.map(body)
    }

    var description: String {
        attribute?.description ?? "nil"
    }
}

/// An optional typed reference to an AG node.
/// Used for fields that may or may not have an associated AG node
/// (e.g., `_layoutComputer`, `safeAreaInsets`, `containerSize`).
@dynamicMemberLookup
struct OptionalAttribute<Value>: Hashable, CustomStringConvertible {
    var base: AnyOptionalAttribute

    init() { base = AnyOptionalAttribute() }
    init(base: AnyOptionalAttribute) { self.base = base }
    init(_ attribute: Attribute<Value>) { base = AnyOptionalAttribute(attribute.identifier) }
    init(_ attribute: Attribute<Value>?) { base = AnyOptionalAttribute(attribute?.identifier) }
    init(_ attribute: WeakAttribute<Value>) { base = AnyOptionalAttribute(attribute.base) }

    var attribute: Attribute<Value>? {
        get {
            guard let identifier = base.attribute else { return nil }
            return Attribute<Value>(identifier: identifier)
        }
        set { base.attribute = newValue?.identifier }
    }

    var projectedValue: Attribute<Value>? {
        get { attribute }
        set { attribute = newValue }
    }

    var value: Value? { attribute?.value }
    var wrappedValue: Value? { value }

    subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Attribute<Member>? {
        attribute?[keyPath: keyPath]
    }

    func map<Result>(_ body: (Attribute<Value>) -> Result) -> Result? {
        attribute.map(body)
    }

    func changedValue(
        options: AGValueOptions
    ) -> (value: Value, changed: Bool)? {
        attribute?.changedValue(options: options)
    }

    var description: String { base.description }
}

#if DEBUG
private final class AGAttributeInvalidOwner {}

extension AGAttribute {
    var _debugSeedAtCreation: UInt32 { _seedAtCreation }

    func _debugValidate() {
        guard !isInvalid else {
            fatalError("Invalid AGAttribute sentinel cannot be used as a graph node.")
        }
        guard let graph = _AGGraph.current else {
            fatalError("AGAttribute(\(rawValue)) accessed outside an active _AGGraph context.")
        }
        if _owningGraphID != ObjectIdentifier(graph) {
            fatalError(
                "AGAttribute(\(rawValue)) accessed from a different _AGGraph than the one it was created in " +
                "(e.g. reading a ViewGraph attribute inside a GestureGraph rule). " +
                "Use the owning graph's cachedValue(for:) for cross-graph reads."
            )
        }
        guard graph._isValid(index: rawValue, seed: _seedAtCreation) else {
            let state = graph._debugSlotStateDescription(at: rawValue)
            fatalError(
                "AGAttribute(\(rawValue)) is stale or invalid in its owning _AGGraph " +
                "(createdSeed=\(_seedAtCreation), \(state))."
            )
        }
    }

    init(rawValue: UInt32, owningGraph: ObjectIdentifier, seed: UInt32) {
        self.rawValue = rawValue
        self._owningGraphID = owningGraph
        self._seedAtCreation = seed
    }

    private init(uncheckedRawValue: UInt32) {
        self.rawValue = uncheckedRawValue
        self._owningGraphID = ObjectIdentifier(AGAttributeInvalidOwner.self)
        self._seedAtCreation = 0
    }

    // AGAttribute.== is a same-graph comparison by contract. Cross-graph collections
    // (e.g. _AGChangeSet) partition by _AGGraph so this operator never runs across
    // graphs. The assert below is a tripwire if that invariant is ever broken.
    static func == (lhs: Self, rhs: Self) -> Bool {
        if lhs.isInvalid || rhs.isInvalid {
            return lhs.rawValue == rhs.rawValue
        }
        assert(
            lhs._owningGraphID == rhs._owningGraphID,
            "Comparing AGAttributes from different graphs."
        )
        return lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension AGWeakAttribute {
    init(identifier: UInt32, seed: UInt32, owningGraph: ObjectIdentifier) {
        self.identifier = identifier
        self.seed = seed
        self._owningGraphID = owningGraph
    }

    private init(uncheckedIdentifier: UInt32, seed: UInt32) {
        self.identifier = uncheckedIdentifier
        self.seed = seed
        self._owningGraphID = ObjectIdentifier(AGAttributeInvalidOwner.self)
    }
}

extension Attribute {
    fileprivate func _debugValidate() {
        identifier._debugValidate()
    }
}
#else
extension AGAttribute {
    func _debugValidate() {}
}

extension Attribute {
    fileprivate func _debugValidate() {}
}
#endif
