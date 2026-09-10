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

struct AnyFontModifier: Hashable, Sendable {
    enum Storage: Hashable, Sendable {
        case monospaced
        case undoMonospaced
        case monospacedDigit
    }

    let storage: Storage

    static func monospaced(_ isActive: Bool) -> Self {
        Self(storage: isActive ? .monospaced : .undoMonospaced)
    }

    static let monospacedDigit = Self(storage: .monospacedDigit)

    var monospacedValue: Bool? {
        switch storage {
        case .monospaced:
            true
        case .undoMonospaced:
            false
        case .monospacedDigit:
            nil
        }
    }

    var isMonospacedDigit: Bool {
        storage == .monospacedDigit
    }
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
        font ?? defaultFont ?? .system(.body)
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

protocol StaticFontModifier {
    static func modify(_ font: Font) -> Font
    static var shapingFeatures: [TypefaceShapingFeature] { get }
}

protocol StaticModifierProviderProtocol {
    var baseFont: Font { get }
    var modifiedFont: Font { get }
    func replacingBaseFont(_ base: Font) -> Font
}

extension StaticFontModifier {
    static var shapingFeatures: [TypefaceShapingFeature] { [] }
}

class AnyFontBox: @unchecked Sendable {
    let fontBox: any TypefaceProvider

    init(_ fontBox: any TypefaceProvider) {
        self.fontBox = fontBox
    }

    func isEqual(to other: AnyFontBox) -> Bool {
        self.fontBox.isEqual(to: other.fontBox)
    }

    func hash(into hasher: inout Hasher) {
        fontBox.hash(into: &hasher)
    }

    func resolved(in environment: EnvironmentValues) -> AnyFontBox {
        AnyFontBox(fontBox.resolved(in: environment))
    }

    func makeTypeface(
        _ context: AppContext,
        dpi: UInt32
    ) -> Typeface? {
        fontBox.makeTypeface(
            context,
            dpi: dpi
        )
    }
    var isShareable: Bool { fontBox.isShareable }
    var shapingFeatures: [TypefaceShapingFeature] {
        fontBox.shapingFeatures
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

    private var applyingStaticModifiers: Font {
        guard let provider = provider.fontBox as?
                any StaticModifierProviderProtocol else {
            return self
        }
        return provider.modifiedFont
    }

    private func transformingBase(
        _ transform: (Font) -> Font
    ) -> Font {
        guard let provider = provider.fontBox as?
                any StaticModifierProviderProtocol else {
            return transform(self)
        }
        return provider.replacingBaseFont(
            provider.baseFont.transformingBase(transform)
        )
    }

    private func applyingMonospacedTrait() -> Font {
        switch provider.fontBox {
        case let system as SystemFontProvider:
            return Font(provider: AnyFontBox(SystemFontProvider(
                size: system.size,
                weight: system.weight,
                design: .monospaced,
                renderingMode: system.renderingMode,
                isItalic: system.isItalic
            )))
        case let external as ExternalFontProvider:
            return Font(provider: AnyFontBox(ExternalFontProvider(
                source: external.source,
                size: external.size,
                weight: external.weight,
                design: .monospaced,
                faceIndex: external.faceIndex,
                renderingMode: external.renderingMode
            )))
        default:
            return self
        }
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
        if provider.isShareable {
            let key = SceneResources.TypefaceKey(
                font: self,
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
        contentScaleFactor: CGFloat
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
            dpi: UInt32(max(scaledDPI, 1))
        )
    }

    func typefaceCascade(
        in environment: EnvironmentValues,
        forContext context: SceneResources,
        dpi: UInt32
    ) -> TypefaceCascade {
        var shapingFeatures = provider.shapingFeatures
        if environment.fontModifiers.usesMonospacedDigits {
            shapingFeatures.append(
                contentsOf: MonospacedDigitModifier.shapingFeatures
            )
        }
        var uniqueShapingFeatures: [TypefaceShapingFeature] = []
        for feature in shapingFeatures where
            !uniqueShapingFeatures.contains(feature) {
            uniqueShapingFeatures.append(feature)
        }

        let font = resolved(in: environment)
        let system = font.provider.fontBox as? SystemFontProvider
        let external = font.provider.fontBox as? ExternalFontProvider
        let catalog = BundledFontCatalog.shared
        let locale = environment.locale
        let design = system?.design ?? external?.design ?? .default
        let families = catalog.configuration.fonts(
            for: locale,
            design: design
        )

        let size = font.pointSizeForSymbolMetrics ?? 17
        let weight = system?.weight ?? external?.weight ?? .regular
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
                    provider: AnyFontBox(system)
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
        let bundledFont = Font(provider: AnyFontBox(provider))
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
        let font = applyingStaticModifiers
        if font != self {
            return font.bundledRenderingMode(in: environment)
        }
        switch font.provider.fontBox {
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
        var font = applyingStaticModifiers
        if environment.fontModifiers.monospacedValue == true {
            font = font.applyingMonospacedTrait()
        }
        if environment.fontModifiers.usesMonospacedDigits {
            font = MonospacedDigitModifier.modify(font)
        }
        return Font(provider: font.provider.resolved(in: environment))
    }

    var pointSizeForSymbolMetrics: CGFloat? {
        if let provider = provider.fontBox as?
                any StaticModifierProviderProtocol {
            return provider.baseFont.pointSizeForSymbolMetrics
        }
        return switch provider.fontBox {
        case let system as SystemFontProvider:
            system.size
        case let bundled as BundledFontProvider:
            bundled.size
        case let external as ExternalFontProvider:
            external.size
        case let custom as CustomFontProvider:
            custom.size
        case let fixed as FixedFontProvider:
            fixed.face.lineHeight
        default:
            nil
        }
    }
}

extension Font {

    struct StaticModifierProvider<Modifier: StaticFontModifier>:
        TypefaceProvider, StaticModifierProviderProtocol {
        let base: Font

        var baseFont: Font { base }

        var modifiedFont: Font {
            Modifier.modify(base.applyingStaticModifiers)
        }

        func replacingBaseFont(_ base: Font) -> Font {
            Font(provider: AnyFontBox(Self(base: base)))
        }

        func isEqual(to other: any TypefaceProvider) -> Bool {
            guard let other = other as? Self else { return false }
            return base == other.base
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(Modifier.self))
            hasher.combine(base)
        }

        func makeTypeface(
            _ context: AppContext,
            dpi: UInt32
        ) -> Typeface? {
            modifiedFont.provider.makeTypeface(context, dpi: dpi)
        }

        var isShareable: Bool {
            modifiedFont.provider.isShareable
        }

        var shapingFeatures: [TypefaceShapingFeature] {
            base.provider.shapingFeatures + Modifier.shapingFeatures
        }
    }

    struct MonospacedModifier: StaticFontModifier {
        static func modify(_ font: Font) -> Font {
            font.applyingMonospacedTrait()
        }
    }

    struct MonospacedDigitModifier: StaticFontModifier {
        static let shapingFeatures: [TypefaceShapingFeature] = [
            TypefaceShapingFeature(tag: 0x746e_756d)
        ]

        static func modify(_ font: Font) -> Font {
            font
        }
    }

    struct UndoModifier<Modifier: StaticFontModifier>: StaticFontModifier {
        static func modify(_ font: Font) -> Font {
            font
        }
    }

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

    public enum TextStyle: CaseIterable {
        case largeTitle
        case title
        case headline
        case subheadline
        case body
        case callout
        case footnote
        case caption
    }
}

extension Font {

    public init(_ font: TextureFont) {
        let fontBox = FixedFontProvider(TextureTypeface(textureFont: font))
        self.init(provider: AnyFontBox(fontBox))
    }

    public init(vector font: VVD.Font,
                embolden: CGFloat = 0,
                outlineThickness: CGFloat = 0) {
        let typeface = VectorTypeface(
            font: font,
            embolden: embolden,
            outlineThickness: outlineThickness)
        let fontBox = FixedFontProvider(typeface)
        self.init(provider: AnyFontBox(fontBox))
    }

    static func pointSize(for style: TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:   return 26
        case .title:        return 22
        case .headline:     return 13
        case .subheadline:  return 11
        case .body:         return 13
        case .callout:      return 12
        case .footnote:     return 10
        case .caption:      return 10
        }
    }

    static func weight(for style: TextStyle) -> Weight {
        switch style {
        case .headline:
            return .bold
        case .largeTitle, .title, .subheadline, .body, .callout, .footnote, .caption:
            return .regular
        }
    }

    public static func system(_ style: Font.TextStyle, design: Font.Design = .default) -> Font {
        let provider = SystemFontProvider(size: pointSize(for: style),
                                          weight: weight(for: style),
                                          design: design,
                                          renderingMode: .automatic)
        return Font(provider: AnyFontBox(provider))
    }

    public static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let provider = SystemFontProvider(size: size,
                                          weight: weight,
                                          design: design,
                                          renderingMode: .automatic)
        return Font(provider: AnyFontBox(provider))
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
        return Font(provider: AnyFontBox(provider))
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
        return Font(provider: AnyFontBox(provider))
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
        return Font(provider: AnyFontBox(provider))
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
        return Font(provider: AnyFontBox(provider))
    }

    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        let provider = CustomFontProvider(name: name, size: pointSize(for: textStyle) + size)
        return Font(provider: AnyFontBox(provider))
    }

    public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
        let provider = CustomFontProvider(name: name, size: fixedSize)
        return Font(provider: AnyFontBox(provider))
    }

    public static func custom(_ name: String, size: CGFloat) -> Font {
        let provider = CustomFontProvider(name: name, size: size)
        return Font(provider: AnyFontBox(provider))
    }
}

extension Font {
    public struct Weight: Hashable, Sendable {
        public var value: CGFloat

        public static let ultraLight = Weight(value: 100)
        public static let thin = Weight(value: 200)
        public static let light = Weight(value: 300)
        public static let regular = Weight(value: 400)
        public static let medium = Weight(value: 500)
        public static let semibold = Weight(value: 600)
        public static let bold = Weight(value: 700)
        public static let heavy = Weight(value: 800)
        public static let black = Weight(value: 900)
    }

    public func weight(_ weight: Weight) -> Font {
        transformingBase { font in
            guard let system = font.provider.fontBox as?
                    SystemFontProvider else {
                return font
            }
            return Font(
                provider: AnyFontBox(SystemFontProvider(
                    size: system.size,
                    weight: weight,
                    design: system.design,
                    renderingMode: system.renderingMode,
                    isItalic: system.isItalic
                ))
            )
        }
    }

    public func bold() -> Font {
        weight(.bold)
    }

    public func bold(_ isActive: Bool) -> Font {
        isActive ? bold() : self
    }

    public func italic() -> Font {
        italic(true)
    }

    public func italic(_ isActive: Bool) -> Font {
        guard isActive else { return self }
        return transformingBase { font in
            guard let system = font.provider.fontBox as?
                    SystemFontProvider else {
                return font
            }
            return Font(
                provider: AnyFontBox(SystemFontProvider(
                    size: system.size,
                    weight: system.weight,
                    design: system.design,
                    renderingMode: system.renderingMode,
                    isItalic: true
                ))
            )
        }
    }

    public func monospacedDigit() -> Font {
        Font(provider: AnyFontBox(StaticModifierProvider<
            MonospacedDigitModifier
        >(base: self)))
    }

    public func monospaced() -> Font {
        monospaced(true)
    }

    public func monospaced(_ isActive: Bool) -> Font {
        if isActive {
            return Font(provider: AnyFontBox(StaticModifierProvider<
                MonospacedModifier
            >(base: self)))
        }
        return Font(provider: AnyFontBox(StaticModifierProvider<
            UndoModifier<MonospacedModifier>
        >(base: self)))
    }

    public static let largeTitle = Font.system(Font.TextStyle.largeTitle)
    public static let title = Font.system(Font.TextStyle.title)
    public static let headline = Font.system(Font.TextStyle.headline)
    public static let subheadline = Font.system(Font.TextStyle.subheadline)
    public static let body = Font.system(Font.TextStyle.body)
    public static let callout = Font.system(Font.TextStyle.callout)
    public static let footnote = Font.system(Font.TextStyle.footnote)
    public static let caption = Font.system(Font.TextStyle.caption)
}
