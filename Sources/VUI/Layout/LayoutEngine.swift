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
/// reserved storage used by placement dispatch.
public struct _Placement: Equatable {
    public var anchor: UnitPoint
    public var anchorPosition: CGPoint
    var proposedSize_: _ProposedSize

    public var proposedSize: CGSize {
        get { proposedSize_.fixingUnspecifiedDimensions() }
        set { proposedSize_ = _ProposedSize(newValue) }
    }

    init(
        proposedSize: _ProposedSize,
        anchoring anchor: UnitPoint = .topLeading,
        at anchorPosition: CGPoint = .zero
    ) {
        self.anchor = anchor
        self.anchorPosition = anchorPosition
        self.proposedSize_ = proposedSize
    }

    public init(
        proposedSize: CGSize,
        anchoring anchor: UnitPoint = .topLeading,
        at anchorPosition: CGPoint = .zero
    ) {
        self.init(
            proposedSize: _ProposedSize(proposedSize),
            anchoring: anchor,
            at: anchorPosition
        )
    }

    init(proposedSize: _ProposedSize, at position: CGPoint) {
        self.init(proposedSize: proposedSize, anchoring: .topLeading, at: position)
    }

    init(proposedSize: _ProposedSize, aligning anchor: UnitPoint, in size: CGSize) {
        self.init(
            proposedSize: proposedSize,
            anchoring: anchor,
            at: CGPoint(x: size.width * anchor.x, y: size.height * anchor.y)
        )
    }

    public init(proposedSize: CGSize, aligning anchor: UnitPoint, in size: CGSize) {
        self.init(proposedSize: _ProposedSize(proposedSize), aligning: anchor, in: size)
    }

    func frameOrigin(childSize: CGSize) -> CGPoint {
        CGPoint(
            x: anchorPosition.x - childSize.width * anchor.x,
            y: anchorPosition.y - childSize.height * anchor.y
        )
    }
}

// MARK: - _PositionAwarePlacementContext

/// Context passed to the position-aware child-placement vtable method.
/// The internal fields are intentionally opaque until behavior requires modeling.
struct _PositionAwarePlacementContext {
}

// MARK: - LayoutEngine protocol

/// Protocol for a layout engine stored inside a LayoutEngineBox.
/// Methods cover sizing, spacing, child geometry generation, explicit alignment,
/// and child placement.
/// Internal because it uses internal types (ViewSize, ViewGeometry, AlignmentKey).
protocol LayoutEngine {
    var debugContentDescription: String? { get }
    func layoutPriority() -> Double
    func ignoresAutomaticPadding() -> Bool
    func requiresSpacingProjection() -> Bool
    mutating func spacing() -> Spacing
    mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize
    mutating func truncates(_ proposal: _ProposedSize) -> Bool
    mutating func lengthThatFits(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat
    mutating func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry]
    mutating func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat?
    mutating func childPlacement(at size: ViewSize) -> _Placement
    mutating func childPlacement(at size: ViewSize,
                                 placementContext: _PositionAwarePlacementContext) -> _Placement
}

/// Renderer-side placement dispatch kept separate from the layout-engine
/// protocol surface.
protocol LayoutEnginePlacing {
    mutating func place(at position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize)
}

extension LayoutEngine {
    var debugContentDescription: String? { nil }
    func layoutPriority() -> Double { 0 }
    func ignoresAutomaticPadding() -> Bool { false }
    func requiresSpacingProjection() -> Bool { false }
    func spacing() -> Spacing { Spacing() }
    mutating func truncates(_ proposal: _ProposedSize) -> Bool {
        let ideal = sizeThatFits(.unspecified)
        return proposal.width.map { ideal.width > $0 } == true ||
            proposal.height.map { ideal.height > $0 } == true
    }
    mutating func lengthThatFits(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat {
        let s = sizeThatFits(proposal)
        return axis == .horizontal ? s.width : s.height
    }
    func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry] { [] }
    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? { nil }
    mutating func childPlacement(at size: ViewSize) -> _Placement {
        _Placement(proposedSize: CGSize(width: size.width, height: size.height),
                   anchoring: .topLeading, at: .zero)
    }
    mutating func childPlacement(at size: ViewSize,
                                 placementContext: _PositionAwarePlacementContext) -> _Placement {
        childPlacement(at: size)
    }
}

extension StatefulRule where Value == LayoutComputer {
    mutating func update<Engine: LayoutEngine>(
        modify: (inout Engine) -> Void,
        create: () -> Engine
    ) {
        if var current = _AGGraph.currentStatefulOutput(LayoutComputer.self),
           current.withMutableEngine(type: Engine.self, do: modify) != nil {
            current.changeCount &+= 1
            _AGGraph.setStatefulOutput(current)
        } else {
            _AGGraph.setStatefulOutput(
                LayoutComputer(box: LayoutEngineBox(engine: create()))
            )
        }
    }

    mutating func update<Engine: LayoutEngine>(to engine: Engine) {
        update(modify: { $0 = engine }, create: { engine })
    }

    mutating func updateIfNotEqual<Engine>(to engine: Engine)
    where Engine: LayoutEngine & Equatable {
        if let current = _AGGraph.currentStatefulOutput(LayoutComputer.self),
           let box = current.box as? LayoutEngineBox<Engine>,
           box.engine == engine {
            return
        }
        update(to: engine)
    }

    mutating func updateLayoutComputer<L: Layout>(
        layout: L,
        environment: Attribute<EnvironmentValues>,
        attributes: [LayoutProxyAttributes]
    ) {
        guard let attribute = _AGGraph.currentRuleContextAttribute else {
            fatalError("Layout computer update requires an active rule context.")
        }
        let context = AnyRuleContext(attribute: attribute)
        let layoutContext = SizeAndSpacingContext(
            context: context,
            owner: attribute,
            environment: environment
        )
        let children = LayoutProxyCollection(
            context: context,
            attributes: attributes
        )
        layout.updateLayoutComputer(
            rule: &self,
            layoutContext: layoutContext,
            children: children
        )
    }
}

extension Layout {
    func updateLayoutComputer<R: StatefulRule>(
        rule: inout R,
        layoutContext: SizeAndSpacingContext,
        children: LayoutProxyCollection
    ) where R.Value == LayoutComputer {
        rule.update(
            modify: { (engine: inout ViewLayoutEngine<Self>) in
                engine.update(
                    layout: self,
                    context: layoutContext,
                    children: children
                )
            },
            create: {
                ViewLayoutEngine(
                    layout: self,
                    context: layoutContext,
                    children: children
                )
            }
        )
    }
}

// MARK: - _AnyLayoutEngineBoxDispatch

/// Class-bound dispatch protocol for LayoutEngineBox.
/// Using a class-bound protocol lets LayoutComputer.box store a single 8-byte pointer.
/// Class-constrained existentials use a single reference word with no inline witness table.
protocol _AnyLayoutEngineBoxDispatch: AnyObject {
    var currentAttribute: AGAttribute { get set }
    var isNilAttribute: Bool { get set }
    func sizeThatFits_(_ proposal: _ProposedSize) -> CGSize
    func spacing_() -> Spacing
    func layoutPriority_() -> Double
    func ignoresAutomaticPadding_() -> Bool
    func requiresSpacingProjection_() -> Bool
    func lengthThatFits_(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat
    func childGeometries_(at size: ViewSize, origin: CGPoint) -> [ViewGeometry]
    func explicitAlignment_(_ key: AlignmentKey, at size: ViewSize) -> CGFloat?
    func childPlacement_(at size: ViewSize) -> _Placement
    func childPlacement_(at size: ViewSize,
                         placementContext: _PositionAwarePlacementContext) -> _Placement
    func place_(_ position: CGPoint, _ anchor: UnitPoint, _ proposal: ProposedViewSize)
}

/// Three-entry insertion-order cache used for repeated layout proposals.
/// Cache hits do not change replacement order: after three distinct inserts,
/// the fourth replaces the oldest inserted entry.
private struct LayoutSizeCache {
    private struct Entry {
        var proposal: _ProposedSize
        var size: CGSize
    }

    private var first: Entry?
    private var second: Entry?
    private var third: Entry?
    private var replacementIndex = 0

    mutating func value(
        for proposal: _ProposedSize,
        makeValue: () -> CGSize
    ) -> CGSize {
        if let first, first.proposal == proposal { return first.size }
        if let second, second.proposal == proposal { return second.size }
        if let third, third.proposal == proposal { return third.size }

        let size = makeValue()
        let entry = Entry(proposal: proposal, size: size)
        switch replacementIndex {
        case 0: first = entry
        case 1: second = entry
        default: third = entry
        }
        replacementIndex = (replacementIndex + 1) % 3
        return size
    }

    mutating func invalidate() {
        first = nil
        second = nil
        third = nil
        replacementIndex = 0
    }
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

    func sizeThatFits_(_ p: _ProposedSize) -> CGSize { engine.sizeThatFits(p) }
    func spacing_() -> Spacing { engine.spacing() }
    func layoutPriority_() -> Double { engine.layoutPriority() }
    func ignoresAutomaticPadding_() -> Bool { engine.ignoresAutomaticPadding() }
    func requiresSpacingProjection_() -> Bool { engine.requiresSpacingProjection() }
    func lengthThatFits_(_ p: _ProposedSize, in axis: Axis) -> CGFloat {
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
        // Closure layout computers are reference-backed renderer bridges. Their
        // placement closure can read geometry through the same layout computer,
        // so invoking the generic mutating witness directly would keep an
        // exclusive modification access to `engine` across that reentrant read.
        if let referenceEngine = engine as? ClosureLayoutEngine {
            referenceEngine.place(at: position, anchor: anchor, proposal: proposal)
            return
        }
        guard var placementEngine = engine as? any LayoutEnginePlacing else {
            return
        }
        placementEngine.place(at: position, anchor: anchor, proposal: proposal)
        guard let updatedEngine = placementEngine as? E else {
            fatalError("LayoutEngine placement dispatch changed the concrete engine type.")
        }
        engine = updatedEngine
    }

}

// MARK: - ClosureLayoutEngine

// MARK: - ViewLayoutEngine<L: Layout>

/// Concrete LayoutEngine for Layout-backed containers.
/// Bridges Layout protocol methods to the LayoutEngine dispatch surface.
/// childGeometries creates PlacementData, exposes it through the thread layout data slot,
/// and lets LayoutSubview.place write child geometries into that buffer.
struct ViewLayoutEngine<L: Layout>: LayoutEngine, LayoutEnginePlacing {
    var layout: L
    var cache: L.Cache
    var proxies: LayoutProxyCollection
    var layoutDirection: LayoutDirection
    var sizeCache: ViewSizeCache
    var cachedAlignmentSize: ViewSize
    var cachedAlignmentGeometry: [ViewGeometry]
    var cachedAlignment: Cache3<CGFloat, CGFloat?>
    var preferredSpacing: Spacing?

    init(
        layout: L,
        context: SizeAndSpacingContext,
        children: LayoutProxyCollection
    ) {
        self.layout = layout
        self.proxies = children
        self.layoutDirection = context[dynamicMember: \.layoutDirection]
        self.sizeCache = ViewSizeCache()
        self.cachedAlignmentSize = .zero
        self.cachedAlignmentGeometry = []
        self.cachedAlignment = Cache3()
        self.preferredSpacing = nil
        self.cache = layout.makeCache(
            subviews: Self.makeSubviews(
                children: children,
                layoutDirection: self.layoutDirection
            )
        )
    }

    private static func makeSubviews(
        children: LayoutProxyCollection,
        layoutDirection: LayoutDirection
    ) -> LayoutSubviews {
        LayoutSubviews(
            context: children.context,
            attributes: children.attributes,
            layoutDirection: layoutDirection
        )
    }

    private func makeSubviews() -> LayoutSubviews {
        Self.makeSubviews(
            children: proxies,
            layoutDirection: layoutDirection
        )
    }

    mutating func update(
        layout: L,
        context: SizeAndSpacingContext,
        children: LayoutProxyCollection
    ) {
        self.layout = layout
        self.proxies = children
        self.layoutDirection = context[dynamicMember: \.layoutDirection]
        self.layout.updateCache(&cache, subviews: makeSubviews())
        sizeCache = ViewSizeCache()
        cachedAlignmentSize = .zero
        cachedAlignmentGeometry = []
        cachedAlignment = Cache3()
        preferredSpacing = nil
    }

    private func placementTransaction() -> Transaction {
        guard let graph = _AGGraph.current else {
            return Transaction.current
        }
        if let transaction = graph.transaction(for: proxies.context.attribute),
           !transaction.isEmpty {
            return transaction
        }
        for child in proxies.attributes {
            guard let attr = child.layoutComputer.attribute,
                  let transaction = graph.transaction(for: attr.identifier),
                  !transaction.isEmpty else {
                continue
            }
            return transaction
        }
        return Transaction.current
    }

    mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        let layout = layout
        let subviews = makeSubviews()
        return sizeCache.get(proposal) {
            var result: CGSize!
            proxies.context.update {
                result = layout.sizeThatFits(
                    proposal: ProposedViewSize(proposal),
                    subviews: subviews,
                    cache: &cache
                )
            }
            return result
        }
    }

    mutating func spacing() -> Spacing {
        if let preferredSpacing {
            return preferredSpacing
        }
        let layout = layout
        let subviews = makeSubviews()
        var spacing: Spacing!
        proxies.context.update {
            spacing = layout.spacing(subviews: subviews, cache: &cache).spacing
        }
        preferredSpacing = spacing
        return spacing
    }

    mutating func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        let subviews = makeSubviews()
        let bounds = CGRect(origin: .zero, size: size.value)

        var result: CGFloat?
        proxies.context.update {
            switch key.axis {
            case .horizontal:
                result = layout.explicitAlignment(of: HorizontalAlignment(alignmentKey: key.bits),
                                                  in: bounds,
                                                  proposal: ProposedViewSize(size.proposal),
                                                  subviews: subviews,
                                                  cache: &cache)
            case .vertical:
                result = layout.explicitAlignment(of: VerticalAlignment(alignmentKey: key.bits),
                                                  in: bounds,
                                                  proposal: ProposedViewSize(size.proposal),
                                                  subviews: subviews,
                                                  cache: &cache)
            }
        }
        return result
    }

    mutating func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry] {
        if origin == .zero,
           cachedAlignmentSize == size,
           cachedAlignmentGeometry.count == proxies.count {
            return cachedAlignmentGeometry
        }

        let subviews = makeSubviews()
        var placementData = PlacementData(
            count: proxies.count,
            bounds: CGRect(origin: origin, size: size.value),
            layoutDirection: layoutDirection
        )
        return withUnsafeMutablePointer(to: &placementData) { pointer in
            ThreadLayoutData.withPlacementData(pointer) {
                Transaction.withScopedThreadTransaction(placementTransaction()) {
                    proxies.context.update {
                        layout.placeSubviews(
                            in: CGRect(origin: origin, size: size.value),
                            proposal: ProposedViewSize(size.proposal),
                            subviews: subviews,
                            cache: &cache
                        )
                    }
                }
            }
            let geometries = pointer.pointee.resolvedGeometries(
                children: proxies.attributes,
                proposal: ProposedViewSize(size.proposal)
            )
            if origin == .zero {
                cachedAlignmentSize = size
                cachedAlignmentGeometry = geometries
            }
            return geometries
        }
    }

    mutating func place(at position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize) {
        let subviews = makeSubviews()
        let size = sizeThatFits(_ProposedSize(proposal))
        let origin = CGPoint(
            x: position.x - size.width * anchor.x,
            y: position.y - size.height * anchor.y
        )
        Transaction.withScopedThreadTransaction(placementTransaction()) {
            proxies.context.update {
                layout.placeSubviews(
                    in: CGRect(origin: origin, size: size),
                    proposal: proposal,
                    subviews: subviews,
                    cache: &cache
                )
            }
        }
    }
}

// MARK: - ClosureLayoutEngine

/// Closure-based LayoutEngine bridging the closure-based LayoutComputer API
/// to the LayoutEngine protocol required by LayoutEngineBox.
final class ClosureLayoutEngine: LayoutEngine, LayoutEnginePlacing {
    var _sizeThatFits: (_ProposedSize) -> CGSize
    var _spacing: Spacing
    var _place: (CGPoint, UnitPoint, ProposedViewSize) -> Void
    var _childGeometries: (ViewSize, CGPoint) -> [ViewGeometry]
    var _priority: Double
    var _explicitAlignment: ((AlignmentKey, ViewSize) -> CGFloat?)?

    init(
        sizeThatFits: @escaping (_ProposedSize) -> CGSize,
        spacing: Spacing = Spacing(),
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

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize { _sizeThatFits(proposal) }
    func spacing() -> Spacing { _spacing }
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
