//
//  File: AGRule.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// MARK: - Protocols

/// Base protocol for all computed attribute bodies.
///
/// These methods define the lifecycle and update hooks dispatched by graph-owned
/// rule boxes.
protocol _AttributeBody {
    static func _destroySelf(_ body: UnsafeMutableRawPointer)
    static func _updateDefault(_ body: UnsafeMutableRawPointer)
    static var comparisonMode: AGComparisonMode { get }
    static var _hasDestroySelf: Bool { get }
    static var flags: AGAttributeTypeFlags { get }
}

protocol AttributeBodyVisitor {
    mutating func visit<Body: _AttributeBody>(body: UnsafePointer<Body>)
}

extension _AttributeBody {
    static func _destroySelf(_ body: UnsafeMutableRawPointer) {}
    static func _updateDefault(_ body: UnsafeMutableRawPointer) {}
    static var comparisonMode: AGComparisonMode { .layout }
    static var _hasDestroySelf: Bool { false }
    static var flags: AGAttributeTypeFlags { .mainThread }
    var updateWasCancelled: Bool { _AGGraphUpdateWasCancelled() }
}

/// A computed attribute body that exposes its result through `value`.
protocol Rule: _AttributeBody {
    associatedtype Value
    static var initialValue: Value? { get }
    var value: Value { get }
}

extension Rule {
    static var initialValue: Value? { nil }

    static func _updateDefault(_ body: UnsafeMutableRawPointer) {
        let rule = body.assumingMemoryBound(to: Self.self).pointee
        _AGGraph.setStatefulOutput(rule.value)
    }

    static func _update(_ body: UnsafeMutableRawPointer, attribute: AGAttribute) {
        _AGGraph.withRuleContext(attribute) {
            _updateDefault(body)
        }
    }

    var bodyChanged: Bool {
        _AGGraphAnyInputsChanged()
    }
}

extension Rule where Self: Hashable {
    func cachedValue(
        options: AGCachedValueOptions,
        owner: AGAttribute?
    ) -> Value {
        withUnsafePointer(to: self) { bodyPointer in
            Self._cachedValue(
                options: options,
                owner: owner,
                hashValue: hashValue,
                bodyPtr: UnsafeRawPointer(bodyPointer),
                update: { Self._update }
            ).pointee
        }
    }

    static func _cachedValue(
        options: AGCachedValueOptions,
        owner: AGAttribute?,
        hashValue: Int,
        bodyPtr: UnsafeRawPointer,
        update: () -> (UnsafeMutableRawPointer, AGAttribute) -> Void
    ) -> UnsafePointer<Value> {
        guard let graph = _AGGraph.current else {
            fatalError("Rule._cachedValue requires an active _AGGraph context.")
        }
        let rule = bodyPtr.assumingMemoryBound(to: Self.self).pointee
        // The typed Rule node owns evaluation dispatch.
        _ = update
        guard let pointer = graph.cachedRuleValue(
            for: rule,
            options: options,
            owner: owner,
            hashValue: hashValue,
            createIfMissing: true
        ) else {
            fatalError("Rule._cachedValue failed to create a cached value.")
        }
        return pointer
    }

    func cachedValueIfExists(
        options: AGCachedValueOptions,
        owner: AGAttribute?
    ) -> Value? {
        guard let graph = _AGGraph.current else {
            fatalError("Rule.cachedValueIfExists requires an active _AGGraph context.")
        }
        return graph.cachedRuleValue(
            for: self,
            options: options,
            owner: owner,
            hashValue: hashValue,
            createIfMissing: false
        )?.pointee
    }
}

/// Marker for attribute bodies. Conformance alone does not move evaluation to
/// another executor.
protocol AsyncAttribute: _AttributeBody {}

extension AsyncAttribute {
    static var flags: AGAttributeTypeFlags { [] }
}

protocol _AnyAttributeBodyBox: AnyObject {
    var bodyType: Any.Type { get }
    var bodyPointer: UnsafeMutableRawPointer { get }
    var typeFlags: AGAttributeTypeFlags { get }
    func callDestroy()
    func mutateBody<Body>(as type: Body.Type, _ body: (inout Body) -> Void) -> Bool
    func visitBody<Visitor: AttributeBodyVisitor>(_ visitor: inout Visitor)
}

protocol _AnyRuleBox: _AnyAttributeBodyBox {
    func publishValue(to graph: _AGGraph, for attribute: AGAttribute)
}

final class _RuleBox<R: Rule>: _AnyRuleBox {
    private let storage: UnsafeMutablePointer<R>

    init(_ rule: R) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: rule)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    func publishValue(to graph: _AGGraph, for attribute: AGAttribute) {
        graph.publishComputedValue(storage.pointee.value, for: attribute)
    }

    func mutateRule(_ body: (inout R) -> Void) {
        body(&storage.pointee)
    }

    var bodyType: Any.Type { R.self }
    var bodyPointer: UnsafeMutableRawPointer { UnsafeMutableRawPointer(storage) }
    var typeFlags: AGAttributeTypeFlags { R.flags }

    func callDestroy() {
        guard R._hasDestroySelf else { return }
        R._destroySelf(bodyPointer)
    }

    func mutateBody<Body>(as type: Body.Type, _ body: (inout Body) -> Void) -> Bool {
        guard ObjectIdentifier(Body.self) == ObjectIdentifier(R.self) else {
            return false
        }
        body(&bodyPointer.assumingMemoryBound(to: Body.self).pointee)
        return true
    }

    func visitBody<Visitor: AttributeBodyVisitor>(_ visitor: inout Visitor) {
        visitor.visit(body: UnsafePointer(storage))
    }
}

protocol _AnyRuleClosureBox: AnyObject {
    var isSideEffect: Bool { get }
    func publishValue(to graph: _AGGraph, for attribute: AGAttribute)
}

final class _RuleClosureBox<Value>: _AnyRuleClosureBox {
    private let rule: () -> Value
    let isSideEffect: Bool

    init(rule: @escaping () -> Value, isSideEffect: Bool) {
        self.rule = rule
        self.isSideEffect = isSideEffect
    }

    func publishValue(to graph: _AGGraph, for attribute: AGAttribute) {
        graph.publishComputedValue(rule(), for: attribute)
    }
}

protocol _AnyLowLevelAttributeBox: _AnyAttributeBodyBox {
    func callUpdate(attribute: AGAttribute)
}

final class _LowLevelAttributeBox<Body: _AttributeBody>: _AnyLowLevelAttributeBox {
    private let storage: UnsafeMutablePointer<Body>
    private let update: (UnsafeMutableRawPointer, AGAttribute) -> Void
    let typeFlags: AGAttributeTypeFlags

    init(
        body: Body,
        flags: AGAttributeTypeFlags,
        update: @escaping (UnsafeMutableRawPointer, AGAttribute) -> Void
    ) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: body)
        typeFlags = flags
        self.update = update
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    var bodyType: Any.Type { Body.self }
    var bodyPointer: UnsafeMutableRawPointer { UnsafeMutableRawPointer(storage) }

    func callUpdate(attribute: AGAttribute) {
        update(bodyPointer, attribute)
    }

    func callDestroy() {
        guard Body._hasDestroySelf else { return }
        Body._destroySelf(bodyPointer)
    }

    func mutateBody<OtherBody>(
        as type: OtherBody.Type,
        _ body: (inout OtherBody) -> Void
    ) -> Bool {
        guard ObjectIdentifier(OtherBody.self) == ObjectIdentifier(Body.self) else {
            return false
        }
        body(&bodyPointer.assumingMemoryBound(to: OtherBody.self).pointee)
        return true
    }

    func visitBody<Visitor: AttributeBodyVisitor>(_ visitor: inout Visitor) {
        visitor.visit(body: UnsafePointer(storage))
    }
}

/// An AG computed node that maintains mutable state between re-evaluations.
///
/// Unlike a plain `makeRule` closure, the conforming struct is stored inside the AG node
/// and reused on each evaluation, enabling lazy initialization and conditional output updates.
///
/// Implement `updateValue()` to recompute the output. Call `_AGGraph.setStatefulOutput(_:)`
/// inside `updateValue()` to publish a new value. If `setStatefulOutput` is not called, the
/// previously cached output is retained unchanged.
/// Used by view-system filters (e.g. GestureFilter, ContentShapeResponderFilter) that own
/// a lazily-initialized responder object and update only its properties on re-evaluation.
protocol StatefulRule: _AttributeBody {
    associatedtype Value
    static var initialValue: Value? { get }
    mutating func updateValue()
}

extension StatefulRule {
    static var initialValue: Value? { nil }

    static func _updateDefault(_ body: UnsafeMutableRawPointer) {
        body.assumingMemoryBound(to: Self.self).pointee.updateValue()
    }

    static func _update(_ body: UnsafeMutableRawPointer, attribute: AGAttribute) {
        _AGGraph.withRuleContext(attribute) {
            _updateDefault(body)
        }
    }

    var value: Value {
        get {
            guard let value = _AGGraph.currentStatefulOutput(Value.self) else {
                fatalError("StatefulRule.value read before the current rule published a value.")
            }
            return value
        }
        nonmutating set {
            _AGGraph.setStatefulOutput(newValue)
        }
    }

    var hasValue: Bool {
        _AGGraph.currentStatefulOutput(Value.self) != nil
    }

    var bodyChanged: Bool {
        _AGGraphAnyInputsChanged()
    }
}

/// Lifecycle hook for attribute bodies that own resources tied to a node.
protocol ObservedAttribute: _AttributeBody {
    mutating func destroy()
}

extension ObservedAttribute {
    static func _destroySelf(_ body: UnsafeMutableRawPointer) {
        body.assumingMemoryBound(to: Self.self).pointee.destroy()
    }

    static var _hasDestroySelf: Bool { true }
}

/// Hidden lifecycle hook for stateful attributes owned by removable subgraphs.
protocol RemovableAttribute: _AttributeBody {
    static func willRemove(attribute: AGAttribute)
    static func didReinsert(attribute: AGAttribute)
}

extension RemovableAttribute {
    static func willRemove(attribute: AGAttribute) {}
    static func didReinsert(attribute: AGAttribute) {}
}

protocol _AnyStatefulBox: _AnyAttributeBodyBox {
    func callUpdate()
    func callWillRemove(attribute: AGAttribute)
    func callDidReinsert(attribute: AGAttribute)
}

final class _StatefulBox<R: StatefulRule>: _AnyStatefulBox {
    private let storage: UnsafeMutablePointer<R>

    init(_ rule: R) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: rule)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    func mutateRule(_ body: (inout R) -> Void) {
        body(&storage.pointee)
    }

    var bodyType: Any.Type { R.self }
    var bodyPointer: UnsafeMutableRawPointer { UnsafeMutableRawPointer(storage) }
    var typeFlags: AGAttributeTypeFlags { R.flags }

    func mutateBody<Body>(as type: Body.Type, _ body: (inout Body) -> Void) -> Bool {
        guard ObjectIdentifier(Body.self) == ObjectIdentifier(R.self) else {
            return false
        }
        body(&bodyPointer.assumingMemoryBound(to: Body.self).pointee)
        return true
    }

    func visitBody<Visitor: AttributeBodyVisitor>(_ visitor: inout Visitor) {
        visitor.visit(body: UnsafePointer(storage))
    }

    func callUpdate() {
        storage.pointee.updateValue()
    }

    func callDestroy() {
        guard R._hasDestroySelf else { return }
        R._destroySelf(bodyPointer)
    }

    func callWillRemove(attribute: AGAttribute) {
        guard let type = R.self as? any RemovableAttribute.Type else { return }
        type.willRemove(attribute: attribute)
    }
    func callDidReinsert(attribute: AGAttribute) {
        guard let type = R.self as? any RemovableAttribute.Type else { return }
        type.didReinsert(attribute: attribute)
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
        guard let graph = _AGGraph.current else {
            fatalError("AnyRuleContext.update called outside an active graph.")
        }
        graph.withRuleUpdate(attribute, body: body)
    }

    func valueAndFlags<Value>(
        of input: Attribute<Value>,
        options: AGValueOptions
    ) -> (value: Value, flags: AGChangedValueFlags) {
        _AGGraphGetInputValue(
            input,
            relativeTo: attribute,
            options: options
        )
    }

    func changedValue<Value>(
        of input: Attribute<Value>,
        options: AGValueOptions
    ) -> (value: Value, changed: Bool) {
        let result = valueAndFlags(of: input, options: options)
        return (result.value, result.flags.contains(.changed))
    }

    subscript<Value>(_ attribute: Attribute<Value>) -> Value {
        _AGGraph.withRuleContext(self.attribute) {
            attribute.value
        }
    }

    subscript<Value>(_ attribute: WeakAttribute<Value>) -> Value? {
        guard let graph = _AGGraph.current,
              attribute.isValid(in: graph) else { return nil }
        return _AGGraph.withRuleContext(self.attribute) {
            attribute.toStrong().value
        }
    }

    subscript<Value>(_ attribute: OptionalAttribute<Value>) -> Value? {
        guard let attribute = attribute.attribute else { return nil }
        return _AGGraph.withRuleContext(self.attribute) {
            attribute.value
        }
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
        get {
            _AGGraph.withRuleContext(attribute.identifier) {
                guard let value = _AGGraph.currentStatefulOutput(Value.self) else {
                    fatalError("RuleContext.value read before the current rule published a value.")
                }
                return value
            }
        }
        nonmutating set {
            _AGGraph.withRuleContext(attribute.identifier) {
                _AGGraph.setStatefulOutput(newValue)
            }
        }
    }

    var hasValue: Bool {
        guard let graph = _AGGraph.current else { return false }
        return graph.hasCachedValue(for: attribute.identifier)
    }

    func update(body: () -> Void) {
        AnyRuleContext(self).update(body: body)
    }

    func valueAndFlags<OtherValue>(
        of input: Attribute<OtherValue>,
        options: AGValueOptions
    ) -> (value: OtherValue, flags: AGChangedValueFlags) {
        AnyRuleContext(self).valueAndFlags(of: input, options: options)
    }

    func changedValue<OtherValue>(
        of input: Attribute<OtherValue>,
        options: AGValueOptions
    ) -> (value: OtherValue, changed: Bool) {
        AnyRuleContext(self).changedValue(of: input, options: options)
    }

    subscript<OtherValue>(_ attribute: Attribute<OtherValue>) -> OtherValue {
        AnyRuleContext(self)[attribute]
    }

    subscript<OtherValue>(_ attribute: WeakAttribute<OtherValue>) -> OtherValue? {
        AnyRuleContext(self)[attribute]
    }

    subscript<OtherValue>(_ attribute: OptionalAttribute<OtherValue>) -> OtherValue? {
        AnyRuleContext(self)[attribute]
    }
}

extension Rule {
    var attribute: Attribute<Value> {
        context.attribute
    }

    var context: RuleContext<Value> {
        guard let id = _AGGraph.currentRuleContextAttribute else {
            fatalError("Rule.context accessed outside rule evaluation.")
        }
        return RuleContext(attribute: Attribute<Value>(id))
    }
}

extension StatefulRule {
    var attribute: Attribute<Value> {
        context.attribute
    }

    var context: RuleContext<Value> {
        guard let id = _AGGraph.currentRuleContextAttribute else {
            fatalError("StatefulRule.context accessed outside rule evaluation.")
        }
        return RuleContext(attribute: Attribute<Value>(id))
    }
}

// MARK: - Standard Attribute Bodies

struct External<Value>: _AttributeBody, CustomStringConvertible {
    init() {}

    static var flags: AGAttributeTypeFlags { [] }
    static var comparisonMode: AGComparisonMode { .storedRepresentation }
    static func _update(_ body: UnsafeMutableRawPointer, attribute: AGAttribute) {}

    var description: String { String(describing: Value.self) }
}

struct _External: _AttributeBody, CustomStringConvertible {
    static var flags: AGAttributeTypeFlags { [] }
    static var comparisonMode: AGComparisonMode { .storedRepresentation }

    var description: String { "External value" }
}

struct Focus<Root, Value>: Rule, CustomStringConvertible {
    var root: Attribute<Root>
    var keyPath: KeyPath<Root, Value>

    init(root: Attribute<Root>, keyPath: KeyPath<Root, Value>) {
        self.root = root
        self.keyPath = keyPath
    }

    static var flags: AGAttributeTypeFlags { [] }
    var value: Value { root.value[keyPath: keyPath] }
    var description: String { "• \(String(describing: Value.self))" }
}

struct Map<Input, Output>: Rule, CustomStringConvertible {
    var arg: Attribute<Input>
    let body: (Input) -> Output

    init(_ arg: Attribute<Input>, _ body: @escaping (Input) -> Output) {
        self.arg = arg
        self.body = body
    }

    static var flags: AGAttributeTypeFlags { [] }
    var value: Output { body(arg.value) }
    var description: String { "λ \(String(describing: Output.self))" }
}
