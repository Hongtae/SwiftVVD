//
//  File: Preferences.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// A named value produced by a view and collected upward through the view tree.
public protocol PreferenceKey {
    associatedtype Value
    static var defaultValue: Value { get }
    static func reduce(value: inout Value, nextValue: () -> Value)
    // Whether removed views' preference values are retained during the update.
    static var _includesRemovedValues: Bool { get }
    // Whether the host (WindowController) can read this preference via preferenceValue(_:).
    static var _isReadableByHost: Bool { get }
}

extension PreferenceKey {
    public static var _includesRemovedValues: Bool { false }
    public static var _isReadableByHost: Bool { false }
}

extension PreferenceKey where Self.Value: ExpressibleByNilLiteral {
    public static var defaultValue: Self.Value { nil }
}

/// Sub-protocol of PreferenceKey whose _isReadableByHost is always true.
/// Used for preference keys that the host can register, read, and remove.
public protocol HostPreferenceKey: PreferenceKey {}

extension HostPreferenceKey {
    public static var _isReadableByHost: Bool { true }
}

/// A type-erased container for a set of `PreferenceKey` metatypes.
/// Stored in `PreferencesInputs.keys` (static keys known at build time)
/// and `PreferencesInputs.hostKeys` (dynamic keys tracked as an AG node).
///
/// `keys` stores the actual metatypes (not just ObjectIdentifiers) so that
/// callers can open the existential and recover the concrete `K` via SE-0352.
/// This matches the reference framework's `Array<PreferenceKey.Type>` layout.
struct PreferenceKeys {
    var keys: [any PreferenceKey.Type] = []

    mutating func insert<K: PreferenceKey>(_ keyType: K.Type) {
        if !keys.contains(where: { $0 == keyType }) { keys.append(keyType) }
    }

    func contains<K: PreferenceKey>(_ keyType: K.Type) -> Bool {
        keys.contains(where: { $0 == keyType })
    }
}

/// Debug/inspector support for the view tree.
public enum _ViewDebug {
    /// Identifies a single debuggable property of a view node.
    public enum Property: UInt32, Hashable {
        case type           = 0
        case value          = 1
        case transform      = 2
        case position       = 3
        case size           = 4
        case environment    = 5
        case phase          = 6
        case layoutComputer = 7
        case displayList    = 8
    }

    /// A bitmask of `Property` values tracking which debug properties are active.
    public struct Properties: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        init(_ property: Property) { self.init(rawValue: 1 << property.rawValue) }

        public static let type:           Properties = .init(.type)
        public static let value:          Properties = .init(.value)
        public static let transform:      Properties = .init(.transform)
        public static let position:       Properties = .init(.position)
        public static let size:           Properties = .init(.size)
        public static let environment:    Properties = .init(.environment)
        public static let phase:          Properties = .init(.phase)
        public static let layoutComputer: Properties = .init(.layoutComputer)
        public static let displayList:    Properties = .init(.displayList)
        public static let all:            Properties = [.type, .value, .transform, .position,
                                                        .size, .environment, .phase,
                                                        .layoutComputer, .displayList]
    }

    /// Opaque container for collected debug data.
    public struct Data {}
}

/// Inputs controlling which preferences a view subtree needs to collect.
///
/// - `keys`: the static set of preference keys requested by the host at
///   `_makeViewList` time (compile-time known).
/// - `hostKeys`: an AG node tracking dynamically-registered keys.
///   When this node's value changes, affected rules re-evaluate.
struct PreferencesInputs {
    var keys: PreferenceKeys
    var hostKeys: Attribute<PreferenceKeys>

    init(keys: PreferenceKeys, hostKeys: Attribute<PreferenceKeys>) {
        self.keys = keys
        self.hostKeys = hostKeys
    }
}

/// The preferences produced by a view during `_makeView`.
/// Each entry pairs the preference key's metatype with a type-erased AG node ID
/// that will hold the accumulated value for that key.
struct PreferencesOutputs {
    struct KeyValue {
        let key: any PreferenceKey.Type
        let value: AGAttribute      // type-erased raw node ID
        /// Builds a new AG rule that reduces `nodes` into a single value using
        /// the concrete `PreferenceKey.reduce` implementation captured at append time.
        let _makeReduceRule: (_ nodes: [AGAttribute], _ graph: AttributeGraph) -> AGAttribute
        /// Points the indirect placeholder at the matching concrete attr in `concrete`.
        /// Non-placeholder outputs leave this nil.
        let _attachIndirect: ((_ concrete: PreferencesOutputs, _ graph: AttributeGraph) -> Void)?
        /// Detaches the indirect placeholder (points it to nil for the default value).
        /// Non-placeholder outputs leave this nil.
        let _detachIndirect: ((_ graph: AttributeGraph) -> Void)?
        /// Registers a permanent AG dependency on `dep` so this placeholder is
        /// invalidated whenever `dep` changes. Non-placeholder outputs leave this nil.
        let _setIndirectDependency: ((_ dep: AGAttribute, _ graph: AttributeGraph) -> Void)?
    }

    var preferences: [KeyValue] = []
    var debugProperties: _ViewDebug.Properties = .init(rawValue: 0)

    mutating func append<K: PreferenceKey>(_ keyType: K.Type, node: AGAttribute) {
        preferences.append(KeyValue(
            key: keyType,
            value: node,
            _makeReduceRule: { nodes, graph in
                let weakNodes = nodes.compactMap { graph.weakAttributeIfValid(for: $0) }
                let attr: Attribute<K.Value> = graph.makeRule {
                    var combined = K.defaultValue
                    for weakNode in weakNodes where weakNode.isValid(in: graph) {
                        let val = Attribute<K.Value>(weakNode.toStrong()).value
                        K.reduce(value: &combined) { val }
                    }
                    return combined
                }
                return attr.identifier
            },
            _attachIndirect: nil,
            _detachIndirect: nil,
            _setIndirectDependency: nil
        ))
    }

    /// Merges multiple `PreferencesOutputs` by reducing per-key AG nodes.
    /// For each unique key across all outputs, creates a single AG reduce rule.
    static func merge(_ outputs: [PreferencesOutputs], in graph: AttributeGraph) -> PreferencesOutputs {
        var grouped: [ObjectIdentifier: (representative: KeyValue, nodes: [AGAttribute])] = [:]
        for output in outputs {
            for kv in output.preferences {
                let id = ObjectIdentifier(kv.key)
                if grouped[id] == nil {
                    grouped[id] = (kv, [])
                }
                grouped[id]!.nodes.append(kv.value)
            }
        }
        var result = PreferencesOutputs()
        for (_, entry) in grouped {
            let reducedNode = entry.representative._makeReduceRule(entry.nodes, graph)
            result.preferences.append(KeyValue(
                key: entry.representative.key,
                value: reducedNode,
                _makeReduceRule: entry.representative._makeReduceRule,
                _attachIndirect: nil,
                _detachIndirect: nil,
                _setIndirectDependency: nil
            ))
        }
        return result
    }
}

extension PreferencesInputs {
    /// Creates placeholder preference outputs for the requested keys.
    /// Each placeholder is backed by an indirect AG attribute for the key.
    func makeIndirectOutputs() -> PreferencesOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("PreferencesInputs.makeIndirectOutputs called outside AG context.")
        }
        var outputs = PreferencesOutputs()
        for key in keys.keys {
            _appendIndirectPreference(key, to: &outputs, in: graph)
        }
        return outputs
    }

    private func _appendIndirectPreference<K: PreferenceKey>(
        _ key: K.Type,
        to outputs: inout PreferencesOutputs,
        in graph: AttributeGraph
    ) {
        let indirectAttr: Attribute<K.Value> = graph.makeIndirectAttribute(defaultValue: K.defaultValue)
        outputs.preferences.append(PreferencesOutputs.KeyValue(
            key: K.self,
            value: indirectAttr.identifier,
            _makeReduceRule: { nodes, graph in
                let weakNodes = nodes.compactMap { graph.weakAttributeIfValid(for: $0) }
                let reduced: Attribute<K.Value> = graph.makeRule {
                    var combined = K.defaultValue
                    for weakNode in weakNodes where weakNode.isValid(in: graph) {
                        let val = Attribute<K.Value>(weakNode.toStrong()).value
                        K.reduce(value: &combined) { val }
                    }
                    return combined
                }
                return reduced.identifier
            },
            _attachIndirect: { concrete, graph in
                let matches = concrete.preferences.filter { $0.key == K.self }
                switch matches.count {
                case 0:
                    graph.setIndirectTarget(indirectAttr.identifier, to: nil)
                case 1:
                    let concreteKV = matches[0]
                    graph.setIndirectTarget(indirectAttr.identifier, to: concreteKV.value)
                default:
                    let weakMatches = matches.compactMap { graph.weakAttributeIfValid(for: $0.value) }
                    let reduced: Attribute<K.Value> = graph.makeRule {
                        var combined = K.defaultValue
                        for weakNode in weakMatches where weakNode.isValid(in: graph) {
                            let val = Attribute<K.Value>(weakNode.toStrong()).value
                            K.reduce(value: &combined) { val }
                        }
                        return combined
                    }
                    graph.setIndirectTarget(indirectAttr.identifier, to: reduced.identifier)
                }
            },
            _detachIndirect: { graph in
                graph.setIndirectTarget(indirectAttr.identifier, to: nil)
            },
            _setIndirectDependency: { dep, graph in
                graph.setIndirectDependency(indirectAttr.identifier, dependsOn: dep)
            }
        ))
    }
}

extension PreferencesOutputs {
    /// Points each placeholder preference attr at the matching concrete attr.
    func attachIndirectOutputs(to placeholders: PreferencesOutputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("PreferencesOutputs.attachIndirectOutputs called outside AG context.")
        }
        for placeholder in placeholders.preferences {
            placeholder._attachIndirect?(self, graph)
        }
    }

    /// Registers a permanent AG dependency on `attr` for all placeholder slots.
    func setIndirectDependency(_ attr: AGAttribute?) {
        guard let dep = attr else { return }
        guard let graph = AttributeGraph.current else {
            fatalError("PreferencesOutputs.setIndirectDependency called outside AG context.")
        }
        for kv in preferences {
            kv._setIndirectDependency?(dep, graph)
        }
    }

    /// Detaches all placeholder slots (points them to nil for the default value).
    func detachIndirectOutputs() {
        guard let graph = AttributeGraph.current else {
            fatalError("PreferencesOutputs.detachIndirectOutputs called outside AG context.")
        }
        for kv in preferences {
            kv._detachIndirect?(graph)
        }
    }
}

extension PreferencesOutputs {
    /// Registers a preference transform for Key.
    /// Creates a new AG rule that reads existing K outputs, applies transform, and replaces entry.
    /// Host-readable keys also feed the host preference combiner through ViewGraph side effects.
    mutating func makePreferenceTransformer<K: PreferenceKey>(
        key: K.Type,
        transformAttr: Attribute<(inout K.Value) -> Void>,
        transactionAttr: Attribute<Transaction>,
        graph: AttributeGraph
    ) {
        // Collect existing nodes for K from child outputs.
        let existingNodes = values(for: K.self)
        let weakNodes = existingNodes.compactMap { graph.weakAttributeIfValid(for: $0) }

        // Create a new AG rule: reduce existing children, then apply transform.
        let transformedAttr: Attribute<K.Value> = graph.makeRule {
            var value = K.defaultValue
            for weakNode in weakNodes where weakNode.isValid(in: graph) {
                let val = Attribute<K.Value>(weakNode.toStrong()).value
                K.reduce(value: &value) { val }
            }
            let transaction = transactionAttr.value
            withTransaction(transaction) {
                transformAttr.value(&value)
            }
            return value
        }

        // Replace old K entries with the single transformed node.
        preferences.removeAll(where: {
            ObjectIdentifier($0.key) == ObjectIdentifier(K.self)
        })
        append(K.self, node: transformedAttr.identifier)
    }

    func values(for key: any PreferenceKey.Type) -> [AGAttribute] {
        let id = ObjectIdentifier(key)
        var result: [AGAttribute] = []
        for kv in preferences {
            if ObjectIdentifier(kv.key) == id {
                result.append(kv.value)
            }
        }
        return result
    }

    /// Reduces all entries for `key` into a single AG node using the stored
    /// `_makeReduceRule`. Returns nil if no entry exists for the key.
    /// For "last wins" reduce semantics this is equivalent to replace.
    /// for union semantics (e.g. OptionSet) all entries are merged correctly.
    func reducedValue<K: PreferenceKey>(for key: K.Type,
                                        in graph: AttributeGraph) -> Attribute<K.Value>? {
        let nodes = values(for: key)
        guard !nodes.isEmpty,
              let representative = preferences.first(where: {
                  ObjectIdentifier($0.key) == ObjectIdentifier(key)
              }) else { return nil }
        return Attribute(representative._makeReduceRule(nodes, graph))
    }
}
