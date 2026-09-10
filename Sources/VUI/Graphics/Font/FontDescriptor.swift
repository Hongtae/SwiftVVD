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
        case system(Font.Design, Font.Weight, Bool)
        case named(String, Bundle?)
        case family(BundledFontCatalog, String, FontResourceResolver.Traits)
        case selected(BundledFontCatalog, FontResourceResolver.Candidate, FontResourceResolver.Traits?)
        case typeface(any TypefaceProvider)
    }

    struct Resolution {
        let provider: any TypefaceProvider
        let weight: CGFloat
        let catalog: BundledFontCatalog?
        let candidate: FontResourceResolver.Candidate?
    }

    let source: Source
    let pointSize: CGFloat
    let shapingFeatures: [TypefaceShapingFeature]
    // Each consumer owns its descriptor; only catalog snapshots are shared across threads.
    private var resolution: Resolution?

    init(source: Source, pointSize: CGFloat, shapingFeatures: [TypefaceShapingFeature] = []) {
        self.source = source
        self.pointSize = pointSize
        self.shapingFeatures = shapingFeatures
    }

    var resolvedWeight: CGFloat { resolve().weight }

    func typefaceProvider(in environment: EnvironmentValues) -> any TypefaceProvider {
        resolve().provider.resolved(in: environment)
    }

    func weight(_ weight: Font.Weight) -> FontDescriptor {
        switch source {
        case let .system(design, _, italic):
            return FontDescriptor(source: .system(design, weight, italic), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures)
        case let .family(catalog, name, current):
            var traits = current
            traits.weight = weight.value
            return FontDescriptor(source: .family(catalog, name, traits), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures)
        case let .typeface(provider):
            if let system = provider as? SystemFontProvider {
                return FontDescriptor(source: .typeface(SystemFontProvider(
                    size: pointSize, weight: weight, design: system.design,
                    renderingMode: system.renderingMode, isItalic: system.isItalic
                )), pointSize: pointSize, shapingFeatures: shapingFeatures)
            }
            if let external = provider as? ExternalFontProvider {
                return FontDescriptor(source: .typeface(ExternalFontProvider(
                    source: external.source, size: pointSize, weight: weight, design: external.design,
                    faceIndex: external.faceIndex, renderingMode: external.renderingMode
                )), pointSize: pointSize, shapingFeatures: shapingFeatures)
            }
            return self
        default:
            let resolved = resolve()
            guard let catalog = resolved.catalog, let candidate = resolved.candidate else { return self }
            var traits = retainedTraits ?? candidate.traits
            traits.weight = weight.value
            return FontDescriptor(source: .family(catalog, candidate.family, traits), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures)
        }
    }

    func symbolicTrait(_ trait: UInt32, active: Bool) -> FontDescriptor {
        switch source {
        case let .system(design, weight, italic):
            let nextWeight = trait == 2 ? symbolicWeight(weight, active: active) : weight
            return FontDescriptor(source: .system(design, nextWeight, trait == 1 ? active : italic),
                                  pointSize: pointSize, shapingFeatures: shapingFeatures)
        case let .typeface(provider):
            guard let system = provider as? SystemFontProvider else { return self }
            let nextWeight = trait == 2 ? symbolicWeight(system.weight, active: active) : system.weight
            return FontDescriptor(source: .typeface(SystemFontProvider(
                size: pointSize, weight: nextWeight, design: system.design,
                renderingMode: system.renderingMode, isItalic: trait == 1 ? active : system.isItalic
            )), pointSize: pointSize, shapingFeatures: shapingFeatures)
        default:
            let resolved = resolve()
            guard let catalog = resolved.catalog, let candidate = resolved.candidate else { return self }
            if (candidate.traits.symbolic & trait != 0) == active { return self }
            var requested = candidate.traits
            if trait == 2 { requested.weight = active ? Font.Weight.bold.value : 0 }
            let candidates = catalog.resources.resolver.family(candidate.family).filter {
                ($0.traits.symbolic & trait != 0) == active
            }
            guard let selected = FontResourceResolver.select(candidates, matching: requested) else { return self }
            return FontDescriptor(source: .selected(catalog, selected, retainedTraits), pointSize: pointSize,
                                  shapingFeatures: shapingFeatures)
        }
    }

    func monospaced(_ active: Bool) -> FontDescriptor {
        guard active else { return self }
        switch source {
        case let .system(_, weight, italic):
            return FontDescriptor(source: .system(.monospaced, weight, italic),
                                  pointSize: pointSize, shapingFeatures: shapingFeatures)
        case let .typeface(provider):
            if let system = provider as? SystemFontProvider {
                return FontDescriptor(source: .typeface(SystemFontProvider(
                    size: pointSize, weight: system.weight,
                    design: .monospaced,
                    renderingMode: system.renderingMode, isItalic: system.isItalic
                )), pointSize: pointSize, shapingFeatures: shapingFeatures)
            }
            if let external = provider as? ExternalFontProvider {
                return FontDescriptor(source: .typeface(ExternalFontProvider(
                    source: external.source, size: pointSize, weight: external.weight,
                    design: .monospaced,
                    faceIndex: external.faceIndex, renderingMode: external.renderingMode
                )), pointSize: pointSize, shapingFeatures: shapingFeatures)
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
        FontDescriptor(source: source, pointSize: pointSize, shapingFeatures: shapingFeatures + features)
    }

    private func resolve() -> Resolution {
        if let resolution { return resolution }
        let resolved: Resolution
        switch source {
        case let .system(design, weight, italic):
            let provider = SystemFontProvider(size: pointSize, weight: weight, design: design, isItalic: italic)
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
                let catalog = BundledFontCatalog.shared
                let configuration = catalog.configuration
                let resource = catalog.resource(for: configuration.systemFont(for: .default),
                                                locale: Locale(identifier: configuration.defaultLocale))
                let candidates = catalog.resources.resolver.candidates.filter { $0.face.resource == resource }
                if let candidate = FontResourceResolver.select(candidates, matching: .init(symbolic: 0, weight: 0, width: 0, slant: 0)) {
                    resolved = realized(candidate, in: catalog)
                } else {
                    resolved = Resolution(provider: SystemFontProvider(size: pointSize, weight: .regular, design: .default),
                                          weight: 0, catalog: nil, candidate: nil)
                }
            }
        case let .family(catalog, name, traits):
            guard let candidate = FontResourceResolver.select(catalog.resources.resolver.family(name), matching: traits) else {
                preconditionFailure("A resolved font family must retain its candidates.")
            }
            resolved = realized(candidate, in: catalog)
        case let .selected(catalog, candidate, _):
            resolved = realized(candidate, in: catalog)
        }
        resolution = resolved
        return resolved
    }

    private func realized(_ candidate: FontResourceResolver.Candidate, in catalog: BundledFontCatalog) -> Resolution {
        Resolution(provider: BundledFontProvider(
            resource: candidate.face.resource, size: pointSize,
            weight: Font.Weight(value: candidate.traits.weight), renderingMode: .automatic,
            variations: candidate.variations, appliesSyntheticWeight: false,
            instanceIndex: candidate.instanceIndex
        ), weight: candidate.traits.weight, catalog: catalog, candidate: candidate)
    }
}

protocol FontDefinition {
    static func resolveTextStyleFont(textStyle: Font.TextStyle, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> FontDescriptor
    static func resolveTextStyleFontInfo(textStyle: Font.TextStyle, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> Font.ResolvedTraits
    static func resolveSystemFont(size: CGFloat, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> FontDescriptor
    static func resolveCustomFont(name: String, size: CGFloat, textStyle: Font.TextStyle?, in context: Font.Context) -> FontDescriptor
}

enum DefaultFontDefinition: FontDefinition {}

extension FontDefinition {
    static func resolveTextStyleFont(textStyle: Font.TextStyle, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> FontDescriptor {
        resolveSystemFont(size: Font.pointSize(for: textStyle), design: design, weight: weight ?? Font.weight(for: textStyle), in: context)
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
