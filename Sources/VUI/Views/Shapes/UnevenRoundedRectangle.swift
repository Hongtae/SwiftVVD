//
//  File: UnevenRoundedRectangle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct RectangleCornerRadii: Equatable, Animatable, Sendable, BitwiseCopyable {
    package var topLeft: CGFloat
    package var topRight: CGFloat
    package var bottomRight: CGFloat
    package var bottomLeft: CGFloat

    public var topLeading: CGFloat {
        get { topLeft }
        set { topLeft = newValue }
    }

    public var bottomLeading: CGFloat {
        get { bottomLeft }
        set { bottomLeft = newValue }
    }

    public var bottomTrailing: CGFloat {
        get { bottomRight }
        set { bottomRight = newValue }
    }

    public var topTrailing: CGFloat {
        get { topRight }
        set { topRight = newValue }
    }

    package init(topLeft: CGFloat, topRight: CGFloat,
                 bottomRight: CGFloat, bottomLeft: CGFloat) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0,
                bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) {
        self.init(topLeft: topLeading, topRight: topTrailing,
                  bottomRight: bottomTrailing, bottomLeft: bottomLeading)
    }

    public typealias AnimatableData = AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    >

    public var animatableData: AnimatableData {
        get {
            .init(.init(topLeft, topRight), .init(bottomRight, bottomLeft))
        }
        set {
            topLeft = newValue.first.first
            topRight = newValue.first.second
            bottomRight = newValue.second.first
            bottomLeft = newValue.second.second
        }
    }

    public subscript(corner: Edge.Corner) -> CGFloat {
        switch corner {
        case .topLeading: topLeading
        case .topTrailing: topTrailing
        case .bottomLeading: bottomLeading
        case .bottomTrailing: bottomTrailing
        }
    }
}

extension Shape where Self == UnevenRoundedRectangle {
    public static func rect(
        cornerRadii: RectangleCornerRadii,
        style: RoundedCornerStyle = .continuous
    ) -> Self {
        .init(cornerRadii: cornerRadii, style: style)
    }

    public static func rect(
        topLeadingRadius: CGFloat = 0,
        bottomLeadingRadius: CGFloat = 0,
        bottomTrailingRadius: CGFloat = 0,
        topTrailingRadius: CGFloat = 0,
        style: RoundedCornerStyle = .continuous
    ) -> Self {
        .init(topLeadingRadius: topLeadingRadius,
              bottomLeadingRadius: bottomLeadingRadius,
              bottomTrailingRadius: bottomTrailingRadius,
              topTrailingRadius: topTrailingRadius,
              style: style)
    }
}

public struct UnevenRoundedRectangle: Shape {
    public var cornerRadii: RectangleCornerRadii
    public var style: RoundedCornerStyle

    @inlinable public init(
        cornerRadii: RectangleCornerRadii,
        style: RoundedCornerStyle = .continuous
    ) {
        self.cornerRadii = cornerRadii
        self.style = style
    }

    @inlinable public init(
        topLeadingRadius: CGFloat = 0,
        bottomLeadingRadius: CGFloat = 0,
        bottomTrailingRadius: CGFloat = 0,
        topTrailingRadius: CGFloat = 0,
        style: RoundedCornerStyle = .continuous
    ) {
        self.init(
            cornerRadii: .init(
                topLeading: topLeadingRadius,
                bottomLeading: bottomLeadingRadius,
                bottomTrailing: bottomTrailingRadius,
                topTrailing: topTrailingRadius),
            style: style)
    }

    public func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadii: cornerRadii, style: style)
    }

    public var animatableData: RectangleCornerRadii.AnimatableData {
        get { cornerRadii.animatableData }
        set { cornerRadii.animatableData = newValue }
    }

    public typealias AnimatableData = RectangleCornerRadii.AnimatableData
    public typealias Body = _ShapeView<UnevenRoundedRectangle, ForegroundStyle>
}

extension UnevenRoundedRectangle: InsettableShape {
    @inlinable public func inset(by amount: CGFloat) -> some InsettableShape {
        _Inset(base: self, amount: amount)
    }

    @usableFromInline
    struct _Inset: InsettableShape {
        @usableFromInline
        var base: UnevenRoundedRectangle
        @usableFromInline
        var amount: CGFloat

        @inlinable init(base: UnevenRoundedRectangle, amount: CGFloat) {
            self.base = base
            self.amount = amount
        }

        @usableFromInline
        func path(in rect: CGRect) -> Path {
            let radii = RectangleCornerRadii(
                topLeading: max(base.cornerRadii.topLeading - amount, 0),
                bottomLeading: max(base.cornerRadii.bottomLeading - amount, 0),
                bottomTrailing: max(base.cornerRadii.bottomTrailing - amount, 0),
                topTrailing: max(base.cornerRadii.topTrailing - amount, 0))
            return Path(roundedRect: rect.insetBy(dx: amount, dy: amount),
                        cornerRadii: radii, style: base.style)
        }

        @usableFromInline
        var animatableData: AnimatablePair<UnevenRoundedRectangle.AnimatableData, CGFloat> {
            get { .init(base.animatableData, amount) }
            set {
                base.animatableData = newValue.first
                amount = newValue.second
            }
        }

        @inlinable func inset(by amount: CGFloat) -> UnevenRoundedRectangle._Inset {
            var copy = self
            copy.amount += amount
            return copy
        }

        @usableFromInline
        typealias AnimatableData = AnimatablePair<UnevenRoundedRectangle.AnimatableData, CGFloat>
        @usableFromInline
        typealias Body = _ShapeView<UnevenRoundedRectangle._Inset, ForegroundStyle>
        @usableFromInline
        typealias InsetShape = UnevenRoundedRectangle._Inset
    }
}
