//
//  File: ScrollView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Stored configuration backing the public ScrollView shell.
struct ScrollViewConfiguration {
    var axes: Axis.Set
    var showsIndicators: Bool
    var contentInsets: EdgeInsets
    var isScrollEnabled: Bool?
    var automaticallyAdjustsContentInsets: Bool
    var interactionActivityTag: AnyHashable?

    init(
        axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        contentInsets: EdgeInsets = EdgeInsets(),
        isScrollEnabled: Bool? = nil,
        automaticallyAdjustsContentInsets: Bool = true,
        interactionActivityTag: AnyHashable? = nil
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.contentInsets = contentInsets
        self.isScrollEnabled = isScrollEnabled
        self.automaticallyAdjustsContentInsets = automaticallyAdjustsContentInsets
        self.interactionActivityTag = interactionActivityTag
    }

    var nonScrollableEdges: Edge.Set {
        var edges = Edge.Set.all
        if axes.contains(.horizontal) {
            edges.subtract(Edge.Set.horizontal)
        }
        if axes.contains(.vertical) {
            edges.subtract(Edge.Set.vertical)
        }
        return edges
    }
}

/// Scroll container view that wraps content in the system scroll-view shell.
public struct ScrollView<Content>: View where Content: View {
    public var content: Content
    var configuration: ScrollViewConfiguration

    public var axes: Axis.Set {
        get { configuration.axes }
        set { configuration.axes = newValue }
    }

    public var showsIndicators: Bool {
        get { configuration.showsIndicators }
        set { configuration.showsIndicators = newValue }
    }

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.configuration = ScrollViewConfiguration(
            axes: axes,
            showsIndicators: showsIndicators
        )
    }

    public var body: SystemScrollViewContainer<Content> {
        SystemScrollViewContainer(configuration: configuration, content: content)
    }
}

extension ScrollView {
    public var _contentInsets: EdgeInsets {
        get { configuration.contentInsets }
        set { configuration.contentInsets = newValue }
    }

    public var _automaticallyAdjustsContentInsets: Bool {
        get { configuration.automaticallyAdjustsContentInsets }
        set { configuration.automaticallyAdjustsContentInsets = newValue }
    }
}

/// Builds the modifier stack around content before mounting the primitive scroll host.
public struct SystemScrollViewContainer<Content>: View where Content: View {
    var configuration: ScrollViewConfiguration
    var content: Content

    public var body: some View {
        let scrollContent = content
            .modifier(StyleContextWriter<ScrollViewStyleContext>())
            .modifier(StaticIf<
                _SemanticFeature<Semantics_v4>,
                RefreshScopeModifier,
                EmptyModifier
            >(trueBody: RefreshScopeModifier(), falseBody: EmptyModifier()))
            .modifier(StaticIf<
                _SemanticFeature<Semantics_v5>,
                ResetScrollEnvironmentModifier,
                EmptyModifier
            >(trueBody: ResetScrollEnvironmentModifier(), falseBody: EmptyModifier()))
            .modifier(StaticIf<
                InertPaddingLayoutRequired,
                _PaddingLayout,
                EmptyModifier
            >(
                trueBody: _PaddingLayout(edges: .all, insets: configuration.contentInsets),
                falseBody: EmptyModifier()
            ))
            .modifier(ResetScrollInputsModifier())
            .modifier(ResetContentMarginModifier(placements: [
                .automatic,
                .scrollContent,
                .scrollIndicators,
            ]))
            .modifier(EnvironmentAxesModifier(scrollableAxes: configuration.axes))

        let scrollView = SystemScrollView(
            configuration: configuration,
            content: scrollContent
        )
        return _UnaryViewAdaptor(
            scrollView
                .modifier(StaticIf<
                    BothFeatures<_SemanticFeature<Semantics_v4>, InferredToolbarUserDefaultFeature>,
                    ToolbarScopeModifier,
                    EmptyModifier
                >(trueBody: ToolbarScopeModifier(), falseBody: EmptyModifier()))
                .modifier(ResolvedScrollBehaviorModifier(axes: configuration.axes))
                .modifier(ScrollPhaseStateConfigurationModifier())
        )
    }
}

/// Primitive scroll host that publishes scrollable, phase, and geometry preferences.
struct SystemScrollView<Content>: View where Content: View {
    var configuration: ScrollViewConfiguration
    var content: Content

    typealias Body = Never

    var body: Never {
        neverBody()
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("SystemScrollView._makeView called outside an active _AGGraph context.")
        }

        var contentInputs = inputs
        let phaseState = contentInputs.base.scrollPhaseState.attribute ?? {
            let state = graph.makeInput(value: ScrollPhaseState())
            contentInputs.base.appendScrollPhaseState(OptionalAttribute(state))
            return state
        }()

        let configuration = view[\.configuration]._attribute
        let scrollableAxes: Attribute<Axis.Set> = graph.makeRule {
            configuration.value.axes
        }
        let layoutState: Attribute<SystemScrollLayoutState> = graph.makeInput(
            value: SystemScrollLayoutState()
        )
        let graphRef = _AGGraphContext.current ?? _AGGraphContext(graph: graph)
        let hostingScrollView: Attribute<HostingScrollView> = graph.makeStatefulRule(
            MakeHostingScrollView(
                _layoutState: layoutState,
                _phaseState: phaseState,
                graphRef: graphRef
            )
        )
        let scrollable = ScrollViewScrollable(
            graphRef: graphRef,
            layoutState: layoutState,
            hostingScrollView: hostingScrollView
        )
        let scrollableAttr: Attribute<any Scrollable> = graph.makeRule(
            ScrollableProvider(scrollable: scrollable)
        )
        let contentGeometry = graph.makeIndirectAttribute(defaultValue: ScrollGeometry())
        let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
            inputs.base.cachedEnvironment.value.environment.value.layoutDirection
        }
        contentInputs.scrollable = OptionalAttribute(scrollableAttr)
        let childSafeArea = graph.makeRule(
            ScrollViewChildSafeArea(
                safeAreaInsets: inputs.safeAreaInsets,
                configuration: configuration
            )
        )
        let safeAreaPosition: Attribute<CGPoint> = graph.makeRule(
            ScrollViewChildPosition(
                safeAreaInsets: childSafeArea,
                axes: scrollableAxes,
                layoutDirection: layoutDirection
            )
        )
        contentInputs.transform = graph.makeRule(
            ScrollViewContentTransformProvider(
                transform: inputs.transform,
                position: inputs.position,
                safeAreaPosition: safeAreaPosition,
                geometry: contentGeometry,
                axes: scrollableAxes
            )
        )
        contentInputs.safeAreaInsets = OptionalAttribute(graph.makeRule(
            ScrollViewChildSafeAreaInsets(
                safeAreaInsets: childSafeArea,
                layoutDirection: layoutDirection
            )
        ))
        contentInputs.preferences.keys.insert(ScrollablePreferenceKey.self)
        contentInputs.preferences.keys.insert(UpdateScrollStateRequestKey.self)

        let contentOutputs = Content._makeView(view: view[\.content], inputs: contentInputs)
        let layoutComputer: Attribute<LayoutComputer> = graph.makeRule(
            ScrollViewLayoutComputerProvider(
                contentLayout: contentOutputs._layoutComputer.attribute?.asWeak() ?? WeakAttribute()
            )
        )
        let scrollLayoutComputer = OptionalAttribute(layoutComputer)
        var outputs = contentOutputs
        outputs._layoutComputer = scrollLayoutComputer

        let frame: Attribute<ViewFrame> = graph.makeRule(
            ViewFrameProvider(
                position: inputs.position,
                containerSize: inputs.size,
                layoutComputer: scrollLayoutComputer
            )
        )
        let anchorStorage = graph.makeInput(value: ScrollAnchorStorage())
        let defaultAnchors: Attribute<ScrollAnchorStorage> = graph.makeStatefulRule(
            ScrollViewDefaultAnchors(
                _configuration: configuration,
                _anchors: anchorStorage
            )
        )
        let pixelLength: Attribute<CGFloat> = graph.makeRule {
            inputs.base.cachedEnvironment.value.environment.value.animationPixelLength
        }
        let positionBinding = inputs.base.scrollPositionBinding(kind: .scrollView).attribute?.value
        let adjustedState: Attribute<SystemScrollLayoutState> = graph.makeStatefulRule(
            ScrollViewAdjustedState(
                _size: inputs.size,
                _configuration: configuration,
                _defaultAnchors: defaultAnchors,
                _state: layoutState,
                _phaseState: phaseState,
                _contentFrame: frame,
                _pixelLength: pixelLength,
                _phase: inputs.base.phase,
                _transaction: inputs.base.transaction,
                _layoutDirection: layoutDirection,
                _positionBinding: positionBinding
            )
        )
        let environment = inputs.base.cachedEnvironment.value.environment
        let scrollEnvironmentStorage: Attribute<ScrollEnvironmentStorage> = graph.makeRule {
            environment.value.scrollEnvironmentStorage
        }
        let behaviorProperties: Attribute<ScrollTargetBehaviorProperties> = graph.makeStatefulRule(
            ScrollViewAdjustedBehaviorProperties(
                _configuration: configuration,
                _environment: environment,
                _storage: scrollEnvironmentStorage
            )
        )
        let isEnabled: Attribute<Bool> = graph.makeRule {
            environment.value.isEnabled
        }
        let scrollEnvironmentProperties: Attribute<ScrollEnvironmentProperties> = graph.makeRule(
            ScrollViewAdjustedProperties(
                _configuration: configuration,
                _scrollStorage: scrollEnvironmentStorage,
                _behaviorProperties: behaviorProperties,
                _layoutDirection: layoutDirection,
                _isEnabled: isEnabled,
                _isContainedInPlatter: OptionalAttribute()
            )
        )
        let alignmentAdjustment: Attribute<CGSize> = graph.makeRule(
            ScrollViewAlignmentAdjustment(
                _configuration: configuration,
                _scrollAnchors: defaultAnchors,
                _contentFrame: frame,
                _size: inputs.size
            )
        )
        let rtlAdjustment: Attribute<CGSize> = graph.makeRule(
            ScrollViewRTLAlignmentAdjustment(
                _configuration: configuration,
                _scrollAnchors: defaultAnchors,
                _contentFrame: frame,
                _size: inputs.size,
                _layoutDirection: layoutDirection
            )
        )
        let adjustedSafeArea: Attribute<EdgeInsets> = graph.makeRule(
            ScrollViewAdjustedSafeArea(
                _safeArea: childSafeArea,
                _configuration: configuration,
                _alignmentAdjustment: alignmentAdjustment,
                _rtlAdjustment: rtlAdjustment
            )
        )
        let containerSize: Attribute<CGSize> = graph.makeRule {
            inputs.size.value.value
        }
        let updatedHostingScrollView: Attribute<HostingScrollView> = graph.makeStatefulRule(
            UpdatedHostingScrollView(
                _scrollView: hostingScrollView,
                _configuration: configuration,
                _properties: scrollEnvironmentProperties,
                _contentFrame: frame,
                _size: containerSize,
                _safeAreaInsets: adjustedSafeArea,
                _rtlAdjustment: rtlAdjustment,
                _adjustedState: adjustedState,
                _environment: environment
            )
        )
        _ = graph.makeSideEffectRule {
            _ = updatedHostingScrollView.value
            return ()
        }
        // Motion is sampled from the graph clock, while the host object remains
        // stable across frames and owns the in-flight deceleration state.
        let motionHostingScrollView: Attribute<HostingScrollView> = graph.makeStatefulRule(
            HostingScrollViewMotionUpdate(
                _scrollView: updatedHostingScrollView,
                _time: inputs.base.time
            )
        )
        _ = graph.makeSideEffectRule {
            _ = motionHostingScrollView.value
            return ()
        }
        let geometry: Attribute<ScrollGeometry> = graph.makeRule(
            ScrollGeometryProvider(
                layoutState: adjustedState,
                frame: frame,
                size: inputs.size,
                layoutDirection: layoutDirection
            )
        )
        graph.setIndirectTarget(contentGeometry, to: geometry)
        scrollable.bindGeometry(geometry, layoutDirection: layoutDirection)
        if let childScrollables = contentOutputs.preferences.value(for: ScrollablePreferenceKey.self) {
            scrollable.bindChildScrollables(Attribute<[any Scrollable]>(childScrollables))
        }

        if inputs.preferences.keys.contains(ScrollablePreferenceKey.self) {
            let preferenceAttr: Attribute<[any Scrollable]> = graph.makeRule(
                ScrollablePreferenceProvider(scrollable: scrollableAttr)
            )
            outputs.preferences.setValue(preferenceAttr.identifier, for: ScrollablePreferenceKey.self)
        }

        if inputs.preferences.keys.contains(ScrollGeometryPreferenceKey.self) {
            let transform: Attribute<ViewTransform> = graph.makeRule(
                ScrollGeometryTransformProvider(
                    position: inputs.position,
                    transform: inputs.transform
                )
            )
            let preferenceAttr: Attribute<[ScrollGeometryState]> = graph.makeRule(
                ScrollGeometryStateProvider(
                    geometry: geometry,
                    scrollableAxes: scrollableAxes,
                    transform: transform
                )
            )
            outputs.preferences.setValue(preferenceAttr.identifier, for: ScrollGeometryPreferenceKey.self)
        }

        let enqueueRequests: Attribute<Void> = graph.makeStatefulRule(
            ScrollStateEnqueueRequests(
                phaseState: phaseState,
                scrollable: scrollableAttr,
                inputs: contentInputs,
                outputs: contentOutputs
            )
        )
        _ = graph.makeSideEffectRule {
            _ = enqueueRequests.value
            return ()
        }

        let gestureModifier: Attribute<SystemScrollViewGesture> = graph.makeRule {
            SystemScrollViewGesture(scrollView: motionHostingScrollView.value)
        }
        // Wrap the completed content outputs so child responders remain nested
        // under the scroll responder for click-versus-pan arbitration.
        return SystemScrollViewGesture.makeView(
            modifier: _GraphValue(_attribute: gestureModifier),
            inputs: inputs
        ) { _, _ in
            outputs
        }
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Content._makeViewList(view: view[\.content], inputs: inputs)
    }
}

private struct ScrollViewChildSafeArea: Rule {
    typealias Value = EdgeInsets

    var safeAreaInsets: OptionalAttribute<SafeAreaInsets>
    var configuration: Attribute<ScrollViewConfiguration>

    func updateValue() -> EdgeInsets {
        guard let insets = safeAreaInsets.attribute?.value.value else {
            return EdgeInsets()
        }
        let edges = _SemanticFeature<Semantics_v6>.isEnabled
            ? configuration.value.nonScrollableEdges
            : Edge.Set(rawValue: 0)
        return insets.in(edges)
    }
}

private struct ScrollViewChildPosition: Rule {
    typealias Value = CGPoint

    var safeAreaInsets: Attribute<EdgeInsets>
    var axes: Attribute<Axis.Set>
    var layoutDirection: Attribute<LayoutDirection>

    func updateValue() -> CGPoint {
        guard _SemanticFeature<Semantics_v6>.isEnabled else {
            return .zero
        }
        let offset = safeAreaInsets.value
            .xFlipIfRightToLeft { layoutDirection.value }
            .in(originOffsetEdges)
            .originOffset
        return CGPoint(x: offset.width, y: offset.height)
    }

    private var originOffsetEdges: Edge.Set {
        if layoutDirection.value == .rightToLeft && axes.value == .vertical {
            return .vertical
        }
        return .all
    }
}

private struct ScrollViewChildSafeAreaInsets: Rule {
    typealias Value = SafeAreaInsets

    var safeAreaInsets: Attribute<EdgeInsets>
    var layoutDirection: Attribute<LayoutDirection>

    func updateValue() -> SafeAreaInsets {
        let elements: [SafeAreaInsets.Element] = _SemanticFeature<Semantics_v6>.isEnabled
            ? [
                SafeAreaInsets.Element(
                    regions: .container,
                    insets: safeAreaInsets.value.xFlipIfRightToLeft { layoutDirection.value },
                    cornerInsets: nil
                ),
            ]
            : []
        return SafeAreaInsets(
            space: ScrollCoordinateSpace.safeArea.id,
            elements: elements
        )
    }
}

/// Scrollable facade that sends graph requests through the hosting state carrier.
private final class ScrollViewScrollable: Scrollable {
    private let graphRef: _AGGraphContext
    private let layoutState: Attribute<SystemScrollLayoutState>
    private let hostingScrollView: Attribute<HostingScrollView>
    private var geometry: Attribute<ScrollGeometry>?
    private var layoutDirection: Attribute<LayoutDirection>?
    private var childScrollables: Attribute<[any Scrollable]>?

    init(
        graphRef: _AGGraphContext,
        layoutState: Attribute<SystemScrollLayoutState>,
        hostingScrollView: Attribute<HostingScrollView>
    ) {
        self.graphRef = graphRef
        self.layoutState = layoutState
        self.hostingScrollView = hostingScrollView
    }

    func bindGeometry(
        _ geometry: Attribute<ScrollGeometry>,
        layoutDirection: Attribute<LayoutDirection>
    ) {
        self.geometry = geometry
        self.layoutDirection = layoutDirection
    }

    func bindChildScrollables(_ childScrollables: Attribute<[any Scrollable]>) {
        self.childScrollables = childScrollables
    }

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        graphRef.withCurrent {
            guard let childScrollables else { return false }
            for child in childScrollables.value {
                if child.scroll(to: id) {
                    return true
                }
            }
            return false
        }
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        graphRef.withCurrent {
            guard let geometry,
                  let layoutDirection,
                  let resolvedTarget = target(geometry.value, layoutDirection.value) else {
                return false
            }
            setContentOffset(
                resolvedTarget.contentOffset(in: geometry.value),
                mode: .target(
                    target,
                    config: ScrollTargetConfiguration(transaction: Transaction.current)
                )
            )
            return true
        }
    }

    var allowsContentOffsetAdjustments: Bool {
        true
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        graphRef.withCurrent {
            let current = layoutState.value.contentOffset
            setContentOffset(
                CGPoint(
                    x: current.x + offset.width,
                    y: current.y + offset.height
                ),
                mode: .adjustment(reason: reason)
            )
            return true
        }
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        graphRef.withCurrent {
            guard let childScrollables else { return nil }
            for child in childScrollables.value {
                if let typedChild = child as? A {
                    return body(typedChild)
                }
                if let result = child.mapFirstChild(ofType: type, body: body) {
                    return result
                }
            }
            return nil
        }
    }

    private func setContentOffset(
        _ contentOffset: CGPoint,
        mode: SystemScrollLayoutState.ContentOffsetMode
    ) {
        var state = layoutState.value
        state.contentOffset = contentOffset
        state.contentOffsetMode = mode
        state.contentOffsetSeed.value &+= 1
        layoutState.setValue(state, transaction: Transaction.current)
        _ = hostingScrollView.value
    }
}

private extension ScrollTarget {
    func contentOffset(in geometry: ScrollGeometry) -> CGPoint {
        guard let anchor else {
            return rect.origin
        }
        return CGPoint(
            x: rect.minX + rect.width * anchor.x - geometry.visibleRect.width * anchor.x,
            y: rect.minY + rect.height * anchor.y - geometry.visibleRect.height * anchor.y
        )
    }
}

/// Exposes the container's scrollable host through the preference graph.
private struct ScrollableProvider: Rule {
    typealias Value = any Scrollable

    var scrollable: ScrollViewScrollable

    func updateValue() -> any Scrollable {
        scrollable
    }
}

/// Wraps one scrollable host in the preference payload shape.
private struct ScrollablePreferenceProvider: Rule {
    typealias Value = [any Scrollable]

    var scrollable: Attribute<any Scrollable>

    func updateValue() -> [any Scrollable] {
        [scrollable.value]
    }
}

/// Host-owned layout relay for the scroll container's child content.
private struct ScrollViewLayoutComputerProvider: Rule {
    typealias Value = LayoutComputer

    var contentLayout: WeakAttribute<LayoutComputer>

    func updateValue() -> LayoutComputer {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewLayoutComputerProvider.updateValue called outside AG context.")
        }
        guard contentLayout.isValid(in: graph) else {
            return LayoutComputer.defaultValue
        }

        let inner = contentLayout.toStrong().value
        return LayoutComputer(
            sizeThatFits: { proposal in
                inner.sizeThatFits(proposal)
            },
            spacing: inner.spacing,
            place: { position, anchor, proposal in
                inner.place(at: position, anchor: anchor, proposal: proposal)
            },
            childGeometries: { size, origin in
                inner.childGeometries(at: size, origin: origin)
            },
            priority: inner.priority,
            explicitAlignment: { key, size in
                inner.explicitAlignment(key, at: size)
            }
        )
    }
}

/// Combines position and size inputs into a single content frame.
private struct ViewFrameProvider: Rule {
    typealias Value = ViewFrame

    var position: Attribute<CGPoint>
    var containerSize: Attribute<ViewSize>
    var layoutComputer: OptionalAttribute<LayoutComputer>

    func updateValue() -> ViewFrame {
        let containerSize = containerSize.value
        let contentSize = layoutComputer.attribute?.value.sizeThatFits(
            ProposedViewSize(containerSize.value)
        ) ?? containerSize.value
        return ViewFrame(
            origin: position.value,
            size: ViewSize(contentSize, proposal: ProposedViewSize(containerSize.value))
        )
    }
}

/// Derives ScrollGeometry from layout state, view frame, and layout direction.
private struct ScrollGeometryProvider: Rule {
    typealias Value = ScrollGeometry

    var layoutState: Attribute<SystemScrollLayoutState>
    var frame: Attribute<ViewFrame>
    var size: Attribute<ViewSize>
    var layoutDirection: Attribute<LayoutDirection>

    func updateValue() -> ScrollGeometry {
        let state = layoutState.value
        let containerSize = size.value.value
        let contentSize = frame.value.size.value
        let visibleSize = containerSize.outset(by: state.contentInsets)
        var geometry = ScrollGeometry(
            contentOffset: state.contentOffset,
            contentSize: contentSize,
            contentInsets: state.contentInsets,
            containerSize: containerSize,
            visibleRect: CGRect(origin: state.contentOffset, size: visibleSize)
        )
        geometry.applyLayoutDirection(layoutDirection.value)
        return geometry
    }
}

/// Extends the content transform with the scroll view's frame position.
private struct ScrollGeometryTransformProvider: Rule {
    typealias Value = ViewTransform

    var position: Attribute<CGPoint>
    var transform: Attribute<ViewTransform>

    func updateValue() -> ViewTransform {
        var value = transform.value
        value.appendPosition(position.value)
        return value
    }
}

/// Placeholder modifier that preserves refresh-scope placement in the modifier stack.
private struct RefreshScopeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

/// Predicate used for padding paths that must always participate in layout.
private struct InertPaddingLayoutRequired: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        true
    }
}

/// Clears scroll phase and geometry preference requests below a scroll boundary.
private struct ResetScrollInputsModifier: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
    }

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var inputs = inputs
        inputs.preferences.keys.remove(ScrollPhasePreferenceKey.self)
        inputs.preferences.keys.remove(ScrollGeometryPreferenceKey.self)
        return body(_Graph(), inputs)
    }
}

/// Selects which scroll margin channel a content-margin modifier targets.
public struct ContentMarginPlacement {
    enum Role: UInt8 {
        case automatic = 0
        case scrollContent = 1
        case scrollIndicators = 2
        case toolbar = 3
    }

    var role: Role

    init(role: Role) {
        self.role = role
    }

    public static var automatic: ContentMarginPlacement {
        ContentMarginPlacement(role: .automatic)
    }

    public static var scrollContent: ContentMarginPlacement {
        ContentMarginPlacement(role: .scrollContent)
    }

    public static var scrollIndicators: ContentMarginPlacement {
        ContentMarginPlacement(role: .scrollIndicators)
    }
}

struct OptionalEdgeInsets: Equatable {
    var top: CGFloat?
    var leading: CGFloat?
    var bottom: CGFloat?
    var trailing: CGFloat?

    init() {
        self.top = nil
        self.leading = nil
        self.bottom = nil
        self.trailing = nil
    }

    init(_ insets: EdgeInsets) {
        self.top = insets.top
        self.leading = insets.leading
        self.bottom = insets.bottom
        self.trailing = insets.trailing
    }

    init(edges: Edge.Set, length: CGFloat?) {
        self.top = edges.contains(.top) ? length : nil
        self.leading = edges.contains(.leading) ? length : nil
        self.bottom = edges.contains(.bottom) ? length : nil
        self.trailing = edges.contains(.trailing) ? length : nil
    }

    mutating func merge(_ other: OptionalEdgeInsets, in edges: Edge.Set) {
        if edges.contains(.top) {
            top = other.top
        }
        if edges.contains(.leading) {
            leading = other.leading
        }
        if edges.contains(.bottom) {
            bottom = other.bottom
        }
        if edges.contains(.trailing) {
            trailing = other.trailing
        }
    }

    func edgeInsets(in edges: Edge.Set, fallback: OptionalEdgeInsets? = nil) -> EdgeInsets {
        EdgeInsets(
            top: edges.contains(.top) ? (top ?? fallback?.top ?? 0) : 0,
            leading: edges.contains(.leading) ? (leading ?? fallback?.leading ?? 0) : 0,
            bottom: edges.contains(.bottom) ? (bottom ?? fallback?.bottom ?? 0) : 0,
            trailing: edges.contains(.trailing) ? (trailing ?? fallback?.trailing ?? 0) : 0
        )
    }
}

struct ContentMarginProxy: Equatable {
    var automatic: OptionalEdgeInsets
    var scrollContent: OptionalEdgeInsets
    var scrollIndicators: OptionalEdgeInsets
    var toolbar: OptionalEdgeInsets

    init(
        automatic: OptionalEdgeInsets = OptionalEdgeInsets(),
        scrollContent: OptionalEdgeInsets = OptionalEdgeInsets(),
        scrollIndicators: OptionalEdgeInsets = OptionalEdgeInsets(),
        toolbar: OptionalEdgeInsets = OptionalEdgeInsets()
    ) {
        self.automatic = automatic
        self.scrollContent = scrollContent
        self.scrollIndicators = scrollIndicators
        self.toolbar = toolbar
    }

    func margins(
        for placement: ContentMarginPlacement,
        in edges: Edge.Set,
        allowAutomatic: Bool = true
    ) -> EdgeInsets {
        let automaticFallback = allowAutomatic ? automatic : nil
        switch placement.role {
        case .automatic:
            return allowAutomatic ? automatic.edgeInsets(in: edges) : EdgeInsets()
        case .scrollContent:
            return scrollContent.edgeInsets(in: edges, fallback: automaticFallback)
        case .scrollIndicators:
            return scrollIndicators.edgeInsets(in: edges, fallback: automaticFallback)
        case .toolbar:
            return toolbar.edgeInsets(in: edges, fallback: automaticFallback)
        }
    }
}

private struct AutomaticContentMarginKey: EnvironmentKey {
    static var defaultValue: OptionalEdgeInsets { OptionalEdgeInsets() }
}

private struct ScrollContentContentMarginKey: EnvironmentKey {
    static var defaultValue: OptionalEdgeInsets { OptionalEdgeInsets() }
}

private struct ScrollIndicatorContentMarginKey: EnvironmentKey {
    static var defaultValue: OptionalEdgeInsets { OptionalEdgeInsets() }
}

private struct ToolbarContentMarginKey: EnvironmentKey {
    static var defaultValue: OptionalEdgeInsets { OptionalEdgeInsets() }
}

extension EnvironmentValues {
    var automaticContentMargins: OptionalEdgeInsets {
        get { self[AutomaticContentMarginKey.self] }
        set { self[AutomaticContentMarginKey.self] = newValue }
    }

    var scrollContentContentMargins: OptionalEdgeInsets {
        get { self[ScrollContentContentMarginKey.self] }
        set { self[ScrollContentContentMarginKey.self] = newValue }
    }

    var scrollIndicatorContentMargins: OptionalEdgeInsets {
        get { self[ScrollIndicatorContentMarginKey.self] }
        set { self[ScrollIndicatorContentMarginKey.self] = newValue }
    }

    var toolbarContentMargins: OptionalEdgeInsets {
        get { self[ToolbarContentMarginKey.self] }
        set { self[ToolbarContentMarginKey.self] = newValue }
    }

    var contentMarginProxy: ContentMarginProxy {
        ContentMarginProxy(
            automatic: automaticContentMargins,
            scrollContent: scrollContentContentMargins,
            scrollIndicators: scrollIndicatorContentMargins,
            toolbar: toolbarContentMargins
        )
    }

    mutating func setContentMargins(
        _ insets: OptionalEdgeInsets,
        in edges: Edge.Set,
        for placement: ContentMarginPlacement
    ) {
        switch placement.role {
        case .automatic:
            automaticContentMargins.merge(insets, in: edges)
        case .scrollContent:
            scrollContentContentMargins.merge(insets, in: edges)
        case .scrollIndicators:
            scrollIndicatorContentMargins.merge(insets, in: edges)
        case .toolbar:
            toolbarContentMargins.merge(insets, in: edges)
        }
    }

    mutating func resetContentMargins(for placement: ContentMarginPlacement) {
        switch placement.role {
        case .automatic:
            automaticContentMargins = OptionalEdgeInsets()
        case .scrollContent:
            scrollContentContentMargins = OptionalEdgeInsets()
        case .scrollIndicators:
            scrollIndicatorContentMargins = OptionalEdgeInsets()
        case .toolbar:
            toolbarContentMargins = OptionalEdgeInsets()
        }
    }
}

struct ContentMarginModifier: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    var edges: Edge.Set
    var insets: OptionalEdgeInsets
    var placement: ContentMarginPlacement

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }

        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let modifierAttribute = modifier._attribute
        let environment: Attribute<EnvironmentValues> = graph.makeRule {
            let modifier = modifierAttribute.value
            var values = parentEnvironment.value.trackingCopy()
            values.setContentMargins(modifier.insets, in: modifier.edges, for: modifier.placement)
            return values
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }
}

extension View {
    public func contentMargins(
        _ edges: Edge.Set = .all,
        _ insets: EdgeInsets,
        for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        modifier(ContentMarginModifier(
            edges: edges,
            insets: OptionalEdgeInsets(insets),
            placement: placement
        ))
    }

    public func contentMargins(
        _ edges: Edge.Set = .all,
        _ length: CGFloat?,
        for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        modifier(ContentMarginModifier(
            edges: edges,
            insets: OptionalEdgeInsets(edges: edges, length: length),
            placement: placement
        ))
    }

    public func contentMargins(
        _ length: CGFloat,
        for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        contentMargins(.all, length, for: placement)
    }
}

private struct NearestScrollableAxesEnvironmentKey: EnvironmentKey {
    static var defaultValue: Axis.Set { [] }
}

private struct AllScrollableAxesEnvironmentKey: EnvironmentKey {
    static var defaultValue: Axis.Set { [] }
}

extension EnvironmentValues {
    var nearestScrollableAxes: Axis.Set {
        get { self[NearestScrollableAxesEnvironmentKey.self] }
        set { self[NearestScrollableAxesEnvironmentKey.self] = newValue }
    }

    var allScrollableAxes: Axis.Set {
        get { self[AllScrollableAxesEnvironmentKey.self] }
        set { self[AllScrollableAxesEnvironmentKey.self] = newValue }
    }
}

private extension CachedEnvironment.ID {
    static let nearestScrollableAxes = CachedEnvironment.ID(
        value: ObjectIdentifier(NearestScrollableAxesEnvironmentKey.self).hashValue
    )
    static let allScrollableAxes = CachedEnvironment.ID(
        value: ObjectIdentifier(AllScrollableAxesEnvironmentKey.self).hashValue
    )
    static let contentMarginProxy = CachedEnvironment.ID(
        value: ObjectIdentifier(AutomaticContentMarginKey.self).hashValue
            ^ ObjectIdentifier(ScrollContentContentMarginKey.self).hashValue
            ^ ObjectIdentifier(ScrollIndicatorContentMarginKey.self).hashValue
            ^ ObjectIdentifier(ToolbarContentMarginKey.self).hashValue
    )
}

extension _GraphInputs {
    var nearestScrollableAxes: Attribute<Axis.Set> {
        cachedEnvironment.value.attribute(id: .nearestScrollableAxes) {
            $0.nearestScrollableAxes
        }
    }

    var allScrollableAxes: Attribute<Axis.Set> {
        cachedEnvironment.value.attribute(id: .allScrollableAxes) {
            $0.allScrollableAxes
        }
    }

    var contentMarginProxy: Attribute<ContentMarginProxy> {
        cachedEnvironment.value.attribute(id: .contentMarginProxy) {
            $0.contentMarginProxy
        }
    }
}

extension _ViewInputs {
    var nearestScrollableAxes: Attribute<Axis.Set> {
        base.nearestScrollableAxes
    }

    var allScrollableAxes: Attribute<Axis.Set> {
        base.allScrollableAxes
    }

    var contentMarginProxy: Attribute<ContentMarginProxy> {
        base.contentMarginProxy
    }
}

/// Clears selected content-margin channels below a scroll boundary.
struct ResetContentMarginModifier: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    var placements: [ContentMarginPlacement]

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }

        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let modifierAttribute = modifier._attribute
        let environment: Attribute<EnvironmentValues> = graph.makeRule {
            let modifier = modifierAttribute.value
            var values = parentEnvironment.value.trackingCopy()
            for placement in modifier.placements {
                values.resetContentMargins(for: placement)
            }
            return values
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }
}

/// Carries scrollable axis settings through the modifier pipeline.
struct EnvironmentAxesModifier: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    var scrollableAxes: Axis.Set

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }
        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let modifierAttribute = modifier._attribute
        let environment: Attribute<EnvironmentValues> = graph.makeRule {
            let axes = modifierAttribute.value.scrollableAxes
            var values = parentEnvironment.value.trackingCopy()
            values.nearestScrollableAxes = axes
            values.allScrollableAxes.formUnion(axes)
            return values
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }
}

/// Resolves the inherited scroll target behavior for this scroll container.
private struct ResolvedScrollBehaviorModifier: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    var axes: Axis.Set

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }

        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let trackedEnvironment: Attribute<EnvironmentValues> = graph.makeStatefulRule(
            TrackedEnvironment(
                _environment: parentEnvironment,
                tracker: _PropertyListTracker()
            )
        )
        let behavior: Attribute<ResolvedScrollBehavior?> = graph.makeStatefulRule(
            MakeBehavior(
                _modifier: modifier._attribute,
                _environment: trackedEnvironment,
                oldDefaultBehavior: nil
            )
        )
        let behaviorTransform: Attribute<BehaviorTransform> = graph.makeRule(
            MakeBehaviorTransform(_behavior: behavior)
        )
        let transformedEnvironment: Attribute<EnvironmentValues> = graph.makeStatefulRule(
            TransformScrollStorageEnvironment(
                _environment: trackedEnvironment,
                _transform: behaviorTransform,
                previousProperties: nil
            )
        )
        let environment: Attribute<EnvironmentValues> = graph.makeRule(
            UpdateEnvironment(_environment: transformedEnvironment)
        )
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }

    private struct TrackedEnvironment: StatefulRule {
        typealias Value = EnvironmentValues

        var _environment: Attribute<EnvironmentValues>
        var tracker: _PropertyListTracker

        mutating func updateValue() {
            let values = _environment.value
            if _AGGraph.currentStatefulOutput(Value.self) != nil,
               !_AGGraphAnyInputsChanged(),
               !tracker.hasDifferentUsedValues(values._plist) {
                return
            }

            tracker.reset()
            _AGGraph.setStatefulOutput(EnvironmentValues(values._plist, tracker: tracker))
        }
    }

    private struct MakeBehavior: StatefulRule {
        typealias Value = ResolvedScrollBehavior?

        var _modifier: Attribute<ResolvedScrollBehaviorModifier>
        var _environment: Attribute<EnvironmentValues>
        var oldDefaultBehavior: ResolvedScrollBehavior?

        mutating func updateValue() {
            let behavior = defaultBehavior
            _AGGraph.setStatefulOutput(behavior)
            oldDefaultBehavior = behavior
        }

        private var defaultBehavior: ResolvedScrollBehavior? {
            let modifier = _modifier.value
            guard !modifier.axes.isEmpty else { return nil }
            return _environment.value.scrollEnvironmentStorage.properties.scrollBehavior
        }
    }

    private struct MakeBehaviorTransform: Rule {
        typealias Value = BehaviorTransform

        var _behavior: Attribute<ResolvedScrollBehavior?>

        func updateValue() -> BehaviorTransform {
            BehaviorTransform(behavior: _behavior.value)
        }
    }

    private struct UpdateEnvironment: Rule {
        typealias Value = EnvironmentValues

        var _environment: Attribute<EnvironmentValues>

        func updateValue() -> EnvironmentValues {
            let environment = _environment.value
            var values = environment.trackingCopy()
            values.scrollEnvironmentStorage = environment.scrollEnvironmentStorage
            return values
        }
    }

    private struct BehaviorTransform: ScrollEnvironmentTransform {
        var behavior: ResolvedScrollBehavior?

        func update(properties: inout ScrollEnvironmentProperties) {
            properties.scrollBehavior = behavior
        }
    }
}

/// Collects scroll phase state published by scroll containers.
struct ScrollPhasePreferenceKey: PreferenceKey {
    static var defaultValue: [ScrollPhaseState] { [] }

    static func reduce(value: inout [ScrollPhaseState], nextValue: () -> [ScrollPhaseState]) {
        value.append(contentsOf: nextValue())
    }
}

/// Wraps a container phase state in the preference payload shape.
private struct ScrollPhaseProvider: Rule {
    typealias Value = [ScrollPhaseState]

    var phaseState: Attribute<ScrollPhaseState>

    func updateValue() -> [ScrollPhaseState] {
        [phaseState.value]
    }
}

/// Installs a fresh scroll phase state for descendants of a scroll container.
struct ScrollPhaseStateConfigurationModifier: ViewModifier {
    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollPhaseStateConfigurationModifier._makeView called outside an active _AGGraph context.")
        }

        var contentInputs = inputs
        let phaseState = graph.makeInput(value: ScrollPhaseState())
        contentInputs.base.appendScrollPhaseState(OptionalAttribute(phaseState))
        var outputs = body(_Graph(), contentInputs)

        if inputs.preferences.keys.contains(ScrollPhasePreferenceKey.self) {
            let preferenceAttr: Attribute<[ScrollPhaseState]> = graph.makeRule(
                ScrollPhaseProvider(phaseState: phaseState)
            )
            outputs.preferences.setValue(preferenceAttr.identifier, for: ScrollPhasePreferenceKey.self)
        }
        return outputs
    }
}

private extension PreferenceKeys {
    mutating func remove<K: PreferenceKey>(_ keyType: K.Type) {
        let id = ObjectIdentifier(keyType)
        keys.removeAll { ObjectIdentifier($0) == id }
    }
}
