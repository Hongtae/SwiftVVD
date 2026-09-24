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
    let legibilityWeight: LegibilityWeight?
    let renderingMode: Font.RenderingMode
    let isItalic: Bool
    let width: Font.Width?

    init(size: CGFloat,
         weight: Font.Weight,
         design: Font.Design,
         legibilityWeight: LegibilityWeight? = nil,
         renderingMode: Font.RenderingMode = .automatic,
         isItalic: Bool = false,
         width: Font.Width? = nil) {
        self.size = size
        self.weight = weight
        self.design = design
        self.legibilityWeight = legibilityWeight
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
                    legibilityWeight: legibilityWeight,
                    renderingMode: renderingMode,
                    isItalic: isItalic,
                    width: width)
    }

    func isEqual(to: any TypefaceProvider) -> Bool {
        if let other = to as? Self {
            return self.size == other.size &&
                   self.weight == other.weight &&
                   self.design == other.design &&
                   self.legibilityWeight == other.legibilityWeight &&
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
        hasher.combine(legibilityWeight)
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
        let selectionWeight = legibilitySelectionWeight
        guard let provider = BundledFontProvider(
            family: configuration.systemFont(for: design),
            locale: Locale(identifier: configuration.defaultLocale),
            size: size,
            weight: selectionWeight,
            renderingMode: renderingMode,
            isItalic: isItalic,
            catalog: catalog,
            width: width
        ) else { return nil }
        return provider.makeTypeface(context, dpi: dpi)
    }

    private var legibilitySelectionWeight: Font.Weight {
        guard legibilityWeight == .bold else { return weight }
        switch design {
        case .rounded, .monospaced:
            return weight
        case .default:
            if weight == .ultraLight { return .thin }
            if weight == .thin { return .light }
            if weight == .light { return .regular }
            if weight == .regular { return .semibold }
            if weight == .medium { return .bold }
            if weight == .semibold { return .heavy }
            if weight == .bold || weight == .heavy { return .black }
            return weight
        case .serif:
            if weight == .ultraLight || weight == .thin ||
                weight == .light || weight == .regular {
                return .semibold
            }
            if weight == .medium { return .bold }
            if weight == .semibold { return .heavy }
            if weight == .bold || weight == .heavy { return .black }
            return weight
        }
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
    let resolvedVariation: FontVariationSelection.Resolved?
    let opticalConstruction: FontOpticalConstruction?

    init(
        resource: BundledFontResource,
        size: CGFloat,
        weight: Font.Weight,
        renderingMode: Font.RenderingMode,
        variations: [BundledFontVariation] = [],
        appliesSyntheticWeight: Bool = true,
        instanceIndex: Int? = nil,
        resolvedVariation: FontVariationSelection.Resolved? = nil,
        opticalConstruction: FontOpticalConstruction? = nil
    ) {
        self.resource = resource
        self.instanceIndex = instanceIndex
        self.size = size
        self.weight = weight
        self.renderingMode = renderingMode
        self.variations = variations
        self.appliesSyntheticWeight = appliesSyntheticWeight
        self.resolvedVariation = resolvedVariation
        self.opticalConstruction = opticalConstruction
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
            instanceIndex: instanceIndex,
            resolvedVariation: resolvedVariation,
            opticalConstruction: opticalConstruction
        )
    }

    func withSize(_ size: CGFloat, variationExtras: [UInt32: CGFloat]? = nil) -> Self {
        let copiedVariation: FontVariationSelection.Resolved?
        if let resolvedVariation, let variationExtras {
            copiedVariation = .init(coordinates: resolvedVariation.coordinates,
                                   comparison: resolvedVariation.comparison, extras: variationExtras)
        } else {
            copiedVariation = resolvedVariation
        }
        return Self(resource: resource, size: size, weight: weight, renderingMode: renderingMode,
             variations: variations, appliesSyntheticWeight: appliesSyntheticWeight,
             instanceIndex: instanceIndex, resolvedVariation: copiedVariation,
             opticalConstruction: opticalConstruction?.withSize(size))
    }

    func isEqual(to: any TypefaceProvider) -> Bool {
        guard let other = to as? Self else { return false }
        return resource == other.resource &&
            instanceIndex == other.instanceIndex &&
            size == other.size &&
            weight == other.weight &&
            renderingMode == other.renderingMode &&
            variations == other.variations &&
            resolvedVariation == other.resolvedVariation &&
            opticalConstruction == other.opticalConstruction &&
            appliesSyntheticWeight == other.appliesSyntheticWeight
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(resource)
        hasher.combine(instanceIndex)
        hasher.combine(size)
        hasher.combine(weight)
        hasher.combine(renderingMode)
        hasher.combine(variations)
        hasher.combine(resolvedVariation)
        hasher.combine(opticalConstruction)
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
        guard let data,
              let metadata = VVD.Font.metadata(data: data, faceIndex: resource.faceIndex) else { return nil }
        let requested = Dictionary(uniqueKeysWithValues: variations.map { ($0.tag, $0.value) })
        guard requested.values.allSatisfy(\.isFinite) else { return nil }
        let resolved = opticalConstruction?.resolved ?? resolvedVariation ?? FontVariationSelection(metadata: metadata, instanceIndex: instanceIndex)
            .resolved(requested: requested)
        guard resolved.coordinates.count == metadata.variationAxes.count,
              resolved.coordinates.allSatisfy(\.isFinite) else { return nil }
        let selection = FontVariationSelection(metadata: metadata, coordinates: resolved.coordinates)

        let logicalEmbolden = appliesSyntheticWeight
            ? SystemFontProvider.embolden(for: weight)
            : 0
        var selectedFont = SelectedFont(
            source: .file(resource.url, faceIndex: resource.faceIndex, namedInstance: instanceIndex),
            pointSize: size, variation: selection,
            comparisonCoordinates: resolved.comparison,
            syntheticWeight: logicalEmbolden)
        selectedFont.variationExtras = resolved.extras
        if let opticalConstruction {
            selectedFont.opticalConstruction = opticalConstruction
            selectedFont.descriptor.postScriptName = opticalConstruction.postScriptName
            selectedFont.descriptor.derivesOpticalSize = opticalConstruction.derivesOpticalSize
        }
        func applyVariations(to font: VVD.Font) -> Bool {
            metadata.variationAxes.isEmpty || font.setVariationCoordinates(selection.rasterCoordinates)
        }
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
                renderScale: contentScaleFactor, logicalEmbolden: logicalEmbolden,
                selectedFont: selectedFont
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
                                       logicalEmbolden: logicalEmbolden, selectedFont: selectedFont)
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
                logicalEmbolden: logicalEmbolden,
                selectedFont: selectedFont
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
                logicalEmbolden: logicalEmbolden,
                selectedFont: selectedFont
            )
        }
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
        let metadata: VVD.Font.FaceMetadata?
        let selectedSource: SelectedFont.Source
        switch source {
        case let .file(url):
            metadata = VVD.Font.metadata(path: url.path, faceIndex: faceIndex)
            selectedSource = .file(url, faceIndex: faceIndex, namedInstance: nil)
        case let .data(data):
            metadata = VVD.Font.metadata(data: data.storage, faceIndex: faceIndex)
            selectedSource = .data(data, faceIndex: faceIndex)
        }
        guard let metadata else { return nil }
        let weightAxis = metadata.variationAxes.first { $0.tag == Self.weightVariationTag }
        let requested = weightAxis.map { axis in
            [axis.tag: min(max(weight.weightClass, axis.minimumValue), axis.maximumValue)]
        } ?? [:]
        guard requested.values.allSatisfy(\.isFinite) else { return nil }
        let merged = FontVariationSelection(metadata: metadata).merging(requested)
        let selection = merged.selection
        func applyRequestedWeight(to font: VVD.Font) -> Bool {
            metadata.variationAxes.isEmpty || font.setVariationCoordinates(selection.rasterCoordinates)
        }
        guard let layoutFont = source.makeFont(faceIndex: faceIndex),
              applyRequestedWeight(to: layoutFont) else { return nil }
        let usesVariableWeight = weightAxis != nil
        let requestedWeight = weight.value.isFinite
            ? weight
            : .regular
        let logicalEmbolden = usesVariableWeight
            ? 0
            : SystemFontProvider.embolden(for: requestedWeight)
        var selectedFont = SelectedFont(source: selectedSource, pointSize: size, variation: selection,
            comparisonCoordinates: selection.comparisonCoordinates(requested: merged.extras ?? [:]),
            syntheticWeight: logicalEmbolden)
        selectedFont.variationExtras = merged.extras
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
                logicalEmbolden: logicalEmbolden,
                selectedFont: selectedFont
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
                logicalEmbolden: logicalEmbolden,
                selectedFont: selectedFont
            )
        }
    }
}

struct FixedFontProvider: TypefaceProvider {
    /// Supplied faces keep renderer state outside selected-font comparison.
    /// Cache admission still needs the immutable snapshot taken by the public Font bridge.
    private struct ResourceConfiguration: Hashable {
        enum Rendering: Hashable {
            case texture(boldStrength: CGFloat, outlineThickness: CGFloat)
            case vector(embolden: CGFloat, outlineThickness: CGFloat)
        }

        let dpiX: UInt32
        let dpiY: UInt32
        let isBitmapPreferred: Bool
        let isKerningEnabled: Bool
        let isColorEnabled: Bool
        let rendering: Rendering

        init?(_ face: any Typeface) {
            let font: VVD.Font
            switch face {
            case let face as TextureTypeface:
                font = face.textureFont
                rendering = .texture(
                    boldStrength: face.textureFont.boldStrength,
                    outlineThickness: face.textureFont.outlineThickness
                )
            case let face as VectorTypeface:
                font = face.font
                rendering = .vector(
                    embolden: face.embolden,
                    outlineThickness: face.outlineThickness
                )
            default:
                return nil
            }
            let dpi = font.dpi
            self.dpiX = dpi.x
            self.dpiY = dpi.y
            self.isBitmapPreferred = font.isBitmapPreferred
            self.isKerningEnabled = font.isKerningEnabled
            self.isColorEnabled = font.isColorEnabled
        }
    }

    let face: any Typeface
    let pointSize: CGFloat
    private let source: VVD.Font.Source?
    private let resourceConfiguration: ResourceConfiguration?
    let selection: FontResourceResolver.Selection?

    init(_ face: any Typeface, pointSize: CGFloat, metadata: VVD.Font.FaceMetadata? = nil) {
        self.face = face
        self.pointSize = pointSize
        self.source = (face as? any VVDFontBackedTypeface)?.font.source
        self.resourceConfiguration = ResourceConfiguration(face)
        if let metadata, let font = (face as? any VVDFontBackedTypeface)?.font,
           let selected = face.selectedFont {
            let coordinates = font.variationCoordinates
            self.selection = .init(variation: FontVariationSelection(metadata: metadata,
                coordinates: metadata.variationAxes.map { coordinates[$0.tag] ?? $0.defaultValue }),
                comparison: selected.variation)
        } else {
            self.selection = nil
        }
    }

    var identifier: String {
        face.identifier
    }

    var supportsSizeCopy: Bool {
        face is VectorTypeface || face is TextureTypeface
    }

    func isEqual(to: any TypefaceProvider) -> Bool {
        if let other = to as? Self {
            guard pointSize == other.pointSize else { return false }
            if let source, let otherSource = other.source,
               let selected = face.selectedFont, let otherSelected = other.face.selectedFont {
                return source === otherSource && type(of: face) == type(of: other.face) &&
                    resourceConfiguration == other.resourceConfiguration &&
                    selected.isEqual(to: otherSelected)
            }
            return self.face.isEqual(to: other.face)
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        if let source, face.selectedFont != nil {
            hasher.combine(ObjectIdentifier(source))
            hasher.combine(ObjectIdentifier(type(of: face)))
            hasher.combine(resourceConfiguration)
        } else {
            face.hashIdentity(into: &hasher)
        }
        hasher.combine(pointSize)
    }

    func withSize(_ size: CGFloat) -> Self? {
        let copy: (any Typeface)?
        switch face {
        case let face as VectorTypeface: copy = face.withSize(size)
        case let face as TextureTypeface: copy = face.withSize(size)
        default: return nil
        }
        guard let copy else { return nil }
        return Self(copy, pointSize: size, metadata: selection?.variation.metadata)
    }

    func copying(pointSize: CGFloat, comparison: [UInt32: CGFloat]) -> Self? {
        guard let selection, let current = face.selectedFont else { return nil }
        // Missing comparison axes preserve the graphics input. The parser's
        // copy tolerance is also independent of comparison-coordinate rounding.
        let coordinates = selection.variation.applying(comparison).rasterCoordinates
        let selected = current.copying(pointSize: pointSize, comparison: comparison)
        let copy: (any Typeface)?
        switch face {
        case let face as VectorTypeface:
            copy = face.withSize(pointSize, selectedFont: selected, coordinates: coordinates)
        case let face as TextureTypeface:
            copy = face.withSize(pointSize, selectedFont: selected, coordinates: coordinates)
        default:
            return nil
        }
        guard let copy else { return nil }
        return Self(copy, pointSize: pointSize, metadata: selection.variation.metadata)
    }

    func makeTypeface(
        _: AppContext,
        dpi: UInt32
    ) -> Typeface? {
        self.face
    }

    var isShareable: Bool { false }
}
