//
//  File: FontContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Font {
    struct Context: Hashable, Sendable, CustomDebugStringConvertible {
        var sizeCategory: ContentSizeCategory
        var legibilityWeight: LegibilityWeight?
        var fontDefinition: FontDefinitionType
        var watchDisplayVariant: WatchDisplayVariant
        var shouldRedactContent: Bool
        var effectiveFont: Font
        var fontModifiers: [AnyFontModifier]
        // Name lookup follows the consuming environment, independently of the host thread.
        var resourceBundle: Bundle?
        // Automatic rendering is resolved before shared resource publication.
        var defaultFontRenderingMode: DefaultRenderingMode = .bitmap()

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.sizeCategory == rhs.sizeCategory &&
            lhs.legibilityWeight == rhs.legibilityWeight &&
            lhs.fontDefinition == rhs.fontDefinition &&
            lhs.watchDisplayVariant == rhs.watchDisplayVariant &&
            lhs.shouldRedactContent == rhs.shouldRedactContent &&
            lhs.effectiveFont == rhs.effectiveFont &&
            lhs.fontModifiers == rhs.fontModifiers &&
            lhs.defaultFontRenderingMode == rhs.defaultFontRenderingMode &&
            lhs.resourceBundle?.bundleURL.standardizedFileURL ==
                rhs.resourceBundle?.bundleURL.standardizedFileURL
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(sizeCategory)
            hasher.combine(legibilityWeight)
            hasher.combine(fontDefinition)
            hasher.combine(watchDisplayVariant)
            hasher.combine(shouldRedactContent)
            hasher.combine(effectiveFont)
            hasher.combine(fontModifiers)
            hasher.combine(defaultFontRenderingMode)
            hasher.combine(resourceBundle?.bundleURL.standardizedFileURL)
        }

        var debugDescription: String {
            "Font.Context(sizeCategory: \(sizeCategory), font: \(effectiveFont), resourceBundle: \(String(describing: resourceBundle?.bundleURL)))"
        }
    }

    struct ResolvedTraits {
        var pointSize: CGFloat
        var weight: CGFloat
        var width: CGFloat?

        init(pointSize: CGFloat, weight: CGFloat) {
            self.pointSize = pointSize
            self.weight = weight
            self.width = nil
        }

        init(_ descriptor: FontDescriptor) {
            pointSize = descriptor.pointSize
            weight = descriptor.resolvedWeight
            width = nil
        }
    }
}

struct FontDefinitionType: Hashable {
    var base: any FontDefinition.Type = DefaultFontDefinition.self

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.base == rhs.base }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(base)) }
}

// These inputs describe resolution; they do not select a native device or font service.
enum ContentSizeCategory: Hashable {
    case extraSmall, small, medium, large, extraLarge, extraExtraLarge, extraExtraExtraLarge
    case accessibilityMedium, accessibilityLarge, accessibilityExtraLarge
    case accessibilityExtraExtraLarge, accessibilityExtraExtraExtraLarge

    init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .extraLarge
        case .xxLarge: self = .extraExtraLarge
        case .xxxLarge: self = .extraExtraExtraLarge
        case .accessibility1: self = .accessibilityMedium
        case .accessibility2: self = .accessibilityLarge
        case .accessibility3: self = .accessibilityExtraLarge
        case .accessibility4: self = .accessibilityExtraExtraLarge
        case .accessibility5: self = .accessibilityExtraExtraExtraLarge
        }
    }
}

enum DynamicTypeSize: Hashable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5
}

enum LegibilityWeight: Hashable {
    case regular, bold
}

enum WatchDisplayVariant: Hashable {
    case h340, h390, h394, h448, h430, h484, h502, h446, h496, h514
}

private enum DynamicTypeSizeKey: EnvironmentKey {
    static var defaultValue: DynamicTypeSize { .large }
}

private enum LegibilityWeightKey: EnvironmentKey {
    static var defaultValue: LegibilityWeight? { nil }
}

private enum FontDefinitionKey: EnvironmentKey {
    static var defaultValue: FontDefinitionType { .init() }
}

private enum ShouldRedactContentKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

private enum WatchDisplayVariantKey: EnvironmentKey {
    static var defaultValue: WatchDisplayVariant { .h390 }
}

private enum FontContextKey: DerivedEnvironmentKey {
    static func value(in environment: EnvironmentValues) -> Font.Context {
        Font.Context(
            sizeCategory: ContentSizeCategory(environment.dynamicTypeSize),
            legibilityWeight: environment.legibilityWeight,
            fontDefinition: environment.fontDefinition,
            watchDisplayVariant: environment.watchDisplayVariant,
            shouldRedactContent: environment.shouldRedactContent,
            effectiveFont: environment.effectiveFont,
            fontModifiers: environment.fontModifiers,
            resourceBundle: environment.resourceBundle,
            defaultFontRenderingMode: environment.defaultFontRenderingMode
        )
    }
}

extension EnvironmentValues {
    var fontResolutionContext: Font.Context { self[FontContextKey.self] }

    var dynamicTypeSize: DynamicTypeSize {
        get { self[DynamicTypeSizeKey.self] }
        set { self[DynamicTypeSizeKey.self] = newValue }
    }

    var legibilityWeight: LegibilityWeight? {
        get { self[LegibilityWeightKey.self] }
        set { self[LegibilityWeightKey.self] = newValue }
    }

    var fontDefinition: FontDefinitionType {
        get { self[FontDefinitionKey.self] }
        set { self[FontDefinitionKey.self] = newValue }
    }

    var shouldRedactContent: Bool {
        get { self[ShouldRedactContentKey.self] }
        set { self[ShouldRedactContentKey.self] = newValue }
    }

    var watchDisplayVariant: WatchDisplayVariant {
        get { self[WatchDisplayVariantKey.self] }
        set { self[WatchDisplayVariantKey.self] = newValue }
    }
}
