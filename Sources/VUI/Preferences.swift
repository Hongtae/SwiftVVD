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

/// Sub-protocol of PreferenceKey whose _isReadableByHost is always true.
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

    /// A bitmask of `Property` values that tracks which debug properties are active.
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
/// - `hostKeys`: an AG node tracking dynamically-registered keys;
///   when this node's value changes, affected rules re-evaluate.
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
    }

    var preferences: [KeyValue] = []
    var debugProperties: _ViewDebug.Properties = .init(rawValue: 0)

    mutating func append<K: PreferenceKey>(_ keyType: K.Type, node: AGAttribute) {
        preferences.append(KeyValue(
            key: keyType,
            value: node,
            _makeReduceRule: { nodes, graph in
                let attr: Attribute<K.Value> = graph.makeRule {
                    var combined = K.defaultValue
                    for nodeID in nodes {
                        let val = Attribute<K.Value>(nodeID).value
                        K.reduce(value: &combined) { val }
                    }
                    return combined
                }
                return attr.identifier
            }
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
                _makeReduceRule: entry.representative._makeReduceRule
            ))
        }
        return result
    }
}

extension PreferencesOutputs {
    /// Registers a preference transform for Key.
    /// Creates a new AG rule that reads existing K outputs, applies transform, and replaces entry.
    /// If K._isReadableByHost == true, also participates in the HostPreferencesCombiner pipeline
    /// handled in ViewGraph.init via side-effect rule.
    mutating func makePreferenceTransformer<K: PreferenceKey>(
        key: K.Type,
        transformAttr: Attribute<(inout K.Value) -> Void>,
        transactionAttr: Attribute<Transaction>,
        graph: AttributeGraph
    ) {
        // Collect existing nodes for K from child outputs.
        let existingNodes = values(for: K.self)

        // Create a new AG rule: reduce existing children, then apply transform.
        let transformedAttr: Attribute<K.Value> = graph.makeRule {
            var value = K.defaultValue
            for nodeID in existingNodes {
                let val = Attribute<K.Value>(nodeID).value
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
    /// For "last wins" reduce semantics this is equivalent to replace;
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
