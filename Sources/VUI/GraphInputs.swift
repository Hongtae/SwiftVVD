//
//  File: GraphInputs.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// PropertyKey hierarchy for graph inputs.
//
// PropertyKey  (PropertyList.swift) - base: defaultValue, valuesEqual
//   -> GraphInput - adds AG reuse support (makeReusable, tryToReuse, isTriviallyReusable)
//      -> ViewInput - marker: keys stored in _ViewInputs.customInputs channel

/// Opaque map passed to GraphReusable methods.
/// Reserved for AG reuse bookkeeping.
struct IndirectAttributeMap {}

/// Protocol for values that support AG node reuse.
protocol GraphReusable {
    mutating func makeReusable(indirectMap: IndirectAttributeMap)
    mutating func tryToReuse(by other: Self, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool
    static var isTriviallyReusable: Bool { get }
}

extension GraphReusable {
    mutating func makeReusable(indirectMap: IndirectAttributeMap) {}
    mutating func tryToReuse(by other: Self, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool { false }
    static var isTriviallyReusable: Bool { false }
}

/// Refinement of PropertyKey that participates in AG node reuse.
/// Keys conforming to GraphInput can be stored in _GraphInputs.customInputs (base channel).
protocol GraphInput: PropertyKey {
    static func makeReusable(indirectMap: IndirectAttributeMap, value: inout Value)
    static func tryToReuse(_ a: Value, by b: Value, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool
    static var isTriviallyReusable: Bool { get }
}

extension GraphInput {
    static func makeReusable(indirectMap: IndirectAttributeMap, value: inout Value) {}
    static func tryToReuse(_ a: Value, by b: Value, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool { false }
    static var isTriviallyReusable: Bool { false }
}

extension GraphInput where Value: GraphReusable {
    static func makeReusable(indirectMap: IndirectAttributeMap, value: inout Value) {
        value.makeReusable(indirectMap: indirectMap)
    }
    static func tryToReuse(_ a: Value, by b: Value, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool {
        var copy = a
        return copy.tryToReuse(by: b, indirectMap: indirectMap, testOnly: testOnly)
    }
    static var isTriviallyReusable: Bool { Value.isTriviallyReusable }
}

/// Marker refinement of GraphInput for view-level channel.
/// Keys conforming to ViewInput are stored in _ViewInputs.customInputs (view channel).
/// No additional requirements.
protocol ViewInput: GraphInput {}

struct UsingGraphicsRenderer: ViewInput {
    typealias Value = Bool
    static var defaultValue: Bool { false }
}

struct ArchivedViewInput: ViewInput {
    struct Flags: OptionSet {
        var rawValue: UInt8

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        static let isArchived = Flags(rawValue: 1 << 0)
        static let stableIDs = Flags(rawValue: 1 << 1)
        static let customFontURLs = Flags(rawValue: 1 << 2)
        static let assetCatalogRefences = Flags(rawValue: 1 << 3)
        static let preciseTextLayout = Flags(rawValue: 1 << 4)
        static let intelligenceContent = Flags(rawValue: 1 << 5)
        static let publicArchive = Flags(rawValue: 1 << 6)
    }

    struct DeploymentVersion: RawRepresentable, Hashable, Comparable, Codable {
        var rawValue: Int8

        init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        static let v5 = DeploymentVersion(rawValue: 1)
        static let v6 = DeploymentVersion(rawValue: 2)
        static let v7 = DeploymentVersion(rawValue: 3)
        static let v7_4 = DeploymentVersion(rawValue: 4)

        static var current: DeploymentVersion { .v7_4 }
        static var oldest: DeploymentVersion { .v5 }

        static func < (lhs: DeploymentVersion, rhs: DeploymentVersion) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            rawValue = try container.decode(Int8.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    struct Value: Equatable {
        var flags: Flags
        var deploymentVersion: DeploymentVersion

        init(
            flags: Flags = [],
            deploymentVersion: DeploymentVersion = .current
        ) {
            self.flags = flags
            self.deploymentVersion = deploymentVersion
        }

        var isArchived: Bool { flags.contains(.isArchived) }
        var stableIDs: Bool { flags.contains(.stableIDs) }
        var customFontURLs: Bool { flags.contains(.customFontURLs) }
        var assetCatalogRefences: Bool { flags.contains(.assetCatalogRefences) }
        var preciseTextLayout: Bool { flags.contains(.preciseTextLayout) }

        static var isArchived: Value {
            Value(flags: .isArchived)
        }
    }

    static var defaultValue: Value { Value() }
}

/// A generic single-owner reference box.
/// Used in `_GraphInputs.cachedEnvironment` so that copying `_GraphInputs`
/// (a struct) still shares the same `CachedEnvironment` instance across
/// all descendants of the same view subtree.
final class MutableBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// Animation time value passed through the AG graph.
/// Only stored property: `seconds: Double` (8 bytes).
struct Time {
    var seconds: Double

    static var zero: Time { Time(seconds: 0) }
    static var infinity: Time { Time(seconds: Double.infinity) }
    static var systemUptime: Time { Time(seconds: ProcessInfo.processInfo.systemUptime) }

    init(seconds: Double = 0) { self.seconds = seconds }

    static func + (lhs: Time, rhs: Double) -> Time { Time(seconds: lhs.seconds + rhs) }
    static func - (lhs: Time, rhs: Double) -> Double { lhs.seconds - rhs }
    static func < (lhs: Time, rhs: Time) -> Bool { lhs.seconds < rhs.seconds }
    static func == (lhs: Time, rhs: Time) -> Bool { lhs.seconds == rhs.seconds }
}

/// Render phase passed through the AG graph.
/// Stored as one UInt32: bit 0 is the removal flag, bits 1...31 are resetSeed.
struct Phase {
    var rawValue: UInt32 = 0

    var isBeingRemoved: Bool {
        get { (rawValue & 0x1) != 0 }
        set {
            if newValue {
                rawValue |= 0x1
            } else {
                rawValue &= ~UInt32(0x1)
            }
        }
    }

    var resetSeed: UInt32 {
        get { rawValue >> 1 }
        set { rawValue = (rawValue & 0x1) | (newValue &<< 1) }
    }

    var isInserted: Bool { !isBeingRemoved }

    static var invalid: Phase { Phase(value: UInt32(bitPattern: Int32(-16))) }

    init() {}
    init(value: UInt32) {
        self.rawValue = value
    }

    mutating func merge(_ other: Phase) {
        let preservedRemoval = rawValue & 0x1
        let seedBits = rawValue & ~UInt32(0x1)
        rawValue = (seedBits &+ other.rawValue) | preservedRemoval
    }
}

struct ViewPhaseOverride: GraphInput {
    static var defaultValue: OptionalAttribute<Phase> { OptionalAttribute() }

    static func valuesEqual(
        _ lhs: OptionalAttribute<Phase>,
        _ rhs: OptionalAttribute<Phase>
    ) -> Bool {
        lhs.base.identifier == rhs.base.identifier
    }
}

/// Animated view frame snapshot passed through the animation system.
/// { origin: CGPoint (16 bytes), size: ViewSize (32 bytes) }
/// Total size: 48 bytes.
struct ViewFrame: Equatable {
    var origin: CGPoint
    var size: ViewSize

    init(size: ViewSize) {
        self.origin = .zero
        self.size = size
    }
    init(origin: CGPoint, size: ViewSize) {
        self.origin = origin
        self.size = size
    }

    mutating func round(toMultipleOf value: CGFloat) {
        origin.x = (origin.x / value).rounded() * value
        origin.y = (origin.y / value).rounded() * value
        size.value.width  = (size.value.width  / value).rounded() * value
        size.value.height = (size.value.height / value).rounded() * value
    }
}

/// Shared environment cache passed down the view tree via `_GraphInputs`.
/// Copying `_GraphInputs` preserves the same `CachedEnvironment` reference
/// (via `MutableBox`) so all descendants share a single environment Attribute.
struct CachedEnvironment {

    // Direct Int identity used for cache lookup.
    struct ID: Hashable {
        var value: Int
    }

    struct MapItem {
        var key: ID
        var value: AGAttribute
    }

    struct AnimatedFrame {
        var position:          Attribute<CGPoint>
        var size:              Attribute<ViewSize>
        var pixelLength:       Attribute<CGFloat>
        var time:              Attribute<Time>
        var transaction:       Attribute<Transaction>
        var viewPhase:         Attribute<Phase>
        var animatedFrame:     Attribute<ViewFrame>
        var _animatedPosition: Attribute<CGPoint>?
        var _animatedSize:     Attribute<ViewSize>?
        var _animatedCGSize:   Attribute<CGSize>?
    }

    /// The live `EnvironmentValues` AG node.
    /// Reading `.value` inside a rule registers a dependency so the rule
    /// re-evaluates automatically when the environment changes.
    var environment: Attribute<EnvironmentValues>

    /// Style-map items threaded through the environment cache.
    var mapItems: [MapItem]

    /// Per-frame animation layout snapshot.
    /// Nil until layout AG nodes are wired. Animation modifiers read from here.
    var animatedFrame: AnimatedFrame?

    /// Cache of resolved shape styles keyed by ResolvedShapeStyles.
    /// Reserved for resolved shape-style storage.
    var resolvedShapeStyles: Any?

    /// Platform-specific renderer cache (e.g. Metal layer reference).
    var platformCache: Any?

    init(environment: Attribute<EnvironmentValues>) {
        self.environment = environment
        self.mapItems = []
        self.animatedFrame = nil
        self.resolvedShapeStyles = nil
        self.platformCache = nil
    }

    func replacingEnvironment(_ environment: Attribute<EnvironmentValues>) -> CachedEnvironment {
        var copy = CachedEnvironment(environment: environment)
        copy.animatedFrame = animatedFrame
        return copy
    }

    mutating func attribute<Value>(
        id: ID,
        _ value: @escaping (EnvironmentValues) -> Value
    ) -> Attribute<Value> {
        if let item = mapItems.first(where: { $0.key == id }) {
            return Attribute<Value>(item.value)
        }
        guard let graph = _AGGraph.current else {
            fatalError("CachedEnvironment.attribute(id:_:) called outside an active _AGGraph context.")
        }
        let environment = environment
        let attribute = graph.makeRule {
            value(environment.value)
        }
        mapItems.append(MapItem(key: id, value: attribute.identifier))
        return attribute
    }
}

/// The bundle of AG context Attributes passed from parent to child during
/// `_makeView` traversal.  All fields are Attribute references (IDs), so
/// copying this struct is cheap.
public struct _GraphInputs {
    struct Options: OptionSet, Sendable {
        var rawValue: UInt32

        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        static let animationsDisabled = Options(rawValue: 0x1)
        static let viewRequestsLayoutComputer = Options(rawValue: 0x2)
        static let viewStackOrientationIsDefined = Options(rawValue: 0x4)
        static let viewStackOrientationIsHorizontal = Options(rawValue: 0x8)
        static let viewDisplayListAccessibility = Options(rawValue: 0x10)
        static let viewNeedsGeometry = Options(rawValue: 0x20)
        static let viewNeedsGeometryAccessibility = Options(rawValue: 0x40)
        static let needsStableDisplayListIDs = Options(rawValue: 0x100)
        static let supportsVariableFrameDuration = Options(rawValue: 0x400)
        static let needsDynamicLayout = Options(rawValue: 0x800)
        static let needsAccessibility = Options(rawValue: 0x1000)
        static let doNotScrape = Options(rawValue: 0x2000)
    }

    /// Arbitrary typed values threaded through the view tree (styles, options, etc.).
    var customInputs: PropertyList

    /// Current animation time.
    var time: Attribute<Time>

    /// Shared environment cache.  `MutableBox` ensures all copies of
    /// `_GraphInputs` in the same subtree point at the same `CachedEnvironment`.
    var cachedEnvironment: MutableBox<CachedEnvironment>

    /// Current render phase (referenced as `viewPhase` inside AnimatedFrame).
    var phase: Attribute<Phase>

    /// Current transaction (animation parameters, etc.).
    var transaction: Attribute<Transaction>

    /// Bitmask tracking which debug properties have changed since the last evaluation.
    var changedDebugProperties: UInt32

    /// Bitmask of options controlling view list traversal behavior.
    var options: Options

    /// Set of AG node IDs whose inputs have been merged into this context.
    var mergedInputs: Set<AGAttribute>

    // Base-channel subscript stores in customInputs (PropertyList).
    subscript<T: GraphInput>(_ key: T.Type) -> T.Value {
        get { customInputs.value(forKey: key) }
        set { customInputs.setValue(newValue, forKey: key) }
    }

    mutating func applyViewPhaseOverrideIfNeeded() {
        guard let phaseOverride = self[ViewPhaseOverride.self].attribute else {
            return
        }
        phase = phaseOverride
    }

    // Stack operations for base-channel keys with Stack values.
    // Used by the ViewModifier body-input stack (BodyInput<Content>).

    /// Push an element onto the Stack stored for `key` in the base channel.
    mutating func append<T: GraphInput, E>(_ element: E, forKey key: T.Type) where T.Value == Stack<E> {
        var stack = customInputs.value(forKey: key)
        stack = .node(element, stack)
        customInputs.setValue(stack, forKey: key)
    }

    /// Pop and return the top element from the Stack stored for `key` in the base channel.
    /// Returns nil if the stack is empty.
    mutating func popLast<T: GraphInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        var stack = customInputs.value(forKey: key)
        let elem = stack.pop()
        customInputs.setValue(stack, forKey: key)
        return elem
    }

    /// Peek at the top element of the Stack stored for `key` without consuming it.
    /// Returns nil if the stack is empty.
    func top<T: GraphInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        customInputs.value(forKey: key).top
    }

    /// Returns true when any current BodyInput<T> stack in customInputs is non-empty.
    var containsNonEmptyBodyStack: Bool {
        customInputs.forEachValue(ofType: Stack<BodyInputElement>.self) { _, stack in
            !stack.isEmpty
        }
    }

    // MARK: - merge(_:ignoringPhase:)
    //
    // Merges `other`'s fields into `self`:
    //   1. PropertyList merge (customInputs)
    //   2. Environment: create MergedEnvironment AG rule if attrs differ
    //   3. Transaction: create MergedTransaction AG rule if attrs differ
    //   4. Phase (skipped when ignoringPhase==true): create MergedPhase AG rule if attrs differ
    //   5. flags OR, import other animations-disabled option, mergedInputs union
    //
    // mergedInputs (Set<AGAttribute>) prevents duplicate rule creation for the same attr pair.
    mutating func merge(_ other: _GraphInputs, ignoringPhase: Bool) {
        guard let graph = _AGGraph.current else {
            fatalError("_GraphInputs.merge(_:ignoringPhase:) called outside an active _AGGraph context.")
        }

        // Step 1: PropertyList
        customInputs.merge(other.customInputs)

        // Step 2: Environment
        let selfEnvID  = cachedEnvironment.value.environment.identifier
        let otherEnvID = other.cachedEnvironment.value.environment.identifier
        if selfEnvID != otherEnvID, mergedInputs.insert(otherEnvID).inserted {
            let selfWeak = cachedEnvironment.value.environment.asWeak().raw
            let newEnvAttr = graph.makeRule(MergedEnvironment(selfWeak: selfWeak,
                                                               otherRaw: otherEnvID.rawValue))
            var newCE = cachedEnvironment.value
            newCE.environment = newEnvAttr
            cachedEnvironment = MutableBox(newCE)
            changedDebugProperties |= 0x20
        }

        // Step 3: Transaction
        let selfTxID  = transaction.identifier
        let otherTxID = other.transaction.identifier
        if selfTxID != otherTxID, mergedInputs.insert(otherTxID).inserted {
            let selfWeak = transaction.asWeak().raw
            transaction = graph.makeRule(MergedTransaction(selfWeak: selfWeak,
                                                            otherRaw: otherTxID.rawValue))
        }

        // Step 4: Phase
        if !ignoringPhase {
            let selfPhaseID  = phase.identifier
            let otherPhaseID = other.phase.identifier
            if selfPhaseID != otherPhaseID, mergedInputs.insert(otherPhaseID).inserted {
                let selfWeak = phase.asWeak().raw
                phase = graph.makeRule(MergedPhase(selfWeak: selfWeak,
                                                    otherRaw: otherPhaseID.rawValue))
                changedDebugProperties |= 0x40
            }
        }

        // Step 5: remaining fields
        changedDebugProperties |= other.changedDebugProperties
        if other.options.contains(.animationsDisabled) {
            options.insert(.animationsDisabled)
        }
        mergedInputs.formUnion(other.mergedInputs)
    }

    // Alias: merge(_:) == merge(_:ignoringPhase: false)
    mutating func merge(_ other: _GraphInputs) {
        merge(other, ignoringPhase: false)
    }
}

// MARK: - Merged* AG Rules
// All three follow the same pattern: weak ref to self attr + strong raw of other attr.
// updateValue() reads both (registering AG dependencies), merges, returns result.
// When the weak ref is invalid (subgraph was deallocated), returns other's value unchanged.

// Merges two EnvironmentValues by chaining their PropertyLists (self = higher priority).
struct MergedEnvironment: Rule {
    typealias Value = EnvironmentValues
    let selfWeak: AGWeakAttribute
    let otherRaw: UInt32

    func updateValue() -> EnvironmentValues {
        let graph = _AGGraph.current!
        let otherAttr = Attribute<EnvironmentValues>(AGAttribute(rawValue: otherRaw))
        let otherEnv = otherAttr.value
        guard selfWeak.isValid(in: graph) else { return otherEnv.trackingCopy() }
        let selfEnv = Attribute<EnvironmentValues>(selfWeak.toStrong()).value
        var mergedList = selfEnv._plist
        mergedList.merge(otherEnv._plist)
        return EnvironmentValues.tracking(mergedList)
    }
}

// Merges two Transactions by chaining their PropertyLists (self = higher priority).
struct MergedTransaction: Rule {
    typealias Value = Transaction
    let selfWeak: AGWeakAttribute
    let otherRaw: UInt32

    func updateValue() -> Transaction {
        let graph = _AGGraph.current!
        let otherAttr = Attribute<Transaction>(AGAttribute(rawValue: otherRaw))
        let otherTx = otherAttr.value
        guard selfWeak.isValid(in: graph) else { return otherTx }
        var result = Attribute<Transaction>(selfWeak.toStrong()).value
        result.plist.merge(otherTx.plist)
        return result
    }
}

// Merges two Phases while preserving the receiver removal bit.
struct MergedPhase: Rule {
    typealias Value = Phase
    let selfWeak: AGWeakAttribute
    let otherRaw: UInt32

    func updateValue() -> Phase {
        let graph = _AGGraph.current!
        let otherAttr = Attribute<Phase>(AGAttribute(rawValue: otherRaw))
        let otherPhase = otherAttr.value
        guard selfWeak.isValid(in: graph) else { return otherPhase }
        var result = Attribute<Phase>(selfWeak.toStrong()).value
        result.merge(otherPhase)
        return result
    }
}
