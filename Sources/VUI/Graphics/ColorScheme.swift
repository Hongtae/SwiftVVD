//
//  File: ColorScheme.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//


public enum ColorScheme: CaseIterable, Hashable, Equatable, Sendable {
    case light
    case dark
}

public enum ColorSchemeContrast: CaseIterable, Hashable, Equatable, Sendable {
    case standard
    case increased
}

// colorSchemeContrast uses a top-level environment key.
struct ColorSchemeContrastKey: EnvironmentKey {
    static let defaultValue: ColorSchemeContrast = .standard
}

extension EnvironmentValues {
    // ExplicitColorSchemeKey overrides PlatformColorSchemeKey fallback.
    // The setter writes only the explicit key.
    struct ExplicitColorSchemeKey: EnvironmentKey {
        static let defaultValue: ColorScheme? = nil
    }
    struct PlatformColorSchemeKey: EnvironmentKey {
        static let defaultValue: ColorScheme = .light
    }

    public var colorScheme: ColorScheme {
        get { self[ExplicitColorSchemeKey.self] ?? self[PlatformColorSchemeKey.self] }
        set { self[ExplicitColorSchemeKey.self] = newValue }
    }

    // get-only public; wraps _colorSchemeContrast (system-injected via PlatformColorSchemeKey analogue).
    public var colorSchemeContrast: ColorSchemeContrast {
        get { self[ColorSchemeContrastKey.self] }
    }

    public var _colorSchemeContrast: ColorSchemeContrast {
        get { self[ColorSchemeContrastKey.self] }
        set { self[ColorSchemeContrastKey.self] = newValue }
    }
}

extension View {
    @inlinable nonisolated public func colorScheme(_ colorScheme: ColorScheme) -> some View {
        return environment(\.colorScheme, colorScheme)
    }
}

// Used by ColorSchemeTrait to carry the preferred color scheme through ViewTraitCollection
// when _PreferenceWritingModifier<PreferredColorSchemeKey>._makeViewList propagates to children.
public struct PreviewColorSchemeTraitKey: _ViewTraitKey {
    public static var defaultValue: ColorScheme? { nil }
}

public struct PreferredColorSchemeKey: PreferenceKey {
    public typealias Value = ColorScheme?
    // Keep-first reduction: only writes nextValue() when value is currently nil.
    public static func reduce(value: inout ColorScheme?, nextValue: () -> ColorScheme?) {
        if value == nil {
            value = nextValue()
        }
    }
}

extension View {
    @inlinable nonisolated public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
        return preference(key: PreferredColorSchemeKey.self, 
                          value: colorScheme)
    }
}
