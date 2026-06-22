//
//  File: BackgroundStyleModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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
    public static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewInputs called outside an active AttributeGraph context.")
        }
        let parentEnvAttr = inputs.base.cachedEnvironment.value.environment
        let newEnvAttr: Attribute<EnvironmentValues> = graph.makeRule {
            let m = modifier._attribute.value
            var env = parentEnvAttr.value.trackingCopy()
            env.backgroundStyle = AnyShapeStyle(m.style)
            return env
        }
        inputs.base.cachedEnvironment = MutableBox(CachedEnvironment(environment: newEnvAttr))
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        fatalError()
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
