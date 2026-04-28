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
struct LayoutProxyAttributes {
    /// Optional AG attribute for the child's layout computation.
    var layoutComputer: OptionalAttribute<LayoutComputer>
    /// Optional AG attribute for this child's ViewList (used for trait access).
    /// Reading `.value.traits` inside a layout rule registers a re-layout dependency.
    var traitsList: OptionalAttribute<any ViewList>

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
/// Dependency tracking uses @TaskLocal; context is stored as the layoutComputer rawValue.
struct LayoutProxy {
    /// AG rule context.
    var context: UInt32
    var attributes: LayoutProxyAttributes

    init(attributes: LayoutProxyAttributes) {
        self.context = attributes.layoutComputer.attribute?.identifier.rawValue ?? 0
        self.attributes = attributes
    }

    /// The child's LayoutComputer value (reads AG attribute; registers dependency).
    var layoutComputer: LayoutComputer {
        guard let attr = attributes.layoutComputer.attribute else {
            return LayoutComputer.defaultValue
        }
        return attr.value
    }

    /// The child's ViewTraitCollection if a traitsList attribute is present.
    /// Reads traitsList attr and returns ViewList.traits.
    /// Returns nil if no traitsList attribute is set.
    var traits: ViewTraitCollection? {
        guard let viewList = attributes.traitsList.attribute?.value else { return nil }
        return viewList.traits  // ViewList protocol method WT[7]
    }

    /// Returns the trait value for key K.
    subscript<K: _ViewTraitKey>(key: K.Type) -> K.Value {
        traits?[key] ?? K.defaultValue
    }
}

// MARK: - PlacementData

/// Local placement buffer used by ViewLayoutEngine.childGeometries(at:origin:).
/// LayoutSubview.place writes into it via setGeometry(_:at:layoutDirection:).
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
            let dimensions = computer.dimensions(in: proposal)
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

private extension ViewGeometry {
    static var invalidValue: ViewGeometry {
        ViewGeometry(
            origin: CGPoint(x: CGFloat.infinity, y: CGFloat.infinity),
            dimensions: ViewDimensions(guideComputer: LayoutComputer.defaultValue,
                                       size: ViewSize(width: CGFloat.infinity,
                                                      height: CGFloat.infinity))
        )
    }

    var isInvalid: Bool {
        !origin.x.isFinite || !origin.y.isFinite
    }
}

enum ThreadLayoutData {
    nonisolated(unsafe) private static var current: UnsafeMutablePointer<PlacementData>?

    static func withPlacementData<R>(
        _ pointer: UnsafeMutablePointer<PlacementData>,
        _ body: () -> R
    ) -> R {
        let previous = current
        current = pointer
        defer { current = previous }
        return body()
    }

    static func setGeometry(_ geometry: ViewGeometry,
                            at index: Int,
                            layoutDirection: LayoutDirection) -> Bool {
        guard let current else { return false }
        current.pointee.setGeometry(geometry, at: index, layoutDirection: layoutDirection)
        return true
    }
}

// MARK: - LayoutSubview

/// A proxy for a single child view in a Layout.
public struct LayoutSubview: Equatable {

    var proxy: LayoutProxy

    /// Index used by PlacementData.setGeometry(at:).
    /// Currently unused for final placement.
    var placementIndex: Int32

    /// Per-subview layout direction.
    var layoutDirection: LayoutDirection

    init(proxy: LayoutProxy,
         placementIndex: Int32 = 0,
         layoutDirection: LayoutDirection = .leftToRight) {
        self.proxy = proxy
        self.placementIndex = placementIndex
        self.layoutDirection = layoutDirection
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
        proxy.layoutComputer.priority
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proxy.layoutComputer.sizeThatFits(proposal)
    }

    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        proxy.layoutComputer.dimensions(in: proposal)
    }

    public var spacing: ViewSpacing {
        proxy.layoutComputer.spacing
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
                                         at: Int(placementIndex),
                                         layoutDirection: layoutDirection) {
            proxy.layoutComputer.place(at: geometry.origin,
                                       anchor: .topLeading,
                                       proposal: geometry.dimensions.size.proposal)
        }
    }

    public static func == (a: LayoutSubview, b: LayoutSubview) -> Bool {
        a.proxy.attributes.layoutComputer.base.identifier == b.proxy.attributes.layoutComputer.base.identifier
    }
}

// MARK: - LayoutSubviews

public struct LayoutSubviews: Equatable, RandomAccessCollection {
    public typealias SubSequence = LayoutSubviews
    public typealias Element = LayoutSubview
    public typealias Index = Int
    public typealias Indices = Range<LayoutSubviews.Index>
    public typealias Iterator = IndexingIterator<LayoutSubviews>

    public var layoutDirection: LayoutDirection
    public var startIndex: Int { subviews.startIndex }
    public var endIndex: Int { subviews.endIndex }

    let subviews: [LayoutSubview]
    init<S>(subviews: S, layoutDirection: LayoutDirection) where S: Sequence, S.Element == Self.Element {
        self.subviews = .init(subviews)
        self.layoutDirection = layoutDirection
    }

    public subscript(index: Int) -> LayoutSubviews.Element {
        subviews[index]
    }

    public subscript(bounds: Range<Int>) -> LayoutSubviews {
        .init(subviews: subviews[bounds], layoutDirection: layoutDirection)
    }

    public subscript<S>(indices: S) -> LayoutSubviews where S: Sequence, S.Element == Int {
        var items: [LayoutSubview] = []
        for i in indices {
            items.append(self.subviews[i])
        }
        return .init(subviews: items, layoutDirection: layoutDirection)
    }
}
