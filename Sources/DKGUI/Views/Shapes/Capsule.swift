//
//  File: Capsule.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Capsule: Shape {
    public var style: RoundedCornerStyle

    @inlinable public init(style: RoundedCornerStyle = .circular) {
        self.style = style
    }

    public func path(in r: CGRect) -> Path {
        let radius = min(r.width, r.height) * 0.5
        return Path(roundedRect: r,
                    cornerRadius: radius,
                    style: self.style)
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = _ShapeView<Capsule, ForegroundStyle>
}

extension Capsule: InsettableShape {
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
            Capsule().path(in: rect.insetBy(dx: self.amount, dy: self.amount))
        }

        @usableFromInline
        var animatableData: CGFloat {
            get { amount }
            set { amount = newValue }
        }

        @inlinable func inset(by amount: CGFloat) -> Capsule._Inset {
            var copy = self
            copy.amount += amount
            return copy
        }

        @usableFromInline
        typealias AnimatableData = CGFloat
        @usableFromInline
        typealias Body = _ShapeView<Capsule._Inset, ForegroundStyle>
        @usableFromInline
        typealias InsetShape = Capsule._Inset
    }
}
