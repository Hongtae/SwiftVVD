//
//  File: Circle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Circle: Shape {
    public func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.5
        return Path(ellipseIn: CGRect(x: rect.midX - radius,
                                      y: rect.midY - radius,
                                      width: radius * 2,
                                      height: radius * 2))
    }

    @inlinable public init() {
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = _ShapeView<Circle, ForegroundStyle>
}

extension Circle: InsettableShape {
    @inlinable public func inset(by amount: CGFloat) -> some InsettableShape {
        return _Inset(amount: amount)
    }

    @usableFromInline
    @frozen struct _Inset: InsettableShape {
        @usableFromInline
        var amount: CGFloat

        @inlinable init(amount: CGFloat) {
            self.amount = amount
        }

        @usableFromInline
        func path(in rect: CGRect) -> Path {
            Circle().path(in: rect.insetBy(dx: self.amount, dy: self.amount))
        }

        @usableFromInline
        var animatableData: CGFloat {
            get { amount }
            set { amount = newValue }
        }

        @inlinable func inset(by amount: CGFloat) -> Circle._Inset {
            var copy = self
            copy.amount += amount
            return copy
        }
        
        @usableFromInline
        typealias AnimatableData = CGFloat
        @usableFromInline
        typealias Body = _ShapeView<Circle._Inset, ForegroundStyle>
        @usableFromInline
        typealias InsetShape = Circle._Inset
    }
}
