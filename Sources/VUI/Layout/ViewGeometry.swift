//
//  File: ViewGeometry.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - ViewGeometry

/// Per-child geometry computed by the layout engine during the layout pass.
/// Used as the output type of LayoutEngineBox.childGeometries and LayoutChildGeometry rule.
struct ViewGeometry: Equatable {
    /// Position in parent-local coordinates (top-left corner after anchor resolution).
    var origin: CGPoint

    /// Layout dimensions for alignment guide queries and size access.
    var dimensions: ViewDimensions

    init(origin: CGPoint, dimensions: ViewDimensions) {
        self.origin = origin
        self.dimensions = dimensions
    }

    static var zero: ViewGeometry {
        ViewGeometry(
            origin: .zero,
            dimensions: ViewDimensions(
                guideComputer: .defaultValue,
                size: .zero
            )
        )
    }
}

extension ViewGeometry: Animatable {
    typealias AnimatableData = AnimatablePair<CGPoint.AnimatableData, CGSize.AnimatableData>

    var animatableData: AnimatableData {
        get {
            AnimatablePair(origin.animatableData, dimensions.size.value.animatableData)
        }
        set {
            origin.animatableData = newValue.first
            dimensions.size.value.animatableData = newValue.second
            dimensions.size.proposal = _ProposedSize(dimensions.size.value)
        }
    }
}

// MARK: - ViewSize

/// The concrete size of a view as resolved by the layout pass.
/// `width`/`height` are computed accessors into `value`.
/// `proposal` stores the proposal that was used to compute this size; needed by the
/// animation system to interpolate between layout frames.
struct ViewSize: Equatable, Sendable {
    var value: CGSize
    private var _proposedWidth: CGFloat
    private var _proposedHeight: CGFloat

    var proposal: _ProposedSize {
        get {
            _ProposedSize(
                width: _proposedWidth.isNaN ? nil : _proposedWidth,
                height: _proposedHeight.isNaN ? nil : _proposedHeight
            )
        }
        set {
            _proposedWidth = newValue.width ?? .nan
            _proposedHeight = newValue.height ?? .nan
        }
    }

    var width:  CGFloat { get { value.width  } set { value.width  = newValue } }
    var height: CGFloat { get { value.height } set { value.height = newValue } }

    init(_ value: CGSize, proposal: _ProposedSize = .unspecified) {
        self.value = value
        self._proposedWidth = proposal.width ?? .nan
        self._proposedHeight = proposal.height ?? .nan
    }
    init(width: CGFloat, height: CGFloat, proposal: _ProposedSize = .unspecified) {
        self.init(
            CGSize(width: width, height: height),
            proposal: proposal
        )
    }

    static let zero = ViewSize(.zero, proposal: .zero)

    static func fixed(_ cgSize: CGSize) -> ViewSize {
        ViewSize(cgSize, proposal: _ProposedSize(cgSize))
    }

    static func == (lhs: ViewSize, rhs: ViewSize) -> Bool {
        lhs.value == rhs.value && lhs.proposal == rhs.proposal
    }
}

extension ViewSize: Animatable {
    typealias AnimatableData = CGSize.AnimatableData

    var animatableData: AnimatableData {
        get { value.animatableData }
        set {
            value.animatableData = newValue
            proposal = _ProposedSize(value)
        }
    }
}

/// Minimal geometry descriptor for a scroll view's current scroll state.
/// Used by `ViewTransform.appendScrollGeometry` to embed the scroll offset
/// in the transform chain so that hit-testing correctly maps through scroll containers.
public struct ScrollGeometry: Equatable, Sendable, CustomDebugStringConvertible {
    /// The current scroll offset (content origin offset from the container origin).
    public var contentOffset: CGPoint {
        didSet { updateVisibleRect() }
    }
    public var contentSize:   CGSize
    public var contentInsets: EdgeInsets
    public var containerSize: CGSize {
        didSet { updateVisibleRect() }
    }
    public private(set) var visibleRect: CGRect

    public init(
        contentOffset: CGPoint = .zero,
        contentSize:   CGSize  = .zero,
        contentInsets: EdgeInsets = EdgeInsets(),
        containerSize: CGSize  = .zero
    ) {
        self.init(
            contentOffset: contentOffset,
            contentSize: contentSize,
            contentInsets: contentInsets,
            containerSize: containerSize,
            visibleRect: CGRect(origin: contentOffset, size: containerSize)
        )
    }

    init(
        contentOffset: CGPoint,
        contentSize: CGSize,
        contentInsets: EdgeInsets,
        containerSize: CGSize,
        visibleRect: CGRect
    ) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
        self.visibleRect = visibleRect
    }

    public var bounds: CGRect {
        visibleRect
    }

    public var debugDescription: String {
        "<ScrollGeometry: contentOffset \(contentOffset), " +
        "contentSize \(contentSize), " +
        "contentInsets <top: \(contentInsets.top), " +
        "leading: \(contentInsets.leading), " +
        "bottom: \(contentInsets.bottom), " +
        "trailing: \(contentInsets.trailing)>, " +
        "containerSize \(containerSize), " +
        "visibleRect \(visibleRect)>"
    }

    private mutating func updateVisibleRect() {
        visibleRect = CGRect(origin: contentOffset, size: containerSize)
    }

    static func rootViewTransform(contentOffset: CGPoint, containerSize: CGSize) -> ScrollGeometry {
        ScrollGeometry(
            contentOffset: contentOffset,
            contentSize: CGSize(width: CGFloat.infinity, height: CGFloat.infinity),
            contentInsets: EdgeInsets(),
            containerSize: containerSize,
            visibleRect: CGRect(origin: contentOffset, size: containerSize)
        )
    }

    static func viewTransform(
        contentInsets: EdgeInsets,
        contentSize: CGSize,
        containerSize: CGSize
    ) -> ScrollGeometry {
        let visibleRect = CGRect(
            x: -contentInsets.leading,
            y: -contentInsets.top,
            width: max(containerSize.width + contentInsets.leading + contentInsets.trailing, 0),
            height: max(containerSize.height + contentInsets.top + contentInsets.bottom, 0)
        )
        return ScrollGeometry(
            contentOffset: .zero,
            contentSize: contentSize,
            contentInsets: contentInsets,
            containerSize: containerSize,
            visibleRect: visibleRect
        )
    }

    mutating func applyLayoutDirection(_ layoutDirection: LayoutDirection, contentSize override: CGSize? = nil) {
        guard layoutDirection == .rightToLeft else {
            return
        }
        let previousOffset = contentOffset
        let previousVisibleRect = visibleRect
        let width = override?.width ?? contentSize.width
        let newOffsetX = width - containerSize.width - previousOffset.x
        contentOffset = CGPoint(x: newOffsetX, y: previousOffset.y)
        visibleRect = previousVisibleRect.offsetBy(dx: newOffsetX - previousOffset.x, dy: 0)
    }
}

extension CGSize {
    func inset(by insets: EdgeInsets) -> CGSize {
        CGSize(
            width: max(width - insets.leading - insets.trailing, 0),
            height: max(height - insets.top - insets.bottom, 0)
        )
    }

    func outset(by insets: EdgeInsets) -> CGSize {
        CGSize(
            width: max(width + insets.leading + insets.trailing, 0),
            height: max(height + insets.top + insets.bottom, 0)
        )
    }
}

/// The cumulative coordinate-space transform applied to a view.
///
/// Internally stores two independent layers:
///
/// 1. **`_transformItems`** - ordered sequence of non-translation transforms
///    (affine rotations/scales, projection transforms, scroll offsets, etc.)
///    in local-to-global application order.
///    Appended by `appendAffineTransform`, `appendProjectionTransform`, etc.
///
/// 2. **`_globalPosition`** - the view's accumulated global translation,
///    set (and replaced) by `appendPosition`.  This is always the final step
///    when converting local to global.
///
/// Converting **global to local** (`convertGlobal(to: .local, ...)`) is the
/// canonical hit-test path:
///   1. Subtract `_globalPosition`.
///   2. Apply the inverse of each `_transformItem` in **reverse** order.
///
/// Converting **local to global** (`convertGlobal(from: .local, ...)`) is used
/// to compute a child view's global position from its parent-local offset:
///   1. Apply each `_transformItem` in **forward** order.
///   2. Add `_globalPosition`.
struct ViewTransform: Equatable, CustomStringConvertible, Sendable {

    // Item

    /// One entry in the transform chain.
    enum Item: Equatable, @unchecked Sendable {
        /// View position in global window coordinates.
        /// Set by `appendPosition`; replaces any previous position.
        case position(CGPoint)

        /// Position with display-scale factor (for sub-pixel placement).
        case positionWithScale(CGPoint, CGFloat)

        /// Additional translation in the current local space (e.g. `.offset`).
        case translation(CGSize)

        /// 2-D affine transform (rotation / scale / shear).
        /// `inverse == true` means the stored transform is in local-to-global form.
        case affineTransform(CGAffineTransform, inverse: Bool)

        /// 3-D projective transform.
        /// `inverse == true` means the stored transform is in local-to-global form.
        case projectionTransform(ProjectionTransform, inverse: Bool)

        /// Scroll-container geometry (offset, clip).
        case scrollGeometry(ScrollGeometry, isClipped: Bool)

        /// Named coordinate-space marker (by `AnyHashable` name).
        case coordinateSpaceName(AnyHashable)

        /// Coordinate-space marker (by internal coordinate-space id).
        case coordinateSpaceID(CoordinateSpace.ID)

        /// Sized named coordinate-space marker.
        case sizedSpace(name: AnyHashable, size: CGSize)

        /// Sized coordinate-space marker (by internal coordinate-space id).
        case sizedSpaceID(id: CoordinateSpace.ID, size: CGSize)

        /// Reset the accumulated position to an explicit global point.
        case resetPosition(CGPoint)

        /// Fine-grained position adjustment (e.g. pixel-boundary snapping).
        case positionAdjustment(CGSize)
    }

    // Storage

    /// Non-translation transform items, in local-to-global order.
    private var _transformItems: [Item] = []

    /// Accumulated global position (the final translation in local-to-global order).
    private var _globalPosition: CGPoint = .zero

    // Init

    init() {}

    // Accessors

    var isEmpty: Bool {
        _transformItems.isEmpty && _globalPosition == .zero
    }

    var description: String {
        var components = _transformItems.map { String(describing: $0) }
        if _globalPosition != .zero {
            components.append(
                String(describing: CGSize(
                    width: _globalPosition.x,
                    height: _globalPosition.y
                ))
            )
        }
        return components.joined(separator: "; ")
    }

    // Append / mutate methods

    /// Sets the view's position in global coordinates.
    /// Replaces any previous position; non-position items are preserved.
    mutating func appendPosition(_ position: CGPoint) {
        _globalPosition = position
    }

    /// Sets the view's position with an explicit display-scale multiplier.
    mutating func appendPosition(_ position: CGPoint, scale: CGFloat) {
        _globalPosition = CGPoint(x: position.x * scale, y: position.y * scale)
    }

    /// Appends a translation in the current local coordinate space.
    mutating func appendTranslation(_ size: CGSize) {
        _transformItems.append(.translation(size))
    }

    /// Appends a 2-D affine transform.
    /// Pass `inverse: true` when the transform maps local coordinates to
    /// global coordinates.
    mutating func appendAffineTransform(_ t: CGAffineTransform, inverse: Bool) {
        _transformItems.append(.affineTransform(t, inverse: inverse))
    }

    /// Appends a 3-D projective transform.
    /// Pass `inverse: true` when the transform maps local coordinates to
    /// global coordinates.
    mutating func appendProjectionTransform(_ t: ProjectionTransform, inverse: Bool) {
        _transformItems.append(.projectionTransform(t, inverse: inverse))
    }

    /// Appends a scroll-container geometry descriptor.
    mutating func appendScrollGeometry(_ sg: ScrollGeometry, isClipped: Bool) {
        _transformItems.append(.scrollGeometry(sg, isClipped: isClipped))
    }

    /// Marks the current position in the chain as a named coordinate space.
    mutating func appendCoordinateSpace(name: AnyHashable) {
        _transformItems.append(.coordinateSpaceName(name))
    }

    /// Marks the current position in the chain as an internal coordinate space.
    mutating func appendCoordinateSpace(id: CoordinateSpace.ID) {
        _transformItems.append(.coordinateSpaceID(id))
    }

    /// Marks the current position as a sized named coordinate space.
    mutating func appendSizedSpace(name: AnyHashable, size: CGSize) {
        _transformItems.append(.sizedSpace(name: name, size: size))
    }

    /// Marks the current position as a sized internal coordinate space.
    mutating func appendSizedSpace(id: CoordinateSpace.ID, size: CGSize) {
        _transformItems.append(.sizedSpaceID(id: id, size: size))
    }

    /// Resets the accumulated global position to an explicit value.
    mutating func resetPosition(_ point: CGPoint) {
        _globalPosition = point
        _transformItems.append(.resetPosition(point))
    }

    /// Applies a fine-grained position adjustment (sub-pixel snapping etc.).
    mutating func setPositionAdjustment(_ size: CGSize) {
        _globalPosition.x += size.width
        _globalPosition.y += size.height
        _transformItems.append(.positionAdjustment(size))
    }

    mutating func offsetPosition(by offset: CGSize) {
        _globalPosition.x += offset.width
        _globalPosition.y += offset.height
    }

    // Coordinate conversion

    /// Converts `points` from global window coordinates into the view's local space.
    ///
    /// This is the canonical hit-test path:
    /// 1. Subtract the view's `_globalPosition`.
    /// 2. Apply the inverse of each `_transformItem` in reverse order.
    func convertGlobal<A: MutableCollection>(
        to space: CoordinateSpace,
        points: inout A
    ) where A.Element == CGPoint {
        switch space {
        case .global:
            return
        case .local:
            break
        case .named(let name):
            guard let markerIndex = lastCoordinateSpaceMarkerIndex(matching: name) else {
                return
            }
            for i in points.indices {
                points[i].x -= _globalPosition.x
                points[i].y -= _globalPosition.y
            }
            let suffixStart = _transformItems.index(after: markerIndex)
            for item in _transformItems[suffixStart...].reversed() {
                _applyItem(item, inverted: true, to: &points)
            }
            return
        }
        for i in points.indices {
            points[i].x -= _globalPosition.x
            points[i].y -= _globalPosition.y
        }
        // Step 2: undo non-translation items in reverse.
        for item in _transformItems.reversed() {
            _applyItem(item, inverted: true, to: &points)
        }
    }

    /// Converts `points` from the view's local space into global window coordinates.
    ///
    /// Used to compute a child view's global position from its parent-local offset:
    /// 1. Apply each `_transformItem` in forward order.
    /// 2. Add `_globalPosition`.
    func convertGlobal<A: MutableCollection>(
        from space: CoordinateSpace,
        points: inout A
    ) where A.Element == CGPoint {
        guard case .local = space else { return }
        // Step 1: apply non-translation items forward.
        for item in _transformItems {
            _applyItem(item, inverted: false, to: &points)
        }
        // Step 2: apply global translation.
        for i in points.indices {
            points[i].x += _globalPosition.x
            points[i].y += _globalPosition.y
        }
    }

    /// Converts local points into the nearest matching internal coordinate
    /// space marker carried by this transform. If the marker is absent, fall
    /// back to the existing local-to-global conversion.
    func convert<A: MutableCollection>(
        to space: ScrollCoordinateSpace,
        points: inout A
    ) where A.Element == CGPoint {
        guard let markerIndex = lastCoordinateSpaceMarkerIndex(matching: space.id) else {
            convertGlobal(from: .local, points: &points)
            return
        }

        let suffixStart = _transformItems.index(after: markerIndex)
        for item in _transformItems[suffixStart...] {
            _applyItem(item, inverted: false, to: &points)
        }
    }

    // Item iteration.

    /// Iterates all transform items in forward or reverse order.
    /// Forward order: `[_transformItems..., .position(_globalPosition)]`
    /// Reverse order: `[.position(_globalPosition), ..._transformItems.reversed()]`
    func forEach(inverted: Bool, _ body: (Item, inout Bool) -> ()) {
        var stop = false
        if inverted {
            body(.position(_globalPosition), &stop)
            if !stop {
                for item in _transformItems.reversed() {
                    body(item, &stop)
                    if stop { break }
                }
            }
        } else {
            for item in _transformItems {
                body(item, &stop)
                if stop { return }
            }
            body(.position(_globalPosition), &stop)
        }
    }

    var containingScrollGeometry: ScrollGeometry? {
        firstScrollGeometry(inverted: false)
    }

    var nearestScrollGeometry: ScrollGeometry? {
        firstScrollGeometry(inverted: true)
    }

    var scrollCoordinateSpaces: [ScrollCoordinateSpace] {
        _transformItems.compactMap { item in
            switch item {
            case .coordinateSpaceID(let id):
                return ScrollCoordinateSpace(id: id)
            case .sizedSpaceID(let id, _):
                return ScrollCoordinateSpace(id: id)
            default:
                return nil
            }
        }
    }

    var scrollCoordinateSpaceSizes: [(ScrollCoordinateSpace, CGSize)] {
        _transformItems.compactMap { item in
            guard case let .sizedSpaceID(id, size) = item,
                  let space = ScrollCoordinateSpace(id: id) else {
                return nil
            }
            return (space, size)
        }
    }

    var translations: [CGSize] {
        _transformItems.compactMap { item in
            guard case let .translation(value) = item else {
                return nil
            }
            return value
        }
    }

    func size(ofNamedCoordinateSpace name: AnyHashable) -> CGSize? {
        for item in _transformItems.reversed() {
            if case let .sizedSpace(candidate, size) = item,
               candidate == name {
                return size
            }
        }
        return nil
    }

    // Global position (read-only)

    /// The accumulated global position of this view (the origin in window coordinates).
    var globalPosition: CGPoint { _globalPosition }

    // Private helpers

    private func firstScrollGeometry(inverted: Bool) -> ScrollGeometry? {
        var geometry: ScrollGeometry?
        forEach(inverted: inverted) { item, stop in
            guard case let .scrollGeometry(value, _) = item else { return }
            geometry = value
            stop = true
        }
        return geometry
    }

    private func lastCoordinateSpaceMarkerIndex(matching id: CoordinateSpace.ID) -> [Item].Index? {
        for index in _transformItems.indices.reversed() {
            switch _transformItems[index] {
            case .coordinateSpaceID(let candidate),
                 .sizedSpaceID(let candidate, _):
                if candidate == id {
                    return index
                }
            default:
                continue
            }
        }
        return nil
    }

    private func lastCoordinateSpaceMarkerIndex(matching name: AnyHashable) -> [Item].Index? {
        for index in _transformItems.indices.reversed() {
            switch _transformItems[index] {
            case .coordinateSpaceName(let candidate),
                 .sizedSpace(let candidate, _):
                if candidate == name {
                    return index
                }
            default:
                continue
            }
        }
        return nil
    }

    private func _applyItem<A: MutableCollection>(
        _ item: Item,
        inverted: Bool,
        to points: inout A
    ) where A.Element == CGPoint {
        switch item {
        case .affineTransform(let t, let isLocalToGlobal):
            let effective: CGAffineTransform = (inverted == isLocalToGlobal)
                ? t.inverted()
                : t
            for i in points.indices {
                points[i] = points[i].applying(effective)
            }

        case .projectionTransform(let t, let isLocalToGlobal):
            let effective: ProjectionTransform = (inverted == isLocalToGlobal)
                ? t.inverted()
                : t
            for i in points.indices {
                points[i] = points[i].applying(effective)
            }

        case .translation(let sz):
            if inverted {
                for i in points.indices {
                    points[i].x -= sz.width
                    points[i].y -= sz.height
                }
            } else {
                for i in points.indices {
                    points[i].x += sz.width
                    points[i].y += sz.height
                }
            }

        case .scrollGeometry(let sg, _):
            // The content is shifted by contentOffset; to go global to local, subtract it.
            let dx = sg.contentOffset.x
            let dy = sg.contentOffset.y
            if inverted {
                for i in points.indices { points[i].x -= dx; points[i].y -= dy }
            } else {
                for i in points.indices { points[i].x += dx; points[i].y += dy }
            }

        case .positionAdjustment(let sz):
            if inverted {
                for i in points.indices { points[i].x -= sz.width; points[i].y -= sz.height }
            } else {
                for i in points.indices { points[i].x += sz.width; points[i].y += sz.height }
            }

        case .position, .positionWithScale, .resetPosition,
             .coordinateSpaceName, .coordinateSpaceID,
             .sizedSpace, .sizedSpaceID:
            // Coordinate-space markers and position items are handled separately
            // (position via _globalPosition; markers are no-ops for point conversion).
            break
        }
    }

    // Identity

    static let identity = ViewTransform()
}

extension CGRect {
    func converted(to space: ScrollCoordinateSpace, using transform: ViewTransform) -> CGRect {
        var points = [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: minX, y: maxY),
        ]
        transform.convert(to: space, points: &points)
        return CGRect(cornerPoints: points)
    }

    init(cornerPoints points: [CGPoint]) {
        guard let first = points.first else {
            self = .null
            return
        }

        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }
        self = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension ScrollGeometry {
    /// Projects the visible scroll window onto one axis for overlap checks.
    func outsetOffsetAndSize(axis: Axis) -> (offset: CGFloat, size: CGFloat) {
        switch axis {
        case .horizontal:
            return (visibleRect.minX, visibleRect.width)
        case .vertical:
            return (visibleRect.minY, visibleRect.height)
        }
    }

    /// Expands an accessibility viewport toward the supplied view-size limit.
    mutating func outsetForAX(limit: CGSize) {
        outsetOffsetAndSize(axis: .horizontal, limit: limit)
        outsetOffsetAndSize(axis: .vertical, limit: limit)
    }

    private mutating func outsetOffsetAndSize(axis: Axis, limit: CGSize) {
        let containerLength: CGFloat
        let limitLength: CGFloat
        let offset: CGFloat
        switch axis {
        case .horizontal:
            containerLength = containerSize.width
            limitLength = limit.width
            offset = contentOffset.x
        case .vertical:
            containerLength = containerSize.height
            limitLength = limit.height
            offset = contentOffset.y
        }
        guard containerLength < limitLength else {
            return
        }

        // Pull the window backward by at most one current container length,
        // then grow it without exceeding the extent reachable from that shift.
        let newOffset = min(max(offset - containerLength, 0), offset)
        let addedLength = containerLength + offset - newOffset
        let newContainerLength = min(
            max(limitLength - offset, addedLength),
            containerLength + addedLength
        )

        var contentOffset = contentOffset
        var containerSize = containerSize
        var visibleRect = visibleRect
        switch axis {
        case .horizontal:
            contentOffset.x = newOffset
            containerSize.width = newContainerLength
            visibleRect.origin.x += newOffset - offset
            visibleRect.size.width += newContainerLength - containerLength
        case .vertical:
            contentOffset.y = newOffset
            containerSize.height = newContainerLength
            visibleRect.origin.y += newOffset - offset
            visibleRect.size.height += newContainerLength - containerLength
        }

        // Offset, container extent, and the explicit visible rectangle form one
        // correlated scroll state. Rebuild them together so didSet observers do
        // not replace the adjusted visible rectangle with the default bounds.
        self = ScrollGeometry(
            contentOffset: contentOffset,
            contentSize: contentSize,
            contentInsets: contentInsets,
            containerSize: containerSize,
            visibleRect: visibleRect
        )
    }
}

struct ScrollViewContentTransformProvider: Rule {
    typealias Value = ViewTransform

    var transform: Attribute<ViewTransform>
    var position: Attribute<CGPoint>
    var safeAreaPosition: Attribute<CGPoint>
    var geometry: Attribute<ScrollGeometry>
    var axes: Attribute<Axis.Set>
    var isClipped: Bool

    init(
        transform: Attribute<ViewTransform>,
        position: Attribute<CGPoint>,
        safeAreaPosition: Attribute<CGPoint>,
        geometry: Attribute<ScrollGeometry>,
        axes: Attribute<Axis.Set>,
        isClipped: Bool = true
    ) {
        self.transform = transform
        self.position = position
        self.safeAreaPosition = safeAreaPosition
        self.geometry = geometry
        self.axes = axes
        self.isClipped = isClipped
    }

    var value: ViewTransform {
        var value = transform.value
        value.resetPosition(position.value)
        let scrollGeometry = geometry.value
        value.appendScrollGeometry(
            ScrollGeometry.rootViewTransform(
                contentOffset: scrollGeometry.contentOffset,
                containerSize: scrollGeometry.containerSize
            ),
            isClipped: true
        )
        value.appendScrollGeometry(
            ScrollGeometry.viewTransform(
                contentInsets: scrollGeometry.contentInsets,
                contentSize: scrollGeometry.contentSize,
                containerSize: scrollGeometry.containerSize
            ),
            isClipped: isClipped
        )
        value.appendSizedSpace(id: ScrollCoordinateSpace.all.id, size: scrollGeometry.containerSize)
        let axes = axes.value
        if axes.contains(.horizontal) {
            value.appendSizedSpace(id: ScrollCoordinateSpace.horizontal.id, size: scrollGeometry.containerSize)
        }
        if axes.contains(.vertical) {
            value.appendSizedSpace(id: ScrollCoordinateSpace.vertical.id, size: scrollGeometry.containerSize)
        }
        value.appendTranslation(CGSize(
            width: scrollGeometry.contentOffset.x,
            height: scrollGeometry.contentOffset.y
        ))
        value.appendSizedSpace(id: ScrollCoordinateSpace.content.id, size: scrollGeometry.contentSize)
        if _SemanticFeature<Semantics_v6>.isEnabled {
            let position = safeAreaPosition.value
            value.appendTranslation(CGSize(width: position.x, height: position.y))
            value.appendSizedSpace(
                id: ScrollCoordinateSpace.safeArea.id,
                size: scrollGeometry.containerSize.outset(by: scrollGeometry.contentInsets)
            )
            value.appendTranslation(CGSize(width: -position.x, height: -position.y))
        }
        return value
    }
}

public struct RectangleCornerInsets: Hashable, Sendable {
    public var topLeading: CGSize
    public var topTrailing: CGSize
    public var bottomLeading: CGSize
    public var bottomTrailing: CGSize

    public init() {
        self.topLeading = .zero
        self.topTrailing = .zero
        self.bottomLeading = .zero
        self.bottomTrailing = .zero
    }

    public init(
        topLeading: CGSize,
        topTrailing: CGSize,
        bottomLeading: CGSize,
        bottomTrailing: CGSize
    ) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }
}

struct AbsoluteRectangleCornerInsets: Hashable, Sendable {
    var topLeft: CGSize
    var topRight: CGSize
    var bottomLeft: CGSize
    var bottomRight: CGSize

    init() {
        self.topLeft = .zero
        self.topRight = .zero
        self.bottomLeft = .zero
        self.bottomRight = .zero
    }

    init(
        topLeft: CGSize,
        topRight: CGSize,
        bottomLeft: CGSize,
        bottomRight: CGSize
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    init(_ insets: RectangleCornerInsets, layoutDirection: LayoutDirection = .leftToRight) {
        switch layoutDirection {
        case .leftToRight:
            self.init(
                topLeft: insets.topLeading,
                topRight: insets.topTrailing,
                bottomLeft: insets.bottomLeading,
                bottomRight: insets.bottomTrailing
            )
        case .rightToLeft:
            self.init(
                topLeft: insets.topTrailing,
                topRight: insets.topLeading,
                bottomLeft: insets.bottomTrailing,
                bottomRight: insets.bottomLeading
            )
        }
    }
}

public struct SafeAreaRegions: OptionSet, Sendable {
    public let rawValue: UInt

    @inlinable public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let container = SafeAreaRegions(rawValue: 1)
    public static let keyboard = SafeAreaRegions(rawValue: 2)
    public static let all = SafeAreaRegions(rawValue: UInt.max)
}

struct SafeAreaInsets: Equatable, Sendable {
    struct Element: Equatable, Sendable {
        var regions: SafeAreaRegions
        var insets: EdgeInsets
        var cornerInsets: AbsoluteRectangleCornerInsets?

        init(
            regions: SafeAreaRegions,
            insets: EdgeInsets,
            cornerInsets: AbsoluteRectangleCornerInsets?
        ) {
            self.regions = regions
            self.insets = insets
            self.cornerInsets = cornerInsets
        }
    }

    indirect enum OptionalValue: Equatable, Sendable {
        case empty
        case insets(SafeAreaInsets)
    }

    var space: CoordinateSpace.ID
    var elements: [Element]
    var next: OptionalValue

    var value: EdgeInsets {
        elements.reduce(next.value) { partial, element in
            partial.adding(element.insets)
        }
    }

    init() {
        self.init(space: CoordinateSpace.ID(rawValue: 0), elements: [])
    }

    init(_ insets: EdgeInsets) {
        self.init(
            space: CoordinateSpace.ID(rawValue: 0),
            elements: [Element(regions: .container, insets: insets, cornerInsets: nil)]
        )
    }

    init(
        space: CoordinateSpace.ID,
        elements: [Element],
        next: OptionalValue = .empty
    ) {
        self.space = space
        self.elements = elements
        self.next = next
    }

    static let zero = SafeAreaInsets()
}

private extension SafeAreaInsets.OptionalValue {
    var value: EdgeInsets {
        switch self {
        case .empty:
            return EdgeInsets()
        case .insets(let insets):
            return insets.value
        }
    }
}
