//
//  File: ShapeView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct _ShapeView<Content, Style>: View where Content: Shape, Style: ShapeStyle {

    public typealias Body = Never
    public var body: Never { neverBody() }

    public var shape: Content
    public var style: Style
    public var fillStyle: FillStyle

    public init(shape: Content, style: Style, fillStyle: FillStyle = FillStyle()) {
        self.shape = shape
        self.style = style
        self.fillStyle = fillStyle
    }
}