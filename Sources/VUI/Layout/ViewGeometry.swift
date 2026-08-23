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
struct ViewGeometry: Equatable, _AGTypeDescriptorEquatable {
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
struct ViewSize: Equatable, Sendable, _AGTypeDescriptorEquatable {
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
        didSet {
            visibleRect.origin.x += contentOffset.x - oldValue.x
            visibleRect.origin.y += contentOffset.y - oldValue.y
        }
    }
    public var contentSize:   CGSize
    public var contentInsets: EdgeInsets
    public var containerSize: CGSize {
        didSet {
            visibleRect.size.width += containerSize.width - oldValue.width
            visibleRect.size.height += containerSize.height - oldValue.height
        }
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

/// Distinguishes internal coordinate-space IDs from user-provided names while
/// keeping the public `CoordinateSpace` surface unchanged.
private struct CoordinateSpaceIDStorage: Hashable, Sendable {
    var id: CoordinateSpace.ID
}

private extension CoordinateSpace {
    static func internalID(_ id: CoordinateSpace.ID) -> CoordinateSpace {
        .named(AnyHashable(CoordinateSpaceIDStorage(id: id)))
    }

    var internalID: CoordinateSpace.ID? {
        guard case let .named(name) = self,
              let storage = name.base as? CoordinateSpaceIDStorage else {
            return nil
        }
        return storage.id
    }
}

/// One immutable entry in a transform-local coordinate-space lookup chain.
/// Copies of `ViewTransform` may share an existing tail and prepend new entries.
private final class CoordinateSpaceNode: @unchecked Sendable {
    let next: CoordinateSpaceNode?
    let space: CoordinateSpace
    let depth: Int

    init(next: CoordinateSpaceNode?, space: CoordinateSpace, depth: Int) {
        self.next = next
        self.space = space
        self.depth = depth
    }
}

/// The cumulative coordinate-space transform applied to a view.
///
/// Internally stores three coordinated layers:
///
/// 1. **`_transformItems`** - ordered transform elements in global-to-local
///    traversal order. Appending a non-folded element first commits the current
///    folded translation at that exact position in the sequence.
///
/// 2. **Coordinate-space lookup** - an immutable transform-local chain that
///    assigns stable tags to named and internal coordinate spaces. Items carry
///    only those tags; the lookup is derived state and is not part of equality.
///
/// 3. **Position storage** - a position adjustment plus a folded
///    global-to-local translation. Appending a position replaces the previous
///    adjustment by folding their delta into the translation. Resetting a
///    position performs the same fold and clears the adjustment, allowing
///    descendants to append positions relative to that boundary.
///
/// Converting **global to local** (`convertGlobal(to: .local, ...)`) is the
/// canonical hit-test path:
///   1. Traverse committed elements in forward order.
///   2. Apply the remaining folded translation last.
///
/// Converting **local to global** (`convertGlobal(from: .local, ...)`) is used
/// to compute a child view's global position from its parent-local offset:
///   1. Apply the inverse folded translation first.
///   2. Traverse committed elements in reverse, inverted order.
struct ViewTransform: Equatable, CustomStringConvertible, Sendable,
    _AGTypeDescriptorEquatable {

    // Item

    /// One entry in the transform chain.
    enum Item: Equatable, @unchecked Sendable {
        /// Additional translation in the current local space (e.g. `.offset`).
        case translation(CGSize)

        /// 2-D affine transform (rotation / scale / shear).
        /// `inverse == true` means the stored transform is in local-to-global form.
        case affineTransform(CGAffineTransform, inverse: Bool)

        /// 3-D projective transform.
        /// `inverse == true` means the stored transform is in local-to-global form.
        case projectionTransform(ProjectionTransform, inverse: Bool)

        /// Coordinate-space marker resolved through the transform-local chain.
        case coordinateSpace(CoordinateSpaceTag)

        /// Sized coordinate-space marker resolved through the same tag chain.
        case sizedSpace(CoordinateSpaceTag, size: CGSize)

        /// Scroll-container geometry (offset, clip).
        case scrollGeometry(ScrollGeometry, isClipped: Bool)
    }

    struct UnsafeBuffer: Sendable {
        fileprivate var items: [Item] = []
        fileprivate var count = 0

        init() {}

        mutating func appendTranslation(_ size: CGSize) {
            guard size != .zero else { return }
            append(.translation(size))
        }

        mutating func appendAffineTransform(
            _ transform: CGAffineTransform,
            inverse: Bool
        ) {
            if transform.a == 1,
               transform.b == 0,
               transform.c == 0,
               transform.d == 1 {
                appendTranslation(CGSize(
                    width: inverse ? -transform.tx : transform.tx,
                    height: inverse ? -transform.ty : transform.ty
                ))
            } else {
                append(.affineTransform(transform, inverse: inverse))
            }
        }

        mutating func appendProjectionTransform(
            _ transform: ProjectionTransform,
            inverse: Bool
        ) {
            if transform.isAffine {
                appendAffineTransform(
                    CGAffineTransform(
                        a: transform.m11,
                        b: transform.m12,
                        c: transform.m21,
                        d: transform.m22,
                        tx: transform.m31,
                        ty: transform.m32
                    ),
                    inverse: inverse
                )
            } else {
                append(.projectionTransform(transform, inverse: inverse))
            }
        }

        mutating func appendCoordinateSpace(
            id: CoordinateSpace.ID,
            transform: inout ViewTransform
        ) {
            append(.coordinateSpace(
                transform.resolveCoordinateSpaceTag(.internalID(id))
            ))
        }

        mutating func appendSizedSpace(
            id: CoordinateSpace.ID,
            size: CGSize,
            transform: inout ViewTransform
        ) {
            append(.sizedSpace(
                transform.resolveCoordinateSpaceTag(.internalID(id)),
                size: size
            ))
        }

        mutating func appendScrollGeometry(
            _ geometry: ScrollGeometry,
            isClipped: Bool
        ) {
            append(.scrollGeometry(geometry, isClipped: isClipped))
        }

        private mutating func append(_ item: Item) {
            items.append(item)
            count += 1
        }
    }

    // Storage

    /// Committed transform items, in global-to-local traversal order.
    private var _transformItems: [Item] = []

    /// Derived mapping from coordinate-space values to transform-local tags.
    private var _coordinateSpaceNode: CoordinateSpaceNode?

    /// Most recently appended position used to replace absolute placement.
    private var _positionAdjustment: CGSize = .zero

    /// Folded translation applied when converting global coordinates to local.
    private var _positionTranslation: CGSize = .zero

    // Init

    init() {}

    // Accessors

    var isEmpty: Bool {
        _transformItems.isEmpty &&
            _positionTranslation == .zero
    }

    var description: String {
        var components = _transformItems.map { String(describing: $0) }
        if _positionTranslation != .zero {
            components.append(String(describing: _positionTranslation))
        }
        return components.joined(separator: "; ")
    }

    static func == (lhs: ViewTransform, rhs: ViewTransform) -> Bool {
        lhs._transformItems == rhs._transformItems &&
            lhs._positionAdjustment == rhs._positionAdjustment &&
            lhs._positionTranslation == rhs._positionTranslation
    }

    // Append / mutate methods

    /// Replaces the prior position adjustment while preserving folded ancestry.
    mutating func appendPosition(_ position: CGPoint) {
        _positionTranslation.width -= position.x - _positionAdjustment.width
        _positionTranslation.height -= position.y - _positionAdjustment.height
        _positionAdjustment = CGSize(width: position.x, height: position.y)
    }

    /// Sets the view's position with an explicit display-scale multiplier.
    mutating func appendPosition(_ position: CGPoint, scale: CGFloat) {
        _positionTranslation.width -= position.x - _positionAdjustment.width
        _positionTranslation.height -= position.y - _positionAdjustment.height
        _positionAdjustment = CGSize(
            width: position.x * scale,
            height: position.y * scale
        )
    }

    /// Appends a translation in the current local coordinate space.
    mutating func appendTranslation(_ size: CGSize) {
        _positionTranslation.width += size.width
        _positionTranslation.height += size.height
    }

    mutating func append(movingContentsOf buffer: inout UnsafeBuffer) {
        commitPositionTranslation()
        _transformItems.append(contentsOf: buffer.items)
        buffer.items.removeAll(keepingCapacity: false)
        buffer.count = 0
    }

    /// Appends a 2-D affine transform.
    /// Pass `inverse: true` when the transform maps local coordinates to
    /// global coordinates.
    mutating func appendAffineTransform(_ t: CGAffineTransform, inverse: Bool) {
        if t.a == 1, t.b == 0, t.c == 0, t.d == 1 {
            appendTranslation(CGSize(
                width: inverse ? -t.tx : t.tx,
                height: inverse ? -t.ty : t.ty
            ))
        } else {
            commitPositionTranslation()
            _transformItems.append(.affineTransform(t, inverse: inverse))
        }
    }

    /// Appends a 3-D projective transform.
    /// Pass `inverse: true` when the transform maps local coordinates to
    /// global coordinates.
    mutating func appendProjectionTransform(_ t: ProjectionTransform, inverse: Bool) {
        if t.isAffine {
            appendAffineTransform(
                CGAffineTransform(
                    a: t.m11,
                    b: t.m12,
                    c: t.m21,
                    d: t.m22,
                    tx: t.m31,
                    ty: t.m32
                ),
                inverse: inverse
            )
        } else {
            commitPositionTranslation()
            _transformItems.append(.projectionTransform(t, inverse: inverse))
        }
    }

    /// Appends a scroll-container geometry descriptor.
    mutating func appendScrollGeometry(_ sg: ScrollGeometry, isClipped: Bool) {
        commitPositionTranslation()
        _transformItems.append(.scrollGeometry(sg, isClipped: isClipped))
    }

    /// Marks the current position in the chain as a named coordinate space.
    mutating func appendCoordinateSpace(name: AnyHashable) {
        commitPositionTranslation()
        _transformItems.append(.coordinateSpace(
            resolveCoordinateSpaceTag(.named(name))
        ))
    }

    /// Marks the current position in the chain as an internal coordinate space.
    mutating func appendCoordinateSpace(id: CoordinateSpace.ID) {
        commitPositionTranslation()
        _transformItems.append(.coordinateSpace(
            resolveCoordinateSpaceTag(.internalID(id))
        ))
    }

    /// Marks the current position as a sized named coordinate space.
    mutating func appendSizedSpace(name: AnyHashable, size: CGSize) {
        commitPositionTranslation()
        _transformItems.append(.sizedSpace(
            resolveCoordinateSpaceTag(.named(name)),
            size: size
        ))
    }

    /// Marks the current position as a sized internal coordinate space.
    mutating func appendSizedSpace(id: CoordinateSpace.ID, size: CGSize) {
        commitPositionTranslation()
        _transformItems.append(.sizedSpace(
            resolveCoordinateSpaceTag(.internalID(id)),
            size: size
        ))
    }

    /// Folds a coordinate-boundary position and clears the position adjustment.
    mutating func resetPosition(_ point: CGPoint) {
        _positionTranslation.width -= point.x - _positionAdjustment.width
        _positionTranslation.height -= point.y - _positionAdjustment.height
        _positionAdjustment = .zero
    }

    var positionAdjustment: CGSize { _positionAdjustment }

    /// Replaces the position adjustment used by the next append or reset.
    mutating func setPositionAdjustment(_ size: CGSize) {
        _positionAdjustment = size
    }

    // Coordinate conversion

    /// Converts `points` from global window coordinates into the view's local space.
    ///
    /// This is the canonical hit-test path. Stored items are already ordered
    /// from the global space toward the descendant local space.
    func convertGlobal<A: MutableCollection>(
        to space: CoordinateSpace,
        points: inout A
    ) where A.Element == CGPoint {
        guard let tag = coordinateSpaceTag(space) else {
            return
        }
        if tag == .global {
            return
        }
        if tag == .local {
            applyGlobalToLocal(points: &points)
            return
        }
        guard let markerIndex = lastCoordinateSpaceMarkerIndex(matching: tag) else {
            return
        }
        for item in _transformItems[...markerIndex] {
            _applyTraversalItem(item, to: &points)
        }
    }

    /// Converts `points` from the view's local space into global window coordinates.
    ///
    /// Used to compute a child view's global position from its parent-local offset.
    func convertGlobal<A: MutableCollection>(
        from space: CoordinateSpace,
        points: inout A
    ) where A.Element == CGPoint {
        guard case .local = space else { return }
        applyLocalToGlobal(points: &points)
    }

    /// Converts local points into the nearest matching internal coordinate
    /// space marker carried by this transform. If the marker is absent, fall
    /// back to the existing local-to-global conversion.
    func convert<A: MutableCollection>(
        to space: ScrollCoordinateSpace,
        points: inout A
    ) where A.Element == CGPoint {
        guard let tag = coordinateSpaceTag(.internalID(space.id)),
              let markerIndex = lastCoordinateSpaceMarkerIndex(matching: tag) else {
            convertGlobal(from: .local, points: &points)
            return
        }

        if _positionTranslation != .zero {
            _applyTraversalItem(
                .translation(CGSize(
                    width: -_positionTranslation.width,
                    height: -_positionTranslation.height
                )),
                to: &points
            )
        }
        let suffixStart = _transformItems.index(after: markerIndex)
        for item in _transformItems[suffixStart...].reversed() {
            _applyTraversalItem(iterationItem(item, inverted: true), to: &points)
        }
    }

    // Item iteration.

    /// Iterates all transform items in forward or reverse order.
    /// Forward order ends with the folded global-to-local translation.
    /// Reverse order starts with its inverse and inverts each stored item.
    func forEach(inverted: Bool, _ body: (Item, inout Bool) -> ()) {
        guard !_transformItems.isEmpty else { return }
        var stop = false
        if inverted {
            if _positionTranslation != .zero {
                body(
                    .translation(
                        CGSize(
                            width: -_positionTranslation.width,
                            height: -_positionTranslation.height
                        )
                    ),
                    &stop
                )
            }
            if !stop {
                for item in _transformItems.reversed() {
                    body(iterationItem(item, inverted: true), &stop)
                    if stop { break }
                }
            }
        } else {
            for item in _transformItems {
                body(item, &stop)
                if stop { return }
            }
            if _positionTranslation != .zero {
                body(.translation(_positionTranslation), &stop)
            }
        }
    }

    var containingScrollGeometry: ScrollGeometry? {
        resolvedScrollGeometry(allowUnclipped: false)
    }

    var nearestScrollGeometry: ScrollGeometry? {
        resolvedScrollGeometry(allowUnclipped: true)
    }

    var scrollCoordinateSpaces: [ScrollCoordinateSpace] {
        _transformItems.compactMap { item in
            let tag: CoordinateSpaceTag
            switch item {
            case .coordinateSpace(let value), .sizedSpace(let value, _):
                tag = value
            default:
                return nil
            }
            guard let id = coordinateSpace(for: tag)?.internalID else {
                return nil
            }
            return ScrollCoordinateSpace(id: id)
        }
    }

    var scrollCoordinateSpaceSizes: [(ScrollCoordinateSpace, CGSize)] {
        _transformItems.compactMap { item in
            guard case let .sizedSpace(tag, size) = item,
                  let id = coordinateSpace(for: tag)?.internalID,
                  let space = ScrollCoordinateSpace(id: id) else {
                return nil
            }
            return (space, size)
        }
    }

    var translations: [CGSize] {
        var values: [CGSize] = _transformItems.compactMap { item in
            guard case let .translation(value) = item else {
                return nil
            }
            return value
        }
        if !_transformItems.isEmpty, _positionTranslation != .zero {
            values.append(_positionTranslation)
        }
        return values
    }

    func size(ofNamedCoordinateSpace name: AnyHashable) -> CGSize? {
        guard let tag = coordinateSpaceTag(.named(name)) else {
            return nil
        }
        for item in _transformItems.reversed() {
            if case let .sizedSpace(candidate, size) = item,
               candidate == tag {
                return size
            }
        }
        return nil
    }

    // Global position (read-only)

    /// The accumulated global position of this view (the origin in window coordinates).
    var globalPosition: CGPoint {
        CGPoint(
            x: -_positionTranslation.width,
            y: -_positionTranslation.height
        )
    }

    // Private helpers

    private mutating func commitPositionTranslation() {
        guard _positionTranslation != .zero else { return }
        _transformItems.append(.translation(_positionTranslation))
        _positionTranslation = .zero
    }

    private func applyGlobalToLocal<A: MutableCollection>(
        points: inout A
    ) where A.Element == CGPoint {
        if _transformItems.isEmpty {
            if _positionTranslation != .zero {
                _applyTraversalItem(.translation(_positionTranslation), to: &points)
            }
            return
        }
        forEach(inverted: false) { item, _ in
            _applyTraversalItem(item, to: &points)
        }
    }

    private func applyLocalToGlobal<A: MutableCollection>(
        points: inout A
    ) where A.Element == CGPoint {
        if _transformItems.isEmpty {
            if _positionTranslation != .zero {
                _applyTraversalItem(
                    .translation(CGSize(
                        width: -_positionTranslation.width,
                        height: -_positionTranslation.height
                    )),
                    to: &points
                )
            }
            return
        }
        forEach(inverted: true) { item, _ in
            _applyTraversalItem(item, to: &points)
        }
    }

    private func resolvedScrollGeometry(allowUnclipped: Bool) -> ScrollGeometry? {
        var geometry: ScrollGeometry?
        forEach(inverted: false) { item, _ in
            item.apply(to: &geometry, allowUnclipped: allowUnclipped)
        }
        return geometry
    }

    private func iterationItem(_ item: Item, inverted: Bool) -> Item {
        guard inverted else { return item }
        switch item {
        case .translation(let size):
            return .translation(
                CGSize(width: -size.width, height: -size.height)
            )
        case .affineTransform(let transform, let inverse):
            return .affineTransform(transform, inverse: !inverse)
        case .projectionTransform(let transform, let inverse):
            return .projectionTransform(transform, inverse: !inverse)
        case .scrollGeometry,
             .coordinateSpace,
             .sizedSpace:
            return item
        }
    }

    private func coordinateSpaceTag(
        _ space: CoordinateSpace
    ) -> CoordinateSpaceTag? {
        switch space {
        case .global:
            return .global
        case .local:
            return .local
        case .named:
            var node = _coordinateSpaceNode
            while let current = node {
                if current.space == space {
                    return CoordinateSpaceTag(base: current.depth)
                }
                node = current.next
            }
            return nil
        }
    }

    private mutating func resolveCoordinateSpaceTag(
        _ space: CoordinateSpace
    ) -> CoordinateSpaceTag {
        if let tag = coordinateSpaceTag(space) {
            return tag
        }
        let depth = (_coordinateSpaceNode?.depth ?? 0) + 1
        _coordinateSpaceNode = CoordinateSpaceNode(
            next: _coordinateSpaceNode,
            space: space,
            depth: depth
        )
        return CoordinateSpaceTag(base: depth)
    }

    private func coordinateSpace(
        for tag: CoordinateSpaceTag
    ) -> CoordinateSpace? {
        if tag == .global {
            return .global
        }
        if tag == .local {
            return .local
        }
        var node = _coordinateSpaceNode
        while let current = node {
            if current.depth == tag.base {
                return current.space
            }
            node = current.next
        }
        return nil
    }

    private func lastCoordinateSpaceMarkerIndex(
        matching tag: CoordinateSpaceTag
    ) -> [Item].Index? {
        for index in _transformItems.indices.reversed() {
            switch _transformItems[index] {
            case .coordinateSpace(let candidate),
                 .sizedSpace(let candidate, _):
                if candidate == tag {
                    return index
                }
            default:
                continue
            }
        }
        return nil
    }

    private func _applyTraversalItem<A: MutableCollection>(
        _ item: Item,
        to points: inout A
    ) where A.Element == CGPoint {
        switch item {
        case .affineTransform(let t, let isLocalToGlobal):
            let effective = isLocalToGlobal ? t.inverted() : t
            for i in points.indices {
                points[i] = points[i].applying(effective)
            }

        case .projectionTransform(let t, let isLocalToGlobal):
            let effective = isLocalToGlobal ? t.inverted() : t
            for i in points.indices {
                points[i] = points[i].applying(effective)
            }

        case .translation(let sz):
            for i in points.indices {
                points[i].x += sz.width
                points[i].y += sz.height
            }

        case .scrollGeometry,
             .coordinateSpace,
             .sizedSpace:
            // Geometry and coordinate-space items carry traversal metadata.
            break
        }
    }

    // Identity

    static let identity = ViewTransform()
}

private extension ViewTransform.Item {
    func apply(to geometry: inout ScrollGeometry?, allowUnclipped: Bool) {
        switch self {
        case let .translation(offset):
            geometry?.contentOffset.x += offset.width
            geometry?.contentOffset.y += offset.height

        case let .affineTransform(transform, inverse):
            let preservesAxisAlignment =
                (transform.b == 0 && transform.c == 0) ||
                (transform.a == 0 && transform.d == 0)
            guard preservesAxisAlignment else {
                geometry = nil
                return
            }
            guard var geometryValue = geometry else {
                return
            }
            let effectiveTransform = inverse ? transform.inverted() : transform
            geometryValue.contentOffset = geometryValue.contentOffset.applying(effectiveTransform)
            geometryValue.containerSize = geometryValue.containerSize.applying(effectiveTransform)
            geometry = geometryValue

        case .projectionTransform:
            geometry = nil

        case let .scrollGeometry(value, isClipped):
            if isClipped || allowUnclipped {
                geometry = value
            }

        case .coordinateSpace,
             .sizedSpace:
            break
        }
    }
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
