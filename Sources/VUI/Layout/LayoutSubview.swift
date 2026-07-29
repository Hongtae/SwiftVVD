//
//  File: LayoutSubview.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - LayoutProxyAttributes

/// Attributes for LayoutProxy: layoutComputer + traitsList.
/// Both fields use a sentinel value for nil encoding (OptionalAttribute pattern).
struct LayoutProxyAttributes: Equatable {
    /// Optional AG attribute for the child's layout computation.
    var layoutComputer: OptionalAttribute<LayoutComputer>
    /// Optional AG attribute for this child's ViewList (used for trait access).
    /// Reading `.value.traits` inside a layout rule registers a re-layout dependency.
    var traitsList: OptionalAttribute<any ViewList>

    init(
        layoutComputer: OptionalAttribute<LayoutComputer>,
        traitsList: OptionalAttribute<any ViewList>
    ) {
        self.layoutComputer = layoutComputer
        self.traitsList = traitsList
    }

    init(layoutComputer: Attribute<LayoutComputer>,
         traitsList: OptionalAttribute<any ViewList> = OptionalAttribute()) {
        self.layoutComputer = OptionalAttribute(layoutComputer)
        self.traitsList = traitsList
    }

    init(traitsList: OptionalAttribute<any ViewList>) {
        self.layoutComputer = OptionalAttribute()
        self.traitsList = traitsList
    }

    init() {
        self.layoutComputer = OptionalAttribute()
        self.traitsList = OptionalAttribute()
    }

    var isEmpty: Bool {
        layoutComputer.attribute == nil && traitsList.attribute == nil
    }
}

// MARK: - LayoutProxy

/// Proxy for a child view in a Layout.
/// Dependency tracking uses AG thread-local reads.
struct LayoutProxy: Equatable {
    var context: AnyRuleContext
    var attributes: LayoutProxyAttributes

    init(attributes: LayoutProxyAttributes) {
        let contextAttribute = _AGGraph.currentRuleContextAttribute ??
            attributes.layoutComputer.attribute?.identifier ??
            .invalid
        self.context = AnyRuleContext(attribute: contextAttribute)
        self.attributes = attributes
    }

    init(context: AnyRuleContext, attributes: LayoutProxyAttributes) {
        self.context = context
        self.attributes = attributes
    }

    init(
        context: AnyRuleContext,
        layoutComputer: Attribute<LayoutComputer>?
    ) {
        self.context = context
        self.attributes = LayoutProxyAttributes(
            layoutComputer: OptionalAttribute(layoutComputer),
            traitsList: OptionalAttribute()
        )
    }

    /// The child's LayoutComputer value (reads AG attribute; registers dependency).
    var layoutComputer: LayoutComputer {
        guard let attr = attributes.layoutComputer.attribute else {
            return LayoutComputer.defaultValue
        }
        return context[attr]
    }

    func dimensions(in proposal: _ProposedSize) -> ViewDimensions {
        layoutComputer.dimensions(in: proposal)
    }

    /// The child's ViewTraitCollection if a traitsList attribute is present.
    /// Reading the traitsList attribute registers a layout dependency.
    /// Returns nil if no traitsList attribute is set.
    var traits: ViewTraitCollection? {
        guard let traitsList = attributes.traitsList.attribute else {
            return nil
        }
        let viewList: any ViewList = context[traitsList]
        return viewList.traits
    }

    /// Returns the trait value for key K.
    subscript<K: _ViewTraitKey>(key: K.Type) -> K.Value {
        traits?[key] ?? K.defaultValue
    }

    func finallyPlaced(
        at placement: _Placement,
        in size: CGSize,
        layoutDirection: LayoutDirection
    ) -> ViewGeometry {
        let proposal = placement.proposedSize_
        let resolvedDimensions = self.dimensions(in: proposal)
        var origin = CGPoint(
            x: placement.anchorPosition.x - resolvedDimensions.width * placement.anchor.x,
            y: placement.anchorPosition.y - resolvedDimensions.height * placement.anchor.y
        )
        if layoutDirection == .rightToLeft {
            origin.x = size.width - origin.x
        }
        return ViewGeometry(origin: origin, dimensions: resolvedDimensions)
    }
}

struct LayoutProxyCollection: RandomAccessCollection {
    typealias Index = Int
    typealias Element = LayoutProxy

    var context: AnyRuleContext
    var attributes: [LayoutProxyAttributes]

    var startIndex: Int { attributes.startIndex }
    var endIndex: Int { attributes.endIndex }

    subscript(position: Int) -> LayoutProxy {
        LayoutProxy(context: context, attributes: attributes[position])
    }
}

// MARK: - PlacementData

/// Local placement buffer used by ViewLayoutEngine.childGeometries(at:origin:).
/// ThreadLayoutData exposes this during layout so LayoutSubview.place can write child
/// geometries into the active placement pass.
struct PlacementData {
    var isLocked: Bool
    var geometries: [ViewGeometry]
    var placedCount: Int
    var bounds: CGRect
    var layoutDirection: LayoutDirection

    init(count: Int,
         bounds: CGRect,
         layoutDirection: LayoutDirection) {
        self.isLocked = false
        self.geometries = Array(repeating: .invalidValue, count: count)
        self.placedCount = 0
        self.bounds = bounds
        self.layoutDirection = layoutDirection
    }

    mutating func setGeometry(_ geometry: ViewGeometry,
                              at index: Int,
                              layoutDirection: LayoutDirection) {
        precondition(!isLocked)
        precondition(index >= 0 && index < geometries.count)

        let old = geometries[index]
        if old.isInvalid && !geometry.isInvalid {
            placedCount += 1
        }

        var stored = geometry
        if layoutDirection != self.layoutDirection {
            let maxX = bounds.maxX
            stored.origin.x = maxX - (geometry.origin.x + geometry.dimensions.width)
        }
        geometries[index] = stored
    }

    mutating func resolvedGeometries(children: [LayoutProxyAttributes],
                                     proposal: ProposedViewSize) -> [ViewGeometry] {
        guard placedCount != geometries.count else { return geometries }
        for index in geometries.indices where geometries[index].isInvalid {
            let computer = children[index].layoutComputer.attribute?.value ?? LayoutComputer.defaultValue
            let dimensions = computer.dimensions(in: _ProposedSize(proposal))
            let origin = CGPoint(
                x: bounds.midX - dimensions.width * 0.5,
                y: bounds.midY - dimensions.height * 0.5
            )
            geometries[index] = ViewGeometry(origin: origin, dimensions: dimensions)
        }
        placedCount = geometries.count
        return geometries
    }
}

extension ViewGeometry {
    static var invalidValue: ViewGeometry {
        ViewGeometry(
            origin: CGPoint(x: CGFloat.nan, y: CGFloat.nan),
            dimensions: ViewDimensions(
                guideComputer: LayoutComputer.defaultValue,
                size: ViewSize(
                    width: -CGFloat.infinity,
                    height: -CGFloat.infinity,
                    proposal: _ProposedSize(
                        width: -CGFloat.infinity,
                        height: -CGFloat.infinity
                    )
                )
            )
        )
    }

    var isInvalid: Bool {
        !origin.x.isFinite || !origin.y.isFinite
    }
}

enum ThreadLayoutData {
    private static let placementData = _AGThreadLocal<UnsafeMutablePointer<PlacementData>?>(nil)

    static func withPlacementData<R>(
        _ pointer: UnsafeMutablePointer<PlacementData>,
        _ body: () -> R
    ) -> R {
        placementData.withValue(pointer, operation: body)
    }

    static func setGeometry(_ geometry: ViewGeometry,
                            at index: Int,
                            layoutDirection: LayoutDirection) -> Bool {
        guard let pointer = placementData.value else { return false }
        pointer.pointee.setGeometry(geometry, at: index, layoutDirection: layoutDirection)
        return true
    }
}

// MARK: - LayoutSubview

/// A proxy for a single child view in a Layout.
/// Stores the child proxy, placement index, and layout direction used by the
/// placement buffer.
public struct LayoutSubview: Equatable {

    var proxy: LayoutProxy

    /// Index used by PlacementData.setGeometry(at:) during placement.
    var index: Int32

    /// Per-subview layout direction.
    var containerLayoutDirection: LayoutDirection

    init(proxy: LayoutProxy,
         index: Int32 = 0,
         containerLayoutDirection: LayoutDirection = .leftToRight) {
        self.proxy = proxy
        self.index = index
        self.containerLayoutDirection = containerLayoutDirection
    }

    // MARK: - Trait access

    /// Returns the trait value for key K.
    /// Delegates to LayoutProxy.subscript.
    public func _trait<K>(key: K.Type) -> K.Value where K: _ViewTraitKey {
        proxy[key]
    }

    public subscript<K>(key: K.Type) -> K.Value where K: LayoutValueKey {
        _trait(key: _LayoutTrait<K>.self)
    }

    // MARK: - Layout API

    public var priority: Double {
        proxy.layoutComputer.layoutPriority()
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proxy.layoutComputer.sizeThatFits(_ProposedSize(proposal))
    }

    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        proxy.layoutComputer.dimensions(in: _ProposedSize(proposal))
    }

    public var spacing: ViewSpacing {
        ViewSpacing(
            proxy.layoutComputer.spacing(),
            layoutDirection: containerLayoutDirection
        )
    }

    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        let dimensions = self.dimensions(in: proposal)
        place(at: position, anchor: anchor, dimensions: dimensions)
    }

    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, dimensions: ViewDimensions) {
        let origin = CGPoint(
            x: position.x - dimensions.width * anchor.x,
            y: position.y - dimensions.height * anchor.y
        )
        guard origin.x.isFinite && origin.y.isFinite else {
            fatalError("view origin is invalid: \(position), \(anchor), \(CGSize(width: dimensions.width, height: dimensions.height))")
        }
        place(in: ViewGeometry(origin: origin, dimensions: dimensions), layoutDirection: .leftToRight)
    }

    func place(in geometry: ViewGeometry, layoutDirection: LayoutDirection) {
        if !ThreadLayoutData.setGeometry(geometry,
                                         at: Int(index),
                                         layoutDirection: layoutDirection) {
            proxy.layoutComputer.place(at: geometry.origin,
                                       anchor: .topLeading,
                                       proposal: ProposedViewSize(geometry.dimensions.size.proposal))
        }
    }

}

@available(*, unavailable)
extension LayoutSubview: Sendable {
}

// MARK: - LayoutSubviews

public struct LayoutSubviews: Equatable, RandomAccessCollection, @unchecked Sendable {
    private enum Storage: Equatable {
        struct IndexedAttributes: Equatable {
            var attributes: LayoutProxyAttributes
            var index: Int32
        }

        case direct([LayoutProxyAttributes])
        case indirect([IndexedAttributes])

        var count: Int {
            switch self {
            case .direct(let attributes):
                return attributes.count
            case .indirect(let attributes):
                return attributes.count
            }
        }

        subscript(position: Int) -> IndexedAttributes {
            switch self {
            case .direct(let attributes):
                return IndexedAttributes(
                    attributes: attributes[position],
                    index: Int32(position)
                )
            case .indirect(let attributes):
                return attributes[position]
            }
        }
    }

    public typealias SubSequence = LayoutSubviews
    public typealias Element = LayoutSubview
    public typealias Index = Int
    public typealias Indices = Range<LayoutSubviews.Index>
    public typealias Iterator = IndexingIterator<LayoutSubviews>

    var context: AnyRuleContext
    private var storage: Storage
    public var layoutDirection: LayoutDirection
    public var startIndex: Int { 0 }
    public var endIndex: Int { storage.count }

    init(
        context: AnyRuleContext,
        attributes: [LayoutProxyAttributes],
        layoutDirection: LayoutDirection
    ) {
        self.context = context
        self.storage = .direct(attributes)
        self.layoutDirection = layoutDirection
    }

    private init(
        context: AnyRuleContext,
        indexedAttributes: [Storage.IndexedAttributes],
        layoutDirection: LayoutDirection
    ) {
        self.context = context
        self.storage = .indirect(indexedAttributes)
        self.layoutDirection = layoutDirection
    }

    public subscript(index: Int) -> LayoutSubviews.Element {
        let item = storage[index]
        return LayoutSubview(
            proxy: LayoutProxy(
                context: context,
                attributes: item.attributes
            ),
            index: item.index,
            containerLayoutDirection: layoutDirection
        )
    }

    public subscript(bounds: Range<Int>) -> LayoutSubviews {
        LayoutSubviews(
            context: context,
            indexedAttributes: bounds.map { storage[$0] },
            layoutDirection: layoutDirection
        )
    }

    public subscript<S>(indices: S) -> LayoutSubviews where S: Sequence, S.Element == Int {
        LayoutSubviews(
            context: context,
            indexedAttributes: indices.map { storage[$0] },
            layoutDirection: layoutDirection
        )
    }
}
