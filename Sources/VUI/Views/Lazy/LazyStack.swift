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

protocol LazyLayoutNamespace {
}

typealias _ProposedSize = ProposedViewSize

@dynamicMemberLookup
struct SizeAndSpacingContext {
    var context: AnyRuleContext
    var owner: AGAttribute?
    var environment: Attribute<EnvironmentValues>

    init(
        context: AnyRuleContext,
        owner: AGAttribute? = nil,
        environment: Attribute<EnvironmentValues>
    ) {
        self.context = context
        self.owner = owner
        self.environment = environment
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<EnvironmentValues, Value>) -> Value {
        environment.value[keyPath: keyPath]
    }

    mutating func update(_ context: AnyRuleContext) {
        self.context = context
    }
}

struct _LazyLayout_Properties: LazyLayoutNamespace {
    var axes: Axis.Set
    var multipleViewAxes: Axis.Set

    init(axes: Axis.Set = [], multipleViewAxes: Axis.Set = []) {
        self.axes = axes
        self.multipleViewAxes = multipleViewAxes
    }
}

enum _LazyLayout_PrefetchResult: UInt8, Hashable {
    case none
    case some
    case all

    @discardableResult
    mutating func advanceToSome() -> Bool {
        let hadWork = self != .none
        self = hadWork ? .some : .all
        return hadWork
    }
}

struct ScrollPrefetchState: Equatable, PropertyKey {
    typealias Value = OptionalAttribute<ScrollPrefetchState>

    static var defaultValue: OptionalAttribute<ScrollPrefetchState> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ a: OptionalAttribute<ScrollPrefetchState>,
        _ b: OptionalAttribute<ScrollPrefetchState>
    ) -> Bool {
        a.base.identifier == b.base.identifier
    }

    var id: UniqueID
    var deadline: UInt64
    var edges: Edge.Set

    init(deadline: UInt64 = 0) {
        self.id = UniqueID()
        self.deadline = deadline
        self.edges = []
    }

    func commit(to attribute: WeakAttribute<ScrollPrefetchState>) {
        guard let graph = _AGGraph.current,
              attribute.isValid(in: graph) else {
            return
        }

        let host = GraphHost.currentHost
        var transaction = Transaction.current
        transaction.fromScrollView = true
        host.asyncTransaction(
            transaction,
            id: Transaction.id,
            mutation: AssignmentGraphMutation(attribute: attribute, value: self),
            style: .deferred,
            mayDeferUpdate: false
        )
        Update.enqueueAction(reason: 0x09) { [weak host] in
            host?.flushTransactions()
        }
    }
}

enum LazyPrefetchOperation {
    case display(LazyLayoutCacheItem)
    case removal
}

struct LazySubviewPrefetcher<LayoutType: LazyLayout>: StatefulRule {
    typealias Value = Void

    var _layout: Attribute<LayoutType>
    var _size: Attribute<ViewSize>
    var _position: Attribute<CGPoint>
    var _transform: Attribute<ViewTransform>
    var _environment: Attribute<EnvironmentValues>
    var _prefetchState: Attribute<ScrollPrefetchState>
    var _cache: Attribute<LazyLayoutViewCache>
    var _containerSize: OptionalAttribute<ViewSize>
    var operations: [LazyPrefetchOperation]
    var lastStateID: UniqueID?
    var lastEdges: Edge.Set
    var didScheduleContinuation: Bool

    init(
        layout: Attribute<LayoutType>,
        size: Attribute<ViewSize>,
        position: Attribute<CGPoint>,
        transform: Attribute<ViewTransform>,
        environment: Attribute<EnvironmentValues>,
        prefetchState: Attribute<ScrollPrefetchState>,
        cache: Attribute<LazyLayoutViewCache>,
        containerSize: OptionalAttribute<ViewSize>
    ) {
        self._layout = layout
        self._size = size
        self._position = position
        self._transform = transform
        self._environment = environment
        self._prefetchState = prefetchState
        self._cache = cache
        self._containerSize = containerSize
        self.operations = []
        self.lastStateID = nil
        self.lastEdges = []
        self.didScheduleContinuation = false
    }

    mutating func updateValue() {
        _ = updateHostState()
        _AGGraph.setStatefulOutput(())
    }

    @discardableResult
    mutating func updateHostState() -> _LazyLayout_PrefetchResult {
        let info = _prefetchState.value
        let cache = _cache.value

        if let lastStateID,
           lastStateID != info.id || lastEdges != info.edges {
            cache.resetPrefetchPhases()
        }
        lastStateID = info.id
        lastEdges = info.edges

        guard !cache.allowedPrefetchEdges.intersection(info.edges).isEmpty else {
            didScheduleContinuation = false
            return .none
        }
        return update(info: info, owner: _prefetchState.identifier)
    }

    @discardableResult
    mutating func update(
        info: ScrollPrefetchState,
        owner: AGAttribute
    ) -> _LazyLayout_PrefetchResult {
        didScheduleContinuation = false
        var result = makeLayoutPrefetchResult(info: info, offset: 0, owner: owner)
        if result == .some {
            didScheduleContinuation = true
            return result
        }

        let cache = _cache.value
        while let operation = operations.popLast() {
            let next: _LazyLayout_PrefetchResult
            switch operation {
            case .display(let item):
                _ = cache.prefetchOutputs()
                next = cache.advancePrefetchPhaseForDisplay(item: item)
            case .removal:
                next = cache.advancePrefetchPhaseForRemoval()
            }
            if mergePrefetchResult(next, into: &result) {
                return result
            }
        }
        return result
    }

    @discardableResult
    mutating func makeLayoutPrefetchResult(
        info: ScrollPrefetchState,
        offset: Int,
        owner: AGAttribute
    ) -> _LazyLayout_PrefetchResult {
        let axes = LayoutType._lazyLayoutProperties.axes
        if axes.contains(.horizontal),
           !info.edges.intersection(.horizontal).isEmpty {
            let result = makeLayoutPrefetchResult(
                info: info,
                offset: offset,
                axis: .horizontal,
                owner: owner
            )
            if result != .none {
                return result
            }
        }
        if axes.contains(.vertical),
           !info.edges.intersection(.vertical).isEmpty {
            return makeLayoutPrefetchResult(
                info: info,
                offset: offset,
                axis: .vertical,
                owner: owner
            )
        }
        return .none
    }

    @discardableResult
    mutating func makeLayoutPrefetchResult(
        info: ScrollPrefetchState,
        offset: Int,
        axis: Axis,
        owner: AGAttribute
    ) -> _LazyLayout_PrefetchResult {
        _ = info
        _ = offset
        _ = axis
        _ = owner
        // Viewport candidate materialization is a separate lazy-host slice.
        return .none
    }

    private mutating func mergePrefetchResult(
        _ next: _LazyLayout_PrefetchResult,
        into result: inout _LazyLayout_PrefetchResult
    ) -> Bool {
        switch next {
        case .none:
            return false
        case .all:
            result = .all
            return false
        case .some:
            result = .some
            didScheduleContinuation = true
            return true
        }
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

struct AccessibilitySectionContext: Equatable {
    var id: UInt32
    var isHeader: Bool
    var isFooter: Bool

    init(id: UInt32 = 0, isHeader: Bool = false, isFooter: Bool = false) {
        self.id = id
        self.isHeader = isHeader
        self.isFooter = isFooter
    }
}

@dynamicMemberLookup
struct _LazyLayout_SizeAndSpacingContext: LazyLayoutNamespace {
    var baseContext: SizeAndSpacingContext
    var _containerSize: OptionalAttribute<ViewSize>

    init(
        ruleContext: AnyRuleContext,
        owner: AGAttribute? = nil,
        environment: Attribute<EnvironmentValues>,
        containerSize: OptionalAttribute<ViewSize> = OptionalAttribute()
    ) {
        self.baseContext = SizeAndSpacingContext(
            context: ruleContext,
            owner: owner,
            environment: environment
        )
        self._containerSize = containerSize
    }

    var ruleContext: AnyRuleContext {
        baseContext.context
    }

    var containerSize: CGSize {
        _containerSize.attribute?.value.value ?? .zero
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<EnvironmentValues, Value>) -> Value {
        baseContext[dynamicMember: keyPath]
    }

    mutating func update(_ context: AnyRuleContext) {
        baseContext.update(context)
    }
}

struct _LazyLayout_PlacementContext: LazyLayoutNamespace {
    struct Geometry: Equatable {
        var transform: ViewTransform
        var layoutDirection: LayoutDirection
        var isAccessibilityEnabled: Bool

        init(
            transform: ViewTransform = ViewTransform(),
            layoutDirection: LayoutDirection = .leftToRight,
            isAccessibilityEnabled: Bool = false
        ) {
            self.transform = transform
            self.layoutDirection = layoutDirection
            self.isAccessibilityEnabled = isAccessibilityEnabled
        }
    }

    var base: _LazyLayout_SizeAndSpacingContext
    var position: CGPoint
    var size: CGSize
    var pinnedViews: PinnedScrollableViews
    var geometry: Geometry

    init(
        base: _LazyLayout_SizeAndSpacingContext,
        position: CGPoint = .zero,
        size: ViewSize = .zero,
        transform: ViewTransform = ViewTransform(),
        layoutDirection: LayoutDirection = .leftToRight,
        pinnedViews: PinnedScrollableViews = [],
        isAccessibilityEnabled: Bool = false
    ) {
        self.base = base
        self.position = position
        self.size = size.value
        self.pinnedViews = pinnedViews
        self.geometry = Geometry(
            transform: transform,
            layoutDirection: layoutDirection,
            isAccessibilityEnabled: isAccessibilityEnabled
        )
    }

    var transform: ViewTransform {
        geometry.transform
    }

    var layoutDirection: LayoutDirection {
        geometry.layoutDirection
    }

    var isAccessibilityEnabled: Bool {
        geometry.isAccessibilityEnabled
    }

    var unadjustedVisibleRect: CGRect {
        CGRect(origin: position, size: size)
    }

    var nearestVisibleRect: CGRect {
        unadjustedVisibleRect
    }

    var containingVisibleRect: CGRect {
        unadjustedVisibleRect
    }

    var clampedVisibleRect: CGRect {
        unadjustedVisibleRect
    }

    var allowsTranslations: Bool {
        true
    }
}

struct _LazyLayout_EstimatedPlacementContext: LazyLayoutNamespace {
    var base: _LazyLayout_PlacementContext

    init(base: _LazyLayout_PlacementContext) {
        self.base = base
    }
}

struct _LazyLayout_Subviews: LazyLayoutNamespace {
    enum Node {
        case subviews(_LazyLayout_Subviews)
        case section(_LazyLayout_Section)
    }

    var cache: LazyLayoutViewCache
    var context: AnyRuleContext
    var node: _ViewList_Node
    var transform: _ViewList_SublistTransform
    var section: LazyLayoutCacheSection
    var baseIndex: Int

    init(
        cache: LazyLayoutViewCache,
        context: AnyRuleContext,
        node: _ViewList_Node,
        transform: _ViewList_SublistTransform,
        section: LazyLayoutCacheSection = LazyLayoutCacheSection(),
        baseIndex: Int = 0
    ) {
        self.cache = cache
        self.context = context
        self.node = node
        self.transform = transform
        self.section = section
        self.baseIndex = baseIndex
    }
}

struct _LazyLayout_Section: LazyLayoutNamespace {
    struct ID: Hashable {
        var id: UInt32
    }

    var base: _ViewList_Section
    var transform: _ViewList_SublistTransform
    var cache: LazyLayoutViewCache
    var context: AnyRuleContext
    var baseIndex: Int

    init(
        base: _ViewList_Section,
        transform: _ViewList_SublistTransform,
        cache: LazyLayoutViewCache,
        context: AnyRuleContext,
        baseIndex: Int = 0
    ) {
        self.base = base
        self.transform = transform
        self.cache = cache
        self.context = context
        self.baseIndex = baseIndex
    }
}

struct _LazyLayout_Subview: LazyLayoutNamespace {
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

    func proposeSize(_ proposal: ProposedViewSize) -> _LazyLayout_ProposedSubview {
        let item = cache.item(data: data)
        item.placement = _Placement(
            proposedSize: proposal.replacingUnspecifiedDimensions()
        )
        return _LazyLayout_ProposedSubview(
            item: item,
            proposal: proposal,
            index: index
        )
    }

    func beginPrefetching(at proposal: ProposedViewSize) {
        cache.item(data: data).beginPrefetching(at: proposal)
    }

    func lengthAndSpacing(
        size: ProposedViewSize,
        axis: Axis,
        predecessor: _LazyLayout_Subview?,
        uniformSpacing: CGFloat?
    ) -> (length: CGFloat, spacing: CGFloat) {
        let item = cache.item(data: data)
        let layoutComputer = item.outputs._layoutComputer.attribute?.value ?? .defaultValue
        let length = layoutComputer.lengthThatFits(size, in: axis)
        guard let predecessor else {
            return (length, 0)
        }
        if let uniformSpacing {
            return (length, uniformSpacing)
        }
        let predecessorItem = predecessor.cache.item(data: predecessor.data)
        let predecessorLayoutComputer =
            predecessorItem.outputs._layoutComputer.attribute?.value ?? .defaultValue
        return (
            length,
            predecessorLayoutComputer.spacing.distance(to: layoutComputer.spacing, along: axis)
        )
    }

    func place(at placement: _Placement) -> _LazyLayout_PlacedSubview {
        let item = cache.item(data: data)
        item.placement = placement
        return _LazyLayout_PlacedSubview(
            item: item,
            placement: placement,
            index: index
        )
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

class LazyLayoutViewCache: LazyLayoutNamespace {
    struct LeastRecentlyUsedItems {
        private(set) var usedSeed: UInt32 = 0
        var maxIdle: Int = 0
        var lastTransactionID = TransactionID()
        var transactionSeed: UInt32 = 0
        private(set) var items: [LazyLayoutCacheItem]?

        mutating func invalidate() {
            items = nil
        }

        mutating func updatedItems(_ items: [LazyLayoutCacheItem]) -> [LazyLayoutCacheItem] {
            if let cachedItems = self.items {
                return cachedItems
            }
            usedSeed &+= 1
            let sorted = items.sorted {
                if $0.usedSeed == $1.usedSeed {
                    return $0.reuseIdentifier < $1.reuseIdentifier
                }
                return $0.usedSeed < $1.usedSeed
            }
            self.items = sorted
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
        item.insertionTransactionSeed = lru.transactionSeed
        let transaction = Transaction.current
        var state = item._state.value
        if reset {
            state.resetDelta &+= 1
        }
        if transaction.fromScrollView {
            state.phase = .identity
            state.enableTransitions = false
        } else {
            state.phase = .willAppear
            state.enableTransitions = item._list.attribute?.value.edit(
                forID: item.id,
                since: lru.lastTransactionID
            ) == .inserted
        }
        state.isRemoved = false
        item._state.setValue(state, transaction: transaction)
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
            isReusableCandidate(
                item,
                for: id,
                reuseIdentifier: reuseIdentifier,
                transitionType: transitionType
            ) &&
            item.prefetchPhase != .pendingRemoval
        }
    }

    func reusedItem(
        data: _LazyLayout_Subview.Data,
        anyTransition transition: AnyTransition?
    ) -> LazyLayoutCacheItem? {
        let id = data.id.canonicalID
        let transitionType = transition?._transitionType
        let reuseIdentifier = data.id.reuseIdentifier
        let candidates = lru.updatedItems(Array(items.values))
        guard let item = candidates.first(where: {
            isReusableCandidate(
                $0,
                for: id,
                reuseIdentifier: reuseIdentifier,
                transitionType: transitionType
            )
        }) else {
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

    private func isReusableCandidate(
        _ item: LazyLayoutCacheItem,
        for id: _ViewList_ID.Canonical,
        reuseIdentifier: Int,
        transitionType: Any.Type?
    ) -> Bool {
        guard item.id.canonicalID != id,
              item.reuseIdentifier == reuseIdentifier else {
            return false
        }
        let insertionAge = Int32(bitPattern: lru.transactionSeed &- item.insertionTransactionSeed)
        guard insertionAge >= 1,
              item.placementSeed != placementSeed,
              item.displayIndex == nil else {
            return false
        }
        return item.transitionType == transitionType
    }

    func prefetchOutputs() -> [_ViewOutputs] {
        items.values
            .filter { $0.prefetchSeed == commitSeed }
            .compactMap { prefetchOutput(for: $0.outputs) }
    }

    func resetPrefetchPhases() {
        guard supportsViewHierarchyPrefetching else { return }
        for item in items.values {
            item.prefetchPhase = .notPrefetching
            item.prefetchSeed = 0
            resetMaxDisplayListSubviews(item: item)
        }
        signalPrefetch()
    }

    func updatePrefetchPhases() {
        guard supportsViewHierarchyPrefetching else { return }
        var didClearItemPhase = false
        for item in items.values {
            guard item.displayIndex != nil else {
                let removalAge = Int32(bitPattern: lru.transactionSeed &- item.removalTransactionSeed)
                if item.prefetchPhase == .pendingRemoval,
                   lru.maxIdle < Int(removalAge) {
                    item.prefetchPhase = .notPrefetching
                    didClearItemPhase = true
                }
                continue
            }
            if item.prefetchPhase == .notPrefetching {
                resetMaxDisplayListSubviews(item: item)
                continue
            }
            maxDisplayListSubviews = nil
            item.prefetchPhase = .notPrefetching
            resetMaxDisplayListSubviews(item: item)
            didClearItemPhase = true
        }
        if didClearItemPhase {
            signalPrefetch()
        }
    }

    func advancePrefetchPhaseForDisplay(item: LazyLayoutCacheItem) -> _LazyLayout_PrefetchResult {
        guard supportsViewHierarchyPrefetching else { return .none }
        switch item.prefetchPhase {
        case .pendingDisplay:
            guard hasChildPrefetchPhaseWork(item: item) else { return .none }
            signalPrefetch()
            return advanceChildPrefetchPhase(item: item) ? .some : .all
        case .prefetching:
            item.prefetchPhase = .pendingDisplay
            signalPrefetch()
            return setupChildPrefetchPhase(item: item) ? .some : .all
        default:
            return .none
        }
    }

    func advancePrefetchPhaseForRemoval() -> _LazyLayout_PrefetchResult {
        guard supportsViewHierarchyPrefetching else { return .none }
        var didCollect = false
        for item in items.values where item.prefetchPhase == .pendingRemoval {
            item.prefetchPhase = .notPrefetching
            didCollect = true
        }
        if didCollect {
            signalPrefetch()
        }
        return .all
    }

    func resetMaxDisplayListSubviews(item: LazyLayoutCacheItem) {
        for childCache in liveChildCaches(for: item) {
            guard childCache.maxDisplayListSubviews != nil else { continue }
            childCache.maxDisplayListSubviews = nil
            childCache.signalPrefetch()
        }
    }

    func hasChildPrefetchPhaseWork(item: LazyLayoutCacheItem) -> Bool {
        guard item.prefetchSeed == commitSeed else { return false }
        for childCache in liveChildCaches(for: item) {
            guard let maxDisplayListSubviews = childCache.maxDisplayListSubviews else { continue }
            let lower = childCache.placedIndices.min
            guard lower >= 0 else { continue }
            let upper = childCache.placedIndices.max
            guard upper >= 1 else { continue }
            let placedDelta = upper &- lower
            if placedDelta > 0 {
                if placedDelta >= maxDisplayListSubviews {
                    return true
                }
            } else if maxDisplayListSubviews < 1 {
                return true
            }
        }
        return false
    }

    func setupChildPrefetchPhase(item: LazyLayoutCacheItem) -> Bool {
        guard item.prefetchSeed == commitSeed else { return false }
        var scheduled = false
        for childCache in liveChildCaches(for: item) {
            guard childCache.maxDisplayListSubviews == nil else { continue }
            childCache.maxDisplayListSubviews = 0
            childCache.signalPrefetch()
            scheduled = true
        }
        return scheduled
    }

    func advanceChildPrefetchPhase(item: LazyLayoutCacheItem) -> Bool {
        guard item.prefetchSeed == commitSeed else { return false }
        var scheduled = false
        for childCache in liveChildCaches(for: item) {
            guard let maxDisplayListSubviews = childCache.maxDisplayListSubviews else { continue }
            childCache.maxDisplayListSubviews = maxDisplayListSubviews &+ 1
            childCache.signalPrefetch()
            scheduled = true
        }
        return scheduled
    }

    func signalPrefetch() {
        let signal = _weakPrefetchSignal.raw
        Update.enqueueAction { [weak viewGraph] in
            guard let viewGraph else { return }
            viewGraph.data.withCurrent {
                let graph = viewGraph.data.graph
                guard signal.isValid(in: graph) else { return }
                graph.invalidateAttribute(signal.toStrong())
            }
        }
    }

    var supportsPrefetching: Bool {
        false
    }

    var supportsViewHierarchyPrefetching: Bool {
        guard supportsPrefetching else { return false }
        guard _SemanticFeature<Semantics_v7>.isEnabled else { return false }
        return !inputs[UsingGraphicsRenderer.self]
    }

    private func prefetchOutput(for outputs: _ViewOutputs) -> _ViewOutputs? {
        let displayNodes = outputs.preferences.values(for: DisplayList.Key.self)
        guard !displayNodes.isEmpty else { return nil }
        var preferences = PreferencesOutputs()
        for node in displayNodes {
            preferences.append(DisplayList.Key.self, node: node)
        }
        return _ViewOutputs(preferences: preferences)
    }

    private func liveChildCaches(for item: LazyLayoutCacheItem) -> [LazyLayoutViewCache] {
        guard let children = childCaches[item.id.canonicalID] else { return [] }
        return children.children.compactMap(\.value)
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

        let subgraph = AGSubgraph()
        let release = data.elements.retain()
        var childInputs = inputs
        childInputs.copyCaches()
        let materialized = AGSubgraph.$current.withValue(subgraph) {
            let state = graph.makeInput(value: LazyLayoutCacheItem.State())
            let outputs = data.elements.makeOneElement(at: 0, inputs: childInputs) {
                elementInputs,
                makeView in
                makeView(elementInputs)
            } ?? _ViewOutputs()
            return (state: state, outputs: outputs)
        }

        let item = LazyLayoutCacheItem(
            cache: self,
            subgraph: subgraph,
            outputs: materialized.outputs,
            state: materialized.state,
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
        item.releaseElements = release
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

final class _LazyLayoutViewCache<LayoutType: LazyLayout>: LazyLayoutViewCache {
    var _layout: Attribute<LayoutType>
    var cacheState: Attribute<LayoutType.Cache>

    init(
        layout: Attribute<LayoutType>,
        cacheState: Attribute<LayoutType.Cache>,
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
        self._layout = layout
        self.cacheState = cacheState
        super.init(
            viewGraph: viewGraph,
            parentSubgraph: parentSubgraph,
            inputs: inputs,
            outputs: outputs,
            list: list,
            layoutDirection: layoutDirection,
            nearestScrollableAxes: nearestScrollableAxes,
            placedSubviews: placedSubviews,
            prefetchSignal: prefetchSignal,
            scrollPosition: scrollPosition,
            accessibilityEnabled: accessibilityEnabled
        )
    }

    override var supportsPrefetching: Bool {
        guard AGSubgraphIsValid(parentSubgraph) else { return false }
        return !LayoutType._lazyLayoutProperties.axes.intersection(_nearestScrollableAxes.value).isEmpty
    }
}

struct _LazyLayout_PlacedSubview {
    var item: LazyLayoutCacheItem
    var placement: _Placement
    var index: Int

    var id: _ViewList_ID {
        item.id
    }

    var size: CGSize {
        let layoutComputer = item.outputs._layoutComputer.attribute?.value ?? .defaultValue
        return layoutComputer.sizeThatFits(ProposedViewSize(placement.proposedSize))
    }

    var origin: CGPoint {
        let size = size
        return CGPoint(
            x: placement.anchorPosition.x - size.width * placement.anchor.x,
            y: placement.anchorPosition.y - size.height * placement.anchor.y
        )
    }

    var frame: CGRect {
        CGRect(origin: origin, size: size)
    }

    var isHeader: Bool {
        item.section.isHeader
    }

    var isFooter: Bool {
        item.section.isFooter
    }

    func matches(_ pinnedViews: PinnedScrollableViews) -> Bool {
        (isHeader && pinnedViews.contains(.sectionHeaders)) ||
            (isFooter && pinnedViews.contains(.sectionFooters))
    }

    var accessibilityContext: AccessibilitySectionContext {
        AccessibilitySectionContext(
            id: item.section.id ?? 0,
            isHeader: item.section.isHeader,
            isFooter: item.section.isFooter
        )
    }
}

extension _LazyLayout_PlacedSubview: LazyLayoutNamespace {
}

struct _LazyLayout_ProposedSubview: LazyLayoutNamespace {
    var item: LazyLayoutCacheItem
    var proposal: _ProposedSize
    var index: Int

    init(
        item: LazyLayoutCacheItem,
        proposal: _ProposedSize,
        index: Int
    ) {
        self.item = item
        self.proposal = proposal
        self.index = index
    }
}

struct _LazyLayout_ProposedSizes: LazyLayoutNamespace {
    var subviews: [_LazyLayout_ProposedSubview]

    init(subviews: [_LazyLayout_ProposedSubview] = []) {
        self.subviews = subviews
    }
}

struct _LazyLayout_Placements: LazyLayoutNamespace {
    var subviews: [_LazyLayout_PlacedSubview]
    var validRect: CGRect
    var invalidSize: Bool
    var translation: CGSize
    var wasCancelled: Bool

    init(
        subviews: [_LazyLayout_PlacedSubview] = [],
        validRect: CGRect = .null,
        invalidSize: Bool = false,
        translation: CGSize = .zero,
        wasCancelled: Bool = false
    ) {
        self.subviews = subviews
        self.validRect = validRect
        self.invalidSize = invalidSize
        self.translation = translation
        self.wasCancelled = wasCancelled
    }
}

struct _LazyLayout_EstimatedPlacements: LazyLayoutNamespace {
    var index: Int?
    var subviews: [_LazyLayout_PlacedSubview]

    init(index: Int? = nil, subviews: [_LazyLayout_PlacedSubview] = []) {
        self.index = index
        self.subviews = subviews
    }
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
    static var _lazyLayoutProperties: _LazyLayout_Properties { get }
}

extension LazyLayout {
    static var _lazyLayoutProperties: _LazyLayout_Properties {
        switch Self.layoutProperties.stackOrientation {
        case .horizontal:
            return _LazyLayout_Properties(axes: .horizontal)
        case .vertical:
            return _LazyLayout_Properties(axes: .vertical)
        case nil:
            return _LazyLayout_Properties()
        }
    }

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
