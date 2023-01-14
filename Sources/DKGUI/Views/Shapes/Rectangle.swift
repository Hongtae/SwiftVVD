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

extension Rectangle {
    struct _Inset: Shape {
        typealias AnimatableData = EmptyAnimatableData
        typealias Body = Never

        let amount: CGFloat

        var animatableData: AnimatableData {
            get { .init() }
            set { }
        }
        var body: Never { neverBody() }
    }
}
