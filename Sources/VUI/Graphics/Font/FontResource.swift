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
    /// Selected logical weight, independent of the shared physical glyph resource.
    let selectedWeight: CGFloat?
    let shapingFeatures: [TypefaceShapingFeature]
    let textStyle: Font.TextStyle?
    let stylePolicy: FontStylePolicy?
    let language: String?
    let languageAwareLineHeightRatio: Double?
    private let preferredLanguageGroup: Int
    private let metricLanguageGroup: Int
    private let source: FontDescriptor.Source
    private let variation: [UInt32: CGFloat]?
    private let selection: FontDescriptor.Resolution?
    private let renderingMode: Font.DefaultRenderingMode

    init(descriptor: FontDescriptor, in context: Font.Context) {
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = context.defaultFontRenderingMode
        self.provider = descriptor.typefaceProvider(in: environment)
        self.pointSize = descriptor.pointSize
        self.selectedWeight = descriptor.selectedWeight
        self.shapingFeatures = descriptor.shapingFeatures
        self.language = descriptor.language
        self.languageAwareLineHeightRatio = descriptor.languageAwareLineHeightRatio
        self.stylePolicy = descriptor.stylePolicy
        let data = descriptor.stylePolicy == nil ? nil : BundledFontCatalog.shared.outsetData
        self.preferredLanguageGroup = data?.preferredGroup(for: Locale.preferredLanguages) ?? 0
        self.metricLanguageGroup = descriptor.language.map { data?.preferredGroup(for: [$0]) ?? 0 }
            ?? preferredLanguageGroup
        let selection = descriptor.resolvedConstruction
        if let catalog = selection.catalog, let candidate = selection.candidate {
            self.source = .selected(catalog, candidate, nil)
            self.variation = (selection.provider as? BundledFontProvider)?.resolvedVariation?.extras
                ?? candidate.variationSelection.descriptorVariation
            self.selection = selection
        } else {
            self.source = descriptor.source
            self.variation = descriptor.variation
            self.selection = nil
        }
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
                       languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation,
                       resolution: selection)
    }

    /// Copies the selected construction at another point size.
    func fontWithSize(_ requestedSize: CGFloat) -> FontResource? {
        let size = requestedSize == 0 ? pointSize : requestedSize
        guard size.isFinite, size > 0 else { return nil }
        if size == pointSize { return self }
        var resizedSelection = selection
        if let selection, let value = selection.provider as? BundledFontProvider {
            let provider = BundledFontProvider(resource: value.resource, size: size, weight: value.weight,
                renderingMode: value.renderingMode, variations: value.variations,
                appliesSyntheticWeight: value.appliesSyntheticWeight, instanceIndex: value.instanceIndex,
                resolvedVariation: value.resolvedVariation)
            resizedSelection = FontDescriptor.Resolution(provider: provider, weight: selection.weight,
                catalog: selection.catalog, candidate: selection.candidate,
                usesVariationBase: selection.usesVariationBase)
        }
        let resizedSource: FontDescriptor.Source
        if case let .typeface(provider) = source {
            let resized: any TypefaceProvider
            switch provider {
            case let value as SystemFontProvider:
                resized = SystemFontProvider(size: size, weight: value.weight, design: value.design,
                    renderingMode: value.renderingMode, isItalic: value.isItalic, width: value.width)
            case let value as BundledFontProvider:
                resized = BundledFontProvider(resource: value.resource, size: size, weight: value.weight,
                    renderingMode: value.renderingMode, variations: value.variations,
                    appliesSyntheticWeight: value.appliesSyntheticWeight, instanceIndex: value.instanceIndex,
                    resolvedVariation: value.resolvedVariation)
            case let value as ExternalFontProvider:
                resized = ExternalFontProvider(source: value.source, size: size, weight: value.weight,
                    design: value.design, faceIndex: value.faceIndex, renderingMode: value.renderingMode)
            default:
                // A supplied face has no request from which to create another size.
                return nil
            }
            resizedSource = .typeface(resized)
        } else {
            resizedSource = source
        }
        let descriptor = FontDescriptor(source: resizedSource, pointSize: size,
            shapingFeatures: shapingFeatures, renderingMode: renderingMode, language: language,
            languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation,
            resolution: resizedSelection)
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = renderingMode
        return FontResource(descriptor: descriptor, in: environment.fontResolutionContext)
    }

    var requestedPointSize: CGFloat? {
        if case let .typeface(provider) = source, provider is FixedFontProvider { return nil }
        return pointSize
    }

    private var hasLanguageAwareMetrics: Bool {
        stylePolicy != nil && (metricLanguageGroup > 0 ||
            (languageAwareLineHeightRatio != nil && preferredLanguageGroup > 0))
    }

    /// Outset adjustment has its own component default, independent of the metric ratio.
    func adjustedOutsets(_ outsets: EdgeInsets) -> EdgeInsets {
        guard hasLanguageAwareMetrics else { return outsets }
        var result = outsets
        result.top -= 0.33 * result.top
        result.bottom -= 0.33 * result.bottom
        return result
    }

    /// Resolves natural metrics and independent clipping outsets in points.
    func resolvedMetrics(for face: Typeface, scaleFactor: CGFloat,
                         applyingStylePolicy: Bool = true) -> ResolvedFontMetrics? {
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
        let rawAscent = convert(design.ascender)
        let rawDescent = abs(convert(design.descender))
        let policy = applyingStylePolicy ? stylePolicy : nil
        let gap = policy.map { $0.targetHeight * units / $0.nominalSize - (rawAscent + rawDescent) }
            ?? convert(design.lineGap)
        var ascent = rawAscent
        var descent = rawDescent
        if let policy, hasLanguageAwareMetrics {
            let ratio = languageAwareLineHeightRatio ?? policy.lineHeightRatio(languageGroup: metricLanguageGroup)
            var attributes = face.outsetAttributes
            if let selectedWeight { attributes?.weight = selectedWeight }
            if ratio > 0, let attributes,
               let outsets = BundledFontCatalog.shared.outsetData?.outsets(
                   for: attributes, pointSize: 1, preferredGroup: metricLanguageGroup) {
                let fraction = ratio > 1 ? 0.33 : ratio
                ascent = rawAscent.addingProduct(fraction * Double(outsets.top), units)
                descent = rawDescent.addingProduct(fraction * Double(outsets.bottom), units)
                if ratio > 1 {
                    // Exactly one uses the additive branch. Larger ratios preserve
                    // optical leading while redistributing the ascent/descent target.
                    let naturalHeight = ((rawAscent + rawDescent) + gap) * size
                    let leading = gap * size
                    let factor = (naturalHeight * ratio - leading) / (naturalHeight - leading)
                    let target = (rawDescent * factor).addingProduct(rawAscent, factor)
                    let total = ascent + descent
                    ascent = ascent / total * target
                    descent = descent / total * target
                }
            }
        }
        result.ascender = CGFloat(ascent * size)
        result.descender = -CGFloat(descent * size)
        result.leading = CGFloat(gap * size)
        if let clipping = design.clipping {
            // Clipping uses the requested point size directly, independently
            // of outline-format quantization of the natural metrics.
            result.outsets.top = max(0, CGFloat(clipping.ascent) * pointSize / CGFloat(units) - result.ascender)
            result.outsets.bottom = max(0, CGFloat(clipping.descent) * pointSize / CGFloat(units) + result.descender)
        }
        return result
    }

    static func == (lhs: FontResource, rhs: FontResource) -> Bool {
        lhs.selectedWeight == rhs.selectedWeight &&
            lhs.language == rhs.language &&
            lhs.languageAwareLineHeightRatio == rhs.languageAwareLineHeightRatio &&
            lhs.stylePolicy == rhs.stylePolicy &&
            lhs.preferredLanguageGroup == rhs.preferredLanguageGroup &&
            lhs.metricLanguageGroup == rhs.metricLanguageGroup &&
            lhs.textStyle == rhs.textStyle &&
            lhs.shapingFeatures == rhs.shapingFeatures &&
            lhs.provider.isEqual(to: rhs.provider)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(selectedWeight)
        hasher.combine(language)
        hasher.combine(languageAwareLineHeightRatio)
        hasher.combine(stylePolicy)
        hasher.combine(preferredLanguageGroup)
        hasher.combine(metricLanguageGroup)
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
            let descriptor = font.descriptor()
            return context.shouldRedactContent ? descriptor.clearFeatures() : descriptor
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
