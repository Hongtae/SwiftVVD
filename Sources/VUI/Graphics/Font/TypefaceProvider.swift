//
//  File: TypefaceProvider.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

protocol TypefaceProvider {
    func isEqual(to: any TypefaceProvider) -> Bool
    func hash(into hasher: inout Hasher)
    func resolved(in environment: EnvironmentValues) -> Self

    func makeTypeface(
        _: AppContext,
        dpi: UInt32
    ) -> Typeface?

    var isShareable: Bool { get }
    var pointSize: CGFloat { get }
    var shapingFeatures: [TypefaceShapingFeature] { get }
}

extension TypefaceProvider {
    var isShareable: Bool { true }
    var shapingFeatures: [TypefaceShapingFeature] { [] }

    func resolved(in environment: EnvironmentValues) -> Self {
        self
    }
}

var defaultFontURL: URL? {
    let catalog = BundledFontCatalog.shared
    let configuration = catalog.configuration
    return catalog.resource(
        for: configuration.systemFont(for: .default),
        locale: Locale(identifier: configuration.defaultLocale)
    )?.url
}

var defaultItalicFontURL: URL? {
    let catalog = BundledFontCatalog.shared
    let configuration = catalog.configuration
    return catalog.resource(
        for: configuration.systemFont(for: .default),
        locale: Locale(identifier: configuration.defaultLocale),
        isItalic: true
    )?.url
}

struct BundledFontResource: Hashable, Sendable {
    let url: URL
    let faceIndex: Int

    init(url: URL, faceIndex: Int = 0) {
        precondition(faceIndex >= 0, "The font face index must not be negative.")
        self.url = url
        self.faceIndex = faceIndex
    }
}

struct BundledFontVariation: Hashable, Sendable {
    let tag: UInt32
    let value: CGFloat
}

let defaultDPI = 72

struct SystemFontProvider: TypefaceProvider {
    var pointSize: CGFloat { size }
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let renderingMode: Font.RenderingMode
    let isItalic: Bool
    let width: Font.Width?

    init(size: CGFloat,
         weight: Font.Weight,
         design: Font.Design,
         renderingMode: Font.RenderingMode = .automatic,
         isItalic: Bool = false,
         width: Font.Width? = nil) {
        self.size = size
        self.weight = weight
        self.design = design
        self.renderingMode = renderingMode
        self.isItalic = isItalic
        self.width = width
    }

    static func embolden(for weight: Font.Weight) -> CGFloat {
        let emboldenFactor = 1.0
        return ((weight.weightClass - 400.0) / 300.0) * emboldenFactor
    }

    func resolved(in environment: EnvironmentValues) -> Self {
        guard case .automatic = renderingMode else {
            return self
        }

        let renderingMode: Font.RenderingMode
        switch environment.defaultFontRenderingMode {
        case let .bitmap(options):
            renderingMode = .bitmap(options)
        case let .vector(options):
            renderingMode = .vector(options)
        }

        return Self(size: size,
                    weight: weight,
                    design: design,
                    renderingMode: renderingMode,
                    isItalic: isItalic,
                    width: width)
    }

    func isEqual(to: any TypefaceProvider) -> Bool {
        if let other = to as? Self {
            return self.size == other.size &&
                   self.weight == other.weight &&
                   self.design == other.design &&
                   self.renderingMode == other.renderingMode &&
                   self.isItalic == other.isItalic &&
                   self.width == other.width
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(size)
        hasher.combine(weight)
        hasher.combine(design)
        hasher.combine(renderingMode)
        hasher.combine(isItalic)
        hasher.combine(width)
    }

    func makeTypeface(
        _ context: AppContext,
        dpi: UInt32
    ) -> Typeface? {
        let catalog = BundledFontCatalog.shared
        let configuration = catalog.configuration
        guard let provider = BundledFontProvider(
            family: configuration.systemFont(for: design),
            locale: Locale(identifier: configuration.defaultLocale),
            size: size,
            weight: weight,
            renderingMode: renderingMode,
            isItalic: isItalic,
            catalog: catalog,
            width: width
        ) else { return nil }
        return provider.makeTypeface(context, dpi: dpi)
    }
}

struct BundledFontProvider: TypefaceProvider {
    var pointSize: CGFloat { size }
    let resource: BundledFontResource
    let instanceIndex: Int?
    let size: CGFloat
    let weight: Font.Weight
    let renderingMode: Font.RenderingMode
    let variations: [BundledFontVariation]
    let appliesSyntheticWeight: Bool

    init(
        resource: BundledFontResource,
        size: CGFloat,
        weight: Font.Weight,
        renderingMode: Font.RenderingMode,
        variations: [BundledFontVariation] = [],
        appliesSyntheticWeight: Bool = true,
        instanceIndex: Int? = nil
    ) {
        self.resource = resource
        self.instanceIndex = instanceIndex
        self.size = size
        self.weight = weight
        self.renderingMode = renderingMode
        self.variations = variations
        self.appliesSyntheticWeight = appliesSyntheticWeight
    }

    init?(
        family: BundledFontID,
        locale: Locale,
        size: CGFloat,
        weight: Font.Weight,
        renderingMode: Font.RenderingMode,
        isItalic: Bool,
        catalog: BundledFontCatalog,
        width: Font.Width? = nil
    ) {
        guard let descriptor = catalog.configuration.fontDescriptors[family],
              let resource = catalog.resource(
                for: family,
                locale: locale,
                weight: weight.weightClass,
                isItalic: isItalic
              ) else {
            return nil
        }
        let source = descriptor.source(
            for: weight.weightClass,
            isItalic: isItalic
        )
        var variations: [BundledFontVariation]
        if let weightAxis = source.weightAxis {
            variations = [BundledFontVariation(
                tag: weightAxis.tag,
                value: min(
                    max(weight.weightClass, weightAxis.minimum),
                    weightAxis.maximum
                )
            )]
        } else {
            variations = []
        }
        if let width {
            let candidates = catalog.resources.resolver.candidates.filter { $0.face.resource == resource }
            if var traits = candidates.first?.traits {
                traits.weight = weight.value
                traits.width = width.value
                if let candidate = FontResourceResolver.select(candidates, matching: traits) {
                    // Keep the configured weight policy and use an available width instance.
                    variations += candidate.variations.filter { $0.tag == 0x7764_7468 }
                }
            }
        }
        self.init(
            resource: resource,
            size: size,
            weight: weight,
            renderingMode: renderingMode,
            variations: variations,
            appliesSyntheticWeight: descriptor.appliesSyntheticWeight
        )
    }

    func resolved(in environment: EnvironmentValues) -> Self {
        guard case .automatic = renderingMode else {
            return self
        }

        let renderingMode: Font.RenderingMode
        switch environment.defaultFontRenderingMode {
        case let .bitmap(options):
            renderingMode = .bitmap(options)
        case let .vector(options):
            renderingMode = .vector(options)
        }
        return Self(
            resource: resource,
            size: size,
            weight: weight,
            renderingMode: renderingMode,
            variations: variations,
            appliesSyntheticWeight: appliesSyntheticWeight,
            instanceIndex: instanceIndex
        )
    }

    func isEqual(to: any TypefaceProvider) -> Bool {
        guard let other = to as? Self else { return false }
        return resource == other.resource &&
            instanceIndex == other.instanceIndex &&
            size == other.size &&
            weight == other.weight &&
            renderingMode == other.renderingMode &&
            variations == other.variations &&
            appliesSyntheticWeight == other.appliesSyntheticWeight
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(resource)
        hasher.combine(instanceIndex)
        hasher.combine(size)
        hasher.combine(weight)
        hasher.combine(renderingMode)
        hasher.combine(variations)
        hasher.combine(appliesSyntheticWeight)
    }

    func makeTypeface(
        _ context: AppContext,
        dpi: UInt32
    ) -> Typeface? {
        precondition(dpi > 0, "The font DPI must be positive.")
        let contentScaleFactor = CGFloat(dpi) / CGFloat(defaultDPI)
        var data = context.resourceData(forURL: resource.url)
        if data == nil {
            do {
                Log.debug("Loading font resource: \(resource.url)")
                let loaded = try Data(contentsOf: resource.url, options: [])
                data = loaded.makeFixedAddressStorage()
                if let data {
                    context.setResource(data: data, forURL: resource.url)
                }
            } catch {
                Log.error("Error on loading data: \(error)")
            }
        }
        guard let data else { return nil }

        let logicalEmbolden = appliesSyntheticWeight
            ? SystemFontProvider.embolden(for: weight)
            : 0
        guard let layoutFont = VVD.Font(
            data: data,
            faceIndex: resource.faceIndex
        ) else { return nil }
        guard applyVariations(to: layoutFont) else { return nil }
        layoutFont.setPointSize(
            size,
            dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
        )
        if layoutFont.hasColor {
            let options: Font.RenderingMode.Bitmap
            switch renderingMode {
            case .automatic: fatalError("Unresolved font rendering mode")
            case let .bitmap(value): options = value
            case let .vector(value): options = .init(outlineThickness: value.outlineThickness)
            }
            let metrics = VectorTypeface(
                font: layoutFont, layoutFont: layoutFont,
                renderScale: contentScaleFactor, logicalEmbolden: logicalEmbolden
            )
            let device = context.graphicsDeviceContext
            return DeferredGlyphTypeface(metrics: metrics) {
                guard let device,
                      let font = VVD.TextureFont(deviceContext: device, data: data,
                                                 faceIndex: resource.faceIndex),
                      applyVariations(to: font) else { return nil }
                font.boldStrength = logicalEmbolden * contentScaleFactor
                font.outlineThickness = options.outlineThickness * contentScaleFactor
                font.isBitmapPreferred = options.isBitmapPreferred
                font.isColorEnabled = options.isColorEnabled
                font.setPointSize(size, dpi: (dpi, dpi))
                return TextureTypeface(textureFont: font, layoutFont: layoutFont,
                                       renderScale: contentScaleFactor,
                                       logicalEmbolden: logicalEmbolden)
            }
        }
        switch renderingMode {
        case .automatic:
            fatalError("Unresolved font rendering mode")
        case let .bitmap(options):
            guard let device = context.graphicsDeviceContext,
                  let font = VVD.TextureFont(
                    deviceContext: device,
                    data: data,
                    faceIndex: resource.faceIndex
                  ) else {
                return nil
            }
            guard applyVariations(to: font) else { return nil }
            font.boldStrength = logicalEmbolden * contentScaleFactor
            font.outlineThickness =
                options.outlineThickness * contentScaleFactor
            font.isBitmapPreferred = options.isBitmapPreferred
            font.isColorEnabled = options.isColorEnabled
            font.setPointSize(size, dpi: (dpi, dpi))
            return TextureTypeface(
                textureFont: font,
                layoutFont: layoutFont,
                renderScale: contentScaleFactor,
                logicalEmbolden: logicalEmbolden
            )
        case let .vector(options):
            guard let font = VVD.Font(
                data: data,
                faceIndex: resource.faceIndex
            ) else { return nil }
            guard applyVariations(to: font) else { return nil }
            font.setPointSize(size, dpi: (dpi, dpi))
            return VectorTypeface(
                font: font,
                embolden: logicalEmbolden * contentScaleFactor,
                outlineThickness:
                    options.outlineThickness * contentScaleFactor,
                layoutFont: layoutFont,
                renderScale: contentScaleFactor,
                logicalEmbolden: logicalEmbolden
            )
        }
    }

    private func applyVariations(to font: VVD.Font) -> Bool {
        guard !variations.isEmpty else { return true }
        return font.setVariationCoordinates(
            Dictionary(uniqueKeysWithValues: variations.map {
                ($0.tag, $0.value)
            })
        )
    }
}

final class ExternalFontData: @unchecked Sendable {
    let storage: any FixedAddressStorageData

    init(_ data: Data) {
        self.storage = data.makeFixedAddressStorage()
    }
}

enum ExternalFontSource: Hashable, @unchecked Sendable {
    case file(URL)
    case data(ExternalFontData)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.file(lhs), .file(rhs)):
            return lhs == rhs
        case let (.data(lhs), .data(rhs)):
            return lhs === rhs
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .file(url):
            hasher.combine(0)
            hasher.combine(url)
        case let .data(data):
            hasher.combine(1)
            hasher.combine(ObjectIdentifier(data))
        }
    }

    func makeFont(faceIndex: Int) -> VVD.Font? {
        switch self {
        case let .file(url):
            guard url.isFileURL else {
                Log.error("Font.file requires a local file URL: \(url)")
                return nil
            }
            return VVD.Font(
                path: url.standardizedFileURL.path,
                faceIndex: faceIndex
            )
        case let .data(data):
            return VVD.Font(data: data.storage, faceIndex: faceIndex)
        }
    }

    func makeTextureFont(
        deviceContext: GraphicsDeviceContext,
        faceIndex: Int
    ) -> VVD.TextureFont? {
        switch self {
        case let .file(url):
            guard url.isFileURL else {
                Log.error("Font.file requires a local file URL: \(url)")
                return nil
            }
            return VVD.TextureFont(
                deviceContext: deviceContext,
                path: url.standardizedFileURL.path,
                faceIndex: faceIndex
            )
        case let .data(data):
            return VVD.TextureFont(
                deviceContext: deviceContext,
                data: data.storage,
                faceIndex: faceIndex
            )
        }
    }
}

struct ExternalFontProvider: TypefaceProvider {
    var pointSize: CGFloat { size }
    private static let weightVariationTag: UInt32 = 0x7767_6874

    let source: ExternalFontSource
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let faceIndex: Int
    let renderingMode: Font.RenderingMode

    func resolved(in environment: EnvironmentValues) -> Self {
        guard case .automatic = renderingMode else {
            return self
        }

        let renderingMode: Font.RenderingMode
        switch environment.defaultFontRenderingMode {
        case let .bitmap(options):
            renderingMode = .bitmap(options)
        case let .vector(options):
            renderingMode = .vector(options)
        }
        return Self(
            source: source,
            size: size,
            weight: weight,
            design: design,
            faceIndex: faceIndex,
            renderingMode: renderingMode
        )
    }

    func isEqual(to: any TypefaceProvider) -> Bool {
        guard let other = to as? Self else { return false }
        return source == other.source &&
            size == other.size &&
            weight == other.weight &&
            design == other.design &&
            faceIndex == other.faceIndex &&
            renderingMode == other.renderingMode
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(source)
        hasher.combine(size)
        hasher.combine(weight)
        hasher.combine(design)
        hasher.combine(faceIndex)
        hasher.combine(renderingMode)
    }

    func makeTypeface(
        _ context: AppContext,
        dpi: UInt32
    ) -> Typeface? {
        precondition(dpi > 0, "The font DPI must be positive.")
        let contentScaleFactor = CGFloat(dpi) / CGFloat(defaultDPI)
        guard let layoutFont = source.makeFont(faceIndex: faceIndex),
              applyRequestedWeight(to: layoutFont) else {
            return nil
        }
        let usesVariableWeight = layoutFont.variationAxes.contains {
            $0.tag == Self.weightVariationTag
        }
        let requestedWeight = weight.value.isFinite
            ? weight
            : .regular
        let logicalEmbolden = usesVariableWeight
            ? 0
            : SystemFontProvider.embolden(for: requestedWeight)
        layoutFont.setPointSize(
            size,
            dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
        )

        switch renderingMode {
        case .automatic:
            fatalError("Unresolved font rendering mode")
        case let .bitmap(options):
            guard let device = context.graphicsDeviceContext,
                  let font = source.makeTextureFont(
                    deviceContext: device,
                    faceIndex: faceIndex
                  ),
                  applyRequestedWeight(to: font) else {
                return nil
            }
            font.boldStrength = logicalEmbolden * contentScaleFactor
            font.outlineThickness =
                options.outlineThickness * contentScaleFactor
            font.isBitmapPreferred = options.isBitmapPreferred
            font.isColorEnabled = options.isColorEnabled
            font.setPointSize(size, dpi: (dpi, dpi))
            return TextureTypeface(
                textureFont: font,
                layoutFont: layoutFont,
                renderScale: contentScaleFactor,
                logicalEmbolden: logicalEmbolden
            )
        case let .vector(options):
            guard let font = source.makeFont(faceIndex: faceIndex),
                  applyRequestedWeight(to: font) else {
                return nil
            }
            font.setPointSize(size, dpi: (dpi, dpi))
            return VectorTypeface(
                font: font,
                embolden: logicalEmbolden * contentScaleFactor,
                outlineThickness:
                    options.outlineThickness * contentScaleFactor,
                layoutFont: layoutFont,
                renderScale: contentScaleFactor,
                logicalEmbolden: logicalEmbolden
            )
        }
    }

    private func applyRequestedWeight(to font: VVD.Font) -> Bool {
        guard let axis = font.variationAxes.first(where: {
            $0.tag == Self.weightVariationTag
        }) else {
            return true
        }
        let requested = weight.weightClass
        let value = min(
            max(requested, axis.minimumValue),
            axis.maximumValue
        )
        return font.setVariationCoordinates([
            Self.weightVariationTag: value
        ])
    }
}

struct FixedFontProvider: TypefaceProvider {
    let face: any Typeface
    var pointSize: CGFloat { face.lineHeight }

    init(_ face: any Typeface) {
        self.face = face
    }

    var identifier: String {
        face.identifier
    }

    func isEqual(to: any TypefaceProvider) -> Bool {
        if let other = to as? Self {
            return self.face.isEqual(to: other.face)
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        face.hashIdentity(into: &hasher)
    }

    func makeTypeface(
        _: AppContext,
        dpi: UInt32
    ) -> Typeface? {
        self.face
    }

    var isShareable: Bool { false }
}
