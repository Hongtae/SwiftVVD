//
//  File: Rectangle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Rectangle : Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        return path
    }

    @inlinable public init() {
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = _ShapeView<Rectangle, ForegroundStyle>
}

extension Rectangle : InsettableShape {
    @inlinable public func inset(by amount: CGFloat) -> some InsettableShape {
        return _Inset(amount: amount)
    }

    @usableFromInline
    struct _Inset : InsettableShape {
        @usableFromInline
        var amount: CGFloat

        @inlinable init(amount: CGFloat) {
            self.amount = amount
        }

        @usableFromInline
        func path(in rect: CGRect) -> Path {
            Rectangle().path(in: rect.insetBy(dx: self.amount, dy: self.amount))
        }

        @usableFromInline
        var animatableData: CGFloat {
            get { amount }
            set { amount = newValue }
        }

        @inlinable func inset(by amount: CGFloat) -> Rectangle._Inset {
            var copy = self
            copy.amount += amount
            return copy
        }
        
        @usableFromInline
        typealias AnimatableData = CGFloat
        @usableFromInline
        typealias Body = _ShapeView<_Inset, ForegroundStyle>
        @usableFromInline
        typealias InsetShape = Rectangle._Inset
    }
}
