//
//  File: Layout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

protocol LeafViewLayout {
    func spacing() -> ViewSpacing
    func sizeThatFits(in proposal: _ProposedSize) -> CGSize
}

extension LeafViewLayout {
    func spacing() -> ViewSpacing {
        ViewSpacing()
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
            LeafLayoutComputer(view: view._attribute)
        )
        outputs._layoutComputer = OptionalAttribute(layoutComputer)
    }
}

private struct LeafLayoutComputer<Leaf: LeafViewLayout>: StatefulRule {
    typealias Value = LayoutComputer

    var view: Attribute<Leaf>

    mutating func updateValue() {
        let engine = LeafLayoutEngine(view: view.value)
        _AGGraph.setStatefulOutput(
            LayoutComputer(box: LayoutEngineBox(engine: engine))
        )
    }
}

struct LeafLayoutEngine<Leaf: LeafViewLayout>: LayoutEngine {
    var view: Leaf

    func spacing() -> ViewSpacing {
        view.spacing()
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        view.sizeThatFits(in: proposal)
    }
}

// MARK: - Layout AG rules

/// AG Rule: computes child geometries for a layout container.
/// Reads parentSize/parentPosition and calls LayoutComputer.childGeometries via the box vtable.
struct LayoutChildGeometries: Rule {
    typealias Value = [ViewGeometry]
    var parentSize: Attribute<ViewSize>
    var parentPosition: Attribute<CGPoint>
    var layoutComputer: Attribute<LayoutComputer>
    func updateValue() -> [ViewGeometry] {
        let lc = layoutComputer.value
        return lc.box.childGeometries_(at: parentSize.value, origin: parentPosition.value)
    }
}

/// AG Rule: extracts one ViewGeometry from the LayoutChildGeometries output by index.
/// Position and size projections are created with makeRule closures.
private struct LayoutChildGeometry: Rule {
    typealias Value = ViewGeometry
    var geometriesAttr: Attribute<[ViewGeometry]>
    var index: Int
    func updateValue() -> ViewGeometry {
        let geoms = geometriesAttr.value
        guard index < geoms.count else {
            return ViewGeometry(origin: .zero,
                                dimensions: ViewDimensions(guideComputer: .defaultValue, size: .zero))
        }
        return geoms[index]
    }
}

/// Shared bridge from dynamic-container item identity back to scroll item geometry.
final class ScrollableLayoutItemGeometryContext {
    var layoutDirection: Attribute<LayoutDirection>
    var containerInfo: Attribute<DynamicContainer.Info>?
    var placement: (AnyHashable) -> _Placement?

    init(
        layoutDirection: Attribute<LayoutDirection>,
        placement: @escaping (AnyHashable) -> _Placement?
    ) {
        self.layoutDirection = layoutDirection
        self.placement = placement
    }

    func identifier(for uniqueId: _ViewList_ID.Canonical) -> AnyHashable? {
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

/// Resolves a dynamic list unique id to the scroll layout's item identifier.
private struct ScrollableItemIdentifier: Rule {
    typealias Value = AnyHashable?

    var uniqueId: _ViewList_ID.Canonical
    var context: ScrollableLayoutItemGeometryContext

    func updateValue() -> AnyHashable? {
        context.identifier(for: uniqueId)
    }
}

/// Publishes geometry that keeps scroll item placement and child layout in sync.
private struct ScrollableItemGeometry: Rule {
    typealias Value = ViewGeometry

    var identifier: Attribute<AnyHashable?>
    var context: ScrollableLayoutItemGeometryContext
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var layoutComputer: Attribute<LayoutComputer>

    func updateValue() -> ViewGeometry {
        guard let identifier = identifier.value,
              let placement = context.placement(identifier) else {
            return ViewGeometry(
                origin: .zero,
                dimensions: ViewDimensions(guideComputer: .defaultValue, size: .zero)
            )
        }
        let layoutDirection = context.layoutDirection.value
        let resolvedSize = size.value
        let proxy = LayoutProxy(
            attributes: LayoutProxyAttributes(layoutComputer: layoutComputer)
        )
        var geometry = proxy.finallyPlaced(
            at: placement,
            in: resolvedSize.value,
            layoutDirection: layoutDirection
        )
        let origin = position.value
        geometry.origin.x += origin.x
        geometry.origin.y += origin.y
        return geometry
    }
}

/// Projection rule for child-facing position inputs rewritten by scroll layout.
private struct ScrollableItemGeometryPosition: Rule {
    typealias Value = CGPoint

    var geometry: Attribute<ViewGeometry>

    func updateValue() -> CGPoint {
        geometry.value.origin
    }
}

/// Projection rule for child-facing size inputs rewritten by scroll layout.
private struct ScrollableItemGeometrySize: Rule {
    typealias Value = ViewSize

    var geometry: Attribute<ViewGeometry>

    func updateValue() -> ViewSize {
        geometry.value.dimensions.size
    }
}

/// StatefulRule: produces LayoutComputer wrapping ViewLayoutEngine<L> for a static child list.
/// Re-fires when layoutAttr changes (e.g. animating spacing). Child LC deps are tracked
/// downstream by LayoutChildGeometries (which calls childGeometries via ViewLayoutEngine).
private struct StaticLayoutComputer<L: Layout>: StatefulRule {
    typealias Value = LayoutComputer
    var layoutAttr: Attribute<L>
    var children: [LayoutProxyAttributes]
    var layoutDirection: LayoutDirection
    mutating func updateValue() {
        let layout = layoutAttr.value
        if var current = _AGGraph.currentStatefulOutput(LayoutComputer.self),
           let box = current.box as? LayoutEngineBox<ViewLayoutEngine<L>> {
            box.engine.update(
                layout: layout,
                layoutAttr: layoutAttr,
                children: children,
                layoutDirection: layoutDirection
            )
            current.changeCount &+= 1
            _AGGraph.setStatefulOutput(current)
            return
        }
        let engine = ViewLayoutEngine(
            layout: layout,
            layoutAttr: layoutAttr,
            children: children,
            layoutDirection: layoutDirection
        )
        let box = LayoutEngineBox(engine: engine)
        _AGGraph.setStatefulOutput(LayoutComputer(box: box))
    }
}

/// Dynamic container storage used by DynamicContainerInfo.
enum DynamicContainer {
    final class TransitionRemovalListener: @unchecked Sendable {
        private struct State {
            var seedValue: UInt32 = 0
            var completionInstalled = false
            var completed = false
            var completionPublished = false
        }

        private let seed: Attribute<UInt32>
        private let inbox: AGInbox
        private let state = Mutex(State())

        init(seed: Attribute<UInt32>, inbox: AGInbox) {
            self.seed = seed
            self.inbox = inbox
        }

        var isComplete: Bool {
            state.withLock { $0.completed }
        }

        var isCompletionPublished: Bool {
            state.withLock { $0.completionPublished }
        }

        func readSeed() {
            _ = seed.value
        }

        func installCompletion(into transaction: inout Transaction) -> AnimationCompletionObserver? {
            let shouldInstall = state.withLock { state in
                guard !state.completionInstalled else {
                    return false
                }
                state.completionInstalled = true
                return true
            }
            guard shouldInstall else {
                return transaction.animationCompletionObserver
            }

            transaction.addAnimationCompletion(
                criteria: .removed,
                tracksStandalonePending: false
            ) { [weak self] in
                self?.complete()
            }
            return transaction.animationCompletionObserver
        }

        private func complete() {
            guard let nextSeed = state.withLock({ state -> UInt32? in
                guard !state.completed else {
                    return nil
                }
                state.completed = true
                state.seedValue &+= 1
                return state.seedValue
            }) else {
                return
            }

            let seed = self.seed
            inbox.enqueue { [weak self] in
                self?.state.withLock { state in
                    state.completionPublished = true
                }
                seed.setValue(nextSeed)
            }
        }
    }

    /// Field roles: subgraph, uniqueId, viewCount, outputs,
    /// needsTransitions, listener, zIndex, removalOrder, precedingViewCount,
    /// resetSeed, phase, item, completion seed, transition transactions.
    /// The identity is stored in canonical form for lookup across updates.
    final class ItemInfo {
        var subgraph: AGSubgraph
        var uniqueId: _ViewList_ID.Canonical
        var viewCount: Int
        var outputs: _ViewOutputs
        var needsTransitions: Bool
        var listener: TransitionRemovalListener?
        var zIndex: Double
        var removalOrder: Int
        var precedingViewCount: Int
        var resetSeed: UInt32
        var phase: UInt8
        // Type-erased dynamic adaptor item payload. The scrollable layout bridge
        // uses this to recover the original collection index from DynamicContainer.Info.
        var item: AnyHashable?
        // Cache for non-unary DynamicContainer items. This keeps each materialized
        // child addressable until multi-output storage is modeled.
        var layoutAttributes: [LayoutProxyAttributes]
        var preferenceOutputs: [PreferencesOutputs]
        var viewPhase: Attribute<TransitionPhase>?
        var transitionPhaseSetters: [_TransitionPhaseSetter]
        var transitionCompletionSeed: Attribute<UInt32>?
        var transitionTransactions: _TransitionTransactionResolver?
        var removalLifecycleStarted: Bool
        var ignoredRetainedUnusedRemovalObserver: ObjectIdentifier?
        var retainAfterRemovalCompletion: Bool

        init(
            subgraph: AGSubgraph,
            uniqueId: _ViewList_ID.Canonical,
            viewCount: Int,
            outputs: _ViewOutputs,
            layoutAttributes: [LayoutProxyAttributes],
            preferenceOutputs: [PreferencesOutputs],
            viewPhase: Attribute<TransitionPhase>? = nil,
            transitionPhaseSetters: [_TransitionPhaseSetter] = [],
            needsTransitions: Bool = false,
            listener: TransitionRemovalListener? = nil,
            zIndex: Double = 0,
            removalOrder: Int = 0,
            precedingViewCount: Int = 0,
            resetSeed: UInt32 = 0,
            phase: UInt8 = 1,
            item: AnyHashable? = nil,
            transitionCompletionSeed: Attribute<UInt32>? = nil,
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
            self.item = item
            self.layoutAttributes = layoutAttributes
            self.preferenceOutputs = preferenceOutputs
            self.viewPhase = viewPhase
            self.transitionPhaseSetters = transitionPhaseSetters
            self.transitionCompletionSeed = transitionCompletionSeed
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

    /// Field roles: items, indexMap, displayMap, removedCount, unusedCount,
    /// allUnary, seed. Equality compares the seed field.
    struct Info: Equatable {
        var items: [ItemInfo] = []
        var indexMap: [_ViewList_ID.Canonical: Int] = [:]
        var displayMap: [UInt32]?
        var removedCount: Int = 0
        var unusedCount: Int = 0
        var allUnary: Bool = true
        var seed: UInt32 = 0

        static func == (lhs: Info, rhs: Info) -> Bool {
            lhs.seed == rhs.seed
        }

        func viewIndex(id: _ViewList_ID.Canonical) -> Int? {
            indexMap[id]
        }

        func item(for id: _ViewList_ID.Canonical) -> ItemInfo? {
            guard let index = indexMap[id], items.indices.contains(index) else { return nil }
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
                    if lhs.phase == 2 { return true }
                    if rhs.phase == 2 { return false }
                }
                return lhsIndex < rhsIndex
            }.map { UInt32($0) }
        }

        private struct ItemIdentity: Equatable {
            var uniqueId: _ViewList_ID.Canonical
            var viewCount: Int
            var phase: UInt8
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

struct LayoutPlacementAnimationsDisabledInput: ViewInput {
    static var defaultValue: Bool { false }
}

struct LayoutPlacementProjection {
    var targetFrame: Attribute<ViewFrame>
    var presentationFrame: Attribute<ViewFrame>
}

struct LayoutPlacementProjectionInput: ViewInput {
    static var defaultValue: LayoutPlacementProjection? { nil }

    static func valuesEqual(
        _ lhs: LayoutPlacementProjection?,
        _ rhs: LayoutPlacementProjection?
    ) -> Bool {
        lhs?.targetFrame.identifier == rhs?.targetFrame.identifier &&
            lhs?.presentationFrame.identifier == rhs?.presentationFrame.identifier
    }
}

private struct ProjectedLayoutPosition: Rule {
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var projection: LayoutPlacementProjection

    func updateValue() -> CGPoint {
        let rawOrigin = position.value
        let childSize = size.value.value
        let target = projection.targetFrame.value
        let presentation = projection.presentationFrame.value
        let targetPoint = CGPoint(
            x: rawOrigin.x + childSize.width * 0.5,
            y: rawOrigin.y + childSize.height * 0.5
        )
        let projectedPoint = CGPoint(
            x: project(
                targetPoint.x,
                from: target.origin.x,
                length: target.size.value.width,
                to: presentation.origin.x,
                length: presentation.size.value.width
            ),
            y: project(
                targetPoint.y,
                from: target.origin.y,
                length: target.size.value.height,
                to: presentation.origin.y,
                length: presentation.size.value.height
            )
        )
        return CGPoint(
            x: projectedPoint.x - childSize.width * 0.5,
            y: projectedPoint.y - childSize.height * 0.5
        )
    }

    private func project(
        _ value: CGFloat,
        from sourceOrigin: CGFloat,
        length sourceLength: CGFloat,
        to destinationOrigin: CGFloat,
        length destinationLength: CGFloat
    ) -> CGFloat {
        guard sourceLength != 0 else {
            return destinationOrigin + value - sourceOrigin
        }
        let unitPosition = (value - sourceOrigin) / sourceLength
        return destinationOrigin + destinationLength * unitPosition
    }
}

/// Keeps a phase-3 retained-unused item cached after its later animated removal
/// listener completes. Cache-owned lazy hosts use this to preserve source state
/// across same-identity removal/reinsertion windows.
struct DynamicContainerRetainCompletedUnusedRemovals: ViewInput {
    static var defaultValue: Bool { false }
}

/// Stores layout attributes keyed by DynamicContainer item id and rebuilds its sorted
/// attribute cache when DynamicContainer.Info.seed changes.
private struct DynamicLayoutMap {
    var map: [_ViewList_ID.Canonical: [LayoutProxyAttributes]] = [:]
    var sortedArray: [LayoutProxyAttributes] = []
    var sortedSeeds: UInt32?

    mutating func set(_ attributes: [LayoutProxyAttributes], uniqueId: _ViewList_ID.Canonical) {
        if attributes.isEmpty {
            map.removeValue(forKey: uniqueId)
        } else {
            map[uniqueId] = attributes
        }
        sortedSeeds = nil
    }

    mutating func remove(uniqueId: _ViewList_ID.Canonical) {
        map.removeValue(forKey: uniqueId)
        sortedSeeds = nil
    }

    mutating func replace(with info: DynamicContainer.Info) {
        map.removeAll(keepingCapacity: true)
        sortedSeeds = nil
        for item in info.activeItems {
            set(item.layoutAttributes, uniqueId: item.uniqueId)
        }
    }

    mutating func attributes(info: DynamicContainer.Info) -> [LayoutProxyAttributes] {
        if sortedSeeds == info.seed { return sortedArray }

        let activeItems = info.activeItems
        let orderedItems: [DynamicContainer.ItemInfo]
        if let displayMap = info.displayMap {
            // Retained removal items stay alive for rendering and completion, but
            // layout itself consumes the active prefix so siblings collapse into
            // their target slots immediately.
            let activeDisplayMap = info.removedCount > 0 ?
                displayMap.prefix(activeItems.count) : displayMap[...]
            orderedItems = activeDisplayMap.compactMap { index in
                let i = Int(index)
                guard i >= activeItems.startIndex && i < activeItems.endIndex else { return nil }
                return info.items[i]
            }
        } else {
            orderedItems = Array(activeItems)
        }

        sortedArray = orderedItems.flatMap { item in
            let attributes = map[item.uniqueId] ?? item.layoutAttributes
            if attributes.isEmpty {
                return Array(repeating: LayoutProxyAttributes(), count: item.viewCount)
            }
            return attributes
        }
        sortedSeeds = info.seed
        return sortedArray
    }
}

/// StatefulRule: reconciles dynamic container items and publishes DynamicContainer.Info.
struct DynamicContainerInfo: StatefulRule {
    typealias Value = DynamicContainer.Info
    var viewListAttr: Attribute<any ViewList>
    var inputs: _ViewInputs
    var info = DynamicContainer.Info()
    var retainedElements: [_ViewList_ID.Canonical: _ViewList_SubgraphRelease] = [:]
    var hasValue = false

    mutating func updateValue() {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicContainerInfo.updateValue called outside AG context.")
        }

        let capturedInputs = inputs
        let currentList = viewListAttr.value
        let inheritedTransaction = inputs.base.transaction.value
        let listTransaction = graph.transaction(for: viewListAttr.identifier) ?? inheritedTransaction
        var from = 0
        var liveIDs = Set<_ViewList_ID.Canonical>()
        var orderedItems: [DynamicContainer.ItemInfo] = []
        var precedingViewCount = 0
        var needsInsertionPhaseUpdate = false

        _ = _applySublists(in: currentList, from: &from, listAttribute: viewListAttr) { sublist in
            for offset in 0..<sublist.count {
                let elementIndex = sublist.start + offset
                let id = sublist.id.elementID(at: elementIndex).canonicalID
                liveIDs.insert(id)

                let viewCount = sublist.elements.count
                let needsTransitions = sublist.traits[CanTransitionTraitKey.self]
                // allUnary becomes false when any active item reports viewCount != 1.
                // The same viewCount is used for cumulative child offsets.
                if let existing = info.item(for: id), existing.viewCount != viewCount {
                    existing.invalidate()
                    retainedElements.removeValue(forKey: id)
                }
                if let existing = info.item(for: id), existing.needsTransitions != needsTransitions {
                    existing.invalidate()
                    retainedElements.removeValue(forKey: id)
                }

                let reusableItem = info.item(for: id).flatMap { existing in
                    existing.viewCount == viewCount && existing.needsTransitions == needsTransitions ? existing : nil
                }
                let transition = needsTransitions ? sublist.traits[TransitionTraitKey.self] : nil
                let insertionTransaction = reusableItem == nil && hasValue
                    ? transition?.positiveInsertionTransaction(from: listTransaction)
                    : nil
                let item: DynamicContainer.ItemInfo?
                if let reusableItem {
                    item = reusableItem
                } else {
                    item = makeItem(
                        uniqueId: id,
                        viewCount: viewCount,
                        sublist: sublist,
                        offset: offset,
                        transition: transition,
                        initialTransitionPhase: insertionTransaction == nil ? .identity : .willAppear,
                        capturedInputs: capturedInputs,
                        graph: graph
                    )
                }
                if let item {
                    // Item object depth is driven by view-level zIndex. displayMap
                    // stores UInt32 item indexes sorted by that depth.
                    item.zIndex = sublist.traits[ZIndexTraitKey.self]
                    item.needsTransitions = needsTransitions
                    if item.phase == 3 {
                        item.subgraph.didReinsert()
                    }
                    if insertionTransaction != nil {
                        item.phase = 0
                        needsInsertionPhaseUpdate = true
                    } else if item.phase != 1 {
                        item.listener = nil
                        item.removalLifecycleStarted = false
                        item.retainAfterRemovalCompletion = false
                        item.setTransitionPhase(.identity, transaction: listTransaction)
                        item.phase = 1
                    }
                    item.precedingViewCount = precedingViewCount
                    precedingViewCount += item.viewCount
                    orderedItems.append(item)
                }
            }
            return true
        }

        let retention = retainedInactiveItems(
            excluding: liveIDs,
            transaction: listTransaction,
            graph: graph
        )
        info.replaceItems(
            active: orderedItems,
            removed: retention.removed,
            unused: retention.unused
        )
        hasValue = true
        _AGGraph.setStatefulOutput(info)
        if needsInsertionPhaseUpdate,
           let currentAttribute = _AGGraph.currentRuleContextAttribute {
            graph.inbox.enqueue {
                graph.invalidateAttribute(currentAttribute)
            }
        }
    }

    private mutating func retainedInactiveItems(
        excluding liveIDs: Set<_ViewList_ID.Canonical>,
        transaction: Transaction,
        graph: _AGGraph
    ) -> (removed: [DynamicContainer.ItemInfo], unused: [DynamicContainer.ItemInfo]) {
        var removedItems: [DynamicContainer.ItemInfo] = []
        var unusedItems: [DynamicContainer.ItemInfo] = []
        let maxUnusedItems = max(inputs[DynamicContainerMaxUnusedItems.self], 0)
        let retainCompletedUnusedRemovals = inputs[DynamicContainerRetainCompletedUnusedRemovals.self]
        func positiveRemovalTransition(
            for item: DynamicContainer.ItemInfo
        ) -> (transaction: Transaction, completionSeed: Attribute<UInt32>)? {
            let transitionTransaction = item.transitionTransactions?(.didDisappear, transaction)
                .first { candidate in
                    guard let animation = candidate.effectiveAnimation else { return false }
                    return animation.box.duration > 0
                }
            guard item.needsTransitions,
                  let transitionTransaction,
                  let animation = transitionTransaction.effectiveAnimation,
                  animation.box.duration > 0,
                  let completionSeed = item.transitionCompletionSeed else {
                return nil
            }
            return (transitionTransaction, completionSeed)
        }

        for item in info.items where !liveIDs.contains(item.uniqueId) {
            if item.phase == 2 {
                guard let listener = item.listener else {
                    item.invalidate()
                    retainedElements.removeValue(forKey: item.uniqueId)
                    continue
                }
                listener.readSeed()
                if listener.isCompletionPublished {
                    if item.retainAfterRemovalCompletion {
                        item.listener = nil
                        item.retainAfterRemovalCompletion = false
                        item.phase = 3
                        item.removalOrder = 0
                        guard unusedItems.count < maxUnusedItems else {
                            item.invalidate()
                            retainedElements.removeValue(forKey: item.uniqueId)
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
                        item.removalOrder = removedItems.count
                        removedItems.append(item)
                        continue
                    }
                    item.invalidate()
                    retainedElements.removeValue(forKey: item.uniqueId)
                    continue
                }
                item.removalOrder = removedItems.count
                removedItems.append(item)
                continue
            }
            if item.phase == 3 {
                let transition = positiveRemovalTransition(for: item)
                let observerID = transition?.transaction.animationCompletionObserver.map(ObjectIdentifier.init)
                let didIgnoreObserver = observerID != nil &&
                    item.ignoredRetainedUnusedRemovalObserver == observerID
                if removedItems.isEmpty,
                   !didIgnoreObserver,
                   let transition {
                    let listener = DynamicContainer.TransitionRemovalListener(
                        seed: transition.completionSeed,
                        inbox: graph.inbox
                    )
                    item.listener = listener
                    item.ignoredRetainedUnusedRemovalObserver = nil
                    item.retainAfterRemovalCompletion = retainCompletedUnusedRemovals

                    var removalTransaction = transition.transaction
                    _ = listener.installCompletion(into: &removalTransaction)
                    item.phase = 2
                    item.removalLifecycleStarted = true
                    item.setTransitionPhase(.didDisappear, transaction: removalTransaction)
                    listener.readSeed()
                    finalizeAnimationCompletions(
                        in: removalTransaction,
                        animation: removalTransaction.effectiveAnimation
                    )

                    item.removalOrder = removedItems.count
                    removedItems.append(item)
                    continue
                }
                if !removedItems.isEmpty, let observerID {
                    item.ignoredRetainedUnusedRemovalObserver = observerID
                }
                guard unusedItems.count < maxUnusedItems else {
                    item.invalidate()
                    retainedElements.removeValue(forKey: item.uniqueId)
                    continue
                }
                unusedItems.append(item)
                continue
            }

            guard let transition = positiveRemovalTransition(for: item) else {
                guard unusedItems.count < maxUnusedItems else {
                    item.invalidate()
                    retainedElements.removeValue(forKey: item.uniqueId)
                    continue
                }
                item.listener = nil
                item.subgraph.willRemove()
                item.phase = 3
                item.removalOrder = 0
                unusedItems.append(item)
                continue
            }

            let listener = DynamicContainer.TransitionRemovalListener(
                seed: transition.completionSeed,
                inbox: graph.inbox
            )
            item.listener = listener

            var removalTransaction = transition.transaction
            _ = listener.installCompletion(into: &removalTransaction)
            item.phase = 2
            item.setTransitionPhase(.didDisappear, transaction: removalTransaction)
            listener.readSeed()
            finalizeAnimationCompletions(
                in: removalTransaction,
                animation: removalTransaction.effectiveAnimation
            )

            item.removalOrder = removedItems.count
            removedItems.append(item)
        }
        return (removedItems, unusedItems)
    }

    private mutating func makeItem(
        uniqueId: _ViewList_ID.Canonical,
        viewCount: Int,
        sublist: _ViewList_Sublist,
        offset: Int,
        transition: AnyTransition?,
        initialTransitionPhase: TransitionPhase,
        capturedInputs: _ViewInputs,
        graph: _AGGraph
    ) -> DynamicContainer.ItemInfo? {
        let subgraph = AGSubgraph()
        let release = (sublist.elements as? _ViewList_SubgraphElements)?.retain()
        var baseInputs = capturedInputs
        baseInputs.copyCaches()

        let item: DynamicContainer.ItemInfo? = AGSubgraph.withCurrent(subgraph) {
            let viewPhase = graph.makeInput(value: initialTransitionPhase)
            let parentTransform = capturedInputs.transform

            var firstOutputs: _ViewOutputs?
            var layoutAttributes: [LayoutProxyAttributes] = []
            var preferenceOutputs: [PreferencesOutputs] = []
            var transitionPhaseSetters: [_TransitionPhaseSetter] = []
            let transitionCompletionSeed = transition.map { _ in graph.makeInput(value: UInt32(0)) }
            let traitsListAttr = sublist.list.map { OptionalAttribute($0) } ??
                OptionalAttribute<any ViewList>()
            let scrollContext = baseInputs[ScrollableLayoutItemGeometryContextKey.self]
            let dynamicItem = scrollContext != nil ? sublist.id.canonicalID.explicitID : nil

            // Non-unary items are a single DynamicContainer item whose viewCount spans
            // multiple child outputs, not multiple item records.
            for elementOffset in offset..<(offset + viewCount) {
                let rawPosAttr = graph.makeInput(value: CGPoint.zero)
                let rawSizeAttr = graph.makeInput(value: ViewSize(.zero))
                let isPlacedAttr = graph.makeInput(value: false)
                let scrollBasePosAttr = scrollContext.map { _ in
                    graph.makeInput(value: CGPoint.zero)
                }
                let scrollLayoutComputer = scrollContext.map { _ in
                    graph.makeIndirectAttribute(defaultValue: LayoutComputer.defaultValue)
                }

                let childOutputs = sublist.elements.makeOneElement(at: elementOffset, inputs: baseInputs) {
                    elementInputs,
                    makeView in
                    var childInputs = elementInputs
                    childInputs[DynamicContainerTransitionPhaseInput.self] =
                        OptionalAttribute(viewPhase)
                    childInputs[LayoutPlacementStateInput.self] =
                        OptionalAttribute(isPlacedAttr)
                    let projectedPosition = childInputs[
                        LayoutPlacementProjectionInput.self
                    ].map { projection in
                        graph.makeRule(
                            ProjectedLayoutPosition(
                                position: rawPosAttr,
                                size: rawSizeAttr,
                                projection: projection
                            )
                        )
                    } ?? rawPosAttr
                    let animatedFrame = makeAnimatableFrameAttributes(
                        in: &childInputs.base,
                        position: projectedPosition,
                        size: rawSizeAttr,
                        supportsVFD: childInputs.supportsVFD,
                        animationsDisabled: childInputs[
                            LayoutPlacementAnimationsDisabledInput.self
                        ]
                    )
                    let posAttr = animatedFrame.position
                    let sizeAttr = animatedFrame.size
                    let childTransform: Attribute<ViewTransform> = graph.makeRule {
                        var t = parentTransform.value
                        // The backend placement bridge writes absolute root/window origins
                        // into posAttr. Keep parent transform items, but do not translate the
                        // already-absolute origin through the parent position again.
                        t.appendPosition(posAttr.value)
                        return t
                    }
                    childInputs.position = posAttr
                    childInputs.size = sizeAttr
                    if let scrollContext, let scrollLayoutComputer {
                        let identifierAttr = graph.makeRule(
                            ScrollableItemIdentifier(uniqueId: uniqueId, context: scrollContext)
                        )
                        let geometryAttr = graph.makeRule(
                            ScrollableItemGeometry(
                                identifier: identifierAttr,
                                context: scrollContext,
                                position: scrollBasePosAttr ?? posAttr,
                                size: sizeAttr,
                                layoutComputer: scrollLayoutComputer
                            )
                        )
                        if childInputs.needsGeometry {
                            childInputs.size = graph.makeRule(
                                ScrollableItemGeometrySize(geometry: geometryAttr)
                            )
                            childInputs.position = graph.makeRule(
                                ScrollableItemGeometryPosition(geometry: geometryAttr)
                            )
                            childInputs.requestsLayoutComputer = true
                        }
                    }
                    childInputs.transform = childTransform
                    childInputs.containerPosition = capturedInputs.position
                    childInputs.safeAreaInsets = capturedInputs.safeAreaInsets
                    childInputs.containerSize = OptionalAttribute(capturedInputs.size)
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

                let wrapperLC: Attribute<LayoutComputer> = graph.makeRule {
                    let inner = lcAttr.value
                    var pendingPlacementTransaction = graph.transaction(for: lcAttr.identifier)
                    return LayoutComputer(
                        sizeThatFits: { inner.sizeThatFits($0) },
                        spacing: inner.spacing,
                        place: { pos, anchor, proposal in
                            let sz = inner.sizeThatFits(proposal)
                            let rawOrigin = CGPoint(
                                x: pos.x - sz.width * anchor.x,
                                y: pos.y - sz.height * anchor.y
                            )
                            // The transaction captured when the child layout computer
                            // refreshed applies to its next placement only. Reading the
                            // graph transaction again here would revive stale resource
                            // publication keys during later parent animations.
                            let placementTransaction =
                                pendingPlacementTransaction ?? Transaction.current
                            pendingPlacementTransaction = nil
                            rawPosAttr.setValue(rawOrigin, transaction: placementTransaction)
                            rawSizeAttr.setValue(
                                ViewSize(sz, proposal: proposal),
                                transaction: placementTransaction
                            )
                            isPlacedAttr.setValue(true, transaction: placementTransaction)
                            if let scrollContext,
                               let scrollBasePosAttr,
                               let identifier = dynamicItem,
                               let placement = scrollContext.placement(identifier) {
                                scrollBasePosAttr.setValue(
                                    CGPoint(
                                        x: pos.x - placement.anchorPosition.x,
                                        y: pos.y - placement.anchorPosition.y
                                    )
                                )
                            } else {
                                scrollBasePosAttr?.setValue(rawOrigin)
                            }
                            Transaction.withScopedThreadTransaction(placementTransaction) {
                                inner.place(at: pos, anchor: anchor, proposal: proposal)
                            }
                        },
                        explicitAlignment: { inner.explicitAlignment($0, at: $1) }
                    )
                }
                if let scrollLayoutComputer {
                    graph.setIndirectTarget(scrollLayoutComputer, to: wrapperLC)
                }

                layoutAttributes.append(LayoutProxyAttributes(
                    layoutComputer: wrapperLC,
                    traitsList: traitsListAttr
                ))
            }

            guard var outputs = firstOutputs else { return nil }
            if let firstLayoutComputer = layoutAttributes.first?.layoutComputer.attribute {
                outputs._layoutComputer = OptionalAttribute(firstLayoutComputer)
            }
            return DynamicContainer.ItemInfo(
                subgraph: subgraph,
                uniqueId: uniqueId,
                viewCount: viewCount,
                outputs: outputs,
                layoutAttributes: layoutAttributes,
                preferenceOutputs: preferenceOutputs,
                viewPhase: viewPhase,
                transitionPhaseSetters: transitionPhaseSetters,
                needsTransitions: transition != nil,
                phase: initialTransitionPhase == .willAppear ? 0 : 1,
                item: dynamicItem,
                transitionCompletionSeed: transitionCompletionSeed,
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
            retainedElements[uniqueId] = release
        }
        return item
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
private struct DynamicLayoutComputer<L: Layout>: StatefulRule {
    typealias Value = LayoutComputer
    var layoutAttr: Attribute<L>
    var containerInfoAttr: Attribute<DynamicContainer.Info>
    var layoutMap = DynamicLayoutMap()

    mutating func updateValue() {
        let layout = layoutAttr.value
        let info = containerInfoAttr.value
        layoutMap.replace(with: info)
        let children = layoutMap.attributes(info: info)
        for child in children {
            _ = child.layoutComputer.attribute?.value
        }  // register AG deps on each child LC
        if var current = _AGGraph.currentStatefulOutput(LayoutComputer.self),
           let box = current.box as? LayoutEngineBox<ViewLayoutEngine<L>> {
            box.engine.update(
                layout: layout,
                layoutAttr: layoutAttr,
                children: children,
                layoutDirection: .leftToRight
            )
            current.changeCount &+= 1
            _AGGraph.setStatefulOutput(current)
            return
        }
        let engine = ViewLayoutEngine(
            layout: layout,
            layoutAttr: layoutAttr,
            children: children,
            layoutDirection: .leftToRight
        )
        _AGGraph.setStatefulOutput(LayoutComputer(box: LayoutEngineBox(engine: engine)))
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

    func subviewClosest(to rect: CGRect) -> ScrollableCollectionSubview? {
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

    static func hasMultipleViews(in axis: Axis) -> Bool {
        false
    }

    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int? {
        viewList.value.firstOffset(forID: id, style: _ViewList_IteratorStyle())
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
        containerInfo.value.item(for: subgraph)?.uniqueId
    }

    func scroll(toCollectionViewID id: _ViewList_ID.Canonical, anchor: UnitPoint?) -> Bool {
        guard let offset = firstCollectionViewIndex(of: id) else {
            return false
        }
        return setContentTarget { _, _ in
            makeTarget(at: offset, anchor: anchor)
        }
    }

    var containerParentScrollable: (any Scrollable)? {
        resolvedParentScrollable
    }

    var containerChildScrollables: [any Scrollable] {
        childScrollables?.value ?? []
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

public protocol Layout: Animatable {
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
    /// Generic implementation of `_makeLayoutView` that works for any `Layout` type.
    ///
    /// Algorithm:
    /// 1. Calls `body(_Graph(), inputs)` to wire the content's AG nodes and obtain
    ///    `_ViewListOutputs` containing per-child `ViewProxy` values.
    /// 2. For each child proxy, creates a per-child position `Attribute<CGPoint>` and
    ///    calls `proxy.makeView` with child-specific inputs to get `_ViewOutputs`.
    /// 3. Creates an `Attribute<LayoutComputer>` rule that:
    ///    - reads the layout configuration from `root._attribute` (registers dependency),
    ///    - reads each child's LayoutComputer attribute (registers re-layout dependency),
    ///    - builds `LayoutSubviews` and returns a `LayoutComputer` with sizing and
    ///      placement closures that delegate to the concrete `Layout` protocol methods.
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
            // Step 1: makeElements traversal. Create per-child indirect posAttr/sizeAttr,
            //   call makeView, collect child LCs + prefs. Indirect attrs resolve the chicken-and-egg:
            //   makeView needs posAttr/sizeAttr handles, and those are wired to concrete attrs later.
            var childProxyAttrs: [LayoutProxyAttributes] = []
            var allPreferences: [PreferencesOutputs] = []

            var from = 0
            elements.makeElements(from: &from, inputs: layoutInputs, indirectMap: nil) { elementInputs, makeView in
                // Backend bridge: primitive display rules read the position/size
                // attributes they received during makeView. StaticLayoutComputer's
                // geometry projection is not enough unless the render backend pulls
                // those projection attrs directly, so keep concrete placement attrs
                // and update them from the LayoutComputer.place path.
                // Replace this bridge once the renderer consumes
                // LayoutChildGeometries projection directly.
                let rawPosAttr = graph.makeInput(value: CGPoint.zero)
                let rawSizeAttr = graph.makeInput(value: ViewSize.zero)
                let isPlacedAttr = graph.makeInput(value: false)

                var childInputs = elementInputs
                childInputs[LayoutPlacementStateInput.self] =
                    OptionalAttribute(isPlacedAttr)
                let projectedPosition = childInputs[
                    LayoutPlacementProjectionInput.self
                ].map { projection in
                    graph.makeRule(
                        ProjectedLayoutPosition(
                            position: rawPosAttr,
                            size: rawSizeAttr,
                            projection: projection
                        )
                    )
                } ?? rawPosAttr
                let animatedFrame = makeAnimatableFrameAttributes(
                    in: &childInputs.base,
                    position: projectedPosition,
                    size: rawSizeAttr,
                    supportsVFD: childInputs.supportsVFD,
                    animationsDisabled: childInputs[
                        LayoutPlacementAnimationsDisabledInput.self
                    ]
                )
                let posAttr = animatedFrame.position
                let sizeAttr = animatedFrame.size
                let parentTransformAttr = inputs.transform
                let childTransformAttr: Attribute<ViewTransform> = graph.makeRule {
                    var t = parentTransformAttr.value
                    // The backend placement bridge writes absolute root/window origins
                    // into posAttr. Keep parent transform items, but do not translate the
                    // already-absolute origin through the parent position again.
                    t.appendPosition(posAttr.value)
                    return t
                }
                childInputs.position = posAttr
                childInputs.size = sizeAttr
                childInputs.transform = childTransformAttr
                childInputs.containerPosition = inputs.position
                childInputs.containerSize = OptionalAttribute(inputs.size)
                childInputs.safeAreaInsets = inputs.safeAreaInsets
                childInputs.stackOrientation = layoutInputs.stackOrientation
                childInputs[DynamicStackOrientation.self] = OptionalAttribute(dynamicStackOrientationAttr)

                let childOutputs = makeView(childInputs)
                if let lcAttr = childOutputs._layoutComputer.attribute {
                    let wrapperLC: Attribute<LayoutComputer> = graph.makeRule {
                        let inner = lcAttr.value
                        var pendingPlacementTransaction = graph.transaction(for: lcAttr.identifier)
                        return LayoutComputer(
                            sizeThatFits: { inner.sizeThatFits($0) },
                            spacing: inner.spacing,
                            place: { position, anchor, proposal in
                                let resolvedSize = inner.sizeThatFits(proposal)
                                let origin = CGPoint(
                                    x: position.x - resolvedSize.width * anchor.x,
                                    y: position.y - resolvedSize.height * anchor.y
                                )
                                // Consume the child refresh transaction once. Later
                                // placements inherit the active layout transaction.
                                let placementTransaction =
                                    pendingPlacementTransaction ?? Transaction.current
                                pendingPlacementTransaction = nil
                                rawPosAttr.setValue(origin, transaction: placementTransaction)
                                rawSizeAttr.setValue(
                                    ViewSize(resolvedSize, proposal: proposal),
                                    transaction: placementTransaction
                                )
                                isPlacedAttr.setValue(true, transaction: placementTransaction)
                                Transaction.withScopedThreadTransaction(placementTransaction) {
                                    inner.place(at: position, anchor: anchor, proposal: proposal)
                                }
                            },
                            priority: inner.priority,
                            explicitAlignment: { inner.explicitAlignment($0, at: $1) }
                        )
                    }
                    // Trait-writing static bodies are promoted to dynamicList by
                    // _TraitWritingModifier._makeViewList, so the plain static path has no
                    // ViewList attribute for LayoutProxyAttributes.traitsList.
                    childProxyAttrs.append(LayoutProxyAttributes(layoutComputer: wrapperLC))
                    allPreferences.append(childOutputs.preferences)
                }
                return (childOutputs, true)
            }

            let staticLCAttr: Attribute<LayoutComputer> = graph.makeStatefulRule(
                StaticLayoutComputer(
                    layoutAttr: root._attribute,
                    children: childProxyAttrs,
                    layoutDirection: .leftToRight
                )
            )

            layoutComputerAttr = staticLCAttr
            mergedPreferences = PreferencesOutputs.merge(allPreferences, in: graph)

        case .dynamicList(let viewListAttr, _):
            // DynamicContainerInfo manages item lifecycle. DynamicLayoutComputer consumes its Info.
            var dynamicInputs = layoutInputs
            dynamicInputs.stackOrientation = layoutInputs.stackOrientation
            dynamicInputs[DynamicStackOrientation.self] = OptionalAttribute(dynamicStackOrientationAttr)
            let containerInfoAttr: Attribute<DynamicContainer.Info> = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: viewListAttr,
                    inputs: dynamicInputs
                )
            )

            layoutComputerAttr = graph.makeStatefulRule(
                DynamicLayoutComputer(
                    layoutAttr: root._attribute,
                    containerInfoAttr: containerInfoAttr
                )
            )
            let childGeometries: Attribute<[ViewGeometry]> = graph.makeRule(
                LayoutChildGeometries(
                    parentSize: inputs.size,
                    parentPosition: inputs.position,
                    layoutComputer: layoutComputerAttr
                )
            )

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
                        info.activeAndRemovedItems : info.activeItems
                    return items.flatMap { item in
                        item.preferenceOutputs.flatMap { preferences in
                            preferences.values(for: keyType).compactMap {
                                graph.weakAttributeIfValid(for: $0)
                            }
                        }
                    }
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

public enum LayoutDirection: Hashable, CaseIterable {
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

public struct LayoutProperties {
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

    func updateValue() -> Axis? {
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

struct DefaultLayoutProperty: PropertyKey {
    static var defaultValue: any Layout { VStackLayout() }
    static func valuesEqual(_ a: any Layout, _ b: any Layout) -> Bool { false }

    var description: String {
        "DefaultLayoutProperty"
    }
}
