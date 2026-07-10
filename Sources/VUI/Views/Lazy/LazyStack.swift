//
//  File: LazyStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct ResettableLazyLayoutRoot<Content>: View where Content: View {
    var content: Content

    struct MakeAdaptor<LayoutType: LazyLayout>: Rule {
        var root: Attribute<LayoutType>

        func updateValue() -> LazyLayoutAdaptor_V1<LayoutType> {
            LazyLayoutAdaptor_V1(layout: root.value)
        }
    }

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
        if !hadWork {
            self = .some
        }
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
    case layout
    case outputs
    case display(LazyLayoutCacheItem)
    case layoutDisplay(LazyLayoutCacheItem, ProposedViewSize)
    case removal
}

struct LazyPrefetchPhaseAdvance {
    var result: _LazyLayout_PrefetchResult
    var didNotify: Bool
}

final class LazyLayoutCacheReference<LayoutType: LazyLayout> {
    var cache: _LazyLayoutViewCache<LayoutType>?
    var updateViewCache: Attribute<Void>?
    var layoutComputer: Attribute<LayoutComputer>?
}

struct LazySubviewMaterialization<LayoutType: LazyLayout>: StatefulRule {
    typealias Value = Void

    var reference: LazyLayoutCacheReference<LayoutType>

    mutating func updateValue() {
        guard let cache = reference.cache else {
            _AGGraph.setStatefulOutput(())
            return
        }
        guard let owner = _AGGraph.currentRuleContextAttribute else {
            fatalError("LazySubviewMaterialization evaluated outside a rule context.")
        }

        _ = reference.updateViewCache?.value
        let subviews = cache.subviews(context: AnyRuleContext(attribute: owner))
        var placedSubviews: [_LazyLayout_PlacedSubview] = []
        var from = 0
        _ = subviews.apply(from: &from) { _, subview, _ in
            let item = cache.item(data: subview.data)
            let placement = _Placement(proposedSize: CGSize.zero)
            item.placement = placement
            placedSubviews.append(
                _LazyLayout_PlacedSubview(
                    item: item,
                    placement: placement,
                    index: subview.index
                )
            )
        }
        cache.commitPlacedSubviews(placedSubviews)
        cache.updateItemPhases()
        _AGGraph.setStatefulOutput(())
    }
}

private struct LazyDynamicStackOrientationRule<L: Layout>: Rule {
    var layout: Attribute<L>

    func updateValue() -> Axis? {
        _ = layout.value
        return L.layoutProperties.stackOrientation
    }
}

struct UpdateViewCache: StatefulRule {
    typealias Value = Void

    var phase: Attribute<Phase>
    weak var cache: LazyLayoutViewCache?
    var lastResetSeed: UInt32?

    init(phase: Attribute<Phase>, cache: LazyLayoutViewCache?) {
        self.phase = phase
        self.cache = cache
        self.lastResetSeed = nil
    }

    mutating func updateValue() {
        let resetSeed = phase.value.resetSeed
        if let lastResetSeed,
           lastResetSeed != resetSeed {
            cache?.reset()
        }
        lastResetSeed = resetSeed
        _AGGraph.setStatefulOutput(())
    }

    mutating func destroy() {
        cache?.invalidate()
    }
}

struct LazySubviewPlacements<LayoutType: LazyStack>: StatefulRule {
    typealias Value = [_LazyLayout_PlacedSubview]

    var layout: Attribute<LayoutType>
    var size: Attribute<ViewSize>
    var position: Attribute<CGPoint>
    var environment: Attribute<EnvironmentValues>
    var layoutDirection: Attribute<LayoutDirection>
    var accessibilityEnabled: Attribute<Bool>
    var reference: LazyLayoutCacheReference<LayoutType>
    var stackCache: _LazyStack_Cache<LayoutType>

    init(
        layout: Attribute<LayoutType>,
        size: Attribute<ViewSize>,
        position: Attribute<CGPoint>,
        environment: Attribute<EnvironmentValues>,
        layoutDirection: Attribute<LayoutDirection>,
        accessibilityEnabled: Attribute<Bool>,
        reference: LazyLayoutCacheReference<LayoutType>
    ) {
        self.layout = layout
        self.size = size
        self.position = position
        self.environment = environment
        self.layoutDirection = layoutDirection
        self.accessibilityEnabled = accessibilityEnabled
        self.reference = reference
        self.stackCache = _LazyStack_Cache()
    }

    mutating func updateValue() {
        guard let cache = reference.cache else {
            _AGGraph.setStatefulOutput([])
            return
        }
        let previousSubviews = _AGGraph.currentStatefulOutput([_LazyLayout_PlacedSubview].self)
        _ = reference.updateViewCache?.value
        let placements = makePlacements(cache: cache)
        cache.commitPlacedSubviews(placements.subviews)
        cache.outerPlacedRect = placements.validRect
        cache.containingSize = size.value.value
        _AGGraph.setStatefulOutput(placements.subviews)
        if shouldInvalidateSize(previous: previousSubviews, current: placements) {
            if let layoutComputer = reference.layoutComputer {
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
        let start = stackCache.resolveIndexAndPosition(
            stack: layout,
            subviews: subviews,
            visible: visible,
            minor: minor
        )
        return stackCache.place(
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
                item.beginPrefetching(at: proposal)
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
        let subviews = cache.subviews(context: ruleContext)
        let proposedSize = ProposedViewSize(_size.value.value)

        if let layout = stackLayout(LazyHStackLayout.self),
           axis == .horizontal {
            var stackCache = _LazyStack_Cache<LazyHStackLayout>(
                visibleLength: prefetchVisibleLength(axis: axis)
            )
            return enqueueLayoutDisplayOperations(
                from: layout.proposeSizes(
                    at: offset,
                    subviews: subviews,
                    context: sizingContext,
                    cache: &stackCache,
                    in: proposedSize
                )
            )
        }

        if let layout = stackLayout(LazyVStackLayout.self),
           axis == .vertical {
            var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                visibleLength: prefetchVisibleLength(axis: axis)
            )
            return enqueueLayoutDisplayOperations(
                from: layout.proposeSizes(
                    at: offset,
                    subviews: subviews,
                    context: sizingContext,
                    cache: &stackCache,
                    in: proposedSize
                )
            )
        }

        if let layout = stackLayout(LazyHGridLayout.self),
           axis == .horizontal {
            var stackCache = _LazyStack_Cache<LazyHGridLayout>(
                visibleLength: prefetchVisibleLength(axis: axis)
            )
            return enqueueLayoutDisplayOperations(
                from: layout.proposeSizes(
                    at: offset,
                    subviews: subviews,
                    context: sizingContext,
                    cache: &stackCache,
                    in: proposedSize
                )
            )
        }

        if let layout = stackLayout(LazyVGridLayout.self),
           axis == .vertical {
            var stackCache = _LazyStack_Cache<LazyVGridLayout>(
                visibleLength: prefetchVisibleLength(axis: axis)
            )
            return enqueueLayoutDisplayOperations(
                from: layout.proposeSizes(
                    at: offset,
                    subviews: subviews,
                    context: sizingContext,
                    cache: &stackCache,
                    in: proposedSize
                )
            )
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
        if let adaptor = layout as? LazyLayoutAdaptor_V1<StackLayoutType> {
            return adaptor.layout
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
        forID id: ID,
        style: _ViewList_IteratorStyle = _ViewList_IteratorStyle()
    ) -> Int? {
        var from = 0
        var resolved: Int?
        _ = apply(from: &from, style: style) { _, subview, stop in
            guard subview.data.id.containsID(id) else { return }
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
                let id = sublist.id.elementID(at: index)
                let data = _LazyLayout_Subview.Data(
                    elements: _ViewList_SubgraphElements(
                        base: _LazyLayout_SingleElement(
                            base: sublist.elements,
                            elementIndex: offset
                        )
                    ),
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
            var nodeTransform = combinedTransform(with: temporaryTransform)
            if section.id != nil {
                nodeTransform = _viewListTransformDroppingGroupEntryIDs(nodeTransform)
            }

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
                dropNestedSectionSharedGeneratedID: section.id != nil,
                body: body
            )
        case .group(let group):
            return forEachSublist(
                in: group,
                from: &from,
                style: style,
                transform: transform,
                dropNestedSectionSharedGeneratedID: section.id != nil,
                body: body
            )
        case .section(let section):
            return forEachSublist(
                in: section,
                from: &from,
                style: style,
                transform: transform,
                dropSectionSharedGeneratedID: self.section.id != nil,
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
        dropNestedSectionSharedGeneratedID: Bool,
        body: (_ViewList_Sublist) -> Bool
    ) -> Bool {
        list.applyNodes(
            from: &from,
            style: style,
            list: listAttribute,
            transform: _ViewList_TemporarySublistTransform()
        ) { nodeFrom, nodeStyle, node, temporaryTransform in
            var nodeTransform = combinedTransform(baseTransform, with: temporaryTransform)
            if dropNestedSectionSharedGeneratedID {
                nodeTransform = _viewListTransformDroppingGroupEntryIDs(nodeTransform)
            }
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
                    dropSectionSharedGeneratedID: dropNestedSectionSharedGeneratedID,
                    body: body
                )

            case .list(let list, let attribute):
                return forEachSublist(
                    in: list,
                    from: &nodeFrom,
                    listAttribute: attribute,
                    style: nodeStyle,
                    transform: nodeTransform,
                    dropNestedSectionSharedGeneratedID: dropNestedSectionSharedGeneratedID,
                    body: body
                )

            case .group(let group):
                return forEachSublist(
                    in: group,
                    from: &nodeFrom,
                    style: nodeStyle,
                    transform: nodeTransform,
                    dropNestedSectionSharedGeneratedID: dropNestedSectionSharedGeneratedID,
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
        dropSectionSharedGeneratedID: Bool,
        body: (_ViewList_Sublist) -> Bool
    ) -> Bool {
        func mergedRegionTransform(
            _ regionTransform: _ViewList_SublistTransform
        ) -> _ViewList_SublistTransform {
            let appended = dropSectionSharedGeneratedID
                ? _sectionRegionTransformDroppingSharedGeneratedID(regionTransform)
                : regionTransform
            return mergedTransform(baseTransform, appending: appended)
        }

        if let header = section.header,
           !forEachSublist(
               in: header.list,
               from: &from,
               listAttribute: header.attribute,
               style: style,
               transform: mergedRegionTransform(section.headerFooterSubviewIDTransform),
               dropNestedSectionSharedGeneratedID: true,
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
               transform: mergedRegionTransform(section.subviewIDTransform),
               dropNestedSectionSharedGeneratedID: true,
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
               transform: mergedRegionTransform(section.headerFooterSubviewIDTransform),
               dropNestedSectionSharedGeneratedID: true,
               body: body
           ) {
            return false
        }
        return true
    }

    private func mergedTransform(
        _ base: _ViewList_SublistTransform,
        appending appended: _ViewList_SublistTransform
    ) -> _ViewList_SublistTransform {
        var merged = base
        for item in appended.items {
            merged.push(item)
        }
        merged.subgraphCount += appended.subgraphCount
        return merged
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
                list: nil,
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

private struct _LazyLayout_SingleElement: _ViewList_Elements {
    var base: any _ViewList_Elements
    var elementIndex: Int

    var count: Int {
        1
    }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        guard from == 0 else {
            from -= 1
            return (nil, true)
        }

        var shouldContinue = true
        let output = base.makeOneElement(
            at: elementIndex,
            inputs: inputs,
            indirectMap: indirectMap
        ) { elementInputs, makeView in
            let (resolved, keepGoing) = body(elementInputs, makeView)
            shouldContinue = keepGoing
            return resolved
        }
        return (output, shouldContinue)
    }

    func tryToReuseElement(
        at index: Int,
        by other: any _ViewList_Elements,
        at otherIndex: Int,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        base.tryToReuseElement(
            at: elementIndex + index,
            by: other,
            at: otherIndex,
            indirectMap: indirectMap,
            testOnly: testOnly
        )
    }
}

struct _LazyLayout_Section: LazyLayoutNamespace {
    struct ID: Hashable {
        var id: UInt32
    }

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
            transform: regionTransform(for: region),
            section: region.cacheSection(id: base.id),
            baseIndex: baseIndex + precedingEstimatedCount(before: region)
        )
    }

    private func regionTransform(for region: Region) -> _ViewList_SublistTransform {
        switch region {
        case .header, .footer:
            return mergedTransform(appending: base.headerFooterSubviewIDTransform)
        case .content:
            return mergedTransform(appending: base.subviewIDTransform)
        }
    }

    private func mergedTransform(
        appending appended: _ViewList_SublistTransform
    ) -> _ViewList_SublistTransform {
        var merged = transform
        for item in appended.items {
            merged.push(item)
        }
        merged.subgraphCount += appended.subgraphCount
        return merged
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
    var transitionPhaseSetters: [_TransitionPhaseSetter]
    var transitionCompletionSeed: Attribute<UInt32>?
    var transitionTransactions: _TransitionTransactionResolver?
    var removalListener: DynamicContainer.TransitionRemovalListener?

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
        self.transitionPhaseSetters = []
        self.transitionCompletionSeed = nil
        self.transitionTransactions = nil
        self.removalListener = nil
    }

    func setTransitionPhase(
        _ phase: TransitionPhase,
        transaction: Transaction = Transaction()
    ) {
        for setter in transitionPhaseSetters {
            setter(phase, transaction)
        }
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

    func reset() {
        lru.reset()
        commitSeed = 1
        placementSeed = 1
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

        let target = layoutComputer.asWeak().raw
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
            Update.enqueueAction(reason: 0x11) { [weak viewGraph] in
                viewGraph?.continueTransaction(invalidating: target)
            }
        }
    }

    private func layoutInvalidationSeed(for layoutComputer: Attribute<LayoutComputer>) -> UInt32 {
        let changeCount = layoutComputer.value.changeCount
        if changeCount != 0 {
            return UInt32(truncatingIfNeeded: changeCount)
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

    private func lazyViewPhase(
        basePhase: Attribute<Phase>,
        elementPhase: Attribute<Phase>,
        state: Attribute<LazyLayoutCacheItem.State>,
        in graph: _AGGraph
    ) -> Attribute<Phase> {
        let secondaryPhase = elementPhase.identifier == basePhase.identifier
            ? OptionalAttribute<Phase>()
            : OptionalAttribute(elementPhase)
        return graph.makeRule(
            LazyViewPhase(
                basePhase: basePhase,
                secondaryPhase: secondaryPhase,
                state: state
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
        if let listener = item.removalListener {
            listener.readSeed()
            guard listener.isCompletionPublished else { return }
            item.removalListener = nil
        }
        if state.isRemoved {
            item.subgraph.invalidate()
            item.subgraph.removeFromParent()
            items.removeValue(forKey: item.id.canonicalID)
            return
        }
        if state.phase == .identity,
           item.displayIndex != nil {
            let listTransaction = currentListTransaction()
            var removalTransaction = item.transitionTransactions?(.didDisappear, listTransaction)
                .first { candidate in
                    guard let animation = candidate.effectiveAnimation else { return false }
                    return animation.box.duration > 0
                } ?? listTransaction
            if let completionSeed = item.transitionCompletionSeed,
               let animation = removalTransaction.effectiveAnimation,
               animation.box.duration > 0,
               let graph = _AGGraph.current {
                let listener = DynamicContainer.TransitionRemovalListener(
                    seed: completionSeed,
                    inbox: graph.inbox
                )
                item.removalListener = listener
                _ = listener.installCompletion(into: &removalTransaction)
            }
            item.setTransitionPhase(.didDisappear, transaction: removalTransaction)
            state.phase = .didDisappear
            state.enableTransitions = item.willEnableTransitions
            item._state.setValue(state, transaction: removalTransaction)
            item.willEnableTransitions = false
            item.removalListener?.readSeed()
            finalizeAnimationCompletions(
                in: removalTransaction,
                animation: removalTransaction.effectiveAnimation
            )
            if item.parentingPhase == .inserted {
                item.displayIndex = nil
                item.placement = nil
                item.prefetchPhase = .notPrefetching
            }
            return
        }
        guard item.animationCount == 0 else { return }
        if item.parentingPhase == .inserted {
            item.displayIndex = nil
            item.placement = nil
            item.prefetchPhase = .notPrefetching
            state.isRemoved = false
            item._state.setValue(state, transaction: currentListTransaction())
            return
        }
        item.displayIndex = nil
        item.placement = nil
        item.prefetchPhase = supportsViewHierarchyPrefetching ? .pendingRemoval : .notPrefetching
        state.isRemoved = true
        item._state.setValue(state, transaction: currentListTransaction())
        item.subgraph.willRemove()
        if let graph = _AGGraph.current,
           let currentAttribute = _AGGraph.currentRuleContextAttribute {
            graph.inbox.enqueue {
                graph.invalidateAttribute(currentAttribute)
            }
        }
    }

    func commitPlacedSubviews(_ placedSubviews: [_LazyLayout_PlacedSubview]) {
        placementSeed &+= 1
        var minPlacedIndex = Int.max
        var maxPlacedIndex = Int.min
        for (displayIndex, placedSubview) in placedSubviews.enumerated() {
            let item = placedSubview.item
            item.displayIndex = displayIndex
            item.usedSeed = lru.usedSeed
            item.placementSeed = placementSeed
            item.commitSeed = placementSeed
            item.placement = placedSubview.placement
            item.pendingPlacement = nil
            item.parentingPhase = .inserted
            minPlacedIndex = min(minPlacedIndex, placedSubview.index)
            maxPlacedIndex = max(maxPlacedIndex, placedSubview.index)
        }
        if minPlacedIndex <= maxPlacedIndex {
            placedIndices = (minPlacedIndex, maxPlacedIndex)
        } else {
            placedIndices = (0, -1)
        }

        var hasStaleItems = false
        for item in items.values where item.commitSeed != placementSeed {
            if containsCurrentListItem(item) {
                item.parentingPhase = .inserted
                item.prefetchPhase = .notPrefetching
                hasStaleItems = true
                continue
            }
            item.parentingPhase = .removed
            item.removalTransactionSeed = lru.transactionSeed
            item.prefetchPhase = supportsViewHierarchyPrefetching ? .pendingRemoval : .notPrefetching
            item.willEnableTransitions = item.transitionType != nil
            hasStaleItems = true
        }
        if hasStaleItems {
            viewGraph?.continueTransaction(
                LazyLayoutCacheItem.AllItemsPhaseMutation(cache: self)
            )
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
        refresh(item, data: data, transition: transition)
        let newID = item.id.canonicalID
        if oldID != newID {
            items.removeValue(forKey: oldID)
            if let children = childCaches.removeValue(forKey: oldID) {
                childCaches[newID] = children
            }
            if let seed = childCacheSeeds.removeValue(forKey: oldID) {
                childCacheSeeds[newID] = seed
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
        guard item.id.canonicalID != id,
              item.reuseIdentifier == reuseIdentifier else {
            return false
        }
        guard item.parentingPhase != .inserted else {
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

    private func containsCurrentListItem(_ item: LazyLayoutCacheItem) -> Bool {
        _list.value.firstOffset(
            forID: item.id.canonicalID,
            style: _ViewList_IteratorStyle()
        ) != nil
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
            let state = graph.makeInput(value: LazyLayoutCacheItem.State())
            let transitionCompletionSeed = transition.map { _ in graph.makeInput(value: UInt32(0)) }
            var transitionPhaseSetters: [_TransitionPhaseSetter] = []
            var lazyTransactionAttr: Attribute<Transaction>?
            let outputs = data.elements.makeOneElement(at: 0, inputs: childInputs) {
                elementInputs,
                makeView in
                var elementInputs = elementInputs
                elementInputs.base.phase = lazyViewPhase(
                    basePhase: childInputs.base.phase,
                    elementPhase: elementInputs.base.phase,
                    state: state,
                    in: graph
                )
                let lazyTransaction = graph.makeStatefulRule(
                    LazyTransaction(
                        transaction: elementInputs.base.transaction,
                        state: state,
                        item: nil
                    )
                )
                lazyTransactionAttr = lazyTransaction
                elementInputs.base.transaction = lazyTransaction
                if let transition {
                    return transition._makeView(
                        phase: .identity,
                        inputs: elementInputs,
                        phaseSetters: &transitionPhaseSetters
                    ) { _, transitionInputs in
                        makeView(transitionInputs)
                    }
                }
                return makeView(elementInputs)
            } ?? _ViewOutputs()
            return (
                state: state,
                outputs: outputs,
                transitionCompletionSeed: transitionCompletionSeed,
                transitionPhaseSetters: transitionPhaseSetters,
                lazyTransactionAttr: lazyTransactionAttr
            )
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
        item.transitionPhaseSetters = materialized.transitionPhaseSetters
        item.transitionCompletionSeed = materialized.transitionCompletionSeed
        item.transitionTransactions = transition.map { transition in
            { phase, transaction in
                transition._retainedRemovalTransactions(from: transaction, phase: phase)
            }
        }
        if let lazyTransactionAttr = materialized.lazyTransactionAttr {
            graph.mutateStatefulRule(lazyTransactionAttr.identifier, as: LazyTransaction.self) { rule in
                rule.item = item
            }
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
        item._list = data.list.map(OptionalAttribute.init) ?? OptionalAttribute<any ViewList>()
        item.id = data.id
        item.reuseIdentifier = data.id.reuseIdentifier
        item.section = data.section
        item.transition = nil
        item.transitionType = transition?._transitionType
        item.transitionCompletionSeed = transition == nil ? nil : item.transitionCompletionSeed
        item.transitionTransactions = transition.map { transition in
            { phase, transaction in
                transition._retainedRemovalTransactions(from: transaction, phase: phase)
            }
        }
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

    override func reset() {
        let subviews = LayoutSubviews(subviews: [], layoutDirection: _layoutDirection.value)
        cacheState.setValue(_layout.value.makeCache(subviews: subviews))
        super.reset()
    }
}

struct LazyScrollable<LayoutType: LazyLayout>: ScrollableCollection, ScrollableContainer {
    var position: WeakAttribute<CGPoint>
    var transform: WeakAttribute<ViewTransform>
    var parent: WeakAttribute<any Scrollable>
    var children: WeakAttribute<[any Scrollable]>
    var cache: _LazyLayoutViewCache<LayoutType>?

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

    static func hasMultipleViews(in axis: Axis) -> Bool {
        switch axis {
        case .horizontal:
            return LayoutType._lazyLayoutProperties.multipleViewAxes.contains(.horizontal)
        case .vertical:
            return LayoutType._lazyLayoutProperties.multipleViewAxes.contains(.vertical)
        }
    }

    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int? {
        cache?._list.value.firstOffset(forID: id, style: _ViewList_IteratorStyle())
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
        let context = _AGGraph.currentRuleContextAttribute.map {
            AnyRuleContext(attribute: $0)
        }
        return setContentTarget { _, _ in
            makeTarget(for: id, anchor: anchor, context: context)
        }
    }

    var containerParentScrollable: (any Scrollable)? {
        resolvedParent
    }

    var containerChildScrollables: [any Scrollable] {
        resolvedChildren
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
        value(for: transform) ?? ViewTransform()
    }

    private var resolvedParent: (any Scrollable)? {
        value(for: parent)
    }

    private var resolvedChildren: [any Scrollable] {
        value(for: children) ?? []
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
        for id: _ViewList_ID.Canonical,
        anchor: UnitPoint?,
        context: AnyRuleContext?
    ) -> ScrollTarget? {
        guard let placedSubview = placedSubviews.first(where: { lazyCollectionID($0.id, matches: id) }) else {
            guard let targetProducer = cache as? any LazyScrollableTargetProducing,
                  let context else {
                return nil
            }
            return targetProducer.lazyScrollableTarget(
                for: id,
                anchor: anchor,
                transform: resolvedTransform,
                context: context
            )
        }
        let frame = cache?.targetFrame(for: placedSubview) ?? placedSubview.frame
        let rect = frame.converted(to: .content, using: resolvedTransform)
        return ScrollTarget(rect: rect, anchor: anchor)
    }
}

private protocol LazyScrollableTargetProducing {
    func lazyScrollableTarget(
        for id: _ViewList_ID.Canonical,
        anchor: UnitPoint?,
        transform: ViewTransform,
        context: AnyRuleContext
    ) -> ScrollTarget?
}

extension _LazyLayoutViewCache: LazyScrollableTargetProducing where LayoutType: LazyStack {
    func lazyScrollableTarget(
        for id: _ViewList_ID.Canonical,
        anchor: UnitPoint?,
        transform: ViewTransform,
        context: AnyRuleContext
    ) -> ScrollTarget? {
        let style = _ViewList_IteratorStyle()
        guard _list.value.firstOffset(forID: id, style: style) != nil else {
            return nil
        }

        let subviews = subviews(context: context)
        let layout = _layout.value
        var minorSize = lazyMinorLength(containingSize, axis: LayoutType.majorAxis)
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

        var currentSubviews: [_LazyLayout_Subview] = []
        var previousSubviews: [_LazyLayout_Subview]?
        var position = CGFloat.zero
        var target: _LazyLayout_PlacedSubview?
        let minorCount = max(1, minor.count)

        func placementPoint(for point: CGPoint, at groupPosition: CGFloat) -> CGPoint {
            switch LayoutType.majorAxis {
            case .horizontal:
                return CGPoint(x: groupPosition + point.x, y: point.y)
            case .vertical:
                return CGPoint(x: point.x, y: groupPosition + point.y)
            }
        }

        func flushCurrentSubviews(stop: inout Bool) {
            guard !currentSubviews.isEmpty else { return }
            let group = currentSubviews
            let measured = layout.lengthAndSpacing(
                subviews: group,
                predecessors: previousSubviews,
                minorGeometry: minor.geometry
            )
            let groupPosition = position + measured.spacing
            if group.contains(where: { lazyCollectionID($0.data.id, matches: id) }) {
                layout.place(
                    subviews: group,
                    length: measured.length,
                    minorGeometry: minor.geometry
                ) { subview, point, proposal, anchor in
                    guard lazyCollectionID(subview.data.id, matches: id) else { return }
                    target = subview.place(at: _Placement(
                        proposedSize: proposal.replacingUnspecifiedDimensions(),
                        anchoring: anchor,
                        at: placementPoint(for: point, at: groupPosition)
                    ))
                }
                stop = true
            }
            position = groupPosition + measured.length
            previousSubviews = group
            currentSubviews.removeAll(keepingCapacity: true)
        }

        var from = 0
        _ = subviews.apply(from: &from, style: style) { _, subview, stop in
            currentSubviews.append(subview)
            if currentSubviews.count >= minorCount {
                flushCurrentSubviews(stop: &stop)
            }
        }
        if target == nil {
            var stop = false
            flushCurrentSubviews(stop: &stop)
        }

        guard let placedSubview = target else {
            return nil
        }
        let rect = targetFrame(for: placedSubview).converted(to: .content, using: transform)
        return ScrollTarget(rect: rect, anchor: anchor)
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

private func placeLazySubviews(
    _ placedSubviews: [_LazyLayout_PlacedSubview],
    at origin: CGPoint
) {
    for placedSubview in placedSubviews {
        let layoutComputer =
            placedSubview.item.outputs._layoutComputer.attribute?.value ?? .defaultValue
        let anchorPosition = CGPoint(
            x: origin.x + placedSubview.placement.anchorPosition.x,
            y: origin.y + placedSubview.placement.anchorPosition.y
        )
        layoutComputer.place(
            at: anchorPosition,
            anchor: placedSubview.placement.anchor,
            proposal: ProposedViewSize(placedSubview.placement.proposedSize)
        )
    }
}

private func lazyChildGeometries(
    from placedSubviews: [_LazyLayout_PlacedSubview],
    origin: CGPoint
) -> [ViewGeometry] {
    placedSubviews.map { placedSubview in
        let layoutComputer =
            placedSubview.item.outputs._layoutComputer.attribute?.value ?? .defaultValue
        let frame = placedSubview.frame.offsetBy(dx: origin.x, dy: origin.y)
        return ViewGeometry(
            origin: frame.origin,
            dimensions: ViewDimensions(
                guideComputer: layoutComputer,
                size: ViewSize(
                    frame.size,
                    proposal: ProposedViewSize(placedSubview.placement.proposedSize)
                )
            )
        )
    }
}

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

struct MinorProperties<LayoutType: LazyStack>: LazyLayoutNamespace {
    var count: Int
    var size: CGFloat
    var geometry: LayoutType.MinorGeometry

    init(count: Int, size: CGFloat, geometry: LayoutType.MinorGeometry) {
        self.count = count
        self.size = size
        self.geometry = geometry
    }
}

struct LengthSpacing: LazyLayoutNamespace, Equatable {
    var length: CGFloat
    var spacing: CGFloat?
}

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

enum StoppingCondition: LazyLayoutNamespace, Equatable {
    case never
    case position(CGFloat)
    case index(Int)
}

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

        if index < section.content.baseIndex {
            var headerFrom = max(0, index - section.header.baseIndex)
            _ = section.header.apply(from: &headerFrom, style: style) { _, subview, childStop in
                placeBoundary(subview: subview)
                childStop = shouldStop()
            }
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
                proposal: proposal,
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
        proposal: ProposedViewSize,
        anchor: UnitPoint
    ) -> _LazyLayout_PlacedSubview {
        let placed = subview.place(at: _Placement(
            proposedSize: proposal.replacingUnspecifiedDimensions(),
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

struct _LazyStack_Cache<LayoutType: LazyStack>: LazyLayoutNamespace {
    var minor: MinorProperties<LayoutType>?
    var endIndex: Int?
    var placedIndices: Range<Int>
    var placedExtent: Range<CGFloat>
    var visibleExtent: Range<CGFloat>
    var visibleLength: CGFloat
    var containerLength: CGFloat
    var estimations: EstimationCache
    var prefetchStride: Int

    init(
        minor: MinorProperties<LayoutType>? = nil,
        endIndex: Int? = nil,
        placedIndices: Range<Int> = 0..<0,
        placedExtent: Range<CGFloat> = CGFloat.zero..<CGFloat.zero,
        visibleExtent: Range<CGFloat> = CGFloat.zero..<CGFloat.zero,
        visibleLength: CGFloat = .infinity,
        containerLength: CGFloat = 0,
        estimations: EstimationCache = EstimationCache(),
        prefetchStride: Int = 1
    ) {
        self.minor = minor
        self.endIndex = endIndex
        self.placedIndices = placedIndices
        self.placedExtent = placedExtent
        self.visibleExtent = visibleExtent
        self.visibleLength = visibleLength
        self.containerLength = containerLength
        self.estimations = estimations
        self.prefetchStride = prefetchStride
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
            axes: LayoutType._lazyLayoutProperties.axes,
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
        let scaledOffset = CGFloat(max(0, offset)) * CGFloat(max(1, prefetchStride))
        return scaledOffset <= floor(visibleLength) * 0.75
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

struct LazyViewPhase: Rule {
    typealias Value = Phase

    var basePhase: Attribute<Phase>
    var secondaryPhase: OptionalAttribute<Phase>
    var state: Attribute<LazyLayoutCacheItem.State>

    func updateValue() -> Phase {
        var phase = basePhase.value
        if let secondaryPhase = secondaryPhase.attribute {
            phase.merge(secondaryPhase.value)
        }

        let state = state.value
        phase.rawValue &+= state.resetDelta &<< 1
        if state.phase == .didDisappear {
            phase.isBeingRemoved = true
        }
        return phase
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

private protocol LazyLayoutAccessibilityRoleProviding {
    static var lazyAccessibilityRole: AccessibilityLayoutRole? { get }
}

private enum LazyLayoutAccessibilityRole {
    static func role<LayoutType: LazyLayout>(for type: LayoutType.Type) -> AccessibilityLayoutRole? {
        if type is any LazyHVStack.Type { return .stack }
        if type is any HVGrid.Type { return .grid }
        return nil
    }
}

struct LazyLayoutAdaptor_V1<LayoutType: LazyLayout>: LazyLayout {
    var layout: LayoutType

    typealias Body = Never
    typealias Cache = LayoutType.Cache
    typealias AnimatableData = LayoutType.AnimatableData

    static var layoutProperties: LayoutProperties {
        LayoutType.layoutProperties
    }

    static var _lazyLayoutProperties: _LazyLayout_Properties {
        LayoutType._lazyLayoutProperties
    }

    var animatableData: AnimatableData {
        get { layout.animatableData }
        set { layout.animatableData = newValue }
    }

    var pinnedViews: PinnedScrollableViews {
        layout.pinnedViews
    }

    func makeCache(subviews: Subviews) -> Cache {
        layout.makeCache(subviews: subviews)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        layout.updateCache(&cache, subviews: subviews)
    }

    func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        layout.spacing(subviews: subviews, cache: &cache)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }

    func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGFloat? {
        layout.explicitAlignment(
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
        layout.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }
}

extension LazyLayoutAdaptor_V1: LazyLayoutAccessibilityRoleProviding {
    static var lazyAccessibilityRole: AccessibilityLayoutRole? {
        LazyLayoutAccessibilityRole.role(for: LayoutType.self)
    }
}

extension LazyLayout {
    static var _viewListOptions: Int {
        Int(_ViewListInputs.sectionListOptions)
    }

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

extension LazyLayoutAdaptor_V1: LazyStack where LayoutType: LazyStack {
    typealias MinorGeometry = LayoutType.MinorGeometry

    static var majorAxis: Axis {
        LayoutType.majorAxis
    }

    var spacing: CGFloat? {
        layout.spacing
    }

    var headerAnchor: UnitPoint {
        layout.headerAnchor
    }

    var footerAnchor: UnitPoint {
        layout.footerAnchor
    }

    func flexibleMinorSize(subviews: _LazyLayout_Subviews) -> CGFloat {
        layout.flexibleMinorSize(subviews: subviews)
    }

    func minorGeometry(updatingSize size: inout CGFloat) -> (count: Int, data: MinorGeometry) {
        layout.minorGeometry(updatingSize: &size)
    }

    func lengthAndSpacing(
        subviews: [_LazyLayout_Subview],
        predecessors: [_LazyLayout_Subview]?,
        minorGeometry: MinorGeometry
    ) -> (length: CGFloat, spacing: CGFloat) {
        layout.lengthAndSpacing(
            subviews: subviews,
            predecessors: predecessors,
            minorGeometry: minorGeometry
        )
    }

    func place(
        subviews: [_LazyLayout_Subview],
        length: CGFloat?,
        minorGeometry: MinorGeometry,
        emit: (_LazyLayout_Subview, CGPoint, _ProposedSize, UnitPoint) -> Void
    ) {
        layout.place(
            subviews: subviews,
            length: length,
            minorGeometry: minorGeometry,
            emit: emit
        )
    }
}

extension ResettableLazyLayoutRoot {
    static func _makeLazyLayoutView<Root, TreeContent>(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs
    where Content == _VariadicView.Tree<Root, TreeContent>,
          Root: LazyStack,
          TreeContent: View {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        var lazyInputs = inputs
        lazyInputs.base[DynamicContainerWillRemoveBeforeInvalidation.self] = true
        lazyInputs[DynamicContainerRetainCompletedUnusedRemovals.self] = true
        lazyInputs[DynamicContainerMaxUnusedItems.self] = 1

        let tree = view[\.content]
        let adaptor: Attribute<LazyLayoutAdaptor_V1<Root>> = graph.makeRule(
            MakeAdaptor(root: tree[\.root]._attribute)
        )
        return LazyLayoutAdaptor_V1<Root>._makeView(
            root: _GraphValue(_attribute: adaptor),
            inputs: lazyInputs
        ) { _, inputs in
            var listInputs = inputs.listInputs
            listInputs.formUnion(viewListOptions: Root._viewListOptions)
            return TreeContent._makeViewList(view: tree[\.content], inputs: listInputs)
        }
    }
}

extension LazyStack {
    static func _makeView(
        root: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: (_Graph, _ViewInputs) -> _ViewListOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        guard let host = _AGGraphContext.current?.context as? GraphHost else {
            var fallbackInputs = inputs
            fallbackInputs.base[DynamicContainerWillRemoveBeforeInvalidation.self] = true
            return Self._makeLayoutView(root: root, inputs: fallbackInputs, body: body)
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
        let initialSubviews = LayoutSubviews(
            subviews: [],
            layoutDirection: layoutDirection.value
        )
        let cacheState = graph.makeInput(
            value: root._attribute.value.makeCache(subviews: initialSubviews)
        )
        let reference = LazyLayoutCacheReference<Self>()
        let placedSubviews: Attribute<[_LazyLayout_PlacedSubview]> = graph.makeStatefulRule(
            LazySubviewPlacements(
                layout: root._attribute,
                size: inputs.size,
                position: inputs.position,
                environment: inputs.base.cachedEnvironment.value.environment,
                layoutDirection: layoutDirection,
                accessibilityEnabled: accessibilityEnabled,
                reference: reference
            )
        )
        let prefetchSignal = graph.makeInput(value: ())
        let cache = _LazyLayoutViewCache(
            layout: root._attribute,
            cacheState: cacheState,
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
        reference.cache = cache
        reference.updateViewCache = graph.makeStatefulRule(
            UpdateViewCache(phase: inputs.base.phase, cache: cache)
        )
        let materializedSubviews: Attribute<Void> = graph.makeStatefulRule(
            LazySubviewMaterialization<Self>(reference: reference)
        )

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
            preferences.makePreferenceTransformer(
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
            preferences.makePreferenceTransformer(
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
            preferences.makePreferenceTransformer(
                key: UpdateScrollStateRequestKey.self,
                transformAttr: transform,
                graph: graph
            )
        }

        let layoutComputer: Attribute<LayoutComputer> = graph.makeRule {
            LayoutComputer(
                sizeThatFits: { proposal in
                    _ = materializedSubviews.value
                    return proposal.replacingUnspecifiedDimensions(by: inputs.size.value.value)
                },
                place: { position, anchor, proposal in
                    let size = proposal.replacingUnspecifiedDimensions(by: inputs.size.value.value)
                    let origin = CGPoint(
                        x: position.x - size.width * anchor.x,
                        y: position.y - size.height * anchor.y
                    )
                    placeLazySubviews(placedSubviews.value, at: origin)
                },
                childGeometries: { _, origin in
                    lazyChildGeometries(from: placedSubviews.value, origin: origin)
                },
                changeCount: UInt(cache.placementSeed)
            )
        }
        reference.layoutComputer = layoutComputer

        let outputs = _ViewOutputs(
            preferences: preferences,
            layoutComputer: OptionalAttribute(layoutComputer)
        )
        cache.outputs = outputs
        return outputs
    }

    static var majorAxis: Axis {
        if _lazyLayoutProperties.axes.contains(.horizontal) {
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
        context: _LazyLayout_SizeAndSpacingContext,
        cache: inout _LazyStack_Cache<Self>,
        in proposedSize: ProposedViewSize
    ) -> _LazyLayout_ProposedSizes {
        _ = context
        guard cache.allowsLayoutPrefetch(at: offset) else {
            return _LazyLayout_ProposedSizes()
        }
        var from = max(0, offset / max(1, cache.prefetchStride))
        let proposal = Self.lazyStackPrefetchProposal(from: proposedSize)
        var result = _LazyLayout_ProposedSizes()

        _ = subviews.apply(from: &from) { _, subview, stop in
            result.subviews.append(subview.proposeSize(proposal))
            stop = true
        }
        return result
    }

    static func lazyStackPrefetchProposal(from proposedSize: ProposedViewSize) -> ProposedViewSize {
        if _lazyLayoutProperties.axes.contains(.horizontal) {
            return ProposedViewSize(width: nil, height: proposedSize.height)
        }
        if _lazyLayoutProperties.axes.contains(.vertical) {
            return ProposedViewSize(width: proposedSize.width, height: nil)
        }
        return proposedSize
    }
}

protocol LazyHVStack: LazyStack where MinorGeometry == CGFloat {
    associatedtype Base: HVStack

    var base: Base { get }
}

extension LazyHVStack {
    static var majorAxis: Axis {
        Base.majorAxis
    }

    var spacing: CGFloat? {
        base.spacing
    }

    func flexibleMinorSize(subviews: _LazyLayout_Subviews) -> CGFloat {
        _ = subviews
        return .infinity
    }

    func minorGeometry(updatingSize size: inout CGFloat) -> (count: Int, data: CGFloat) {
        (1, size)
    }

    func lengthAndSpacing(
        subviews: [_LazyLayout_Subview],
        predecessors: [_LazyLayout_Subview]?,
        minorGeometry: CGFloat
    ) -> (length: CGFloat, spacing: CGFloat) {
        guard let first = subviews.first else {
            return (0, 0)
        }
        let predecessor = predecessors?.last
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
        var offset = CGFloat.zero
        let proposedSize = ProposedViewSize(
            width: Self.majorAxis == .horizontal ? nil : minorGeometry,
            height: Self.majorAxis == .horizontal ? minorGeometry : nil
        )
        for subview in subviews {
            let point: CGPoint
            switch Self.majorAxis {
            case .horizontal:
                point = CGPoint(x: offset, y: 0)
            case .vertical:
                point = CGPoint(x: 0, y: offset)
            }
            emit(subview, point, proposedSize, .topLeading)
            let measured = subview.lengthAndSpacing(
                size: proposedSize,
                axis: Self.majorAxis,
                predecessor: nil,
                uniformSpacing: spacing
            )
            offset += measured.length + measured.spacing
            if let length, offset >= length { break }
        }
    }
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

struct HVGridGeometry: LazyLayoutNamespace, Equatable {
    var position: CGFloat
    var size: CGFloat
    var anchor: UnitPoint
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
