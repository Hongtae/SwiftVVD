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

    mutating func insert(_ keyType: any PreferenceKey.Type) {
        if !keys.contains(where: { $0 == keyType }) { keys.append(keyType) }
    }

    mutating func formUnion(_ other: PreferenceKeys) {
        for key in other.keys {
            insert(key)
        }
    }

    func contains<K: PreferenceKey>(_ keyType: K.Type) -> Bool {
        keys.contains(where: { $0 == keyType })
    }

    func contains(_ keyType: any PreferenceKey.Type) -> Bool {
        keys.contains(where: { $0 == keyType })
    }
}

struct HostPreferencesKey: PreferenceKey {
    static var defaultValue: PreferenceValues { PreferenceValues() }

    static func reduce(value: inout PreferenceValues, nextValue: () -> PreferenceValues) {
        value.combine(with: nextValue())
    }
}

struct VersionSeed: Equatable, Hashable, Sendable {
    var value: UInt32 = 0

    init(value: UInt32 = 0) {
        self.value = value
    }
}

struct PreferenceValues {
    struct Value<A> {
        var value: A
        var seed: VersionSeed
    }

    struct Entry {
        var key: any PreferenceKey.Type
        var seed: VersionSeed
        var value: Any
    }

    var entries: [Entry] = []

    mutating func append<K: PreferenceKey>(
        _ key: K.Type,
        value: K.Value,
        seed: VersionSeed = VersionSeed()
    ) {
        entries.append(Entry(key: key, seed: seed, value: value))
    }

    mutating func setValue<K: PreferenceKey>(
        _ value: K.Value,
        seed: VersionSeed = VersionSeed(),
        for key: K.Type
    ) {
        let keyID = ObjectIdentifier(key)
        entries.removeAll { ObjectIdentifier($0.key) == keyID }
        append(key, value: value, seed: seed)
    }

    func value<K: PreferenceKey>(for key: K.Type) -> Value<K.Value> {
        storedValue(for: key) ?? Value(value: K.defaultValue, seed: VersionSeed())
    }

    func storedValue<K: PreferenceKey>(for key: K.Type) -> Value<K.Value>? {
        let keyID = ObjectIdentifier(key)
        var combined = K.defaultValue
        var seed = VersionSeed()
        var found = false

        for entry in entries where ObjectIdentifier(entry.key) == keyID {
            if let wrapped = entry.value as? Value<K.Value> {
                K.reduce(value: &combined) { wrapped.value }
                seed = wrapped.seed
                found = true
            } else if let value = entry.value as? K.Value {
                K.reduce(value: &combined) { value }
                seed = entry.seed
                found = true
            }
        }

        guard found else { return nil }
        return Value(value: combined, seed: seed)
    }

    mutating func combine(with other: PreferenceValues) {
        entries.append(contentsOf: other.entries)
    }

    static func combineHostKeyValues(
        into values: inout PreferenceValues,
        keys requestedKeys: PreferenceKeys,
        childIndices: Range<Int>,
        childAt: (Int) -> (PreferenceKeys, PreferenceValues)
    ) {
        for key in requestedKeys.keys {
            values._combineHostValue(
                key,
                childIndices: childIndices,
                childAt: childAt
            )
        }
    }

    private mutating func _combineHostValue<K: PreferenceKey>(
        _ key: K.Type,
        childIndices: Range<Int>,
        childAt: (Int) -> (PreferenceKeys, PreferenceValues)
    ) {
        let local = storedValue(for: key)
        var combined = local?.value ?? K.defaultValue
        var seed = local?.seed ?? VersionSeed()

        for index in childIndices {
            let (childKeys, childValues) = childAt(index)
            guard childKeys.contains(key) else {
                continue
            }
            if let childValue = childValues.storedValue(for: key) {
                K.reduce(value: &combined) { childValue.value }
                seed = childValue.seed
            }
        }

        setValue(combined, seed: seed, for: key)
    }
}

struct PreferenceCombiner<A: PreferenceKey>: StatefulRule {
    typealias Value = A.Value

    var attributes: [WeakAttribute<A.Value>] = []

    mutating func add(_ attribute: WeakAttribute<A.Value>) {
        attributes.append(attribute)
    }

    @discardableResult
    mutating func remove(_ attribute: AGAttribute) -> Bool {
        let oldCount = attributes.count
        attributes.removeAll { $0.raw.identifier == attribute.rawValue }
        return attributes.count != oldCount
    }

    mutating func updateValue() {
        AttributeGraph.setStatefulOutput(value)
    }

    var value: A.Value {
        guard let graph = AttributeGraph.current else {
            fatalError("PreferenceCombiner.value accessed outside AG context.")
        }
        var combined = A.defaultValue
        for attribute in attributes where attribute.isValid(in: graph) {
            let value = attribute.toStrong().value
            A.reduce(value: &combined) { value }
        }
        return combined
    }
}

struct HostPreferencesCombiner: StatefulRule {
    typealias Value = PreferenceValues

    struct Child {
        var _keys: WeakAttribute<PreferenceKeys>
        var _values: WeakAttribute<PreferenceValues>
    }

    var _keys: Attribute<PreferenceKeys>
    var _values: OptionalAttribute<PreferenceValues>
    var children: [Child] = []

    mutating func addChild(
        keys: Attribute<PreferenceKeys>,
        values: WeakAttribute<PreferenceValues>
    ) {
        let child = Child(_keys: keys.asWeak(), _values: values)
        if let index = children.firstIndex(where: {
            $0._keys.raw.identifier == keys.identifier.rawValue
        }) {
            children[index] = child
        } else {
            children.append(child)
        }
    }

    @discardableResult
    mutating func removeChild(for keys: Attribute<PreferenceKeys>) -> Bool {
        guard let index = children.firstIndex(where: {
            $0._keys.raw.identifier == keys.identifier.rawValue
        }) else {
            return false
        }
        children.remove(at: index)
        return true
    }

    mutating func updateValue() {
        AttributeGraph.setStatefulOutput(value)
    }

    var value: PreferenceValues {
        guard let graph = AttributeGraph.current else {
            fatalError("HostPreferencesCombiner.value accessed outside AG context.")
        }

        var values = _values.attribute?.value ?? PreferenceValues()
        let requestedKeys = _keys.value
        var childValues: [(keys: PreferenceKeys, values: PreferenceValues)] = []
        for child in children
            where child._keys.isValid(in: graph) && child._values.isValid(in: graph) {
            childValues.append((
                keys: child._keys.toStrong().value,
                values: child._values.toStrong().value
            ))
        }

        PreferenceValues.combineHostKeyValues(
            into: &values,
            keys: requestedKeys,
            childIndices: childValues.indices,
            childAt: { index in childValues[index] }
        )
        return values
    }
}

final class PreferenceBridge {
    struct BridgedPreference {
        var key: any PreferenceKey.Type
        var combiner: AGWeakAttribute
    }

    weak var viewGraph: ViewGraph?
    var isValid: Bool
    var children: [Unmanaged<ViewGraph>]
    var requestedPreferences: PreferenceKeys
    var bridgedViewInputs: PropertyList
    var _hostPreferenceKeys: WeakAttribute<PreferenceKeys>
    var _hostPreferencesCombiner: WeakAttribute<PreferenceValues>
    var bridgedPreferences: [BridgedPreference]

    init(
        viewGraph: ViewGraph?,
        isValid: Bool = true,
        children: [Unmanaged<ViewGraph>] = [],
        requestedPreferences: PreferenceKeys,
        bridgedViewInputs: PropertyList = PropertyList(),
        hostPreferenceKeys: WeakAttribute<PreferenceKeys>,
        hostPreferencesCombiner: WeakAttribute<PreferenceValues>,
        bridgedPreferences: [BridgedPreference] = []
    ) {
        self.viewGraph = viewGraph
        self.isValid = isValid
        self.children = children
        self.requestedPreferences = requestedPreferences
        self.bridgedViewInputs = bridgedViewInputs
        self._hostPreferenceKeys = hostPreferenceKeys
        self._hostPreferencesCombiner = hostPreferencesCombiner
        self.bridgedPreferences = bridgedPreferences
    }

    convenience init() {
        guard let graph = AttributeGraph.current else {
            fatalError("PreferenceBridge.init() called outside AG context.")
        }
        let requestedKeys = PreferenceKeys()
        let hostKeys = graph.makeInput(value: requestedKeys)
        let hostCombiner = graph.makeStatefulRule(
            HostPreferencesCombiner(
                _keys: hostKeys,
                _values: OptionalAttribute()
            )
        )
        self.init(
            viewGraph: GraphHost.currentHost as? ViewGraph,
            requestedPreferences: requestedKeys,
            hostPreferenceKeys: hostKeys.asWeak(),
            hostPreferencesCombiner: hostCombiner.asWeak()
        )
    }

    func wrapInputs(_ inputs: inout _ViewInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("PreferenceBridge.wrapInputs called outside AG context.")
        }
        guard isValid,
              _hostPreferenceKeys.isValid(in: graph) else {
            return
        }

        inputs.customInputs = bridgedViewInputs
        for key in requestedPreferences.keys {
            inputs.preferences.keys.insert(key)
        }

        inputs.preferences.hostKeys = graph.makeRule(
            MergePreferenceKeys(
                local: inputs.preferences.hostKeys.asWeak(),
                bridged: _hostPreferenceKeys
            )
        )
    }

    func wrapOutputs(_ outputs: inout PreferencesOutputs, inputs: _ViewInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("PreferenceBridge.wrapOutputs called outside AG context.")
        }
        guard isValid else {
            return
        }

        bridgedViewInputs = inputs.customInputs
        let outputRecords = outputs.preferences
        for output in outputRecords {
            if output.key == HostPreferencesKey.self {
                let hostValues = outputs.value(for: HostPreferencesKey.self)
                    .map { OptionalAttribute(Attribute<PreferenceValues>($0)) } ?? OptionalAttribute()
                let hostCombiner = graph.makeStatefulRule(
                    HostPreferencesCombiner(
                        _keys: inputs.preferences.hostKeys,
                        _values: hostValues
                    )
                )
                _hostPreferenceKeys = inputs.preferences.hostKeys.asWeak()
                _hostPreferencesCombiner = hostCombiner.asWeak()
                outputs.setValue(hostCombiner.identifier, for: HostPreferencesKey.self)
            } else if bridgedPreference(for: output.key) == nil {
                wrapPreferenceOutput(output.key, outputs: &outputs, graph: graph)
            }
        }
    }

    func invalidate() {
        guard isValid else { return }
        isValid = false
        let liveChildren = children.map { $0.takeUnretainedValue() }
        children.removeAll()
        requestedPreferences = PreferenceKeys()
        bridgedViewInputs = PropertyList()
        bridgedPreferences.removeAll()
        for child in liveChildren {
            child.setPreferenceBridge(to: nil, isInvalidating: true)
        }
        viewGraph = nil
    }

    func removedStateDidChange() {
        for child in children {
            child.takeUnretainedValue().updateRemovedState()
        }
    }

    func updateHostValues(_ keys: Attribute<PreferenceKeys>) {
        guard isValid else { return }
        viewGraph?.graphInvalidation(from: keys.identifier)
    }

    func addChild(_ child: ViewGraph) {
        guard !children.contains(where: { $0.takeUnretainedValue() === child }) else {
            return
        }
        children.append(Unmanaged.passUnretained(child))
    }

    func removeChild(_ child: ViewGraph) {
        children.removeAll { $0.takeUnretainedValue() === child }
    }

    func addValue(_ value: AGAttribute, for key: any PreferenceKey.Type) {
        func add<K: PreferenceKey>(_ key: K.Type) {
            addValue(Attribute<K.Value>(value), for: key)
        }
        _openExistential(key, do: add)
    }

    func addValue<K: PreferenceKey>(_ value: Attribute<K.Value>, for key: K.Type) {
        guard isValid,
              let graph = AttributeGraph.current,
              let bridgedPreference = bridgedPreference(for: key),
              bridgedPreference.combiner.isValid(in: graph),
              let weakValue = graph.weakAttributeIfValid(for: value.identifier) else {
            return
        }

        let combiner = bridgedPreference.combiner.toStrong()
        graph.mutateStatefulRule(combiner, as: PreferenceCombiner<K>.self) { body in
            body.add(WeakAttribute<K.Value>(weakValue))
        }
        graph.invalidateAttribute(combiner)
        viewGraph?.graphInvalidation(from: value.identifier)
    }

    @discardableResult
    func removeValue(
        _ value: AGAttribute,
        for key: any PreferenceKey.Type,
        isInvalidating: Bool = false
    ) -> Bool {
        var removed = false
        func remove<K: PreferenceKey>(_ key: K.Type) {
            removed = removeValue(
                Attribute<K.Value>(value),
                for: key,
                isInvalidating: isInvalidating
            )
        }
        _openExistential(key, do: remove)
        return removed
    }

    @discardableResult
    func removeValue<K: PreferenceKey>(
        _ value: Attribute<K.Value>,
        for key: K.Type,
        isInvalidating: Bool = false
    ) -> Bool {
        guard isValid,
              let graph = AttributeGraph.current,
              let bridgedPreference = bridgedPreference(for: key),
              bridgedPreference.combiner.isValid(in: graph) else {
            return false
        }

        let combiner = bridgedPreference.combiner.toStrong()
        var didMutate = false
        graph.mutateStatefulRule(combiner, as: PreferenceCombiner<K>.self) { body in
            didMutate = body.remove(value.identifier)
        }
        guard didMutate else { return false }

        graph.invalidateAttribute(combiner)
        viewGraph?.graphInvalidation(from: isInvalidating ? nil : value.identifier)
        return true
    }

    func addHostValues(
        _ values: WeakAttribute<PreferenceValues>,
        for keys: Attribute<PreferenceKeys>
    ) {
        guard isValid,
              let graph = AttributeGraph.current,
              _hostPreferencesCombiner.isValid(in: graph) else {
            return
        }

        let combiner = _hostPreferencesCombiner.toStrong().identifier
        graph.mutateStatefulRule(combiner, as: HostPreferencesCombiner.self) { body in
            body.addChild(keys: keys, values: values)
        }
        graph.invalidateAttribute(combiner)
        viewGraph?.graphInvalidation(from: keys.identifier)
    }

    func addHostValues(
        _ values: OptionalAttribute<PreferenceValues>,
        for keys: Attribute<PreferenceKeys>
    ) {
        guard let attribute = values.attribute else {
            return
        }
        addHostValues(attribute.asWeak(), for: keys)
    }

    func addHostValues(keys: Attribute<PreferenceKeys>, values: Attribute<PreferenceValues>) {
        guard isValid,
              let graph = AttributeGraph.current,
              _hostPreferencesCombiner.isValid(in: graph),
              let weakValues = graph.weakAttributeIfValid(for: values.identifier) else {
            return
        }

        addHostValues(WeakAttribute<PreferenceValues>(weakValues), for: keys)
    }

    @discardableResult
    func removeHostValues(
        for keys: Attribute<PreferenceKeys>,
        isInvalidating: Bool = false
    ) -> Bool {
        guard isValid,
              let graph = AttributeGraph.current,
              _hostPreferencesCombiner.isValid(in: graph) else {
            return false
        }

        let combiner = _hostPreferencesCombiner.toStrong().identifier
        var didMutate = false
        graph.mutateStatefulRule(combiner, as: HostPreferencesCombiner.self) { body in
            didMutate = body.removeChild(for: keys)
        }
        guard didMutate else { return false }

        graph.invalidateAttribute(combiner)
        viewGraph?.graphInvalidation(from: isInvalidating ? nil : keys.identifier)
        return true
    }

    @discardableResult
    func removeHostValues(
        keys: Attribute<PreferenceKeys>,
        isInvalidating: Bool = false
    ) -> Bool {
        removeHostValues(for: keys, isInvalidating: isInvalidating)
    }

    private func bridgedPreference<K: PreferenceKey>(for key: K.Type) -> BridgedPreference? {
        bridgedPreference(for: key as any PreferenceKey.Type)
    }

    private func bridgedPreference(for key: any PreferenceKey.Type) -> BridgedPreference? {
        let keyID = ObjectIdentifier(key)
        return bridgedPreferences.first {
            ObjectIdentifier($0.key) == keyID
        }
    }

    private func replaceBridgedPreference(
        key: any PreferenceKey.Type,
        combiner: AGWeakAttribute
    ) {
        let keyID = ObjectIdentifier(key)
        if let index = bridgedPreferences.firstIndex(where: {
            ObjectIdentifier($0.key) == keyID
        }) {
            bridgedPreferences[index] = BridgedPreference(key: key, combiner: combiner)
        } else {
            bridgedPreferences.append(BridgedPreference(key: key, combiner: combiner))
        }
    }

    private func wrapPreferenceOutput(
        _ key: any PreferenceKey.Type,
        outputs: inout PreferencesOutputs,
        graph: AttributeGraph
    ) {
        func wrap<K: PreferenceKey>(_ key: K.Type) {
            guard let value = outputs.value(for: key) else {
                return
            }
            let weakValue = graph.weakAttributeIfValid(for: value)
                .map { WeakAttribute<K.Value>($0) }
            let combiner = graph.makeStatefulRule(
                PreferenceCombiner<K>(
                    attributes: weakValue.map { [$0] } ?? []
                )
            )
            guard let weakCombiner = graph.weakAttributeIfValid(for: combiner.identifier) else {
                return
            }
            requestedPreferences.insert(key)
            replaceBridgedPreference(key: key, combiner: weakCombiner)
            outputs.setValue(combiner.identifier, for: key)
        }

        _openExistential(key, do: wrap)
    }
}

private struct MergePreferenceKeys: Rule {
    typealias Value = PreferenceKeys

    var local: WeakAttribute<PreferenceKeys>
    var bridged: WeakAttribute<PreferenceKeys>

    func updateValue() -> PreferenceKeys {
        guard let graph = AttributeGraph.current else {
            fatalError("MergePreferenceKeys.updateValue() called outside AG context.")
        }

        var keys = PreferenceKeys()
        if local.isValid(in: graph) {
            for key in local.toStrong().value.keys {
                keys.insert(key)
            }
        }
        if bridged.isValid(in: graph) {
            for key in bridged.toStrong().value.keys {
                keys.insert(key)
            }
        }
        return keys
    }
}

private struct PreferenceBridgeKey: EnvironmentKey {
    static var defaultValue: PreferenceBridge? { nil }

    static func _valuesEqual(_ lhs: PreferenceBridge?, _ rhs: PreferenceBridge?) -> Bool {
        lhs === rhs
    }
}

extension EnvironmentValues {
    var preferenceBridge: PreferenceBridge? {
        get { self[PreferenceBridgeKey.self] }
        set { self[PreferenceBridgeKey.self] = newValue }
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
    func value<K: PreferenceKey>(for key: K.Type) -> AGAttribute? {
        values(for: key).first
    }

    func value(for key: any PreferenceKey.Type) -> AGAttribute? {
        values(for: key).first
    }

    mutating func setValue<K: PreferenceKey>(_ value: AGAttribute?, for key: K.Type) {
        setValue(value, for: key as any PreferenceKey.Type)
    }

    mutating func setValue(_ value: AGAttribute?, for key: any PreferenceKey.Type) {
        let id = ObjectIdentifier(key)
        preferences.removeAll {
            ObjectIdentifier($0.key) == id
        }
        guard let value else {
            return
        }
        appendAny(key, node: value)
    }

    private mutating func appendAny(_ key: any PreferenceKey.Type, node: AGAttribute) {
        func appendOpened<K: PreferenceKey>(_ key: K.Type) {
            self.append(K.self, node: node)
        }

        _openExistential(key, do: appendOpened)
    }

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
