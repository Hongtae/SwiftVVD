//
//  File: ForegroundStyleModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _ForegroundStyleModifier<Style>: ViewModifier where Style: ShapeStyle {
    public var style: Style
    @inlinable public init(style: Style) {
        self.style = style
    }
    public static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.base.viewStyleModifiers.append(Modifier(graph: modifier))
    }
    public typealias Body = Never
}

extension _ForegroundStyleModifier: _ViewInputsModifier {
    class Modifier: _ForegroundStyleViewStyleModifier<_ForegroundStyleModifier> {
        override func apply(modifier: Modifier, to style: inout ViewStyles) {
            style.foregroundStyle.primary = AnyShapeStyle(modifier.style)
        }
    }
}

public struct _ForegroundStyleModifier2<S1, S2>: ViewModifier where S1: ShapeStyle, S2: ShapeStyle {
    public var primary: S1
    public var secondary: S2
    @inlinable public init(primary: S1, secondary: S2) {
        self.primary = primary
        self.secondary = secondary
    }
    public static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.base.viewStyleModifiers.append(Modifier(graph: modifier))
    }
    public typealias Body = Never
}

extension _ForegroundStyleModifier2: _ViewInputsModifier {
    class Modifier: _ForegroundStyleViewStyleModifier<_ForegroundStyleModifier2> {
        override func apply(modifier: Modifier, to style: inout ViewStyles) {
            style.foregroundStyle.primary = AnyShapeStyle(modifier.primary)
            style.foregroundStyle.secondary = AnyShapeStyle(modifier.secondary)
        }
    }
}

public struct _ForegroundStyleModifier3<S1, S2, S3>: ViewModifier where S1: ShapeStyle, S2: ShapeStyle, S3: ShapeStyle {
    public var primary: S1
    public var secondary: S2
    public var tertiary: S3
    @inlinable public init(primary: S1, secondary: S2, tertiary: S3) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
    }
    public static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.base.viewStyleModifiers.append(Modifier(graph: modifier))
    }
    public typealias Body = Never
}

extension _ForegroundStyleModifier3: _ViewInputsModifier {
    class Modifier: _ForegroundStyleViewStyleModifier<_ForegroundStyleModifier3> {
        override func apply(modifier: Modifier, to style: inout ViewStyles) {
            style.foregroundStyle.primary = AnyShapeStyle(modifier.primary)
            style.foregroundStyle.secondary = AnyShapeStyle(modifier.secondary)
            style.foregroundStyle.tertiary = AnyShapeStyle(modifier.tertiary)
        }
    }
}

extension View {
    @inlinable public func foregroundStyle<S>(_ style: S) -> some View where S: ShapeStyle {
        modifier(_ForegroundStyleModifier(style: style))
    }

    @inlinable public func foregroundStyle<S1, S2>(_ primary: S1, _ secondary: S2) -> some View where S1: ShapeStyle, S2: ShapeStyle {
        modifier(_ForegroundStyleModifier2(
            primary: primary, secondary: secondary))
    }

    @inlinable public func foregroundStyle<S1, S2, S3>(_ primary: S1, _ secondary: S2, _ tertiary: S3) -> some View where S1: ShapeStyle, S2: ShapeStyle, S3: ShapeStyle {
        modifier(_ForegroundStyleModifier3(
            primary: primary, secondary: secondary, tertiary: tertiary))
    }
}

class _ForegroundStyleViewStyleModifier<Modifier>: ViewStyleModifier {
    typealias Modifier = Modifier
    var isResolved: Bool {  modifier != nil }
    var modifier: Modifier?
    let graph: _GraphValue<Modifier>
    init(graph: _GraphValue<Modifier>) {
        self.graph = graph
    }

    func apply(to style: inout ViewStyles) {
        if let modifier {
            self.apply(modifier: modifier, to: &style)
        }
    }

    func reset() {
        modifier = nil
    }
    
    func apply(modifier: Modifier, to style: inout ViewStyles) {}

    func resolve(containerView: ViewContext) {
        if let modifier = containerView.value(atPath: self.graph) {
            self.modifier = modifier
        }
    }

    static func == (lhs: _ForegroundStyleViewStyleModifier<Modifier>,
                    rhs: _ForegroundStyleViewStyleModifier<Modifier>) -> Bool {
        lhs === rhs
    }
}
