//
//  File: InsettableShape.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol InsettableShape: Shape {
    associatedtype InsetShape: InsettableShape
    func inset(by amount: CGFloat) -> Self.InsetShape
}

extension InsettableShape {
    @inlinable public func strokeBorder<S>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View where S: ShapeStyle {
        return inset(by: style.lineWidth * 0.5)
            .stroke(style: style)
            .fill(content, style: FillStyle(antialiased: antialiased))
    }

    @inlinable public func strokeBorder(style: StrokeStyle, antialiased: Bool = true) -> some View {
        return inset(by: style.lineWidth * 0.5)
            .stroke(style: style)
            .fill(style: FillStyle(antialiased: antialiased))
    }

    @inlinable public func strokeBorder<S>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View where S: ShapeStyle {
        return strokeBorder(content, style: StrokeStyle(lineWidth: lineWidth),
                            antialiased: antialiased)
    }

    @inlinable public func strokeBorder(lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
        return strokeBorder(style: StrokeStyle(lineWidth: lineWidth),
                            antialiased: antialiased)
    }
}
