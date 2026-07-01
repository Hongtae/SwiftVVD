//
//  File: AGRule.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

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
/// Implement `updateValue()` to recompute the output. Call `_AGGraph.setStatefulOutput(_:)`
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

/// Hidden lifecycle hook for stateful attributes owned by removable subgraphs.
protocol RemovableAttribute: _AttributeBody {
    static func willRemove(attribute: AGAttribute)
    static func didReinsert(attribute: AGAttribute)
}

extension RemovableAttribute {
    static func willRemove(attribute: AGAttribute) {}
    static func didReinsert(attribute: AGAttribute) {}
}

protocol _AnyStatefulBox: AnyObject {
    func callUpdate()
    func callDestroy()
    func callWillRemove(attribute: AGAttribute)
    func callDidReinsert(attribute: AGAttribute)
}

class _StatefulBox<R: StatefulRule>: _AnyStatefulBox {
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
        _AGGraph.withRuleContext(attribute) {
            body()
        }
    }

    subscript<Value>(_ attribute: Attribute<Value>) -> Value {
        attribute.value
    }

    subscript<Value>(_ attribute: WeakAttribute<Value>) -> Value? {
        guard let graph = _AGGraph.current,
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
        guard let graph = _AGGraph.current else { return false }
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
        guard let id = _AGGraph.currentRuleContextAttribute else {
            fatalError("Rule.context accessed outside rule evaluation.")
        }
        return RuleContext(attribute: Attribute<Value>(id))
    }
}

extension StatefulRule {
    var context: RuleContext<Value> {
        guard let id = _AGGraph.currentRuleContextAttribute else {
            fatalError("StatefulRule.context accessed outside rule evaluation.")
        }
        return RuleContext(attribute: Attribute<Value>(id))
    }
}
