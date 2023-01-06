//
//  File: ShapeStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol ShapeStyle {

}

public struct ForegroundStyle: ShapeStyle {
    public init() {
    }
}

public struct SeparatorShapeStyle: ShapeStyle {
    public init() {
    }
}

extension ShapeStyle where Self == ForegroundStyle {
    public static var foreground: ForegroundStyle { .init() }
}

extension ShapeStyle where Self == SeparatorShapeStyle {
    public static var separator: SeparatorShapeStyle { .init() }
}
