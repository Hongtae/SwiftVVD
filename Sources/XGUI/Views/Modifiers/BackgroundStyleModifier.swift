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

extension _EnvironmentBackgroundStyleModifier: _ViewInputsModifier, _EnvironmentValuesResolve {
    public static func _makeViewInputs(modifier: _GraphValue<_EnvironmentBackgroundStyleModifier>, inputs: inout _ViewInputs) {
        inputs.base.modifiers.append(_Modifier(graph: modifier))
    }

    func _resolve(_ values: inout EnvironmentValues) {
        values.backgroundStyle = AnyShapeStyle(self.style)
    }

    class _Modifier: _GraphInputResolve {
        typealias Modifier = _EnvironmentBackgroundStyleModifier
        var isResolved: Bool {  modifier != nil }
        var modifier: Modifier?
        let graph: _GraphValue<Modifier>
        init(graph: _GraphValue<Modifier>) {
            self.graph = graph
        }

        func apply(to environment: inout EnvironmentValues) {
            if let modifier {
                modifier._resolve(&environment)
            }
        }

        func reset() {
            modifier = nil
        }

        func resolve(container: some _GraphValueResolver) {
            if let modifier = container.value(atPath: self.graph) {
                self.modifier = modifier
            }
        }

        static func == (lhs: _Modifier, rhs: _Modifier) -> Bool {
            lhs === rhs
        }
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
