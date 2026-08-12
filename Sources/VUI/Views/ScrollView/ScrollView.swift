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

    var edgesToExpandDisplayListFrame: Edge.Set {
        guard !_SemanticFeature<Semantics_v6>.isEnabled else {
            return .all
        }
        var edges = Edge.Set()
        if axes.contains(.horizontal) {
            edges.formUnion(.horizontal)
        }
        if axes.contains(.vertical) {
            edges.formUnion(.vertical)
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

        let wantsResponderAttachment = inputs.preferences.keys.contains(
            ViewRespondersKey.self
        )
        let wantsDisplayAttachment = inputs.preferences.keys.contains(
            DisplayList.Key.self
        )
        let needsPlatformAttachment = wantsResponderAttachment
            || wantsDisplayAttachment

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
        let resolvedContainerSize = graph.makeInput(
            value: CGSize(width: -.infinity, height: -.infinity)
        )
        let graphRef = _AGGraphContext.current ?? _AGGraphContext(graph: graph)
        let environment = inputs.base.cachedEnvironment.value.environment
        let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
            environment.value.layoutDirection
        }
        let pixelLength: Attribute<CGFloat> = graph.makeRule {
            inputs.base.cachedEnvironment.value.environment.value.animationPixelLength
        }

        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let animatedPosition = cachedEnvironment.animatedPosition(for: inputs)
        let animatedSize = cachedEnvironment.animatedSize(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment

        let contentFrameSize: Attribute<ViewSize> = graph.makeRule(
            ScrollViewContentFrameSize(
                _size: animatedSize,
                _configuration: configuration
            )
        )
        let systemContentInsets: Attribute<EdgeInsets> = graph.subscriptNode(
            parent: layoutState,
            keyPath: \SystemScrollLayoutState.systemContentInsets
        )
        let modelContentFrame: Attribute<ViewFrame> = graph.makeRule(
            ScrollViewContentFrame(
                _size: contentFrameSize,
                _configuration: configuration,
                _systemContentInsets: systemContentInsets,
                _pixelLength: pixelLength,
                _contentComputer: OptionalAttribute()
            )
        )
        let frame = modelContentFrame.animated(inputs: inputs.base)
        let childContainerSize: Attribute<ViewSize> = graph.makeStatefulRule(
            ScrollViewChildContainerSize(
                _configuration: configuration,
                _parentContainerSize: inputs.containerSize,
                _resolvedSize: resolvedContainerSize,
                oldParentSize: ViewSize(
                    CGSize(width: -.infinity, height: -.infinity),
                    proposal: _ProposedSize(
                        width: -.infinity,
                        height: -.infinity
                    )
                ),
                oldSize: CGSize(width: -.infinity, height: -.infinity)
            )
        )
        let defaultAnchors: Attribute<ScrollAnchorStorage> = graph.makeStatefulRule(
            ScrollViewDefaultAnchors(
                _configuration: configuration,
                _anchors: inputs.base.scrollAnchors,
                oldAnchors: ScrollAnchorStorage(),
                oldAxes: .vertical
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
        let animatedAlignmentAdjustment = alignmentAdjustment.animated(inputs: inputs.base)
        let rtlAdjustment: Attribute<CGSize> = graph.makeRule(
            ScrollViewRTLAlignmentAdjustment(
                _configuration: configuration,
                _scrollAnchors: defaultAnchors,
                _contentFrame: frame,
                _size: inputs.size,
                _layoutDirection: layoutDirection
            )
        )
        let adjustedPosition: Attribute<CGPoint> = graph.makeRule(
            ScrollViewAdjustedPosition(
                _position: animatedPosition,
                _configuration: configuration,
                _rtlAdjustment: rtlAdjustment
            )
        )
        let adjustedSize: Attribute<ViewSize> = graph.makeRule(
            ScrollViewAdjustedSize(
                _size: animatedSize,
                _rtlAdjustment: rtlAdjustment
            )
        )
        let parentSafeAreaInsets = inputs.safeAreaInsets
        let safeArea: Attribute<EdgeInsets> = graph.makeRule {
            parentSafeAreaInsets.attribute?.value.value ?? EdgeInsets()
        }
        let adjustedSafeArea: Attribute<EdgeInsets> = graph.makeRule(
            ScrollViewAdjustedSafeArea(
                _safeArea: safeArea,
                _configuration: configuration,
                _alignmentAdjustment: alignmentAdjustment,
                _rtlAdjustment: rtlAdjustment
            )
        )
        let animatedAdjustedSafeArea = adjustedSafeArea.animated(inputs: inputs.base)
        let childSafeArea: Attribute<EdgeInsets> = graph.makeRule(
            ScrollViewChildSafeArea(
                _safeArea: animatedAdjustedSafeArea,
                _configuration: configuration
            )
        )
        let animatedChildSafeArea = childSafeArea.animated(inputs: inputs.base)
        let childPosition: Attribute<CGPoint> = graph.makeRule(
            ScrollViewChildPosition(
                _safeArea: animatedChildSafeArea,
                _layoutDirection: layoutDirection,
                _axes: scrollableAxes
            )
        )
        let childSafeAreaID = CoordinateSpace.ID()
        let isClipEnabled: Attribute<Bool> = graph.makeRule {
            let properties = environment.value.scrollEnvironmentStorage.properties
            return properties.isClippingEnabled
                || properties.clipDisabledBehavior == .automatic
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
        let scrollEnvironmentStorage: Attribute<ScrollEnvironmentStorage> = graph.makeRule {
            environment.value.scrollEnvironmentStorage
        }
        let adjustedScrollBehavior: Attribute<ResolvedScrollBehavior?> = graph.makeRule(
            ScrollViewAdjustedBehavior(
                _axes: scrollableAxes,
                _scrollStorage: scrollEnvironmentStorage
            )
        )
        let scrollableAttr: Attribute<any Scrollable> = graph.makeRule(
            ScrollableProvider(
                _state: layoutState,
                _adjustedState: adjustedState,
                _scrollBehavior: adjustedScrollBehavior,
                _children: OptionalAttribute(),
                _scrollView: OptionalAttribute()
            )
        )

        contentInputs.scrollable = OptionalAttribute(scrollableAttr)
        contentInputs.transform = graph.makeRule(
            ScrollViewChildTransform(
                _configuration: configuration,
                _contentFrame: frame,
                _position: adjustedPosition,
                _size: adjustedSize,
                _transform: inputs.transform,
                _state: layoutState,
                _safeArea: animatedAdjustedSafeArea,
                _childSafeArea: animatedChildSafeArea,
                _childPosition: childPosition,
                _alignmentAdjustment: animatedAlignmentAdjustment,
                _isClipEnabled: isClipEnabled,
                _layoutDirection: layoutDirection,
                childSafeAreaID: childSafeAreaID
            )
        )
        contentInputs.safeAreaInsets = OptionalAttribute(graph.makeRule(
            ScrollViewChildSafeAreaInsets(
                _safeArea: animatedChildSafeArea,
                _layoutDirection: layoutDirection,
                childSafeAreaID: childSafeAreaID
            )
        ))
        contentInputs.size = graph.subscriptNode(
            parent: frame,
            keyPath: \ViewFrame.size
        )
        contentInputs.position = childPosition
        contentInputs.containerPosition = graph.makeInput(value: CGPoint.zero)
        contentInputs.containerSize = OptionalAttribute(childContainerSize)
        contentInputs.requestsLayoutComputer = true
        contentInputs.preferences.keys.add(ScrollablePreferenceKey.self)
        contentInputs.preferences.keys.add(UpdateScrollStateRequestKey.self)
        contentInputs.preferences.keys.add(ScrollableDescendantsAxesKey.self)

        let contentOutputs = Content._makeView(view: view[\.content], inputs: contentInputs)
        if let contentComputer = contentOutputs._layoutComputer.attribute {
            graph.mutateRule(
                modelContentFrame.identifier,
                as: ScrollViewContentFrame.self,
                invalidating: true
            ) {
                $0._contentComputer = OptionalAttribute(contentComputer)
            }
        }
        var outputs = contentOutputs
        if inputs.requestsLayoutComputer {
            let layoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
                ScrollViewLayoutComputer(
                    _configuration: configuration,
                    _systemContentInsets: systemContentInsets,
                    _contentComputer: contentOutputs._layoutComputer
                )
            )
            outputs._layoutComputer = OptionalAttribute(layoutComputer)
        }
        if let childScrollables = contentOutputs.preferences.value(
            for: ScrollablePreferenceKey.self
        ) {
            graph.mutateRule(
                scrollableAttr.identifier,
                as: ScrollableProvider.self
            ) { provider in
                provider._children = OptionalAttribute(
                    Attribute<[any Scrollable]>(childScrollables)
                )
            }
        }
        let hostingScrollView: Attribute<HostingScrollView> = graph.makeStatefulRule(
            MakeHostingScrollView(
                _layoutState: layoutState,
                _phaseState: phaseState,
                _containerSize: resolvedContainerSize,
                graphRef: graphRef
            )
        )
        graph.mutateRule(
            scrollableAttr.identifier,
            as: ScrollableProvider.self
        ) { provider in
            provider._scrollView = OptionalAttribute(hostingScrollView)
        }
        let platformContainer: Attribute<HostingScrollView.PlatformContainer>?
        if needsPlatformAttachment {
            platformContainer = graph.makeStatefulRule(
                UpdatedScrollViewContainer(
                    _scrollView: hostingScrollView
                )
            )
        } else {
            platformContainer = nil
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
        let displayListFrame: Attribute<CGRect>?
        if needsPlatformAttachment {
            displayListFrame = graph.makeRule(
                ScrollViewDisplayListFrame(
                    _configuration: configuration,
                    _position: inputs.position,
                    _containerPosition: inputs.containerPosition,
                    _size: inputs.size,
                    _safeAreaInsets: adjustedSafeArea,
                    _alignmentAdjustment: alignmentAdjustment,
                    _rtlAdjustment: rtlAdjustment,
                    _layoutDirection: layoutDirection,
                    _pixelLength: pixelLength
                )
            )
        } else {
            displayListFrame = nil
        }
        let containerSize: Attribute<CGSize> = graph.makeRule {
            inputs.size.value.value
        }
        let descendantScrollViewsAxes: Attribute<Axis.Set?>? = contentOutputs.preferences
            .value(for: ScrollableDescendantsAxesKey.self)
            .map { Attribute<Axis.Set?>($0) }
        let updatedHostingScrollView: Attribute<HostingScrollView> = graph.makeStatefulRule(
            UpdatedHostingScrollView(
                _descendantScrollViewsAxes: OptionalAttribute(descendantScrollViewsAxes),
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
        if let platformContainer {
            graph.mutateStatefulRule(
                updatedHostingScrollView.identifier,
                as: UpdatedHostingScrollView.self
            ) { updated in
                updated._container = OptionalAttribute(platformContainer)
            }
        }
        // Motion is sampled from the graph clock, while the host object remains
        // stable across frames and owns the in-flight deceleration state.
        let motionHostingScrollView: Attribute<HostingScrollView> = graph.makeStatefulRule(
            HostingScrollViewMotionUpdate(
                _scrollView: updatedHostingScrollView,
                _time: inputs.base.time
            )
        )
        let geometry: Attribute<ScrollGeometry> = graph.makeRule(
            ScrollGeometryProvider(
                layoutState: adjustedState,
                frame: frame,
                size: inputs.size,
                layoutDirection: layoutDirection
            )
        )

        if inputs.preferences.keys.contains(ScrollablePreferenceKey.self) {
            let preferenceAttr: Attribute<[any Scrollable]> = graph.makeRule(
                ScrollablePreferenceProvider(scrollable: scrollableAttr)
            )
            outputs.preferences.setValue(preferenceAttr.identifier, for: ScrollablePreferenceKey.self)
        }

        outputs.preferences.makePreferenceWriter(
            inputs: inputs.preferences,
            key: ScrollableDescendantsAxesKey.self,
            value: scrollableAxes.toOptional
        )

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
        enqueueRequests.setFlags(.transactional, mask: .transactional)

        if wantsResponderAttachment {
            let childResponders = outputs.preferences.reducedValue(
                for: ViewRespondersKey.self,
                in: graph
            ) ?? graph.makeInput(value: ViewRespondersKey.defaultValue)
            let responders: Attribute<[ViewResponder]> = graph.makeStatefulRule(
                ScrollViewResponder(
                    _scrollView: updatedHostingScrollView,
                    _position: inputs.position,
                    _size: inputs.size,
                    _transform: inputs.transform,
                    _children: childResponders,
                    _responder: nil,
                    layoutResponder: DefaultLayoutViewResponder(inputs: inputs)
                )
            )
            outputs.preferences.setValue(
                responders.identifier,
                for: ViewRespondersKey.self
            )
        }

        if wantsDisplayAttachment, let displayListFrame {
            let childDisplayList = outputs.preferences.reducedValue(
                for: DisplayList.Key.self,
                in: graph
            )
            var identityInputs = inputs
            let displayList: Attribute<DisplayList> = graph.makeRule(
                ScrollViewDisplayList(
                    identity: identityInputs.pushIdentity(),
                    _scrollView: motionHostingScrollView,
                    _frame: displayListFrame,
                    _contentList: OptionalAttribute(childDisplayList)
                )
            )
            outputs.preferences.setValue(
                displayList.identifier,
                for: DisplayList.Key.self
            )
        }

        return outputs
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Content._makeViewList(view: view[\.content], inputs: inputs)
    }
}

private struct ScrollViewAdjustedPosition: Rule {
    typealias Value = CGPoint

    var _position: Attribute<CGPoint>
    var _configuration: Attribute<ScrollViewConfiguration>
    var _rtlAdjustment: Attribute<CGSize>

    var value: CGPoint {
        let position = _position.value
        let insetOffset = _configuration.value.contentInsets.originOffset
        let rtlAdjustment = _rtlAdjustment.value
        return CGPoint(
            x: position.x + insetOffset.width + rtlAdjustment.width,
            y: position.y + insetOffset.height + rtlAdjustment.height
        )
    }
}

private struct ScrollViewAdjustedSize: Rule {
    typealias Value = ViewSize

    var _size: Attribute<ViewSize>
    var _rtlAdjustment: Attribute<CGSize>

    var value: ViewSize {
        var size = _size.value
        let adjustment = _rtlAdjustment.value
        size.value.width -= adjustment.width
        size.value.height -= adjustment.height
        return size
    }
}

private struct ScrollViewChildSafeArea: Rule {
    typealias Value = EdgeInsets

    var _safeArea: Attribute<EdgeInsets>
    var _configuration: Attribute<ScrollViewConfiguration>

    var value: EdgeInsets {
        let edges = _SemanticFeature<Semantics_v6>.isEnabled
            ? _configuration.value.nonScrollableEdges
            : Edge.Set(rawValue: 0)
        return _safeArea.value.in(edges)
    }
}

private struct ScrollViewChildPosition: Rule {
    typealias Value = CGPoint

    var _safeArea: Attribute<EdgeInsets>
    var _layoutDirection: Attribute<LayoutDirection>
    var _axes: Attribute<Axis.Set>

    var value: CGPoint {
        guard _SemanticFeature<Semantics_v6>.isEnabled else {
            return .zero
        }
        let offset = _safeArea.value
            .xFlipIfRightToLeft { _layoutDirection.value }
            .in(originOffsetEdges)
            .originOffset
        return CGPoint(x: offset.width, y: offset.height)
    }

    private var originOffsetEdges: Edge.Set {
        if _layoutDirection.value == .rightToLeft && _axes.value == .vertical {
            return .vertical
        }
        return .all
    }
}

private struct ScrollViewChildSafeAreaInsets: Rule {
    typealias Value = SafeAreaInsets

    var _safeArea: Attribute<EdgeInsets>
    var _layoutDirection: Attribute<LayoutDirection>
    var childSafeAreaID: CoordinateSpace.ID

    var value: SafeAreaInsets {
        let elements: [SafeAreaInsets.Element] = _SemanticFeature<Semantics_v6>.isEnabled
            ? [
                SafeAreaInsets.Element(
                    regions: .container,
                    insets: _safeArea.value.xFlipIfRightToLeft { _layoutDirection.value },
                    cornerInsets: nil
                ),
            ]
            : []
        return SafeAreaInsets(
            space: childSafeAreaID,
            elements: elements
        )
    }
}

private struct ScrollViewChildTransform: Rule {
    typealias Value = ViewTransform

    var _configuration: Attribute<ScrollViewConfiguration>
    var _contentFrame: Attribute<ViewFrame>
    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _transform: Attribute<ViewTransform>
    var _state: Attribute<SystemScrollLayoutState>
    var _safeArea: Attribute<EdgeInsets>
    var _childSafeArea: Attribute<EdgeInsets>
    var _childPosition: Attribute<CGPoint>
    var _alignmentAdjustment: Attribute<CGSize>
    var _isClipEnabled: Attribute<Bool>
    var _layoutDirection: Attribute<LayoutDirection>
    var childSafeAreaID: CoordinateSpace.ID

    var value: ViewTransform {
        var transform = _transform.value
        var containerSize = _size.value.value
        if !(containerSize.width > 0) {
            containerSize.width = 0
        }
        if !(containerSize.height > 0) {
            containerSize.height = 0
        }

        let configuration = _configuration.value
        let contentFrame = _contentFrame.value
        let state = _state.value
        let contentInsets = state.systemContentInsets
            .adding(configuration.contentInsets)
            .adding(_safeArea.value)
        let childSafeArea = _childSafeArea.value
        let filteredChildSafeArea = childSafeArea
            .in(configuration.nonScrollableEdges)
            .xFlipIfRightToLeft { _layoutDirection.value }
        let position = _position.value
        let alignmentAdjustment = _alignmentAdjustment.value
        let childSafeAreaOrigin = filteredChildSafeArea.originOffset
        transform.resetPosition(CGPoint(
            x: position.x
                + alignmentAdjustment.width
                - childSafeAreaOrigin.width
                + contentFrame.origin.x,
            y: position.y
                + alignmentAdjustment.height
                - childSafeAreaOrigin.height
                + contentFrame.origin.y
        ))

        let flippedChildSafeArea = childSafeArea
            .xFlipIfRightToLeft { _layoutDirection.value }
        let safeAreaSize = containerSize.outset(by: flippedChildSafeArea)
        let childPosition = _childPosition.value
        if _SemanticFeature<Semantics_v6>.isEnabled {
            transform.appendSizedSpace(id: childSafeAreaID, size: safeAreaSize)
            transform.appendPosition(childPosition)
        }

        var buffer = ViewTransform.UnsafeBuffer()

        if let preparedRect = state.contentRectToPrepare {
            buffer.appendScrollGeometry(
                ScrollGeometry.rootViewTransform(
                    contentOffset: preparedRect.origin,
                    containerSize: preparedRect.size
                ),
                isClipped: true
            )
        }

        let linkedOnOrAfterV6 = isLinkedOnOrAfter(.v6)
        let contentIsClipped: Bool
        if linkedOnOrAfterV6 && _isClipEnabled.value {
            contentIsClipped = state.contentRectToPrepare == nil
        } else {
            contentIsClipped = !linkedOnOrAfterV6
        }
        buffer.appendScrollGeometry(
            ScrollGeometry.viewTransform(
                contentInsets: contentInsets,
                contentSize: contentFrame.size.value,
                containerSize: containerSize
            ),
            isClipped: contentIsClipped
        )
        buffer.appendSizedSpace(
            id: ScrollCoordinateSpace.all.id,
            size: containerSize,
            transform: &transform
        )
        if configuration.axes.contains(.horizontal) {
            buffer.appendSizedSpace(
                id: ScrollCoordinateSpace.horizontal.id,
                size: containerSize,
                transform: &transform
            )
        }
        if configuration.axes.contains(.vertical) {
            buffer.appendSizedSpace(
                id: ScrollCoordinateSpace.vertical.id,
                size: containerSize,
                transform: &transform
            )
        }
        buffer.appendTranslation(CGSize(
            width: state.contentOffset.x + state.systemTranslation.width,
            height: state.contentOffset.y + state.systemTranslation.height
        ))
        buffer.appendSizedSpace(
            id: ScrollCoordinateSpace.content.id,
            size: contentFrame.size.value,
            transform: &transform
        )
        if _SemanticFeature<Semantics_v6>.isEnabled {
            buffer.appendTranslation(CGSize(
                width: childPosition.x,
                height: childPosition.y
            ))
            buffer.appendSizedSpace(
                id: ScrollCoordinateSpace.safeArea.id,
                size: safeAreaSize,
                transform: &transform
            )
            buffer.appendTranslation(CGSize(
                width: -childPosition.x,
                height: -childPosition.y
            ))
        }
        transform.append(movingContentsOf: &buffer)
        return transform
    }
}

/// Scrollable facade that commits requests back to the system layout state.
private final class ScrollViewScrollable: Scrollable {
    var _state: WeakAttribute<SystemScrollLayoutState>
    var _adjustedState: WeakAttribute<SystemScrollLayoutState>
    var _scrollBehavior: WeakAttribute<ResolvedScrollBehavior?>
    var _children: WeakAttribute<[any Scrollable]>
    var _scrollView: WeakAttribute<HostingScrollView>
    var _lastUpdateSeed: MutableBox<UInt32>

    init(
        _state: WeakAttribute<SystemScrollLayoutState>,
        _adjustedState: WeakAttribute<SystemScrollLayoutState>,
        _scrollBehavior: WeakAttribute<ResolvedScrollBehavior?>,
        _children: WeakAttribute<[any Scrollable]>,
        _scrollView: WeakAttribute<HostingScrollView>,
        _lastUpdateSeed: MutableBox<UInt32>
    ) {
        self._state = _state
        self._adjustedState = _adjustedState
        self._scrollBehavior = _scrollBehavior
        self._children = _children
        self._scrollView = _scrollView
        self._lastUpdateSeed = _lastUpdateSeed
    }

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        guard _AGGraph.current != nil else {
            fatalError("ScrollViewScrollable.scroll(to:) requires an active _AGGraph context.")
        }
        for child in _children.value ?? [] {
            if child.scroll(to: id) {
                return true
            }
        }
        return false
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewScrollable.setContentTarget(_:) requires an active _AGGraph context.")
        }
        guard var state = _adjustedState.value,
              _state.isValid(in: graph) else {
            return false
        }

        var resolvedTarget = target
        if let behavior = _scrollBehavior.value.flatMap({ $0 }) {
            let previousTarget = resolvedTarget
            resolvedTarget = { geometry, layoutDirection in
                guard var target = previousTarget(geometry, layoutDirection) else {
                    return nil
                }
                if layoutDirection == .rightToLeft {
                    target.rect.origin.x = geometry.contentSize.width - target.rect.maxX
                }
                let originalTarget = target
                let context = ScrollTargetBehaviorContext(
                    originalTarget: originalTarget,
                    velocity: .zero,
                    geometry: geometry,
                    axes: [],
                    decelerationRate: .standard
                )
                behavior.updateTarget(&target, context: context)
                if layoutDirection == .rightToLeft {
                    target.rect.origin.x = geometry.contentSize.width - target.rect.maxX
                }
                return target
            }
        }

        let translation = state.systemTranslation
        if translation != .zero {
            let previousTarget = resolvedTarget
            resolvedTarget = { geometry, layoutDirection in
                guard var target = previousTarget(geometry, layoutDirection) else {
                    return nil
                }
                target.rect.origin.x -= translation.width
                target.rect.origin.y -= translation.height
                return target
            }
        }

        let transaction = Transaction.current
        let configuration = ScrollTargetConfiguration(transaction: transaction)
        _lastUpdateSeed.value &+= 1
        state.updateContentOffset(
            mode: .target(resolvedTarget, config: configuration),
            updateSeed: _lastUpdateSeed.value
        )
        ScrollViewCommitMutation.commit(
            layoutState: (state, _state),
            isPreferred: true,
            transaction: transaction
        )
        return true
    }

    var allowsContentOffsetAdjustments: Bool {
        guard _AGGraph.current != nil else {
            fatalError("ScrollViewScrollable.allowsContentOffsetAdjustments requires an active _AGGraph context.")
        }
        guard let state = _AGGraph.withoutTracking({ _state.value }) else {
            return false
        }
        switch state.contentOffsetMode {
        case .target:
            return false
        case .adjustment, .system:
            return true
        }
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewScrollable.adjustContentOffset(by:reason:) requires an active _AGGraph context.")
        }
        guard var state = _AGGraph.withoutTracking({ _adjustedState.value }),
              _state.isValid(in: graph) else {
            return false
        }

        let updateSeed = _lastUpdateSeed.value
        if offset != .zero {
            state.contentOffset.x += offset.width
            state.contentOffset.y += offset.height
            state.updateContentOffset(
                mode: .adjustment(reason: reason),
                updateSeed: updateSeed
            )
            ScrollViewCommitMutation.commit(
                layoutState: (state, _state),
                isPreferred: true
            )
        }
        _lastUpdateSeed.value &+= 1
        return true
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        guard _AGGraph.current != nil else {
            fatalError("ScrollViewScrollable.mapFirstChild(ofType:body:) requires an active _AGGraph context.")
        }
        if let scrollable = self as? A {
            return body(scrollable)
        }
        for child in _children.value ?? [] {
            if let result = child.mapFirstChild(ofType: type, body: body) {
                return result
            }
        }
        return nil
    }
}

/// Exposes the container's scrollable host through the preference graph.
private struct ScrollableProvider: Rule {
    typealias Value = any Scrollable

    var _state: Attribute<SystemScrollLayoutState>
    var _adjustedState: Attribute<SystemScrollLayoutState>
    var _scrollBehavior: Attribute<ResolvedScrollBehavior?>
    var _children: OptionalAttribute<[any Scrollable]>
    var _scrollView: OptionalAttribute<HostingScrollView>

    var value: any Scrollable {
        ScrollViewScrollable(
            _state: _state.asWeak(),
            _adjustedState: _adjustedState.asWeak(),
            _scrollBehavior: _scrollBehavior.asWeak(),
            _children: WeakAttribute(_children.attribute),
            _scrollView: WeakAttribute(_scrollView.attribute),
            _lastUpdateSeed: MutableBox(0)
        )
    }
}

private struct ScrollViewAdjustedBehavior: Rule {
    typealias Value = ResolvedScrollBehavior?

    var _axes: Attribute<Axis.Set>
    var _scrollStorage: Attribute<ScrollEnvironmentStorage>

    var value: ResolvedScrollBehavior? {
        guard !_axes.value.isEmpty else { return nil }
        return _scrollStorage.value.properties.scrollBehavior
    }
}

/// Wraps one scrollable host in the preference payload shape.
private struct ScrollablePreferenceProvider: Rule {
    typealias Value = [any Scrollable]

    var scrollable: Attribute<any Scrollable>

    var value: [any Scrollable] {
        [scrollable.value]
    }
}

private struct ScrollViewContentFrameSize: Rule {
    typealias Value = ViewSize

    var _size: Attribute<ViewSize>
    var _configuration: Attribute<ScrollViewConfiguration>

    var value: ViewSize {
        var size = _size.value
        let insets = _configuration.value.contentInsets
        size.value.width -= insets.leading + insets.trailing
        size.value.height -= insets.top + insets.bottom
        return size
    }
}

private struct ScrollViewContentFrame: Rule {
    typealias Value = ViewFrame

    var _size: Attribute<ViewSize>
    var _configuration: Attribute<ScrollViewConfiguration>
    var _systemContentInsets: Attribute<EdgeInsets>
    var _pixelLength: Attribute<CGFloat>
    var _contentComputer: OptionalAttribute<LayoutComputer>

    var value: ViewFrame {
        let containingSize = _size.value.value.inset(
            by: _systemContentInsets.value
        )
        var frame = ScrollViewUtilities.contentFrame(
            in: containingSize,
            contentComputer: _contentComputer.attribute?.value,
            axes: _configuration.value.axes
        )
        frame.round(toMultipleOf: _pixelLength.value)
        return frame
    }
}

private struct ScrollViewChildContainerSize: StatefulRule {
    typealias Value = ViewSize

    var _configuration: Attribute<ScrollViewConfiguration>
    var _parentContainerSize: OptionalAttribute<ViewSize>
    var _resolvedSize: Attribute<CGSize>
    var oldParentSize: ViewSize
    var oldSize: CGSize

    mutating func updateValue() {
        var inheritedSize = _parentContainerSize.attribute?.value ?? .zero
        inheritedSize.value = inheritedSize.value.inset(
            by: _configuration.value.contentInsets
        )

        let resolvedSize = _resolvedSize.value
        let invalidSize = CGSize(width: -.infinity, height: -.infinity)
        var output = inheritedSize
        if resolvedSize != invalidSize && resolvedSize != .zero {
            output.value = resolvedSize
        }

        if _AGGraph.currentStatefulOutput(ViewSize.self) == nil
            || oldParentSize != inheritedSize
            || oldSize != resolvedSize {
            _AGGraph.setStatefulOutput(output)
        }
        oldParentSize = inheritedSize
        oldSize = resolvedSize
    }
}

/// Host-owned layout computer for the scroll container's child content.
private struct ScrollViewLayoutComputer: StatefulRule {
    typealias Value = LayoutComputer

    var _configuration: Attribute<ScrollViewConfiguration>
    var _systemContentInsets: Attribute<EdgeInsets>
    var _contentComputer: OptionalAttribute<LayoutComputer>

    mutating func updateValue() {
        let configuration = _configuration.value
        let contentInsets = configuration.contentInsets.adding(
            _systemContentInsets.value
        )
        let contentComputer = _contentComputer.attribute?.value
        updateIfNotEqual(
            to: Engine(
                axes: configuration.axes,
                contentInsets: contentInsets,
                contentComputer: contentComputer,
                cache: ViewSizeCache()
            )
        )
    }

    struct Engine: LayoutEngine, Equatable {
        var axes: Axis.Set
        var contentInsets: EdgeInsets
        var contentComputer: LayoutComputer?
        var cache: ViewSizeCache

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.axes == rhs.axes
                && lhs.contentInsets == rhs.contentInsets
                && lhs.contentComputer == rhs.contentComputer
        }

        mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            cache.get(proposal) {
                let insetProposal = _ProposedSize(
                    width: proposal.width.map {
                        max($0 - contentInsets.leading - contentInsets.trailing, 0)
                    },
                    height: proposal.height.map {
                        max($0 - contentInsets.top - contentInsets.bottom, 0)
                    }
                )
                let contentSize = ScrollViewUtilities.sizeThatFits(
                    in: ProposedViewSize(insetProposal),
                    contentComputer: contentComputer,
                    axes: axes
                ) ?? insetProposal.fixingUnspecifiedDimensions()
                return CGSize(
                    width: contentSize.width
                        + contentInsets.leading
                        + contentInsets.trailing,
                    height: contentSize.height
                        + contentInsets.top
                        + contentInsets.bottom
                )
            }
        }
    }
}

/// Derives ScrollGeometry from layout state, view frame, and layout direction.
private struct ScrollGeometryProvider: Rule {
    typealias Value = ScrollGeometry

    var layoutState: Attribute<SystemScrollLayoutState>
    var frame: Attribute<ViewFrame>
    var size: Attribute<ViewSize>
    var layoutDirection: Attribute<LayoutDirection>

    var value: ScrollGeometry {
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

    var value: ViewTransform {
        var value = transform.value
        value.appendPosition(position.value)
        return value
    }
}

private struct RefreshScopeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.refresh, nil)
    }
}

private struct InertPaddingLayoutRequired: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        !isLinkedOnOrAfter(.v5)
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

struct OptionalEdgeInsets: Hashable {
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

    subscript(edge: Edge) -> CGFloat? {
        get {
            switch edge {
            case .top: top
            case .leading: leading
            case .bottom: bottom
            case .trailing: trailing
            }
        }
        set {
            switch edge {
            case .top: top = newValue
            case .leading: leading = newValue
            case .bottom: bottom = newValue
            case .trailing: trailing = newValue
            }
        }
    }

    static var none: OptionalEdgeInsets { OptionalEdgeInsets() }

    func `in`(edges: Edge.Set) -> EdgeInsets {
        EdgeInsets(
            top: edges.contains(.top) ? (top ?? 0) : 0,
            leading: edges.contains(.leading) ? (leading ?? 0) : 0,
            bottom: edges.contains(.bottom) ? (bottom ?? 0) : 0,
            trailing: edges.contains(.trailing) ? (trailing ?? 0) : 0
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
        var insets: OptionalEdgeInsets
        switch placement.role {
        case .automatic:
            insets = automatic
        case .scrollContent:
            insets = scrollContent
        case .scrollIndicators:
            insets = scrollIndicators
        case .toolbar:
            insets = toolbar
        }
        if insets == .none, allowAutomatic {
            insets = automatic
        }
        return insets.in(edges: edges)
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

private struct ToolbarMarginKey: EnvironmentKey {
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
        get { self[ToolbarMarginKey.self] }
        set { self[ToolbarMarginKey.self] = newValue }
    }

    var contentMarginProxy: ContentMarginProxy {
        ContentMarginProxy(
            automatic: automaticContentMargins,
            scrollContent: scrollContentContentMargins,
            scrollIndicators: scrollIndicatorContentMargins,
            toolbar: toolbarContentMargins
        )
    }

}

struct ContentMarginModifier: ViewModifier, EnvironmentModifier {
    typealias Body = Never

    var edges: Edge.Set
    var insets: OptionalEdgeInsets
    var placement: ContentMarginPlacement

    static func makeEnvironment(
        modifier: Attribute<Self>,
        environment: inout EnvironmentValues
    ) {
        let modifier = modifier.value
        guard !modifier.edges.isEmpty else { return }

        switch modifier.placement.role {
        case .automatic:
            var insets = environment.automaticContentMargins
            for edge in Edge.allCases where modifier.edges.contains(Edge.Set(edge)) {
                insets[edge] = modifier.insets[edge]
            }
            environment.automaticContentMargins = insets
        case .scrollContent:
            var insets = environment.scrollContentContentMargins
            for edge in Edge.allCases where modifier.edges.contains(Edge.Set(edge)) {
                insets[edge] = modifier.insets[edge]
            }
            environment.scrollContentContentMargins = insets
        case .scrollIndicators:
            var insets = environment.scrollIndicatorContentMargins
            for edge in Edge.allCases where modifier.edges.contains(Edge.Set(edge)) {
                insets[edge] = modifier.insets[edge]
            }
            environment.scrollIndicatorContentMargins = insets
        case .toolbar:
            var insets = environment.toolbarContentMargins
            for edge in Edge.allCases where modifier.edges.contains(Edge.Set(edge)) {
                insets[edge] = modifier.insets[edge]
            }
            environment.toolbarContentMargins = insets
        }
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
    static let nearestScrollableAxes = CachedEnvironment.ID(base: UniqueID())
    static let allScrollableAxes = CachedEnvironment.ID(base: UniqueID())
    static let contentMarginProxy = CachedEnvironment.ID(base: UniqueID())
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

struct ResetContentMarginModifier: ViewModifier, EnvironmentModifier {
    typealias Body = Never

    var placements: [ContentMarginPlacement.Role]

    static func makeEnvironment(
        modifier: Attribute<Self>,
        environment: inout EnvironmentValues
    ) {
        for placement in modifier.value.placements {
            let insets = OptionalEdgeInsets()
            switch placement {
            case .automatic:
                environment.automaticContentMargins = insets
            case .scrollContent:
                environment.scrollContentContentMargins = insets
            case .scrollIndicators:
                environment.scrollIndicatorContentMargins = insets
            case .toolbar:
                environment.toolbarContentMargins = insets
            }
        }
    }
}

/// Carries scrollable axis settings through the modifier pipeline.
struct EnvironmentAxesModifier: ViewModifier, EnvironmentModifier {
    typealias Body = Never

    var scrollableAxes: Axis.Set

    static func makeEnvironment(
        modifier: Attribute<Self>,
        environment: inout EnvironmentValues
    ) {
        let axes = modifier.scrollableAxes.value
        environment.nearestScrollableAxes = axes
        environment.allScrollableAxes.formUnion(axes)
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
            let defaultBehavior = defaultBehavior
            var behavior = defaultBehavior
            if behavior != nil {
                behavior?.axes = _modifier.value.axes
                behavior?._environment = _environment.asWeak()
            }
            _AGGraph.setStatefulOutput(behavior)
            oldDefaultBehavior = defaultBehavior
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

        var value: BehaviorTransform {
            BehaviorTransform(behavior: _behavior.value)
        }
    }

    private struct UpdateEnvironment: Rule, AsyncAttribute {
        typealias Value = EnvironmentValues

        var _environment: Attribute<EnvironmentValues>

        var value: EnvironmentValues {
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

    var value: [ScrollPhaseState] {
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
