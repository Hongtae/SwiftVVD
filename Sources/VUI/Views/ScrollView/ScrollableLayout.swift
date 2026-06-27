//
//  File: ScrollableLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Layout-time scroll viewport description passed to scrollable layout code.
public struct _ScrollLayout: Equatable {
    public var contentOffset: CGPoint
    public var size: CGSize
    public var visibleRect: CGRect

    public init(contentOffset: CGPoint, size: CGSize, visibleRect: CGRect) {
        self.contentOffset = contentOffset
        self.size = size
        self.visibleRect = visibleRect
    }
}

/// Supplies the content and root view used by the older scroll-view shell.
public protocol _ScrollableContentProvider {
    associatedtype ScrollableContent: View
    var scrollableContent: Self.ScrollableContent { get }

    associatedtype Root: View
    func root(scrollView: _ScrollView<Self>.Main) -> Self.Root
    func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint?
}

extension _ScrollableContentProvider {
    public func root(scrollView: _ScrollView<Self>.Main) -> _ScrollViewRoot<Self> {
        _ScrollViewRoot(scrollView: scrollView)
    }

    public func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint? {
        nil
    }
}

/// Provides gesture policy for a scroll-view proxy.
public protocol _ScrollViewGestureProvider {
    func scrollableDirections(proxy: _ScrollViewProxy) -> _EventDirections
    func gestureMask(proxy: _ScrollViewProxy) -> GestureMask
}

extension _ScrollViewGestureProvider {
    public func defaultScrollableDirections(proxy: _ScrollViewProxy) -> _EventDirections {
        .all
    }

    public func defaultGestureMask(proxy: _ScrollViewProxy) -> GestureMask {
        .all
    }

    public func scrollableDirections(proxy: _ScrollViewProxy) -> _EventDirections {
        defaultScrollableDirections(proxy: proxy)
    }

    public func gestureMask(proxy: _ScrollViewProxy) -> GestureMask {
        defaultGestureMask(proxy: proxy)
    }
}

/// Default gesture provider that uses the protocol fallback policy.
private struct DefaultScrollViewGestureProvider: _ScrollViewGestureProvider {
}

/// Configuration payload shared by the older scroll-view shell and proxy.
public struct _ScrollViewConfig {
    public static let decelerationRateNormal: Double = 0.998
    public static let decelerationRateFast: Double = 0.99

    public enum ContentOffset {
        case initially(CGPoint)
        case binding(Binding<CGPoint>)
    }

    public var contentOffset: ContentOffset
    public var contentInsets: EdgeInsets
    public var decelerationRate: Double
    public var alwaysBounceVertical: Bool
    public var alwaysBounceHorizontal: Bool
    public var gestureProvider: any _ScrollViewGestureProvider
    public var stopDraggingImmediately: Bool
    public var isScrollEnabled: Bool
    public var showsHorizontalIndicator: Bool
    public var showsVerticalIndicator: Bool
    public var indicatorInsets: EdgeInsets

    public init() {
        self.contentOffset = .initially(.zero)
        self.contentInsets = EdgeInsets()
        self.decelerationRate = 0.995
        self.alwaysBounceVertical = false
        self.alwaysBounceHorizontal = false
        self.gestureProvider = DefaultScrollViewGestureProvider()
        self.stopDraggingImmediately = false
        self.isScrollEnabled = true
        self.showsHorizontalIndicator = true
        self.showsVerticalIndicator = true
        self.indicatorInsets = EdgeInsets()
    }
}

/// Older scroll-view shell driven by a content provider.
public struct _ScrollView<Provider>: View where Provider: _ScrollableContentProvider {
    public var contentProvider: Provider
    public var config: _ScrollViewConfig

    public init(contentProvider: Provider, config: _ScrollViewConfig = _ScrollViewConfig()) {
        self.contentProvider = contentProvider
        self.config = config
    }

    public var body: Provider.Root {
        contentProvider.root(
            scrollView: Main(contentProvider: contentProvider, config: config)
        )
    }

    public struct Main: View {
        var contentProvider: Provider
        var config: _ScrollViewConfig

        public typealias Body = Never

        public var body: Never {
            neverBody()
        }

        public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
            guard let graph = AttributeGraph.current else {
                fatalError("_ScrollView.Main._makeView called outside an active AttributeGraph context.")
            }
            let scrollView: Attribute<_ScrollViewProxy> = graph.makeRule {
                let current = view._attribute.value
                let pageSize = inputs.size.value.value
                let contentOffset: CGPoint
                switch current.config.contentOffset {
                case .initially(let point):
                    contentOffset = point
                case .binding(let binding):
                    contentOffset = binding.wrappedValue
                }
                return _ScrollViewProxy(
                    config: current.config,
                    contentOffset: contentOffset,
                    contentSize: pageSize,
                    pageSize: pageSize
                )
            }
            let contentAttr: Attribute<Provider.ScrollableContent> = graph.makeRule {
                view._attribute.value.contentProvider.scrollableContent
            }
            var contentInputs = inputs
            contentInputs[ScrollableLayoutScrollViewProxyKey.self] = OptionalAttribute(scrollView)
            return Provider.ScrollableContent._makeView(
                view: _GraphValue(_attribute: contentAttr),
                inputs: contentInputs
            )
        }
    }
}

extension _ScrollView.Main: _PrimitiveView {
}

/// Default root that mounts a provider's scroll-view main view directly.
public struct _ScrollViewRoot<P>: View where P: _ScrollableContentProvider {
    var scrollView: _ScrollView<P>.Main

    public var body: _ScrollView<P>.Main {
        scrollView
    }
}

/// Mutable scroll-view proxy shared with scrollable layout implementations.
public struct _ScrollViewProxy: Equatable {
    public var config: _ScrollViewConfig {
        storage.config
    }

    public var contentOffset: CGPoint {
        get { storage.contentOffset }
        set { storage.contentOffset = newValue }
    }

    public var minContentOffset: CGPoint { .zero }
    public var maxContentOffset: CGPoint { .zero }
    public var contentSize: CGSize { storage.contentSize }
    public var pageSize: CGSize { storage.pageSize }
    public var visibleRect: CGRect { CGRect(origin: contentOffset, size: pageSize) }
    public var isDragging: Bool { false }
    public var isDecelerating: Bool { false }
    public var isScrolling: Bool { isDragging || isDecelerating }
    public var isScrollingHorizontally: Bool { false }
    public var isScrollingVertically: Bool { false }

    private var storage: Storage

    init(
        config: _ScrollViewConfig = _ScrollViewConfig(),
        contentOffset: CGPoint = .zero,
        contentSize: CGSize = .zero,
        pageSize: CGSize = .zero
    ) {
        self.storage = Storage(
            config: config,
            contentOffset: contentOffset,
            contentSize: contentSize,
            pageSize: pageSize
        )
    }

    public func setContentOffset(
        _ newOffset: CGPoint,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        completion?(false)
    }

    public func scrollRectToVisible(
        _ rect: CGRect,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        completion?(false)
    }

    public func contentOffsetOfNextPage(_ directions: _EventDirections) -> CGPoint {
        contentOffset
    }

    public static func == (lhs: _ScrollViewProxy, rhs: _ScrollViewProxy) -> Bool {
        lhs.storage === rhs.storage
    }

    private final class Storage {
        var config: _ScrollViewConfig
        var contentOffset: CGPoint
        var contentSize: CGSize
        var pageSize: CGSize

        init(
            config: _ScrollViewConfig,
            contentOffset: CGPoint,
            contentSize: CGSize,
            pageSize: CGSize
        ) {
            self.config = config
            self.contentOffset = contentOffset
            self.contentSize = contentSize
            self.pageSize = pageSize
        }
    }
}

/// Layout protocol that chooses visible scroll items and their placements.
public protocol _ScrollableLayout: Animatable {
    associatedtype StateType = Void
    static func initialState() -> Self.StateType
    func update(state: inout Self.StateType, proxy: inout _ScrollableLayoutProxy)

    associatedtype ItemModifier: ViewModifier = EmptyModifier
    func modifier(
        for item: _ScrollableLayoutItem,
        layout: _ScrollLayout,
        state: Self.StateType
    ) -> Self.ItemModifier

    func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint?
}

extension _ScrollableLayout where Self.StateType == Void {
    public static func initialState() -> Self.StateType {
        ()
    }
}

extension _ScrollableLayout where Self.ItemModifier == EmptyModifier {
    public func modifier(
        for item: _ScrollableLayoutItem,
        layout: _ScrollLayout,
        state: Self.StateType
    ) -> Self.ItemModifier {
        EmptyModifier()
    }
}

extension _ScrollableLayout {
    public func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint? {
        nil
    }

    public subscript<T>(data: T) -> _ScrollView<_ScrollableLayoutView<T, Self>>
        where T: RandomAccessCollection, T.Element: View, T.Index: Hashable {
        _ScrollView(contentProvider: _ScrollableLayoutView(data: data, layout: self))
    }
}

extension _ScrollableLayout where Self: RandomAccessCollection, Self.Element: View, Self.Index: Hashable {
    public subscript() -> _ScrollView<_ScrollableLayoutView<Self, Self>> {
        _ScrollView(contentProvider: _ScrollableLayoutView(data: self, layout: self))
    }
}

/// Mutable proxy used by scrollable layouts to measure and publish visible items.
public struct _ScrollableLayoutProxy: RandomAccessCollection {
    struct SizeRecord {
        var contentSeed: UInt32
        var proposal: CGSize
        var size: CGSize
    }

    final class Storage {
        var cachedSizes: [AnyHashable: SizeRecord] = [:]
    }

    public let size: CGSize
    public let visibleRect: CGRect
    public let count: Int
    public var visibleItems: [_ScrollableLayoutItem]
    public var contentSize: CGSize
    public var validRect: CGRect

    private var identifiers: [AnyHashable]
    private var contentSeed: UInt32
    private var storage: Storage
    private var measure: (AnyHashable, CGSize) -> CGSize

    init<Data>(
        data: Data,
        size: CGSize,
        visibleRect: CGRect,
        contentSeed: UInt32 = 0,
        storage: Storage = Storage(),
        measure: @escaping (AnyHashable, CGSize) -> CGSize = { _, size in size }
    ) where Data: RandomAccessCollection, Data.Index: Hashable {
        var identifiers: [AnyHashable] = []
        var index = data.startIndex
        while index != data.endIndex {
            identifiers.append(AnyHashable(index))
            index = data.index(after: index)
        }
        self.size = size
        self.visibleRect = visibleRect
        self.count = identifiers.count
        self.visibleItems = []
        self.contentSize = size
        self.validRect = visibleRect
        self.identifiers = identifiers
        self.contentSeed = contentSeed
        self.storage = storage
        self.measure = measure
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public subscript(index: Int) -> AnyHashable {
        identifiers[index]
    }

    public mutating func size(
        of identifier: AnyHashable,
        in size: CGSize,
        validatingContent: Bool = true
    ) -> CGSize {
        if let cached = storage.cachedSizes[identifier],
           cached.proposal == size,
           (!validatingContent || cached.contentSeed == contentSeed) {
            return cached.size
        }
        let measuredSize = measure(identifier, size)
        storage.cachedSizes[identifier] = SizeRecord(
            contentSeed: contentSeed,
            proposal: size,
            size: measuredSize
        )
        return measuredSize
    }

    public mutating func size(
        at index: Int,
        in size: CGSize,
        validatingContent: Bool = true
    ) -> CGSize {
        self.size(of: self[index], in: size, validatingContent: validatingContent)
    }

    public mutating func removeSize(of identifier: AnyHashable) {
        storage.cachedSizes.removeValue(forKey: identifier)
    }

    public mutating func removeAllSizes() {
        storage.cachedSizes.removeAll()
    }
}

/// One item placement emitted by a scrollable layout.
public struct _ScrollableLayoutItem: Equatable {
    public var id: AnyHashable
    private var placement: _Placement

    public var proposedSize: CGSize {
        placement.proposedSize
    }

    public var anchor: UnitPoint {
        placement.anchor
    }

    public var anchorPosition: CGPoint {
        placement.anchorPosition
    }

    public init(
        id: AnyHashable,
        proposedSize: CGSize,
        anchoring anchor: UnitPoint = .topLeading,
        at position: CGPoint
    ) {
        self.id = id
        self.placement = _Placement(
            proposedSize: proposedSize,
            anchoring: anchor,
            at: position
        )
    }

    fileprivate init(id: AnyHashable, placement: _Placement) {
        self.id = id
        self.placement = placement
    }

    var _placement: _Placement {
        placement
    }

    public static func == (a: _ScrollableLayoutItem, b: _ScrollableLayoutItem) -> Bool {
        a.id == b.id && a.placement == b.placement
    }
}

/// View wrapper that turns a random-access collection into a scrollable dynamic list.
public struct _ScrollableLayoutView<Data, Layout>: View
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Element: View,
          Data.Index: Hashable {

    var data: Data
    var layout: Layout

    init(data: Data, layout: Layout) {
        self.data = data
        self.layout = layout
    }

    public typealias Body = Never

    public var body: Never {
        neverBody()
    }

    public static func _makeView(
        view: _GraphValue<_ScrollableLayoutView<Data, Layout>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("_ScrollableLayoutView._makeView called outside an active AttributeGraph context.")
        }

        let layoutState: Attribute<ScrollableLayoutStateValue<Data, Layout>> = graph.makeStatefulRule(
            ScrollableLayoutStateRule(
                data: view[\.data]._attribute,
                layout: view[\.layout]._attribute,
                scrollView: inputs[ScrollableLayoutScrollViewProxyKey.self],
                inputs: inputs
            )
        )
        let listState = ScrollableLayoutViewListState<Data, Layout>(
            view: view._attribute,
            layoutState: layoutState,
            inputs: _ViewListInputs(from: inputs)
        )
        let viewListAttr: Attribute<any ViewList> = graph.makeRule {
            guard let graph = AttributeGraph.current else {
                fatalError("ScrollableLayoutView view-list rule evaluated outside an active AttributeGraph context.")
            }
            let state = layoutState.value
            let current = view._attribute.value
            listState.update(view: current, state: state, graph: graph)
            return ScrollableLayoutViewList(state: listState, seed: listState.seed)
        }

        var dynamicInputs = inputs
        dynamicInputs[DynamicContainerMaxUnusedItems.self] = 1
        let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
            inputs.base.cachedEnvironment.value.environment.value.layoutDirection
        }
        dynamicInputs[ScrollableLayoutItemGeometryContextKey.self] = ScrollableLayoutItemGeometryContext(
            layoutDirection: layoutDirection,
            placement: { identifier in
                layoutState.value.placement(for: identifier)
            }
        )
        let geometryContext = dynamicInputs[ScrollableLayoutItemGeometryContextKey.self]
        let containerInfo: Attribute<DynamicContainer.Info> = graph.makeStatefulRule(
            DynamicContainerInfo(viewListAttr: viewListAttr, inputs: dynamicInputs)
        )
        geometryContext?.containerInfo = containerInfo
        let layoutComputer: Attribute<LayoutComputer> = graph.makeRule(
            ScrollableLayoutComputerRule(layoutState: layoutState, containerInfo: containerInfo)
        )

        var preferences = PreferencesOutputs()
        for keyType in inputs.preferences.keys.keys {
            let nodeListAttr: Attribute<[AGWeakAttribute]> = graph.makeRule {
                let info = containerInfo.value
                return info.activeAndRemovedItems.flatMap { item in
                    item.preferenceOutputs.flatMap { preferences in
                        preferences.values(for: keyType).compactMap {
                            graph.weakAttributeIfValid(for: $0)
                        }
                    }
                }
            }
            let reducedID = _makeDynReduceAttr(keyType, nodeListAttr: nodeListAttr, in: graph)
            preferences.append(keyType, node: reducedID)
        }

        return _ViewOutputs(
            preferences: preferences,
            layoutComputer: OptionalAttribute(layoutComputer)
        )
    }
}

extension _ScrollableLayoutView: _PrimitiveView {
}

extension _ScrollableLayoutView: _ScrollableContentProvider {
    public var scrollableContent: _ScrollableLayoutView<Data, Layout> {
        self
    }

    public func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint? {
        layout.decelerationTarget(
            contentOffset: contentOffset,
            originalContentOffset: originalContentOffset,
            velocity: velocity,
            size: size
        )
    }
}

/// Maximum retained-unused dynamic items a scrollable layout may keep alive.
struct DynamicContainerMaxUnusedItems: ViewInput {
    static var defaultValue: Int { 0 }
}

/// Carries the scroll-view proxy into scrollable layout construction.
private struct ScrollableLayoutScrollViewProxyKey: ViewInput {
    static var defaultValue: OptionalAttribute<_ScrollViewProxy> { OptionalAttribute() }

    static func valuesEqual(
        _ lhs: OptionalAttribute<_ScrollViewProxy>,
        _ rhs: OptionalAttribute<_ScrollViewProxy>
    ) -> Bool {
        lhs.base.identifier == rhs.base.identifier
    }
}

/// Cached scrollable layout output shared by measurement, view-list, and placement rules.
private struct ScrollableLayoutStateValue<Data, Layout>
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Index: Hashable {

    var layoutState: Layout.StateType
    var stateSeed: UInt32
    var contentSeed: UInt32
    var scrollLayout: _ScrollLayout
    var identifiers: [Data.Index]
    var placements: [Data.Index: _Placement]
    var contentSize: CGSize
    var validRect: CGRect

    var visibleItems: [_ScrollableLayoutItem] {
        identifiers.compactMap { index in
            guard let placement = placements[index] else { return nil }
            return _ScrollableLayoutItem(id: AnyHashable(index), placement: placement)
        }
    }

    func placement(for identifier: AnyHashable) -> _Placement? {
        guard let index = identifier.base as? Data.Index else { return nil }
        return placements[index]
    }
}

/// Stateful rule that updates scroll layout state, content seed, and measurement cache.
private struct ScrollableLayoutStateRule<Data, Layout>: StatefulRule
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Element: View,
          Data.Index: Hashable {

    typealias Value = ScrollableLayoutStateValue<Data, Layout>

    var data: Attribute<Data>
    var layout: Attribute<Layout>
    var scrollView: OptionalAttribute<_ScrollViewProxy>
    var inputs: _ViewInputs
    var layoutState: Layout.StateType = Layout.initialState()
    var stateSeed: UInt32 = 0
    var contentSeed: UInt32 = 0
    var proxyStorage = _ScrollableLayoutProxy.Storage()
    var measurementTemplate: ScrollableLayoutMeasurementTemplate<Data>?

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("ScrollableLayoutStateRule.updateValue called outside an active AttributeGraph context.")
        }
        let dataValue = data.value
        let layoutValue = layout.value
        let proxyValue = scrollView.attribute?.value
        let containerSize = proxyValue?.pageSize ?? inputs.size.value.value
        let contentInsets = proxyValue?.config.contentInsets ?? EdgeInsets()
        let visibleSize = containerSize.inset(by: contentInsets)
        let contentOffset = proxyValue?.contentOffset ?? .zero
        let visibleRect = CGRect(
            x: contentOffset.x - contentInsets.leading,
            y: contentOffset.y - contentInsets.top,
            width: visibleSize.width,
            height: visibleSize.height
        )
        let scrollLayout = _ScrollLayout(
            contentOffset: contentOffset,
            size: visibleSize,
            visibleRect: visibleRect
        )
        if measurementTemplate == nil, let first = dataValue.first {
            measurementTemplate = ScrollableLayoutMeasurementTemplate(
                initialContent: first,
                inputs: inputs,
                graph: graph
            )
        }

        let previous = AttributeGraph.currentStatefulOutput(Value.self)
        let firstEvaluation = previous == nil
        let contentChanged = firstEvaluation ||
            AttributeGraph.currentStatefulInputChanged(data.identifier)
        let layoutChanged = firstEvaluation ||
            AttributeGraph.currentStatefulInputChanged(layout.identifier)
        if contentChanged {
            contentSeed &+= 1
        }
        let template = measurementTemplate

        if !layoutChanged,
           !contentChanged,
           let previous,
           previous.scrollLayout.size == scrollLayout.size,
           previous.validRect.contains(scrollLayout.visibleRect) {
            var value = previous
            value.scrollLayout = scrollLayout
            AttributeGraph.setStatefulOutput(value)
            return
        }

        var proxy = _ScrollableLayoutProxy(
            data: dataValue,
            size: visibleSize,
            visibleRect: visibleRect,
            contentSeed: contentSeed,
            storage: proxyStorage
        ) { identifier, proposedSize in
            guard let index = identifier.base as? Data.Index,
                  dataValue.indices.contains(index),
                  let template else {
                return proposedSize
            }
            return template.sizeThatFits(proposedSize, content: dataValue[index])
        }
        layoutValue.update(state: &layoutState, proxy: &proxy)

        var identifiers: [Data.Index] = []
        var placements: [Data.Index: _Placement] = [:]
        for item in proxy.visibleItems {
            guard let index = item.id.base as? Data.Index else { continue }
            identifiers.append(index)
            placements[index] = item._placement
        }

        // State changes every layout update; content changes only when the source
        // view payload changes, so proxy size caches survive pure geometry updates.
        stateSeed &+= 1
        AttributeGraph.setStatefulOutput(
            ScrollableLayoutStateValue<Data, Layout>(
                layoutState: layoutState,
                stateSeed: stateSeed,
                contentSeed: contentSeed,
                scrollLayout: scrollLayout,
                identifiers: identifiers,
                placements: placements,
                contentSize: proxy.contentSize,
                validRect: proxy.validRect
            )
        )
    }
}

/// Reusable hidden child used to measure arbitrary collection elements off the main list.
private final class ScrollableLayoutMeasurementTemplate<Data>
    where Data: RandomAccessCollection,
          Data.Element: View,
          Data.Index: Hashable {

    private let subgraph: AGSubgraph
    private let content: Attribute<Data.Element>
    private let delta: Attribute<UInt32>
    private let outputs: _ViewOutputs
    private var seed: UInt32 = 0

    init(
        initialContent: Data.Element,
        inputs: _ViewInputs,
        graph: AttributeGraph
    ) {
        let subgraph = AGSubgraph()
        let built = AGSubgraph.$current.withValue(subgraph) {
            var templateInputs = inputs
            templateInputs.copyCaches()
            templateInputs.position = graph.makeInput(value: CGPoint.zero)
            templateInputs.size = graph.makeInput(value: ViewSize(.zero))
            templateInputs.containerPosition = inputs.position
            templateInputs.containerSize = OptionalAttribute(inputs.size)

            let content = graph.makeInput(value: initialContent)
            let delta = graph.makeInput(value: UInt32.zero)
            let gatedContent: Attribute<Data.Element> = graph.makeRule {
                _ = delta.value
                return content.value
            }
            let outputs = Data.Element._makeView(
                view: _GraphValue(_attribute: gatedContent),
                inputs: templateInputs
            )
            return (content, delta, outputs)
        }

        self.subgraph = subgraph
        self.content = built.0
        self.delta = built.1
        self.outputs = built.2
    }

    deinit {
        guard AttributeGraph.current != nil else { return }
        subgraph.invalidate()
        subgraph.removeFromParent()
    }

    func sizeThatFits(_ proposal: CGSize, content newContent: Data.Element) -> CGSize {
        seed &+= 1
        delta.setValue(seed)
        content.setValue(newContent)
        let layoutComputer = outputs._layoutComputer.attribute?.value ?? LayoutComputer.defaultValue
        return layoutComputer.sizeThatFits(ProposedViewSize(proposal))
    }
}

/// Owns per-visible-item subgraphs and retains a small unused tail for scroll reuse.
private final class ScrollableLayoutViewListState<Data, Layout>
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Element: View,
          Data.Index: Hashable {

    typealias RowContent = ModifiedContent<Data.Element, Layout.ItemModifier>

    struct Item {
        var elements: _ViewList_SubgraphElements
        var subgraph: AGSubgraph
        var traitListAttr: OptionalAttribute<ViewTraitCollection>

        var traits: ViewTraitCollection {
            traitListAttr.attribute?.value ?? ViewTraitCollection()
        }

        func invalidate() {
            subgraph.invalidate()
            subgraph.removeFromParent()
        }
    }

    var view: Attribute<_ScrollableLayoutView<Data, Layout>>
    var layoutState: Attribute<ScrollableLayoutStateValue<Data, Layout>>
    var inputs: _ViewListInputs
    var items: [AnyHashable: Item] = [:]
    var order: [AnyHashable] = []
    var seed: UInt32 = 0

    init(
        view: Attribute<_ScrollableLayoutView<Data, Layout>>,
        layoutState: Attribute<ScrollableLayoutStateValue<Data, Layout>>,
        inputs: _ViewListInputs
    ) {
        self.view = view
        self.layoutState = layoutState
        self.inputs = inputs
    }

    func update(
        view current: _ScrollableLayoutView<Data, Layout>,
        state: ScrollableLayoutStateValue<Data, Layout>,
        graph: AttributeGraph
    ) {
        var nextOrder: [AnyHashable] = []
        var liveIDs = Set<AnyHashable>()

        for visibleItem in state.visibleItems {
            guard let index = visibleItem.id.base as? Data.Index,
                  current.data.indices.contains(index) else {
                continue
            }

            let id = visibleItem.id
            nextOrder.append(id)
            liveIDs.insert(id)

            if items[id] == nil {
                let subgraph = AGSubgraph()
                let contentAttr: Attribute<RowContent> = AGSubgraph.$current.withValue(subgraph) {
                    graph.makeRule {
                        let current = self.view.value
                        let state = self.layoutState.value
                        let element = current.data[index]
                        let item = state.visibleItems.first { $0.id == id } ?? visibleItem
                        let modifier = current.layout.modifier(
                            for: item,
                            layout: state.scrollLayout,
                            state: state.layoutState
                        )
                        return ModifiedContent(content: element, modifier: modifier)
                    }
                }
                let generator = TypedUnaryViewGenerator(
                    _GraphValue(_attribute: contentAttr),
                    inputs: inputs
                )
                var elements = _ViewList_SubgraphElements(base: UnaryElements(generator: generator))
                elements.wrap(subgraph: _ViewList_Subgraph(subgraph: subgraph))
                items[id] = Item(
                    elements: elements,
                    subgraph: subgraph,
                    traitListAttr: generator.traitListAttr
                )
            }
        }

        var retainedUnused = Set<AnyHashable>()
        for id in order where !liveIDs.contains(id) && retainedUnused.count < 1 {
            retainedUnused.insert(id)
        }
        for id in Array(items.keys) where !liveIDs.contains(id) && !retainedUnused.contains(id) {
            items[id]?.invalidate()
            items.removeValue(forKey: id)
        }

        if nextOrder != order {
            seed &+= 1
            order = nextOrder
        }
    }
}

/// ViewList facade over the visible item subgraphs owned by ScrollableLayoutViewListState.
private struct ScrollableLayoutViewList<Data, Layout>: ViewList
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Element: View,
          Data.Index: Hashable {

    var state: ScrollableLayoutViewListState<Data, Layout>
    var seed: UInt32

    func count(style: _ViewList_IteratorStyle) -> Int {
        state.order.count
    }

    func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
        state.order.count
    }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        for id in state.order {
            guard let item = state.items[id] else { continue }
            if from > 0 {
                from -= 1
                continue
            }
            let sublist = _ViewList_Sublist(
                start: 0,
                count: 1,
                id: _ViewList_ID(explicitID: id),
                elements: item.elements,
                traits: item.traits,
                list: list
            )
            let shouldContinue = to(&from, style, .sublist(sublist), transform)
            from = 0
            if !shouldContinue { return false }
        }
        return true
    }
}

/// Builds a layout computer that places retained dynamic item layout computers.
private struct ScrollableLayoutComputerRule<Data, Layout>: Rule
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Index: Hashable {

    typealias Value = LayoutComputer

    var layoutState: Attribute<ScrollableLayoutStateValue<Data, Layout>>
    var containerInfo: Attribute<DynamicContainer.Info>

    func updateValue() -> LayoutComputer {
        let state = layoutState.value
        let info = containerInfo.value
        let activeItems = Array(info.activeItems)
        let contentSize = state.contentSize
        let placements = state.placements

        for item in activeItems {
            _ = item.layoutAttributes.first?.layoutComputer.attribute?.value
        }

        return LayoutComputer(
            sizeThatFits: { proposal in
                contentSize == .zero ? proposal.replacingUnspecifiedDimensions() : contentSize
            },
            place: { position, anchor, proposal in
                let origin = CGPoint(
                    x: position.x - contentSize.width * anchor.x,
                    y: position.y - contentSize.height * anchor.y
                )
                for item in activeItems {
                    guard let index = item.item?.base as? Data.Index,
                          let placement = placements[index],
                          let childComputer = item.layoutAttributes.first?.layoutComputer.attribute?.value else {
                        continue
                    }
                    let anchorPosition = CGPoint(
                        x: origin.x + placement.anchorPosition.x,
                        y: origin.y + placement.anchorPosition.y
                    )
                    childComputer.place(
                        at: anchorPosition,
                        anchor: placement.anchor,
                        proposal: ProposedViewSize(placement.proposedSize)
                    )
                }
            }
        )
    }
}
