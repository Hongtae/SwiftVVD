//
//  File: RoundedRectangle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct RoundedRectangle: Shape {
    public var cornerSize: CGSize
    public var style: RoundedCornerStyle

    @inlinable public init(cornerSize: CGSize, style: RoundedCornerStyle = .circular) {
        self.cornerSize = cornerSize
        self.style = style
    }

    @inlinable public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {
        let cornerSize = CGSize(width: cornerRadius, height: cornerRadius)
        self.init(cornerSize: cornerSize, style: style)
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: self.cornerSize, style: self.style)
        return path
    }

    public var animatableData: CGSize.AnimatableData {
        get { fatalError() }
        set { fatalError() }
    }

    public typealias AnimatableData = CGSize.AnimatableData
    public typealias Body = _ShapeView<RoundedRectangle, ForegroundStyle>
}

extension RoundedRectangle: InsettableShape {
    @inlinable public func inset(by amount: CGFloat) -> some InsettableShape {
        return _Inset(base: self, amount: amount)
    }

    @usableFromInline
    struct _Inset: InsettableShape {
        @usableFromInline
        var base: RoundedRectangle
        @usableFromInline
        var amount: CGFloat

        @inlinable init(base: RoundedRectangle, amount: CGFloat) {
            (self.base, self.amount) = (base, amount)
        }

        @usableFromInline
        func path(in rect: CGRect) -> Path {
            base.path(in: rect.insetBy(dx: self.amount, dy: self.amount))
        }

        @usableFromInline
        var animatableData: AnimatablePair<RoundedRectangle.AnimatableData, CGFloat> {
            get { .init(base.animatableData, amount) }
            set { (base.animatableData, amount) = newValue[] }
        }

        @inlinable func inset(by amount: CGFloat) -> RoundedRectangle._Inset {
            var copy = self
            copy.amount += amount
            return copy
        }

        @usableFromInline
        typealias AnimatableData = AnimatablePair<RoundedRectangle.AnimatableData, CGFloat>
        @usableFromInline
        typealias Body = _ShapeView<RoundedRectangle._Inset, ForegroundStyle>
        @usableFromInline
        typealias InsetShape = RoundedRectangle._Inset
    }
}
