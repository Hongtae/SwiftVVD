//
//  File: Rectangle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Rectangle: Shape {
    public func path(in rect: CGRect) -> Path {
        fatalError()
    }

    public init() {
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = _ShapeView<Rectangle, ForegroundStyle>

    public var animatableData = EmptyAnimatableData()

    public var body: Body {
        _ShapeView<Rectangle, ForegroundStyle>(shape: self, style: .init())
    }
}

extension Rectangle: InsettableShape {
    @inlinable public func inset(by amount: CGFloat) -> some InsettableShape {
        return _Inset(amount: amount)
    }

    @usableFromInline
    struct _Inset: InsettableShape {
        @usableFromInline
        internal var amount: CGFloat
        @inlinable internal init(amount: CGFloat) {
            self.amount = amount
        }
        @usableFromInline
        internal func path(in rect: CGRect) -> Path { fatalError() }
        @usableFromInline
        internal var animatableData: CGFloat {
            get { fatalError() }
            set { fatalError() }
        }
        @inlinable internal func inset(by amount: CGFloat) -> _Inset {
            var copy = self
            copy.amount += amount
            return copy
        }
        @usableFromInline
        internal typealias AnimatableData = CGFloat
        @usableFromInline
        internal typealias Body = _ShapeView<_Inset, ForegroundStyle>
        @usableFromInline
        internal typealias InsetShape = _Inset

        @usableFromInline
        internal var body: _ShapeView<_Inset, ForegroundStyle> {
            _ShapeView<_Inset, ForegroundStyle>(shape: self, style: ForegroundStyle())
        }
    }
}
