//
//  File: FontResource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Immutable resolution state shared independently of device and glyph resources.
final class FontResource: Hashable, @unchecked Sendable {
    let provider: any TypefaceProvider
    let pointSize: CGFloat
    let shapingFeatures: [TypefaceShapingFeature]
    let textStyle: Font.TextStyle?
    let language: String?
    let languageAwareLineHeightRatio: Double?
    private let source: FontDescriptor.Source
    private let renderingMode: Font.DefaultRenderingMode

    init(descriptor: FontDescriptor, in context: Font.Context) {
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = context.defaultFontRenderingMode
        self.provider = descriptor.typefaceProvider(in: environment)
        self.pointSize = descriptor.pointSize
        self.shapingFeatures = descriptor.shapingFeatures
        self.language = descriptor.language
        self.languageAwareLineHeightRatio = descriptor.languageAwareLineHeightRatio
        self.source = descriptor.source
        self.renderingMode = descriptor.renderingMode ?? context.defaultFontRenderingMode
        if case let .system(_, _, _, _, style) = descriptor.source {
            self.textStyle = style
        } else {
            self.textStyle = nil
        }
    }

    // Every descriptor remains consumer-owned, including its lazy selection state.
    func descriptor() -> FontDescriptor {
        FontDescriptor(source: source, pointSize: pointSize, shapingFeatures: shapingFeatures,
                       renderingMode: renderingMode, language: language,
                       languageAwareLineHeightRatio: languageAwareLineHeightRatio)
    }

    /// Resolves natural metrics and independent clipping outsets in points.
    func resolvedMetrics(for face: Typeface, scaleFactor: CGFloat) -> ResolvedFontMetrics? {
        // A supplied face has no independent requested point size to resolve.
        if case let .typeface(provider) = source, provider is FixedFontProvider {
            return nil
        }
        guard pointSize.isFinite, pointSize > 0,
              let design = face.designMetrics else { return nil }
        let units = Double(design.unitsPerEM)
        let convert: (Int) -> Double
        if design.unitsPerEM == 2048 {
            convert = { Double($0) }
        } else {
            switch design.outlineFormat {
            case .trueType:
                let normalize = 65536 / units
                let restore = units / 65536
                convert = { (Double($0) * normalize).rounded(.toNearestOrAwayFromZero) * restore }
            case .compactFontFormat:
                let reciprocal = ceil(134217728 / units)
                convert = { Double($0) * reciprocal / 65536 * (units / 2048) }
            case .other:
                return nil
            }
        }
        // Cap height retains its independent backend input.
        var result = face.resolvedMetrics.scaled(by: scaleFactor)
        let size = Double(pointSize) / units
        result.ascender = CGFloat(convert(design.ascender) * size)
        result.descender = -CGFloat(abs(convert(design.descender)) * size)
        result.leading = CGFloat(convert(design.lineGap) * size)
        if let clipping = design.clipping {
            // Clipping uses the requested point size directly, independently
            // of outline-format quantization of the natural metrics.
            result.outsets.top = max(0, CGFloat(clipping.ascent) * pointSize / CGFloat(units) - result.ascender)
            result.outsets.bottom = max(0, CGFloat(clipping.descent) * pointSize / CGFloat(units) + result.descender)
        }
        return result
    }

    static func == (lhs: FontResource, rhs: FontResource) -> Bool {
        lhs.language == rhs.language &&
            lhs.languageAwareLineHeightRatio == rhs.languageAwareLineHeightRatio &&
            lhs.textStyle == rhs.textStyle &&
            lhs.shapingFeatures == rhs.shapingFeatures &&
            lhs.provider.isEqual(to: rhs.provider)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(language)
        hasher.combine(languageAwareLineHeightRatio)
        hasher.combine(textStyle)
        hasher.combine(shapingFeatures)
        provider.hash(into: &hasher)
    }
}

extension Font {
    struct FontCache {
        struct Key: Hashable, Sendable {
            var font: Font
            var modifiers: [AnyFontModifier]
            var context: Context
        }

        static let shared = ObjectCache<Key, FontResource> { key in
            var descriptor = key.font.resolveDescriptor(in: key.context)
            for modifier in key.modifiers {
                modifier.modify(descriptor: &descriptor, in: key.context)
            }
            return FontResource(descriptor: descriptor, in: key.context)
        }
    }

    func platformFont(
        in context: Context,
        modifiers: [AnyFontModifier] = [],
        overrideContextModifiers: Bool = false
    ) -> FontResource {
        let modifiers = overrideContextModifiers
            ? modifiers
            : context.fontModifiers + modifiers
        var context = context
        context.fontModifiers = []
        return FontCache.shared[FontCache.Key(font: self, modifiers: modifiers, context: context)]
    }

    struct PlatformFontProvider: FontProvider {
        var font: FontResource
        var tag: ProviderTag { .typeface }

        func resolveDescriptor(in context: Context) -> FontDescriptor {
            font.descriptor()
        }

        func serialize(to encoder: any Encoder) throws {
            throw EncodingError.invalidValue(font, .init(codingPath: encoder.codingPath,
                debugDescription: "Resolved font resources cannot be archived as logical font requests."))
        }

        static func deserialize(from decoder: any Decoder) throws -> Self {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Resolved font resources cannot be decoded from a logical font archive."))
        }
    }
}
