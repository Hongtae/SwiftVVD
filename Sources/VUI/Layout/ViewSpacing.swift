//
//  File: ViewSpacing.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum AbsoluteEdge: Int8, CaseIterable, Hashable, Sendable {
    case top
    case left
    case bottom
    case right

    struct Set: OptionSet, Sendable {
        var rawValue: Int8

        init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        init(_ edge: AbsoluteEdge) {
            self.init(rawValue: Int8(1 << Int(edge.rawValue)))
        }

        init(_ edges: Edge.Set, layoutDirection: LayoutDirection) {
            var result: Set = []
            if edges.contains(.top) { result.insert(.top) }
            if edges.contains(.bottom) { result.insert(.bottom) }
            if edges.contains(.leading) {
                result.insert(layoutDirection == .rightToLeft ? .right : .left)
            }
            if edges.contains(.trailing) {
                result.insert(layoutDirection == .rightToLeft ? .left : .right)
            }
            self = result
        }

        static let top = Set(.top)
        static let left = Set(.left)
        static let bottom = Set(.bottom)
        static let right = Set(.right)
        static let horizontal: Set = [.left, .right]
        static let vertical: Set = [.top, .bottom]
        static let all: Set = [.horizontal, .vertical]

        func contains(_ edge: AbsoluteEdge) -> Bool {
            contains(Set(edge))
        }
    }

    var horizontal: Bool {
        self == .left || self == .right
    }

    var opposite: AbsoluteEdge {
        switch self {
        case .top: .bottom
        case .left: .right
        case .bottom: .top
        case .right: .left
        }
    }
}

struct Spacing: Equatable, CustomStringConvertible {
    struct Category: Hashable {
        var base: UniqueID

        init() {
            base = UniqueID()
        }

        private init(base: UniqueID) {
            self.base = base
        }

        static let `default` = Category()
        static let textToText = Category()
        static let edgeAboveText = Category()
        static let edgeBelowText = Category()
        static let textBaseline = Category()
        static let edgeLeftText = Category()
        static let edgeRightText = Category()
        static let leftTextBaseline = Category()
        static let rightTextBaseline = Category()
    }

    struct Key: Hashable {
        var category: Category
        var edge: AbsoluteEdge

        init(category: Category, edge: AbsoluteEdge) {
            self.category = category
            self.edge = edge
        }
    }

    struct TextMetrics: Comparable {
        var ascend: CGFloat
        var descend: CGFloat
        var leading: CGFloat
        var pixelLength: CGFloat

        var lineSpacing: CGFloat {
            ascend + descend + leading
        }

        static func < (lhs: TextMetrics, rhs: TextMetrics) -> Bool {
            lhs.lineSpacing < rhs.lineSpacing
        }

        func isAlmostEqual(to other: TextMetrics) -> Bool {
            let tolerance = CGFloat(1.4901161193847656e-08)
            func almostEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
                if lhs.isFinite && rhs.isFinite {
                    let scale = max(abs(lhs), abs(rhs), .leastNormalMagnitude)
                    return abs(lhs - rhs) < scale * tolerance
                }
                return lhs == rhs
            }
            return almostEqual(ascend, other.ascend) &&
                almostEqual(descend, other.descend) &&
                almostEqual(leading, other.leading)
        }

        static func spacing(top: TextMetrics, bottom: TextMetrics) -> CGFloat {
            guard _SemanticFeature<Semantics_v5>.isEnabled else {
                return 0
            }

            // Preserve the emitted operation order. Although the unequal
            // branch reduces algebraically to `bottom.leading`, its
            // cancellation and non-finite behavior are part of the result.
            var spacing: CGFloat
            if top.isAlmostEqual(to: bottom) {
                spacing = bottom.leading
            } else {
                spacing = bottom.ascend + bottom.descend
                spacing += bottom.leading
                spacing -= bottom.descend
                spacing += top.descend
                spacing -= top.descend
                spacing -= bottom.ascend
            }

            if top.pixelLength == 1 {
                return ceil(spacing)
            }
            return ceil(spacing / top.pixelLength) * top.pixelLength
        }
    }

    enum Value: Comparable {
        case distance(CGFloat)
        case topTextMetrics(TextMetrics)
        case bottomTextMetrics(TextMetrics)

        init(_ value: CGFloat) {
            self = .distance(value)
        }

        var value: CGFloat? {
            switch self {
            case .distance(let value): value
            case .topTextMetrics, .bottomTextMetrics: nil
            }
        }

        func distance(to other: Value) -> CGFloat? {
            switch (self, other) {
            case let (.distance(lhs), .distance(rhs)):
                lhs + rhs
            case let (.distance(value), _):
                value
            case let (_, .distance(value)):
                value
            case let (.topTextMetrics(top), .bottomTextMetrics(bottom)):
                TextMetrics.spacing(top: top, bottom: bottom)
            case let (.bottomTextMetrics(bottom), .topTextMetrics(top)):
                TextMetrics.spacing(top: top, bottom: bottom)
            default:
                nil
            }
        }

        static func < (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case let (.distance(lhs), .distance(rhs)): lhs < rhs
            case let (.topTextMetrics(lhs), .topTextMetrics(rhs)): lhs < rhs
            case let (.bottomTextMetrics(lhs), .bottomTextMetrics(rhs)): lhs < rhs
            case (.distance, _): true
            case (.topTextMetrics, .bottomTextMetrics): true
            default: false
            }
        }
    }

    nonisolated(unsafe) static var defaultValue = CGSize(width: 8, height: 8)
    static var defaultMinimum: CGFloat { 0 }

    var minima: [Key: Value]

    init(minima: [Key: Value] = [:]) {
        self.minima = minima
    }

    static var zero: Spacing { all(0) }

    static func all(_ value: CGFloat) -> Spacing {
        Spacing(minima: Dictionary(
            uniqueKeysWithValues: AbsoluteEdge.allCases.map {
                (Key(category: .default, edge: $0), .distance(value))
            }
        ))
    }

    static func horizontal(_ value: CGFloat) -> Spacing {
        Spacing(minima: [
            Key(category: .default, edge: .left): .distance(value),
            Key(category: .default, edge: .right): .distance(value),
        ])
    }

    static func vertical(_ value: CGFloat) -> Spacing {
        Spacing(minima: [
            Key(category: .default, edge: .top): .distance(value),
            Key(category: .default, edge: .bottom): .distance(value),
        ])
    }

    static func textSpacing(
        maxFontMetrics: ResolvedFontMetrics,
        idealMetrics: GraphicsContext.ResolvedText.LayoutMetrics,
        layoutProperties: TextLayoutProperties
    ) -> Spacing {
        let beforeEdge: AbsoluteEdge
        let afterEdge: AbsoluteEdge
        let beforeEdgeCategory: Category
        let afterEdgeCategory: Category
        let beforeBaselineCategory: Category
        let afterBaselineCategory: Category

        if layoutProperties.writingMode == .verticalRightToLeft {
            beforeEdge = .right
            afterEdge = .left
            beforeEdgeCategory = .edgeRightText
            afterEdgeCategory = .edgeLeftText
            beforeBaselineCategory = .rightTextBaseline
            afterBaselineCategory = .leftTextBaseline
        } else {
            beforeEdge = .top
            afterEdge = .bottom
            beforeEdgeCategory = .edgeAboveText
            afterEdgeCategory = .edgeBelowText
            beforeBaselineCategory = .textBaseline
            afterBaselineCategory = .textBaseline
        }

        let lineHeight = maxFontMetrics.ascender - maxFontMetrics.descender
        var naturalBoundaryDistance = lineHeight * 0.1
        if _SemanticFeature<Semantics_v5>.isEnabled {
            let pixelLength = layoutProperties.pixelLength
            if pixelLength == 1 {
                naturalBoundaryDistance = ceil(naturalBoundaryDistance)
            } else {
                naturalBoundaryDistance =
                    ceil(naturalBoundaryDistance / pixelLength) * pixelLength
            }
        } else {
            naturalBoundaryDistance =
                ceil(naturalBoundaryDistance / 4) * 4
        }

        // Uniform line height divides leading between both metric extents.
        // Other sizing modes leave it as the text-to-text gap component.
        let distributedLeading =
            layoutProperties.textSizing == .uniformLineHeight
            ? maxFontMetrics.leading
            : 0
        let halfDistributedLeading = distributedLeading * 0.5
        let textMetrics = TextMetrics(
            ascend: maxFontMetrics.ascender + halfDistributedLeading,
            descend: halfDistributedLeading - maxFontMetrics.descender,
            leading: maxFontMetrics.leading - distributedLeading,
            pixelLength: layoutProperties.pixelLength
        )

        let outer = lineHeight + naturalBoundaryDistance
        let beforeDistance = outer - textMetrics.ascend
        let afterDistance = max(
            outer - maxFontMetrics.capHeight,
            naturalBoundaryDistance + textMetrics.descend
        )

        // Metric cases intentionally face the adjacent text: the before edge
        // carries bottom metrics and the after edge carries top metrics.
        return Spacing(minima: [
            Key(category: .textToText, edge: beforeEdge):
                .bottomTextMetrics(textMetrics),
            Key(category: .textToText, edge: afterEdge):
                .topTextMetrics(textMetrics),
            Key(category: afterBaselineCategory, edge: afterEdge):
                .distance(
                    idealMetrics.lastBaseline - idealMetrics.size.height
                ),
            Key(category: beforeBaselineCategory, edge: beforeEdge):
                .distance(-idealMetrics.firstBaseline),
            Key(category: beforeEdgeCategory, edge: beforeEdge):
                .distance(beforeDistance),
            Key(category: afterEdgeCategory, edge: afterEdge):
                .distance(afterDistance),
        ])
    }

    var description: String {
        minima.isEmpty ? "Spacing (empty)" : "Spacing \(minima)"
    }

    var isLayoutDirectionSymmetric: Bool {
        minima.keys.allSatisfy { $0.edge == .top || $0.edge == .bottom } ||
        minima.keys.contains { $0.edge == .left } == minima.keys.contains { $0.edge == .right }
    }

    mutating func incorporate(_ edges: AbsoluteEdge.Set, of other: Spacing) {
        for (key, value) in other.minima where edges.contains(key.edge) {
            if let oldValue = minima[key] {
                minima[key] = max(oldValue, value)
            } else {
                minima[key] = value
            }
        }
    }

    mutating func clear(_ edges: AbsoluteEdge.Set) {
        minima = minima.filter { !edges.contains($0.key.edge) }
    }

    mutating func clear(_ edges: Edge.Set, layoutDirection: LayoutDirection) {
        clear(AbsoluteEdge.Set(edges, layoutDirection: layoutDirection))
    }

    mutating func reset(_ edges: AbsoluteEdge.Set) {
        func retainedCategory(for edge: AbsoluteEdge) -> Category {
            switch edge {
            case .top: .edgeBelowText
            case .left: .edgeRightText
            case .bottom: .edgeAboveText
            case .right: .edgeLeftText
            }
        }

        // Reset preserves the text-boundary identity associated with an edge.
        // Every other selected-edge category is removed.
        var edgesNeedingInsertion = edges
        for key in Array(minima.keys) where edges.contains(key.edge) {
            if key.category == retainedCategory(for: key.edge) {
                minima[key] = .distance(0)
                edgesNeedingInsertion.remove(AbsoluteEdge.Set(key.edge))
            } else {
                minima.removeValue(forKey: key)
            }
        }
        for edge in AbsoluteEdge.allCases
            where edgesNeedingInsertion.contains(edge) {
            minima[Key(
                category: retainedCategory(for: edge),
                edge: edge
            )] = .distance(0)
        }
    }

    mutating func reset(_ edges: Edge.Set, layoutDirection: LayoutDirection) {
        reset(AbsoluteEdge.Set(edges, layoutDirection: layoutDirection))
    }

    func distanceToSuccessorView(
        along axis: Axis,
        layoutDirection: LayoutDirection,
        preferring next: Spacing
    ) -> CGFloat? {
        let trailing: AbsoluteEdge
        let leading: AbsoluteEdge
        switch axis {
        case .horizontal:
            trailing = layoutDirection == .rightToLeft ? .left : .right
            leading = layoutDirection == .rightToLeft ? .right : .left
        case .vertical:
            trailing = .bottom
            leading = .top
        }

        // Iterate the smaller category map. The helper is symmetric under the
        // paired edge/preferred-map swap used by the other branch.
        if minima.count < next.minima.count {
            return _distance(
                from: trailing,
                to: leading,
                ofViewPreferring: next
            )
        }
        return next._distance(
            from: leading,
            to: trailing,
            ofViewPreferring: self
        )
    }

    private func _distance(
        from sourceEdge: AbsoluteEdge,
        to targetEdge: AbsoluteEdge,
        ofViewPreferring preferred: Spacing
    ) -> CGFloat? {
        var distance: CGFloat?
        for (key, value) in minima {
            guard key.category != .default, key.edge == sourceEdge else {
                continue
            }
            guard let preferredValue = preferred.minima[Key(
                category: key.category,
                edge: targetEdge
            )], let candidate = value.distance(to: preferredValue) else {
                continue
            }
            distance = max(distance ?? candidate, candidate)
        }
        if let distance {
            return distance
        }

        // Default values are a fallback category. Unlike non-default scalar
        // pairs, the two sides choose a maximum rather than a sum.
        let sourceDefault = minima[Key(
            category: .default,
            edge: sourceEdge
        )]?.value
        let targetDefault = preferred.minima[Key(
            category: .default,
            edge: targetEdge
        )]?.value
        switch (sourceDefault, targetDefault) {
        case let (source?, target?):
            return max(source, target)
        case let (source?, nil):
            return source
        case let (nil, target?):
            return target
        case (nil, nil):
            return nil
        }
    }
}

public struct ViewSpacing: @unchecked Sendable {
    public static let zero = ViewSpacing(Spacing.zero)
    static let defaultSpacing: CGFloat = Spacing.defaultValue.width

    var spacing: Spacing
    var layoutDirection: LayoutDirection?

    public init() {
        self.spacing = Spacing()
        self.layoutDirection = nil
    }

    init(_ spacing: Spacing, layoutDirection: LayoutDirection? = nil) {
        self.spacing = spacing
        self.layoutDirection = layoutDirection
    }

    init(
        top: CGFloat?,
        leading: CGFloat?,
        bottom: CGFloat?,
        trailing: CGFloat?
    ) {
        var minima: [Spacing.Key: Spacing.Value] = [:]
        if let top { minima[Spacing.Key(category: .default, edge: .top)] = .distance(top) }
        if let leading { minima[Spacing.Key(category: .default, edge: .left)] = .distance(leading) }
        if let bottom { minima[Spacing.Key(category: .default, edge: .bottom)] = .distance(bottom) }
        if let trailing { minima[Spacing.Key(category: .default, edge: .right)] = .distance(trailing) }
        self.spacing = Spacing(minima: minima)
        self.layoutDirection = nil
    }

    public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) {
        self = self.union(other, edges: edges)
    }

    public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing {
        var result = self
        let absoluteEdges = AbsoluteEdge.Set(
            edges,
            layoutDirection: layoutDirection ?? .leftToRight
        )
        result.spacing.incorporate(absoluteEdges, of: other.spacing)
        return result
    }

    public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat {
        spacing.distanceToSuccessorView(
            along: axis,
            layoutDirection: layoutDirection ?? .leftToRight,
            preferring: next.spacing
        ) ?? (axis == .horizontal ? Spacing.defaultValue.width : Spacing.defaultValue.height)
    }
}

extension ViewSpacing: CustomStringConvertible {
    public var description: String {
        spacing.description
    }
}
