//
//  File: LazyStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct ResettableLazyLayoutRoot<Content>: View where Content: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var lazyInputs = inputs
        lazyInputs.base[DynamicContainerWillRemoveBeforeInvalidation.self] = true
        return Content._makeView(view: view[\.content], inputs: lazyInputs)
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Content._makeViewList(view: view[\.content], inputs: inputs)
    }

    typealias Body = Never
}

extension ResettableLazyLayoutRoot: _PrimitiveView {
}

extension View {
    func resettableLazyLayoutRoot() -> ResettableLazyLayoutRoot<Self> {
        ResettableLazyLayoutRoot { self }
    }
}

struct LazyLayoutCacheSection: Hashable {
    var id: UInt32?
    var isHeader: Bool
    var isFooter: Bool

    init(id: UInt32? = nil, isHeader: Bool = false, isFooter: Bool = false) {
        self.id = id
        self.isHeader = isHeader
        self.isFooter = isFooter
    }
}

struct _LazyLayout_Subview {
    var cache: LazyLayoutViewCache
    var context: AnyRuleContext
    var data: Data
    var index: Int

    init(
        cache: LazyLayoutViewCache,
        context: AnyRuleContext,
        data: Data,
        index: Int
    ) {
        self.cache = cache
        self.context = context
        self.data = data
        self.index = index
    }

    struct Data {
        var elements: _ViewList_SubgraphElements
        var id: _ViewList_ID
        var traits: ViewTraitCollection
        var list: Attribute<any ViewList>?
        var section: LazyLayoutCacheSection

        init(
            elements: _ViewList_SubgraphElements,
            id: _ViewList_ID,
            traits: ViewTraitCollection = ViewTraitCollection(),
            list: Attribute<any ViewList>? = nil,
            section: LazyLayoutCacheSection = LazyLayoutCacheSection()
        ) {
            self.elements = elements
            self.id = id
            self.traits = traits
            self.list = list
            self.section = section
        }
    }

    enum Kind: Hashable {
        case normal
        case header
        case footer
    }

    func beginPrefetching(at proposal: ProposedViewSize) {
        cache.item(data: data).beginPrefetching(at: proposal)
    }
}

final class LazyLayoutCacheItem {
    struct State: Hashable {
        var resetDelta: UInt32
        var phase: TransitionPhase
        var enableTransitions: Bool
        var isRemoved: Bool

        init(
            resetDelta: UInt32 = 0,
            phase: TransitionPhase = .identity,
            enableTransitions: Bool = false,
            isRemoved: Bool = false
        ) {
            self.resetDelta = resetDelta
            self.phase = phase
            self.enableTransitions = enableTransitions
            self.isRemoved = isRemoved
        }
    }

    enum PrefetchPhase: Hashable {
        case notPrefetching
        case prefetching
        case pendingDisplay
        case pendingRemoval
    }

    enum ParentingPhase: Hashable {
        case inserted
        case removed
    }

    struct AllItemsPhaseMutation: GraphMutation {
        weak var cache: LazyLayoutViewCache?

        func apply() {
            cache?.updateItemPhases()
        }
    }

    struct SingleItemPhaseMutation: GraphMutation {
        weak var cache: LazyLayoutViewCache?
        weak var item: LazyLayoutCacheItem?

        func apply() {
            guard let item else { return }
            cache?.updateItemPhase(item)
        }
    }

    weak var cache: LazyLayoutViewCache?
    var subgraph: AGSubgraph
    var outputs: _ViewOutputs
    var _state: Attribute<State>
    var _list: OptionalAttribute<any ViewList>
    var elements: _ViewList_SubgraphElements
    var elementIndex: Int
    var releaseElements: _ViewList_SubgraphRelease?
    var indirectMap: IndirectAttributeMap?
    var transition: AGAttribute?
    var transitionType: Any.Type?
    var id: _ViewList_ID
    var reuseIdentifier: Int
    var section: LazyLayoutCacheSection
    var zIndex: Double
    var insertionTransactionSeed: UInt32
    var removalTransactionSeed: UInt32
    var animationCount: UInt32
    var usedSeed: UInt32
    var placementSeed: UInt32
    var commitSeed: UInt32
    var prefetchSeed: UInt32
    var prefetchPhase: PrefetchPhase
    var displayIndex: Int?
    var removedSeed: UInt32
    var placement: _Placement?
    var pendingPlacement: _Placement?
    var releaseSecondaryElements: _ViewList_SubgraphRelease?
    var willEnableTransitions: Bool
    var willAnimateRemoval: Bool
    var parentingPhase: ParentingPhase?
    var hasWarned: Bool

    init(
        cache: LazyLayoutViewCache?,
        subgraph: AGSubgraph,
        outputs: _ViewOutputs,
        state: Attribute<State>,
        list: OptionalAttribute<any ViewList>,
        elements: _ViewList_SubgraphElements,
        elementIndex: Int,
        id: _ViewList_ID,
        reuseIdentifier: Int = 0,
        section: LazyLayoutCacheSection = LazyLayoutCacheSection(),
        transition: AGAttribute? = nil,
        transitionType: Any.Type? = nil,
        zIndex: Double = 0
    ) {
        self.cache = cache
        self.subgraph = subgraph
        self.outputs = outputs
        self._state = state
        self._list = list
        self.elements = elements
        self.elementIndex = elementIndex
        self.releaseElements = nil
        self.indirectMap = nil
        self.transition = transition
        self.transitionType = transitionType
        self.id = id
        self.reuseIdentifier = reuseIdentifier
        self.section = section
        self.zIndex = zIndex
        self.insertionTransactionSeed = 0
        self.removalTransactionSeed = 0
        self.animationCount = 0
        self.usedSeed = 0
        self.placementSeed = 0
        self.commitSeed = 0
        self.prefetchSeed = 0
        self.prefetchPhase = .notPrefetching
        self.displayIndex = nil
        self.removedSeed = 0
        self.placement = nil
        self.pendingPlacement = nil
        self.releaseSecondaryElements = nil
        self.willEnableTransitions = false
        self.willAnimateRemoval = false
        self.parentingPhase = nil
        self.hasWarned = false
    }

    func animationWasAdded() {
        animationCount &+= 1
    }

    func animationWasRemoved() {
        guard animationCount > 0 else { return }
        animationCount &-= 1
        guard animationCount == 0,
              let cache else {
            return
        }
        cache.viewGraph?.continueTransaction(
            SingleItemPhaseMutation(cache: cache, item: self)
        )
    }

    func beginPrefetching(at proposal: ProposedViewSize) {
        guard displayIndex == nil else { return }
        guard let cache else {
            fatalError("LazyLayoutCacheItem.beginPrefetching requires a cache.")
        }
        placement = _Placement(proposedSize: proposal.replacingUnspecifiedDimensions())
        prefetchSeed = cache.commitSeed
        prefetchPhase = cache.supportsViewHierarchyPrefetching ? .prefetching : .notPrefetching
    }
}

struct LazyLayoutCacheChildren {
    struct WeakChild {
        weak var value: LazyLayoutViewCache?
    }

    var seed: Int
    var children: [WeakChild]

    init(seed: Int = 0, children: [WeakChild] = []) {
        self.seed = seed
        self.children = children
    }
}

final class LazyLayoutViewCache {
    struct LeastRecentlyUsedItems {
        private(set) var generationSeed: UInt32 = 0
        private var sortedItems: [LazyLayoutCacheItem]?

        mutating func invalidate() {
            sortedItems = nil
        }

        mutating func updatedItems(_ items: [LazyLayoutCacheItem]) -> [LazyLayoutCacheItem] {
            if let sortedItems {
                return sortedItems
            }
            generationSeed &+= 1
            let sorted = items.sorted {
                if $0.usedSeed == $1.usedSeed {
                    return $0.reuseIdentifier < $1.reuseIdentifier
                }
                return $0.usedSeed < $1.usedSeed
            }
            sortedItems = sorted
            return sorted
        }
    }

    weak var viewGraph: GraphHost?
    var parentSubgraph: AGSubgraph
    var inputs: _ViewInputs
    var outputs: _ViewOutputs
    var _list: Attribute<any ViewList>
    var _layoutDirection: Attribute<LayoutDirection>
    var _nearestScrollableAxes: Attribute<Axis.Set>
    var _placedSubviews: Attribute<[_LazyLayout_PlacedSubview]>
    var _prefetchSignal: Attribute<Void>
    var _weakPrefetchSignal: WeakAttribute<Void>
    var _scrollPosition: OptionalAttribute<Binding<ScrollPosition>>
    var _accessibilityEnabled: Attribute<Bool>
    var items: [_ViewList_ID.Canonical: LazyLayoutCacheItem]
    var lru: LeastRecentlyUsedItems
    var commitSeed: UInt32
    var placementSeed: UInt32
    var outerPlacedRect: CGRect
    var containingSize: CGSize
    var placedIndices: (min: Int, max: Int)
    var averagePlacedCount: (value: Double, count: Int)
    var allowedPrefetchEdges: Edge.Set
    var maxSize: CGSize
    var invalidationSeed: UInt32
    var invalidationTTL: UInt8
    var hasSections: Bool
    var hasDepth: Bool
    var isFirstCommit: Bool
    var maxDisplayListSubviews: Int?
    weak var parentCache: LazyLayoutViewCache?
    var childCaches: [_ViewList_ID.Canonical: LazyLayoutCacheChildren]
    var childCacheSeeds: [_ViewList_ID.Canonical: Int]
    var nextChildCacheSeed: Int

    init(
        viewGraph: GraphHost?,
        parentSubgraph: AGSubgraph,
        inputs: _ViewInputs,
        outputs: _ViewOutputs,
        list: Attribute<any ViewList>,
        layoutDirection: Attribute<LayoutDirection>,
        nearestScrollableAxes: Attribute<Axis.Set>,
        placedSubviews: Attribute<[_LazyLayout_PlacedSubview]>,
        prefetchSignal: Attribute<Void>,
        scrollPosition: OptionalAttribute<Binding<ScrollPosition>>,
        accessibilityEnabled: Attribute<Bool>
    ) {
        self.viewGraph = viewGraph
        self.parentSubgraph = parentSubgraph
        self.inputs = inputs
        self.outputs = outputs
        self._list = list
        self._layoutDirection = layoutDirection
        self._nearestScrollableAxes = nearestScrollableAxes
        self._placedSubviews = placedSubviews
        self._prefetchSignal = prefetchSignal
        self._weakPrefetchSignal = prefetchSignal.asWeak()
        self._scrollPosition = scrollPosition
        self._accessibilityEnabled = accessibilityEnabled
        self.items = [:]
        self.lru = LeastRecentlyUsedItems()
        self.commitSeed = 0
        self.placementSeed = 0
        self.outerPlacedRect = .null
        self.containingSize = .zero
        self.placedIndices = (0, -1)
        self.averagePlacedCount = (0, 0)
        self.allowedPrefetchEdges = []
        self.maxSize = .zero
        self.invalidationSeed = 0
        self.invalidationTTL = 0
        self.hasSections = false
        self.hasDepth = false
        self.isFirstCommit = true
        self.maxDisplayListSubviews = nil
        self.parentCache = nil
        self.childCaches = [:]
        self.childCacheSeeds = [:]
        self.nextChildCacheSeed = 0
    }

    func item(for id: _ViewList_ID.Canonical) -> LazyLayoutCacheItem? {
        items[id]
    }

    func item(for subgraph: AGSubgraph) -> LazyLayoutCacheItem? {
        items.values.first { $0.subgraph === subgraph }
    }

    func item(data: _LazyLayout_Subview.Data) -> LazyLayoutCacheItem {
        let id = data.id.canonicalID
        let transition = anyTransition(data: data)
        let transitionType = transition?._transitionType

        if let item = items[id] {
            refresh(item, data: data, transitionType: transitionType)
            return item
        }

        if let item = reusedItem(data: data, anyTransition: transition) {
            return item
        }

        return makeNewItem(data: data, anyTransition: transition)
    }

    func addItem(_ item: LazyLayoutCacheItem, reset: Bool = false) {
        item.cache = self
        if reset {
            item.usedSeed = 0
            item.placementSeed = 0
            item.commitSeed = 0
            item.prefetchSeed = 0
            item.prefetchPhase = .notPrefetching
        }
        items[item.id.canonicalID] = item
        lru.invalidate()
    }

    func updateItemPhases() {
        for item in items.values {
            updateItemPhase(item)
        }
    }

    func updateItemPhase(_ item: LazyLayoutCacheItem) {
        guard AGSubgraphIsValid(item.subgraph) else { return }
        var state = item._state.value
        if item.commitSeed == placementSeed {
            guard state.phase != .identity else { return }
            state.phase = .identity
            item._state.setValue(state, transaction: Transaction.current)
            return
        }
        guard state.phase != .willAppear else { return }
        if state.phase == .identity,
           item.displayIndex != nil {
            state.phase = .didDisappear
            state.enableTransitions = item.willEnableTransitions
            item._state.setValue(state, transaction: Transaction.current)
            item.willEnableTransitions = false
            return
        }
        guard item.animationCount == 0 else { return }
        item.displayIndex = nil
        item.placement = nil
        item.prefetchPhase = supportsViewHierarchyPrefetching ? .pendingRemoval : .notPrefetching
        state.isRemoved = true
        item._state.setValue(state, transaction: Transaction.current)
    }

    func commitPlacedSubviews(_ placedSubviews: [_LazyLayout_PlacedSubview]) {
        placementSeed &+= 1
        for placedSubview in placedSubviews {
            let item = placedSubview.item
            item.placementSeed = placementSeed
            item.commitSeed = placementSeed
            item.placement = placedSubview.placement
            item.pendingPlacement = nil
        }
    }

    func reusedItem(
        for id: _ViewList_ID.Canonical,
        reuseIdentifier: Int,
        transitionType: Any.Type?
    ) -> LazyLayoutCacheItem? {
        let candidates = lru.updatedItems(Array(items.values))
        return candidates.first { item in
            item.id.canonicalID != id &&
                item.reuseIdentifier == reuseIdentifier &&
                item.displayIndex == nil &&
                item.prefetchPhase != .pendingRemoval &&
                item.transitionType == transitionType
        }
    }

    func reusedItem(
        data: _LazyLayout_Subview.Data,
        anyTransition transition: AnyTransition?
    ) -> LazyLayoutCacheItem? {
        let id = data.id.canonicalID
        let transitionType = transition?._transitionType
        let reuseIdentifier = data.id.reuseIdentifier
        guard let item = reusedItem(
            for: id,
            reuseIdentifier: reuseIdentifier,
            transitionType: transitionType
        ) else {
            return nil
        }
        let oldID = item.id.canonicalID
        refresh(item, data: data, transitionType: transitionType)
        if oldID != item.id.canonicalID {
            items.removeValue(forKey: oldID)
        }
        addItem(item, reset: true)
        return item
    }

    func prefetchOutputs() -> [_ViewOutputs] {
        items.values
            .filter { $0.prefetchSeed == commitSeed }
            .map(\.outputs)
    }

    func resetPrefetchPhases() {
        guard supportsViewHierarchyPrefetching else { return }
        for item in items.values {
            item.prefetchPhase = .notPrefetching
            item.prefetchSeed = 0
        }
        signalPrefetch()
    }

    func updatePrefetchPhases() {
        guard supportsViewHierarchyPrefetching else { return }
        for item in items.values where item.prefetchPhase == .pendingDisplay {
            item.beginPrefetching(at: .unspecified)
        }
        signalPrefetch()
    }

    func signalPrefetch() {
        Update.enqueueAction {}
    }

    var supportsViewHierarchyPrefetching: Bool {
        false
    }

    private func anyTransition(data: _LazyLayout_Subview.Data) -> AnyTransition? {
        guard data.traits[CanTransitionTraitKey.self] else { return nil }
        return data.traits[TransitionTraitKey.self]
    }

    private func makeNewItem(
        data: _LazyLayout_Subview.Data,
        anyTransition transition: AnyTransition?
    ) -> LazyLayoutCacheItem {
        guard let graph = _AGGraph.current else {
            fatalError("LazyLayoutViewCache.item(data:) requires an active AttributeGraph")
        }
        let state = graph.makeInput(value: LazyLayoutCacheItem.State())
        let item = LazyLayoutCacheItem(
            cache: self,
            subgraph: AGSubgraph(),
            outputs: _ViewOutputs(),
            state: state,
            list: data.list.map(OptionalAttribute.init) ?? OptionalAttribute<any ViewList>(),
            elements: data.elements,
            elementIndex: 0,
            id: data.id,
            reuseIdentifier: data.id.reuseIdentifier,
            section: data.section,
            transition: nil,
            transitionType: transition?._transitionType,
            zIndex: data.traits[ZIndexTraitKey.self]
        )
        addItem(item, reset: false)
        return item
    }

    private func refresh(
        _ item: LazyLayoutCacheItem,
        data: _LazyLayout_Subview.Data,
        transitionType: Any.Type?
    ) {
        item.elements = data.elements
        item._list = data.list.map(OptionalAttribute.init) ?? OptionalAttribute<any ViewList>()
        item.id = data.id
        item.reuseIdentifier = data.id.reuseIdentifier
        item.section = data.section
        item.transition = nil
        item.transitionType = transitionType
        item.zIndex = data.traits[ZIndexTraitKey.self]
    }
}

struct _LazyLayout_PlacedSubview {
    var item: LazyLayoutCacheItem
    var placement: _Placement
    var index: Int
}

struct LazyTransaction: StatefulRule, RemovableAttribute {
    typealias Value = Transaction

    var _transaction: Attribute<Transaction>
    var _state: Attribute<LazyLayoutCacheItem.State>
    var item: LazyLayoutCacheItem?
    var lastPhase: TransitionPhase?
    var lastResetDelta: UInt32
    var isRemoved: Bool

    init(
        transaction: Attribute<Transaction>,
        state: Attribute<LazyLayoutCacheItem.State>,
        item: LazyLayoutCacheItem?
    ) {
        self._transaction = transaction
        self._state = state
        self.item = item
        self.lastPhase = nil
        self.lastResetDelta = 0
        self.isRemoved = false
    }

    mutating func updateValue() {
        var transaction = _transaction.value
        let state = _state.value
        if state.enableTransitions,
           !transaction.disablesAnimations,
           transaction.animation != nil,
           let item {
            transaction.addAnimationListener(LazyLayoutCacheItemAnimationListener(item: item))
        }
        lastPhase = state.phase
        lastResetDelta = state.resetDelta
        isRemoved = state.isRemoved
        _AGGraph.setStatefulOutput(transaction)
    }
}

private final class LazyLayoutCacheItemAnimationListener: AnimationListener, @unchecked Sendable {
    weak var item: LazyLayoutCacheItem?

    init(item: LazyLayoutCacheItem) {
        self.item = item
    }

    override func animationWasAdded() {
        item?.animationWasAdded()
    }

    override func animationWasRemoved() -> [() -> Void] {
        item?.animationWasRemoved()
        return []
    }
}

protocol LazyLayout: Layout, _VariadicView_UnaryViewRoot {
    var pinnedViews: PinnedScrollableViews { get }
}

extension LazyLayout {
    static func _makeView(
        root: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: (_Graph, _ViewInputs) -> _ViewListOutputs
    ) -> _ViewOutputs {
        var lazyInputs = inputs
        lazyInputs.base[DynamicContainerWillRemoveBeforeInvalidation.self] = true
        return Self._makeLayoutView(root: root, inputs: lazyInputs, body: body)
    }
}

protocol LazyStack: LazyLayout {
}

protocol LazyHVStack: LazyStack {
    associatedtype Base: HVStack

    var base: Base { get }
}

struct LazyHStackLayout: LazyHVStack {
    var base: _HStackLayout
    var pinnedViews: PinnedScrollableViews

    typealias Body = Never
    typealias AnimatableData = EmptyAnimatableData
    typealias Cache = _HStackLayout.Cache

    init(base: _HStackLayout, pinnedViews: PinnedScrollableViews) {
        self.base = base
        self.pinnedViews = pinnedViews
    }

    static var layoutProperties: LayoutProperties {
        _HStackLayout.layoutProperties
    }

    func makeCache(subviews: Subviews) -> Cache {
        base.makeCache(subviews: subviews)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        base.updateCache(&cache, subviews: subviews)
    }

    func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        base.spacing(subviews: subviews, cache: &cache)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        base.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        base.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }

    func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGFloat? {
        base.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGFloat? {
        base.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }
}

struct LazyVStackLayout: LazyHVStack {
    var base: _VStackLayout
    var pinnedViews: PinnedScrollableViews

    typealias Body = Never
    typealias AnimatableData = EmptyAnimatableData
    typealias Cache = _VStackLayout.Cache

    init(base: _VStackLayout, pinnedViews: PinnedScrollableViews) {
        self.base = base
        self.pinnedViews = pinnedViews
    }

    static var layoutProperties: LayoutProperties {
        _VStackLayout.layoutProperties
    }

    func makeCache(subviews: Subviews) -> Cache {
        base.makeCache(subviews: subviews)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        base.updateCache(&cache, subviews: subviews)
    }

    func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        base.spacing(subviews: subviews, cache: &cache)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        base.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        base.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }

    func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGFloat? {
        base.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGFloat? {
        base.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }
}
