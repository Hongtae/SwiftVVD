//
//  File: FontResource.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

/// Immutable resolution state shared independently of device and glyph resources.
final class FontResource: Hashable, @unchecked Sendable {
    /// Registered selection inputs used before any device resource is created.
    private struct RegisteredConstruction {
        let resource: BundledFontResource
        let name: String?
        let descriptorVariation: [UInt32: CGFloat]?
        let comparisonVariation: [UInt32: CGFloat]
        let derivesOpticalSize: Bool
        let hasVariationExtras: Bool
        let features: [VVD.FontFeatures.Setting]

        init?(_ selection: FontDescriptor.Resolution, shapingFeatures: [TypefaceShapingFeature]) {
            guard let candidate = selection.candidate,
                  let provider = selection.provider as? BundledFontProvider,
                  let resolved = provider.opticalConstruction?.resolved ?? provider.resolvedVariation else { return nil }
            let variation = FontVariationSelection(metadata: candidate.face.metadata, coordinates: resolved.coordinates)
            self.resource = provider.resource
            self.name = provider.opticalConstruction?.postScriptName ?? variation.postScriptName
            self.descriptorVariation = selection.usesVariationBase ? resolved.comparison : variation.descriptorVariation
            self.comparisonVariation = resolved.comparison
            self.derivesOpticalSize = provider.opticalConstruction?.derivesOpticalSize ?? false
            self.hasVariationExtras = resolved.extras != nil
            self.features = candidate.face.featureCatalog.select(shapingFeatures)
        }

        func isEqual(to other: Self) -> Bool {
            resource == other.resource && name == other.name &&
                descriptorVariation == other.descriptorVariation &&
                comparisonVariation == other.comparisonVariation &&
                derivesOpticalSize == other.derivesOpticalSize &&
                VVD.FontFeatures.settingsEqual(features, other.features)
        }

        func hash(into hasher: inout Hasher, extraAttributeCount: Int) {
            // Descriptor hashing uses the selected name. Original extras have
            // a separate hash contribution even when comparison discards them.
            hasher.combine(name)
            hasher.combine(derivesOpticalSize)
            let count = extraAttributeCount + (hasVariationExtras ? 1 : 0)
            hasher.combine(count == 0 ? nil : count)
        }
    }

    let provider: any TypefaceProvider
    let pointSize: CGFloat
    /// Selected logical weight, independent of the shared physical glyph resource.
    let selectedWeight: CGFloat?
    /// Physical-face requests; descriptor copies carry the selected settings.
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
    private let preservesSizeOnSymbolicCopy: Bool
    private let renderingMode: Font.DefaultRenderingMode
    private let registeredConstruction: RegisteredConstruction?

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
        self.preservesSizeOnSymbolicCopy = descriptor.preservesSizeOnSymbolicCopy
        let data = descriptor.stylePolicy == nil ? nil : BundledFontCatalog.shared.outsetData
        self.preferredLanguageGroup = data?.preferredGroup(for: Locale.preferredLanguages) ?? 0
        self.metricLanguageGroup = descriptor.language.map { data?.preferredGroup(for: [$0]) ?? 0 }
            ?? preferredLanguageGroup
        let selection = descriptor.resolvedConstruction
        let registered = RegisteredConstruction(selection, shapingFeatures: descriptor.shapingFeatures)
        self.registeredConstruction = registered
        if let catalog = selection.catalog, let candidate = selection.candidate {
            let provider = selection.provider as? BundledFontProvider
            if let optical = provider?.opticalConstruction {
                self.source = .selected(catalog, candidate.selecting(optical.selection,
                    comparison: optical.resolved.comparison), nil)
                self.variation = optical.resolved.extras
            } else {
                self.source = .selected(catalog, candidate, nil)
                self.variation = provider?.resolvedVariation?.extras ?? candidate.variationSelection.descriptorVariation
            }
            // A copied descriptor starts from this actual selected face, even
            // when construction used the default for an unmatched request.
            var copied = selection
            copied.didMatchRequest = true
            self.selection = copied
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
    // The metric ratio belongs to this resolved font and is not a copied attribute.
    func descriptor() -> FontDescriptor {
        FontDescriptor(source: source, pointSize: pointSize, shapingFeatures: descriptorFeatures,
                       renderingMode: renderingMode, language: language,
                       stylePolicy: stylePolicy, variation: variation,
                       resolution: selection, preservesSizeOnSymbolicCopy: preservesSizeOnSymbolicCopy)
    }

    private var descriptorFeatures: [TypefaceShapingFeature] {
        registeredConstruction?.features.map { TypefaceShapingFeature(tag: $0.tag, value: $0.value) }
            ?? shapingFeatures
    }

    /// Copies the selected construction at another point size.
    func fontWithSize(_ requestedSize: CGFloat) -> FontResource? {
        let size = requestedSize == 0 ? pointSize : requestedSize
        guard size.isFinite, size > 0 else { return nil }
        // An explicit unchanged size preserves the font. Zero reconstructs its
        // published descriptor, including the automatic metric policy.
        if size == pointSize &&
            (requestedSize != 0 ||
             (registeredConstruction == nil && languageAwareLineHeightRatio == nil)) {
            return self
        }
        var resizedSelection = selection
        if let selection, let value = selection.provider as? BundledFontProvider {
            let provider = value.withSize(size, variationExtras: variation)
            resizedSelection = FontDescriptor.Resolution(provider: provider, weight: selection.weight,
                catalog: selection.catalog, candidate: selection.candidate,
                usesVariationBase: selection.usesVariationBase)
        }
        let resizedSource: FontDescriptor.Source
        if case let .supplied(provider, bundle) = source {
            guard let copy = provider.withSize(size) else { return nil }
            resizedSource = .supplied(copy, bundle)
        } else if case let .typeface(provider) = source {
            let resized: any TypefaceProvider
            switch provider {
            case let value as SystemFontProvider:
                resized = SystemFontProvider(size: size, weight: value.weight, design: value.design,
                    renderingMode: value.renderingMode, isItalic: value.isItalic, width: value.width)
            case let value as BundledFontProvider:
                resized = value.withSize(size)
            case let value as ExternalFontProvider:
                resized = ExternalFontProvider(source: value.source, size: size, weight: value.weight,
                    design: value.design, faceIndex: value.faceIndex, renderingMode: value.renderingMode)
            case let value as FixedFontProvider:
                guard let copy = value.withSize(size) else { return nil }
                resized = copy
            default:
                return nil
            }
            resizedSource = .typeface(resized)
        } else {
            resizedSource = source
        }
        let descriptor = FontDescriptor(source: resizedSource, pointSize: size,
            shapingFeatures: descriptorFeatures, renderingMode: renderingMode, language: language,
            stylePolicy: stylePolicy, variation: variation,
            resolution: resizedSelection, preservesSizeOnSymbolicCopy: preservesSizeOnSymbolicCopy)
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = renderingMode
        return FontResource(descriptor: descriptor, in: environment.fontResolutionContext)
    }

    var requestedPointSize: CGFloat? {
        if let provider = source.fixedProvider,
           !provider.supportsSizeCopy { return nil }
        return pointSize
    }

    /// A supplied face retains the metric owner's DPI and layout scale.
    func resolvedPointSize(for face: Typeface, scaleFactor: CGFloat) -> CGFloat? {
        if let provider = source.fixedProvider {
            guard provider.supportsSizeCopy, scaleFactor > 0,
                  let size = face.outsetAttributes?.pointSize else { return nil }
            return size / scaleFactor
        }
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
        guard let pointSize = resolvedPointSize(for: face, scaleFactor: scaleFactor),
              pointSize.isFinite, pointSize > 0,
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
        var result = face.resolvedMetrics.scaled(by: scaleFactor)
        let size = Double(pointSize) / units
        // Cap height bypasses the format-specific conversion of ascent/descent/leading.
        if let capHeight = design.capHeight {
            result.capHeight = CGFloat(Double(capHeight) * size)
        }
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
        guard lhs.selectedWeight == rhs.selectedWeight &&
            lhs.language == rhs.language &&
            lhs.metricRatio == rhs.metricRatio &&
            lhs.stylePolicy == rhs.stylePolicy &&
            lhs.preferredLanguageGroup == rhs.preferredLanguageGroup &&
            lhs.metricLanguageGroup == rhs.metricLanguageGroup &&
            lhs.textStyle == rhs.textStyle else { return false }
        switch (lhs.registeredConstruction, rhs.registeredConstruction) {
        case let (a?, b?):
            return lhs.pointSize == rhs.pointSize && lhs.renderingMode == rhs.renderingMode && a.isEqual(to: b)
        case (nil, nil):
            return lhs.shapingFeatures == rhs.shapingFeatures && lhs.provider.isEqual(to: rhs.provider)
        default:
            return false
        }
    }

    private var metricRatio: Double? {
        registeredConstruction == nil || stylePolicy != nil ? languageAwareLineHeightRatio : nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(selectedWeight)
        hasher.combine(metricRatio)
        hasher.combine(stylePolicy)
        hasher.combine(preferredLanguageGroup)
        hasher.combine(metricLanguageGroup)
        hasher.combine(textStyle)
        if let registeredConstruction {
            hasher.combine(true)
            hasher.combine(pointSize)
            hasher.combine(renderingMode)
            hasher.combine(SelectedFont.constructionFlags(language: language))
            registeredConstruction.hash(into: &hasher,
                extraAttributeCount: (language == nil ? 0 : 1) + (registeredConstruction.features.isEmpty ? 0 : 1))
        } else {
            hasher.combine(false)
            hasher.combine(language)
            hasher.combine(shapingFeatures)
            provider.hash(into: &hasher)
        }
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
