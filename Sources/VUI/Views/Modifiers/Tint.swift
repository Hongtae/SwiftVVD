//
//  File: Tint.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

private struct TintKey: EnvironmentKey {
    static let defaultValue: AnyShapeStyle? = nil
}

private struct TintColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var tint: AnyShapeStyle? {
        get { self[TintKey.self] }
        set { self[TintKey.self] = newValue }
    }

    var tintColor: Color? {
        get { self[TintColorKey.self] }
        set { self[TintColorKey.self] = newValue }
    }
}

extension View {
    public func tint<S>(_ tint: S?) -> some View where S: ShapeStyle {
        environment(\.tint, tint.map(AnyShapeStyle.init))
    }

    @_disfavoredOverload
    public func tint(_ tint: Color?) -> some View {
        environment(\.tintColor, tint)
    }
}
