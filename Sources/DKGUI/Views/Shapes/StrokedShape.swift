//
//  File: StrokedShape.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _StrokedShape<S>: Shape where S: Shape {
    public let shape: S
    public var style: StrokeStyle

    public init(shape: S, style: StrokeStyle) {
        self.shape = shape
        self.style = style
    }

    public typealias AnimatableData = AnimatablePair<EmptyAnimatableData, StrokeStyle.AnimatableData>
    public typealias Body = _ShapeView<Self, ForegroundStyle>

    public var animatableData: AnimatableData {
        get { AnimatableData(.init(), self.style.animatableData)}
        set { self.style.animatableData = newValue.second }
    }

    public var body: Body {
        _ShapeView(shape: self, style: ForegroundStyle())
    }
}
