//
//  File: GraphInputs.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol Feature: ViewInputBoolFlag {
    static var isEnabled: Bool { get }
}

extension Feature {
    static var defaultValue: Bool { isEnabled }
}

struct ImprovedButtonGestureFeature: Feature {
    typealias Value = Bool

    static var isEnabled: Bool { true }
}

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

/// Animation time value passed through the AG graph.
/// Only stored property: `seconds: Double` (8 bytes).
struct Time: Comparable, Hashable {
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

private struct SavedTransactionKey: GraphInput {
    static var defaultValue: [Attribute<Transaction>] { [] }

    static func valuesEqual(
        _ lhs: [Attribute<Transaction>],
        _ rhs: [Attribute<Transaction>]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.identifier == $1.identifier
        }
    }
}

/// The bundle of AG context Attributes passed from parent to child during
/// `_makeView` traversal.  All fields are Attribute references (IDs), so
/// copying this struct is cheap.
public struct _GraphInputs: GraphReusable {
    /// Render phase passed through the graph.
    /// Stored as one UInt32: bit 0 is the removal flag, bits 1...31 are resetSeed.
    struct Phase: Equatable {
        private var removalMask: UInt32 { 1 << 0 }
        private var resetSeedShift: UInt32 { 1 }
        private var resetSeedMask: UInt32 { ~removalMask }
        private var invalidValue: UInt32 {
            UInt32(bitPattern: Int32(-16))
        }

        var value: UInt32 = 0

        var isBeingRemoved: Bool {
            get { (value & removalMask) != 0 }
            set {
                if newValue {
                    value |= removalMask
                } else {
                    value &= resetSeedMask
                }
            }
        }

        var resetSeed: UInt32 {
            get { value >> resetSeedShift }
            set {
                value = (value & removalMask) |
                    (newValue &<< resetSeedShift)
            }
        }

        var isInserted: Bool { !isBeingRemoved }

        static var invalid: Phase {
            let phase = Phase()
            return Phase(value: phase.invalidValue)
        }

        init() {}

        init(value: UInt32) {
            self.value = value
        }

        mutating func merge(_ other: Phase) {
            let preservedRemoval = value & removalMask
            let seedBits = value & resetSeedMask
            value = (seedBits &+ other.value) | preservedRemoval
        }
    }

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
    var phase: Attribute<_GraphInputs.Phase>

    /// Current transaction (animation parameters, etc.).
    var transaction: Attribute<Transaction>

    /// Bitmask tracking which debug properties have changed since the last evaluation.
    var changedDebugProperties: UInt32

    /// Bitmask of options controlling view list traversal behavior.
    var options: Options

    /// Set of AG node IDs whose inputs have been merged into this context.
    var mergedInputs: Set<AGAttribute>

    init(
        time: Attribute<Time>,
        phase: Attribute<_GraphInputs.Phase>,
        environment: Attribute<EnvironmentValues>,
        transaction: Attribute<Transaction>
    ) {
        customInputs = PropertyList()
        self.time = time
        cachedEnvironment = MutableBox(
            CachedEnvironment(environment: environment)
        )
        self.phase = phase
        self.transaction = transaction
        changedDebugProperties = .max
        options = []
        mergedInputs = []
    }

    /// Forks reference-backed caches before a retained child graph is built.
    /// Attribute identities and ordinary graph inputs remain shared.
    mutating func copyCaches() {
        cachedEnvironment = MutableBox(cachedEnvironment.value)
    }

    // Base-channel subscript stores in customInputs (PropertyList).
    subscript<T: GraphInput>(_ key: T.Type) -> T.Value {
        get { customInputs.value(forKey: key) }
        set { customInputs.setValue(newValue, forKey: key) }
    }

    subscript<T: GraphInput>(_ key: T.Type) -> T.Value
        where T.Value: GraphReusable {
        get { customInputs.value(forKey: key) }
        set {
            recordReusableInput(key)
            customInputs.setValue(newValue, forKey: key)
        }
    }

    private mutating func recordReusableInput<T: GraphInput>(
        _ key: T.Type
    ) where T.Value: GraphReusable {
        guard GraphReuseOptions.current.contains(.expandedReuse) else {
            return
        }
        var storage = customInputs.value(forKey: ReusableInputs.self)
        // Consecutive writes of the same key describe one reuse slot.
        if let top = storage.stack.top,
           ObjectIdentifier(top) == ObjectIdentifier(key) {
            return
        }
        var filter = BloomFilter()
        filter.insert(key)
        storage.filter.value |= filter.value
        storage.stack = .node(key, storage.stack)
        customInputs.setValue(
            storage,
            forKey: ReusableInputs.self
        )
    }

    mutating func append<T: GraphInput, E>(
        _ element: E,
        to key: T.Type
    ) where T.Value == Stack<E> {
        var stack = customInputs.value(forKey: key)
        stack = .node(element, stack)
        customInputs.setValue(stack, forKey: key)
    }

    mutating func append<T: GraphInput, E: GraphReusable>(
        _ element: E,
        to key: T.Type
    ) where T.Value == Stack<E> {
        recordReusableInput(key)
        var stack = customInputs.value(forKey: key)
        stack = .node(element, stack)
        customInputs.setValue(stack, forKey: key)
    }

    mutating func popLast<T: GraphInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        var stack = customInputs.value(forKey: key)
        let elem = stack.pop()
        customInputs.setValue(stack, forKey: key)
        return elem
    }

    func top<T: GraphInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        customInputs.value(forKey: key).top
    }

    /// Returns true when any current BodyInput<T> stack in customInputs is non-empty.
    var containsNonEmptyBodyStack: Bool {
        customInputs.forEachValue(ofType: Stack<BodyInputElement>.self) { _, stack in
            !stack.isEmpty
        }
    }

    mutating func pushStableIndex(_ index: Int) {
        guard options.contains(.needsStableDisplayListIDs) else { return }
        pushScope(id: index)
    }

    mutating func pushStableID<ID: Hashable>(_ id: ID) {
        guard options.contains(.needsStableDisplayListIDs) else { return }

        // Prefer the identity's direct strong-hash witness. Other Encodable
        // values are canonicalized before opening the child namespace.
        if let stronglyHashable = id as? any StronglyHashable {
            pushScope(id: stronglyHashable)
            return
        }

        let hash = makeStableIDData(from: id) ?? StrongHash.random()
        pushScope(id: hash)
    }

    mutating func pushStableType(_ type: Any.Type) {
        guard options.contains(.needsStableDisplayListIDs) else { return }
        pushScope(id: makeStableTypeData(type))
    }

    var stableIDScope:
        WeakAttribute<_DisplayList_StableIdentityScope>? {
        guard options.contains(.needsStableDisplayListIDs) else {
            return nil
        }
        let scope = self[_DisplayList_StableIdentityScope.self]
        return scope.isInvalid ? nil : scope
    }

    private mutating func pushScope<ID: StronglyHashable>(id: ID) {
        let parentWeak = self[_DisplayList_StableIdentityScope.self]
        guard let parentAttribute = parentWeak.attribute else {
            fatalError(
                "Stable identity scope push requires a live parent scope."
            )
        }

        let parent = parentAttribute.valueAndFlags(
            options: .withoutDependency
        ).value
        let child = Attribute(
            value: _DisplayList_StableIdentityScope(
                id: id,
                parent: parent
            )
        )
        let childWeak = WeakAttribute(child)
        self[_DisplayList_StableIdentityScope.self] = childWeak

        // The graph owns the scope value; the root tracks only weak handles
        // so discarded subtrees can be pruned during lazy map materialization.
        parent.root.scopes.append(childWeak)
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
            let selfWeak = cachedEnvironment.value.environment.asWeak().base
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
            let selfWeak = transaction.asWeak().base
            transaction = graph.makeRule(MergedTransaction(selfWeak: selfWeak,
                                                            otherRaw: otherTxID.rawValue))
        }

        // Step 4: Phase
        if !ignoringPhase {
            let selfPhaseID  = phase.identifier
            let otherPhaseID = other.phase.identifier
            if selfPhaseID != otherPhaseID, mergedInputs.insert(otherPhaseID).inserted {
                let selfWeak = phase.asWeak().base
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

    mutating func makeReusable(indirectMap: IndirectAttributeMap) {
        // Standard graph inputs become indirect attributes before a reusable
        // element is materialized. The original input bundle remains the key
        // used later by `tryToReuse`.
        time.makeReusable(
            indirectMap: indirectMap,
            withoutInvalidation: false
        )
        phase.makeReusable(
            indirectMap: indirectMap,
            withoutInvalidation: false
        )
        changedDebugProperties |= 0x40

        var environment = cachedEnvironment.value.environment
        environment.makeReusable(
            indirectMap: indirectMap,
            withoutInvalidation: false
        )
        cachedEnvironment = MutableBox(
            CachedEnvironment(environment: environment)
        )
        // A reusable subtree must not retain the previous environment cache
        // object after its environment attribute becomes indirect.
        changedDebugProperties |= 0x60

        // Transaction reuse suppresses only cross-context callback forwarding;
        // retargeting the indirect attribute still propagates dirtiness.
        transaction.makeReusable(
            indirectMap: indirectMap,
            withoutInvalidation: true
        )

        var storage = customInputs.value(
            forKey: ReusableInputs.self
        ).stack
        while let key = storage.pop() {
            makeReusableInput(
                key,
                indirectMap: indirectMap
            )
        }
    }

    mutating func tryToReuse(
        by other: _GraphInputs,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        guard time.tryToReuse(
            by: other.time,
            indirectMap: indirectMap,
            withoutInvalidation: false,
            testOnly: testOnly
        ) else {
            return false
        }
        guard phase.tryToReuse(
            by: other.phase,
            indirectMap: indirectMap,
            withoutInvalidation: false,
            testOnly: testOnly
        ) else {
            return false
        }

        var environment = cachedEnvironment.value.environment
        guard environment.tryToReuse(
            by: other.cachedEnvironment.value.environment,
            indirectMap: indirectMap,
            withoutInvalidation: false,
            testOnly: testOnly
        ) else {
            return false
        }

        // Keep the transaction's callback boundary consistent with its
        // reusable indirect attribute above.
        guard transaction.tryToReuse(
            by: other.transaction,
            indirectMap: indirectMap,
            withoutInvalidation: true,
            testOnly: testOnly
        ) else {
            return false
        }
        return reuseCustomInputs(
            by: other,
            indirectMap: indirectMap,
            testOnly: testOnly
        )
    }

    private mutating func makeReusableInput<T: GraphInput>(
        _ key: T.Type,
        indirectMap: IndirectAttributeMap
    ) {
        if T.isTriviallyReusable {
            return
        }
        var value = customInputs.value(forKey: key)
        T.makeReusable(
            indirectMap: indirectMap,
            value: &value
        )
        customInputs.setValue(value, forKey: key)
    }

    private mutating func reuseCustomInputs(
        by other: _GraphInputs,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        guard GraphReuseOptions.current.contains(.expandedReuse) else {
            return customInputs.isEqual(to: other.customInputs)
        }

        // Expanded reuse handles recorded GraphReusable values separately.
        // All unrecorded property-list values must still compare normally.
        let lhsStorage = customInputs.value(
            forKey: ReusableInputs.self
        )
        let rhsStorage = other.customInputs.value(
            forKey: ReusableInputs.self
        )
        guard lhsStorage.filter.value == rhsStorage.filter.value else {
            return false
        }
        let lhsTypes = reusableInputTypes(lhsStorage.stack)
        let rhsTypes = reusableInputTypes(rhsStorage.stack)
        guard lhsTypes == rhsTypes else {
            return false
        }

        var ignoredTypes = lhsTypes
        ignoredTypes.append(ObjectIdentifier(ReusableInputs.self))
        guard customInputs.isEqual(
            to: other.customInputs,
            ignoring: ignoredTypes
        ) else {
            return false
        }

        var storage = lhsStorage.stack
        while let key = storage.pop() {
            guard tryToReuseInput(
                key,
                by: other,
                indirectMap: indirectMap,
                testOnly: testOnly
            ) else {
                return false
            }
        }
        return true
    }

    private func reusableInputTypes(
        _ storage: Stack<any GraphInput.Type>
    ) -> [ObjectIdentifier] {
        var result: [ObjectIdentifier] = []
        var storage = storage
        while let key = storage.pop() {
            result.append(ObjectIdentifier(key))
        }
        return result
    }

    private mutating func tryToReuseInput<T: GraphInput>(
        _ key: T.Type,
        by other: _GraphInputs,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        if T.isTriviallyReusable {
            return true
        }
        return T.tryToReuse(
            customInputs.value(forKey: key),
            by: other.customInputs.value(forKey: key),
            indirectMap: indirectMap,
            testOnly: testOnly
        )
    }
}

extension _ViewInputs {
    var savedTransactions: [Attribute<Transaction>] {
        get { base[SavedTransactionKey.self] }
        set { base[SavedTransactionKey.self] = newValue }
    }

    func geometryTransaction() -> Attribute<Transaction> {
        savedTransactions.last ?? base.transaction
    }
}

extension _ViewListInputs {
    var savedTransactions: [Attribute<Transaction>] {
        get { base[SavedTransactionKey.self] }
        set { base[SavedTransactionKey.self] = newValue }
    }
}
