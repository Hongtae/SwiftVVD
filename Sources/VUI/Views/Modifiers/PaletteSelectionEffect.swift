//
//  File: PaletteSelectionEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct PaletteSelectionEffect: Equatable, Sendable {
    private enum Guts: Equatable, Sendable {
        case symbolVariant(SymbolVariants)
        case automatic
        case custom
    }

    private var guts: Guts

    private init(guts: Guts) {
        self.guts = guts
    }

    public static let automatic = Self(guts: .automatic)
    public static let custom = Self(guts: .custom)

    public static func symbolVariant(
        _ variant: SymbolVariants
    ) -> Self {
        Self(guts: .symbolVariant(variant))
    }
}

private struct PaletteSelectionEffectKey: EnvironmentKey {
    static let defaultValue: PaletteSelectionEffect = .automatic
}

private struct DisplayMenuAsPaletteKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var paletteSelectionEffect: PaletteSelectionEffect {
        get { self[PaletteSelectionEffectKey.self] }
        set { self[PaletteSelectionEffectKey.self] = newValue }
    }

    var displayMenuAsPalette: Bool {
        get { self[DisplayMenuAsPaletteKey.self] }
        set { self[DisplayMenuAsPaletteKey.self] = newValue }
    }
}

extension View {
    public func paletteSelectionEffect(
        _ effect: PaletteSelectionEffect
    ) -> some View {
        environment(\.paletteSelectionEffect, effect)
    }
}
