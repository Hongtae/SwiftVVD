//
//  File: LazyStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Installs the retained-removal inputs required by a resettable lazy root.
struct ResettableLazyLayoutRoot<Content>: View where Content: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var lazyInputs = inputs
        lazyInputs.base[DynamicContainerWillRemoveBeforeInvalidation.self] = true
        lazyInputs[DynamicContainerRetainCompletedUnusedRemovals.self] = true
        lazyInputs[DynamicContainerMaxUnusedItems.self] = 1
        return Content._makeView(view: view[\.content], inputs: lazyInputs)
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Content._makeViewList(view: view[\.content], inputs: inputs)
    }

    typealias Body = Never
}

extension ResettableLazyLayoutRoot: PrimitiveView {
}

extension View {
    func resettableLazyLayoutRoot() -> ResettableLazyLayoutRoot<Self> {
        ResettableLazyLayoutRoot { self }
    }
}

/// Marks implementation-only carriers that belong to the lazy layout system.
protocol LazyLayoutNamespace {
}

/// Reads one environment value through the current rule's cached-value lane.
private struct EnvironmentFetch<Value>: Rule, AsyncAttribute, Hashable {
    var environment: Attribute<EnvironmentValues>
    var keyPath: KeyPath<EnvironmentValues, Value>

    var value: Value {
        environment.value[keyPath: keyPath]
    }
}

@dynamicMemberLookup
/// Supplies environment-backed values to lazy measurement and spacing calls.
struct SizeAndSpacingContext {
    var context: AnyRuleContext
    var owner: AGAttribute
    var _environment: Attribute<EnvironmentValues>

    init(
        context: AnyRuleContext,
        owner: AGAttribute? = nil,
        environment: Attribute<EnvironmentValues>
    ) {
        self.context = context
        self.owner = owner ?? context.attribute
        self._environment = environment
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<EnvironmentValues, Value>) -> Value {
        EnvironmentFetch(
            environment: _environment,
            keyPath: keyPath
        ).cachedValue(
            options: .prefetchInput,
            owner: owner
        )
    }

    mutating func update(_ context: AnyRuleContext) {
        self.context = context
    }
}

/// Describes the axes and multi-child axes supported by a lazy layout.
struct _LazyLayout_Properties: LazyLayoutNamespace, Equatable {
    var axes: Axis.Set
    var multipleViewAxes: Axis.Set

    init(axes: Axis.Set = [], multipleViewAxes: Axis.Set = []) {
        self.axes = axes
        self.multipleViewAxes = multipleViewAxes
    }
}

/// Summarizes whether a prefetch step found no, partial, or complete work.
enum _LazyLayout_PrefetchResult: UInt8, Hashable {
    case none
    case some
    case all

    @discardableResult
    mutating func advanceToSome() -> Bool {
        let hadWork = self != .none
        if !hadWork {
            self = .some
        }
        return hadWork
    }
}

/// Carries the current scroll-prefetch window and requested edge set.
struct ScrollPrefetchState: ViewInput {
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
            mutation: AssignmentGraphMutation(attribute, newValue: self),
            style: .deferred,
            mayDeferUpdate: false
        )
        Update.enqueueAction(reason: .scrollPrefetch) { [weak host] in
            host?.flushTransactions()
        }
    }
}

/// Identifies one resumable stage in the lazy prefetch state machine.
enum LazyPrefetchOperation {
    case layout
    case outputs
    case display(LazyLayoutCacheItem)
    case layoutDisplay(LazyLayoutCacheItem, _ProposedSize)
    case removal
}

/// Pairs a prefetch result with whether the cache already signaled its host.
struct LazyPrefetchPhaseAdvance {
    var result: _LazyLayout_PrefetchResult
    var didNotify: Bool
}

/// Carries the parent cache and the stable child-registration seed assigned to
/// one materialized lazy item.
struct LazyLayoutCacheParent {
    weak var cache: LazyLayoutViewCache?
    var seed: Int

    init(cache: LazyLayoutViewCache? = nil, seed: Int = -1) {
        self.cache = cache
        self.seed = seed
    }
}

/// Overrides the idle-generation limit inherited by a nested lazy cache.
struct LazyLayoutReuseIdleInput: GraphInput {
    static var defaultValue: Int? { nil }
}

extension _GraphInputs {
    /// Routes a nested lazy cache back to the item that owns its graph.
    struct LazyLayoutCacheParentKey: GraphInput {
        static var defaultValue: LazyLayoutCacheParent {
            LazyLayoutCacheParent()
        }

        static func valuesEqual(
            _ lhs: LazyLayoutCacheParent,
            _ rhs: LazyLayoutCacheParent
        ) -> Bool {
            lhs.cache === rhs.cache && lhs.seed == rhs.seed
        }
    }
}

/// Publishes the primary stack axis contributed by a lazy layout type.
private struct LazyDynamicStackOrientationRule<L: LazyLayout>: Rule {
    var layout: Attribute<L>

    var value: Axis? {
        _ = layout.value
        if L.layoutProperties.axes.contains(.horizontal) {
            return .horizontal
        }
        if L.layoutProperties.axes.contains(.vertical) {
            return .vertical
        }
        return nil
    }
}

/// Resets and republishes the shared lazy cache when the graph phase advances.
struct UpdateViewCache: StatefulRule, ObservedAttribute {
    typealias Value = LazyLayoutViewCache

    var _phase: Attribute<Phase>
    var cache: LazyLayoutViewCache?
    var lastResetSeed: UInt32

    init(_phase: Attribute<Phase>, cache: LazyLayoutViewCache?) {
        self._phase = _phase
        self.cache = cache
        self.lastResetSeed = 0
    }

    mutating func updateValue() {
        let resetSeed = _phase.value.resetSeed
        guard let cache else {
            fatalError("UpdateViewCache requires its cache before evaluation.")
        }
        if lastResetSeed != resetSeed {
            cache.reset()
        }
        lastResetSeed = resetSeed
        _AGGraph.setStatefulOutput(cache)
    }

    mutating func destroy() {
        cache?.invalidate()
    }
}

/// Runs cache collection before exposing the latest committed placements.
struct LazyCollectedPlacements: Rule, AsyncAttribute {
    var _subviews: Attribute<[_LazyLayout_PlacedSubview]>
    var _cache: Attribute<LazyLayoutViewCache>

    var value: [_LazyLayout_PlacedSubview] {
        let cache = _cache.value
        cache.collect()
        return _subviews.value
    }
}

/// Computes the materialized subviews and geometry for one lazy layout pass.
struct LazySubviewPlacements<LayoutType: LazyStack>: StatefulRule, AsyncAttribute
where LayoutType.Cache == _LazyStack_Cache<LayoutType> {
    typealias Value = [_LazyLayout_PlacedSubview]

    var layout: Attribute<LayoutType>
    var size: Attribute<ViewSize>
    var position: Attribute<CGPoint>
    var containerSize: OptionalAttribute<ViewSize>
    var environment: Attribute<EnvironmentValues>
    var layoutDirection: Attribute<LayoutDirection>
    var accessibilityEnabled: Attribute<Bool>
    var _cache: Attribute<LazyLayoutViewCache>
    var _layoutComputer: OptionalAttribute<LayoutComputer>

    init(
        layout: Attribute<LayoutType>,
        size: Attribute<ViewSize>,
        position: Attribute<CGPoint>,
        containerSize: OptionalAttribute<ViewSize>,
        environment: Attribute<EnvironmentValues>,
        layoutDirection: Attribute<LayoutDirection>,
        accessibilityEnabled: Attribute<Bool>,
        cache: Attribute<LazyLayoutViewCache>,
        layoutComputer: OptionalAttribute<LayoutComputer> = OptionalAttribute()
    ) {
        self.layout = layout
        self.size = size
        self.position = position
        self.containerSize = containerSize
        self.environment = environment
        self.layoutDirection = layoutDirection
        self.accessibilityEnabled = accessibilityEnabled
        self._cache = cache
        self._layoutComputer = layoutComputer
    }

    mutating func updateValue() {
        guard let cache = _cache.value as? _LazyLayoutViewCache<LayoutType> else {
            fatalError("LazySubviewPlacements requires its matching concrete cache.")
        }
        let previousSubviews = _AGGraph.currentStatefulOutput([_LazyLayout_PlacedSubview].self)
        // A layout pass owns the next commit generation before any subview is
        // proposed or placed. Subviews stamp that generation into their
        // pending placement, and commit reconciles it with placementSeed.
        cache.commitSeed &+= 1
        var placements = makePlacements(cache: cache)
        let containingSize = containerSize.attribute?.value.value ?? size.value.value
        cache.commitPlacedSubviews(
            from: previousSubviews ?? [],
            to: &placements.subviews,
            wasCancelled: placements.wasCancelled,
            context: AnyRuleContext(context),
            containingSize: containingSize
        )
        cache.outerPlacedRect = placements.validRect
        _AGGraph.setStatefulOutput(placements.subviews)
        if shouldInvalidateSize(previous: previousSubviews, current: placements) {
            if let layoutComputer = _layoutComputer.attribute {
                cache.invalidateSize(
                    layoutComputer: layoutComputer,
                    animation: Transaction.current.animation
                )
            }
        }
    }

    private func shouldInvalidateSize(
        previous: [_LazyLayout_PlacedSubview]?,
        current placements: _LazyLayout_Placements
    ) -> Bool {
        if placements.invalidSize {
            return true
        }
        guard let previous else {
            return !placements.subviews.isEmpty
        }
        guard previous.count == placements.subviews.count else {
            return true
        }
        for (old, new) in zip(previous, placements.subviews) {
            if old.item !== new.item ||
                old.index != new.index ||
                old.placement != new.placement {
                return true
            }
        }
        return false
    }

    private mutating func makePlacements(
        cache: _LazyLayoutViewCache<LayoutType>
    ) -> _LazyLayout_Placements {
        guard let owner = _AGGraph.currentRuleContextAttribute else {
            fatalError("LazySubviewPlacements evaluated outside a rule context.")
        }
        let ruleContext = AnyRuleContext(attribute: owner)
        let layout = layout.value
        _ = environment.value
        _ = layoutDirection.value
        _ = accessibilityEnabled.value
        let containerSize = size.value.value
        let subviews = cache.subviews(context: ruleContext)
        var minorSize = minorLength(containerSize)
        if !minorSize.isFinite || minorSize < 0 {
            minorSize = layout.flexibleMinorSize(subviews: subviews)
        }
        if !minorSize.isFinite || minorSize < 0 {
            minorSize = 0
        }
        let minorData = layout.minorGeometry(updatingSize: &minorSize)
        let minor = MinorProperties<LayoutType>(
            count: minorData.count,
            size: minorSize,
            geometry: minorData.data
        )
        let visible = visibleRange(position: position.value, size: containerSize)
        var cacheState = cache.cacheState
        let start = cacheState.resolveIndexAndPosition(
            stack: layout,
            subviews: subviews,
            visible: visible,
            minor: minor
        )
        let placements = cacheState.place(
            stack: layout,
            subviews: subviews,
            from: start.index,
            position: start.position,
            visible: visible,
            visibleLength: max(0, visible.upperBound - visible.lowerBound),
            containerLength: majorLength(containerSize),
            minor: minor,
            pinnedViews: layout.pinnedViews
        )
        // The concrete cache is the shared owner read by sizing, transitions,
        // and imperative scroll-target lookup after this placement pass.
        cache.cacheState = cacheState
        return placements
    }

    private func majorLength(_ size: CGSize) -> CGFloat {
        switch LayoutType.majorAxis {
        case .horizontal:
            return size.width
        case .vertical:
            return size.height
        }
    }

    private func minorLength(_ size: CGSize) -> CGFloat {
        switch LayoutType.majorAxis {
        case .horizontal:
            return size.height
        case .vertical:
            return size.width
        }
    }

    private func visibleRange(position: CGPoint, size: CGSize) -> Range<CGFloat> {
        let lower: CGFloat
        let length: CGFloat
        switch LayoutType.majorAxis {
        case .horizontal:
            lower = position.x
            length = size.width
        case .vertical:
            lower = position.y
            length = size.height
        }
        guard lower.isFinite,
              length.isFinite,
              length > 0 else {
            return CGFloat.zero..<CGFloat.greatestFiniteMagnitude
        }
        return lower..<(lower + length)
    }
}

/// Advances lazy materialization and removal prefetch work across update passes.
struct LazySubviewPrefetcher<LayoutType: LazyLayout>: StatefulRule, AsyncAttribute {
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
    var nextLayoutOffset: Int
    var lastStateID: UniqueID?
    var lastEdges: Edge.Set
    var lastCacheCommitSeed: UInt32?
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
        self.nextLayoutOffset = 0
        self.lastStateID = nil
        self.lastEdges = []
        self.lastCacheCommitSeed = nil
        self.didScheduleContinuation = false
    }

    mutating func updateValue() {
        repeat {
            _ = updateHostState()
        } while didScheduleContinuation
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
        if lastCacheCommitSeed != cache.commitSeed {
            resetOperationState(for: cache)
        }
        return update(info: info, owner: _prefetchState.identifier)
    }

    mutating func resetOperationState(for cache: LazyLayoutViewCache) {
        operations.removeAll(keepingCapacity: true)
        operations.append(.layout)
        operations.append(.removal)
        nextLayoutOffset = 0
        lastCacheCommitSeed = cache.commitSeed
    }

    @discardableResult
    mutating func update(
        info: ScrollPrefetchState,
        owner: AGAttribute
    ) -> _LazyLayout_PrefetchResult {
        didScheduleContinuation = false
        var result = _LazyLayout_PrefetchResult.none

        let cache = _cache.value
        while let operation = operations.popLast() {
            let next: _LazyLayout_PrefetchResult
            let didNotify: Bool
            switch operation {
            case .layout:
                next = makeLayoutPrefetchResult(info: info, offset: nextLayoutOffset, owner: owner)
                didNotify = false
            case .outputs:
                next = cache.prefetchOutputs()
                didNotify = false
            case .display(let item):
                let advance = cache.advancePrefetchPhaseForDisplayWithNotifyFlag(item: item)
                next = advance.result
                didNotify = advance.didNotify
            case .layoutDisplay(let item, let proposal):
                item.beginPrefetching(at: ProposedViewSize(proposal))
                let advance = cache.advancePrefetchPhaseForDisplayWithNotifyFlag(item: item)
                next = advance.result
                didNotify = advance.didNotify
            case .removal:
                let advance = cache.advancePrefetchPhaseForRemovalWithNotifyFlag()
                next = advance.result
                didNotify = advance.didNotify
            }
            if mergePrefetchResult(next, from: operation, didNotify: didNotify, into: &result) {
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
        let axes = LayoutType.layoutProperties.axes
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
        let edgeMask: Edge.Set = axis == .horizontal ? .horizontal : .vertical
        guard !info.edges.intersection(edgeMask).isEmpty else {
            return .none
        }

        let cache = _cache.value
        guard cache.supportsViewHierarchyPrefetching else {
            return .none
        }
        guard scrollGeometryWindowsOverlap(axis: axis) else {
            return .none
        }

        let ruleContext = AnyRuleContext(attribute: owner)
        let sizingContext = _LazyLayout_SizeAndSpacingContext(
            ruleContext: ruleContext,
            owner: owner,
            environment: _environment
        )
        let placementContext = _LazyLayout_PlacementContext(
            base: sizingContext,
            size: _size.value
        )
        let subviews = cache.subviews(context: ruleContext)

        if let layout = stackLayout(LazyHStackLayout.self),
           axis == .horizontal {
            let stackCache = _LazyStack_Cache<LazyHStackLayout>(
                visibleLength: prefetchVisibleLength(axis: axis)
            )
            var proposedSizes = _LazyLayout_ProposedSizes()
            layout.proposeSizes(
                at: offset,
                subviews: subviews,
                context: placementContext,
                cache: stackCache,
                in: &proposedSizes
            )
            return enqueueLayoutDisplayOperations(from: proposedSizes)
        }

        if let layout = stackLayout(LazyVStackLayout.self),
           axis == .vertical {
            let stackCache = _LazyStack_Cache<LazyVStackLayout>(
                visibleLength: prefetchVisibleLength(axis: axis)
            )
            var proposedSizes = _LazyLayout_ProposedSizes()
            layout.proposeSizes(
                at: offset,
                subviews: subviews,
                context: placementContext,
                cache: stackCache,
                in: &proposedSizes
            )
            return enqueueLayoutDisplayOperations(from: proposedSizes)
        }

        if let layout = stackLayout(LazyHGridLayout.self),
           axis == .horizontal {
            let stackCache = _LazyStack_Cache<LazyHGridLayout>(
                visibleLength: prefetchVisibleLength(axis: axis)
            )
            var proposedSizes = _LazyLayout_ProposedSizes()
            layout.proposeSizes(
                at: offset,
                subviews: subviews,
                context: placementContext,
                cache: stackCache,
                in: &proposedSizes
            )
            return enqueueLayoutDisplayOperations(from: proposedSizes)
        }

        if let layout = stackLayout(LazyVGridLayout.self),
           axis == .vertical {
            let stackCache = _LazyStack_Cache<LazyVGridLayout>(
                visibleLength: prefetchVisibleLength(axis: axis)
            )
            var proposedSizes = _LazyLayout_ProposedSizes()
            layout.proposeSizes(
                at: offset,
                subviews: subviews,
                context: placementContext,
                cache: stackCache,
                in: &proposedSizes
            )
            return enqueueLayoutDisplayOperations(from: proposedSizes)
        }

        return .none
    }

    private func stackLayout<StackLayoutType: LazyStack>(
        _ type: StackLayoutType.Type
    ) -> StackLayoutType? {
        let layout = _layout.value
        if let layout = layout as? StackLayoutType {
            return layout
        }
        return nil
    }

    private func prefetchVisibleLength(axis: Axis) -> CGFloat {
        let cache = _cache.value
        let cachedLength = axisLength(cache.containingSize, axis: axis)
        if cachedLength > 0 {
            return cachedLength
        }
        if let containerSize = _containerSize.attribute?.value.value {
            let length = axisLength(containerSize, axis: axis)
            if length > 0 {
                return length
            }
        }
        let sizeLength = axisLength(_size.value.value, axis: axis)
        return sizeLength > 0 ? sizeLength : .infinity
    }

    private func scrollGeometryWindowsOverlap(axis: Axis) -> Bool {
        let transform = _transform.value
        guard let containing = transform.containingScrollGeometry,
              let nearest = transform.nearestScrollGeometry else {
            return true
        }

        let containingRange = containing.outsetOffsetAndSize(axis: axis)
        let nearestRange = nearest.outsetOffsetAndSize(axis: axis)
        guard containingRange.size > 0,
              nearestRange.size > 0 else {
            return false
        }
        let containingMax = containingRange.offset + containingRange.size
        let nearestMax = nearestRange.offset + nearestRange.size
        return containingRange.offset < nearestMax && nearestRange.offset < containingMax
    }

    private func axisLength(_ size: CGSize, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            return size.width
        case .vertical:
            return size.height
        }
    }

    private mutating func enqueueLayoutDisplayOperations(
        from proposedSizes: _LazyLayout_ProposedSizes
    ) -> _LazyLayout_PrefetchResult {
        guard !proposedSizes.subviews.isEmpty else {
            return .none
        }

        for subview in proposedSizes.subviews.reversed() {
            operations.append(.layoutDisplay(subview.item, subview.proposal))
        }
        return .all
    }

    private mutating func mergePrefetchResult(
        _ next: _LazyLayout_PrefetchResult,
        from operation: LazyPrefetchOperation,
        didNotify: Bool,
        into result: inout _LazyLayout_PrefetchResult
    ) -> Bool {
        switch next {
        case .none:
            switch operation {
            case .display, .layoutDisplay, .removal:
                didScheduleContinuation = !didNotify
                return didScheduleContinuation
            case .outputs:
                if !operations.isEmpty {
                    return true
                }
                return false
            case .layout:
                return false
            }
        case .all:
            result = .all
            switch operation {
            case .layout:
                nextLayoutOffset += 1
                operations.append(.outputs)
                return true
            case .outputs:
                if !operations.isEmpty {
                    return true
                }
                return false
            case .display, .layoutDisplay, .removal:
                didScheduleContinuation = !didNotify
                return didScheduleContinuation
            }
        case .some:
            result = .some
            switch operation {
            case .outputs:
                operations.append(operation)
                return true
            case .layout:
                operations.append(operation)
                return true
            case .layoutDisplay(let item, _):
                operations.append(.display(item))
            case .display, .removal:
                operations.append(operation)
            }
            switch operation {
            case .display, .layoutDisplay, .removal:
                didScheduleContinuation = !didNotify
            default:
                didScheduleContinuation = true
            }
            return true
        }
    }
}

/// Identifies an item's section role for pinning and display ordering.
struct LazyLayoutCacheSection: Equatable {
    var id: UInt32?
    var isHeader: Bool
    var isFooter: Bool

    init(id: UInt32? = nil, isHeader: Bool = false, isFooter: Bool = false) {
        self.id = id
        self.isHeader = isHeader
        self.isFooter = isFooter
    }
}

/// Projects a lazy item's section role into accessibility collection metadata.
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
/// Extends the base sizing context with an optional container-size input.
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

/// Builds the size-and-spacing engine shared by a lazy layout root.
///
/// Placement remains owned by `LazySubviewPlacements`; adding child geometry
/// or imperative placement here would duplicate that work and broaden the
/// layout computer's invalidation dependencies.
struct LazyLayoutComputer<LayoutType: LazyLayout>: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer

    var _layout: Attribute<LayoutType>
    var _environment: Attribute<EnvironmentValues>
    var _cache: Attribute<LazyLayoutViewCache>
    var _containerSize: OptionalAttribute<ViewSize>

    /// Measures lazy content from its shared view cache without owning placement.
    struct Engine: LayoutEngine {
        var layout: LayoutType
        var context: _LazyLayout_SizeAndSpacingContext
        var cache: LazyLayoutViewCache
        var maxSize: CGSize
        var sizeCache: ViewSizeCache

        mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            let layout = layout
            let context = context
            let cache = cache
            let measured = sizeCache.get(proposal) {
                var result: CGSize!
                context.ruleContext.update {
                    let subviews = cache.subviews(context: context.ruleContext)
                    let cacheState = cache.copyCacheState(type: LayoutType.self)
                    result = layout.sizeThatFits(
                        proposedSize: ProposedViewSize(proposal),
                        subviews: subviews,
                        context: context,
                        cache: cacheState
                    )
                }
                return result
            }

            // The cache records the largest committed lazy extent. A later
            // partial materialization must not make the container shrink below
            // that extent merely because fewer items were measured this pass.
            return CGSize(
                width: max(measured.width, maxSize.width),
                height: max(measured.height, maxSize.height)
            )
        }

        mutating func spacing() -> Spacing {
            var result: Spacing!
            context.ruleContext.update {
                let subviews = cache.subviews(context: context.ruleContext)
                let cacheState = cache.copyCacheState(type: LayoutType.self)
                result = layout.spacing(
                    subviews: subviews,
                    context: context,
                    cache: cacheState
                )
            }
            return result
        }
    }

    mutating func updateValue() {
        let ruleContext = AnyRuleContext(context)
        let cache = _cache.value
        let engine = Engine(
            layout: _layout.value,
            context: _LazyLayout_SizeAndSpacingContext(
                ruleContext: ruleContext,
                owner: ruleContext.attribute,
                environment: _environment,
                containerSize: _containerSize
            ),
            cache: cache,
            maxSize: cache.maxSize,
            sizeCache: ViewSizeCache()
        )
        update(to: engine)
    }
}

/// Supplies geometry, visibility, and environment state to lazy placement.
struct _LazyLayout_PlacementContext: LazyLayoutNamespace {
    /// Groups the geometry values shared by placement callbacks.
    struct Geometry {
        var scrollGeometry: ScrollGeometry
        var nearestScrollGeometry: ScrollGeometry
        var viewSize: CGSize
        var isAccessibilityEnabled: Bool
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
        let viewSize = size.value
        let fallbackGeometry = ScrollGeometry(
            contentOffset: .zero,
            contentSize: viewSize,
            contentInsets: EdgeInsets(),
            containerSize: viewSize,
            visibleRect: CGRect(origin: .zero, size: viewSize)
        )
        // Resolve the containing and nearest windows independently so a
        // transform that supplies only one does not erase the other fallback.
        var scrollGeometry = transform.containingScrollGeometry ?? fallbackGeometry
        var nearestScrollGeometry = transform.nearestScrollGeometry ?? fallbackGeometry

        if layoutDirection == .rightToLeft {
            // Mirror each visible window around the placement width while
            // preserving its size and its nonhorizontal scroll state.
            let previousOffset = scrollGeometry.contentOffset
            let newOffsetX = viewSize.width - scrollGeometry.visibleRect.maxX
            scrollGeometry = ScrollGeometry(
                contentOffset: CGPoint(x: newOffsetX, y: previousOffset.y),
                contentSize: scrollGeometry.contentSize,
                contentInsets: scrollGeometry.contentInsets,
                containerSize: scrollGeometry.containerSize,
                visibleRect: scrollGeometry.visibleRect.offsetBy(
                    dx: newOffsetX - previousOffset.x,
                    dy: 0
                )
            )

            let previousNearestOffset = nearestScrollGeometry.contentOffset
            let newNearestOffsetX =
                viewSize.width - nearestScrollGeometry.visibleRect.maxX
            nearestScrollGeometry = ScrollGeometry(
                contentOffset: CGPoint(
                    x: newNearestOffsetX,
                    y: previousNearestOffset.y
                ),
                contentSize: nearestScrollGeometry.contentSize,
                contentInsets: nearestScrollGeometry.contentInsets,
                containerSize: nearestScrollGeometry.containerSize,
                visibleRect: nearestScrollGeometry.visibleRect.offsetBy(
                    dx: newNearestOffsetX - previousNearestOffset.x,
                    dy: 0
                )
            )
        }

        self.base = base
        self.position = position
        self.size = viewSize
        self.pinnedViews = pinnedViews
        self.geometry = Geometry(
            scrollGeometry: scrollGeometry,
            nearestScrollGeometry: nearestScrollGeometry,
            viewSize: viewSize,
            isAccessibilityEnabled: isAccessibilityEnabled
        )
    }

    var nearestScrollGeometry: ScrollGeometry {
        geometry.nearestScrollGeometry
    }

    var containingScrollGeometry: ScrollGeometry {
        geometry.scrollGeometry
    }

    var nearestVisibleRect: CGRect {
        nearestScrollGeometry.visibleRect
    }

    var unadjustedVisibleRect: CGRect {
        containingScrollGeometry.visibleRect
    }

    var containerSize: CGSize {
        base.containerSize
    }

    var contentInsets: EdgeInsets {
        nearestScrollGeometry.contentInsets
    }

    var containingVisibleRect: CGRect {
        // Accessibility expansion is callback-local; the stored scroll state
        // remains the unadjusted geometry used by the other accessors.
        var geometry = containingScrollGeometry
        if self.geometry.isAccessibilityEnabled {
            geometry.outsetForAX(limit: self.geometry.viewSize)
        }
        return geometry.visibleRect
    }

    var clampedVisibleRect: CGRect {
        containingVisibleRect.intersection(
            CGRect(origin: .zero, size: size)
        )
    }

    var allowsTranslations: Bool {
        guard size.width != 0, size.height != 0 else {
            return false
        }
        // Translation is useful only when the nearest viewport is displaced
        // from an origin edge and leaves undisplayed extent toward an end edge.
        let visibleRect = nearestVisibleRect
        return (visibleRect.minX > 0 || visibleRect.minY > 0)
            && (size.width > visibleRect.maxX || size.height > visibleRect.maxY)
    }
}

/// Wraps placement context for estimated, noncommitting layout queries.
struct _LazyLayout_EstimatedPlacementContext: LazyLayoutNamespace {
    var base: _LazyLayout_PlacementContext

    init(base: _LazyLayout_PlacementContext) {
        self.base = base
    }
}

/// Traverses lazy view-list nodes without eagerly materializing every child.
struct _LazyLayout_Subviews: LazyLayoutNamespace {
    /// Presents nested list and section nodes to lazy layout traversal.
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

    func estimatedCount(style: _ViewList_IteratorStyle = _ViewList_IteratorStyle()) -> Int {
        switch node {
        case .list(let list, _):
            return list.estimatedCount(style: style)
        case .group(let group):
            return group.estimatedCount(style: style)
        case .section(let section):
            return section.estimatedCount(style: style)
        case .sublist(let sublist):
            return sublist.count
        }
    }

    func id(at index: Int, style: _ViewList_IteratorStyle = _ViewList_IteratorStyle()) -> _ViewList_ID? {
        var from = index
        var resolved: _ViewList_ID?
        _ = apply(from: &from, style: style) { _, subview, stop in
            resolved = subview.data.id
            stop = true
        }
        return resolved
    }

    func firstIndex<ID: Hashable>(
        of id: ID,
        style: _ViewList_IteratorStyle = _ViewList_IteratorStyle()
    ) -> Int? {
        var from = 0
        var resolved: Int?
        _ = apply(from: &from, style: style) { _, subview, stop in
            guard _viewListID(subview.data.id, matches: id) else { return }
            resolved = subview.index
            stop = true
        }
        return resolved
    }

    @discardableResult
    func apply(
        from: inout Int,
        style: _ViewList_IteratorStyle = _ViewList_IteratorStyle(),
        to body: (inout Int, _LazyLayout_Subview, inout Bool) -> Void
    ) -> Bool {
        var remainingToSkip = max(0, from)
        var traversalIndex = baseIndex
        var nodeFrom = 0
        let completed = forEachSublist(from: &nodeFrom, style: style) { sublist in
            let start = max(0, sublist.start)
            guard start < sublist.count else { return true }

            for offset in start..<sublist.count {
                if remainingToSkip > 0 {
                    remainingToSkip -= 1
                    traversalIndex += 1
                    continue
                }

                var index = traversalIndex
                var shouldStop = false
                let id = sublist.id.elementID(at: offset)
                let data = _LazyLayout_Subview.Data(
                    elements: sublist.elements,
                    id: id,
                    traits: sublist.traits,
                    list: sublist.list,
                    section: section
                )
                let subview = _LazyLayout_Subview(
                    cache: cache,
                    context: context,
                    data: data,
                    index: index
                )
                body(&index, subview, &shouldStop)
                if shouldStop { return false }
                traversalIndex = index + 1
            }
            return true
        }
        from = 0
        return completed
    }

    @discardableResult
    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle = _ViewList_IteratorStyle(),
        to body: (inout Int, Node, inout Bool) -> Void
    ) -> Bool {
        if case .section(let section) = node {
            var index = baseIndex + max(0, from)
            var shouldStop = false
            let child = _LazyLayout_Section(
                base: section,
                transform: transform,
                cache: cache,
                context: context,
                baseIndex: baseIndex
            )
            body(&index, .section(child), &shouldStop)
            from = max(0, index - baseIndex)
            return !shouldStop
        }

        var traversalIndex = baseIndex
        return forEachNode(from: &from, style: style) { nodeFrom, node, temporaryTransform in
            var shouldStop = false
            let nodeTransform = combinedTransform(with: temporaryTransform)

            switch node {
            case .section(let section):
                let child = _LazyLayout_Section(
                    base: section,
                    transform: nodeTransform,
                    cache: cache,
                    context: context,
                    baseIndex: traversalIndex
                )
                var index = child.baseIndex + max(0, nodeFrom)
                body(&index, .section(child), &shouldStop)
                traversalIndex = child.baseIndex + section.estimatedCount(style: style)
                nodeFrom = shouldStop ? max(0, index - child.baseIndex) : 0

            case .sublist(let sublist):
                let child = _LazyLayout_Subviews(
                    cache: cache,
                    context: context,
                    node: .sublist(sublist),
                    transform: nodeTransform,
                    section: section,
                    baseIndex: traversalIndex
                )
                var index = child.baseIndex + max(0, nodeFrom)
                body(&index, .subviews(child), &shouldStop)
                traversalIndex = index + max(0, sublist.count - max(0, sublist.start))
                nodeFrom = shouldStop ? max(0, index - child.baseIndex) : 0

            case .list(let list, let attribute):
                let child = _LazyLayout_Subviews(
                    cache: cache,
                    context: context,
                    node: .list(list, attribute),
                    transform: nodeTransform,
                    section: section,
                    baseIndex: traversalIndex
                )
                var index = child.baseIndex + max(0, nodeFrom)
                body(&index, .subviews(child), &shouldStop)
                traversalIndex = child.baseIndex + list.estimatedCount(style: style)
                nodeFrom = shouldStop ? max(0, index - child.baseIndex) : 0

            case .group(let group):
                let child = _LazyLayout_Subviews(
                    cache: cache,
                    context: context,
                    node: .group(group),
                    transform: nodeTransform,
                    section: section,
                    baseIndex: traversalIndex
                )
                var index = child.baseIndex + max(0, nodeFrom)
                body(&index, .subviews(child), &shouldStop)
                traversalIndex = child.baseIndex + group.estimatedCount(style: style)
                nodeFrom = shouldStop ? max(0, index - child.baseIndex) : 0
            }
            return !shouldStop
        }
    }

    private func combinedTransform(
        with temporaryTransform: _ViewList_TemporarySublistTransform
    ) -> _ViewList_SublistTransform {
        combinedTransform(transform, with: temporaryTransform)
    }

    private func combinedTransform(
        _ base: _ViewList_SublistTransform,
        with temporaryTransform: _ViewList_TemporarySublistTransform
    ) -> _ViewList_SublistTransform {
        let temporary = temporaryTransform.copy()
        guard !temporary.items.isEmpty else {
            return base
        }
        var combined = base
        for item in temporary.items {
            combined.push(item)
        }
        combined.subgraphCount += temporary.subgraphCount
        return combined
    }

    private func forEachSublist(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        body: (_ViewList_Sublist) -> Bool
    ) -> Bool {
        switch node {
        case .list(let list, let listAttribute):
            return forEachSublist(
                in: list,
                from: &from,
                listAttribute: listAttribute,
                style: style,
                transform: transform,
                body: body
            )
        case .group(let group):
            return forEachSublist(
                in: group,
                from: &from,
                style: style,
                transform: transform,
                body: body
            )
        case .section(let section):
            return forEachSublist(
                in: section,
                from: &from,
                style: style,
                transform: transform,
                body: body
            )
        case .sublist(var sublist):
            transform.apply(to: &sublist)
            let shouldContinue = body(sublist)
            from = 0
            return shouldContinue
        }
    }

    private func forEachSublist(
        in list: any ViewList,
        from: inout Int,
        listAttribute: Attribute<any ViewList>? = nil,
        style: _ViewList_IteratorStyle,
        transform baseTransform: _ViewList_SublistTransform,
        body: (_ViewList_Sublist) -> Bool
    ) -> Bool {
        _applyNodesExpandingGroups(
            in: list,
            from: &from,
            style: style,
            listAttribute: listAttribute,
            transform: _ViewList_TemporarySublistTransform()
        ) { nodeFrom, nodeStyle, node, temporaryTransform in
            let nodeTransform = combinedTransform(baseTransform, with: temporaryTransform)
            switch node {
            case .sublist(var sublist):
                nodeTransform.apply(to: &sublist)
                return body(sublist)

            case .section(let section):
                return forEachSublist(
                    in: section,
                    from: &nodeFrom,
                    style: nodeStyle,
                    transform: nodeTransform,
                    body: body
                )

            case .list(let list, let attribute):
                return forEachSublist(
                    in: list,
                    from: &nodeFrom,
                    listAttribute: attribute,
                    style: nodeStyle,
                    transform: nodeTransform,
                    body: body
                )

            case .group(let group):
                return forEachSublist(
                    in: group,
                    from: &nodeFrom,
                    style: nodeStyle,
                    transform: nodeTransform,
                    body: body
                )
            }
        }
    }

    private func forEachSublist(
        in section: _ViewList_Section,
        from: inout Int,
        style: _ViewList_IteratorStyle,
        transform baseTransform: _ViewList_SublistTransform,
        body: (_ViewList_Sublist) -> Bool
    ) -> Bool {
        if let header = section.header,
           !forEachSublist(
               in: header.list,
               from: &from,
               listAttribute: header.attribute,
               style: style,
               transform: baseTransform,
               body: body
           ) {
            return false
        }
        if let content = section.content,
           !forEachSublist(
               in: content.list,
               from: &from,
               listAttribute: content.attribute,
               style: style,
               transform: baseTransform,
               body: body
           ) {
            return false
        }
        if let footer = section.footer,
           !forEachSublist(
               in: footer.list,
               from: &from,
               listAttribute: footer.attribute,
               style: style,
               transform: baseTransform,
               body: body
           ) {
            return false
        }
        return true
    }

    private func forEachNode(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        body: (inout Int, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        switch node {
        case .list(let list, let listAttribute):
            return list.applyNodes(
                from: &from,
                style: style,
                list: listAttribute,
                transform: _ViewList_TemporarySublistTransform()
            ) { nodeFrom, _, node, temporaryTransform in
                body(&nodeFrom, node, temporaryTransform)
            }
        case .group(let group):
            return group.applyNodes(
                from: &from,
                style: style,
                transform: _ViewList_TemporarySublistTransform()
            ) { nodeFrom, _, node, temporaryTransform in
                body(&nodeFrom, node, temporaryTransform)
            }
        case .section(let section):
            return body(&from, .section(section), _ViewList_TemporarySublistTransform())
        case .sublist(let sublist):
            return body(&from, .sublist(sublist), _ViewList_TemporarySublistTransform())
        }
    }

}

/// Splits one lazy section into independently traversable header, content, and footer regions.
struct _LazyLayout_Section: LazyLayoutNamespace {
    /// Carries the stable section identity shared by its three regions.
    struct ID: Hashable {
        var id: UInt32
    }

    /// Selects which section region contributes an item to traversal.
    private enum Region {
        case header
        case content
        case footer

        func cacheSection(id: UInt32) -> LazyLayoutCacheSection {
            switch self {
            case .header:
                return LazyLayoutCacheSection(id: id, isHeader: true)
            case .content:
                return LazyLayoutCacheSection(id: id)
            case .footer:
                return LazyLayoutCacheSection(id: id, isFooter: true)
            }
        }
    }

    private static let sectionEstimatedCountStyle = _ViewList_IteratorStyle(value: 2)

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

    var header: _LazyLayout_Subviews {
        region(.header)
    }

    var content: _LazyLayout_Subviews {
        region(.content)
    }

    var footer: _LazyLayout_Subviews {
        region(.footer)
    }

    private func region(_ region: Region) -> _LazyLayout_Subviews {
        let entry = entry(for: region)
        let node: _ViewList_Node
        if let entry {
            node = .list(entry.list, entry.attribute)
        } else {
            node = .list(EmptyViewList() as any ViewList, nil)
        }

        return _LazyLayout_Subviews(
            cache: cache,
            context: context,
            node: node,
            transform: transform,
            section: region.cacheSection(id: base.id),
            baseIndex: baseIndex + precedingEstimatedCount(before: region)
        )
    }

    private func entry(
        for region: Region
    ) -> (list: any ViewList, attribute: Attribute<any ViewList>)? {
        switch region {
        case .header:
            return base.header
        case .content:
            return base.content
        case .footer:
            return base.footer
        }
    }

    private func precedingEstimatedCount(before region: Region) -> Int {
        switch region {
        case .header:
            return 0
        case .content:
            return estimatedCount(of: base.header)
        case .footer:
            return estimatedCount(of: base.header) + estimatedCount(of: base.content)
        }
    }

    private func estimatedCount(
        of entry: (list: any ViewList, attribute: Attribute<any ViewList>)?
    ) -> Int {
        entry?.list.estimatedCount(style: Self.sectionEstimatedCountStyle) ?? 0
    }
}

/// Resolves, proposes, prefetches, and places one lazily materialized child.
struct _LazyLayout_Subview: LazyLayoutNamespace {
    var cache: LazyLayoutViewCache
    var context: AnyRuleContext
    var data: Data
    var index: Int

    var id: _ViewList_ID {
        data.id
    }

    var kind: Kind {
        if data.section.isHeader {
            return .header
        }
        return data.section.isFooter ? .footer : .normal
    }

    var sectionID: UInt32? {
        data.section.id
    }

    /// Resolves the materialized child's layout computer while preserving the
    /// evaluating rule that owns this lazy traversal.
    var layout: LayoutProxy {
        let item = cache.item(data: data)
        return LayoutProxy(
            context: context,
            layoutComputer: item.outputs._layoutComputer.attribute
        )
    }

    subscript<K>(key: K.Type) -> K.Value where K: _ViewTraitKey {
        data.traits[key]
    }

    subscript<K>(key: K.Type) -> K.Value where K: LayoutValueKey {
        data.traits[_LayoutTrait<K>.self]
    }

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

    /// Carries the view-list identity and element storage needed for materialization.
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

    /// Distinguishes ordinary items from section boundary items.
    enum Kind: Hashable, CustomDebugStringConvertible {
        case normal
        case header
        case footer

        var debugDescription: String {
            switch self {
            case .normal: "normal"
            case .header: "header"
            case .footer: "footer"
            }
        }
    }

    func proposeSize(_ proposal: ProposedViewSize) -> _LazyLayout_ProposedSubview {
        let item = cache.item(data: data)
        guard let cache = item.cache else {
            fatalError("_LazyLayout_Subview.proposeSize requires an owning cache.")
        }
        item.placementSeed = cache.commitSeed
        item.prefetchSeed = 0
        item.pendingPlacement = _Placement(
            proposedSize: proposal.replacingUnspecifiedDimensions()
        )
        return _LazyLayout_ProposedSubview(
            item: item,
            proposal: _ProposedSize(proposal),
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
        let layout = layout
        let length = layout.lengthThatFits(_ProposedSize(size), in: axis)
        guard let predecessor else {
            return (length, 0)
        }
        if let uniformSpacing {
            return (length, uniformSpacing)
        }
        let layoutDirection = context[cache._layoutDirection]
        let spacing = predecessor.layout.spacing().distanceToSuccessorView(
            along: axis,
            layoutDirection: layoutDirection,
            preferring: layout.spacing()
        )
        return (
            length,
            spacing
                ?? (axis == .horizontal
                    ? Spacing.defaultValue.width
                    : Spacing.defaultValue.height)
        )
    }

    func place(at placement: _Placement) -> _LazyLayout_PlacedSubview {
        let item = cache.item(data: data)
        guard let cache = item.cache else {
            fatalError("_LazyLayout_Subview.place requires an owning cache.")
        }
        item.placementSeed = cache.commitSeed
        item.prefetchSeed = 0
        item.pendingPlacement = placement
        return _LazyLayout_PlacedSubview(
            item: item,
            placement: placement,
            index: index
        )
    }
}

/// Retains one materialized lazy child and all state needed to reuse, place,
/// transition, prefetch, or eventually evict its graph.
final class LazyLayoutCacheItem: AnimationListener, LazyLayoutNamespace, @unchecked Sendable {
    /// Publishes transition phase and removal state to the retained child graph.
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

    /// Describes ownership work that may keep an offscreen item alive.
    enum PrefetchPhase: Hashable {
        case notPrefetching
        case prefetching
        case pendingDisplay
        case pendingRemoval
    }

    /// Records whether the item's subgraph is attached to the cache parent.
    enum ParentingPhase: Hashable {
        case inserted
        case removed
    }

    /// Defers phase reconciliation for every retained item to the graph host.
    struct AllItemsPhaseMutation: GraphMutation {
        weak var cache: LazyLayoutViewCache?

        func apply() {
            cache?.updateItemPhases()
        }
    }

    /// Defers phase reconciliation for one item after its last animation ends.
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
        self.removedSeed = .max
        self.placement = nil
        self.pendingPlacement = nil
        self.releaseSecondaryElements = nil
        self.willEnableTransitions = false
        self.willAnimateRemoval = false
        self.parentingPhase = nil
        self.hasWarned = false
    }

    override func animationWasAdded() {
        animationCount &+= 1
    }

    override func animationWasRemoved() {
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

/// Tracks weakly owned descendant lazy caches for one retained parent item.
struct LazyLayoutCacheChildren {
    var seed: Int
    var children: [WeakBox<LazyLayoutViewCache>]

    init(seed: Int = 0, children: [WeakBox<LazyLayoutViewCache>] = []) {
        self.seed = seed
        self.children = children
    }
}

/// Owns materialized lazy children and the placement state shared by sizing,
/// scrolling, transitions, and per-item geometry rules.
///
/// The cache is reference-backed because those subsystems must observe one
/// placement lifecycle. Mutations that affect graph outputs still invalidate
/// their narrow AG attributes explicitly; mutating this object is not itself
/// an AttributeGraph dependency.
class LazyLayoutViewCache: LazyLayoutNamespace, CustomStringConvertible {
    /// Groups every per-item graph node produced during one lazy child
    /// materialization before ownership is transferred to the cache item.
    struct SubviewOutputs {
        var state: Attribute<LazyLayoutCacheItem.State>?
        var geometry: Attribute<ViewGeometry>?
        var phase: Attribute<Phase>?
        var displayListWrapper: Attribute<HiddenForReuseEffect>?
        var transaction: Attribute<Transaction>?
        var transition: AGAttribute?
        var transitionType: Any.Type?
        var viewOutputs: _ViewOutputs

        init(
            state: Attribute<LazyLayoutCacheItem.State>? = nil,
            geometry: Attribute<ViewGeometry>? = nil,
            phase: Attribute<Phase>? = nil,
            displayListWrapper: Attribute<HiddenForReuseEffect>? = nil,
            transaction: Attribute<Transaction>? = nil,
            transition: AGAttribute? = nil,
            transitionType: Any.Type? = nil,
            viewOutputs: _ViewOutputs = _ViewOutputs()
        ) {
            self.state = state
            self.geometry = geometry
            self.phase = phase
            self.displayListWrapper = displayListWrapper
            self.transaction = transaction
            self.transition = transition
            self.transitionType = transitionType
            self.viewOutputs = viewOutputs
        }
    }

    /// Orders reusable items by recent use and memoizes that ordering per pass.
    struct LeastRecentlyUsedItems {
        private(set) var usedSeed: UInt32 = 0
        var maxIdle: Int = 16
        var lastTransactionID = TransactionID()
        var transactionSeed: UInt32 = 0
        private(set) var items: [LazyLayoutCacheItem]?

        mutating func invalidate() {
            items = nil
        }

        mutating func reset() {
            usedSeed = 1
            lastTransactionID = TransactionID()
            transactionSeed = 1
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
    var childCacheSeeds: [Int: _ViewList_ID.Canonical]
    var nextChildCacheSeed: Int

    /// Identifies the concrete lazy layout type hidden behind this cache.
    class var viewType: Any.Type {
        fatalError("LazyLayoutViewCache.viewType requires a concrete cache type.")
    }

    var description: String {
        "LazyLayoutViewCache<\(String(describing: type(of: self).viewType))>"
    }

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

    func reset() {
        lru.reset()
        commitSeed = 1
        placementSeed = 1
        hasSections = false
        hasDepth = false
        isFirstCommit = true
    }

    func invalidate() {
        lru.invalidate()
        for item in items.values {
            guard AGSubgraphIsValid(item.subgraph) else { continue }
            item.subgraph.willRemove()
            item.subgraph.invalidate()
            item.subgraph.removeFromParent()
        }
        items.removeAll()
    }

    /// Synchronizes retained subgraph parenting and evicts only expired,
    /// unplaced items that have no animation or prefetch ownership.
    func collect() {
        for item in items.values {
            synchronizeParenting(of: item)
        }

        items = items.filter { _, item in
            let idleAge = Int(lru.usedSeed &- item.usedSeed)
            let isExpired = idleAge > lru.maxIdle
                && item.placementSeed != placementSeed
                && item.animationCount == 0
                && item.prefetchSeed != commitSeed
                && item.prefetchPhase != .pendingRemoval
            guard isExpired else {
                return true
            }

            if item.subgraph.isInserted {
                item.subgraph.willRemove()
            }
            item.subgraph.invalidate()
            item.subgraph.removeFromParent()
            return false
        }
        lru.invalidate()
    }

    private func synchronizeParenting(of item: LazyLayoutCacheItem) {
        if item.displayIndex == nil {
            guard item.parentingPhase == .inserted else {
                return
            }
            item.subgraph.willRemove()
            item.subgraph.removeFromParent()
            item.parentingPhase = .removed
            return
        }

        guard item.parentingPhase != .inserted else {
            return
        }
        parentSubgraph.addChild(item.subgraph)
        if item.parentingPhase == .removed {
            item.subgraph.didReinsert()
        }
        item.parentingPhase = .inserted
    }

    func invalidateSize(layoutComputer: Attribute<LayoutComputer>, animation: Animation?) {
        guard let graph = _AGGraph.current else {
            fatalError("LazyLayoutViewCache.invalidateSize requires an active AttributeGraph.")
        }
        guard let viewGraph else {
            return
        }

        let seed = layoutInvalidationSeed(for: layoutComputer)
        if invalidationSeed == seed {
            guard invalidationTTL != 0 else {
                return
            }
        } else {
            invalidationSeed = seed
            invalidationTTL = 2
        }
        invalidationTTL &-= 1

        let target = layoutComputer.asWeak().base
        guard target.isValid(in: graph) else {
            return
        }

        if let animation {
            viewGraph.asyncTransaction(
                Transaction(animation: animation),
                id: Transaction.id,
                mutation: InvalidatingGraphMutation(attribute: target),
                style: .deferred,
                mayDeferUpdate: false
            )
        } else {
            Update.enqueueAction { [weak viewGraph] in
                viewGraph?.continueTransaction(invalidating: target)
            }
        }
    }

    private func layoutInvalidationSeed(for layoutComputer: Attribute<LayoutComputer>) -> UInt32 {
        let seed = layoutComputer.value.seed
        if seed != 0 {
            return UInt32(truncatingIfNeeded: seed)
        }
        return layoutComputer.identifier.rawValue
    }

    func targetFrame(for placedSubview: _LazyLayout_PlacedSubview) -> CGRect {
        var frame = placedSubview.frame
        let containerWidth = containingSize.width
        if _layoutDirection.value == .rightToLeft,
           containerWidth.isFinite {
            frame.origin.x = containerWidth - frame.maxX
        }
        return frame
    }

    func item(for id: _ViewList_ID.Canonical) -> LazyLayoutCacheItem? {
        items[id]
    }

    func item(for subgraph: AGSubgraph) -> LazyLayoutCacheItem? {
        items.values.first { $0.subgraph === subgraph }
    }

    /// Returns an independent copy of the concrete layout's cache state.
    ///
    /// Size and spacing queries are observational. Letting them mutate the
    /// placement cache would make repeated measurements order-dependent.
    func copyCacheState<LayoutType: LazyLayout>(
        type: LayoutType.Type
    ) -> LayoutType.Cache {
        fatalError(
            "LazyLayoutViewCache.copyCacheState(type:) requires a matching concrete cache."
        )
    }

    /// Resolves the entrance placement for an item entering the committed display set.
    func initialPlacement(
        newIndex: Int,
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasInsertedToSubviews: Bool,
        context: AnyRuleContext
    ) -> _Placement {
        fatalError(
            "LazyLayoutViewCache.initialPlacement requires a matching concrete cache."
        )
    }

    /// Resolves the destination placement retained while an item leaves the display set.
    func finalPlacement(
        oldIndex: Int,
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasRemovedFromSubviews: Bool,
        context: AnyRuleContext
    ) -> _Placement {
        fatalError(
            "LazyLayoutViewCache.finalPlacement requires a matching concrete cache."
        )
    }

    /// Resolves the placement visible to a materialized item.
    ///
    /// The display index is the common O(1) path, but identity is verified
    /// because retained/reused items can outlive an array generation. A scan
    /// repairs a stale index. During retargeting, pending placement takes
    /// precedence over the last committed item placement.
    func placement(
        of item: LazyLayoutCacheItem,
        in placedSubviews: [_LazyLayout_PlacedSubview]
    ) -> _Placement? {
        if let displayIndex = item.displayIndex,
           placedSubviews.indices.contains(displayIndex),
           placedSubviews[displayIndex].item === item {
            return placedSubviews[displayIndex].placement
        }
        if let placedSubview = placedSubviews.first(where: { $0.item === item }) {
            return placedSubview.placement
        }
        return item.pendingPlacement ?? item.placement
    }

    func subviews(context: AnyRuleContext) -> _LazyLayout_Subviews {
        let transactionID = TransactionID(context: context)
        if lru.lastTransactionID != transactionID {
            lru.lastTransactionID = transactionID
            lru.transactionSeed &+= 1
        }
        return _LazyLayout_Subviews(
            cache: self,
            context: context,
            node: .list(_list.value, _list),
            transform: _ViewList_SublistTransform()
        )
    }

    func currentListTransaction() -> Transaction {
        guard let graph = _AGGraph.current else {
            fatalError("LazyLayoutViewCache.currentListTransaction requires an active AttributeGraph.")
        }
        return graph.transaction(for: _list.identifier) ?? inputs.base.transaction.value
    }

    func item(data: _LazyLayout_Subview.Data) -> LazyLayoutCacheItem {
        let id = data.id.canonicalID
        let transition = anyTransition(data: data)

        if let item = items[id] {
            refresh(item, data: data, transition: transition)
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
        item.removedSeed = .max
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
        hasSections = hasSections || item.section.id != nil
        hasDepth = hasDepth || item.zIndex != 0
        lru.invalidate()
    }

    private func lazyViewPhase(
        basePhase: Attribute<Phase>,
        elementPhase: Attribute<Phase>,
        state: Attribute<LazyLayoutCacheItem.State>,
        in graph: _AGGraph
    ) -> Attribute<Phase> {
        return graph.makeRule(
            LazyViewPhase(
                _phase1: basePhase,
                _phase2: elementPhase,
                _state: state
            )
        )
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
            item._state.setValue(state, transaction: currentListTransaction())
            return
        }
        guard state.phase != .willAppear else { return }
        if state.phase == .identity,
           item.displayIndex != nil {
            let listTransaction = currentListTransaction()
            state.phase = .didDisappear
            state.enableTransitions = item.willEnableTransitions
            // The concrete transition body owns phase-specific transaction
            // filtering. Publishing only the item state keeps one source of
            // truth for both ordinary and filtered transitions.
            item._state.setValue(state, transaction: listTransaction)
            item.willEnableTransitions = false
            return
        }
        guard item.animationCount == 0 else { return }
        item.displayIndex = nil
        item.placement = nil
        item.prefetchPhase = supportsViewHierarchyPrefetching ? .pendingRemoval : .notPrefetching
        state.isRemoved = true
        item._state.setValue(state, transaction: currentListTransaction())
    }

    /// Reconciles one pending layout result with the previously displayed item set.
    func commitPlacedSubviews(
        from previousPlacedSubviews: [_LazyLayout_PlacedSubview],
        to placedSubviews: inout [_LazyLayout_PlacedSubview],
        wasCancelled: Bool,
        context: AnyRuleContext,
        containingSize: CGSize
    ) {
        placementSeed &+= 1
        var oldPlacedSubviews = previousPlacedSubviews
        var minPlacedIndex: Int?
        var maxPlacedIndex: Int?
        var needsPhaseUpdate = false
        var appendedStaleItem = false
        var retargetedRemovalItems: [LazyLayoutCacheItem] = []

        var newIndex = 0
        while newIndex < placedSubviews.count {
            let targetPlacedSubview = placedSubviews[newIndex]
            let item = targetPlacedSubview.item

            // One cache item may appear only once in a committed display set.
            // Keep the first occurrence so displayIndex remains unambiguous.
            if item.commitSeed == placementSeed {
                if !item.hasWarned {
                    item.hasWarned = true
                    print(
                        "\(String(reflecting: type(of: self).viewType)): the ID " +
                        "\(item.id.canonicalID) occurs multiple times within " +
                        "the collection, this will give undefined results!"
                    )
                }
                placedSubviews.remove(at: newIndex)
                continue
            }

            let state = item._state.value
            if state.phase != .identity {
                if item.displayIndex == nil {
                    if !isFirstCommit {
                        let initial = initialPlacement(
                            newIndex: newIndex,
                            newPlacedSubviews: placedSubviews,
                            oldPlacedSubviews: oldPlacedSubviews,
                            wasInsertedToSubviews: state.enableTransitions,
                            context: context
                        )
                        placedSubviews[newIndex].placement = initial
                        var oldPlacedSubview = targetPlacedSubview
                        oldPlacedSubview.placement = initial
                        oldPlacedSubviews.append(oldPlacedSubview)
                        needsPhaseUpdate = true
                    }
                } else {
                    needsPhaseUpdate = true
                }
            }

            item.displayIndex = newIndex
            item.usedSeed = lru.usedSeed
            item.commitSeed = placementSeed
            item.placement = targetPlacedSubview.placement

            minPlacedIndex = minPlacedIndex.map {
                min($0, targetPlacedSubview.index)
            } ?? targetPlacedSubview.index
            maxPlacedIndex = maxPlacedIndex.map {
                max($0, targetPlacedSubview.index)
            } ?? targetPlacedSubview.index
            newIndex += 1
        }

        updatePlacedIndices(
            minIndex: minPlacedIndex,
            maxIndex: maxPlacedIndex,
            containingSize: containingSize
        )

        for item in items.values where item.commitSeed != placementSeed {
            guard let previousPlacement = item.placement,
                  let oldIndex = item.displayIndex else {
                continue
            }

            let state = item._state.value
            var displayedPlacement = previousPlacement
            if state.phase != .didDisappear {
                let transaction = currentListTransaction()
                if transaction.fromScrollView {
                    // Scroll-driven eviction has no retained transition. Its
                    // prefetch generation alone owns the offscreen item.
                    item.displayIndex = nil
                    item.prefetchPhase =
                        supportsViewHierarchyPrefetching
                        ? .pendingRemoval
                        : .notPrefetching
                    item.removalTransactionSeed = lru.transactionSeed
                    item.placement = nil
                    continue
                }

                let itemList = item._list.attribute?.value
                let wasRemoved = itemList?.edit(
                    forID: item.id,
                    since: lru.lastTransactionID
                ) == .removed
                displayedPlacement = finalPlacement(
                    oldIndex: oldIndex,
                    oldPlacedSubviews: oldPlacedSubviews,
                    newPlacedSubviews: placedSubviews,
                    wasRemovedFromSubviews: wasRemoved,
                    context: context
                )
                item.willEnableTransitions =
                    item.transitionType != nil && wasRemoved
                item.willAnimateRemoval = true
                item.removedSeed = placementSeed
                retargetedRemovalItems.append(item)
                needsPhaseUpdate = true
            } else if item.willAnimateRemoval {
                item.willAnimateRemoval = false
                needsPhaseUpdate = true
            } else if item.animationCount == 0 {
                needsPhaseUpdate = true
            }

            item.displayIndex = placedSubviews.count
            item.usedSeed = lru.usedSeed
            placedSubviews.append(
                _LazyLayout_PlacedSubview(
                    item: item,
                    placement: displayedPlacement,
                    index: -1
                )
            )
            appendedStaleItem = true
        }

        // The outgoing item is displayed at its previous placement while its
        // cache stores the final target consumed by the transition geometry.
        for item in retargetedRemovalItems {
            guard let displayIndex = item.displayIndex,
                  placedSubviews.indices.contains(displayIndex),
                  let previousPlacement = item.placement else {
                fatalError("Retargeted lazy removal lost its committed placement.")
            }
            let finalPlacement = placedSubviews[displayIndex].placement
            placedSubviews[displayIndex].placement = previousPlacement
            item.placement = finalPlacement
        }

        if hasDepth || hasSections || appendedStaleItem {
            sortForDisplay(&placedSubviews)
        }

        if needsPhaseUpdate {
            viewGraph?.continueTransaction(
                LazyLayoutCacheItem.AllItemsPhaseMutation(cache: self)
            )
        } else if !wasCancelled && !placedSubviews.isEmpty {
            isFirstCommit = false
        }
    }

    /// Updates the visible index range and its rolling density estimate.
    private func updatePlacedIndices(
        minIndex: Int?,
        maxIndex: Int?,
        containingSize: CGSize
    ) {
        if self.containingSize != containingSize {
            averagePlacedCount = (0, 0)
        }

        placedIndices = (minIndex ?? -1, maxIndex ?? -1)
        if let minIndex, let maxIndex {
            let nextCount = averagePlacedCount.count + 1
            averagePlacedCount.value =
                (
                    averagePlacedCount.value *
                    Double(averagePlacedCount.count) +
                    Double(maxIndex - minIndex)
                ) / Double(nextCount)
            averagePlacedCount.count = nextCount
        }
        self.containingSize = containingSize
    }

    /// Orders committed display items by depth, section role, and removal age.
    private func sortForDisplay(
        _ placedSubviews: inout [_LazyLayout_PlacedSubview]
    ) {
        placedSubviews.sort { lhs, rhs in
            let lhsItem = lhs.item
            let rhsItem = rhs.item
            if lhsItem.zIndex != rhsItem.zIndex {
                return lhsItem.zIndex < rhsItem.zIndex
            }

            let lhsIsSectionBoundary =
                lhsItem.section.isHeader || lhsItem.section.isFooter
            let rhsIsSectionBoundary =
                rhsItem.section.isHeader || rhsItem.section.isFooter
            if lhsIsSectionBoundary != rhsIsSectionBoundary {
                return !lhsIsSectionBoundary
            }

            if lhsItem.removedSeed != rhsItem.removedSeed {
                return lhsItem.removedSeed < rhsItem.removedSeed
            }

            guard let lhsIndex = lhsItem.displayIndex,
                  let rhsIndex = rhsItem.displayIndex else {
                fatalError("Displayed lazy items require display indices.")
            }
            return lhsIndex < rhsIndex
        }

        for index in placedSubviews.indices {
            placedSubviews[index].item.displayIndex = index
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
            )
        }
    }

    func reusedItem(
        data: _LazyLayout_Subview.Data,
        anyTransition transition: AnyTransition?
    ) -> LazyLayoutCacheItem? {
        let id = data.id.canonicalID
        let reuseIdentifier = data.id.reuseIdentifier
        let candidates = lru.updatedItems(Array(items.values))
        guard let item = candidates.first(where: {
            isReusableCandidateBase(
                $0,
                for: id,
                reuseIdentifier: reuseIdentifier
            ) && hasCompatibleTransition($0, transition: transition)
        }) else {
            return nil
        }
        let oldID = item.id.canonicalID
        refresh(item, data: data, transition: transition)
        let newID = item.id.canonicalID
        if oldID != newID {
            items.removeValue(forKey: oldID)
            if let children = childCaches.removeValue(forKey: oldID) {
                childCaches[newID] = children
                childCacheSeeds[children.seed] = newID
            }
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
        guard isReusableCandidateBase(
            item,
            for: id,
            reuseIdentifier: reuseIdentifier
        ) else { return false }
        switch (item.transitionType, transitionType) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        default:
            return false
        }
    }

    private func isReusableCandidateBase(
        _ item: LazyLayoutCacheItem,
        for id: _ViewList_ID.Canonical,
        reuseIdentifier: Int
    ) -> Bool {
        guard item.id.canonicalID != id,
              item.reuseIdentifier == reuseIdentifier,
              item.parentingPhase != .inserted else {
            return false
        }
        let insertionAge = Int32(bitPattern: lru.transactionSeed &- item.insertionTransactionSeed)
        return insertionAge >= 1
            && item.placementSeed != placementSeed
            && item.displayIndex == nil
    }

    private func hasCompatibleTransition(
        _ item: LazyLayoutCacheItem,
        transition: AnyTransition?
    ) -> Bool {
        guard let transition else {
            return item.transitionType == nil
        }
        var comparison = CompareTransitionType(
            existingType: item.transitionType,
            compatibleTypes: false
        )
        transition.visitType(&comparison)
        return comparison.compatibleTypes
    }

    func prefetchOutputs() -> _LazyLayout_PrefetchResult {
        var result = _LazyLayout_PrefetchResult.none
        for _ in prefetchDisplayListOutputs() {
            result.advanceToSome()
        }
        return result
    }

    func prefetchDisplayListOutputs() -> [_ViewOutputs] {
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
        advancePrefetchPhaseForDisplayWithNotifyFlag(item: item).result
    }

    func advancePrefetchPhaseForDisplayWithNotifyFlag(item: LazyLayoutCacheItem) -> LazyPrefetchPhaseAdvance {
        var didNotify = false
        func notify() {
            didNotify = true
            signalPrefetch()
        }

        guard supportsViewHierarchyPrefetching else {
            return LazyPrefetchPhaseAdvance(result: .none, didNotify: didNotify)
        }
        switch item.prefetchPhase {
        case .pendingDisplay:
            guard hasChildPrefetchPhaseWork(item: item) else {
                return LazyPrefetchPhaseAdvance(result: .none, didNotify: didNotify)
            }
            notify()
            return LazyPrefetchPhaseAdvance(
                result: advanceChildPrefetchPhase(item: item) ? .some : .all,
                didNotify: didNotify
            )
        case .prefetching:
            item.prefetchPhase = .pendingDisplay
            notify()
            return LazyPrefetchPhaseAdvance(
                result: setupChildPrefetchPhase(item: item) ? .some : .all,
                didNotify: didNotify
            )
        default:
            return LazyPrefetchPhaseAdvance(result: .none, didNotify: didNotify)
        }
    }

    func advancePrefetchPhaseForRemoval() -> _LazyLayout_PrefetchResult {
        advancePrefetchPhaseForRemovalWithNotifyFlag().result
    }

    func advancePrefetchPhaseForRemovalWithNotifyFlag() -> LazyPrefetchPhaseAdvance {
        guard supportsViewHierarchyPrefetching else {
            return LazyPrefetchPhaseAdvance(result: .none, didNotify: false)
        }
        var didCollect = false
        for item in items.values where item.prefetchPhase == .pendingRemoval {
            item.prefetchPhase = .notPrefetching
            didCollect = true
        }
        if didCollect {
            signalPrefetch()
        }
        return LazyPrefetchPhaseAdvance(result: .all, didNotify: didCollect)
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
        let signal = _weakPrefetchSignal.base
        Update.enqueueAction { [weak viewGraph] in
            guard let viewGraph else { return }
            viewGraph.data.withCurrent {
                let graph = viewGraph.graph
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

    /// Returns the stable seed used when descendants register a nested cache
    /// under this materialized item.
    private func childCacheSeed(id: _ViewList_ID.Canonical) -> Int {
        if let children = childCaches[id] {
            return children.seed
        }
        let seed = nextChildCacheSeed
        childCacheSeeds[seed] = id
        nextChildCacheSeed &+= 1
        return seed
    }

    /// Attaches a nested cache to the item identified by its previously issued
    /// seed without introducing a strong parent-child ownership cycle.
    fileprivate func addChildCache(_ child: LazyLayoutViewCache, seed: Int) {
        guard let id = childCacheSeeds[seed] else { return }
        var children = childCaches[id] ?? LazyLayoutCacheChildren(seed: seed)
        children.children.append(WeakBox(child))
        childCaches[id] = children
        child.parentCache = self
    }

    private func liveChildCaches(for item: LazyLayoutCacheItem) -> [LazyLayoutViewCache] {
        guard let children = childCaches[item.id.canonicalID] else { return [] }
        return children.children.compactMap(\.base)
    }

    private func anyTransition(data: _LazyLayout_Subview.Data) -> AnyTransition? {
        guard data.traits[CanTransitionTraitKey.self] else { return nil }
        return data.traits[TransitionTraitKey.self]
    }

    /// Builds the graph-node bundle owned by one materialized lazy child.
    private func makeSubviewOutputs(
        inputs parentInputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        data: _LazyLayout_Subview.Data,
        anyTransition transition: AnyTransition?
    ) -> SubviewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("LazyLayoutViewCache.makeSubviewOutputs requires an active AttributeGraph.")
        }

        let parentSeed = childCacheSeed(id: data.id.canonicalID)
        var result = SubviewOutputs()
        let outputs = data.elements.makeOneElement(
            at: data.id.index,
            inputs: parentInputs,
            indirectMap: indirectMap
        ) { elementInputs, makeView in
            var elementInputs = elementInputs
            elementInputs.base.merge(parentInputs.base, ignoringPhase: true)

            let state = graph.makeInput(
                value: LazyLayoutCacheItem.State(
                    phase: .willAppear,
                    isRemoved: true
                )
            )
            let geometry: Attribute<ViewGeometry> = graph.makeRule(
                LazyViewGeometry(
                    _subviews: _placedSubviews,
                    _size: self.inputs.size,
                    _parentPosition: self.inputs.position,
                    _layoutDirection: _layoutDirection,
                    cache: self,
                    item: nil
                )
            )
            let phase = lazyViewPhase(
                basePhase: parentInputs.base.phase,
                elementPhase: elementInputs.base.phase,
                state: state,
                in: graph
            )
            let displayListWrapper: Attribute<HiddenForReuseEffect> =
                graph.makeStatefulRule(
                    LazyDisplayListWrapper(
                        item: nil,
                        isRemoved: false,
                        wasHiddenForReuse: false
                    )
                )

            // Geometry is projected from a single node so origin and size
            // cannot observe different placement generations.
            elementInputs.position = geometry.origin()
            elementInputs.size = geometry.size()
            elementInputs.base.phase = phase
            elementInputs.base[LazyLayoutReuseIdleInput.self] = Optional<Int>.none
            elementInputs.base[_GraphInputs.LazyLayoutCacheParentKey.self] =
                LazyLayoutCacheParent(cache: self, seed: parentSeed)

            let transaction: Attribute<Transaction> = graph.makeStatefulRule(
                LazyTransaction(
                    transaction: elementInputs.base.transaction,
                    state: state,
                    item: nil
                )
            )
            elementInputs.base.transaction = transaction

            var transitionAttribute: AGAttribute?
            var transitionType: Any.Type?
            let makeBody: (_Graph, _ViewInputs) -> _ViewOutputs = { _, bodyInputs in
                guard let transition else {
                    return makeView(bodyInputs)
                }
                var visitor = MakeSubviewTransition(
                    _state: state,
                    inputs: bodyInputs,
                    id: data.id,
                    makeElt: makeView,
                    outputs: nil,
                    transition: nil,
                    transitionType: nil
                )
                transition.visit(&visitor)
                transitionAttribute = visitor.transition
                transitionType = visitor.transitionType
                return visitor.outputs ?? _ViewOutputs()
            }

            let viewOutputs: _ViewOutputs
            if elementInputs.preferences.keys.contains(DisplayList.Key.self) {
                viewOutputs = _RendererEffectSupport.makeView(
                    effect: _GraphValue(_attribute: displayListWrapper),
                    inputs: elementInputs,
                    body: makeBody
                )
            } else {
                viewOutputs = makeBody(_Graph(), elementInputs)
            }

            result = SubviewOutputs(
                state: state,
                geometry: geometry,
                phase: phase,
                displayListWrapper: displayListWrapper,
                transaction: transaction,
                transition: transitionAttribute,
                transitionType: transitionType,
                viewOutputs: viewOutputs
            )
            return viewOutputs
        }
        result.viewOutputs = outputs ?? _ViewOutputs()
        return result
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
        let materialized = AGSubgraph.withCurrent(subgraph) {
            makeSubviewOutputs(
                inputs: childInputs,
                indirectMap: nil,
                data: data,
                anyTransition: transition
            )
        }
        guard let state = materialized.state else {
            fatalError("Lazy child materialization did not produce an item state.")
        }

        let item = LazyLayoutCacheItem(
            cache: self,
            subgraph: subgraph,
            outputs: materialized.viewOutputs,
            state: state,
            list: data.list.map(OptionalAttribute.init) ?? OptionalAttribute<any ViewList>(),
            elements: data.elements,
            elementIndex: data.id.index,
            id: data.id,
            reuseIdentifier: data.id.reuseIdentifier,
            section: data.section,
            transition: materialized.transition,
            transitionType: materialized.transitionType,
            zIndex: data.traits[ZIndexTraitKey.self]
        )
        if let transaction = materialized.transaction {
            graph.mutateStatefulRule(transaction.identifier, as: LazyTransaction.self) { rule in
                rule.item = item
            }
        }
        if let geometry = materialized.geometry {
            graph.mutateRule(
                geometry.identifier,
                as: LazyViewGeometry.self,
                invalidating: true
            ) { geometry in
                geometry.item = item
            }
        }
        if let displayListWrapper = materialized.displayListWrapper {
            graph.mutateStatefulRule(
                displayListWrapper.identifier,
                as: LazyDisplayListWrapper.self,
                invalidating: true
            ) { wrapper in
                wrapper.item = item
            }
        }
        if let transitionAttribute = materialized.transition,
           let transition {
            var visitor = UpdateSubviewTransition(
                transition: transitionAttribute,
                item: item
            )
            transition.visitType(&visitor)
        }
        item.releaseElements = release
        addItem(item, reset: false)
        return item
    }

    private func refresh(
        _ item: LazyLayoutCacheItem,
        data: _LazyLayout_Subview.Data,
        transition: AnyTransition?
    ) {
        item.elements = data.elements
        item.elementIndex = data.id.index
        item._list = data.list.map(OptionalAttribute.init) ?? OptionalAttribute<any ViewList>()
        item.id = data.id
        item.reuseIdentifier = data.id.reuseIdentifier
        item.section = data.section
        item.zIndex = data.traits[ZIndexTraitKey.self]
        hasSections = hasSections || data.section.id != nil
        hasDepth = hasDepth || item.zIndex != 0
    }
}

/// Binds the type-erased lazy cache lifecycle to one concrete layout and its
/// opaque user-defined `Cache` value.
final class _LazyLayoutViewCache<LayoutType: LazyLayout>: LazyLayoutViewCache {
    var _layout: Attribute<LayoutType>
    var cacheState: LayoutType.Cache

    override class var viewType: Any.Type { LayoutType.self }

    init(
        layout: Attribute<LayoutType>,
        cacheState: LayoutType.Cache,
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

        // A nested cache registers through the seed issued while its owning
        // item was materialized. The seed survives item reuse even when the
        // canonical item ID changes.
        let parent = inputs.base[_GraphInputs.LazyLayoutCacheParentKey.self]
        if parent.seed != -1, let parentCache = parent.cache {
            parentCache.addChildCache(self, seed: parent.seed)
        }
        if let maxIdle = inputs.base[LazyLayoutReuseIdleInput.self] {
            lru.maxIdle = maxIdle
        }
    }

    override var supportsPrefetching: Bool {
        guard AGSubgraphIsValid(parentSubgraph) else { return false }
        return !LayoutType.layoutProperties.axes.intersection(_nearestScrollableAxes.value).isEmpty
    }

    override func reset() {
        cacheState = LayoutType.initialCache
        super.reset()
    }

    override func copyCacheState<L: LazyLayout>(type: L.Type) -> L.Cache {
        guard ObjectIdentifier(type) == ObjectIdentifier(LayoutType.self) else {
            fatalError(
                "Lazy layout cache type mismatch: expected \(LayoutType.self), got \(L.self)."
            )
        }

        // The metatype check above proves that both associated Cache types
        // are identical. Rebinding is needed only because this virtual method
        // crosses the type-erased base-class boundary.
        return withUnsafePointer(to: cacheState) { pointer in
            UnsafeRawPointer(pointer)
                .assumingMemoryBound(to: L.Cache.self)
                .pointee
        }
    }

    override func initialPlacement(
        newIndex: Int,
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasInsertedToSubviews: Bool,
        context: AnyRuleContext
    ) -> _Placement {
        withPlacementData { layout, placementContext in
            let cacheState = copyCacheState(type: LayoutType.self)
            let subviews = subviews(context: placementContext.base.ruleContext)
            return layout.initialPlacement(
                newIndex: newIndex,
                newPlacedSubviews: newPlacedSubviews,
                oldPlacedSubviews: oldPlacedSubviews,
                wasInsertedToSubviews: wasInsertedToSubviews,
                context: placementContext,
                subviews: subviews,
                cache: cacheState
            )
        }
    }

    override func finalPlacement(
        oldIndex: Int,
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasRemovedFromSubviews: Bool,
        context: AnyRuleContext
    ) -> _Placement {
        withPlacementData { layout, placementContext in
            let cacheState = copyCacheState(type: LayoutType.self)
            let subviews = subviews(context: placementContext.base.ruleContext)
            return layout.finalPlacement(
                oldIndex: oldIndex,
                oldPlacedSubviews: oldPlacedSubviews,
                newPlacedSubviews: newPlacedSubviews,
                wasRemovedFromSubviews: wasRemovedFromSubviews,
                context: placementContext,
                subviews: subviews,
                cache: cacheState
            )
        }
    }

    /// Reconstructs the concrete layout and placement context for virtual callbacks.
    fileprivate func withPlacementData<Result>(
        _ body: (LayoutType, _LazyLayout_PlacementContext) -> Result
    ) -> Result {
        // The placed-subviews node is the stable dependency owner for both
        // rule-driven placement and imperative target lookup outside evaluation.
        let context = AnyRuleContext(attribute: _placedSubviews.identifier)
        let layout = _layout.value
        let sizingContext = _LazyLayout_SizeAndSpacingContext(
            ruleContext: context,
            owner: context.attribute,
            environment: inputs.base.cachedEnvironment.value.environment,
            containerSize: inputs.containerSize
        )
        let placementContext = _LazyLayout_PlacementContext(
            base: sizingContext,
            position: inputs.position.value,
            size: inputs.size.value,
            transform: inputs.transform.value,
            layoutDirection: _layoutDirection.value,
            pinnedViews: layout.pinnedViews,
            isAccessibilityEnabled: _accessibilityEnabled.value
        )
        return body(layout, placementContext)
    }
}

/// Exposes a concrete lazy cache through the scrollable collection interfaces.
struct LazyScrollable<LayoutType: LazyLayout>: ScrollableCollection, ScrollableContainer {
    var position: WeakAttribute<CGPoint>
    var transform: WeakAttribute<ViewTransform>
    var _parent: WeakAttribute<any Scrollable>
    var _children: WeakAttribute<[any Scrollable]>
    var cache: _LazyLayoutViewCache<LayoutType>?

    init(
        position: WeakAttribute<CGPoint>,
        transform: WeakAttribute<ViewTransform>,
        parent: WeakAttribute<any Scrollable>,
        children: WeakAttribute<[any Scrollable]>,
        cache: _LazyLayoutViewCache<LayoutType>?
    ) {
        self.position = position
        self.transform = transform
        self._parent = parent
        self._children = children
        self.cache = cache
    }

    var visibleCollectionViewIDs: [_ViewList_ID.Canonical] {
        placedSubviews.map { $0.id.canonicalID }
    }

    func forEachVisibleSubview(_ body: (ScrollableCollectionSubview, inout Bool) -> Void) {
        let transform = resolvedTransform
        for placedSubview in placedSubviews {
            let frame = placedSubview.frame
            var stop = false
            body(
                ScrollableCollectionSubview(
                    id: placedSubview.id,
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
        guard let source = placedSubviews.first(where: { lazyCollectionID($0.id, matches: id) }) else {
            return nil
        }
        let sourceFrame = navigationFrame(for: source).insetBy(
            dx: -border.width,
            dy: -border.height
        )
        var best: (index: Int, distance: CGFloat)?
        for candidate in placedSubviews {
            guard !lazyCollectionID(candidate.id, matches: id),
                  !candidate.matches(pinnedViews),
                  let distance = navigationDistance(
                    from: sourceFrame,
                    to: navigationFrame(for: candidate),
                    towards: point
                  ) else {
                continue
            }
            if best == nil || distance < best!.distance {
                best = (candidate.index, distance)
            }
        }
        guard let index = best?.index else {
            return nil
        }
        return collectionViewID(at: index)
    }

    static func hasMultipleViewsInAxis(_ axis: Axis) -> Bool {
        switch axis {
        case .horizontal:
            return LayoutType.layoutProperties.multipleViewAxes.contains(.horizontal)
        case .vertical:
            return LayoutType.layoutProperties.multipleViewAxes.contains(.vertical)
        }
    }

    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int? {
        cache?._list.value.firstOffset(of: id)
    }

    func applyCollectionViewIDs(
        from index: inout Int,
        to body: (_ViewList_ID.Canonical, inout Bool) -> Void
    ) -> Bool {
        guard let cache else { return false }
        var emitted = false
        let completed = cache._list.value.applyIDs(from: &index, listAttribute: cache._list) { id in
            emitted = true
            var stop = false
            body(id.canonicalID, &stop)
            return !stop
        }
        return emitted && completed
    }

    func collectionViewID(for subgraph: AGSubgraph) -> _ViewList_ID.Canonical? {
        cache?.item(for: subgraph)?.id.canonicalID
    }

    func scroll(toCollectionViewID id: _ViewList_ID.Canonical, anchor: UnitPoint?) -> Bool {
        guard let cache,
              let attribute = _AGGraph.currentRuleContextAttribute else {
            return false
        }
        let context = AnyRuleContext(attribute: attribute)
        let subviews = cache.subviews(context: context)
        guard let index = subviews.firstIndex(of: id),
              let target = makeTarget(at: index, anchor: anchor) else {
            return false
        }
        return setParentTarget(target)
    }

    var parent: (any Scrollable)? {
        resolvedParent
    }

    var children: [any Scrollable]? {
        value(for: _children)
    }

    func makeTarget<ID: Hashable>(
        for id: ID
    ) -> ((ScrollGeometry, LayoutDirection) -> ScrollTarget?)? {
        guard let cache,
              let index = cache.withPlacementData({ layout, placementContext in
                  let subviews = cache.subviews(
                      context: placementContext.base.ruleContext
                  )
                  return layout.firstIndex(
                      of: id,
                      subviews: subviews,
                      context: placementContext
                  )
              }) else {
            return nil
        }
        let anchor = Transaction.current.scrollTargetAnchor
        return makeTarget(at: index, anchor: anchor)
    }

    static var accessibilityRole: AccessibilityLayoutRole? {
        if let adaptorType = LayoutType.self as? any LazyLayoutAccessibilityRoleProviding.Type {
            return adaptorType.lazyAccessibilityRole
        }
        return LazyLayoutAccessibilityRole.role(for: LayoutType.self)
    }

    var isLazy: Bool {
        true
    }

    private var placedSubviews: [_LazyLayout_PlacedSubview] {
        cache?._placedSubviews.value ?? []
    }

    private var resolvedTransform: ViewTransform {
        var resolved = value(for: transform) ?? ViewTransform()
        if let position = value(for: position) {
            resolved.appendPosition(position)
        }
        return resolved
    }

    private var resolvedParent: (any Scrollable)? {
        value(for: _parent)
    }

    private func collectionViewID(at index: Int) -> _ViewList_ID.Canonical? {
        var offset = index
        var result: _ViewList_ID.Canonical?
        _ = cache?._list.value.applyIDs(from: &offset, listAttribute: cache?._list) { id in
            result = id.canonicalID
            return false
        }
        return result
    }

    private func navigationFrame(for placedSubview: _LazyLayout_PlacedSubview) -> CGRect {
        cache?.targetFrame(for: placedSubview) ?? placedSubview.frame
    }

    private func navigationDistance(
        from source: CGRect,
        to candidate: CGRect,
        towards point: UnitPoint
    ) -> CGFloat? {
        let dx = point.x - 0.5
        let dy = point.y - 0.5
        let epsilon = CGFloat.ulpOfOne

        var primary = CGFloat.zero
        var cross = CGFloat.zero
        if abs(dx) >= abs(dy) {
            if dx > epsilon {
                primary = candidate.minX - source.maxX
            } else if dx < -epsilon {
                primary = source.minX - candidate.maxX
            } else {
                return nil
            }
            cross = candidate.midY - source.midY
        } else {
            if dy > epsilon {
                primary = candidate.minY - source.maxY
            } else if dy < -epsilon {
                primary = source.minY - candidate.maxY
            } else {
                return nil
            }
            cross = candidate.midX - source.midX
        }

        guard primary >= -epsilon else {
            return nil
        }
        return (primary * primary + cross * cross).squareRoot()
    }

    private func value<T>(for weakAttribute: WeakAttribute<T>) -> T? {
        guard let graph = _AGGraph.current,
              weakAttribute.isValid(in: graph) else {
            return nil
        }
        return weakAttribute.toStrong().value
    }

    private func makeTarget(
        at index: Int,
        anchor: UnitPoint?
    ) -> ((ScrollGeometry, LayoutDirection) -> ScrollTarget?)? {
        guard let cache else {
            return nil
        }
        // Resolve placement data when the request is applied so the target
        // uses the cache's current geometry and dependency owner.
        return { _, _ in
            guard var rect = cache.withPlacementData({ layout, placementContext -> CGRect? in
                let subviews = cache.subviews(
                    context: placementContext.base.ruleContext
                )
                let cacheState = cache.copyCacheState(type: LayoutType.self)
                guard var rect = layout.boundingRect(
                    at: index,
                    subviews: subviews,
                    context: placementContext,
                    cache: cacheState
                ) else {
                    return nil
                }
                if cache._layoutDirection.value == .rightToLeft {
                    rect.origin.x = placementContext.size.width - rect.maxX
                }
                return rect
            }),
            var transform = value(for: transform),
            let position = value(for: position) else {
                return nil
            }
            transform.appendPosition(position)
            rect = rect.converted(to: .content, using: transform)
            return ScrollTarget(rect: rect, anchor: anchor)
        }
    }
}

private func lazyCollectionID(
    _ viewID: _ViewList_ID,
    matches target: _ViewList_ID.Canonical
) -> Bool {
    let canonical = viewID.canonicalID
    if canonical == target {
        return true
    }
    if let explicitID = target.explicitID {
        return canonical.explicitID == explicitID || viewID.allExplicitIDs.contains(explicitID)
    }
    guard target.requiresImplicitID else {
        return false
    }
    return canonical.implicitID == target.implicitID
}

private func lazyMinorLength(_ size: CGSize, axis: Axis) -> CGFloat {
    switch axis {
    case .horizontal:
        return size.height
    case .vertical:
        return size.width
    }
}

private extension CGRect {
    func midpointDistance(to other: CGRect) -> CGFloat {
        let dx = midX - other.midX
        let dy = midY - other.midY
        return (dx * dx + dy * dy).squareRoot()
    }

    func distance(to point: CGPoint) -> CGFloat {
        let dx = abs(point.x - midX) - width / 2
        let dy = abs(point.y - midY) - height / 2
        if min(dx, dy) > 0 {
            return (dx * dx + dy * dy).squareRoot()
        }
        return max(dx, dy)
    }

    func distance(to other: CGRect, in axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            return abs(midX - other.midX) - (width + other.width) / 2
        case .vertical:
            return abs(midY - other.midY) - (height + other.height) / 2
        }
    }
}

/// Pairs a materialized cache item with its committed placement and list index.
struct _LazyLayout_PlacedSubview {
    var item: LazyLayoutCacheItem
    var placement: _Placement
    var index: Int

    var id: _ViewList_ID {
        item.id
    }

    var size: CGSize {
        let layoutComputer = item.outputs._layoutComputer.attribute?.value ?? .defaultValue
        return layoutComputer.sizeThatFits(_ProposedSize(placement.proposedSize))
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

private extension Array where Element == _LazyLayout_PlacedSubview {
    func motionVectors(
        closestTo targetIndex: Int,
        in destination: [_LazyLayout_PlacedSubview],
        avoiding avoidanceRect: CGRect,
        distance: (CGRect, CGRect) -> CGFloat
    ) -> (translation: CGSize, scale: CGSize)? {
        var destinationIndices: [_ViewList_ID.Canonical: Int] = [:]
        for (index, subview) in destination.enumerated() {
            // Later entries deliberately replace earlier duplicate canonical
            // identities, matching the destination array's final occurrence.
            destinationIndices[subview.id.canonicalID] = index
        }

        let targetFrame = self[targetIndex].frame
        var selectedDistance: CGFloat?
        var selectedVector: (translation: CGSize, scale: CGSize)?

        for sourceSubview in self {
            guard let destinationIndex =
                    destinationIndices[sourceSubview.id.canonicalID] else {
                continue
            }
            let sourceFrame = sourceSubview.frame
            guard !sourceFrame.isEmpty else {
                continue
            }
            let destinationFrame = destination[destinationIndex].frame
            guard !destinationFrame.isEmpty else {
                continue
            }

            let translation = CGSize(
                width: destinationFrame.origin.x - sourceFrame.origin.x,
                height: destinationFrame.origin.y - sourceFrame.origin.y
            )
            let scale = CGSize(
                width: destinationFrame.width / sourceFrame.width,
                height: destinationFrame.height / sourceFrame.height
            )
            var projectedTarget = targetFrame
            projectedTarget.origin.x += translation.width
            projectedTarget.origin.y += translation.height
            projectedTarget.size.width =
                targetFrame.width == 0 ? 0 : targetFrame.width * scale.width
            projectedTarget.size.height =
                targetFrame.height == 0 ? 0 : targetFrame.height * scale.height
            // A surviving neighbor is usable only when its transform predicts
            // that the transition target remains outside the live viewport.
            guard projectedTarget.intersection(avoidanceRect).isEmpty else {
                continue
            }

            let candidateDistance = distance(targetFrame, sourceFrame)
            if let selectedDistance, candidateDistance >= selectedDistance {
                continue
            }
            selectedDistance = candidateDistance
            selectedVector = (translation, scale)
        }
        return selectedVector
    }

    func externalPlacement(
        of index: Int,
        avoiding avoidanceRect: CGRect,
        in axis: Axis
    ) -> _Placement {
        var placement = self[index].placement
        let dimension = placement.proposedSize_[axis] ?? 10
        let lowerBound: CGFloat
        let upperBound: CGFloat
        let anchor: CGFloat
        let oldPosition: CGFloat
        switch axis {
        case .horizontal:
            lowerBound = avoidanceRect.minX
            upperBound = avoidanceRect.maxX
            anchor = placement.anchor.x
            oldPosition = placement.anchorPosition.x
        case .vertical:
            lowerBound = avoidanceRect.minY
            upperBound = avoidanceRect.maxY
            anchor = placement.anchor.y
            oldPosition = placement.anchorPosition.y
        }
        // Move forward by at least one proposed length, or beyond one complete
        // avoidance span when that lies farther away.
        let newPosition = Swift.max(
            oldPosition + dimension,
            upperBound + (upperBound - lowerBound) + anchor * dimension
        )
        switch axis {
        case .horizontal:
            placement.anchorPosition.x = newPosition
        case .vertical:
            placement.anchorPosition.y = newPosition
        }
        return placement
    }
}

/// Groups the placed header, content, and footer entries of one pinnable section.
private struct PinnedLazySection {
    var horizontalBounds: ClosedRange<CGFloat>
    var verticalBounds: ClosedRange<CGFloat>
    var headerIndex: Int?
    var footerIndex: Int?
    var headerFrame: CGRect?
    var footerFrame: CGRect?
    private var horizontalBodyPositions: [CGFloat]
    private var verticalBodyPositions: [CGFloat]

    init(frame: CGRect) {
        self.horizontalBounds = frame.minX...frame.maxX
        self.verticalBounds = frame.minY...frame.maxY
        self.headerIndex = nil
        self.footerIndex = nil
        self.headerFrame = nil
        self.footerFrame = nil
        self.horizontalBodyPositions = []
        self.verticalBodyPositions = []
    }

    mutating func include(_ frame: CGRect) {
        horizontalBounds = min(horizontalBounds.lowerBound, frame.minX)...max(horizontalBounds.upperBound, frame.maxX)
        verticalBounds = min(verticalBounds.lowerBound, frame.minY)...max(verticalBounds.upperBound, frame.maxY)
    }

    mutating func recordBody(_ frame: CGRect) {
        Self.appendUnique(frame.minX, to: &horizontalBodyPositions)
        Self.appendUnique(frame.minY, to: &verticalBodyPositions)
    }

    func bounds(for axis: Axis) -> ClosedRange<CGFloat> {
        switch axis {
        case .horizontal:
            return horizontalBounds
        case .vertical:
            return verticalBounds
        }
    }

    func bodyMajorGroupCount(for axis: Axis) -> Int {
        switch axis {
        case .horizontal:
            return horizontalBodyPositions.count
        case .vertical:
            return verticalBodyPositions.count
        }
    }

    private static func appendUnique(_ position: CGFloat, to positions: inout [CGFloat]) {
        guard !positions.contains(where: { abs($0 - position) < 0.001 }) else {
            return
        }
        positions.append(position)
    }
}

extension Array where Element == _LazyLayout_PlacedSubview {
    mutating func pinSectionHeadersAndFooters(
        geometry: ScrollGeometry,
        layoutDirection: LayoutDirection,
        axes: Axis.Set,
        pinnedViews: PinnedScrollableViews
    ) {
        _ = layoutDirection
        guard !isEmpty,
              !axes.isEmpty,
              !pinnedViews.isEmpty else {
            return
        }

        var sections: [UInt32: PinnedLazySection] = [:]
        for index in indices {
            let sectionID = self[index].item.section.id ?? UInt32(self[index].index)
            let frame = self[index].frame
            var section = sections[sectionID] ?? PinnedLazySection(frame: frame)
            section.include(frame)
            if self[index].isHeader {
                section.headerIndex = index
                section.headerFrame = frame
            } else if self[index].isFooter {
                section.footerIndex = index
                section.footerFrame = frame
            } else {
                section.recordBody(frame)
            }
            sections[sectionID] = section
        }

        for section in sections.values {
            commitPinnedSection(
                section,
                geometry: geometry,
                axes: axes,
                pinnedViews: pinnedViews
            )
        }
        adjustShortSectionHeaders(
            in: sections,
            geometry: geometry,
            axes: axes,
            pinnedViews: pinnedViews
        )
        pushMiddleHeadersBeforePinnedNextHeader(
            in: sections,
            geometry: geometry,
            axes: axes,
            pinnedViews: pinnedViews
        )
        removeHeadersCoveredByPinnedNextHeader(
            in: sections,
            geometry: geometry,
            axes: axes,
            pinnedViews: pinnedViews
        )
    }

    private mutating func commitPinnedSection(
        _ section: PinnedLazySection,
        geometry: ScrollGeometry,
        axes: Axis.Set,
        pinnedViews: PinnedScrollableViews
    ) {
        if axes.contains(.vertical) {
            if pinnedViews.contains(.sectionHeaders),
               let index = section.headerIndex {
                pinHeader(at: index, section: section, visible: geometry.visibleRect.minY...geometry.visibleRect.maxY, axis: .vertical)
            }
            if pinnedViews.contains(.sectionFooters),
               let index = section.footerIndex {
                pinFooter(at: index, section: section, visible: geometry.visibleRect.minY...geometry.visibleRect.maxY, axis: .vertical)
            }
        }

        if axes.contains(.horizontal) {
            if pinnedViews.contains(.sectionHeaders),
               let index = section.headerIndex {
                pinHeader(at: index, section: section, visible: geometry.visibleRect.minX...geometry.visibleRect.maxX, axis: .horizontal)
            }
            if pinnedViews.contains(.sectionFooters),
               let index = section.footerIndex {
                pinFooter(at: index, section: section, visible: geometry.visibleRect.minX...geometry.visibleRect.maxX, axis: .horizontal)
            }
        }
    }

    private mutating func pinHeader(
        at index: Int,
        section: PinnedLazySection,
        visible: ClosedRange<CGFloat>,
        axis: Axis
    ) {
        let size = majorSize(of: self[index], axis: axis)
        let anchor = majorAnchor(of: self[index], axis: axis)
        let anchorOffset = size * anchor
        let lower = visible.lowerBound + anchorOffset
        setMajorPosition(
            Swift.max(majorPosition(of: self[index], axis: axis), lower),
            at: index,
            axis: axis
        )
    }

    private mutating func pinFooter(
        at index: Int,
        section: PinnedLazySection,
        visible: ClosedRange<CGFloat>,
        axis: Axis
    ) {
        let size = majorSize(of: self[index], axis: axis)
        let anchor = majorAnchor(of: self[index], axis: axis)
        let anchorOffset = size * anchor
        let bounds = section.bounds(for: axis)
        let lower = bounds.lowerBound + anchorOffset
        let upper = visible.upperBound - size + anchorOffset
        setMajorPosition(
            Swift.max(Swift.min(majorPosition(of: self[index], axis: axis), upper), lower),
            at: index,
            axis: axis
        )
    }

    private func majorSize(of subview: _LazyLayout_PlacedSubview, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            return subview.size.width
        case .vertical:
            return subview.size.height
        }
    }

    private func majorAnchor(of subview: _LazyLayout_PlacedSubview, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            return subview.placement.anchor.x
        case .vertical:
            return subview.placement.anchor.y
        }
    }

    private func majorPosition(of subview: _LazyLayout_PlacedSubview, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            return subview.placement.anchorPosition.x
        case .vertical:
            return subview.placement.anchorPosition.y
        }
    }

    private mutating func setMajorPosition(_ value: CGFloat, at index: Int, axis: Axis) {
        switch axis {
        case .horizontal:
            self[index].placement.anchorPosition.x = value
        case .vertical:
            self[index].placement.anchorPosition.y = value
        }
    }

    private mutating func adjustShortSectionHeaders(
        in sections: [UInt32: PinnedLazySection],
        geometry: ScrollGeometry,
        axes: Axis.Set,
        pinnedViews: PinnedScrollableViews
    ) {
        guard pinnedViews.contains(.sectionHeaders) else {
            return
        }

        if axes.contains(.vertical) {
            adjustShortSectionHeaders(
                in: sections,
                visible: geometry.visibleRect.minY...geometry.visibleRect.maxY,
                axis: .vertical
            )
        }
        if axes.contains(.horizontal) {
            adjustShortSectionHeaders(
                in: sections,
                visible: geometry.visibleRect.minX...geometry.visibleRect.maxX,
                axis: .horizontal
            )
        }
    }

    private mutating func adjustShortSectionHeaders(
        in sections: [UInt32: PinnedLazySection],
        visible: ClosedRange<CGFloat>,
        axis: Axis
    ) {
        let headers = orderedPinnedHeaders(in: sections, axis: axis)
        guard headers.count > 1 else {
            return
        }

        for offset in headers.indices.dropFirst() {
            let header = headers[offset]
            guard indices.contains(header.index),
                  isShortSectionHeader(header) else {
                continue
            }

            let size = majorSize(of: self[header.index], axis: axis)
            let position = visible.lowerBound <= header.position + size + 0.001
                ? header.position
                : -size
            setMajorPosition(position, at: header.index, axis: axis)
        }
    }

    private mutating func pushMiddleHeadersBeforePinnedNextHeader(
        in sections: [UInt32: PinnedLazySection],
        geometry: ScrollGeometry,
        axes: Axis.Set,
        pinnedViews: PinnedScrollableViews
    ) {
        guard pinnedViews.contains(.sectionHeaders) else {
            return
        }

        if axes.contains(.vertical) {
            pushMiddleHeadersBeforePinnedNextHeader(
                in: sections,
                visibleLowerBound: geometry.visibleRect.minY,
                axis: .vertical
            )
        }
        if axes.contains(.horizontal) {
            pushMiddleHeadersBeforePinnedNextHeader(
                in: sections,
                visibleLowerBound: geometry.visibleRect.minX,
                axis: .horizontal
            )
        }
    }

    private mutating func pushMiddleHeadersBeforePinnedNextHeader(
        in sections: [UInt32: PinnedLazySection],
        visibleLowerBound: CGFloat,
        axis: Axis
    ) {
        let headers = orderedPinnedHeaders(in: sections, axis: axis)
        guard headers.count > 2 else {
            return
        }

        for nextOffset in headers.indices.dropFirst().dropFirst()
            where headers[nextOffset].position >= visibleLowerBound - 0.001 {
            let previous = headers[headers.index(before: nextOffset)]
            let next = headers[nextOffset]
            guard indices.contains(previous.index) else {
                continue
            }
            let upper = next.position - majorSize(of: self[previous.index], axis: axis)
            setMajorPosition(
                Swift.min(majorPosition(of: self[previous.index], axis: axis), upper),
                at: previous.index,
                axis: axis
            )
        }
    }

    private mutating func removeHeadersCoveredByPinnedNextHeader(
        in sections: [UInt32: PinnedLazySection],
        geometry: ScrollGeometry,
        axes: Axis.Set,
        pinnedViews: PinnedScrollableViews
    ) {
        guard pinnedViews.contains(.sectionHeaders) else {
            return
        }

        var indexesToRemove = Set<Int>()
        if axes.contains(.vertical) {
            collectHeadersCoveredByPinnedNextHeader(
                in: sections,
                visible: geometry.visibleRect.minY...geometry.visibleRect.maxY,
                axis: .vertical,
                preserveHeadersWithPinnedFooters: pinnedViews.contains(.sectionFooters),
                indexesToRemove: &indexesToRemove
            )
        }
        if axes.contains(.horizontal) {
            collectHeadersCoveredByPinnedNextHeader(
                in: sections,
                visible: geometry.visibleRect.minX...geometry.visibleRect.maxX,
                axis: .horizontal,
                preserveHeadersWithPinnedFooters: pinnedViews.contains(.sectionFooters),
                indexesToRemove: &indexesToRemove
            )
        }

        for index in indexesToRemove.sorted(by: >) where indices.contains(index) {
            remove(at: index)
        }
    }

    private func collectHeadersCoveredByPinnedNextHeader(
        in sections: [UInt32: PinnedLazySection],
        visible: ClosedRange<CGFloat>,
        axis: Axis,
        preserveHeadersWithPinnedFooters: Bool,
        indexesToRemove: inout Set<Int>
    ) {
        let headers = orderedPinnedHeaders(in: sections, axis: axis)
        guard headers.count > 1 else {
            return
        }

        for nextOffset in headers.indices.dropFirst()
            where headers[nextOffset].position <= visible.lowerBound + 0.001 {
            let removalEnd = nextOffset == headers.index(after: headers.startIndex)
                ? nextOffset
                : headers.index(before: nextOffset)
            for previousOffset in headers.startIndex..<removalEnd {
                if !isPreservedByPinnedFooter(
                    headers[previousOffset],
                    visibleLowerBound: visible.lowerBound,
                    enabled: preserveHeadersWithPinnedFooters
                ) {
                    indexesToRemove.insert(headers[previousOffset].index)
                }
            }
            let previousOffset = headers.index(before: nextOffset)
            if previousOffset != headers.startIndex,
               isShortSectionHeader(headers[previousOffset]),
               !isPreservedByPinnedFooter(
                   headers[previousOffset],
                   visibleLowerBound: visible.lowerBound,
                   enabled: preserveHeadersWithPinnedFooters
               ) {
                indexesToRemove.insert(headers[previousOffset].index)
            }
        }
    }

    private func orderedPinnedHeaders(
        in sections: [UInt32: PinnedLazySection],
        axis: Axis
    ) -> [(index: Int, position: CGFloat, sectionUpperBound: CGFloat, bodyMajorGroupCount: Int, footerUpperBound: CGFloat?)] {
        sections.values.compactMap { section -> (index: Int, position: CGFloat, sectionUpperBound: CGFloat, bodyMajorGroupCount: Int, footerUpperBound: CGFloat?)? in
            guard let index = section.headerIndex,
                  let frame = section.headerFrame else {
                return nil
            }
            let footerUpperBound = section.footerFrame.map { upperBound(of: $0, axis: axis) }
            return (
                index,
                lowerBound(of: frame, axis: axis),
                section.bounds(for: axis).upperBound,
                section.bodyMajorGroupCount(for: axis),
                footerUpperBound
            )
        }.sorted { lhs, rhs in
            if lhs.position == rhs.position {
                return lhs.index < rhs.index
            }
            return lhs.position < rhs.position
        }
    }

    private func isShortSectionHeader(
        _ header: (index: Int, position: CGFloat, sectionUpperBound: CGFloat, bodyMajorGroupCount: Int, footerUpperBound: CGFloat?)
    ) -> Bool {
        header.bodyMajorGroupCount <= 2
    }

    private func isPreservedByPinnedFooter(
        _ header: (index: Int, position: CGFloat, sectionUpperBound: CGFloat, bodyMajorGroupCount: Int, footerUpperBound: CGFloat?),
        visibleLowerBound: CGFloat,
        enabled: Bool
    ) -> Bool {
        guard enabled,
              let footerUpperBound = header.footerUpperBound else {
            return false
        }
        return footerUpperBound >= visibleLowerBound - 0.001
    }

    private func lowerBound(of frame: CGRect, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            return frame.minX
        case .vertical:
            return frame.minY
        }
    }

    private func upperBound(of frame: CGRect, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            return frame.maxX
        case .vertical:
            return frame.maxY
        }
    }
}

/// Records one lazily materialized item and the proposal prepared for prefetch.
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

/// Accumulates proposal work emitted by a lazy layout prefetch query.
struct _LazyLayout_ProposedSizes: LazyLayoutNamespace {
    var subviews: [_LazyLayout_ProposedSubview]

    init(subviews: [_LazyLayout_ProposedSubview] = []) {
        self.subviews = subviews
    }
}

/// Stores the resolved cross-axis track count, extent, and layout-specific geometry.
struct MinorProperties<LayoutType: LazyStack>: LazyLayoutNamespace, Equatable {
    var count: Int
    var size: CGFloat
    var geometry: LayoutType.MinorGeometry

    init(count: Int, size: CGFloat, geometry: LayoutType.MinorGeometry) {
        self.count = count
        self.size = size
        self.geometry = geometry
    }
}

/// Couples one major-axis item length with its preceding spacing.
struct LengthSpacing: LazyLayoutNamespace, Equatable {
    var length: CGFloat
    var spacing: CGFloat?
}

/// Maintains rolling length and spacing estimates for unmaterialized stack groups.
struct EstimationCache: LazyLayoutNamespace {
    var lengthToCount: [CGFloat: Int]
    var spacingToCount: [CGFloat: Int]
    var zeroIndices: IndexSet

    init(
        lengthToCount: [CGFloat: Int] = [:],
        spacingToCount: [CGFloat: Int] = [:],
        zeroIndices: IndexSet = IndexSet()
    ) {
        self.lengthToCount = lengthToCount
        self.spacingToCount = spacingToCount
        self.zeroIndices = zeroIndices
    }

    var average: LengthSpacing {
        guard !lengthToCount.isEmpty else {
            return LengthSpacing(length: 0, spacing: nil)
        }
        return LengthSpacing(
            length: Self.weightedAverage(lengthToCount) ?? 0,
            spacing: Self.weightedAverage(spacingToCount)
        )
    }

    mutating func add(length: CGFloat, spacing: CGFloat?, count: Int) {
        lengthToCount[length, default: 0] += count
        if let spacing {
            spacingToCount[spacing, default: 0] += count
        }
        trimSampleTable(&lengthToCount)
        trimSampleTable(&spacingToCount)
    }

    mutating func merge(_ other: EstimationCache) {
        lengthToCount.merge(other.lengthToCount, uniquingKeysWith: +)
        spacingToCount.merge(other.spacingToCount, uniquingKeysWith: +)
        zeroIndices.formUnion(other.zeroIndices)
    }

    private func trimSampleTable(_ table: inout [CGFloat: Int]) {
        guard table.count >= 26,
              let key = table.min(by: { lhs, rhs in lhs.value < rhs.value })?.key else {
            return
        }
        table.removeValue(forKey: key)
    }

    private static func weightedAverage(_ table: [CGFloat: Int]) -> CGFloat? {
        var weightedTotal = CGFloat.zero
        var countTotal = CGFloat.zero
        for (value, count) in table {
            let weight = CGFloat(count)
            weightedTotal += value * weight
            countTotal += weight
        }
        guard countTotal > 0 else {
            return nil
        }
        return weightedTotal / countTotal
    }
}

/// Carries the immutable stack inputs shared by exact and estimated placement.
struct PlacementProperties<LayoutType: LazyStack>: LazyLayoutNamespace {
    var minor: MinorProperties<LayoutType>
    var visible: Range<CGFloat>
    var resetEstimates: Bool
    var estimatesChanged: Bool
    var visibleLength: CGFloat
    var containerLength: CGFloat

    init(
        minor: MinorProperties<LayoutType>,
        visible: Range<CGFloat>,
        resetEstimates: Bool = false,
        estimatesChanged: Bool = false,
        visibleLength: CGFloat,
        containerLength: CGFloat
    ) {
        self.minor = minor
        self.visible = visible
        self.resetEstimates = resetEstimates
        self.estimatesChanged = estimatesChanged
        self.visibleLength = visibleLength
        self.containerLength = containerLength
    }
}

/// Selects the terminal index or major-axis position for a placement traversal.
enum StoppingCondition: LazyLayoutNamespace, Equatable {
    case never
    case position(CGFloat)
    case index(Int)
}

/// Traverses lazy list nodes while measuring, grouping, and emitting visible stack items.
struct StackPlacement<LayoutType: LazyStack>: LazyLayoutNamespace {
    var stack: LayoutType
    var axis: Axis
    var minor: MinorProperties<LayoutType>
    var visible: Range<CGFloat>
    var pinnedViews: PinnedScrollableViews
    var queriedIndex: Int?
    var index: Int
    var skipFirst: Bool
    var position: CGFloat
    var stoppingCondition: StoppingCondition
    var currentSubviews: [_LazyLayout_Subview]
    var lastSubviews: [_LazyLayout_Subview]?
    var pendingHeader: _LazyLayout_Subview?
    var placedSubviews: [_LazyLayout_PlacedSubview]
    var placedIndex: (min: Int, max: Int)
    var placedPosition: (min: CGFloat, max: CGFloat)
    var placedQuery: (min: CGFloat, max: CGFloat)
    var wasCancelled: Bool
    var estimations: EstimationCache

    init(
        stack: LayoutType,
        axis: Axis,
        minor: MinorProperties<LayoutType>,
        visible: Range<CGFloat>,
        pinnedViews: PinnedScrollableViews = [],
        queriedIndex: Int? = nil,
        index: Int = 0,
        skipFirst: Bool = false,
        position: CGFloat = 0,
        stoppingCondition: StoppingCondition = .never,
        currentSubviews: [_LazyLayout_Subview] = [],
        lastSubviews: [_LazyLayout_Subview]? = nil,
        pendingHeader: _LazyLayout_Subview? = nil,
        placedSubviews: [_LazyLayout_PlacedSubview] = [],
        placedIndex: (min: Int, max: Int) = (0, 0),
        placedPosition: (min: CGFloat, max: CGFloat) = (0, 0),
        placedQuery: (min: CGFloat, max: CGFloat) = (0, 0),
        wasCancelled: Bool = false,
        estimations: EstimationCache = EstimationCache()
    ) {
        self.stack = stack
        self.axis = axis
        self.minor = minor
        self.visible = visible
        self.pinnedViews = pinnedViews
        self.queriedIndex = queriedIndex
        self.index = index
        self.skipFirst = skipFirst
        self.position = position
        self.stoppingCondition = stoppingCondition
        self.currentSubviews = currentSubviews
        self.lastSubviews = lastSubviews
        self.pendingHeader = pendingHeader
        self.placedSubviews = placedSubviews
        self.placedIndex = placedIndex
        self.placedPosition = placedPosition
        self.placedQuery = placedQuery
        self.wasCancelled = wasCancelled
        self.estimations = estimations
    }

    mutating func reset(
        index: Int,
        position: CGFloat,
        stoppingCondition: StoppingCondition,
        skipFirst: Bool
    ) {
        self.index = index
        self.skipFirst = skipFirst
        self.position = position
        self.stoppingCondition = stoppingCondition
        currentSubviews.removeAll(keepingCapacity: true)
        lastSubviews = nil
        pendingHeader = nil
        placedSubviews.removeAll(keepingCapacity: true)
        placedIndex = (Int.max, Int.min)
        placedPosition = (.infinity, -.infinity)
        placedQuery = (.infinity, -.infinity)
        wasCancelled = false
        estimations = EstimationCache()
    }

    func shouldStop() -> Bool {
        switch stoppingCondition {
        case .never:
            return false
        case .position(let limit):
            return position >= limit
        case .index(let limit):
            return index > limit
        }
    }

    func isVisible(length: CGFloat) -> Bool {
        isVisible(length: length, count: minor.count)
    }

    func isVisible(length: CGFloat, count: Int) -> Bool {
        if let queriedIndex {
            let upper = index + max(1, count)
            return queriedIndex >= index && queriedIndex < upper
        }

        let lower = max(visible.lowerBound, position)
        let upper = min(visible.upperBound, position + length)
        return lower < upper || (lower == upper && length == 0)
    }

    mutating func addVisibleSubview(length: CGFloat, spacing: CGFloat) {
        addVisibleSubview(length: length, spacing: spacing, count: minor.count)
    }

    mutating func addVisibleSubview(length: CGFloat, spacing: CGFloat, count: Int) {
        let upperIndex = index + max(1, count) - 1
        placedIndex = (
            min: min(index, placedIndex.min),
            max: max(upperIndex, placedIndex.max)
        )

        let lower = position - spacing
        let upper = position + length
        placedPosition = (
            min: min(lower, placedPosition.min),
            max: max(upper, placedPosition.max)
        )

        if let queriedIndex,
           queriedIndex >= index,
            queriedIndex < index + max(1, count) {
            placedQuery = (
                min: min(position, placedQuery.min),
                max: max(upper, placedQuery.max)
            )
        }
    }

    @discardableResult
    mutating func place(subviews: _LazyLayout_Subviews) -> Bool {
        var from = max(0, index - subviews.baseIndex)
        let completed = placeTraversal(subviews: subviews, from: &from, style: _ViewList_IteratorStyle())
        flushMinorGroup()
        return completed
    }

    @discardableResult
    mutating func place(
        subviews: _LazyLayout_Subviews,
        from: Int,
        position: CGFloat,
        stopping: StoppingCondition,
        style: _ViewList_IteratorStyle
    ) -> Bool {
        reset(index: from, position: position, stoppingCondition: stopping, skipFirst: false)
        if index >= minor.count {
            skipFirst = true
            index -= minor.count
        }

        var traversalStart = max(0, index - subviews.baseIndex)
        let completed = placeTraversal(subviews: subviews, from: &traversalStart, style: style)
        flushMinorGroup()
        guard completed else {
            return false
        }
        return abs(self.position - placedPosition.max) < 0.01
    }

    private mutating func placeTraversal(
        subviews: _LazyLayout_Subviews,
        from: inout Int,
        style: _ViewList_IteratorStyle
    ) -> Bool {
        subviews.applyNodes(from: &from, style: style) { nodeFrom, node, stop in
            place(node: node, from: &nodeFrom, stop: &stop, style: style)
        }
    }

    private mutating func place(
        node: _LazyLayout_Subviews.Node,
        from: inout Int,
        stop: inout Bool,
        style: _ViewList_IteratorStyle
    ) {
        switch node {
        case .subviews(let child):
            from = max(0, index - child.baseIndex)
            let childCompleted = child.apply(from: &from, style: style) { _, subview, childStop in
                placeBody(subview: subview)
                childStop = shouldStop()
            }
            if !childCompleted {
                stop = true
            }
        case .section(let section):
            placeSection(section, from: &from, style: style)
        }
        if shouldStop() {
            stop = true
        }
    }

    private mutating func placeSection(
        _ section: _LazyLayout_Section,
        from: inout Int,
        style: _ViewList_IteratorStyle
    ) {
        flushMinorGroup()
        guard !shouldStop() else {
            return
        }

        var headerFrom = 0
        _ = section.header.apply(from: &headerFrom, style: style) { _, subview, childStop in
            placeBoundary(subview: subview)
            childStop = shouldStop()
        }
        guard !shouldStop() else {
            return
        }

        from = max(0, index - section.content.baseIndex)
        let contentCompleted = section.content.apply(from: &from, style: style) { _, subview, childStop in
            placeBody(subview: subview)
            childStop = shouldStop()
        }
        from = roundedSectionTraversalPointer(
            contentBaseIndex: section.content.baseIndex
        )
        if !contentCompleted {
            return
        }
        flushMinorGroup()
        guard !shouldStop() else {
            return
        }

        var footerFrom = 0
        _ = section.footer.apply(from: &footerFrom, style: style) { _, subview, childStop in
            placeBoundary(subview: subview)
            childStop = shouldStop()
        }
        flushMinorGroup()
    }

    private func roundedSectionTraversalPointer(contentBaseIndex: Int) -> Int {
        let minorCount = max(1, minor.count)
        let contentOffset = max(0, index - contentBaseIndex)
        return contentBaseIndex + (contentOffset / minorCount) * minorCount
    }

    mutating func measureBackwards(
        subviews groups: [[_LazyLayout_Subview]],
        lastIndex: Int,
        lastPosition: CGFloat,
        atStart: Bool,
        atEnd: Bool,
        allowBeforeFirst: Bool
    ) {
        guard !groups.isEmpty else {
            return
        }

        reset(
            index: lastIndex,
            position: lastPosition,
            stoppingCondition: .position(visible.lowerBound),
            skipFirst: true
        )
        if atEnd {
            index = max(0, index - minor.count)
        }

        var didFlush = false
        for groupIndex in groups.indices.reversed() {
            let group = groups[groupIndex]
            let predecessors = groupIndex > groups.startIndex ? groups[groupIndex - 1] : nil
            flushBackwards(
                subviews: group,
                predecessors: predecessors,
                includeEmpty: atStart && groupIndex == groups.startIndex,
                allowBeforeFirst: allowBeforeFirst
            )
            didFlush = true
            if !allowBeforeFirst,
               !atStart,
               position <= visible.lowerBound {
                break
            }
        }
        if !didFlush, atStart {
            flushBackwards(
                subviews: [],
                predecessors: nil,
                includeEmpty: true,
                allowBeforeFirst: allowBeforeFirst
            )
        }
        skipFirst = false
    }

    private mutating func flushBackwards(
        subviews: [_LazyLayout_Subview],
        predecessors: [_LazyLayout_Subview]?,
        includeEmpty: Bool,
        allowBeforeFirst: Bool
    ) {
        currentSubviews = subviews
        guard !currentSubviews.isEmpty || includeEmpty else {
            return
        }

        if !currentSubviews.isEmpty {
            let measured = stack.lengthAndSpacing(
                subviews: currentSubviews,
                predecessors: predecessors,
                minorGeometry: minor.geometry
            )
            position -= measured.length
            if predecessors != nil {
                position -= measured.spacing
            }
            index = max(0, index - minor.count)
        } else if includeEmpty, !allowBeforeFirst {
            position = max(position, visible.lowerBound)
        }

        lastSubviews = currentSubviews
        currentSubviews.removeAll(keepingCapacity: true)
    }

    @discardableResult
    mutating func placeBody(subview: _LazyLayout_Subview) -> Bool {
        currentSubviews.append(subview)
        guard currentSubviews.count >= max(1, minor.count) else {
            return false
        }
        flushMinorGroup()
        return true
    }

    mutating func placeBoundary(subview: _LazyLayout_Subview) {
        flushMinorGroup()

        let proposal = fullMinorProposal()
        let predecessor = lastSubviews?.last
        let measured = subview.lengthAndSpacing(
            size: proposal,
            axis: axis,
            predecessor: predecessor,
            uniformSpacing: stack.spacing
        )
        addMeasurements(length: measured.length, spacing: measured.spacing)
        position += measured.spacing

        if isVisible(length: measured.length, count: 1) {
            addVisibleSubview(length: measured.length, spacing: measured.spacing, count: 1)
            emit(
                subview,
                at: boundaryPoint(),
                proposal: _ProposedSize(proposal),
                anchor: .topLeading
            )
        }

        position += measured.length
        index = max(index, subview.index + 1)
        lastSubviews = [subview]
        currentSubviews.removeAll(keepingCapacity: true)
    }

    private func fullMinorProposal() -> ProposedViewSize {
        switch axis {
        case .horizontal:
            return ProposedViewSize(width: nil, height: minor.size)
        case .vertical:
            return ProposedViewSize(width: minor.size, height: nil)
        }
    }

    private func boundaryPoint() -> CGPoint {
        switch axis {
        case .horizontal:
            return CGPoint(x: position, y: 0)
        case .vertical:
            return CGPoint(x: 0, y: position)
        }
    }

    mutating func flushMinorGroup(
        emit: ((_LazyLayout_PlacedSubview) -> Void)? = nil
    ) {
        guard !currentSubviews.isEmpty else {
            return
        }

        let subviews = currentSubviews
        if skipFirst {
            skipFirst = false
            index += minor.count
            lastSubviews = subviews
            currentSubviews.removeAll(keepingCapacity: true)
            return
        }

        let measured = stack.lengthAndSpacing(
            subviews: subviews,
            predecessors: lastSubviews,
            minorGeometry: minor.geometry
        )
        addMeasurements(length: measured.length, spacing: measured.spacing)
        position += measured.spacing

        if isVisible(length: measured.length) {
            addVisibleSubview(length: measured.length, spacing: measured.spacing)
            stack.place(
                subviews: subviews,
                length: measured.length,
                minorGeometry: minor.geometry
            ) { subview, point, proposal, anchor in
                let placed = self.emit(
                    subview,
                    at: placementPoint(for: point),
                    proposal: proposal,
                    anchor: anchor
                )
                emit?(placed)
            }
        }

        position += measured.length
        index += minor.count
        lastSubviews = subviews
        currentSubviews.removeAll(keepingCapacity: true)
    }

    private mutating func addMeasurements(length: CGFloat, spacing: CGFloat) {
        estimations.add(length: length, spacing: spacing, count: 1)
        if length == 0 {
            estimations.zeroIndices.insert(index)
        } else if estimations.zeroIndices.contains(index) {
            estimations.zeroIndices.remove(index)
        }
    }

    private func placementPoint(for point: CGPoint) -> CGPoint {
        switch axis {
        case .horizontal:
            return CGPoint(x: position + point.x, y: point.y)
        case .vertical:
            return CGPoint(x: point.x, y: position + point.y)
        }
    }

    @discardableResult
    mutating func emit(
        _ subview: _LazyLayout_Subview,
        at point: CGPoint,
        proposal: _ProposedSize,
        anchor: UnitPoint
    ) -> _LazyLayout_PlacedSubview {
        let placed = subview.place(at: _Placement(
            proposedSize: proposal.fixingUnspecifiedDimensions(),
            anchoring: anchor,
            at: point
        ))
        placedSubviews.append(placed)
        return placed
    }

    func placedBounds(minorAxis: ClosedRange<CGFloat>) -> CGRect {
        guard placedPosition.min < placedPosition.max else {
            return .null
        }

        let majorLength = placedPosition.max - placedPosition.min
        let minorLength = minorAxis.upperBound - minorAxis.lowerBound
        switch axis {
        case .horizontal:
            return CGRect(
                x: placedPosition.min,
                y: minorAxis.lowerBound,
                width: majorLength,
                height: minorLength
            )
        case .vertical:
            return CGRect(
                x: minorAxis.lowerBound,
                y: placedPosition.min,
                width: minorLength,
                height: majorLength
            )
        }
    }

    var placedExtent: ClosedRange<CGFloat> {
        guard placedPosition.min < placedPosition.max else {
            precondition(!position.isNaN)
            return position...position
        }
        return placedPosition.min...placedPosition.max
    }

    func placedBounds(minorAxis: CGFloat) -> CGRect {
        guard minorAxis > 0 else {
            return .null
        }
        return placedBounds(minorAxis: 0...minorAxis)
    }
}

/// Preserves stack estimates and the last resolved viewport start across layout passes.
struct _LazyStack_Cache<LayoutType: LazyStack>: LazyLayoutNamespace {
    var minor: MinorProperties<LayoutType>?
    var endIndex: Int?
    var placedIndices: Range<Int>
    var placedExtent: Range<CGFloat>
    var visibleExtent: Range<CGFloat>
    var visibleLength: CGFloat
    var containerLength: CGFloat
    var estimations: EstimationCache

    init(
        minor: MinorProperties<LayoutType>? = nil,
        endIndex: Int? = nil,
        placedIndices: Range<Int> = 0..<0,
        placedExtent: Range<CGFloat> = CGFloat.zero..<CGFloat.zero,
        visibleExtent: Range<CGFloat> = CGFloat.zero..<CGFloat.zero,
        visibleLength: CGFloat = .infinity,
        containerLength: CGFloat = 0,
        estimations: EstimationCache = EstimationCache()
    ) {
        self.minor = minor
        self.endIndex = endIndex
        self.placedIndices = placedIndices
        self.placedExtent = placedExtent
        self.visibleExtent = visibleExtent
        self.visibleLength = visibleLength
        self.containerLength = containerLength
        self.estimations = estimations
    }

    mutating func reset() {
        minor = nil
        endIndex = nil
        placedIndices = 0..<0
        placedExtent = CGFloat.zero..<CGFloat.zero
        visibleExtent = CGFloat.zero..<CGFloat.zero
        resetEstimates()
    }

    mutating func resetEstimates() {
        estimations = EstimationCache()
    }

    mutating func place(
        stack: LayoutType,
        subviews: _LazyLayout_Subviews,
        from: Int,
        position: CGFloat,
        visible: Range<CGFloat>,
        visibleLength: CGFloat,
        containerLength: CGFloat,
        minor: MinorProperties<LayoutType>,
        stopping: StoppingCondition = .never,
        style: _ViewList_IteratorStyle = _ViewList_IteratorStyle(),
        pinnedViews: PinnedScrollableViews = []
    ) -> _LazyLayout_Placements {
        self.minor = minor
        visibleExtent = visible
        self.visibleLength = visibleLength
        self.containerLength = containerLength

        var placement = StackPlacement(
            stack: stack,
            axis: LayoutType.majorAxis,
            minor: minor,
            visible: visible,
            pinnedViews: pinnedViews,
            placedIndex: (min: Int.max, max: Int.min),
            placedPosition: (min: .infinity, max: -.infinity),
            placedQuery: (min: .infinity, max: -.infinity),
            estimations: estimations
        )
        let completed = placement.place(
            subviews: subviews,
            from: from,
            position: position,
            stopping: stopping,
            style: style
        )

        estimations = placement.estimations
        if placement.placedIndex.min <= placement.placedIndex.max {
            placedIndices = placement.placedIndex.min..<(placement.placedIndex.max + 1)
        } else {
            placedIndices = 0..<0
        }
        let extent = placement.placedExtent
        placedExtent = extent.lowerBound..<extent.upperBound
        endIndex = completed ? placement.index : nil

        var placedSubviews = placement.placedSubviews
        placedSubviews.pinSectionHeadersAndFooters(
            geometry: pinningGeometry(
                axis: LayoutType.majorAxis,
                visible: visible,
                minorSize: minor.size,
                containerLength: containerLength
            ),
            layoutDirection: .leftToRight,
            axes: LayoutType.layoutProperties.axes,
            pinnedViews: pinnedViews
        )

        return _LazyLayout_Placements(
            subviews: placedSubviews,
            validRect: placement.placedBounds(minorAxis: 0...minor.size),
            invalidSize: false,
            translation: .zero,
            wasCancelled: placement.wasCancelled || !completed
        )
    }

    mutating func resolveIndexAndPosition(
        stack: LayoutType,
        subviews: _LazyLayout_Subviews,
        visible: Range<CGFloat>,
        minor: MinorProperties<LayoutType>,
        style: _ViewList_IteratorStyle = _ViewList_IteratorStyle()
    ) -> (index: Int, position: CGFloat) {
        self.minor = minor
        visibleExtent = visible

        let minorCount = max(1, minor.count)
        let estimatedCount = max(0, subviews.estimatedCount(style: style))
        guard estimatedCount > 0 else {
            return (0, 0)
        }

        let average = estimations.average
        let estimatedStride = max(0, average.length) + max(0, average.spacing ?? 0)
        let visibleStart = max(0, visible.lowerBound)
        guard estimatedStride > 0, visibleStart > 0 else {
            return (0, 0)
        }

        let maxGroupIndex = max(0, (estimatedCount - 1) / minorCount)
        let groupIndex = min(maxGroupIndex, Int(floor(visibleStart / estimatedStride)))
        let candidateIndex = groupIndex * minorCount
        guard candidateIndex > 0 else {
            if let measured = measuredStart(
                stack: stack,
                subviews: subviews,
                visibleStart: visibleStart,
                minor: minor,
                style: style
            ) {
                return measured
            }
            return (0, 0)
        }

        let prefix = measuredPrefix(
            stack: stack,
            subviews: subviews,
            upTo: candidateIndex,
            minor: minor,
            style: style
        )
        guard prefix.position > visibleStart,
              !prefix.groups.isEmpty else {
            if let measured = measuredStart(
                stack: stack,
                subviews: subviews,
                visibleStart: visibleStart,
                minor: minor,
                style: style
            ) {
                return measured
            }
            return (candidateIndex, prefix.position)
        }

        var placement = StackPlacement(
            stack: stack,
            axis: LayoutType.majorAxis,
            minor: minor,
            visible: visible
        )
        placement.measureBackwards(
            subviews: prefix.groups,
            lastIndex: candidateIndex,
            lastPosition: prefix.position,
            atStart: false,
            atEnd: false,
            allowBeforeFirst: false
        )
        return (placement.index, placement.position)
    }

    private func measuredStart(
        stack: LayoutType,
        subviews: _LazyLayout_Subviews,
        visibleStart: CGFloat,
        minor: MinorProperties<LayoutType>,
        style: _ViewList_IteratorStyle
    ) -> (index: Int, position: CGFloat)? {
        let minorCount = max(1, minor.count)
        var from = 0
        var currentSubviews: [_LazyLayout_Subview] = []
        var previousSubviews: [_LazyLayout_Subview]?
        var position = CGFloat.zero
        var result: (index: Int, position: CGFloat)?

        func flushCurrentSubviews() {
            guard result == nil,
                  !currentSubviews.isEmpty else {
                currentSubviews.removeAll(keepingCapacity: true)
                return
            }

            let measured = stack.lengthAndSpacing(
                subviews: currentSubviews,
                predecessors: previousSubviews,
                minorGeometry: minor.geometry
            )
            let startPosition = position
            let endPosition = position + measured.spacing + measured.length
            if endPosition > visibleStart {
                result = (currentSubviews[0].index, startPosition)
            }
            position = endPosition
            previousSubviews = currentSubviews
            currentSubviews.removeAll(keepingCapacity: true)
        }

        func collect(_ subview: _LazyLayout_Subview, stop: inout Bool) {
            guard result == nil else {
                stop = true
                return
            }
            currentSubviews.append(subview)
            if currentSubviews.count >= minorCount {
                flushCurrentSubviews()
                if result != nil {
                    stop = true
                }
            }
        }

        func collect(_ child: _LazyLayout_Subviews, stop: inout Bool) {
            switch child.node {
            case .sublist:
                var childFrom = 0
                let completed = child.apply(from: &childFrom, style: style) { _, subview, childStop in
                    collect(subview, stop: &childStop)
                }
                if !completed {
                    stop = true
                }
            default:
                var childFrom = 0
                let completed = child.applyNodes(from: &childFrom, style: style) { _, node, childStop in
                    switch node {
                    case .subviews(let nested):
                        collect(nested, stop: &childStop)
                    case .section(let nested):
                        collect(nested, stop: &childStop)
                    }
                }
                if !completed {
                    stop = true
                }
            }
        }

        func collect(_ section: _LazyLayout_Section, stop: inout Bool) {
            flushCurrentSubviews()
            guard result == nil,
                  !stop else {
                return
            }

            collect(section.header, stop: &stop)
            guard result == nil,
                  !stop else {
                return
            }

            collect(section.content, stop: &stop)
            flushCurrentSubviews()
            guard result == nil,
                  !stop else {
                return
            }

            collect(section.footer, stop: &stop)
            flushCurrentSubviews()
            if result != nil {
                stop = true
            }
        }

        _ = subviews.applyNodes(from: &from, style: style) { _, node, stop in
            switch node {
            case .subviews(let child):
                collect(child, stop: &stop)
            case .section(let section):
                collect(section, stop: &stop)
            }
        }

        flushCurrentSubviews()
        return result
    }

    private func measuredPrefix(
        stack: LayoutType,
        subviews: _LazyLayout_Subviews,
        upTo limit: Int,
        minor: MinorProperties<LayoutType>,
        style: _ViewList_IteratorStyle
    ) -> (groups: [[_LazyLayout_Subview]], position: CGFloat) {
        guard limit > 0 else {
            return ([], 0)
        }

        let minorCount = max(1, minor.count)
        var from = 0
        var groups: [[_LazyLayout_Subview]] = []
        var currentSubviews: [_LazyLayout_Subview] = []
        var previousSubviews: [_LazyLayout_Subview]?
        var position = CGFloat.zero

        func flushCurrentSubviews() {
            guard !currentSubviews.isEmpty else {
                return
            }
            let measured = stack.lengthAndSpacing(
                subviews: currentSubviews,
                predecessors: previousSubviews,
                minorGeometry: minor.geometry
            )
            position += measured.spacing + measured.length
            groups.append(currentSubviews)
            previousSubviews = currentSubviews
            currentSubviews.removeAll(keepingCapacity: true)
        }

        func collect(_ subview: _LazyLayout_Subview, stop: inout Bool) {
            guard subview.index < limit else {
                stop = true
                return
            }
            currentSubviews.append(subview)
            if currentSubviews.count >= minorCount {
                flushCurrentSubviews()
            }
        }

        func collect(_ child: _LazyLayout_Subviews, stop: inout Bool) {
            switch child.node {
            case .sublist:
                var childFrom = 0
                let completed = child.apply(from: &childFrom, style: style) { _, subview, childStop in
                    collect(subview, stop: &childStop)
                }
                if !completed {
                    stop = true
                }
            default:
                var childFrom = 0
                let completed = child.applyNodes(from: &childFrom, style: style) { _, node, childStop in
                    switch node {
                    case .subviews(let nested):
                        collect(nested, stop: &childStop)
                    case .section(let nested):
                        collect(nested, stop: &childStop)
                    }
                }
                if !completed {
                    stop = true
                }
            }
        }

        func collect(_ section: _LazyLayout_Section, stop: inout Bool) {
            flushCurrentSubviews()
            guard !stop else {
                return
            }

            collect(section.header, stop: &stop)
            guard !stop else {
                return
            }

            collect(section.content, stop: &stop)
            flushCurrentSubviews()
            guard !stop else {
                return
            }

            collect(section.footer, stop: &stop)
            flushCurrentSubviews()
        }

        _ = subviews.applyNodes(from: &from, style: style) { _, node, stop in
            switch node {
            case .subviews(let child):
                collect(child, stop: &stop)
            case .section(let section):
                collect(section, stop: &stop)
            }
        }

        flushCurrentSubviews()
        return (groups, position)
    }

    private func pinningGeometry(
        axis: Axis,
        visible: Range<CGFloat>,
        minorSize: CGFloat,
        containerLength: CGFloat
    ) -> ScrollGeometry {
        switch axis {
        case .horizontal:
            return ScrollGeometry(
                contentOffset: CGPoint(x: visible.lowerBound, y: 0),
                contentSize: CGSize(width: containerLength, height: minorSize),
                containerSize: CGSize(width: visible.upperBound - visible.lowerBound, height: minorSize)
            )
        case .vertical:
            return ScrollGeometry(
                contentOffset: CGPoint(x: 0, y: visible.lowerBound),
                contentSize: CGSize(width: minorSize, height: containerLength),
                containerSize: CGSize(width: minorSize, height: visible.upperBound - visible.lowerBound)
            )
        }
    }

    func allowsLayoutPrefetch(at offset: Int) -> Bool {
        guard visibleLength.isFinite,
              visibleLength > 0 else {
            return true
        }
        let scaledOffset = CGFloat(max(0, offset)) * CGFloat(max(1, minor?.count ?? 1))
        return scaledOffset <= floor(visibleLength) * 0.75
    }
}

/// Returns the placed item set and validity metadata produced by one layout pass.
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

/// Returns a provisional index and item set for noncommitting placement queries.
struct _LazyLayout_EstimatedPlacements: LazyLayoutNamespace {
    var index: Int?
    var subviews: [_LazyLayout_PlacedSubview]

    init(index: Int? = nil, subviews: [_LazyLayout_PlacedSubview] = []) {
        self.index = index
        self.subviews = subviews
    }
}

/// Projects one lazy item's current placement into the geometry consumed by
/// its materialized child graph.
///
/// This rule is the sole bridge from the shared placed-subview array to that
/// child. Keeping geometry here lets AttributeGraph invalidate only affected
/// item graphs instead of recursively placing every visible layout computer.
struct LazyViewGeometry: Rule, AsyncAttribute {
    var _subviews: Attribute<[_LazyLayout_PlacedSubview]>
    var _size: Attribute<ViewSize>
    var _parentPosition: Attribute<CGPoint>
    var _layoutDirection: Attribute<LayoutDirection>
    var cache: LazyLayoutViewCache
    var item: LazyLayoutCacheItem?

    var value: ViewGeometry {
        guard let item else {
            fatalError("LazyViewGeometry evaluated before its cache item was connected.")
        }

        let parentSize = _size.value
        let placement = cache.placement(of: item, in: _subviews.value)
            ?? _Placement(proposedSize: parentSize.proposal, at: .zero)
        let layoutComputer =
            item.outputs._layoutComputer.attribute?.value ?? .defaultValue
        let childSize = layoutComputer.sizeThatFits(placement.proposedSize_)
        var geometry = ViewGeometry(
            origin: placement.frameOrigin(childSize: childSize),
            dimensions: ViewDimensions(
                guideComputer: layoutComputer,
                size: ViewSize(childSize, proposal: placement.proposedSize_)
            )
        )

        // Reflection is parent-local. The parent position is added only after
        // RTL finalization so global coordinates do not affect the mirror.
        geometry.finalizeLayoutDirection(
            _layoutDirection.value,
            parentSize: parentSize.value
        )
        let parentPosition = _parentPosition.value
        geometry.origin.x += parentPosition.x
        geometry.origin.y += parentPosition.y
        return geometry
    }
}

/// Merges the parent and element phases with the retained lazy item's
/// transition state.
struct LazyViewPhase: Rule, AsyncAttribute {
    typealias Value = Phase

    var _phase1: Attribute<Phase>
    var _phase2: Attribute<Phase>
    var _state: Attribute<LazyLayoutCacheItem.State>

    var value: Phase {
        var phase = _phase1.value
        phase.merge(_phase2.value)

        let state = _state.value
        phase.rawValue &+= state.resetDelta &<< 1
        if state.phase == .didDisappear {
            phase.isBeingRemoved = true
        }
        return phase
    }
}

/// Marks a materialized lazy child's display list as hidden while the child is
/// retained only for reuse or while its owning subgraph is detached.
struct HiddenForReuseEffect: Equatable, RendererEffect {
    typealias AnimatableData = EmptyAnimatableData
    typealias Body = Never

    var isHiddenForReuse: Bool

    func effectValue(size: CGSize) -> DisplayList.Effect {
        let stateWord: UInt32 = isHiddenForReuse ? 0x100 : 0
        return .state(StrongHash(words: (stateWord, 0, 0, 0, 0)))
    }
}

/// Publishes the hidden-for-reuse renderer state for one retained lazy item.
struct LazyDisplayListWrapper: StatefulRule, RemovableAttribute, AsyncAttribute {
    typealias Value = HiddenForReuseEffect

    var item: LazyLayoutCacheItem?
    var isRemoved: Bool
    var wasHiddenForReuse: Bool

    mutating func updateValue() {
        guard let item else {
            fatalError("LazyDisplayListWrapper evaluated before its cache item was connected.")
        }

        // Prefetch-phase changes are reference-backed cache mutations. Reading
        // the signal establishes the AG dependency that republishes this state.
        _ = item.cache?._prefetchSignal.value
        let isPendingReuse: Bool
        switch item.prefetchPhase {
        case .pendingDisplay, .pendingRemoval:
            isPendingReuse = true
        case .notPrefetching, .prefetching:
            isPendingReuse = false
        }
        let isHiddenForReuse = isRemoved || isPendingReuse
        guard !hasValue || wasHiddenForReuse != isHiddenForReuse else {
            return
        }
        wasHiddenForReuse = isHiddenForReuse
        _AGGraph.setStatefulOutput(
            HiddenForReuseEffect(isHiddenForReuse: isHiddenForReuse)
        )
    }

    static func willRemove(attribute: AGAttribute) {
        setRemoved(true, attribute: attribute)
    }

    static func didReinsert(attribute: AGAttribute) {
        setRemoved(false, attribute: attribute)
    }

    private static func setRemoved(_ isRemoved: Bool, attribute: AGAttribute) {
        guard let graph = _AGGraph.current else { return }
        var cache: LazyLayoutViewCache?
        graph.mutateStatefulRule(attribute, as: Self.self) { wrapper in
            wrapper.isRemoved = isRemoved
            guard let item = wrapper.item else {
                fatalError("LazyDisplayListWrapper removal requires its cache item.")
            }
            cache = item.cache
        }
        cache?.signalPrefetch()
    }
}

/// Resolves the concrete transition body from the current item state while
/// retaining the last compatible type-erased transition value.
struct LazyTransition<A: Transition>: StatefulRule, AsyncAttribute {
    typealias Value = A.Body

    var _state: Attribute<LazyLayoutCacheItem.State>
    var item: LazyLayoutCacheItem?
    var lastValue: A

    mutating func updateValue() {
        guard let item else {
            fatalError("LazyTransition evaluated before its cache item was connected.")
        }

        let current = item._list.attribute?.value.traits[TransitionTraitKey.self]
            ?? .opacity
        if let compatible = current.base(as: A.self) {
            lastValue = compatible
        }

        let state = _state.value
        let phase = state.enableTransitions ? state.phase : .identity
        _AGGraph.setStatefulOutput(
            lastValue.body(
                content: PlaceholderContentView<A>(),
                phase: phase
            )
        )
    }
}

/// Opens a type-erased transition and constructs its concrete lazy child
/// transition subtree.
struct MakeSubviewTransition: TransitionVisitor {
    var _state: Attribute<LazyLayoutCacheItem.State>
    var inputs: _ViewInputs
    var id: _ViewList_ID
    var makeElt: (_ViewInputs) -> _ViewOutputs
    var outputs: _ViewOutputs?
    var transition: AGAttribute?
    var transitionType: Any.Type?

    mutating func visit<A: Transition>(_ transition: A) {
        guard let graph = _AGGraph.current else {
            fatalError("MakeSubviewTransition requires an active AttributeGraph.")
        }
        let body: Attribute<A.Body> = graph.makeStatefulRule(
            LazyTransition(
                _state: _state,
                item: nil,
                lastValue: transition
            )
        )
        let makeElt = makeElt
        outputs = A.makeView(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        ) { _, inputs in
            makeElt(inputs)
        }
        self.transition = body.identifier
        transitionType = A.self
    }
}

/// Connects a reused or newly allocated cache item to its concrete transition
/// state rule without rebuilding the transition subtree.
struct UpdateSubviewTransition: TransitionTypeVisitor {
    var transition: AGAttribute
    var item: LazyLayoutCacheItem

    mutating func visit<A: Transition>(_ type: A.Type) {
        _AGGraph.current?.mutateStatefulRule(
            transition,
            as: LazyTransition<A>.self,
            invalidating: true
        ) { rule in
            rule.item = item
        }
    }
}

/// Compares a retained transition node's concrete type with a reuse candidate.
struct CompareTransitionType: TransitionTypeVisitor {
    var existingType: Any.Type?
    var compatibleTypes: Bool

    mutating func visit<A: Transition>(_ type: A.Type) {
        guard let existingType else {
            compatibleTypes = false
            return
        }
        compatibleTypes = ObjectIdentifier(existingType) == ObjectIdentifier(A.self)
    }
}

/// Publishes an item's transition-aware transaction and tracks removable state.
struct LazyTransaction: StatefulRule, RemovableAttribute, AsyncAttribute {
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

        switch state.phase {
        case .willAppear:
            // A newly materialized child receives its visual insertion through
            // the transition node. Its ordinary subtree transaction must not
            // animate the same state change a second time.
            transaction.animation = nil
            transaction.disablesAnimations = true
        case .identity:
            // Removal/reinsertion and graph-reset boundaries publish a settled
            // transaction before the child resumes ordinary identity updates.
            if isRemoved || lastResetDelta != state.resetDelta {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        case .didDisappear:
            // Register the cache item exactly once when entering the removal
            // phase. Its animation count retains placement until the last
            // descendant animation drains.
            if lastPhase != .didDisappear {
                guard let item else {
                    fatalError("LazyTransaction removal requires its cache item.")
                }
                transaction.addAnimationListener(item)
            }
        }

        lastPhase = state.phase
        lastResetDelta = state.resetDelta
        _AGGraph.setStatefulOutput(transaction)
    }

    static func willRemove(attribute: AGAttribute) {
        _AGGraph.current?.mutateStatefulRule(
            attribute,
            as: Self.self,
            invalidating: true
        ) { transaction in
            transaction.isRemoved = true
        }
    }

    static func didReinsert(attribute: AGAttribute) {
        _AGGraph.current?.mutateStatefulRule(
            attribute,
            as: Self.self,
            invalidating: true
        ) { transaction in
            transaction.isRemoved = false
        }
    }
}

/// Defines sizing, placement, estimation, and transition hooks for lazy containers.
protocol LazyLayout: Animatable, _VariadicView_UnaryViewRoot {
    associatedtype Cache

    static var layoutProperties: _LazyLayout_Properties { get }
    static var initialCache: Cache { get }
    func sizeThatFits(
        proposedSize: ProposedViewSize,
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_SizeAndSpacingContext,
        cache: Cache
    ) -> CGSize
    func spacing(
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_SizeAndSpacingContext,
        cache: Cache
    ) -> Spacing
    func place(
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_PlacementContext,
        cache: inout Cache,
        in placements: inout _LazyLayout_Placements
    )
    func estimatedPlacement(
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_EstimatedPlacementContext,
        cache: Cache,
        in placements: inout _LazyLayout_EstimatedPlacements
    )
    func proposeSizes(
        at offset: Int,
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_PlacementContext,
        cache: Cache,
        in proposedSizes: inout _LazyLayout_ProposedSizes
    )
    func initialPlacement(
        newIndex: Int,
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasInsertedToSubviews: Bool,
        context: _LazyLayout_PlacementContext,
        subviews: _LazyLayout_Subviews,
        cache: Cache
    ) -> _Placement
    func finalPlacement(
        oldIndex: Int,
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasRemovedFromSubviews: Bool,
        context: _LazyLayout_PlacementContext,
        subviews: _LazyLayout_Subviews,
        cache: Cache
    ) -> _Placement
    func firstIndex<ID: Hashable>(
        of id: ID,
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_PlacementContext
    ) -> Int?
    func boundingRect(
        at index: Int,
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_PlacementContext,
        cache: Cache
    ) -> CGRect?
    var pinnedViews: PinnedScrollableViews { get }
}

/// Allows a lazy layout type to provide an explicit accessibility collection role.
private protocol LazyLayoutAccessibilityRoleProviding {
    static var lazyAccessibilityRole: AccessibilityLayoutRole? { get }
}

/// Resolves the default accessibility role from the lazy layout family.
private enum LazyLayoutAccessibilityRole {
    static func role<LayoutType: LazyLayout>(for type: LayoutType.Type) -> AccessibilityLayoutRole? {
        if type is any LazyHVStack.Type { return .stack }
        if type is any HVGrid.Type { return .grid }
        return nil
    }
}

extension LazyLayout {
    static var _viewListOptions: Int {
        _ViewListInputs.Options.requiresSections.rawValue
    }

    static var layoutProperties: _LazyLayout_Properties {
        _LazyLayout_Properties()
    }

    func spacing(
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_SizeAndSpacingContext,
        cache: Cache
    ) -> Spacing {
        Spacing()
    }

    func initialPlacement(
        newIndex: Int,
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasInsertedToSubviews: Bool,
        context: _LazyLayout_PlacementContext,
        subviews: _LazyLayout_Subviews,
        cache: Cache
    ) -> _Placement {
        newPlacedSubviews[newIndex].placement
    }

    func finalPlacement(
        oldIndex: Int,
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasRemovedFromSubviews: Bool,
        context: _LazyLayout_PlacementContext,
        subviews: _LazyLayout_Subviews,
        cache: Cache
    ) -> _Placement {
        oldPlacedSubviews[oldIndex].placement
    }

}

/// Adds one-dimensional grouping and estimation requirements to a lazy layout.
protocol LazyStack: LazyLayout {
    associatedtype MinorGeometry: Equatable

    static var majorAxis: Axis { get }
    var spacing: CGFloat? { get }
    var headerAnchor: UnitPoint { get }
    var footerAnchor: UnitPoint { get }

    func flexibleMinorSize(subviews: _LazyLayout_Subviews) -> CGFloat
    func minorGeometry(updatingSize size: inout CGFloat) -> (count: Int, data: MinorGeometry)
    func lengthAndSpacing(
        subviews: [_LazyLayout_Subview],
        predecessors: [_LazyLayout_Subview]?,
        minorGeometry: MinorGeometry
    ) -> (length: CGFloat, spacing: CGFloat)
    func place(
        subviews: [_LazyLayout_Subview],
        length: CGFloat?,
        minorGeometry: MinorGeometry,
        emit: (_LazyLayout_Subview, CGPoint, _ProposedSize, UnitPoint) -> Void
    )
}

extension LazyStack where Cache == _LazyStack_Cache<Self> {
    static var initialCache: Cache {
        _LazyStack_Cache()
    }

    func initialPlacement(
        newIndex: Int,
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasInsertedToSubviews: Bool,
        context: _LazyLayout_PlacementContext,
        subviews: _LazyLayout_Subviews,
        cache: Cache
    ) -> _Placement {
        let target = newPlacedSubviews[newIndex]
        // An explicit list insertion keeps the layout-produced target. Only a
        // survivor reflow derives an entrance transform from stable identity.
        guard !wasInsertedToSubviews else {
            return target.placement
        }

        let avoidanceRect = context.containingVisibleRect
        if let vector = newPlacedSubviews.motionVectors(
            closestTo: newIndex,
            in: oldPlacedSubviews,
            avoiding: avoidanceRect,
            distance: { target, candidate in
                distanceFromRect(target, toRect: candidate)
            }
        ) {
            var placement = target.placement
            placement.anchorPosition.x += vector.translation.width
            placement.anchorPosition.y += vector.translation.height
            let measuredSize = target.size
            placement.proposedSize_ = _ProposedSize(
                width: measuredSize.width == 0
                    ? 0
                    : measuredSize.width * vector.scale.width,
                height: measuredSize.height == 0
                    ? 0
                    : measuredSize.height * vector.scale.height
            )
            return placement
        }

        // A nearby full-ID match preserves local layout continuity. The
        // forward external placement is the final observed fallback.
        if let nearby = placementOfNearbySubview(
            target,
            subviews: subviews,
            context: context,
            cache: cache
        ) {
            return nearby
        }
        return newPlacedSubviews.externalPlacement(
            of: newIndex,
            avoiding: avoidanceRect,
            in: Self.majorAxis
        )
    }

    func finalPlacement(
        oldIndex: Int,
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasRemovedFromSubviews: Bool,
        context: _LazyLayout_PlacementContext,
        subviews: _LazyLayout_Subviews,
        cache: Cache
    ) -> _Placement {
        let target = oldPlacedSubviews[oldIndex]
        // An explicit list removal keeps the committed old placement. Reflow
        // uses surviving identities to predict the target state.
        guard !wasRemovedFromSubviews else {
            return target.placement
        }

        let avoidanceRect = context.containingVisibleRect
        if let vector = oldPlacedSubviews.motionVectors(
            closestTo: oldIndex,
            in: newPlacedSubviews,
            avoiding: avoidanceRect,
            distance: { target, candidate in
                distanceFromRect(target, toRect: candidate)
            }
        ) {
            var placement = target.placement
            placement.anchorPosition.x += vector.translation.width
            placement.anchorPosition.y += vector.translation.height
            let measuredSize = target.size
            placement.proposedSize_ = _ProposedSize(
                width: measuredSize.width == 0
                    ? 0
                    : measuredSize.width * vector.scale.width,
                height: measuredSize.height == 0
                    ? 0
                    : measuredSize.height * vector.scale.height
            )
            return placement
        }

        if let nearby = placementOfNearbySubview(
            target,
            subviews: subviews,
            context: context,
            cache: cache
        ) {
            return nearby
        }
        return oldPlacedSubviews.externalPlacement(
            of: oldIndex,
            avoiding: avoidanceRect,
            in: Self.majorAxis
        )
    }

    private func placementOfNearbySubview(
        _ target: _LazyLayout_PlacedSubview,
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_PlacementContext,
        cache: Cache
    ) -> _Placement? {
        guard cache.minor != nil, !cache.estimations.lengthToCount.isEmpty else {
            return nil
        }
        let average = cache.estimations.average
        let stride = average.length + (average.spacing ?? 0)
        var from = cache.placedIndices.upperBound
        // Search exactly one estimated visible-length window beyond the placed
        // prefix; the numeric conversion deliberately keeps trapping semantics.
        let limit = from + Int(cache.visibleLength / stride)
        var nearbyIndex: Int?
        _ = subviews.apply(
            from: &from,
            style: _ViewList_IteratorStyle(value: 2)
        ) { index, subview, stop in
            if subview.id == target.id {
                nearbyIndex = index
                stop = true
            } else if index >= limit {
                stop = true
            }
        }
        guard let nearbyIndex,
              let rect = boundingRect(
                  at: nearbyIndex,
                  subviews: subviews,
                  context: context,
                  cache: cache
              ) else {
            return nil
        }

        var placement = target.placement
        placement.anchorPosition = CGPoint(
            x: rect.origin.x + rect.width * placement.anchor.x,
            y: rect.origin.y + rect.height * placement.anchor.y
        )
        return placement
    }

    private func distanceFromRect(_ rect: CGRect, toRect: CGRect) -> CGFloat {
        // Multi-view major axes rank by point distance to the candidate center;
        // the alternate route ranks by the signed gap along the major axis.
        if Self.layoutProperties.axes.contains(Self.majorAxis) {
            return rect.distance(
                to: CGPoint(x: toRect.midX, y: toRect.midY)
            )
        }
        return rect.distance(to: toRect, in: Self.majorAxis)
    }

    func sizeThatFits(
        proposedSize: ProposedViewSize,
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_SizeAndSpacingContext,
        cache: Cache
    ) -> CGSize {
        let proposedMinor: CGFloat?
        switch Self.majorAxis {
        case .horizontal:
            proposedMinor = proposedSize.height
        case .vertical:
            proposedMinor = proposedSize.width
        }

        var minorSize = proposedMinor
            ?? flexibleMinorSize(subviews: subviews)
        guard let minor = resolveMinorProperties(
            minorSize: &minorSize,
            cache: cache
        ) else {
            return .zero
        }

        var cache = cache
        if sufficientlyDiffers(
            lazyMajorLength(context.containerSize),
            cache.containerLength
        ) {
            cache.resetEstimates()
        }

        // Measure only the bounded estimate sample. The remaining groups use
        // its average instead of materializing the full lazy list.
        var position = CGFloat.zero
        var index = 0
        measureEstimates(
            updatingPosition: &position,
            index: &index,
            minor: minor,
            subviews: subviews,
            cache: &cache
        )

        let average = cache.estimations.average
        let estimatedCount = subviews.estimatedCount(
            style: _ViewList_IteratorStyle(
                value: UInt(minor.count) << 1
            )
        )
        let remainingCount = max(estimatedCount - index, 0)
        let remainingGroupCount =
            (remainingCount + minor.count - 1) / minor.count
        let averageSpacing = average.spacing ?? 0
        position += CGFloat(remainingGroupCount)
            * (average.length + averageSpacing)
        if index == 0,
           average.spacing != nil,
           remainingGroupCount > 0 {
            position -= averageSpacing
        }

        let majorSize = ceil(position)
        let resolvedMinor = max(proposedMinor ?? 0, minor.size)
        switch Self.majorAxis {
        case .horizontal:
            return CGSize(width: majorSize, height: resolvedMinor)
        case .vertical:
            return CGSize(width: resolvedMinor, height: majorSize)
        }
    }

    func place(
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_PlacementContext,
        cache: inout Cache,
        in placements: inout _LazyLayout_Placements
    ) {
        let minor = lazyMinorProperties(size: context.size, subviews: subviews)
        let visible = lazyVisibleRange(context.nearestVisibleRect)
        let start = cache.resolveIndexAndPosition(
            stack: self,
            subviews: subviews,
            visible: visible,
            minor: minor
        )
        placements = cache.place(
            stack: self,
            subviews: subviews,
            from: start.index,
            position: start.position,
            visible: visible,
            visibleLength: max(0, visible.upperBound - visible.lowerBound),
            containerLength: lazyMajorLength(context.size),
            minor: minor,
            pinnedViews: pinnedViews
        )
    }

    func estimatedPlacement(
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_EstimatedPlacementContext,
        cache: Cache,
        in placements: inout _LazyLayout_EstimatedPlacements
    ) {
        var cache = cache
        var resolved = _LazyLayout_Placements()
        place(
            subviews: subviews,
            context: context.base,
            cache: &cache,
            in: &resolved
        )
        placements.index = resolved.subviews.first?.index
        placements.subviews = resolved.subviews
    }

    func firstIndex<ID: Hashable>(
        of id: ID,
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_PlacementContext
    ) -> Int? {
        _ = context
        return subviews.firstIndex(of: id)
    }

    func boundingRect(
        at index: Int,
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_PlacementContext,
        cache: Cache
    ) -> CGRect? {
        guard index >= 0 else {
            return nil
        }

        var cache = cache
        var minorSize = lazyMinorLength(context.size)
        guard let minor = resolveMinorProperties(
            minorSize: &minorSize,
            cache: cache
        ) else {
            return nil
        }

        let minorCount = minor.count
        let group = index / minorCount
        let groupIndex = group * minorCount
        let visible = lazyVisibleRange(context.nearestVisibleRect)
        let visibleLength = positiveLength(of: visible)
        let containerLength = context.base._containerSize.attribute.flatMap {
            positiveLength(lazyMajorLength($0.value.value))
        }
        let resetEstimates = shouldResetEstimates(
            visibleLength: visibleLength,
            containerLength: containerLength,
            cache: cache
        )
        if resetEstimates {
            cache.resetEstimates()
        }

        if cache.estimations.lengthToCount.isEmpty {
            var position = CGFloat.zero
            var measuredIndex = 0
            measureEstimates(
                updatingPosition: &position,
                index: &measuredIndex,
                minor: minor,
                subviews: subviews,
                cache: &cache
            )
        }

        let average = cache.estimations.average
        let stride = average.length + (average.spacing ?? 0)
        let estimatedOrigin = CGFloat(group) * stride
        let estimatedLength = cache.estimations.lengthToCount.isEmpty
            ? 0
            : average.length
        let estimatedRect = boundingRect(
            majorOrigin: estimatedOrigin,
            majorLength: estimatedLength,
            minorLength: minor.size
        )

        // Exact lookup is meaningful only when the cached placement prefix
        // was produced with the same cross-axis grouping and estimate basis.
        guard !resetEstimates,
              !cache.placedIndices.isEmpty,
              cache.minor == minor else {
            return estimatedRect
        }

        let delta = groupIndex - cache.placedIndices.lowerBound
        let groupDelta = delta / minorCount
        let distanceStride = cache.estimations.lengthToCount.isEmpty
            ? 32
            : stride
        let estimatedDistance = CGFloat(abs(groupDelta)) * distanceStride
        let cachedVisibleLength = max(
            0,
            cache.visibleExtent.upperBound - cache.visibleExtent.lowerBound
        )
        // Distant queries remain estimate-backed. Only targets within three
        // cached visible spans enter exact forward or backward placement.
        guard estimatedDistance <= cachedVisibleLength * 3 else {
            return estimatedRect
        }

        var placement = StackPlacement(
            stack: self,
            axis: Self.majorAxis,
            minor: minor,
            visible: visible,
            queriedIndex: index,
            placedIndex: (min: Int.max, max: Int.min),
            placedPosition: (min: .infinity, max: -.infinity),
            placedQuery: (min: .infinity, max: -.infinity),
            estimations: cache.estimations
        )
        let style = _ViewList_IteratorStyle()
        if groupIndex < cache.placedIndices.lowerBound {
            var atEnd = false
            let groups = collectBackwards(
                from: groupIndex,
                to: cache.placedIndices.lowerBound,
                subviews: subviews,
                style: style,
                atEnd: &atEnd
            )
            placement.measureBackwards(
                subviews: groups,
                lastIndex: cache.placedIndices.lowerBound,
                lastPosition: cache.placedExtent.lowerBound,
                atStart: groupIndex == 0,
                atEnd: atEnd,
                allowBeforeFirst: false
            )
            _ = placement.place(
                subviews: subviews,
                from: placement.index,
                position: placement.position,
                stopping: .index(groupIndex),
                style: style
            )
        } else {
            _ = placement.place(
                subviews: subviews,
                from: cache.placedIndices.lowerBound,
                position: cache.placedExtent.lowerBound,
                stopping: .index(groupIndex),
                style: style
            )
        }

        guard placement.placedQuery.min < placement.placedQuery.max else {
            return estimatedRect
        }
        return boundingRect(
            majorOrigin: placement.placedQuery.min,
            majorLength: placement.placedQuery.max - placement.placedQuery.min,
            minorLength: minor.size
        )
    }

    private func resolveMinorProperties(
        minorSize: inout CGFloat,
        cache: Cache
    ) -> MinorProperties<Self>? {
        _ = cache
        let resolved = minorGeometry(updatingSize: &minorSize)
        guard resolved.count > 0, minorSize > 0 else {
            return nil
        }
        return MinorProperties(
            count: resolved.count,
            size: minorSize,
            geometry: resolved.data
        )
    }

    private func shouldResetEstimates(
        visibleLength: CGFloat?,
        containerLength: CGFloat?,
        cache: Cache
    ) -> Bool {
        sufficientlyDiffers(visibleLength, cache.visibleLength)
            || sufficientlyDiffers(containerLength, cache.containerLength)
    }

    private func sufficientlyDiffers(
        _ current: CGFloat?,
        _ cached: CGFloat
    ) -> Bool {
        guard let current,
              current > 0,
              cached > 0 else {
            return false
        }
        return abs(current - cached) >= 0.01
    }

    private func measureEstimates(
        updatingPosition position: inout CGFloat,
        index: inout Int,
        minor: MinorProperties<Self>,
        subviews: _LazyLayout_Subviews,
        cache: inout Cache
    ) {
        let upperBound: Int
        if !cache.placedIndices.isEmpty,
           cache.minor == minor {
            index = cache.placedIndices.lowerBound
            position = cache.placedExtent.lowerBound
            if index >= minor.count {
                index -= minor.count
            }
            upperBound = cache.placedIndices.upperBound - index <= 1
                ? cache.placedIndices.upperBound + minor.count
                : cache.placedIndices.upperBound
        } else {
            // A cold estimate samples two complete minor groups. Later
            // placement passes merge measurements around the cached prefix.
            guard cache.estimations.lengthToCount.isEmpty || index < 0 else {
                return
            }
            upperBound = minor.count * 2
            guard index < upperBound else {
                return
            }
        }

        var currentSubviews: [_LazyLayout_Subview] = []
        var lastSubviews: [_LazyLayout_Subview]?
        var measured = EstimationCache()
        var from = max(0, index - subviews.baseIndex)

        func flushMinorGroup() {
            guard !currentSubviews.isEmpty else {
                return
            }
            let dimensions = lengthAndSpacing(
                subviews: currentSubviews,
                predecessors: lastSubviews,
                minorGeometry: minor.geometry
            )
            position += dimensions.length + dimensions.spacing
            measured.add(
                length: dimensions.length,
                spacing: lastSubviews == nil ? nil : dimensions.spacing,
                count: 1
            )
            index += minor.count
            lastSubviews = currentSubviews
            currentSubviews.removeAll(keepingCapacity: true)
        }

        _ = subviews.apply(from: &from, style: _ViewList_IteratorStyle()) {
            sourceIndex, subview, stop in
            guard sourceIndex < upperBound else {
                stop = true
                return
            }
            if subview.data.section.isHeader || subview.data.section.isFooter {
                flushMinorGroup()
            }
            currentSubviews.append(subview)
            if subview.data.section.isHeader
                || subview.data.section.isFooter
                || currentSubviews.count >= minor.count {
                flushMinorGroup()
            }
        }
        flushMinorGroup()
        cache.estimations.merge(measured)
    }

    private func collectBackwards(
        from lowerBound: Int,
        to upperBound: Int,
        subviews: _LazyLayout_Subviews,
        style: _ViewList_IteratorStyle,
        atEnd: inout Bool
    ) -> [[_LazyLayout_Subview]] {
        guard lowerBound < upperBound else {
            atEnd = false
            return []
        }

        let count =
            (subviews.cache as? _LazyLayoutViewCache<Self>)?
                .cacheState.minor?.count
            ?? 1
        var from = max(0, lowerBound - subviews.baseIndex)
        var current: [_LazyLayout_Subview] = []
        var result: [[_LazyLayout_Subview]] = []
        let completed = subviews.apply(from: &from, style: style) {
            sourceIndex, subview, stop in
            guard sourceIndex < upperBound else {
                stop = true
                return
            }
            current.append(subview)
            if current.count >= count {
                result.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        atEnd = completed
        return result
    }

    private func boundingRect(
        majorOrigin: CGFloat,
        majorLength: CGFloat,
        minorLength: CGFloat
    ) -> CGRect {
        switch Self.majorAxis {
        case .horizontal:
            return CGRect(
                x: majorOrigin,
                y: 0,
                width: majorLength,
                height: minorLength
            )
        case .vertical:
            return CGRect(
                x: 0,
                y: majorOrigin,
                width: minorLength,
                height: majorLength
            )
        }
    }

    private func positiveLength(of range: Range<CGFloat>) -> CGFloat? {
        positiveLength(range.upperBound - range.lowerBound)
    }

    private func positiveLength(_ value: CGFloat) -> CGFloat? {
        guard value.isFinite, value > 0 else {
            return nil
        }
        return value
    }

    private func lazyMinorProperties(
        size: CGSize,
        subviews: _LazyLayout_Subviews
    ) -> MinorProperties<Self> {
        var minorSize = lazyMinorLength(size)
        if !minorSize.isFinite || minorSize < 0 {
            minorSize = flexibleMinorSize(subviews: subviews)
        }
        if !minorSize.isFinite || minorSize < 0 {
            minorSize = 0
        }
        let minor = minorGeometry(updatingSize: &minorSize)
        return MinorProperties(
            count: max(1, minor.count),
            size: minorSize,
            geometry: minor.data
        )
    }

    private func lazyMajorLength(_ size: CGSize) -> CGFloat {
        switch Self.majorAxis {
        case .horizontal: size.width
        case .vertical: size.height
        }
    }

    private func lazyMinorLength(_ size: CGSize) -> CGFloat {
        switch Self.majorAxis {
        case .horizontal: size.height
        case .vertical: size.width
        }
    }

    private func lazyVisibleRange(_ rect: CGRect) -> Range<CGFloat> {
        let lower: CGFloat
        let upper: CGFloat
        switch Self.majorAxis {
        case .horizontal:
            lower = rect.minX
            upper = rect.maxX
        case .vertical:
            lower = rect.minY
            upper = rect.maxY
        }
        guard lower.isFinite,
              upper.isFinite,
              upper > lower else {
            return 0..<CGFloat.greatestFiniteMagnitude
        }
        return lower..<upper
    }
}

extension LazyLayout where Self: LazyStack, Cache == _LazyStack_Cache<Self> {
    static func _makeView(
        root: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: (_Graph, _ViewInputs) -> _ViewListOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        guard let host = _AGGraphContext.current?.context as? GraphHost else {
            fatalError("\(self)._makeView called outside an active GraphHost context.")
        }

        let dynamicStackOrientationAttr: Attribute<Axis?> = graph.makeRule(
            LazyDynamicStackOrientationRule(layout: root._attribute)
        )
        var lazyInputs = inputs
        lazyInputs.base[DynamicContainerWillRemoveBeforeInvalidation.self] = true
        lazyInputs.stackOrientation = nil
        lazyInputs[DynamicStackOrientation.self] = OptionalAttribute(dynamicStackOrientationAttr)

        let childListOutputs = body(_Graph(), lazyInputs)
        let listAttr: Attribute<any ViewList>
        switch childListOutputs.views {
        case .staticList(let elements):
            listAttr = graph.makeInput(value: BaseViewList(elements: elements) as any ViewList)
        case .dynamicList(let list, _):
            listAttr = list
        }

        let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
            inputs.base.cachedEnvironment.value.environment.value.layoutDirection
        }
        let accessibilityEnabled: Attribute<Bool> = graph.makeRule {
            inputs.base.cachedEnvironment.value.environment.value.accessibilityEnabled
        }
        let updateViewCache: Attribute<LazyLayoutViewCache> = graph.makeStatefulRule(
            UpdateViewCache(_phase: inputs.base.phase, cache: nil)
        )
        let rawPlacedSubviews: Attribute<[_LazyLayout_PlacedSubview]> = graph.makeStatefulRule(
            LazySubviewPlacements(
                layout: root._attribute,
                size: inputs.size,
                position: inputs.position,
                containerSize: inputs.containerSize,
                environment: inputs.base.cachedEnvironment.value.environment,
                layoutDirection: layoutDirection,
                accessibilityEnabled: accessibilityEnabled,
                cache: updateViewCache
            )
        )
        let placedSubviews: Attribute<[_LazyLayout_PlacedSubview]> = graph.makeRule(
            LazyCollectedPlacements(
                _subviews: rawPlacedSubviews,
                _cache: updateViewCache
            )
        )
        placedSubviews.setFlags(.transactional, mask: .transactional)
        let prefetchSignal = graph.makeInput(value: ())
        let cache = _LazyLayoutViewCache(
            layout: root._attribute,
            cacheState: Self.initialCache,
            viewGraph: host,
            parentSubgraph: AGSubgraph.current ?? AGSubgraph(),
            inputs: lazyInputs,
            outputs: _ViewOutputs(),
            list: listAttr,
            layoutDirection: layoutDirection,
            nearestScrollableAxes: inputs.nearestScrollableAxes,
            placedSubviews: placedSubviews,
            prefetchSignal: prefetchSignal,
            scrollPosition: inputs.base.scrollPositionBinding(kind: .scrollContent),
            accessibilityEnabled: accessibilityEnabled
        )
        updateViewCache.mutateBody(
            as: UpdateViewCache.self,
            invalidating: true
        ) {
            $0.cache = cache
        }

        var preferences = PreferencesOutputs()
        var childScrollables: Attribute<ScrollablePreferenceKey.Value>?
        for keyType in inputs.preferences.keys.keys {
            let nodeListAttr: Attribute<[AGWeakAttribute]> = graph.makeRule {
                return cache.items.values.flatMap { item in
                    item.outputs.preferences.values(for: keyType).compactMap {
                        graph.weakAttributeIfValid(for: $0)
                    }
                }
            }
            let reducedID = _makeDynReduceAttr(keyType, nodeListAttr: nodeListAttr, in: graph)
            preferences.append(keyType, node: reducedID)
            if ObjectIdentifier(keyType) == ObjectIdentifier(ScrollablePreferenceKey.self) {
                childScrollables = Attribute<ScrollablePreferenceKey.Value>(reducedID)
            }
        }

        let emptyScrollables = graph.makeInput(value: ScrollablePreferenceKey.defaultValue)
        let parentScrollable = inputs.weakScrollable
        let collection: Attribute<any ScrollableCollection> = graph.makeRule {
            LazyScrollable<Self>(
                position: inputs.position.asWeak(),
                transform: inputs.transform.asWeak(),
                parent: parentScrollable,
                children: (childScrollables ?? emptyScrollables).asWeak(),
                cache: cache
            ) as any ScrollableCollection
        }
        if inputs.preferences.keys.contains(ScrollTargetRole.ContentKey.self),
           let role = inputs.scrollTargetRole.attribute {
            let transform: Attribute<(inout ScrollTargetRole.ContentKey.Value) -> Void> = graph.makeRule(
                ScrollTargetRole.SetLayout(role: role, collection: collection)
            )
            preferences.makePreferenceTransformer(
                inputs: inputs.preferences,
                key: ScrollTargetRole.ContentKey.self,
                transform: transform
            )
        }
        if inputs.preferences.keys.contains(ScrollTargetRole.Key.self),
           let role = inputs.scrollTargetRole.attribute {
            let transform: Attribute<(inout ScrollTargetRole.Key.Value) -> Void> = graph.makeRule(
                ScrollTargetRole.SetLayout(role: role, collection: collection)
            )
            preferences.makePreferenceTransformer(
                inputs: inputs.preferences,
                key: ScrollTargetRole.Key.self,
                transform: transform
            )
        }
        if inputs.preferences.keys.contains(ScrollablePreferenceKey.self) {
            let transform: Attribute<(inout ScrollablePreferenceKey.Value) -> Void> = graph.makeRule {
                let scrollable = collection.value as any Scrollable
                return { value in
                    ScrollablePreferenceKey.reduce(value: &value) { [scrollable] }
                }
            }
            preferences.makePreferenceTransformer(
                inputs: inputs.preferences,
                key: ScrollablePreferenceKey.self,
                transform: transform
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
            preferences.makePreferenceTransformer(
                inputs: inputs.preferences,
                key: UpdateScrollStateRequestKey.self,
                transform: transform
            )
        }

        let layoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
            LazyLayoutComputer(
                _layout: root._attribute,
                _environment: inputs.base.cachedEnvironment.value.environment,
                _cache: updateViewCache,
                _containerSize: inputs.containerSize
            )
        )
        rawPlacedSubviews.mutateBody(
            as: LazySubviewPlacements<Self>.self,
            invalidating: true
        ) {
            $0._layoutComputer = OptionalAttribute(layoutComputer)
        }

        let outputs = _ViewOutputs(
            preferences: preferences,
            layoutComputer: OptionalAttribute(layoutComputer)
        )
        cache.outputs = outputs
        return outputs
    }
}

extension LazyStack {

    static var majorAxis: Axis {
        if layoutProperties.axes.contains(.horizontal) {
            return .horizontal
        }
        return .vertical
    }

    var headerAnchor: UnitPoint {
        Self.majorAxis == .horizontal ? .leading : .top
    }

    var footerAnchor: UnitPoint {
        Self.majorAxis == .horizontal ? .trailing : .bottom
    }

    func proposeSizes(
        at offset: Int,
        subviews: _LazyLayout_Subviews,
        context: _LazyLayout_PlacementContext,
        cache: _LazyStack_Cache<Self>,
        in proposedSizes: inout _LazyLayout_ProposedSizes
    ) {
        guard cache.allowsLayoutPrefetch(at: offset) else {
            return
        }
        var from = max(0, offset / max(1, cache.minor?.count ?? 1))
        let proposal = Self.lazyStackPrefetchProposal(
            from: ProposedViewSize(context.size)
        )

        _ = subviews.apply(from: &from) { _, subview, stop in
            proposedSizes.subviews.append(subview.proposeSize(proposal))
            stop = true
        }
    }

    static func lazyStackPrefetchProposal(from proposedSize: ProposedViewSize) -> ProposedViewSize {
        if layoutProperties.axes.contains(.horizontal) {
            return ProposedViewSize(width: nil, height: proposedSize.height)
        }
        if layoutProperties.axes.contains(.vertical) {
            return ProposedViewSize(width: proposedSize.width, height: nil)
        }
        return proposedSize
    }
}

/// Adapts a horizontal or vertical stack layout to lazy stack traversal.
protocol LazyHVStack: LazyStack where MinorGeometry == CGFloat {
    associatedtype Base: HVStack

    var base: Base { get }
}

extension LazyHVStack {
    static var majorAxis: Axis {
        Base.majorAxis
    }

    static var layoutProperties: _LazyLayout_Properties {
        let axes = Axis.Set(majorAxis)
        return _LazyLayout_Properties(
            axes: axes,
            multipleViewAxes: axes
        )
    }

    var spacing: CGFloat? {
        base.spacing
    }

    private var anchor: UnitPoint {
        switch Self.majorAxis {
        case .horizontal:
            return UnitPoint(x: 0.5, y: base.alignment.fraction)
        case .vertical:
            return UnitPoint(x: base.alignment.fraction, y: 0.5)
        }
    }

    var headerAnchor: UnitPoint {
        anchor
    }

    var footerAnchor: UnitPoint {
        anchor
    }

    func flexibleMinorSize(subviews: _LazyLayout_Subviews) -> CGFloat {
        // The graph backend has no automatic deadline policy, but an existing
        // cancellation still stops this bounded traversal at the same points.
        if _AGGraph.currentUpdateContext != nil,
           _AGGraphCancelUpdateIfNeeded() {
            return 0
        }

        var result = CGFloat.zero
        var from = 0
        _ = subviews.apply(
            from: &from,
            style: _ViewList_IteratorStyle(value: 2)
        ) { _, subview, stop in
            if _AGGraph.currentUpdateContext != nil,
               _AGGraphCancelUpdateIfNeeded() {
                stop = true
                return
            }

            let size = subview.layout.size(in: .unspecified)
            switch Self.majorAxis {
            case .horizontal:
                result = size.height
            case .vertical:
                result = size.width
            }
            stop = true
        }
        return result
    }

    func minorGeometry(updatingSize size: inout CGFloat) -> (count: Int, data: CGFloat) {
        (1, size)
    }

    func lengthAndSpacing(
        subviews: [_LazyLayout_Subview],
        predecessors: [_LazyLayout_Subview]?,
        minorGeometry: CGFloat
    ) -> (length: CGFloat, spacing: CGFloat) {
        // Lazy placement always supplies a nonempty minor group. Preserve the
        // direct-index trap if that invariant is violated.
        let first = subviews[0]
        let predecessor = predecessors.map {
            $0[$0.count - 1]
        }
        return first.lengthAndSpacing(
            size: Self.lazyStackPrefetchProposal(
                from: ProposedViewSize(
                    width: Self.majorAxis == .horizontal ? nil : minorGeometry,
                    height: Self.majorAxis == .horizontal ? minorGeometry : nil
                )
            ),
            axis: Self.majorAxis,
            predecessor: predecessor,
            uniformSpacing: spacing
        )
    }

    func place(
        subviews: [_LazyLayout_Subview],
        length: CGFloat?,
        minorGeometry: CGFloat,
        emit: (_LazyLayout_Subview, CGPoint, _ProposedSize, UnitPoint) -> Void
    ) {
        _ = length
        // One HV-stack minor group contains exactly one child. Group traversal
        // and major-axis advancement remain the caller's responsibility.
        emit(
            subviews[0],
            .zero,
            _ProposedSize(
                nil,
                in: Self.majorAxis,
                by: minorGeometry
            ),
            anchor
        )
    }
}

/// Implements the horizontal lazy stack root and its pinned-view configuration.
struct LazyHStackLayout: LazyHVStack {
    var base: _HStackLayout
    var pinnedViews: PinnedScrollableViews

    typealias Body = Never
    typealias AnimatableData = EmptyAnimatableData
    typealias Cache = _LazyStack_Cache<Self>

    init(base: _HStackLayout, pinnedViews: PinnedScrollableViews) {
        self.base = base
        self.pinnedViews = pinnedViews
    }

}

/// Describes one grid track's cross-axis position, extent, and anchor.
struct HVGridGeometry: LazyLayoutNamespace, Equatable {
    var position: CGFloat
    var size: CGFloat
    var anchor: UnitPoint
}

/// Implements the vertical lazy stack root and its pinned-view configuration.
struct LazyVStackLayout: LazyHVStack {
    var base: _VStackLayout
    var pinnedViews: PinnedScrollableViews

    typealias Body = Never
    typealias AnimatableData = EmptyAnimatableData
    typealias Cache = _LazyStack_Cache<Self>

    init(base: _VStackLayout, pinnedViews: PinnedScrollableViews) {
        self.base = base
        self.pinnedViews = pinnedViews
    }

}
