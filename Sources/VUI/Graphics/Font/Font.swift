//
//  File: Font.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension View {
    public func font(_ font: Font?) -> some View {
        return environment(\.font, font)
    }

    public func monospacedDigit() -> some View {
        transformEnvironment(\.fontModifiers) { modifiers in
            modifiers.appendAsNearest(.monospacedDigit)
        }
    }

    public func monospaced(_ isActive: Bool = true) -> some View {
        transformEnvironment(\.fontModifiers) { modifiers in
            modifiers.appendAsNearest(.monospaced(isActive))
        }
    }
}

enum FontEnvironmentKey: EnvironmentKey {
    static var defaultValue: Font? { return nil }
}

enum DefaultFontKey: EnvironmentKey {
    static var defaultValue: Font? { nil }
}

private enum DefaultFontRenderingModeKey: EnvironmentKey {
    static var defaultValue: Font.DefaultRenderingMode { .bitmap() }
}

private enum EmojiFontPresetKey: EnvironmentKey {
    static var defaultValue: String? { nil }
}

private enum FontModifiersKey: EnvironmentKey {
    static var defaultValue: [AnyFontModifier] { [] }
}

private extension Array where Element == AnyFontModifier {
    mutating func appendAsNearest(_ modifier: AnyFontModifier) {
        removeAll { $0 == modifier }
        append(modifier)
    }

    var monospacedValue: Bool? {
        reversed().lazy.compactMap(\.monospacedValue).first
    }

    var usesMonospacedDigits: Bool {
        contains(where: \.isMonospacedDigit)
    }
}

extension EnvironmentValues {
    public var font: Font? {
        set { self[FontEnvironmentKey.self] = newValue }
        get { self[FontEnvironmentKey.self] }
    }

    var defaultFont: Font? {
        set { self[DefaultFontKey.self] = newValue }
        get { self[DefaultFontKey.self] }
    }

    var effectiveFont: Font {
        font ?? defaultFont ?? .system(size: Font.pointSize(for: .body))
    }

    var fontModifiers: [AnyFontModifier] {
        set { self[FontModifiersKey.self] = newValue }
        get { self[FontModifiersKey.self] }
    }

    mutating func replaceMonospacedFontModifier(with isActive: Bool) {
        fontModifiers.removeAll { $0.monospacedValue != nil }
        fontModifiers.append(.monospaced(isActive))
    }

    mutating func addMonospacedDigitFontModifier() {
        fontModifiers.appendAsNearest(.monospacedDigit)
    }

    public var defaultFontRenderingMode: Font.DefaultRenderingMode {
        set { self[DefaultFontRenderingModeKey.self] = newValue }
        get { self[DefaultFontRenderingModeKey.self] }
    }

    /// Selects an emoji font priority list from the active font configuration.
    /// A nil or unknown name uses the configuration's default preset.
    public var emojiFontPreset: String? {
        get { self[EmojiFontPresetKey.self] }
        set { self[EmojiFontPresetKey.self] = newValue }
    }
}

public struct Font: Hashable, Sendable {
    let provider: AnyFontBox

    init(provider: AnyFontBox) {
        self.provider = provider
    }

    public static func == (lhs: Font, rhs: Font) -> Bool {
        lhs.provider.isEqual(to: rhs.provider)
    }

    public func hash(into hasher: inout Hasher) {
        provider.hash(into: &hasher)
    }

    init(typefaceProvider: any TypefaceProvider, features: [TypefaceShapingFeature] = []) {
        provider = FontBox(TypefaceFontProvider(typefaceProvider, features: features))
    }

    var typefaceProvider: (any TypefaceProvider)? {
        if let resolved = provider as? FontBox<PlatformFontProvider> {
            return resolved.base.font.provider
        }
        return (provider as? FontBox<TypefaceFontProvider>)?.base.base
    }

    var typefaceFeatures: [TypefaceShapingFeature] {
        if let resolved = provider as? FontBox<PlatformFontProvider> {
            return resolved.base.font.shapingFeatures
        }
        return (provider as? FontBox<TypefaceFontProvider>)?.base.features ?? []
    }

    func resolveDescriptor(in context: Context) -> FontDescriptor {
        provider.resolveDescriptor(in: context)
    }

    func resolveTraits(in context: Context) -> ResolvedTraits {
        provider.resolveTraits(in: context)
    }

    func removing<T: StaticFontModifier>(modifier: T.Type) -> Font {
        func wrap<P: FontProvider>(_ value: P) -> Font { Font(provider: FontBox(value)) }
        return _openExistential(provider.removing(modifier: modifier), do: wrap)
    }

    func typeface(
        forContext context: SceneResources,
        contentScaleFactor: CGFloat
    ) -> Typeface? {
        precondition(
            contentScaleFactor.isFinite && contentScaleFactor > 0,
            "The font content scale factor must be positive and finite."
        )
        let scaledDPI = (CGFloat(defaultDPI) * contentScaleFactor).rounded()
        precondition(
            scaledDPI <= CGFloat(UInt32.max),
            "The font content scale factor exceeds the backend DPI range."
        )
        let dpi = UInt32(max(scaledDPI, 1))
        return typeface(forContext: context, dpi: dpi)
    }

    func typeface(
        forContext context: SceneResources,
        dpi: UInt32
    ) -> Typeface? {
        precondition(dpi > 0, "The font DPI must be positive.")
        guard let app = appContext else { return nil }
        let font = typefaceProvider == nil ? resolved(in: EnvironmentValues()) : self
        let provider = font.typefaceProvider!
        if provider.isShareable {
            let key = SceneResources.TypefaceKey(
                font: Font(typefaceProvider: provider, features: font.typefaceFeatures),
                dpi: dpi
            )
            if let typeface = context.cachedTypefaces[key] {
                return typeface
            }
            if let typeface = provider.makeTypeface(
                app,
                dpi: key.dpi
            ) {
                context.cachedTypefaces[key] = typeface
                return typeface
            }
        } else {
            return provider.makeTypeface(
                app,
                dpi: dpi
            )
        }
        return nil
    }

    func typefaceCascade(
        in environment: EnvironmentValues,
        forContext context: SceneResources,
        contentScaleFactor: CGFloat,
        applyEnvironmentModifiers: Bool = true
    ) -> TypefaceCascade {
        precondition(
            contentScaleFactor.isFinite && contentScaleFactor > 0,
            "The font content scale factor must be positive and finite."
        )
        let scaledDPI = (CGFloat(defaultDPI) * contentScaleFactor).rounded()
        precondition(
            scaledDPI <= CGFloat(UInt32.max),
            "The font content scale factor exceeds the backend DPI range."
        )
        return typefaceCascade(
            in: environment,
            forContext: context,
            dpi: UInt32(max(scaledDPI, 1)),
            applyEnvironmentModifiers: applyEnvironmentModifiers
        )
    }

    func typefaceCascade(
        in environment: EnvironmentValues,
        forContext context: SceneResources,
        dpi: UInt32,
        applyEnvironmentModifiers: Bool = true
    ) -> TypefaceCascade {
        let font = !applyEnvironmentModifiers ||
            (provider is FontBox<PlatformFontProvider> && environment.fontModifiers.isEmpty)
            ? self : resolved(in: environment)
        var shapingFeatures = font.typefaceFeatures
        if applyEnvironmentModifiers && environment.fontModifiers.usesMonospacedDigits {
            shapingFeatures.append(
                contentsOf: MonospacedDigitModifier.shapingFeatures
            )
        }
        var uniqueShapingFeatures: [TypefaceShapingFeature] = []
        for feature in shapingFeatures where
            !uniqueShapingFeatures.contains(feature) {
            uniqueShapingFeatures.append(feature)
        }

        let system = font.typefaceProvider as? SystemFontProvider
        let external = font.typefaceProvider as? ExternalFontProvider
        let catalog = BundledFontCatalog.shared
        let locale = environment.locale
        let design = system?.design ?? external?.design ?? .default
        let families = catalog.configuration.fonts(
            for: locale,
            design: design
        )

        let size = font.pointSizeForSymbolMetrics ?? 17
        let weight = system?.weight ?? external?.weight ??
            (font.typefaceProvider as? BundledFontProvider)?.weight ?? .regular
        let renderingMode = font.bundledRenderingMode(in: environment)
        let primary = font.typeface(forContext: context, dpi: dpi)

        var ordinaryFaces: [Typeface] = []
        if system == nil, let primary {
            ordinaryFaces.append(primary)
        }

        for family in families {
            let face: Typeface?
            if family == catalog.configuration.systemFont(for: design),
               let system {
                face = primary ?? Font(
                    typefaceProvider: system
                ).typeface(forContext: context, dpi: dpi)
            } else {
                face = font.bundledTypeface(
                    family: family,
                    locale: locale,
                    size: size,
                    weight: weight,
                    renderingMode: renderingMode,
                    catalog: catalog,
                    context: context,
                    dpi: dpi,
                    isItalic: system?.isItalic ?? false,
                    deferLoading: true
                )
            }
            guard let face,
                  !ordinaryFaces.contains(where: { $0.isEqual(to: face) })
            else {
                continue
            }
            ordinaryFaces.append(face)
        }

        let applicationCatalog = environment.resourceBundle.flatMap {
            BundledFontCatalog.catalog(in: $0)
        }
        let emojiCatalog = applicationCatalog.flatMap {
            $0.configuration.defaultEmojiPreset == nil ? nil : $0
        } ?? catalog
        for family in emojiCatalog.configuration.emojiFonts(preset: environment.emojiFontPreset) {
            if let face = font.bundledTypeface(
                family: family, locale: locale, size: size, weight: weight,
                renderingMode: renderingMode, catalog: emojiCatalog,
                context: context, dpi: dpi, isItalic: false,
                deferLoading: true, isEmojiFallback: true
            ) {
                ordinaryFaces.append(face)
            }
        }

        let missingGlyphFace = font.bundledTypeface(
            family: catalog.configuration.missingGlyphFont,
            locale: locale,
            size: size,
            weight: .regular,
            renderingMode: renderingMode,
            catalog: catalog,
            context: context,
            dpi: dpi,
            isItalic: false,
            deferLoading: true
        )
        return TypefaceCascade(
            ordinaryFaces: ordinaryFaces,
            missingGlyphFace: missingGlyphFace,
            shapingFeatures: uniqueShapingFeatures
        )
    }

    private func bundledTypeface(
        family: BundledFontID,
        locale: Locale,
        size: CGFloat,
        weight: Weight,
        renderingMode: RenderingMode,
        catalog: BundledFontCatalog,
        context: SceneResources,
        dpi: UInt32,
        isItalic: Bool,
        deferLoading: Bool = false,
        isEmojiFallback: Bool = false
    ) -> Typeface? {
        guard appContext != nil else { return nil }
        guard let provider = BundledFontProvider(
            family: family,
            locale: locale,
            size: size,
            weight: weight,
            renderingMode: renderingMode,
            isItalic: isItalic,
            catalog: catalog
        ) else { return nil }
        let bundledFont = Font(typefaceProvider: provider)
        if deferLoading {
            return DeferredTypeface(
                font: bundledFont,
                context: context,
                dpi: dpi,
                identifier: "\(family.rawValue):\(provider.resource.faceIndex)",
                isEmojiFallback: isEmojiFallback
            )
        }
        return bundledFont.typeface(forContext: context, dpi: dpi)
    }

    private func bundledRenderingMode(
        in environment: EnvironmentValues
    ) -> RenderingMode {
        let font = self
        switch font.typefaceProvider {
        case let system as SystemFontProvider:
            return system.renderingMode
        case let bundled as BundledFontProvider:
            return bundled.renderingMode
        case let external as ExternalFontProvider:
            return external.renderingMode
        case let fixed as FixedFontProvider:
            if fixed.face is TextureTypeface {
                return .bitmap()
            }
            return .vector()
        default:
            switch environment.defaultFontRenderingMode {
            case let .bitmap(options):
                return .bitmap(options)
            case let .vector(options):
                return .vector(options)
            }
        }
    }

    func resolved(in environment: EnvironmentValues) -> Font {
        var context = environment.fontResolutionContext
        var modifiers = context.fontModifiers.filter { $0.monospacedValue == nil }
        if context.fontModifiers.monospacedValue == true {
            modifiers.append(.static(MonospacedModifier.self))
        }
        context.fontModifiers = modifiers
        let resource = resolve(in: context).resource
        return Font(provider: FontBox(PlatformFontProvider(font: resource)))
    }

    var pointSizeForSymbolMetrics: CGFloat? {
        if let wrapper = provider.baseProvider as? any FontWrapperProvider {
            return wrapper.baseFont.pointSizeForSymbolMetrics
        }
        switch provider.baseProvider {
        case let system as SystemProvider:
            return system.effectiveSize(in: EnvironmentValues().fontResolutionContext)
        case let style as TextStyleProvider:
            return Self.pointSize(for: style.style)
        case let named as NamedProvider:
            return named.textStyle == nil ? named.size : named.size.rounded()
        case let rendering as TypefaceFontProvider:
            return rendering.base.pointSize
        case let resolved as PlatformFontProvider:
            return resolved.font.pointSize
        default:
            return nil
        }
    }
}

extension Font {
    public enum RenderingMode: Hashable, Sendable {
        public struct Bitmap: Hashable, Sendable {
            public let outlineThickness: CGFloat
            public let isBitmapPreferred: Bool
            public let isColorEnabled: Bool

            public init(outlineThickness: CGFloat = 0,
                        isBitmapPreferred: Bool = false,
                        isColorEnabled: Bool = true) {
                self.outlineThickness = outlineThickness
                self.isBitmapPreferred = isBitmapPreferred
                self.isColorEnabled = isColorEnabled
            }
        }

        public struct Vector: Hashable, Sendable {
            public let outlineThickness: CGFloat

            public init(outlineThickness: CGFloat = 0) {
                self.outlineThickness = outlineThickness
            }
        }

        case automatic
        case bitmap(Bitmap = .init())
        case vector(Vector = .init())
    }

    public enum DefaultRenderingMode: Hashable, Sendable {
        case bitmap(RenderingMode.Bitmap = .init())
        case vector(RenderingMode.Vector = .init())
    }

    public enum Design: Hashable, Sendable {
        case `default`
        case serif
        case rounded
        case monospaced
    }

    public enum TextStyle: CaseIterable, Hashable, Sendable, Codable {
        case largeTitle
        case title
        case title2
        case title3
        case headline
        case subheadline
        case body
        case callout
        case footnote
        case caption
        case caption2
    }
}

extension Font {

    public init(_ font: TextureFont) {
        let fontBox = FixedFontProvider(TextureTypeface(textureFont: font))
        self.init(typefaceProvider: fontBox)
    }

    public init(vector font: VVD.Font,
                embolden: CGFloat = 0,
                outlineThickness: CGFloat = 0) {
        let typeface = VectorTypeface(
            font: font,
            embolden: embolden,
            outlineThickness: outlineThickness)
        let fontBox = FixedFontProvider(typeface)
        self.init(typefaceProvider: fontBox)
    }

    static func pointSize(for style: TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:   return 26
        case .title:        return 22
        case .title2:       return 17
        case .title3:       return 15
        case .headline:     return 13
        case .subheadline:  return 11
        case .body:         return 13
        case .callout:      return 12
        case .footnote:     return 10
        case .caption:      return 10
        case .caption2:     return 10
        }
    }

    static func weight(for style: TextStyle) -> Weight {
        switch style {
        case .headline:
            return .bold
        case .caption2:
            return .medium
        case .largeTitle, .title, .title2, .title3, .subheadline, .body, .callout, .footnote, .caption:
            return .regular
        }
    }

    public static func system(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font {
        Font(provider: FontBox(TextStyleProvider(style: style, design: design, weight: weight)))
    }

    public static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        Font(provider: FontBox(SystemProvider(size: size, weight: weight, design: design,
                                              textStyle: nil, maximumSize: nil)))
    }

    public static func bitmap(_ style: Font.TextStyle,
                              design: Font.Design = .default,
                              outlineThickness: CGFloat = 0,
                              isBitmapPreferred: Bool = false,
                              isColorEnabled: Bool = true) -> Font {
        bitmap(size: pointSize(for: style),
               weight: weight(for: style),
               design: design,
               outlineThickness: outlineThickness,
               isBitmapPreferred: isBitmapPreferred,
               isColorEnabled: isColorEnabled)
    }

    public static func bitmap(size: CGFloat,
                              weight: Font.Weight = .regular,
                              design: Font.Design = .default,
                              outlineThickness: CGFloat = 0,
                              isBitmapPreferred: Bool = false,
                              isColorEnabled: Bool = true) -> Font {
        let provider = SystemFontProvider(
            size: size,
            weight: weight,
            design: design,
            renderingMode: .bitmap(.init(
                outlineThickness: outlineThickness,
                isBitmapPreferred: isBitmapPreferred,
                isColorEnabled: isColorEnabled)))
        return Font(typefaceProvider: provider)
    }

    public static func vector(_ style: Font.TextStyle,
                              design: Font.Design = .default,
                              outlineThickness: CGFloat = 0) -> Font {
        vector(size: pointSize(for: style),
               weight: weight(for: style),
               design: design,
               outlineThickness: outlineThickness)
    }

    public static func vector(size: CGFloat,
                              weight: Font.Weight = .regular,
                              design: Font.Design = .default,
                              outlineThickness: CGFloat = 0) -> Font {
        let provider = SystemFontProvider(
            size: size,
            weight: weight,
            design: design,
            renderingMode: .vector(.init(
                outlineThickness: outlineThickness)))
        return Font(typefaceProvider: provider)
    }

    /// Creates a font backed by a local file URL.
    ///
    /// Remote URLs are not loaded. Download them first and pass their contents
    /// to `data(_:size:weight:design:faceIndex:renderingMode:)`.
    public static func file(
        _ url: URL,
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        faceIndex: Int = 0,
        renderingMode: Font.RenderingMode = .automatic
    ) -> Font {
        let sourceURL = url.isFileURL ? url.standardizedFileURL : url
        let provider = ExternalFontProvider(
            source: .file(sourceURL),
            size: size,
            weight: weight,
            design: design,
            faceIndex: faceIndex,
            renderingMode: renderingMode
        )
        return Font(typefaceProvider: provider)
    }

    /// Creates a font backed by a retained copy of in-memory font data.
    public static func data(
        _ data: Data,
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        faceIndex: Int = 0,
        renderingMode: Font.RenderingMode = .automatic
    ) -> Font {
        let provider = ExternalFontProvider(
            source: .data(ExternalFontData(data)),
            size: size,
            weight: weight,
            design: design,
            faceIndex: faceIndex,
            renderingMode: renderingMode
        )
        return Font(typefaceProvider: provider)
    }

    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        Font(provider: FontBox(NamedProvider(name: name, size: size, textStyle: textStyle)))
    }

    public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
        Font(provider: FontBox(NamedProvider(name: name, size: fixedSize, textStyle: nil)))
    }

    public static func custom(_ name: String, size: CGFloat) -> Font {
        Font(provider: FontBox(NamedProvider(name: name, size: size, textStyle: .body)))
    }
}

extension Font {
    public func weight(_ weight: Weight) -> Font {
        Font(provider: FontBox(ModifierProvider(base: self, modifier: WeightModifier(weight: weight))))
    }

    public func bold() -> Font { bold(true) }
    public func bold(_ isActive: Bool) -> Font {
        if isActive { return Font(provider: FontBox(StaticModifierProvider<BoldModifier>(base: self))) }
        return Font(provider: FontBox(StaticModifierProvider<UndoModifier<BoldModifier>>(base: self)))
    }

    public func italic() -> Font { italic(true) }
    public func italic(_ isActive: Bool) -> Font {
        if isActive { return Font(provider: FontBox(StaticModifierProvider<ItalicModifier>(base: self))) }
        return Font(provider: FontBox(StaticModifierProvider<UndoModifier<ItalicModifier>>(base: self)))
    }

    public func monospacedDigit() -> Font {
        Font(provider: FontBox(StaticModifierProvider<MonospacedDigitModifier>(base: self)))
    }

    public func monospaced() -> Font { monospaced(true) }
    public func monospaced(_ isActive: Bool) -> Font {
        if isActive { return Font(provider: FontBox(StaticModifierProvider<MonospacedModifier>(base: self))) }
        return Font(provider: FontBox(StaticModifierProvider<UndoModifier<MonospacedModifier>>(base: self)))
    }

    public static let largeTitle = Font.system(Font.TextStyle.largeTitle)
    public static let title = Font.system(Font.TextStyle.title)
    public static let title2 = Font.system(Font.TextStyle.title2)
    public static let title3 = Font.system(Font.TextStyle.title3)
    public static let headline = Font.system(Font.TextStyle.headline)
    public static let subheadline = Font.system(Font.TextStyle.subheadline)
    public static let body = Font.system(Font.TextStyle.body)
    public static let callout = Font.system(Font.TextStyle.callout)
    public static let footnote = Font.system(Font.TextStyle.footnote)
    public static let caption = Font.system(Font.TextStyle.caption)
    public static let caption2 = Font.system(Font.TextStyle.caption2)
}
