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
