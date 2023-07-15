//
//  File: ShapeStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol ShapeStyle {
    func _apply(to shape: inout _ShapeStyle_Shape)
    static func _apply(to type: inout _ShapeStyle_ShapeType)
}

extension ShapeStyle {
    public func _apply(to shape: inout _ShapeStyle_Shape) {
    }
    public static func _apply(to type: inout _ShapeStyle_ShapeType) {
    }
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

extension ShapeStyle where Self == Color {
    public static var red: Color    { .red }
    public static var orange: Color { .orange }
    public static var yellow: Color { .yellow }
    public static var green: Color  { .green }
    public static var mint: Color   { .mint }
    public static var teal: Color   { .teal }
    public static var cyan: Color   { .cyan }
    public static var blue: Color   { .blue }
    public static var indigo: Color { .indigo }
    public static var purple: Color { .purple }
    public static var pink: Color   { .pink }
    public static var brown: Color  { .brown }
    public static var white: Color  { .white }
    public static var gray: Color   { .gray }
    public static var black: Color  { .black }
    public static var clear: Color  { .clear }
}

public struct _ShapeStyle_Shape {
}

public struct _ShapeStyle_ShapeType {
}

public struct AnyShapeStyle: ShapeStyle {
    @usableFromInline
    struct Storage: Equatable {
        var box: AnyShapeStyleBox
        @usableFromInline
        static func == (lhs: AnyShapeStyle.Storage, rhs: AnyShapeStyle.Storage) -> Bool {
            lhs.box === rhs.box
        }
    }
    var storage: Storage
    public init<S>(_ style: S) where S: ShapeStyle {
        self.storage = Storage(box: AnyShapeStyleBox(style: style))
    }

    public func _apply(to shape: inout _ShapeStyle_Shape) {
        storage.box._apply(to: &shape)
    }

    public static func _apply(to type: inout _ShapeStyle_ShapeType) {

    }
}

class AnyShapeStyleBox {
    let style: any ShapeStyle
    init<S>(style: S) where S: ShapeStyle {
        self.style = style
    }

    func _apply(to shape: inout _ShapeStyle_Shape) {
    }

    static func _apply(to type: inout _ShapeStyle_ShapeType) {
    }
}
