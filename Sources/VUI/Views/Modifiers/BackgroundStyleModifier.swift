//
//  File: BackgroundStyleModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _EnvironmentBackgroundStyleModifier<S>: ViewModifier where S: ShapeStyle {
    @usableFromInline
    var style: S
    @inlinable init(style: S) {
        self.style = style
    }

    public typealias Body = Never
}

extension _EnvironmentBackgroundStyleModifier: _ViewInputsModifier {
    public static func _makeViewInputs(modifier: _GraphValue<_EnvironmentBackgroundStyleModifier>, inputs: inout _ViewInputs) {
        fatalError("Implement with AG")
    }
}

extension View {
    @inlinable public func backgroundStyle<S>(_ style: S) -> some View where S: ShapeStyle {
        return modifier(_EnvironmentBackgroundStyleModifier(style: style))
    }
}

enum BackgroundStyleEnvironmentKey: EnvironmentKey {
    static var defaultValue: AnyShapeStyle? { return nil }
}

extension EnvironmentValues {
    public var backgroundStyle: AnyShapeStyle? {
        get { self[BackgroundStyleEnvironmentKey.self] }
        set { self[BackgroundStyleEnvironmentKey.self] = newValue }
    }
}
