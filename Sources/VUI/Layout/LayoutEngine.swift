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

/// Exposes graph-backed geometry and environment values during position-aware placement.
struct _PositionAwarePlacementContext {
    var context: AnyRuleContext
    var owner: AGAttribute
    var _size: Attribute<ViewSize>
    var _environment: Attribute<EnvironmentValues>
    var _transform: Attribute<ViewTransform>
    var _position: Attribute<CGPoint>
    var _safeAreaInsets: OptionalAttribute<SafeAreaInsets>

    init(
        context: AnyRuleContext,
        owner: AGAttribute? = nil,
        size: Attribute<ViewSize>,
        environment: Attribute<EnvironmentValues>,
        transform: Attribute<ViewTransform>,
        position: Attribute<CGPoint>,
        safeAreaInsets: OptionalAttribute<SafeAreaInsets>
    ) {
        self.context = context
        self.owner = owner ?? context.attribute
        self._size = size
        self._environment = environment
        self._transform = transform
        self._position = position
        self._safeAreaInsets = safeAreaInsets
    }

    var size: CGSize {
        _size.value.value
    }

    var proposedSize: _ProposedSize {
        _size.value.proposal
    }

    var transform: ViewTransform {
        var transform = _transform.value
        transform.appendPosition(_position.value)
        return transform
    }

    var unadjustedSafeAreaInsets: SafeAreaInsets? {
        _safeAreaInsets.attribute?.value
    }
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
    mutating func lengthThatFits(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat
    mutating func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry]
    mutating func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat?
    mutating func childPlacement(at size: ViewSize) -> _Placement
    mutating func childPlacement(at size: ViewSize,
                                 placementContext: _PositionAwarePlacementContext) -> _Placement
}

extension LayoutEngine {
    var debugContentDescription: String? { nil }
    func layoutPriority() -> Double { 0 }
    func ignoresAutomaticPadding() -> Bool { false }
    func requiresSpacingProjection() -> Bool { false }
    func spacing() -> Spacing { Spacing() }
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
        if var current = _AGGraph.currentStatefulOutput(LayoutComputer.self) {
            current.withMutableEngine(type: Engine.self, do: modify)
            current.seed &+= 1
            _AGGraph.setStatefulOutput(current)
        } else {
            _AGGraph.setStatefulOutput(LayoutComputer(create()))
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

// MARK: - Layout tracing

/// Coordinates optional layout cache and alignment tracing for the active graph.
struct LayoutTrace {
    /// Stores the mutable trace state collected during one graph's layout work.
    final class Recorder {
        var graph: AGGraphRef
        var frameActive: Bool
        var cacheLookup: (proposal: _ProposedSize, hit: Bool)?
        var alignmentTypes: [UInt32: AlignmentID.Type]

        init(graph: AGGraphRef) {
            self.graph = graph
            self.frameActive = false
            self.cacheLookup = nil
            self.alignmentTypes = [:]
        }

        func traceSizeThatFits(
            _ attribute: AGAttribute?,
            proposal: _ProposedSize,
            _ body: () -> CGSize
        ) -> CGSize {
            body()
        }

        func traceLengthThatFits(
            _ attribute: AGAttribute?,
            proposal: _ProposedSize,
            in axis: Axis,
            _ body: () -> CGFloat
        ) -> CGFloat {
            body()
        }

        func traceChildGeometries(
            _ attribute: AGAttribute?,
            at size: ViewSize,
            origin: CGPoint,
            body: () -> [ViewGeometry]
        ) -> [ViewGeometry] {
            body()
        }

        func traceExplicitAlignment(
            _ attribute: AGAttribute?,
            alignment: AlignmentKey,
            at size: ViewSize,
            body: () -> CGFloat?
        ) -> CGFloat? {
            body()
        }
    }

    nonisolated(unsafe) static var recorder: Recorder?

    static func traceSizeThatFits(
        _ attribute: AGAttribute?,
        proposal: _ProposedSize,
        _ body: () -> CGSize
    ) -> CGSize {
        guard let recorder else {
            fatalError("A tracing layout engine was used outside its recorder lifetime.")
        }
        return recorder.traceSizeThatFits(attribute, proposal: proposal, body)
    }

    static func traceLengthThatFits(
        _ attribute: AGAttribute?,
        proposal: _ProposedSize,
        in axis: Axis,
        _ body: () -> CGFloat
    ) -> CGFloat {
        guard let recorder else {
            fatalError("A tracing layout engine was used outside its recorder lifetime.")
        }
        return recorder.traceLengthThatFits(
            attribute,
            proposal: proposal,
            in: axis,
            body
        )
    }

    static func traceCacheLookup(_ proposal: _ProposedSize, _ hit: Bool) {
        recorder?.cacheLookup = (proposal, hit)
    }

    static func traceCacheLookup(_ size: CGSize, _ hit: Bool) {
        traceCacheLookup(_ProposedSize(size), hit)
    }

    static func traceChildGeometries(
        _ attribute: AGAttribute?,
        at size: ViewSize,
        origin: CGPoint,
        _ body: () -> [ViewGeometry]
    ) -> [ViewGeometry] {
        guard let recorder else {
            fatalError("A tracing layout engine was used outside its recorder lifetime.")
        }
        return recorder.traceChildGeometries(
            attribute,
            at: size,
            origin: origin,
            body: body
        )
    }

    static func traceExplicitAlignment(
        _ attribute: AGAttribute?,
        alignment: AlignmentKey,
        at size: ViewSize,
        body: () -> CGFloat?
    ) -> CGFloat? {
        guard let recorder else {
            fatalError("A tracing layout engine was used outside its recorder lifetime.")
        }
        return recorder.traceExplicitAlignment(
            attribute,
            alignment: alignment,
            at: size,
            body: body
        )
    }
}

// MARK: - Layout engine erasure

/// Defines the type-erased dispatch surface stored by a layout computer.
class AnyLayoutEngineBox {
    func mutateEngine<Engine: LayoutEngine, Result>(
        as type: Engine.Type,
        do body: (inout Engine) -> Result
    ) -> Result {
        fatalError("Abstract layout-engine box method.")
    }

    func layoutPriority() -> Double {
        fatalError("Abstract layout-engine box method.")
    }

    func ignoresAutomaticPadding() -> Bool {
        fatalError("Abstract layout-engine box method.")
    }

    func requiresSpacingProjection() -> Bool {
        fatalError("Abstract layout-engine box method.")
    }

    func spacing() -> Spacing {
        fatalError("Abstract layout-engine box method.")
    }

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        fatalError("Abstract layout-engine box method.")
    }

    func lengthThatFits(
        _ proposal: _ProposedSize,
        in axis: Axis
    ) -> CGFloat {
        fatalError("Abstract layout-engine box method.")
    }

    func childGeometries(
        at size: ViewSize,
        origin: CGPoint
    ) -> [ViewGeometry] {
        fatalError("Abstract layout-engine box method.")
    }

    func explicitAlignment(
        _ key: AlignmentKey,
        at size: ViewSize
    ) -> CGFloat? {
        fatalError("Abstract layout-engine box method.")
    }

    func childPlacement(at size: ViewSize) -> _Placement {
        fatalError("Abstract layout-engine box method.")
    }

    func childPlacement(
        at size: ViewSize,
        placementContext: _PositionAwarePlacementContext
    ) -> _Placement {
        fatalError("Abstract layout-engine box method.")
    }
}

/// Owns one concrete layout engine and forwards erased layout operations to it.
class LayoutEngineBox<E: LayoutEngine>: AnyLayoutEngineBox {
    var engine: E

    init(_ engine: E) {
        self.engine = engine
    }

    override func mutateEngine<Engine: LayoutEngine, Result>(
        as type: Engine.Type,
        do body: (inout Engine) -> Result
    ) -> Result {
        guard type == E.self else {
            fatalError(
                "Layout engine type changed from \(E.self) to \(Engine.self)."
            )
        }
        return withUnsafeMutablePointer(to: &engine) { pointer in
            let typed = UnsafeMutableRawPointer(pointer)
                .assumingMemoryBound(to: Engine.self)
            return body(&typed.pointee)
        }
    }

    override func sizeThatFits(_ p: _ProposedSize) -> CGSize {
        engine.sizeThatFits(p)
    }

    override func spacing() -> Spacing {
        engine.spacing()
    }

    override func layoutPriority() -> Double {
        engine.layoutPriority()
    }

    override func ignoresAutomaticPadding() -> Bool {
        engine.ignoresAutomaticPadding()
    }

    override func requiresSpacingProjection() -> Bool {
        engine.requiresSpacingProjection()
    }

    override func lengthThatFits(
        _ p: _ProposedSize,
        in axis: Axis
    ) -> CGFloat {
        engine.lengthThatFits(p, in: axis)
    }

    override func childGeometries(
        at size: ViewSize,
        origin: CGPoint
    ) -> [ViewGeometry] {
        engine.childGeometries(at: size, origin: origin)
    }

    override func explicitAlignment(
        _ key: AlignmentKey,
        at size: ViewSize
    ) -> CGFloat? {
        engine.explicitAlignment(key, at: size)
    }

    override func childPlacement(at size: ViewSize) -> _Placement {
        engine.childPlacement(at: size)
    }

    override func childPlacement(
        at size: ViewSize,
        placementContext: _PositionAwarePlacementContext
    ) -> _Placement {
        engine.childPlacement(at: size, placementContext: placementContext)
    }
}

/// Adds attribute-scoped trace recording around a concrete layout engine.
final class TracingLayoutEngineBox<E: LayoutEngine>: LayoutEngineBox<E> {
    var attribute: AGAttribute?

    override init(_ engine: E) {
        attribute = _AGGraph.currentRuleContextAttribute
        super.init(engine)
    }

    override func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        LayoutTrace.traceSizeThatFits(attribute, proposal: proposal) {
            super.sizeThatFits(proposal)
        }
    }

    override func lengthThatFits(
        _ proposal: _ProposedSize,
        in axis: Axis
    ) -> CGFloat {
        LayoutTrace.traceLengthThatFits(
            attribute,
            proposal: proposal,
            in: axis
        ) {
            super.lengthThatFits(proposal, in: axis)
        }
    }

    override func childGeometries(
        at size: ViewSize,
        origin: CGPoint
    ) -> [ViewGeometry] {
        LayoutTrace.traceChildGeometries(
            attribute,
            at: size,
            origin: origin
        ) {
            super.childGeometries(at: size, origin: origin)
        }
    }

    override func explicitAlignment(
        _ key: AlignmentKey,
        at size: ViewSize
    ) -> CGFloat? {
        LayoutTrace.traceExplicitAlignment(
            attribute,
            alignment: key,
            at: size
        ) {
            super.explicitAlignment(key, at: size)
        }
    }
}

// MARK: - ViewLayoutEngine<L: Layout>

/// Concrete LayoutEngine for Layout-backed containers.
/// Bridges Layout protocol methods to the LayoutEngine dispatch surface.
/// childGeometries creates PlacementData, exposes it through the thread layout data slot,
/// and lets LayoutSubview.place write child geometries into that buffer.
struct ViewLayoutEngine<L: Layout>: LayoutEngine {
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
        if cachedAlignmentSize != size {
            cachedAlignmentSize = size
            cachedAlignmentGeometry = []
            cachedAlignment = Cache3()
        }

        let cacheKey = key.alignmentCacheKey
        if let cached = cachedAlignment.find(cacheKey) {
            return cached
        }

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
        cachedAlignment.put(cacheKey, value: result)
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
            return geometries
        }
    }

}
