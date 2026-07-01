//
//  File: AGAttribute.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - Core Node Types

#if DEBUG
private final class AGAttributeInvalidOwner {}
#endif

/// The raw identifier for an AG node: an index into the graph's slot array.
struct AGAttribute: Hashable, CustomDebugStringConvertible, Sendable {
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
        assert(lhs._owningGraphID == rhs._owningGraphID,
               "Comparing AGAttributes from different graphs.")
        return lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
#else
    func _debugValidate() {}

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

    var debugDescription: String {
        if isInvalid {
            return "@invalid"
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
struct AGWeakAttribute: Hashable, Sendable {
    static let invalid = AGWeakAttribute(uncheckedIdentifier: 0, seed: 0)

    let identifier: UInt32
    let seed: UInt32
    var isInvalid: Bool { identifier == 0 && seed == 0 }

#if DEBUG
    private let _owningGraphID: ObjectIdentifier
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
        guard let graph = _AGGraph.current else {
            fatalError("Attempted to read an Attribute outside of an active _AGGraph context.")
        }
        return graph.value(for: identifier) as! Value
    }

    // Primarily used for State/Input nodes to push new values.
    // Can also be used to inject an initial fallback value into a rule node
    // to resolve potential dependency cycles before it is first evaluated.
    func setValue(_ newValue: Value, transaction: Transaction = Transaction()) {
        _debugValidate()
        guard let graph = _AGGraph.current else {
            fatalError("Attempted to write to an Attribute outside of an active _AGGraph context.")
        }
        graph.setValue(for: self, to: newValue, transaction: transaction)
    }

    /// Creates a typed weak reference to this attribute, capturing the current generation seed.
    func asWeak() -> WeakAttribute<Value> {
        _debugValidate()
        guard let graph = _AGGraph.current else {
            fatalError("Attempted to read an Attribute outside of an active _AGGraph context.")
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
        guard let graph = _AGGraph.current else {
            fatalError("Attempted to write to an Attribute outside of an active _AGGraph context.")
        }
        graph.setValue(for: self, to: newValue, transaction: transaction)
    }
}

/// Typed weak reference to an AG attribute.
/// The type parameter is used only for type-safe access via toStrong().
struct WeakAttribute<T>: Hashable, Sendable {
    let raw: AGWeakAttribute

    init() { self.raw = .invalid }
    init(_ raw: AGWeakAttribute) { self.raw = raw }

    var isInvalid: Bool { raw.isInvalid }
    func isValid(in graph: _AGGraph) -> Bool { raw.isValid(in: graph) }

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
