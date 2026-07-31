//
//  File: Layout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol LeafViewLayout {
    func spacing() -> Spacing
    func sizeThatFits(in proposal: _ProposedSize) -> CGSize
}

extension LeafViewLayout {
    func spacing() -> Spacing {
        Spacing()
    }

    static func makeLeafLayout(
        _ outputs: inout _ViewOutputs,
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) {
        guard inputs.requestsLayoutComputer else { return }
        guard let graph = _AGGraph.current else {
            fatalError("\(self).makeLeafLayout called outside an active _AGGraph context.")
        }

        let layoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
            LeafLayoutComputer(_view: view._attribute)
        )
        outputs._layoutComputer = OptionalAttribute(layoutComputer)
    }
}

private struct LeafLayoutComputer<Leaf: LeafViewLayout>: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer

    var _view: Attribute<Leaf>

    mutating func updateValue() {
        update(
            to: LeafLayoutEngine(
                view: _view.value,
                cache: ViewSizeCache()
            )
        )
    }
}

struct LeafLayoutEngine<Leaf: LeafViewLayout>: LayoutEngine {
    var view: Leaf
    var cache: ViewSizeCache

    func spacing() -> Spacing {
        view.spacing()
    }

    mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        cache.get(proposal) {
            view.sizeThatFits(in: proposal)
        }
    }
}

// MARK: - Layout AG rules

/// Computes one coherent placement array from the container geometry and
/// layout computer. Per-child rules index this array instead of recomputing
/// placement independently.
struct LayoutChildGeometries: Rule, AsyncAttribute {
    typealias Value = [ViewGeometry]

    var _parentSize: Attribute<ViewSize>
    var _parentPosition: Attribute<CGPoint>
    var _layoutComputer: Attribute<LayoutComputer>

    init(
        parentSize: Attribute<ViewSize>,
        parentPosition: Attribute<CGPoint>,
        layoutComputer: Attribute<LayoutComputer>
    ) {
        _parentSize = parentSize
        _parentPosition = parentPosition
        _layoutComputer = layoutComputer
    }

    var value: [ViewGeometry] {
        let layoutComputer = _layoutComputer.value
        return layoutComputer.childGeometries(
            at: _parentSize.value,
            origin: _parentPosition.value
        )
    }
}

/// Selects one child geometry from the aggregate placement result. Position
/// and size remain direct projections of this same value, preserving their
/// shared invalidation boundary.
private struct LayoutChildGeometry: Rule, AsyncAttribute {
    typealias Value = ViewGeometry

    var _childGeometries: Attribute<[ViewGeometry]>
    var index: Int

    var value: ViewGeometry {
        let childGeometries = _childGeometries.value
        precondition(
            index >= 0 && index < childGeometries.count
        )
        return childGeometries[index]
    }
}

/// Resolves a stable dynamic-container identity to the current flattened child
/// geometry. Once published, the last geometry remains stable while the item is
/// retained outside the active layout prefix.
private struct DynamicLayoutViewChildGeometry: StatefulRule, AsyncAttribute {
    typealias Value = ViewGeometry

    var _containerInfo: Attribute<DynamicContainer.Info>
    var _childGeometries: Attribute<[ViewGeometry]>
    var id: DynamicContainerID

    mutating func updateValue() {
        let info = _containerInfo.value
        let currentGeometries = _childGeometries.value
        if let index = info.viewIndex(id: id),
           currentGeometries.indices.contains(index) {
            _AGGraph.setStatefulOutput(currentGeometries[index])
        } else if _AGGraph.currentStatefulOutput(ViewGeometry.self) == nil {
            _AGGraph.setStatefulOutput(ViewGeometry.zero)
        }
    }
}

/// Temporary late-bound construction context for the combined dynamic
/// materializer. The container-info attribute is installed when its stateful
/// rule begins its first evaluation, after the layout computer and aggregate
/// geometry rule already exist.
///
/// Remove this holder and its input when the concrete dynamic-layout adaptor
/// owns both the child geometries and item materialization.
private final class DynamicLayoutViewGeometryContext {
    var containerInfo: Attribute<DynamicContainer.Info>?
    let geometries: Attribute<[ViewGeometry]>

    init(geometries: Attribute<[ViewGeometry]>) {
        self.geometries = geometries
    }
}

/// Threads the temporary geometry holder to the combined materializer.
private struct DynamicLayoutViewGeometryContextInput: ViewInput {
    static var defaultValue: DynamicLayoutViewGeometryContext? { nil }

    static func valuesEqual(
        _ lhs: DynamicLayoutViewGeometryContext?,
        _ rhs: DynamicLayoutViewGeometryContext?
    ) -> Bool {
        lhs === rhs
    }
}

/// Temporary nominal wrapper around mutation of the inline map stored by the
/// dynamic layout computer.
///
/// Item creation and destruction consume this carrier until the concrete
/// adaptor owns the native inout-map closure directly.
private final class DynamicLayoutMapMutator {
    private let body: (@escaping (inout DynamicLayoutMap) -> Void) -> Void

    init(
        _ body: @escaping (@escaping (inout DynamicLayoutMap) -> Void) -> Void
    ) {
        self.body = body
    }

    func callAsFunction(_ mutation: @escaping (inout DynamicLayoutMap) -> Void) {
        body(mutation)
    }
}

/// Threads the temporary inline-map mutation carrier to item reconciliation.
private struct DynamicLayoutMapMutatorInput: ViewInput {
    static var defaultValue: DynamicLayoutMapMutator? { nil }

    static func valuesEqual(
        _ lhs: DynamicLayoutMapMutator?,
        _ rhs: DynamicLayoutMapMutator?
    ) -> Bool {
        lhs === rhs
    }
}

private struct LayoutGeometryPlacementState: Rule {
    var geometry: Attribute<ViewGeometry>

    var value: Bool {
        _ = geometry.value
        return true
    }
}

/// Type-erased construction bridge used while a dynamic container materializes
/// a child owned by a concrete scrollable layout.
///
/// The factory itself does not calculate geometry. It preserves the generic
/// `Data.Index` and layout-state types inside the concrete rule created by the
/// scrollable layout adaptor.
final class ScrollableLayoutItemGeometryContext {
    /// Locally erases construction while preserving the concrete collection
    /// index and layout-state types inside the scroll adaptor.
    ///
    /// This alias owns no measurement or placement algorithm. Revisit it only
    /// if this context becomes generic or geometry construction moves entirely
    /// into the concrete adaptor.
    typealias GeometryFactory = (
        _ context: ScrollableLayoutItemGeometryContext,
        _ uniqueId: UInt32,
        _ parentPosition: Attribute<CGPoint>,
        _ parentSize: Attribute<ViewSize>,
        _ childLayoutComputer: OptionalAttribute<LayoutComputer>
    ) -> Attribute<ViewGeometry>

    var containerInfo: Attribute<DynamicContainer.Info>?
    private var geometryFactory: GeometryFactory

    init(makeGeometry: @escaping GeometryFactory) {
        self.geometryFactory = makeGeometry
    }

    func makeGeometry(
        uniqueId: UInt32,
        parentPosition: Attribute<CGPoint>,
        parentSize: Attribute<ViewSize>,
        childLayoutComputer: OptionalAttribute<LayoutComputer>
    ) -> Attribute<ViewGeometry> {
        geometryFactory(
            self,
            uniqueId,
            parentPosition,
            parentSize,
            childLayoutComputer
        )
    }

    func identifier(for uniqueId: UInt32) -> AnyHashable? {
        guard let containerInfo else { return nil }
        let info = containerInfo.value
        guard let item = info.item(for: uniqueId) else { return nil }
        return item.item
    }
}

/// Carries the scroll item geometry bridge through child view input rewriting.
struct ScrollableLayoutItemGeometryContextKey: ViewInput {
    static var defaultValue: ScrollableLayoutItemGeometryContext? { nil }

    static func valuesEqual(
        _ lhs: ScrollableLayoutItemGeometryContext?,
        _ rhs: ScrollableLayoutItemGeometryContext?
    ) -> Bool {
        lhs === rhs
    }
}

/// Resolves a dynamic-container identity to the concrete collection index used
/// as the key in a scrollable layout's placement state.
struct ScrollableItemIdentifier<Index: Hashable>: Rule {
    typealias Value = Index?

    var uniqueId: UInt32
    var context: ScrollableLayoutItemGeometryContext

    var value: Index? {
        context.identifier(for: uniqueId)?.base as? Index
    }
}

/// Stable key for one flattened view produced by a dynamic container item.
///
/// `uniqueId` identifies the retained item across reconciliation passes, while
/// `viewIndex` selects one output inside a non-unary item.
struct DynamicContainerID: Comparable, Hashable {
    var uniqueId: UInt32
    var viewIndex: Int32

    init(uniqueId: UInt32, viewIndex: Int32) {
        self.uniqueId = uniqueId
        self.viewIndex = viewIndex
    }

    static func < (lhs: DynamicContainerID, rhs: DynamicContainerID) -> Bool {
        if lhs.uniqueId != rhs.uniqueId {
            return lhs.uniqueId < rhs.uniqueId
        }
        return lhs.viewIndex < rhs.viewIndex
    }
}

/// Produces the layout computer for a static child list. The rule is installed
/// before child enumeration and receives the collected child attributes
/// afterward, allowing each child to consume projections of the aggregate
/// placement result without introducing an independent placement owner.
private struct StaticLayoutComputer<L: Layout>: StatefulRule, AsyncAttribute, CustomStringConvertible {
    typealias Value = LayoutComputer

    var _layout: Attribute<L>
    var _environment: Attribute<EnvironmentValues>
    var childAttributes: [LayoutProxyAttributes]

    var description: String {
        "\(L.self) → LayoutComputer"
    }

    mutating func updateValue() {
        updateLayoutComputer(
            layout: _layout.value,
            environment: _environment,
            attributes: childAttributes
        )
    }
}

/// Dynamic container storage used by DynamicContainerInfo.
enum DynamicContainer {
    /// Counts the removal baseline and registered animations for one retained item.
    ///
    /// Registration, baseline release, and completion are serialized by the
    /// owning graph/update lane. Keep the counter and completion flags as plain
    /// state so the zero-count transition stays ordered with graph invalidation.
    final class TransitionRemovalListener: AnimationListener, @unchecked Sendable {
        private weak var host: GraphHost?
        private let invalidationTarget: AGWeakAttribute?
        private let seed: Attribute<UInt32>?
        private let inbox: AGInbox?
        private var seedValue: UInt32 = 0
        private var animationCount = 0
        private var completionInstalled = false
        private var completed = false
        private var completionPublished = false

        init(host: GraphHost, invalidationTarget: AGWeakAttribute) {
            self.host = host
            self.invalidationTarget = invalidationTarget
            self.seed = nil
            self.inbox = nil
        }

        /// Test-only adapter for exercising no-registration completion
        /// scheduling without a graph host. Production dynamic-container
        /// removal uses the weak-host/weak-target initializer above.
        init(seed: Attribute<UInt32>, inbox: AGInbox) {
            self.host = nil
            self.invalidationTarget = nil
            self.seed = seed
            self.inbox = inbox
        }

        var isComplete: Bool {
            completed
        }

        var isCompletionPublished: Bool {
            completionPublished
        }

        func readSeed() {
            _ = seed?.value
        }

        func detachFromHost() {
            host = nil
        }

        override func animationWasAdded() {
            animationCount += 1
        }

        override func animationWasRemoved() -> [() -> Void] {
            guard animationCount > 0 else {
                return []
            }
            animationCount -= 1
            guard animationCount == 0, !completed else {
                return []
            }
            return [{ [weak self] in
                self?.complete()
            }]
        }

        func beginTrackingAnimations() {
            animationWasAdded()
            Update.enqueueAction { [weak self] in
                self?.animationWasRemoved().forEach { $0() }
            }
        }

        func installCompletion(into transaction: inout Transaction) -> AnimationCompletionObserver? {
            guard !completionInstalled else {
                return transaction.animationCompletionObserver
            }
            completionInstalled = true

            transaction.addAnimationCompletion(
                criteria: .removed,
                tracksStandalonePending: false
            ) { [weak self] in
                self?.complete()
            }
            return transaction.animationCompletionObserver
        }

        private func complete() {
            guard !completed else {
                return
            }
            completed = true

            if let host, let invalidationTarget {
                host.continueTransaction(invalidating: invalidationTarget)
                return
            }

            guard let seed, let inbox else {
                return
            }
            seedValue &+= 1
            let nextSeed = seedValue
            inbox.enqueue { [weak self] in
                self?.completionPublished = true
                seed.setValue(nextSeed)
            }
        }
    }

    /// The core record stores subgraph, numeric identity, view count, outputs,
    /// transition state, depth, removal order, flattened offset, reset seed,
    /// and an optional transition phase. A nil phase denotes an unused item.
    ///
    /// Additional storage below `phase` is local compatibility state for the
    /// combined materializer and retained-removal implementation.
    /// The numeric identity is assigned by the container. `sourceID` is a
    /// temporary reconciliation carrier until source identity moves into the
    /// generic dynamic-container adaptor.
    final class ItemInfo {
        var subgraph: AGSubgraph
        var uniqueId: UInt32
        var viewCount: Int32
        var outputs: _ViewOutputs
        var needsTransitions: Bool
        var listener: TransitionRemovalListener?
        var zIndex: Double
        var removalOrder: UInt32
        var precedingViewCount: Int32
        var resetSeed: UInt32
        var phase: TransitionPhase?
        var sourceID: _ViewList_ID.Canonical
        // Type-erased dynamic adaptor item payload. The scrollable layout bridge
        // uses this to recover the original collection index from DynamicContainer.Info.
        var item: AnyHashable?
        // Cache for non-unary DynamicContainer items. This keeps each materialized
        // child addressable until multi-output storage is modeled.
        var layoutAttributes: [LayoutProxyAttributes]
        var preferenceOutputs: [PreferencesOutputs]
        var viewPhase: Attribute<TransitionPhase>?
        var placementTransaction: Attribute<Transaction>?
        var transitionPhaseSetters: [_TransitionPhaseSetter]
        var transitionTransactions: _TransitionTransactionResolver?
        var removalLifecycleStarted: Bool
        var ignoredRetainedUnusedRemovalObserver: ObjectIdentifier?
        var retainAfterRemovalCompletion: Bool

        init(
            subgraph: AGSubgraph,
            uniqueId: UInt32,
            viewCount: Int32,
            outputs: _ViewOutputs,
            sourceID: _ViewList_ID.Canonical,
            layoutAttributes: [LayoutProxyAttributes],
            preferenceOutputs: [PreferencesOutputs],
            viewPhase: Attribute<TransitionPhase>? = nil,
            placementTransaction: Attribute<Transaction>? = nil,
            transitionPhaseSetters: [_TransitionPhaseSetter] = [],
            needsTransitions: Bool = false,
            listener: TransitionRemovalListener? = nil,
            zIndex: Double = 0,
            removalOrder: UInt32 = 0,
            precedingViewCount: Int32 = 0,
            resetSeed: UInt32 = 0,
            phase: TransitionPhase? = .identity,
            item: AnyHashable? = nil,
            transitionTransactions: _TransitionTransactionResolver? = nil,
            removalLifecycleStarted: Bool = false,
            ignoredRetainedUnusedRemovalObserver: ObjectIdentifier? = nil,
            retainAfterRemovalCompletion: Bool = false
        ) {
            self.subgraph = subgraph
            self.uniqueId = uniqueId
            self.viewCount = viewCount
            self.outputs = outputs
            self.needsTransitions = needsTransitions
            self.listener = listener
            self.zIndex = zIndex
            self.removalOrder = removalOrder
            self.precedingViewCount = precedingViewCount
            self.resetSeed = resetSeed
            self.phase = phase
            self.sourceID = sourceID
            self.item = item
            self.layoutAttributes = layoutAttributes
            self.preferenceOutputs = preferenceOutputs
            self.viewPhase = viewPhase
            self.placementTransaction = placementTransaction
            self.transitionPhaseSetters = transitionPhaseSetters
            self.transitionTransactions = transitionTransactions
            self.removalLifecycleStarted = removalLifecycleStarted
            self.ignoredRetainedUnusedRemovalObserver = ignoredRetainedUnusedRemovalObserver
            self.retainAfterRemovalCompletion = retainAfterRemovalCompletion
        }

        func setTransitionPhase(
            _ phase: TransitionPhase,
            transaction: Transaction = Transaction()
        ) {
            viewPhase?.setValue(phase, transaction: transaction)
            for setter in transitionPhaseSetters {
                setter(phase, transaction)
            }
        }

        func invalidate() {
            guard let graph = _AGGraph.current else {
                fatalError("DynamicContainer.ItemInfo.invalidate() called outside an active _AGGraph context.")
            }
            Update.begin()
            defer { Update.end() }
            subgraph.willRemove()
            subgraph.invalidate()
            graph.drainActionOutbox()
            subgraph.removeFromParent()
        }
    }

    /// Stores items, the numeric-id index, display ordering, active-suffix
    /// counts, the unary fast-path flag, and the change seed. Equality compares
    /// only the seed.
    struct Info: Equatable {
        var items: [ItemInfo] = []
        var indexMap: [UInt32: Int] = [:]
        var displayMap: [UInt32]?
        var removedCount: Int = 0
        var unusedCount: Int = 0
        var allUnary: Bool = true
        var seed: UInt32 = 0

        static func == (lhs: Info, rhs: Info) -> Bool {
            lhs.seed == rhs.seed
        }

        func viewIndex(id: DynamicContainerID) -> Int? {
            guard let itemIndex = indexMap[id.uniqueId],
                  items.indices.contains(itemIndex) else {
                return nil
            }
            // The identifier producer owns the per-item range invariant. This
            // lookup only composes the item's flattened base with that offset.
            return Int(items[itemIndex].precedingViewCount + id.viewIndex)
        }

        func item(for id: _ViewList_ID.Canonical) -> ItemInfo? {
            items.first { $0.sourceID == id }
        }

        func item(for uniqueId: UInt32) -> ItemInfo? {
            guard let index = indexMap[uniqueId],
                  items.indices.contains(index) else {
                return nil
            }
            return items[index]
        }

        func item(for subgraph: AGSubgraph) -> ItemInfo? {
            items.first { $0.subgraph === subgraph }
        }

        var activeItems: ArraySlice<ItemInfo> {
            let activeEnd = max(0, items.count - unusedCount - removedCount)
            return items.prefix(activeEnd)
        }

        var activeAndRemovedItems: ArraySlice<ItemInfo> {
            let retainedEnd = max(0, items.count - unusedCount)
            return items.prefix(retainedEnd)
        }

        var displayItems: [ItemInfo] {
            let retainedCount = max(0, items.count - unusedCount)
            guard retainedCount > 0 else { return [] }
            if let displayMap {
                // The map begins with the active-only layout segment and ends
                // with the retained-inclusive display segment.
                return displayMap.suffix(retainedCount).compactMap { index in
                    let index = Int(index)
                    return items.indices.contains(index) ? items[index] : nil
                }
            }
            let activeCount = max(0, retainedCount - removedCount)
            // Removed items render below their active replacements. This lets
            // insertion and removal opacity compose independently instead of
            // the outgoing opaque surface masking the incoming one.
            return Array(items[activeCount..<retainedCount]) +
                Array(items[..<activeCount])
        }

        mutating func replaceItems(
            active activeItems: [ItemInfo],
            removed removedItems: [ItemInfo] = [],
            unused unusedItems: [ItemInfo] = []
        ) {
            let oldIdentity = items.map { ItemIdentity(item: $0) }
            let oldDisplayMap = displayMap
            let oldAllUnary = allUnary
            let oldRemovedCount = removedCount
            let oldUnusedCount = unusedCount
            let newItems = activeItems + removedItems + unusedItems
            var precedingViewCount: Int32 = 0
            for item in newItems {
                item.precedingViewCount = precedingViewCount
                let (next, overflow) = precedingViewCount.addingReportingOverflow(
                    item.viewCount
                )
                precondition(!overflow, "Dynamic container view count overflow.")
                precedingViewCount = next
            }
            let newIdentity = newItems.map { ItemIdentity(item: $0) }
            items = newItems
            removedCount = removedItems.count
            unusedCount = unusedItems.count
            allUnary = !activeItems.contains { $0.viewCount != 1 }
            rebuildIndexMap()
            rebuildDisplayMap()
            if oldIdentity != newIdentity ||
                oldDisplayMap != displayMap ||
                oldAllUnary != allUnary ||
                oldRemovedCount != removedCount ||
                oldUnusedCount != unusedCount {
                seed &+= 1
            }
        }

        private mutating func rebuildIndexMap() {
            indexMap.removeAll(keepingCapacity: true)
            for (index, item) in items.enumerated() {
                indexMap[item.uniqueId] = index
            }
        }

        private mutating func rebuildDisplayMap() {
            // zIndex/depth can produce displayMap. LayoutProxyAttributes does not
            // currently provide a zIndex source, so this only covers stored values.
            let activeEnd = max(0, items.count - unusedCount - removedCount)
            let activeRange = 0..<activeEnd
            let retainedEnd = activeEnd + removedCount
            let retainedRange = 0..<retainedEnd
            guard items[retainedRange].contains(where: { $0.zIndex != 0 }) else {
                displayMap = nil
                return
            }
            let activeMap = sortedDisplayIndexes(in: activeRange)
            guard removedCount != 0 else {
                displayMap = activeMap
                return
            }
            displayMap = activeMap + sortedDisplayIndexes(in: retainedRange)
        }

        private func sortedDisplayIndexes(in range: Range<Int>) -> [UInt32] {
            range.sorted { lhsIndex, rhsIndex in
                let lhs = items[lhsIndex]
                let rhs = items[rhsIndex]
                if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
                // At equal depth, phase-2 removals sort before active phase-1 items
                // in the retained-inclusive segment.
                if lhs.phase != rhs.phase {
                    if lhs.phase == .didDisappear { return true }
                    if rhs.phase == .didDisappear { return false }
                }
                return lhsIndex < rhsIndex
            }.map { UInt32($0) }
        }

        private struct ItemIdentity: Equatable {
            var uniqueId: UInt32
            var viewCount: Int32
            var phase: TransitionPhase?
            var removalLifecycleStarted: Bool

            init(item: ItemInfo) {
                self.uniqueId = item.uniqueId
                self.viewCount = item.viewCount
                self.phase = item.phase
                self.removalLifecycleStarted = item.removalLifecycleStarted
            }
        }
    }
}

private struct DynamicViewPhase: Rule, AsyncAttribute {
    var containerInfo: Attribute<DynamicContainer.Info>
    var phase: Attribute<_GraphInputs.Phase>
    var uniqueId: UInt32

    var value: _GraphInputs.Phase {
        var value = phase.value
        guard let item = containerInfo.value.item(for: uniqueId) else {
            return value
        }
        value.rawValue &+= item.resetSeed &<< 1
        if item.phase == .didDisappear {
            value.isBeingRemoved = true
        }
        return value
    }
}

private struct DynamicTransaction: StatefulRule, AsyncAttribute {
    typealias Value = Transaction

    var containerInfo: Attribute<DynamicContainer.Info>
    var transaction: Attribute<Transaction>
    var uniqueId: UInt32
    var wasRemoved = false

    mutating func updateValue() {
        guard let item = containerInfo.value.item(for: uniqueId),
              let itemPhase = item.phase else {
            _AGGraph.setStatefulOutput(Transaction())
            return
        }

        var value = transaction.value
        let previouslyRemoved = wasRemoved
        wasRemoved = false

        switch itemPhase {
        case .willAppear:
            value.animation = nil
            value.disablesAnimations = true
        case .identity:
            break
        case .didDisappear:
            if !previouslyRemoved, let listener = item.listener {
                value.addAnimationListener(listener)
            }
            wasRemoved = true
        }
        _AGGraph.setStatefulOutput(value)
    }
}

/// Controls retained-removal lifecycle ordering for layout-owned dynamic items.
/// Lazy layout hosts send removal lifecycle callbacks before final invalidation
/// so retained animation listeners can drain after disappearance.
struct DynamicContainerWillRemoveBeforeInvalidation: GraphInput {
    static var defaultValue: Bool { false }
}

struct DynamicContainerTransitionPhaseInput: ViewInput {
    static var defaultValue: OptionalAttribute<TransitionPhase> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ lhs: OptionalAttribute<TransitionPhase>,
        _ rhs: OptionalAttribute<TransitionPhase>
    ) -> Bool {
        lhs.base.identifier == rhs.base.identifier
    }
}

struct LayoutPlacementStateInput: ViewInput {
    static var defaultValue: OptionalAttribute<Bool> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ lhs: OptionalAttribute<Bool>,
        _ rhs: OptionalAttribute<Bool>
    ) -> Bool {
        lhs.base.identifier == rhs.base.identifier
    }
}

struct LayoutPlacementTransactionInput: ViewInput {
    static var defaultValue: OptionalAttribute<Transaction> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ lhs: OptionalAttribute<Transaction>,
        _ rhs: OptionalAttribute<Transaction>
    ) -> Bool {
        lhs.base.identifier == rhs.base.identifier
    }
}

/// Keeps a phase-3 retained-unused item cached after its later animated removal
/// listener completes. Cache-owned lazy hosts use this to preserve source state
/// across same-identity removal/reinsertion windows.
struct DynamicContainerRetainCompletedUnusedRemovals: ViewInput {
    static var defaultValue: Bool { false }
}

/// Stores one flat, identity-sorted layout-attribute entry per dynamic child
/// and rebuilds its active container-order cache when the info seed changes.
struct DynamicLayoutMap {
    var map: [(id: DynamicContainerID, value: LayoutProxyAttributes)] = []
    var sortedArray: [LayoutProxyAttributes] = []
    var sortedSeed: UInt32 = 0

    subscript(id: DynamicContainerID) -> LayoutProxyAttributes {
        get {
            let index = lowerBound(for: id)
            guard index < map.endIndex, map[index].id == id else {
                return LayoutProxyAttributes()
            }
            return map[index].value
        }
        set {
            let index = lowerBound(for: id)
            let found = index < map.endIndex && map[index].id == id
            if newValue == LayoutProxyAttributes() {
                if found {
                    map.remove(at: index)
                }
            } else if found {
                map[index].value = newValue
            } else {
                map.insert((id: id, value: newValue), at: index)
            }
            sortedSeed = 0
        }
    }

    mutating func remove(uniqueId: UInt32) {
        let start = lowerBound(
            for: DynamicContainerID(uniqueId: uniqueId, viewIndex: 0)
        )
        var end = start
        while end < map.endIndex, map[end].id.uniqueId == uniqueId {
            end += 1
        }
        if start < end {
            map.removeSubrange(start..<end)
            sortedSeed = 0
        }
    }

    mutating func attributes(info: DynamicContainer.Info) -> [LayoutProxyAttributes] {
        if sortedSeed == info.seed {
            return sortedArray
        }

        // displayMap belongs to retained rendering order. Layout flattens only
        // the active item prefix in container order.
        sortedArray.removeAll(keepingCapacity: true)
        for item in info.activeItems {
            let count = Int(item.viewCount)
            for viewIndex in 0..<count {
                guard let viewIndex = Int32(exactly: viewIndex) else {
                    preconditionFailure(
                        "Dynamic layout child index must fit Int32."
                    )
                }
                sortedArray.append(
                    self[
                        DynamicContainerID(
                            uniqueId: item.uniqueId,
                            viewIndex: viewIndex
                        )
                    ]
                )
            }
        }
        sortedSeed = info.seed
        return sortedArray
    }

    private func lowerBound(for id: DynamicContainerID) -> Int {
        var lower = map.startIndex
        var upper = map.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if map[middle].id < id {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}

/// Reconciles dynamic items and publishes `DynamicContainer.Info`.
///
/// This declaration currently combines generic container reconciliation with
/// dynamic-layout adaptor materialization. Keep that ownership boundary
/// explicit until the generic adaptor split replaces the temporary context and
/// map-mutation inputs above.
struct DynamicContainerInfo: StatefulRule, AsyncAttribute {
    typealias Value = DynamicContainer.Info
    var viewListAttr: Attribute<any ViewList>
    var inputs: _ViewInputs
    var parentSubgraph: AGSubgraph? = AGSubgraph.current
    var info = DynamicContainer.Info()
    var retainedElements: [_ViewList_ID.Canonical: _ViewList_SubgraphRelease] = [:]
    var hasValue = false
    var lastUniqueId: UInt32 = 0
    var lastResetSeed: UInt32 = 0
    var needsPhaseUpdate = false

    mutating func updateValue() {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicContainerInfo.updateValue called outside AG context.")
        }
        guard let currentAttribute = _AGGraph.currentRuleContextAttribute else {
            fatalError("DynamicContainerInfo.updateValue requires a current rule attribute.")
        }
        let containerInfoAttr = Attribute<DynamicContainer.Info>(currentAttribute)
        if let geometryContext = inputs[DynamicLayoutViewGeometryContextInput.self],
           geometryContext.containerInfo == nil {
            geometryContext.containerInfo = containerInfoAttr
        }

        let resetSeed = inputs.base.phase.value.resetSeed
        let disableTransitions: Bool
        if resetSeed != lastResetSeed {
            lastResetSeed = resetSeed
            disableTransitions = true
        } else {
            disableTransitions = inputs.base.options.contains(.animationsDisabled)
        }

        var promotedItems = Set<ObjectIdentifier>()
        if needsPhaseUpdate {
            for item in info.items where item.phase == .willAppear {
                item.phase = .identity
                promotedItems.insert(ObjectIdentifier(item))
            }
            needsPhaseUpdate = false
        }

        let capturedInputs = inputs
        let currentList = viewListAttr.value
        let listTransaction =
            graph.transaction(for: viewListAttr.identifier) ?? Transaction()
        var from = 0
        var liveIDs = Set<_ViewList_ID.Canonical>()
        var orderedItems: [DynamicContainer.ItemInfo] = []
        var precedingViewCount: Int32 = 0

        _ = _applySublists(in: currentList, from: &from, listAttribute: viewListAttr) { sublist in
            for offset in 0..<sublist.count {
                let elementIndex = sublist.start + offset
                let id = sublist.id.elementID(at: elementIndex).canonicalID
                liveIDs.insert(id)

                // A multi-element sublist exposes one dynamic adaptor item per
                // element. A transformed single-item sublist can still replace
                // its elements with a genuinely non-unary payload.
                let rawViewCount = sublist.count == 1
                    ? sublist.elements.count
                    : 1
                guard let viewCount = Int32(exactly: rawViewCount) else {
                    preconditionFailure(
                        "Dynamic container view count must fit Int32."
                    )
                }
                let needsTransitions = sublist.traits[CanTransitionTraitKey.self]
                // allUnary becomes false when any active item reports viewCount != 1.
                // The same viewCount is used for cumulative child offsets.
                if let existing = info.item(for: id),
                   existing.viewCount != viewCount ||
                    existing.needsTransitions != needsTransitions {
                    eraseItem(existing)
                }

                let reusableItem = info.item(for: id).flatMap { existing in
                    existing.viewCount == viewCount && existing.needsTransitions == needsTransitions ? existing : nil
                }
                let transition = needsTransitions ? sublist.traits[TransitionTraitKey.self] : nil
                let insertionTransaction = reusableItem == nil && hasValue && !disableTransitions
                    ? transition?.positiveInsertionTransaction(from: listTransaction)
                    : nil
                if insertionTransaction != nil {
                    guard let weakAttribute = graph.weakAttributeIfValid(for: currentAttribute) else {
                        fatalError("DynamicContainerInfo insertion requires a live rule attribute.")
                    }
                    GraphHost.currentHost.continueTransaction(invalidating: weakAttribute)
                    needsPhaseUpdate = true
                }
                let item: DynamicContainer.ItemInfo?
                if let reusableItem {
                    item = reusableItem
                } else {
                    let uniqueId = nextUniqueId()
                    item = makeItem(
                        uniqueId: uniqueId,
                        sourceID: id,
                        viewCount: viewCount,
                        sublist: sublist,
                        offset: offset,
                        transition: transition,
                        initialTransitionPhase: insertionTransaction == nil ? .identity : .willAppear,
                        placementTransaction: listTransaction,
                        capturedInputs: capturedInputs,
                        containerInfo: containerInfoAttr,
                        graph: graph
                    )
                }
                if let item {
                    item.placementTransaction?.setValue(listTransaction)
                    // Item object depth is driven by view-level zIndex. displayMap
                    // stores UInt32 item indexes sorted by that depth.
                    item.zIndex = sublist.traits[ZIndexTraitKey.self]
                    item.needsTransitions = needsTransitions
                    if item.phase == nil {
                        item.subgraph.didReinsert()
                    }
                    if insertionTransaction != nil {
                        item.phase = .willAppear
                    } else if item.phase != .identity {
                        item.listener?.detachFromHost()
                        item.listener = nil
                        item.removalLifecycleStarted = false
                        item.retainAfterRemovalCompletion = false
                        item.phase = .identity
                        item.setTransitionPhase(.identity, transaction: listTransaction)
                    } else if promotedItems.contains(ObjectIdentifier(item)) {
                        item.setTransitionPhase(.identity, transaction: listTransaction)
                    }
                    item.precedingViewCount = precedingViewCount
                    let (next, overflow) =
                        precedingViewCount.addingReportingOverflow(
                            item.viewCount
                        )
                    precondition(
                        !overflow,
                        "Dynamic container view count overflow."
                    )
                    precedingViewCount = next
                    orderedItems.append(item)
                }
            }
            return true
        }

        let retention = retainedInactiveItems(
            excluding: liveIDs,
            transaction: listTransaction,
            disableTransitions: disableTransitions,
            graph: graph
        )
        info.replaceItems(
            active: orderedItems,
            removed: retention.removed,
            unused: retention.unused
        )
        hasValue = true
        _AGGraph.setStatefulOutput(info)
    }

    private mutating func retainedInactiveItems(
        excluding liveIDs: Set<_ViewList_ID.Canonical>,
        transaction: Transaction,
        disableTransitions: Bool,
        graph: _AGGraph
    ) -> (removed: [DynamicContainer.ItemInfo], unused: [DynamicContainer.ItemInfo]) {
        var removedItems: [DynamicContainer.ItemInfo] = []
        var unusedItems: [DynamicContainer.ItemInfo] = []
        let maxUnusedItems = max(inputs[DynamicContainerMaxUnusedItems.self], 0)
        let retainCompletedUnusedRemovals = inputs[DynamicContainerRetainCompletedUnusedRemovals.self]
        func makeTransitionRemovalListener() -> DynamicContainer.TransitionRemovalListener {
            guard let currentAttribute = _AGGraph.currentRuleContextAttribute,
                  let invalidationTarget = graph.weakAttributeIfValid(for: currentAttribute) else {
                fatalError("DynamicContainerInfo retained removal requires a live rule attribute.")
            }
            return DynamicContainer.TransitionRemovalListener(
                host: GraphHost.currentHost,
                invalidationTarget: invalidationTarget
            )
        }
        func positiveRemovalTransition(
            for item: DynamicContainer.ItemInfo
        ) -> Transaction? {
            guard !disableTransitions else {
                return nil
            }
            let transitionTransaction = item.transitionTransactions?(.didDisappear, transaction)
                .first { candidate in
                    guard let animation = candidate.effectiveAnimation else { return false }
                    return animation.box.duration > 0
                }
            guard item.needsTransitions,
                  let transitionTransaction,
                  let animation = transitionTransaction.effectiveAnimation,
                  animation.box.duration > 0 else {
                return nil
            }
            return transitionTransaction
        }
        func nextRemovalOrder() -> UInt32 {
            guard let order = UInt32(exactly: removedItems.count) else {
                preconditionFailure(
                    "Dynamic container removal order must fit UInt32."
                )
            }
            return order
        }

        for item in info.items where !liveIDs.contains(item.sourceID) {
            if item.phase == .didDisappear {
                guard let listener = item.listener else {
                    eraseItem(item)
                    continue
                }
                if listener.isComplete {
                    if item.retainAfterRemovalCompletion {
                        item.listener = nil
                        item.retainAfterRemovalCompletion = false
                        item.phase = nil
                        item.removalOrder = 0
                        guard unusedItems.count < maxUnusedItems else {
                            eraseItem(item)
                            continue
                        }
                        unusedItems.append(item)
                        continue
                    }
                    if inputs.base[DynamicContainerWillRemoveBeforeInvalidation.self],
                       !item.removalLifecycleStarted {
                        item.removalLifecycleStarted = true
                        item.subgraph.willRemove()
                        if let currentAttribute = _AGGraph.currentRuleContextAttribute {
                            graph.inbox.enqueue {
                                graph.invalidateAttribute(currentAttribute)
                            }
                        }
                        item.removalOrder = nextRemovalOrder()
                        removedItems.append(item)
                        continue
                    }
                    eraseItem(item)
                    continue
                }
                item.removalOrder = nextRemovalOrder()
                removedItems.append(item)
                continue
            }
            if item.phase == nil {
                let transition = positiveRemovalTransition(for: item)
                let observerID = transition?.animationCompletionObserver.map(ObjectIdentifier.init)
                let didIgnoreObserver = observerID != nil &&
                    item.ignoredRetainedUnusedRemovalObserver == observerID
                if removedItems.isEmpty,
                   !didIgnoreObserver,
                   let transition {
                    let listener = makeTransitionRemovalListener()
                    item.listener = listener
                    item.ignoredRetainedUnusedRemovalObserver = nil
                    item.retainAfterRemovalCompletion = retainCompletedUnusedRemovals
                    listener.beginTrackingAnimations()

                    let removalTransaction = transition
                    item.phase = .didDisappear
                    item.removalLifecycleStarted = true
                    item.setTransitionPhase(.didDisappear, transaction: removalTransaction)
                    finalizeAnimationCompletions(
                        in: removalTransaction,
                        animation: removalTransaction.effectiveAnimation
                    )

                    item.removalOrder = nextRemovalOrder()
                    removedItems.append(item)
                    continue
                }
                if !removedItems.isEmpty, let observerID {
                    item.ignoredRetainedUnusedRemovalObserver = observerID
                }
                guard unusedItems.count < maxUnusedItems else {
                    eraseItem(item)
                    continue
                }
                unusedItems.append(item)
                continue
            }

            guard let transition = positiveRemovalTransition(for: item) else {
                guard unusedItems.count < maxUnusedItems else {
                    eraseItem(item)
                    continue
                }
                item.listener = nil
                item.subgraph.willRemove()
                item.phase = nil
                item.removalOrder = 0
                unusedItems.append(item)
                continue
            }

            let listener = makeTransitionRemovalListener()
            item.listener = listener
            listener.beginTrackingAnimations()

            let removalTransaction = transition
            item.phase = .didDisappear
            item.setTransitionPhase(.didDisappear, transaction: removalTransaction)
            finalizeAnimationCompletions(
                in: removalTransaction,
                animation: removalTransaction.effectiveAnimation
            )

            item.removalOrder = nextRemovalOrder()
            removedItems.append(item)
        }
        return (removedItems, unusedItems)
    }

    private mutating func eraseItem(_ item: DynamicContainer.ItemInfo) {
        inputs[DynamicLayoutMapMutatorInput.self]? {
            $0.remove(uniqueId: item.uniqueId)
        }
        item.invalidate()
        retainedElements.removeValue(forKey: item.sourceID)
    }

    private mutating func makeItem(
        uniqueId: UInt32,
        sourceID: _ViewList_ID.Canonical,
        viewCount: Int32,
        sublist: _ViewList_Sublist,
        offset: Int,
        transition: AnyTransition?,
        initialTransitionPhase: TransitionPhase,
        placementTransaction: Transaction,
        capturedInputs: _ViewInputs,
        containerInfo: Attribute<DynamicContainer.Info>,
        graph: _AGGraph
    ) -> DynamicContainer.ItemInfo? {
        // Rule evaluation does not inherit the materialization scope. Re-enter
        // the parent captured when the container rule was installed.
        let subgraph = AGSubgraph.withCurrent(parentSubgraph) {
            AGSubgraph()
        }
        let release = sublist.elements.retain()
        var baseInputs = capturedInputs
        baseInputs.copyCaches()

        let item: DynamicContainer.ItemInfo? = AGSubgraph.withCurrent(subgraph) {
            let viewPhase = graph.makeInput(value: initialTransitionPhase)
            let placementTransactionAttribute = graph.makeInput(value: placementTransaction)
            let parentTransform = capturedInputs.transform

            var firstOutputs: _ViewOutputs?
            var layoutAttributes: [LayoutProxyAttributes] = []
            var preferenceOutputs: [PreferencesOutputs] = []
            var transitionPhaseSetters: [_TransitionPhaseSetter] = []
            let traitsListAttr = sublist.list.map { OptionalAttribute($0) } ??
                OptionalAttribute<any ViewList>()
            let scrollContext = baseInputs[ScrollableLayoutItemGeometryContextKey.self]
            let layoutGeometryContext = baseInputs[DynamicLayoutViewGeometryContextInput.self]
            let dynamicItem = scrollContext != nil ? sourceID.explicitID : nil

            // Non-unary items are a single DynamicContainer item whose viewCount spans
            // multiple child outputs, not multiple item records.
            let count = Int(viewCount)
            for elementOffset in offset..<(offset + count) {
                guard let viewIndex = Int32(exactly: elementOffset - offset) else {
                    preconditionFailure(
                        "Dynamic layout child index must fit Int32."
                    )
                }
                let fallbackPosAttr = capturedInputs.position
                let fallbackSizeAttr = capturedInputs.size
                let scrollLayoutComputer = scrollContext.map { _ in
                    graph.makeIndirectAttribute(defaultValue: LayoutComputer.defaultValue)
                }
                let childOutputs = sublist.elements.makeOneElement(at: elementOffset, inputs: baseInputs) {
                    elementInputs,
                    makeView in
                    var childInputs = elementInputs
                    childInputs.copyCaches()
                    childInputs.base.transaction = graph.makeStatefulRule(
                        DynamicTransaction(
                            containerInfo: containerInfo,
                            transaction: childInputs.base.transaction,
                            uniqueId: uniqueId
                        )
                    )
                    childInputs.base.phase = graph.makeRule(
                        DynamicViewPhase(
                            containerInfo: containerInfo,
                            phase: childInputs.base.phase,
                            uniqueId: uniqueId
                        )
                    )
                    childInputs[DynamicContainerTransitionPhaseInput.self] =
                        OptionalAttribute(viewPhase)
                    childInputs[LayoutPlacementTransactionInput.self] =
                        OptionalAttribute(placementTransactionAttribute)
                    let geometryAttr: Attribute<ViewGeometry>?
                    if let layoutGeometryContext,
                       let containerInfo = layoutGeometryContext.containerInfo {
                        geometryAttr = graph.makeStatefulRule(
                            DynamicLayoutViewChildGeometry(
                                _containerInfo: containerInfo,
                                _childGeometries: layoutGeometryContext.geometries,
                                id: DynamicContainerID(
                                    uniqueId: uniqueId,
                                    viewIndex: viewIndex
                                )
                            )
                        )
                    } else {
                        geometryAttr = nil
                    }
                    // Both projections share the stateful geometry rule and use
                    // its fixed origin and size field offsets.
                    let posAttr = geometryAttr.map { $0.origin() } ??
                        fallbackPosAttr
                    let sizeAttr = geometryAttr.map { $0.size() } ??
                        fallbackSizeAttr
                    if let geometryAttr {
                        childInputs[LayoutPlacementStateInput.self] = OptionalAttribute(
                            graph.makeRule(LayoutGeometryPlacementState(geometry: geometryAttr))
                        )
                    }
                    var childPosition = posAttr
                    var childSize = sizeAttr
                    if let scrollContext, let scrollLayoutComputer {
                        let geometryAttr = scrollContext.makeGeometry(
                            uniqueId: uniqueId,
                            parentPosition: fallbackPosAttr,
                            parentSize: fallbackSizeAttr,
                            childLayoutComputer: OptionalAttribute(scrollLayoutComputer)
                        )
                        if childInputs.needsGeometry {
                            // Both fields project from one placement rule so a
                            // child cannot observe position from one scroll
                            // state and size from another.
                            childSize = geometryAttr.size()
                            childPosition = geometryAttr.origin()
                            childInputs.requestsLayoutComputer = true
                        }
                    }
                    childInputs.position = childPosition
                    childInputs.size = childSize
                    childInputs.transform = graph.makeRule {
                        var transform = parentTransform.value
                        transform.appendPosition(childPosition.value)
                        return transform
                    }
                    childInputs.containerPosition = capturedInputs.position
                    // Layout placement does not redefine the nearest container
                    // size; viewport-sensitive descendants keep the inherited channel.
                    childInputs.safeAreaInsets = capturedInputs.safeAreaInsets
                    childInputs.stackOrientation = capturedInputs.stackOrientation
                    if let transition {
                        return transition._makeView(
                            phase: initialTransitionPhase,
                            inputs: childInputs,
                            phaseSetters: &transitionPhaseSetters
                        ) { _, transitionInputs in
                            makeView(transitionInputs)
                        }
                    }
                    return makeView(childInputs)
                }

                guard let childOutputs else { return nil }
                if firstOutputs == nil { firstOutputs = childOutputs }
                preferenceOutputs.append(childOutputs.preferences)

                guard let lcAttr = childOutputs._layoutComputer.attribute else {
                    if let scrollLayoutComputer {
                        graph.setIndirectTarget(scrollLayoutComputer, to: nil)
                    }
                    layoutAttributes.append(LayoutProxyAttributes())
                    continue
                }
                if let scrollLayoutComputer {
                    graph.setIndirectTarget(scrollLayoutComputer, to: lcAttr)
                }

                layoutAttributes.append(LayoutProxyAttributes(
                    layoutComputer: lcAttr,
                    traitsList: traitsListAttr
                ))
            }

            guard var outputs = firstOutputs else { return nil }
            if let firstLayoutComputer = layoutAttributes.first?.layoutComputer.attribute {
                outputs._layoutComputer = OptionalAttribute(firstLayoutComputer)
            }
            capturedInputs[DynamicLayoutMapMutatorInput.self]? { map in
                for (viewIndex, attributes) in layoutAttributes.enumerated() {
                    guard let viewIndex = Int32(exactly: viewIndex) else {
                        preconditionFailure(
                            "Dynamic layout child index must fit Int32."
                        )
                    }
                    map[
                        DynamicContainerID(
                            uniqueId: uniqueId,
                            viewIndex: viewIndex
                        )
                    ] = attributes
                }
            }
            return DynamicContainer.ItemInfo(
                subgraph: subgraph,
                uniqueId: uniqueId,
                viewCount: viewCount,
                outputs: outputs,
                sourceID: sourceID,
                layoutAttributes: layoutAttributes,
                preferenceOutputs: preferenceOutputs,
                viewPhase: viewPhase,
                placementTransaction: placementTransactionAttribute,
                transitionPhaseSetters: transitionPhaseSetters,
                needsTransitions: transition != nil,
                phase: initialTransitionPhase,
                item: dynamicItem,
                transitionTransactions: transition.map { transition in
                    { phase, transaction in
                        transition._retainedRemovalTransactions(from: transaction, phase: phase)
                    }
                }
            )
        }

        if item == nil {
            subgraph.invalidate()
            subgraph.removeFromParent()
        } else {
            retainedElements[sourceID] = release
        }
        return item
    }

    private mutating func nextUniqueId() -> UInt32 {
        // IDs belong to this container state and advance once for each newly
        // materialized adaptor item. Reused items keep their existing ID.
        lastUniqueId &+= 1
        return lastUniqueId
    }
}

private extension AnyTransition {
    func positiveInsertionTransaction(from transaction: Transaction) -> Transaction? {
        _filteredTransactions(from: transaction, phase: .willAppear).first { candidate in
            guard !candidate.disablesAnimations,
                  let animation = candidate.effectiveAnimation else {
                return false
            }
            return animation.box.duration > 0
        }
    }
}

/// StatefulRule: consumes DynamicContainer.Info through DynamicLayoutMap and produces
/// LayoutComputer for a dynamic layout list.
private struct DynamicLayoutComputer<L: Layout>: StatefulRule, AsyncAttribute, CustomStringConvertible {
    typealias Value = LayoutComputer
    var _layout: Attribute<L>
    var _environment: Attribute<EnvironmentValues>
    var _containerInfo: OptionalAttribute<DynamicContainer.Info>
    var layoutMap = DynamicLayoutMap()

    var description: String {
        "\(L.self) → LayoutComputer"
    }

    mutating func updateValue() {
        guard let containerInfo = _containerInfo.attribute else {
            fatalError("DynamicLayoutComputer evaluated before its container info was installed.")
        }
        let layout = _layout.value
        let info = containerInfo.value
        let children = layoutMap.attributes(info: info)
        updateLayoutComputer(
            layout: layout,
            environment: _environment,
            attributes: children
        )
    }
}

/// Scrollable collection carrier for dynamic `Layout` children.
private struct DynamicLayoutScrollable: ScrollableCollection, ScrollableContainer {
    var containerInfo: Attribute<DynamicContainer.Info>
    var viewList: Attribute<any ViewList>
    var geometries: Attribute<[ViewGeometry]>
    var transform: Attribute<ViewTransform>
    var parentScrollable: WeakAttribute<any Scrollable>
    var childScrollables: Attribute<ScrollablePreferenceKey.Value>?

    var visibleCollectionViewIDs: [_ViewList_ID.Canonical] {
        collectionViewIDs()
    }

    func forEachVisibleSubview(_ body: (ScrollableCollectionSubview, inout Bool) -> Void) {
        let ids = collectionViewIDs()
        let geometries = geometries.value
        let transform = transform.value
        for offset in ids.indices where geometries.indices.contains(offset) {
            let frame = frame(for: geometries[offset])
            var stop = false
            body(
                ScrollableCollectionSubview(
                    id: viewListID(from: ids[offset]),
                    frame: frame,
                    frameInContent: frame.converted(to: .content, using: transform),
                    transform: transform
                ),
                &stop
            )
            if stop { break }
        }
    }

    func subviewClosestTo(rect: CGRect) -> ScrollableCollectionSubview? {
        var closest: (subview: ScrollableCollectionSubview, distance: CGFloat)?
        forEachVisibleSubview { subview, stop in
            let distance = subview.frame.midpointDistance(to: rect)
            if closest == nil || distance < closest!.distance {
                closest = (subview, distance)
            }
            stop = false
        }
        return closest?.subview
    }

    func nextVisibleCollectionViewID(
        towards point: UnitPoint,
        from id: _ViewList_ID.Canonical,
        border: CGSize,
        ignoring pinnedViews: PinnedScrollableViews
    ) -> _ViewList_ID.Canonical? {
        nil
    }

    static func hasMultipleViewsInAxis(_ axis: Axis) -> Bool {
        false
    }

    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int? {
        viewList.value.firstOffset(of: id)
    }

    func applyCollectionViewIDs(
        from index: inout Int,
        to body: (_ViewList_ID.Canonical, inout Bool) -> Void
    ) -> Bool {
        var emitted = false
        let completed = viewList.value.applyIDs(from: &index, listAttribute: viewList) { id in
            emitted = true
            var stop = false
            body(id.canonicalID, &stop)
            return !stop
        }
        return emitted && completed
    }

    func collectionViewID(for subgraph: AGSubgraph) -> _ViewList_ID.Canonical? {
        containerInfo.value.item(for: subgraph)?.sourceID
    }

    func scroll(toCollectionViewID id: _ViewList_ID.Canonical, anchor: UnitPoint?) -> Bool {
        guard let offset = firstCollectionViewIndex(of: id) else {
            return false
        }
        return setParentTarget { _, _ in
            makeTarget(at: offset, anchor: anchor)
        }
    }

    var parent: (any Scrollable)? {
        resolvedParentScrollable
    }

    var children: [any Scrollable]? {
        childScrollables?.value
    }

    func makeTarget<ID: Hashable>(
        for id: ID
    ) -> ((ScrollGeometry, LayoutDirection) -> ScrollTarget?)? {
        guard let offset = viewList.value.firstOffset(
            forID: id,
            style: _ViewList_IteratorStyle()
        ) else {
            return nil
        }
        let anchor = Transaction.current.scrollTargetAnchor
        return { _, _ in
            makeTarget(at: offset, anchor: anchor)
        }
    }

    private func collectionViewIDs() -> [_ViewList_ID.Canonical] {
        var index = 0
        var ids: [_ViewList_ID.Canonical] = []
        _ = applyCollectionViewIDs(from: &index) { id, stop in
            ids.append(id)
            stop = false
        }
        return ids
    }

    private func makeTarget(at offset: Int, anchor: UnitPoint?) -> ScrollTarget? {
        let geometries = geometries.value
        guard geometries.indices.contains(offset) else {
            return nil
        }
        let rect = frame(for: geometries[offset])
            .converted(to: .content, using: transform.value)
        return ScrollTarget(rect: rect, anchor: anchor)
    }

    private func frame(for geometry: ViewGeometry) -> CGRect {
        CGRect(origin: geometry.origin, size: geometry.dimensions.size.value)
    }

    private func viewListID(from canonical: _ViewList_ID.Canonical) -> _ViewList_ID {
        if let explicitID = canonical.explicitID {
            let implicitID = canonical.implicitID >= 0 ? Int(canonical.implicitID) : 0
            return _ViewList_ID(explicitID: explicitID, implicitID: implicitID)
        }
        return _ViewList_ID(implicitID: Int(canonical.implicitID))
    }

    private var resolvedParentScrollable: (any Scrollable)? {
        guard let graph = _AGGraph.current,
              parentScrollable.isValid(in: graph) else {
            return nil
        }
        return parentScrollable.toStrong().value
    }
}

private extension CGRect {
    func midpointDistance(to other: CGRect) -> CGFloat {
        let dx = midX - other.midX
        let dy = midY - other.midY
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Creates a single AG reduce rule whose input list is resolved dynamically
/// from `nodeListAttr` at evaluation time.
///
/// SE-0352 allows this to be called with `any PreferenceKey.Type`. The
/// compiler opens the existential and binds `K` to the concrete key type,
/// so `Attribute<K.Value>` is correctly typed at call time.
func _makeDynReduceAttr<K: PreferenceKey>(
    _ keyType: K.Type,
    nodeListAttr: Attribute<[AGWeakAttribute]>,
    in graph: _AGGraph
) -> AGAttribute {
    let attr: Attribute<K.Value> = graph.makeRule {
        let nodes = nodeListAttr.value          // registers dep on the ID list
        var combined = K.defaultValue
        for weakNode in nodes where weakNode.isValid(in: graph) {
            let val = Attribute<K.Value>(weakNode.toStrong()).value  // registers dep on each child
            K.reduce(value: &combined) { val }
        }
        return combined
    }
    return attr.identifier
}

public protocol Layout: Sendable, Animatable {
    static var layoutProperties: LayoutProperties { get }

    associatedtype Cache = Void

    typealias Subviews = LayoutSubviews

    func makeCache(subviews: Self.Subviews) -> Self.Cache
    func updateCache(_ cache: inout Self.Cache, subviews: Self.Subviews)
    func spacing(subviews: Self.Subviews, cache: inout Self.Cache) -> ViewSpacing
    func sizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache)
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat?
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat?

    static func _makeLayoutView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs
}

extension Layout {
    /// Builds either the static or dynamic layout graph while keeping
    /// measurement, aggregate placement, and per-child geometry in their
    /// distinct rule owners.
    public static func _makeLayoutView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeLayoutView called outside an active _AGGraph context.")
        }

        // Clear static stack-orientation bits for layout body inputs and expose the
        // live orientation through DynamicStackOrientation.
        let dynamicStackOrientationAttr: Attribute<Axis?> = graph.makeRule(
            DynamicStackOrientationRule(layout: root._attribute)
        )
        var layoutInputs = inputs
        layoutInputs.stackOrientation = nil
        layoutInputs[DynamicStackOrientation.self] = OptionalAttribute(dynamicStackOrientationAttr)

        let childListOutputs = body(_Graph(), layoutInputs)

        // Debug overlay for the layout container itself.
        // Reads the container's pos/size from LayoutChildGeometries-driven posAttr/sizeAttr
        // via the parent. Replace this with the exact layout-container overlay
        // mechanism once modeled.
        let cachedEnvironmentAttr = inputs.base.cachedEnvironment
        let environment = cachedEnvironmentAttr.value.environment
        let containerPosAttr  = inputs.position
        let containerSizeAttr = inputs.size
        let debugDLAttr: Attribute<DisplayList> = graph.makeRule {
            let debugLayout = cachedEnvironmentAttr.value.environment.value._debugLayout
            var dl = DisplayList()
            if debugLayout {
                appendDebugOverlay(
                    to: &dl,
                    frame: CGRect(origin: containerPosAttr.value, size: containerSizeAttr.value.value),
                    category: .layoutContainer
                )
            }
            return dl
        }

        let layoutComputerAttr: Attribute<LayoutComputer>
        var mergedPreferences: PreferencesOutputs

        switch childListOutputs.views {
        case .staticList(let elements):
            var childProxyAttrs: [LayoutProxyAttributes] = []
            var allPreferences: [PreferencesOutputs] = []

            let staticLCAttr: Attribute<LayoutComputer> = graph.makeStatefulRule(
                StaticLayoutComputer(
                    _layout: root._attribute,
                    _environment: environment,
                    childAttributes: [],
                )
            )
            let childGeometries: Attribute<[ViewGeometry]> = graph.makeRule(
                LayoutChildGeometries(
                    parentSize: inputs.size,
                    parentPosition: inputs.position,
                    layoutComputer: staticLCAttr
                )
            )

            var from = 0
            var childIndex = 0
            elements.makeElements(from: &from, inputs: layoutInputs, indirectMap: nil) { elementInputs, makeView in
                let geometry = graph.makeRule(
                    LayoutChildGeometry(
                        _childGeometries: childGeometries,
                        index: childIndex
                    )
                )
                childIndex += 1

                var childInputs = elementInputs
                childInputs.copyCaches()
                childInputs.base.options.insert(.viewNeedsGeometry)
                childInputs.requestsLayoutComputer = true
                childInputs[LayoutPlacementStateInput.self] = OptionalAttribute(
                    graph.makeRule(LayoutGeometryPlacementState(geometry: geometry))
                )
                // Both child inputs project from the same geometry rule so a
                // placement update cannot publish independently recomputed
                // position and size values.
                let posAttr = geometry.origin()
                let sizeAttr = geometry.size()
                let parentTransformAttr = inputs.transform
                let childTransformAttr: Attribute<ViewTransform> = graph.makeRule {
                    var t = parentTransformAttr.value
                    t.appendPosition(posAttr.value)
                    return t
                }
                childInputs.position = posAttr
                childInputs.size = sizeAttr
                childInputs.transform = childTransformAttr
                childInputs.containerPosition = inputs.position
                // Layout placement does not redefine the nearest container
                // size; viewport-sensitive descendants keep the inherited channel.
                childInputs.safeAreaInsets = inputs.safeAreaInsets
                childInputs.stackOrientation = layoutInputs.stackOrientation
                childInputs[DynamicStackOrientation.self] = OptionalAttribute(dynamicStackOrientationAttr)

                let childOutputs = makeView(childInputs)
                if let layoutComputer = childOutputs._layoutComputer.attribute {
                    childProxyAttrs.append(
                        LayoutProxyAttributes(layoutComputer: layoutComputer)
                    )
                } else {
                    childProxyAttrs.append(LayoutProxyAttributes())
                }
                allPreferences.append(childOutputs.preferences)
                return (childOutputs, true)
            }

            graph.mutateStatefulRule(
                staticLCAttr.identifier,
                as: StaticLayoutComputer<Self>.self,
                invalidating: true
            ) {
                $0.childAttributes = childProxyAttrs
            }
            layoutComputerAttr = staticLCAttr
            mergedPreferences = PreferencesOutputs.merge(allPreferences, in: graph)

        case .dynamicList(let viewListAttr, _):
            let dynamicLayoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
                DynamicLayoutComputer(
                    _layout: root._attribute,
                    _environment: environment,
                    _containerInfo: OptionalAttribute()
                )
            )
            let childGeometries: Attribute<[ViewGeometry]> = graph.makeRule(
                LayoutChildGeometries(
                    parentSize: inputs.size,
                    parentPosition: inputs.position,
                    layoutComputer: dynamicLayoutComputer
                )
            )
            let geometryContext = DynamicLayoutViewGeometryContext(
                geometries: childGeometries
            )
            let mapMutator = DynamicLayoutMapMutator { mutation in
                guard let graph = _AGGraph.current else {
                    fatalError("DynamicLayoutMap mutation requires an active AG context.")
                }
                graph.mutateStatefulRule(
                    dynamicLayoutComputer.identifier,
                    as: DynamicLayoutComputer<Self>.self,
                    invalidating: true
                ) {
                    mutation(&$0.layoutMap)
                }
            }
            var dynamicInputs = layoutInputs
            dynamicInputs.stackOrientation = layoutInputs.stackOrientation
            dynamicInputs[DynamicStackOrientation.self] = OptionalAttribute(dynamicStackOrientationAttr)
            dynamicInputs[DynamicLayoutViewGeometryContextInput.self] = geometryContext
            dynamicInputs[DynamicLayoutMapMutatorInput.self] = mapMutator
            let containerInfoAttr: Attribute<DynamicContainer.Info> = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: viewListAttr,
                    inputs: dynamicInputs,
                    parentSubgraph: AGSubgraph.current
                )
            )
            geometryContext.containerInfo = containerInfoAttr
            graph.mutateStatefulRule(
                dynamicLayoutComputer.identifier,
                as: DynamicLayoutComputer<Self>.self,
                invalidating: true
            ) {
                $0._containerInfo = OptionalAttribute(containerInfoAttr)
            }
            layoutComputerAttr = dynamicLayoutComputer

            // Two-level dynamic preference reduce.
            // nodeListAttr reads containerInfoAttr to ensure DynamicContainer.Info is current,
            // then collects the ordered per-child preference node IDs.
            var dynMergedPreferences = PreferencesOutputs()
            var childScrollables: Attribute<ScrollablePreferenceKey.Value>?
            for keyType in inputs.preferences.keys.keys {
                let nodeListAttr: Attribute<[AGWeakAttribute]> = graph.makeRule {
                    let info = containerInfoAttr.value
                    // Retained removals still need to render through DisplayList.Key.
                    // Other preferences stay active-only until their lifecycle is modeled.
                    let items = ObjectIdentifier(keyType) == ObjectIdentifier(DisplayList.Key.self) ?
                        info.displayItems[...] : info.activeItems
                    let nodes = items.flatMap { item in
                        item.preferenceOutputs.flatMap { preferences in
                            preferences.values(for: keyType).compactMap {
                                graph.weakAttributeIfValid(for: $0)
                            }
                        }
                    }
                    return nodes
                }
                let reducedID = _makeDynReduceAttr(keyType, nodeListAttr: nodeListAttr, in: graph)
                dynMergedPreferences.append(keyType, node: reducedID)
                if ObjectIdentifier(keyType) == ObjectIdentifier(ScrollablePreferenceKey.self) {
                    childScrollables = Attribute<ScrollablePreferenceKey.Value>(reducedID)
                }
            }

            let parentScrollable = inputs.weakScrollable
            let collection: Attribute<any ScrollableCollection> = graph.makeRule {
                DynamicLayoutScrollable(
                    containerInfo: containerInfoAttr,
                    viewList: viewListAttr,
                    geometries: childGeometries,
                    transform: inputs.transform,
                    parentScrollable: parentScrollable,
                    childScrollables: childScrollables
                ) as any ScrollableCollection
            }
            if inputs.preferences.keys.contains(ScrollTargetRole.ContentKey.self),
               let role = inputs.scrollTargetRole.attribute {
                let transform: Attribute<(inout ScrollTargetRole.ContentKey.Value) -> Void> = graph.makeRule(
                    ScrollTargetRole.SetLayout(role: role, collection: collection)
                )
                dynMergedPreferences.makePreferenceTransformer(
                    key: ScrollTargetRole.ContentKey.self,
                    transformAttr: transform,
                    graph: graph
                )
            }
            if inputs.preferences.keys.contains(ScrollTargetRole.Key.self),
               let role = inputs.scrollTargetRole.attribute {
                let transform: Attribute<(inout ScrollTargetRole.Key.Value) -> Void> = graph.makeRule(
                    ScrollTargetRole.SetLayout(role: role, collection: collection)
                )
                dynMergedPreferences.makePreferenceTransformer(
                    key: ScrollTargetRole.Key.self,
                    transformAttr: transform,
                    graph: graph
                )
            }
            if inputs.preferences.keys.contains(ScrollablePreferenceKey.self) {
                let transform: Attribute<(inout ScrollablePreferenceKey.Value) -> Void> = graph.makeRule {
                    let scrollable = collection.value as any Scrollable
                    return { value in
                        ScrollablePreferenceKey.reduce(value: &value) { [scrollable] }
                    }
                }
                dynMergedPreferences.makePreferenceTransformer(
                    key: ScrollablePreferenceKey.self,
                    transformAttr: transform,
                    graph: graph
                )
            }
            if inputs.preferences.keys.contains(UpdateScrollStateRequestKey.self) {
                let requests: Attribute<UpdateScrollStateRequestKey.Value> = graph.makeStatefulRule(
                    ScrollStateRequestTransform(collection: collection, inputs: inputs)
                )
                let transform: Attribute<(inout UpdateScrollStateRequestKey.Value) -> Void> = graph.makeRule {
                    let requests = requests.value
                    return { value in
                        UpdateScrollStateRequestKey.reduce(value: &value) { requests }
                    }
                }
                dynMergedPreferences.makePreferenceTransformer(
                    key: UpdateScrollStateRequestKey.self,
                    transformAttr: transform,
                    graph: graph
                )
            }
            mergedPreferences = dynMergedPreferences
        }

        mergedPreferences.append(DisplayList.Key.self, node: debugDLAttr.identifier)

        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: OptionalAttribute(layoutComputerAttr)
        )
    }
}

extension Layout {
    public static var layoutProperties: LayoutProperties {
        .init()
    }

    public func updateCache(_ cache: inout Self.Cache,
                            subviews: Self.Subviews) {
    }

    public func explicitAlignment(of guide: HorizontalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Self.Subviews,
                                  cache: inout Self.Cache) -> CGFloat? {
        return nil
    }

    public func explicitAlignment(of guide: VerticalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Self.Subviews,
                                  cache: inout Self.Cache) -> CGFloat? {
        return nil
    }

    public func spacing(subviews: Self.Subviews,
                        cache: inout Self.Cache) -> ViewSpacing {
        subviews.reduce(ViewSpacing()) { spacing, subview in
            spacing.union(subview.spacing, edges: .all)
        }
    }
}

extension Layout where Self.Cache == () {
    public func makeCache(subviews: Self.Subviews) -> Self.Cache {
        ()
    }
}

extension Layout {
    public func callAsFunction<V>(@ViewBuilder _ content: () -> V) -> some View where V: View {
        _VariadicView.Tree(root: _LayoutRoot(self), content: content())
    }
}

public enum LayoutDirection: Hashable, CaseIterable, Sendable {
    case leftToRight
    case rightToLeft
}

private struct LayoutDirectionKey: EnvironmentKey {
    static var defaultValue: LayoutDirection { .leftToRight }
}

extension EnvironmentValues {
    public var layoutDirection: LayoutDirection {
        get { self[LayoutDirectionKey.self] }
        set { self[LayoutDirectionKey.self] = newValue }
    }
}

public struct LayoutProperties: Sendable {
    public var stackOrientation: Axis?
    public init(stackOrientation: Axis? = nil) {
        self.stackOrientation = stackOrientation
    }
}

struct DynamicStackOrientation: ViewInput {
    static var defaultValue: OptionalAttribute<Axis?> {
        OptionalAttribute()
    }

    static func valuesEqual(_ a: OptionalAttribute<Axis?>, _ b: OptionalAttribute<Axis?>) -> Bool {
        a.base.identifier == b.base.identifier
    }
}

private struct DynamicStackOrientationRule<L: Layout>: Rule {
    var layout: Attribute<L>

    var value: Axis? {
        layout.value._vuiDynamicLayoutProperties.stackOrientation
    }
}

private extension Layout {
    var _vuiDynamicLayoutProperties: LayoutProperties {
        if let anyLayout = self as? AnyLayout {
            return anyLayout.layout._vuiDynamicLayoutProperties
        }
        return Self.layoutProperties
    }
}



private extension Layout {
    @inline(__always)
    func _makeAnyAnimatableData() -> AnyLayout.AnimatableData {
        AnyLayout.AnimatableData(self)
    }

    @inline(__always)
    mutating func _setAnimatableData(_ data: AnyLayout.AnimatableData) {
        data.update(&self)
    }

    @inline(__always)
    func _updateCache(_ cache: inout AnyLayout.Cache,
                      subviews: AnyLayout.Subviews) {
        var c = cache.cache as! Self.Cache
        self.updateCache(&c, subviews: subviews)
        cache.cache = c
    }
    @inline(__always)
    func _spacing(subviews: AnyLayout.Subviews,
                  cache: inout AnyLayout.Cache) -> ViewSpacing {
        var c = cache.cache as! Self.Cache
        let result = self.spacing(subviews: subviews, cache: &c)
        cache.cache = c
        return result
    }
    @inline(__always)
    func _sizeThatFits(proposal: ProposedViewSize,
                       subviews: AnyLayout.Subviews,
                       cache: inout AnyLayout.Cache) -> CGSize {
        var c = cache.cache as! Self.Cache
        let result = self.sizeThatFits(proposal: proposal,
                                       subviews: subviews,
                                       cache: &c)
        cache.cache = c
        return result
    }
    @inline(__always)
    func _placeSubviews(in bounds: CGRect,
                        proposal: ProposedViewSize,
                        subviews: AnyLayout.Subviews,
                        cache: inout AnyLayout.Cache) {
        var c = cache.cache as! Self.Cache
        self.placeSubviews(in: bounds,
                           proposal: proposal,
                           subviews: subviews,
                           cache: &c)
        cache.cache = c
    }
    @inline(__always)
    func _explicitAlignment(of guide: HorizontalAlignment,
                            in bounds: CGRect,
                            proposal: ProposedViewSize,
                            subviews: AnyLayout.Subviews,
                            cache: inout AnyLayout.Cache) -> CGFloat? {
        var c = cache.cache as! Self.Cache
        let result = self.explicitAlignment(of: guide,
                                            in: bounds,
                                            proposal: proposal,
                                            subviews: subviews,
                                            cache: &c)
        cache.cache = c
        return result
    }
    @inline(__always)
    func _explicitAlignment(of guide: VerticalAlignment,
                            in bounds: CGRect,
                            proposal: ProposedViewSize,
                            subviews: AnyLayout.Subviews,
                            cache: inout AnyLayout.Cache) -> CGFloat? {
        var c = cache.cache as! Self.Cache
        let result = self.explicitAlignment(of: guide,
                                            in: bounds,
                                            proposal: proposal,
                                            subviews: subviews,
                                            cache: &c)
        cache.cache = c
        return result
    }
}

public struct AnyLayout: Layout {
    var layout: any Layout

    public struct Cache {
        var cache: Any
    }

    public typealias AnimatableData = _AnyAnimatableData

    public init<L>(_ layout: L) where L: Layout {
        self.layout = layout
    }

    public var animatableData: AnimatableData {
        get { self.layout._makeAnyAnimatableData() }
        set { self.layout._setAnimatableData(newValue) }
    }

    public func placeSubviews(in bounds: CGRect,
                              proposal: ProposedViewSize,
                              subviews: Subviews,
                              cache: inout Cache) {
        self.layout._placeSubviews(in: bounds,
                                   proposal: proposal,
                                   subviews: subviews,
                                   cache: &cache)
    }

    public func sizeThatFits(proposal: ProposedViewSize,
                             subviews: Subviews,
                             cache: inout Cache) -> CGSize {
        self.layout._sizeThatFits(proposal: proposal,
                                  subviews: subviews,
                                  cache: &cache)
    }

    public func explicitAlignment(of guide: HorizontalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Subviews,
                                  cache: inout Cache) -> CGFloat? {
        self.layout._explicitAlignment(of: guide,
                                       in: bounds,
                                       proposal: proposal,
                                       subviews: subviews,
                                       cache: &cache)
    }

    public func explicitAlignment(of guide: VerticalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Subviews,
                                  cache: inout Cache) -> CGFloat? {
        self.layout._explicitAlignment(of: guide,
                                       in: bounds,
                                       proposal: proposal,
                                       subviews: subviews,
                                       cache: &cache)
    }

    public func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        self.layout._spacing(subviews: subviews, cache: &cache)
    }

    public func makeCache(subviews: Subviews) -> Cache {
        Cache(cache: self.layout.makeCache(subviews: subviews))
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        self.layout._updateCache(&cache, subviews: subviews)
    }
}

// VariadicView Root for Layout
public struct _LayoutRoot<L>: _VariadicView.UnaryViewRoot where L: Layout {
    @usableFromInline
    var layout: L
    @inlinable init(_ layout: L) {
        self.layout = layout
    }

    /// Delegates to `L._makeLayoutView` by navigating the root KeyPath to the
    /// embedded `layout: L` AG node.  The generic `Layout._makeLayoutView`
    /// implementation handles the rest.
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        L._makeLayoutView(root: root[\.layout], inputs: inputs, body: body)
    }

    public typealias Body = Never
}

@available(*, unavailable)
extension _LayoutRoot: Sendable {
}

struct DefaultLayoutProperty: PropertyKey {
    static var defaultValue: any Layout { VStackLayout() }
    static func valuesEqual(_ a: any Layout, _ b: any Layout) -> Bool { false }

    var description: String {
        "DefaultLayoutProperty"
    }
}
