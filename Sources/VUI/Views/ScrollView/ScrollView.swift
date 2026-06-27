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
        guard let graph = AttributeGraph.current else {
            fatalError("SystemScrollView._makeView called outside an active AttributeGraph context.")
        }

        var contentInputs = inputs
        let phaseState = contentInputs.base.scrollPhaseState.attribute ?? {
            let state = graph.makeInput(value: ScrollPhaseState())
            contentInputs.base.appendScrollPhaseState(OptionalAttribute(state))
            return state
        }()

        let scrollable = ScrollViewScrollable()
        let scrollableAttr: Attribute<any Scrollable> = graph.makeRule(
            ScrollableProvider(scrollable: scrollable)
        )
        contentInputs.scrollable = OptionalAttribute(scrollableAttr)
        contentInputs.preferences.keys.insert(ScrollablePreferenceKey.self)
        contentInputs.preferences.keys.insert(UpdateScrollStateRequestKey.self)

        let contentOutputs = Content._makeView(view: view[\.content], inputs: contentInputs)
        var outputs = contentOutputs

        if inputs.preferences.keys.contains(ScrollablePreferenceKey.self) {
            let preferenceAttr: Attribute<[any Scrollable]> = graph.makeRule(
                ScrollablePreferenceProvider(scrollable: scrollableAttr)
            )
            outputs.preferences.setValue(preferenceAttr.identifier, for: ScrollablePreferenceKey.self)
        }

        if inputs.preferences.keys.contains(ScrollGeometryPreferenceKey.self) {
            let configuration = view[\.configuration]._attribute
            let layoutState: Attribute<SystemScrollLayoutState> = graph.makeRule(
                SystemScrollLayoutStateProvider(configuration: configuration)
            )
            let frame: Attribute<ViewFrame> = graph.makeRule(
                ViewFrameProvider(position: inputs.position, size: inputs.size)
            )
            let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
                inputs.base.cachedEnvironment.value.environment.value.layoutDirection
            }
            let geometry: Attribute<ScrollGeometry> = graph.makeRule(
                ScrollGeometryProvider(
                    layoutState: layoutState,
                    frame: frame,
                    size: inputs.size,
                    layoutDirection: layoutDirection
                )
            )
            let scrollableAxes: Attribute<Axis.Set> = graph.makeRule {
                configuration.value.axes
            }
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

        return outputs
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Content._makeViewList(view: view[\.content], inputs: inputs)
    }
}

/// Placeholder scrollable host used until platform-backed scrolling is mounted.
private final class ScrollViewScrollable: Scrollable {
    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        false
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        false
    }

    var allowsContentOffsetAdjustments: Bool {
        false
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        false
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        nil
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

/// Current platform scroll offset and insets used to derive ScrollGeometry.
private struct SystemScrollLayoutState: Equatable {
    var contentOffset: CGPoint
    var contentInsets: EdgeInsets

    init(contentOffset: CGPoint = .zero, contentInsets: EdgeInsets = EdgeInsets()) {
        self.contentOffset = contentOffset
        self.contentInsets = contentInsets
    }
}

/// Builds the platform scroll layout state from container configuration.
private struct SystemScrollLayoutStateProvider: Rule {
    typealias Value = SystemScrollLayoutState

    var configuration: Attribute<ScrollViewConfiguration>

    func updateValue() -> SystemScrollLayoutState {
        SystemScrollLayoutState(
            contentOffset: .zero,
            contentInsets: configuration.value.contentInsets
        )
    }
}

/// Combines position and size inputs into a single content frame.
private struct ViewFrameProvider: Rule {
    typealias Value = ViewFrame

    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>

    func updateValue() -> ViewFrame {
        ViewFrame(origin: position.value, size: size.value)
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
private enum ContentMarginPlacement: Hashable, Sendable {
    case automatic
    case scrollContent
    case scrollIndicators
}

/// Placeholder modifier that records content-margin placement reset intent.
private struct ResetContentMarginModifier: ViewModifier {
    var placements: [ContentMarginPlacement]

    func body(content: Content) -> some View {
        content
    }
}

/// Carries scrollable axis settings through the modifier pipeline.
private struct EnvironmentAxesModifier: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    var scrollableAxes: Axis.Set

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
    }
}

/// Placeholder modifier for resolved scroll behavior scoped to specific axes.
private struct ResolvedScrollBehaviorModifier: ViewModifier {
    var axes: Axis.Set

    func body(content: Content) -> some View {
        content
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
        guard let graph = AttributeGraph.current else {
            fatalError("ScrollPhaseStateConfigurationModifier._makeView called outside an active AttributeGraph context.")
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
