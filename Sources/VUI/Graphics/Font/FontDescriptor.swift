//
//  File: FontDescriptor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// A retained request. Metadata lookup is deferred until traits or a typeface are needed.
final class FontDescriptor {
    enum Source {
        // A text style remains distinct from a fixed-size request with the same glyph traits.
        case system(Font.Design, Font.Weight, Bool, width: CGFloat? = nil, textStyle: Font.TextStyle? = nil)
        case named(String, Bundle?)
        case family(BundledFontCatalog, String, FontResourceResolver.Traits)
        case selected(BundledFontCatalog, FontResourceResolver.Candidate, FontResourceResolver.Traits?)
        case typeface(any TypefaceProvider)
        case supplied(FixedFontProvider, Bundle?)

        var fixedProvider: FixedFontProvider? {
            switch self {
            case let .typeface(provider): provider as? FixedFontProvider
            case let .supplied(provider, _): provider
            default: nil
            }
        }
    }

    struct Resolution {
        let provider: any TypefaceProvider
        let weight: CGFloat
        let catalog: BundledFontCatalog?
        let candidate: FontResourceResolver.Candidate?
        var usesVariationBase = false
        // A final default face does not make the original name match succeed.
        var didMatchRequest = true
    }

    let source: Source
    let pointSize: CGFloat
    let variation: [UInt32: CGFloat]?
    let stylePolicy: FontStylePolicy?
    let shapingFeatures: [TypefaceShapingFeature]
    let renderingMode: Font.DefaultRenderingMode?
    let language: String?
    let languageAwareLineHeightRatio: Double?
    // General attribute copies can transport size through later variant selection.
    // This is independent of whether the selected base is retained by a copy.
    let preservesSizeOnSymbolicCopy: Bool
    let hasPointSizeAttribute: Bool
    // Each consumer owns its descriptor; only catalog snapshots are shared across threads.
    private var resolution: Resolution?

    private var hasInitializedSelection: Bool {
        if case .supplied = source { return true }
        return resolution != nil
    }

    init(source: Source, pointSize: CGFloat, shapingFeatures: [TypefaceShapingFeature] = [],
         renderingMode: Font.DefaultRenderingMode? = nil, language: String? = nil,
         languageAwareLineHeightRatio: Double? = nil, stylePolicy: FontStylePolicy? = nil,
         variation: [UInt32: CGFloat]? = nil, resolution: Resolution? = nil,
         preservesSizeOnSymbolicCopy: Bool = false, hasPointSizeAttribute: Bool = true) {
        self.source = source
        self.pointSize = pointSize
        self.variation = variation
        self.stylePolicy = stylePolicy
        self.shapingFeatures = shapingFeatures
        self.renderingMode = renderingMode
        self.language = language
        self.languageAwareLineHeightRatio = languageAwareLineHeightRatio
        self.resolution = resolution
        self.preservesSizeOnSymbolicCopy = preservesSizeOnSymbolicCopy
        self.hasPointSizeAttribute = hasPointSizeAttribute
    }

    var resolvedConstruction: Resolution { resolve() }

    var resolvedWeight: CGFloat { resolve().weight }

    /// Selected logical traits remain separate from the physical glyph coordinates.
    var selectedWeight: CGFloat? {
        if case let .supplied(provider, _) = source { return provider.selection?.traits.weight }
        return resolve().candidate?.traits.weight
    }

    var traitsPointSize: CGFloat { hasPointSizeAttribute ? pointSize : 0 }

    func typefaceProvider(in environment: EnvironmentValues) -> any TypefaceProvider {
        var environment = environment
        if let renderingMode {
            environment.defaultFontRenderingMode = renderingMode
        }
        return resolve().provider.resolved(in: environment)
    }

    func weight(_ weight: Font.Weight) -> FontDescriptor {
        switch source {
        case let .supplied(provider, bundle):
            var traits = provider.selection!.traits
            traits.weight = weight.value
            return suppliedFamily(provider, bundle: bundle, traits: traits)
        case let .system(design, _, italic, width, textStyle):
            return FontDescriptor(source: .system(design, weight, italic, width: width, textStyle: textStyle), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
        case let .family(catalog, name, current):
            var traits = current
            traits.weight = weight.value
            return FontDescriptor(source: .family(catalog, name, traits), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
        case let .typeface(provider):
            if let system = provider as? SystemFontProvider {
                return FontDescriptor(source: .typeface(SystemFontProvider(
                    size: pointSize, weight: weight, design: system.design,
                    renderingMode: system.renderingMode, isItalic: system.isItalic, width: system.width
                )), pointSize: pointSize, shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
            }
            if let external = provider as? ExternalFontProvider {
                return FontDescriptor(source: .typeface(ExternalFontProvider(
                    source: external.source, size: pointSize, weight: weight, design: external.design,
                    faceIndex: external.faceIndex, renderingMode: external.renderingMode
                )), pointSize: pointSize, shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
            }
            return self
        default:
            let resolved = resolve()
            guard let catalog = resolved.catalog, let candidate = resolved.candidate else { return self }
            var traits = retainedTraits ?? candidate.traits
            traits.weight = weight.value
            return FontDescriptor(source: .family(catalog, candidate.family, traits), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
        }
    }

    func width(_ width: CGFloat) -> FontDescriptor {
        switch source {
        case let .supplied(provider, bundle):
            var traits = provider.selection!.traits
            traits.width = width
            return suppliedFamily(provider, bundle: bundle, traits: traits)
        case let .system(design, weight, italic, _, textStyle):
            return FontDescriptor(source: .system(design, weight, italic, width: width, textStyle: textStyle), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
        case let .family(catalog, name, current):
            var traits = current
            traits.width = width
            return FontDescriptor(source: .family(catalog, name, traits), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
        case let .typeface(provider):
            guard let system = provider as? SystemFontProvider else { return self }
            return FontDescriptor(source: .typeface(SystemFontProvider(
                size: pointSize, weight: system.weight, design: system.design,
                renderingMode: system.renderingMode, isItalic: system.isItalic, width: Font.Width(width)
            )), pointSize: pointSize, shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
        default:
            let resolved = resolve()
            guard let catalog = resolved.catalog, let candidate = resolved.candidate else { return self }
            // Replacing an exact face reuses its retained request, not the last selected traits.
            var traits = retainedTraits ?? candidate.traits
            traits.width = width
            return FontDescriptor(source: .family(catalog, candidate.family, traits), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
        }
    }

    func symbolicTrait(_ trait: UInt32, active: Bool) -> FontDescriptor {
        if trait == 0x8000 || trait == 0x10000 {
            switch source {
            case .system, .typeface:
                return FontDescriptor(source: source, pointSize: pointSize, shapingFeatures: shapingFeatures,
                                      renderingMode: renderingMode, language: language,
                                      languageAwareLineHeightRatio: languageAwareLineHeightRatio,
                                      stylePolicy: stylePolicy?.applying(trait: trait, active: active), variation: variation)
            default:
                break
            }
        }
        switch source {
        case let .supplied(provider, bundle):
            return suppliedVariant(provider, bundle: bundle, trait: trait, active: active)
        case let .system(design, weight, italic, width, textStyle):
            let nextWeight = trait == 2 ? symbolicWeight(weight, active: active) : weight
            return FontDescriptor(source: .system(design, nextWeight, trait == 1 ? active : italic,
                                                  width: width, textStyle: textStyle),
                                  pointSize: pointSize, shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
        case let .typeface(provider):
            guard let system = provider as? SystemFontProvider else { return self }
            let nextWeight = trait == 2 ? symbolicWeight(system.weight, active: active) : system.weight
            return FontDescriptor(source: .typeface(SystemFontProvider(
                size: pointSize, weight: nextWeight, design: system.design,
                renderingMode: system.renderingMode, isItalic: trait == 1 ? active : system.isItalic,
                width: system.width
            )), pointSize: pointSize, shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
        default:
            let resolved = resolve()
            guard resolved.didMatchRequest else { return self }
            guard let catalog = resolved.catalog, let candidate = resolved.candidate else { return self }
            if (candidate.traits.symbolic & trait != 0) == active {
                if resolved.usesVariationBase { return self }
                // An unchanged variant can still require a new descriptor match.
                // Keep the original request instead of replacing it with the last result.
                return FontDescriptor(source: source, pointSize: pointSize, shapingFeatures: shapingFeatures,
                                      renderingMode: renderingMode, language: language,
                                      languageAwareLineHeightRatio: languageAwareLineHeightRatio,
                                      stylePolicy: stylePolicy, variation: variation,
                                      preservesSizeOnSymbolicCopy: preservesSizeOnSymbolicCopy, hasPointSizeAttribute: hasPointSizeAttribute)
            }
            var requested = candidate.traits
            // Ordinary family variants do not retain the two leading policy bits.
            requested.symbolic = ((requested.symbolic & ~trait) | (active ? trait : 0)) & ~0x18000
            requested.weight = trait == 2
                ? (active ? Font.Weight.bold.value : 0)
                : (retainedTraits?.weight ?? candidate.traits.weight)
            // A variant must retain the other matching traits, including width and boldness.
            let matchingTraits: UInt32 = 0x0fff_bbff
            let candidates = catalog.resources.resolver.family(candidate.family).filter {
                $0.traits.symbolic & matchingTraits == requested.symbolic & matchingTraits
            }
            let selected: FontResourceResolver.Candidate
            var copiedVariation = variation
            if let variant = FontResourceResolver.selectSymbolicVariant(
                candidates, from: candidate, weight: requested.weight
            ) {
                selected = variant
            } else {
                guard let replacement = FontResourceResolver.symbolicWeightVariation(
                    from: candidate, weight: requested.weight
                ) else { return self }
                if resolved.usesVariationBase && (variation == nil || variation == replacement) {
                    // The selected instance can be returned directly. Its dictionary
                    // contains the selected axes and a size only when copied options
                    // transport one; unrelated original attributes are not merged.
                    let descriptor = FontDescriptor(source: .selected(catalog, candidate, nil),
                        pointSize: preservesSizeOnSymbolicCopy ? pointSize : 12,
                        renderingMode: renderingMode, variation: replacement,
                        preservesSizeOnSymbolicCopy: preservesSizeOnSymbolicCopy,
                        hasPointSizeAttribute: preservesSizeOnSymbolicCopy && hasPointSizeAttribute)
                    let selection = candidate.variationSelection.applying(replacement)
                    descriptor.resolution = descriptor.realized(candidate, in: catalog, variation: .init(
                        coordinates: selection.coordinates, comparison: replacement, extras: replacement))
                    descriptor.resolution?.usesVariationBase = true
                    return descriptor
                }
                selected = candidate
                if !replacement.isEmpty {
                    copiedVariation = (variation ?? [:]).merging(replacement) { _, new in new }
                }
            }
            return FontDescriptor(source: .selected(catalog, selected, retainedTraits), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio,
                                  stylePolicy: stylePolicy, variation: copiedVariation,
                                  preservesSizeOnSymbolicCopy: preservesSizeOnSymbolicCopy, hasPointSizeAttribute: hasPointSizeAttribute)
        }
    }

    private func suppliedCatalog(_ provider: FixedFontProvider, bundle: Bundle?) -> BundledFontCatalog {
        let family = provider.selection!.variation.metadata.familyName ?? ""
        if let catalog = bundle.flatMap({ BundledFontCatalog.catalog(in: $0) }),
           !catalog.resources.resolver.family(family).isEmpty { return catalog }
        return .shared
    }

    private func suppliedFamily(_ provider: FixedFontProvider, bundle: Bundle?,
                                traits: FontResourceResolver.Traits) -> FontDescriptor {
        FontDescriptor(source: .family(suppliedCatalog(provider, bundle: bundle),
                                      provider.selection!.variation.metadata.familyName ?? "", traits),
            pointSize: pointSize, shapingFeatures: shapingFeatures, renderingMode: renderingMode,
            language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio,
            stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
    }

    private func suppliedVariant(_ provider: FixedFontProvider, bundle: Bundle?,
                                 trait: UInt32, active: Bool) -> FontDescriptor {
        let selection = provider.selection!
        if (selection.traits.symbolic & trait != 0) == active { return self }
        var requested = selection.traits
        requested.symbolic = ((requested.symbolic & ~trait) | (active ? trait : 0)) & ~0x18000
        requested.weight = trait == 2 ? (active ? Font.Weight.bold.value : 0) : selection.traits.weight
        let catalog = suppliedCatalog(provider, bundle: bundle)
        let candidates = catalog.resources.resolver.family(selection.variation.metadata.familyName ?? "").filter {
            $0.traits.symbolic & 0x0fff_bbff == requested.symbolic & 0x0fff_bbff
        }
        let candidate = FontResourceResolver.selectSymbolicVariant(candidates, from: selection, weight: requested.weight)
        let attributes: [UInt32: CGFloat]?
        let replacement: [UInt32: CGFloat]
        if let candidate {
            replacement = candidate.comparisonCoordinates
            attributes = candidate.variationSelection.descriptorVariation
        } else {
            guard let copied = FontResourceResolver.symbolicWeightVariation(from: selection,
                                                                            weight: requested.weight) else { return self }
            replacement = copied
            attributes = copied.isEmpty ? nil : copied
        }
        let direct = variation == nil || variation == attributes
        let size = direct && !preservesSizeOnSymbolicCopy ? 12 : pointSize
        let copiedVariation = direct ? attributes : attributes.map { values in
            (variation ?? [:]).merging(values) { _, new in new }
        } ?? variation
        let copiedSource: Source
        if let candidate {
            copiedSource = .selected(catalog, candidate, nil)
        } else if direct {
            guard let copy = provider.copying(pointSize: size, comparison: replacement) else {
                preconditionFailure("A supplied font must preserve its loaded source during variant copying.")
            }
            copiedSource = .supplied(copy, bundle)
        } else {
            copiedSource = .named(provider.face.selectedFont?.descriptor.postScriptName ?? "", bundle)
        }
        let descriptor = FontDescriptor(source: copiedSource, pointSize: size,
            shapingFeatures: direct ? [] : shapingFeatures, renderingMode: renderingMode,
            language: direct ? nil : language,
            languageAwareLineHeightRatio: direct ? nil : languageAwareLineHeightRatio,
            stylePolicy: direct ? nil : stylePolicy, variation: copiedVariation,
            preservesSizeOnSymbolicCopy: preservesSizeOnSymbolicCopy,
            hasPointSizeAttribute: direct ? preservesSizeOnSymbolicCopy && hasPointSizeAttribute : hasPointSizeAttribute)
        if direct, let candidate {
            descriptor.resolution = descriptor.realized(candidate, in: catalog, variation: .init(
                coordinates: candidate.coordinates, comparison: replacement, extras: attributes))
        }
        return descriptor
    }

    func leading(_ leading: Font.Leading) -> FontDescriptor {
        // Each copy consumes the descriptor selected by the preceding operation.
        switch leading {
        case .standard:
            symbolicTrait(0x10000, active: false).symbolicTrait(0x8000, active: false)
        case .tight:
            symbolicTrait(0x10000, active: false).symbolicTrait(0x8000, active: true)
        case .loose:
            symbolicTrait(0x8000, active: false).symbolicTrait(0x10000, active: true)
        }
    }

    func monospaced(_ active: Bool) -> FontDescriptor {
        guard active else { return self }
        switch source {
        case let .system(_, weight, italic, width, textStyle):
            return FontDescriptor(source: .system(.monospaced, weight, italic, width: width, textStyle: textStyle),
                                  pointSize: pointSize, shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
        case let .typeface(provider):
            if let system = provider as? SystemFontProvider {
                return FontDescriptor(source: .typeface(SystemFontProvider(
                    size: pointSize, weight: system.weight,
                    design: .monospaced,
                    renderingMode: system.renderingMode, isItalic: system.isItalic, width: system.width
                )), pointSize: pointSize, shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
            }
            if let external = provider as? ExternalFontProvider {
                return FontDescriptor(source: .typeface(ExternalFontProvider(
                    source: external.source, size: pointSize, weight: external.weight,
                    design: .monospaced,
                    faceIndex: external.faceIndex, renderingMode: external.renderingMode
                )), pointSize: pointSize, shapingFeatures: shapingFeatures, renderingMode: renderingMode,
                                  language: language, languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation, hasPointSizeAttribute: hasPointSizeAttribute)
            }
            return self
        default:
            return self
        }
    }

    private func symbolicWeight(_ weight: Font.Weight, active: Bool) -> Font.Weight {
        if active { return weight == .regular ? .bold : weight }
        return weight.value >= Font.Weight.semibold.value ? .regular : weight
    }

    private var retainedTraits: FontResourceResolver.Traits? {
        switch source {
        case let .family(_, _, traits), let .selected(_, _, traits?): traits
        default: nil
        }
    }

    func adding(features: [TypefaceShapingFeature]) -> FontDescriptor {
        var copied = resolution?.usesVariationBase == true ? resolution : nil
        if copied == nil, let resolution, let catalog = resolution.catalog,
           let optical = (resolution.provider as? BundledFontProvider)?.opticalConstruction,
           let name = optical.postScriptName, let candidate = catalog.resources.resolver.named(name) {
            // Feature copying reconstructs the current selected name, retaining
            // derived descriptor identity without inventing an explicit axis request.
            copied = realized(candidate, in: catalog, derivesOpticalSize: optical.derivesOpticalSize)
        }
        return FontDescriptor(source: source, pointSize: pointSize, shapingFeatures: shapingFeatures + features,
                       renderingMode: renderingMode, language: language,
                       languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation,
                       resolution: copied, preservesSizeOnSymbolicCopy: preservesSizeOnSymbolicCopy, hasPointSizeAttribute: hasPointSizeAttribute)
    }

    func clearFeatures() -> FontDescriptor {
        FontDescriptor(source: source, pointSize: pointSize,
                       renderingMode: renderingMode, language: language,
                       languageAwareLineHeightRatio: languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation,
                       resolution: resolution,
                       preservesSizeOnSymbolicCopy: preservesSizeOnSymbolicCopy || hasInitializedSelection, hasPointSizeAttribute: hasPointSizeAttribute)
    }

    func withTypesetting(language: String? = nil, lineHeightRatio: Double? = nil) -> FontDescriptor {
        guard language != nil || lineHeightRatio != nil else { return self }
        let copiedSource: Source
        if lineHeightRatio != nil, case let .supplied(provider, bundle) = source {
            // Ratio attributes invalidate the supplied base. The original name
            // is rematched without turning physical coordinates into requests.
            copiedSource = .named(provider.face.selectedFont?.descriptor.postScriptName ?? "", bundle)
        } else {
            copiedSource = source
        }
        return FontDescriptor(source: copiedSource, pointSize: pointSize, shapingFeatures: shapingFeatures,
                       renderingMode: renderingMode, language: language ?? self.language,
                       languageAwareLineHeightRatio: lineHeightRatio ?? languageAwareLineHeightRatio, stylePolicy: stylePolicy, variation: variation,
                       resolution: lineHeightRatio == nil && resolution?.usesVariationBase == true ? resolution : nil,
                       preservesSizeOnSymbolicCopy: preservesSizeOnSymbolicCopy || hasInitializedSelection, hasPointSizeAttribute: hasPointSizeAttribute)
    }

    private func resolve() -> Resolution {
        if let resolution { return resolution }
        let resolved: Resolution
        switch source {
        case let .supplied(provider, _):
            resolved = Resolution(provider: provider, weight: provider.selection!.traits.weight,
                                  catalog: nil, candidate: nil)
        case let .system(design, weight, italic, width, _):
            let provider = SystemFontProvider(size: pointSize, weight: weight, design: design,
                                               isItalic: italic, width: width.map(Font.Width.init))
            resolved = Resolution(provider: provider, weight: CGFloat(Float(weight.value)), catalog: nil, candidate: nil)
        case let .typeface(provider):
            let weight = (provider as? SystemFontProvider)?.weight.value ??
                (provider as? BundledFontProvider)?.weight.value ??
                (provider as? ExternalFontProvider)?.weight.value ?? 0
            resolved = Resolution(provider: provider, weight: weight, catalog: nil, candidate: nil)
        case let .named(name, bundle):
            let catalogs = bundle.flatMap { BundledFontCatalog.catalog(in: $0) }.map { [$0, .shared] } ?? [.shared]
            var match: (BundledFontCatalog, FontResourceResolver.Candidate)?
            for catalog in catalogs {
                if let candidate = catalog.resources.resolver.named(name) {
                    match = (catalog, candidate)
                    break
                }
            }
            if let (catalog, candidate) = match {
                resolved = realized(candidate, in: catalog)
            } else {
                resolved = defaultResolution()
            }
        case let .family(catalog, name, traits):
            if let candidate = FontResourceResolver.select(catalog.resources.resolver.family(name), matching: traits) {
                resolved = realized(candidate, in: catalog)
            } else {
                resolved = defaultResolution()
            }
        case let .selected(catalog, candidate, traits):
            let matching = candidate.variationSelection.postScriptName.flatMap { name in
                traits == nil ? catalog.resources.resolver.named(name)
                    : catalog.resources.resolver.named(name, inFamily: candidate.family)
            }
            if let matching {
                resolved = realized(matching, in: catalog)
            } else {
                resolved = defaultResolution()
            }
        }
        resolution = resolved
        return resolved
    }

    private func defaultResolution() -> Resolution {
        let catalog = BundledFontCatalog.shared
        let configuration = catalog.configuration
        let resource = catalog.resource(for: configuration.systemFont(for: .default),
                                        locale: Locale(identifier: configuration.defaultLocale))
        let candidates = catalog.resources.resolver.candidates.filter { $0.face.resource == resource }
        guard let candidate = FontResourceResolver.select(candidates, matching: .init(symbolic: 0, weight: 0, width: 0, slant: 0)) else {
            return Resolution(provider: SystemFontProvider(size: pointSize, weight: .regular, design: .default),
                              weight: 0, catalog: nil, candidate: nil, didMatchRequest: false)
        }
        // A failed match initializes the default face independently of the
        // original request, whose variation remains an extra for later copies.
        let selection = candidate.variationSelection
        var result = realized(candidate, in: catalog, variation: .init(
            coordinates: selection.coordinates,
            comparison: selection.comparisonCoordinates(requested: [:]), extras: variation))
        result.didMatchRequest = false
        return result
    }

    private func realized(_ candidate: FontResourceResolver.Candidate, in catalog: BundledFontCatalog,
                          variation resolvedVariation: FontVariationSelection.Resolved? = nil,
                          derivesOpticalSize: Bool = false) -> Resolution {
        // A preselected default carries extras without creating a variation base.
        let mergesVariation = resolvedVariation == nil
        var resolvedVariation = resolvedVariation ?? candidate.variationSelection.resolved(requested: variation ?? [:])
        let usesVariationBase = mergesVariation && resolvedVariation.extras != nil
        if mergesVariation {
            // Matching can remove defaults or merge the selected axes. Final
            // construction retains the original request independently, including
            // an explicitly empty dictionary and values omitted by matching.
            resolvedVariation = .init(coordinates: resolvedVariation.coordinates,
                                     comparison: resolvedVariation.comparison, extras: variation)
        }
        let selection = FontVariationSelection(metadata: candidate.face.metadata, coordinates: resolvedVariation.coordinates)
        let selected = candidate.selecting(selection, comparison: resolvedVariation.comparison)
        let requests = variation.map { values in
            values.sorted { $0.key < $1.key }.map { BundledFontVariation(tag: $0.key, value: $0.value) }
        } ?? candidate.variations
        return Resolution(provider: BundledFontProvider(
            resource: candidate.face.resource, size: pointSize,
            weight: Font.Weight(value: selected.traits.weight), renderingMode: .automatic,
            variations: requests, appliesSyntheticWeight: false,
            instanceIndex: candidate.instanceIndex, resolvedVariation: resolvedVariation,
            opticalConstruction: FontOpticalConstruction(metadata: candidate.face.metadata,
                resolved: resolvedVariation, derivesOpticalSize: derivesOpticalSize)?.withSize(pointSize)
        ), weight: selected.traits.weight, catalog: catalog, candidate: selected,
            usesVariationBase: usesVariationBase)
    }
}

// Definition metatypes are shared through font resolution contexts.
protocol FontDefinition: SendableMetatype {
    static func resolveTextStyleFont(textStyle: Font.TextStyle, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> FontDescriptor
    static func resolveTextStyleFontInfo(textStyle: Font.TextStyle, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> Font.ResolvedTraits
    static func resolveSystemFont(size: CGFloat, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> FontDescriptor
    static func resolveCustomFont(name: String, size: CGFloat, textStyle: Font.TextStyle?, in context: Font.Context) -> FontDescriptor
}

enum DefaultFontDefinition: FontDefinition {}

extension FontDefinition {
    static func resolveTextStyleFont(textStyle: Font.TextStyle, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> FontDescriptor {
        FontDescriptor(source: .system(design ?? .default, weight ?? Font.weight(for: textStyle), false,
                                       textStyle: textStyle), pointSize: Font.pointSize(for: textStyle),
                       stylePolicy: FontStylePolicy(style: textStyle))
    }

    static func resolveTextStyleFontInfo(textStyle: Font.TextStyle, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> Font.ResolvedTraits {
        Font.ResolvedTraits(pointSize: Font.pointSize(for: textStyle),
                            weight: weight?.value ?? CGFloat(Float(Font.weight(for: textStyle).value)))
    }

    static func resolveSystemFont(size: CGFloat, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> FontDescriptor {
        FontDescriptor(source: .system(design ?? .default, weight ?? .regular, false), pointSize: size)
    }

    static func resolveCustomFont(name: String, size: CGFloat, textStyle: Font.TextStyle?, in context: Font.Context) -> FontDescriptor {
        FontDescriptor(source: .named(name, context.resourceBundle), pointSize: textStyle == nil ? size : size.rounded())
    }
}
