//
//  File: LayoutEngine.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - _Placement

/// The resolved placement for a child view.
/// Stores the child's anchor, parent-local anchor position, proposed size, and
/// reserved storage kept for the mirrored placement surface.
public struct _Placement: Equatable {
    /// The unit point anchor within the child's bounds.
    public var anchor: UnitPoint
    /// The anchor point in parent-local coordinates.
    public var anchorPosition: CGPoint
    /// Proposed width as raw CGFloat. +Inf means unspecified.
    var _proposedWidth: CGFloat
    /// Proposed height as raw CGFloat. +Inf means unspecified.
    var _proposedHeight: CGFloat
    // Reserved internal storage. The runtime role is not modeled yet.
    var _reserved0: CGFloat
    var _reserved1: CGFloat

    /// The proposed size as a CGSize (computed from raw fields).
    public var proposedSize: CGSize {
        get { CGSize(width: _proposedWidth, height: _proposedHeight) }
        set {
            _proposedWidth = newValue.width
            _proposedHeight = newValue.height
        }
    }

    public init(proposedSize: CGSize,
                anchoring anchor: UnitPoint = .topLeading,
                at anchorPosition: CGPoint = .zero) {
        self.anchor = anchor
        self.anchorPosition = anchorPosition
        self._proposedWidth = proposedSize.width
        self._proposedHeight = proposedSize.height
        self._reserved0 = 0
        self._reserved1 = 0
    }

    public static func == (a: _Placement, b: _Placement) -> Bool {
        a.anchor == b.anchor &&
        a.anchorPosition == b.anchorPosition &&
        a._proposedWidth == b._proposedWidth &&
        a._proposedHeight == b._proposedHeight
    }
}

// MARK: - _PositionAwarePlacementContext

/// Context passed to the position-aware child-placement vtable method.
/// The internal fields are intentionally opaque until behavior requires modeling.
struct _PositionAwarePlacementContext {
    var _storage: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)

    init() { _storage = (0, 0, 0, 0, 0, 0, 0) }
}

// MARK: - LayoutEngine protocol

/// Protocol for a layout engine stored inside a LayoutEngineBox.
/// Methods cover sizing, spacing, child geometry generation, explicit alignment,
/// and child placement. `place(at:anchor:proposal:)` is the backend hook for
/// committing final placement to the renderer.
/// Internal because it uses internal types (ViewSize, ViewGeometry, AlignmentKey).
protocol LayoutEngine {
    func layoutPriority() -> Double
    func ignoresAutomaticPadding() -> Bool
    func requiresSpacingProjection() -> Bool
    func spacing() -> ViewSpacing
    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize
    func lengthThatFits(_ proposal: ProposedViewSize, in axis: Axis) -> CGFloat
    func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry]
    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat?
    func childPlacement(at size: ViewSize) -> _Placement
    func childPlacement(at size: ViewSize,
                        placementContext: _PositionAwarePlacementContext) -> _Placement
    // Backend hook for committing final placement to the renderer.
    func place(at position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize)
}

extension LayoutEngine {
    func layoutPriority() -> Double { 0 }
    func ignoresAutomaticPadding() -> Bool { false }
    func requiresSpacingProjection() -> Bool { false }
    func spacing() -> ViewSpacing { ViewSpacing() }
    func lengthThatFits(_ proposal: ProposedViewSize, in axis: Axis) -> CGFloat {
        let s = sizeThatFits(proposal)
        return axis == .horizontal ? s.width : s.height
    }
    func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry] { [] }
    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? { nil }
    func childPlacement(at size: ViewSize) -> _Placement {
        _Placement(proposedSize: CGSize(width: size.width, height: size.height),
                   anchoring: .topLeading, at: .zero)
    }
    func childPlacement(at size: ViewSize,
                        placementContext: _PositionAwarePlacementContext) -> _Placement {
        childPlacement(at: size)
    }
    func place(at position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize) {}
}

// MARK: - _AnyLayoutEngineBoxDispatch

/// Class-bound dispatch protocol for LayoutEngineBox.
/// Using a class-bound protocol lets LayoutComputer.box store a single 8-byte pointer.
/// Class-constrained existentials use a single reference word with no inline witness table.
protocol _AnyLayoutEngineBoxDispatch: AnyObject {
    var currentAttribute: AGAttribute { get set }
    var isNilAttribute: Bool { get set }
    func sizeThatFits_(_ proposal: ProposedViewSize) -> CGSize
    func spacing_() -> ViewSpacing
    func layoutPriority_() -> Double
    func ignoresAutomaticPadding_() -> Bool
    func requiresSpacingProjection_() -> Bool
    func lengthThatFits_(_ proposal: ProposedViewSize, in axis: Axis) -> CGFloat
    func childGeometries_(at size: ViewSize, origin: CGPoint) -> [ViewGeometry]
    func explicitAlignment_(_ key: AlignmentKey, at size: ViewSize) -> CGFloat?
    func childPlacement_(at size: ViewSize) -> _Placement
    func childPlacement_(at size: ViewSize,
                         placementContext: _PositionAwarePlacementContext) -> _Placement
    func place_(_ position: CGPoint, _ anchor: UnitPoint, _ proposal: ProposedViewSize)
}

// MARK: - LayoutEngineBox<E: LayoutEngine>

/// Generic box holding a concrete LayoutEngine instance.
final class LayoutEngineBox<E: LayoutEngine>: _AnyLayoutEngineBoxDispatch {
    /// The AG attribute that "owns" this box (used for dependency tracking).
    var currentAttribute: AGAttribute = .init(rawValue: 0)
    /// True when currentAttribute is not valid (nil attribute).
    var isNilAttribute: Bool = true
    /// The concrete layout engine stored inline.
    var engine: E

    init(engine: E) { self.engine = engine }

    func sizeThatFits_(_ p: ProposedViewSize) -> CGSize { engine.sizeThatFits(p) }
    func spacing_() -> ViewSpacing { engine.spacing() }
    func layoutPriority_() -> Double { engine.layoutPriority() }
    func ignoresAutomaticPadding_() -> Bool { engine.ignoresAutomaticPadding() }
    func requiresSpacingProjection_() -> Bool { engine.requiresSpacingProjection() }
    func lengthThatFits_(_ p: ProposedViewSize, in axis: Axis) -> CGFloat {
        engine.lengthThatFits(p, in: axis)
    }
    func childGeometries_(at size: ViewSize, origin: CGPoint) -> [ViewGeometry] {
        engine.childGeometries(at: size, origin: origin)
    }
    func explicitAlignment_(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        engine.explicitAlignment(key, at: size)
    }
    func childPlacement_(at size: ViewSize) -> _Placement { engine.childPlacement(at: size) }
    func childPlacement_(at size: ViewSize,
                         placementContext: _PositionAwarePlacementContext) -> _Placement {
        engine.childPlacement(at: size, placementContext: placementContext)
    }
    func place_(_ position: CGPoint, _ anchor: UnitPoint, _ proposal: ProposedViewSize) {
        engine.place(at: position, anchor: anchor, proposal: proposal)
    }
}

// MARK: - ClosureLayoutEngine

// MARK: - ViewLayoutEngine<L: Layout>

/// Concrete LayoutEngine for Layout-backed containers.
/// Bridges Layout protocol methods to the LayoutEngine dispatch surface.
/// childGeometries creates PlacementData, exposes it through the thread layout data slot,
/// and lets LayoutSubview.place write child geometries into that buffer.
final class ViewLayoutEngine<L: Layout>: LayoutEngine {
    var layout: L
    var layoutAttr: Attribute<L>?
    var children: [LayoutProxyAttributes]
    var _layoutDirection: LayoutDirection

    init(
        layout: L,
        layoutAttr: Attribute<L>? = nil,
        children: [LayoutProxyAttributes],
        layoutDirection: LayoutDirection
    ) {
        self.layout = layout
        self.layoutAttr = layoutAttr
        self.children = children
        self._layoutDirection = layoutDirection
    }

    private func makeSubviews() -> LayoutSubviews {
        LayoutSubviews(
            subviews: children.enumerated().map { idx, attrs in
                LayoutSubview(
                    proxy: LayoutProxy(attributes: attrs),
                    placementIndex: Int32(idx),
                    layoutDirection: _layoutDirection
                )
            },
            layoutDirection: _layoutDirection
        )
    }

    private func placementTransaction() -> Transaction {
        guard let graph = _AGGraph.current else {
            return Transaction.current
        }
        if let layoutAttr,
           let transaction = graph.transaction(for: layoutAttr.identifier),
           !transaction.isEmpty {
            return transaction
        }
        for child in children {
            guard let attr = child.layoutComputer.attribute,
                  let transaction = graph.transaction(for: attr.identifier),
                  !transaction.isEmpty else {
                continue
            }
            return transaction
        }
        return Transaction.current
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let subviews = makeSubviews()
        var cache = layout.makeCache(subviews: subviews)
        return layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func spacing() -> ViewSpacing {
        let subviews = makeSubviews()
        var cache = layout.makeCache(subviews: subviews)
        return layout.spacing(subviews: subviews, cache: &cache)
    }

    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        let subviews = makeSubviews()
        var cache = layout.makeCache(subviews: subviews)
        let bounds = CGRect(origin: .zero, size: size.value)

        switch key.axis {
        case .horizontal:
            return layout.explicitAlignment(of: HorizontalAlignment(alignmentKey: key.bits),
                                            in: bounds,
                                            proposal: size.proposal,
                                            subviews: subviews,
                                            cache: &cache)
        case .vertical:
            return layout.explicitAlignment(of: VerticalAlignment(alignmentKey: key.bits),
                                            in: bounds,
                                            proposal: size.proposal,
                                            subviews: subviews,
                                            cache: &cache)
        }
    }

    func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry] {
        let subviews = makeSubviews()
        var cache = layout.makeCache(subviews: subviews)
        var placementData = PlacementData(
            count: children.count,
            bounds: CGRect(origin: origin, size: size.value),
            layoutDirection: _layoutDirection
        )
        return withUnsafeMutablePointer(to: &placementData) { pointer in
            ThreadLayoutData.withPlacementData(pointer) {
                withTransaction(placementTransaction()) {
                    layout.placeSubviews(
                        in: CGRect(origin: origin, size: size.value),
                        proposal: ProposedViewSize(size.value),
                        subviews: subviews,
                        cache: &cache
                    )
                }
            }
            return pointer.pointee.resolvedGeometries(children: children,
                                                      proposal: size.proposal)
        }
    }

    func place(at position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize) {
        let subviews = makeSubviews()
        var sizeCache = layout.makeCache(subviews: subviews)
        let size = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &sizeCache)
        let origin = CGPoint(
            x: position.x - size.width * anchor.x,
            y: position.y - size.height * anchor.y
        )
        var placeCache = layout.makeCache(subviews: subviews)
        withTransaction(placementTransaction()) {
            layout.placeSubviews(
                in: CGRect(origin: origin, size: size),
                proposal: proposal,
                subviews: subviews,
                cache: &placeCache
            )
        }
    }
}

// MARK: - ClosureLayoutEngine

/// Closure-based LayoutEngine bridging the closure-based LayoutComputer API
/// to the LayoutEngine protocol required by LayoutEngineBox.
final class ClosureLayoutEngine: LayoutEngine {
    var _sizeThatFits: (ProposedViewSize) -> CGSize
    var _spacing: ViewSpacing
    var _place: (CGPoint, UnitPoint, ProposedViewSize) -> Void
    var _childGeometries: (ViewSize, CGPoint) -> [ViewGeometry]
    var _priority: Double
    var _explicitAlignment: ((AlignmentKey, ViewSize) -> CGFloat?)?

    init(
        sizeThatFits: @escaping (ProposedViewSize) -> CGSize,
        spacing: ViewSpacing = ViewSpacing(),
        place: @escaping (CGPoint, UnitPoint, ProposedViewSize) -> Void = { _, _, _ in },
        childGeometries: @escaping (ViewSize, CGPoint) -> [ViewGeometry] = { _, _ in [] },
        priority: Double = 0,
        explicitAlignment: ((AlignmentKey, ViewSize) -> CGFloat?)? = nil
    ) {
        _sizeThatFits = sizeThatFits
        _spacing = spacing
        _place = place
        _childGeometries = childGeometries
        _priority = priority
        _explicitAlignment = explicitAlignment
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { _sizeThatFits(proposal) }
    func spacing() -> ViewSpacing { _spacing }
    func layoutPriority() -> Double { _priority }
    func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry] {
        _childGeometries(size, origin)
    }
    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        _explicitAlignment?(key, size)
    }
    func place(at position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize) {
        _place(position, anchor, proposal)
    }
}
