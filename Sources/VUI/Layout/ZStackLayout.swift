//
//  File: ZStackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ZStackLayout: Layout {
    public var alignment: Alignment

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = Void

    public init(alignment: Alignment = .center) {
        self.alignment = alignment
    }
}

extension ZStackLayout: DerivedLayout {
    var base: _ZStackLayout {
        _ZStackLayout(alignment: alignment)
    }
}

public struct _ZStackLayout: Layout {
    public var alignment: Alignment

    public typealias Body = Never
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Cache = Void

    public init(alignment: Alignment = .center) {
        self.alignment = alignment
    }

    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.isIdentityUnaryLayout = true
        return properties
    }

    public func spacing(subviews: Self.Subviews,
                        cache: inout Self.Cache) -> ViewSpacing {
        guard let priority = highestPriority(in: subviews) else {
            return .zero
        }

        var spacing = Spacing()
        var hasMatchingSubview = false
        for subview in subviews where subview.priority == priority {
            hasMatchingSubview = true
            spacing.incorporate(.all, of: subview.proxy.spacing())
        }
        guard hasMatchingSubview else {
            return .zero
        }
        return ViewSpacing(
            spacing,
            layoutDirection: subviews.layoutDirection
        )
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard let priority = highestPriority(in: subviews) else {
            return .zero
        }

        var leading = CGPoint(
            x: -CGFloat.infinity,
            y: -CGFloat.infinity
        )
        var trailing = leading
        for subview in subviews where subview.priority == priority {
            let dimensions = subview.dimensions(in: proposal)
            let horizontalGuide = dimensions[alignment.horizontal]
            let verticalGuide = dimensions[alignment.vertical]

            leading.x = max(leading.x, horizontalGuide)
            leading.y = max(leading.y, verticalGuide)
            trailing.x = max(
                trailing.x,
                dimensions.width == CGFloat.infinity
                    ? CGFloat.infinity
                    : dimensions.width - horizontalGuide
            )
            trailing.y = max(
                trailing.y,
                dimensions.height == CGFloat.infinity
                    ? CGFloat.infinity
                    : dimensions.height - verticalGuide
            )
        }

        return CGSize(
            width: leading.x + trailing.x,
            height: leading.y + trailing.y
        )
    }

    public func placeSubviews(in bounds: CGRect,
                              proposal: ProposedViewSize,
                              subviews: Subviews,
                              cache: inout Cache) {
        let childProposal = ProposedViewSize(bounds.size)
        var alignmentPoint = CGPoint(
            x: -CGFloat.infinity,
            y: -CGFloat.infinity
        )

        if let priority = highestPriority(in: subviews) {
            for subview in subviews where subview.priority == priority {
                let dimensions = subview.dimensions(in: childProposal)
                alignmentPoint.x = max(
                    alignmentPoint.x,
                    dimensions[alignment.horizontal]
                )
                alignmentPoint.y = max(
                    alignmentPoint.y,
                    dimensions[alignment.vertical]
                )
            }
        }

        for subview in subviews {
            let dimensions = subview.dimensions(in: childProposal)
            let horizontalGuide = dimensions[alignment.horizontal]
            let verticalGuide = dimensions[alignment.vertical]
            let origin = CGPoint(
                x: alignmentPoint.x == horizontalGuide
                    ? bounds.origin.x
                    : bounds.origin.x + alignmentPoint.x - horizontalGuide,
                y: alignmentPoint.y == verticalGuide
                    ? bounds.origin.y
                    : bounds.origin.y + alignmentPoint.y - verticalGuide
            )
            subview.place(
                in: ViewGeometry(origin: origin, dimensions: dimensions),
                layoutDirection: .leftToRight
            )
        }
    }

    private func highestPriority(in subviews: Subviews) -> Double? {
        subviews.lazy.map(\.priority).max()
    }

    // The underscored layout participates directly in layout view generation.
    public static func _makeView(root: _GraphValue<Self>,
                                 inputs: _ViewInputs,
                                 body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        Self._makeLayoutView(root: root, inputs: inputs, body: body)
    }
}

extension _ZStackLayout: _VariadicView_UnaryViewRoot {}
extension _ZStackLayout: _VariadicView_ImplicitRoot {
    static var implicitRoot: Self {
        Self()
    }
}
extension _ZStackLayout: Sendable {}
