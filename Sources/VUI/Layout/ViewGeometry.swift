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
}

// MARK: - ViewSize

/// The concrete size of a view as resolved by the layout pass.
/// `width`/`height` are computed accessors into `value`.
/// `proposal` stores the proposal that was used to compute this size; needed by the
/// animation system to interpolate between layout frames.
struct ViewSize: Equatable, Sendable {
    var value: CGSize
    var proposal: ProposedViewSize

    var width:  CGFloat { get { value.width  } set { value.width  = newValue } }
    var height: CGFloat { get { value.height } set { value.height = newValue } }

    init(_ value: CGSize, proposal: ProposedViewSize = .unspecified) {
        self.value = value
        self.proposal = proposal
    }
    init(width: CGFloat, height: CGFloat, proposal: ProposedViewSize = .unspecified) {
        self.value = CGSize(width: width, height: height)
        self.proposal = proposal
    }

    static let zero = ViewSize(.zero)

    static func fixed(_ cgSize: CGSize) -> ViewSize {
        ViewSize(cgSize, proposal: ProposedViewSize(cgSize))
    }
}

extension ViewSize: Animatable {
    typealias AnimatableData = CGSize.AnimatableData

    var animatableData: AnimatableData {
        get { value.animatableData }
        set { value.animatableData = newValue }
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
struct ViewTransform: Equatable, Sendable {

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
        /// `inverse == true` means the stored transform is already the inverted form.
        case affineTransform(CGAffineTransform, inverse: Bool)

        /// 3-D projective transform.
        /// `inverse == true` means the stored transform is already the inverted form.
        case projectionTransform(ProjectionTransform, inverse: Bool)

        /// Scroll-container geometry (offset, clip).
        case scrollGeometry(ScrollGeometry, isClipped: Bool)

        /// Named coordinate-space marker (by `AnyHashable` name).
        case coordinateSpaceName(AnyHashable)

        /// Sized named coordinate-space marker.
        case sizedSpace(name: AnyHashable, size: CGSize)

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
    /// Pass `inverse: true` when the transform is already stored in inverted form.
    mutating func appendAffineTransform(_ t: CGAffineTransform, inverse: Bool) {
        _transformItems.append(.affineTransform(t, inverse: inverse))
    }

    /// Appends a 3-D projective transform.
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

    /// Marks the current position as a sized named coordinate space.
    mutating func appendSizedSpace(name: AnyHashable, size: CGSize) {
        _transformItems.append(.sizedSpace(name: name, size: size))
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
        guard case .local = space else { return }
        // Step 1: undo global translation.
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

    // Global position (read-only)

    /// The accumulated global position of this view (the origin in window coordinates).
    var globalPosition: CGPoint { _globalPosition }

    // Private helpers

    private func _applyItem<A: MutableCollection>(
        _ item: Item,
        inverted: Bool,
        to points: inout A
    ) where A.Element == CGPoint {
        switch item {
        case .affineTransform(let t, let isStoredInverse):
            // When inverted==true (global to local) and !isStoredInverse: use t.inverted()
            // When inverted==true  and  isStoredInverse: use t (already inverted stored)
            // When inverted==false and !isStoredInverse: use t
            // When inverted==false and  isStoredInverse: use t.inverted()
            // Summary: effective = (inverted == isStoredInverse) ? t : t.inverted()
            let effective: CGAffineTransform = (inverted == isStoredInverse) ? t : t.inverted()
            for i in points.indices {
                points[i] = points[i].applying(effective)
            }

        case .projectionTransform(let t, let isStoredInverse):
            let effective: ProjectionTransform = (inverted == isStoredInverse) ? t : t.inverted()
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
             .coordinateSpaceName, .sizedSpace:
            // Coordinate-space markers and position items are handled separately
            // (position via _globalPosition; markers are no-ops for point conversion).
            break
        }
    }

    // Identity

    static let identity = ViewTransform()
}

/// The safe-area insets provided to a view by its nearest ancestor container.
/// Conceptually equivalent to `EdgeInsets` but kept as a distinct type so
/// the AG graph can distinguish safe-area changes from general padding changes.
struct SafeAreaInsets: Equatable, Sendable {
    var value: EdgeInsets

    init() { value = EdgeInsets() }
    init(_ insets: EdgeInsets) { value = insets }

    static let zero = SafeAreaInsets()
}
