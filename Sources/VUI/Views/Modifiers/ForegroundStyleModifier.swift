//
//  File: ForegroundStyleModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _ForegroundStyleLevels {
    public var primary: AnyShapeStyle
    public var secondary: AnyShapeStyle?
    public var tertiary: AnyShapeStyle?
}

enum ForegroundStyleEnvironmentKey: EnvironmentKey {
    static var defaultValue: _ForegroundStyleLevels? { nil }
}

extension EnvironmentValues {
    public var foregroundStyleLevels: _ForegroundStyleLevels? {
        get { self[ForegroundStyleEnvironmentKey.self] }
        set { self[ForegroundStyleEnvironmentKey.self] = newValue }
    }
}

public struct _ForegroundStyleModifier<Style>: ViewModifier where Style: ShapeStyle {
    public var style: Style

    @inlinable public init(style: Style) {
        self.style = style
    }

    public static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewInputs called outside an active AttributeGraph context.")
        }
        let parentEnvAttr = inputs.base.cachedEnvironment.value.environment
        let newEnvAttr: Attribute<EnvironmentValues> = graph.makeRule {
            let m = modifier._attribute.value
            var env = parentEnvAttr.value.trackingCopy()
            env.foregroundStyleLevels = _ForegroundStyleLevels(primary: AnyShapeStyle(m.style))
            return env
        }
        inputs.base.cachedEnvironment = MutableBox(CachedEnvironment(environment: newEnvAttr))
    }

    public typealias Body = Never
}

extension _ForegroundStyleModifier: _ViewInputsModifier {
}

public struct _ForegroundStyleModifier2<S1, S2>: ViewModifier where S1: ShapeStyle, S2: ShapeStyle {
    public var primary: S1
    public var secondary: S2

    @inlinable public init(primary: S1, secondary: S2) {
        self.primary = primary
        self.secondary = secondary
    }

    public static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewInputs called outside an active AttributeGraph context.")
        }
        let parentEnvAttr = inputs.base.cachedEnvironment.value.environment
        let newEnvAttr: Attribute<EnvironmentValues> = graph.makeRule {
            let m = modifier._attribute.value
            var env = parentEnvAttr.value.trackingCopy()
            env.foregroundStyleLevels = _ForegroundStyleLevels(
                primary: AnyShapeStyle(m.primary),
                secondary: AnyShapeStyle(m.secondary))
            return env
        }
        inputs.base.cachedEnvironment = MutableBox(CachedEnvironment(environment: newEnvAttr))
    }

    public typealias Body = Never
}

extension _ForegroundStyleModifier2: _ViewInputsModifier {
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
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewInputs called outside an active AttributeGraph context.")
        }
        let parentEnvAttr = inputs.base.cachedEnvironment.value.environment
        let newEnvAttr: Attribute<EnvironmentValues> = graph.makeRule {
            let m = modifier._attribute.value
            var env = parentEnvAttr.value.trackingCopy()
            env.foregroundStyleLevels = _ForegroundStyleLevels(
                primary: AnyShapeStyle(m.primary),
                secondary: AnyShapeStyle(m.secondary),
                tertiary: AnyShapeStyle(m.tertiary))
            return env
        }
        inputs.base.cachedEnvironment = MutableBox(CachedEnvironment(environment: newEnvAttr))
    }
    
    public typealias Body = Never
}

extension _ForegroundStyleModifier3: _ViewInputsModifier {
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
