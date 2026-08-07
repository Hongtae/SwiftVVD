//
//  File: Font.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

extension View {
    public func font(_ font: Font?) -> some View {
        return environment(\.font, font)
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

    public var defaultFontRenderingMode: Font.DefaultRenderingMode {
        set { self[DefaultFontRenderingModeKey.self] = newValue }
        get { self[DefaultFontRenderingModeKey.self] }
    }
}

var defaultFontURL: URL? {
    Bundle.module.url(forResource: "Roboto-Regular",
                      withExtension: "ttf",
                      subdirectory: "Fonts/Roboto")
}

var defaultItalicFontURL: URL? {
    Bundle.module.url(forResource: "Roboto-Italic",
                      withExtension: "ttf",
                      subdirectory: "Fonts/Roboto")
}

let defaultDPI = 72

enum TypefaceGlyph {
    case texture(TextureTypeface.GlyphData)
    case vector(VectorTypeface.GlyphData)
}

struct TypefaceGlyphMetrics {
    var advance: CGSize
    var ascender: CGFloat
    var descender: CGFloat
}

protocol Typeface {
    func glyph(for c: UnicodeScalar) -> TypefaceGlyph?
    func glyphMetrics(for c: UnicodeScalar) -> TypefaceGlyphMetrics?
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint
    func hasGlyph(for: UnicodeScalar) -> Bool

    var lineHeight: CGFloat { get }
    var ascender: CGFloat { get }
    var descender: CGFloat { get }
    var decorationMetrics: TypefaceDecorationMetrics? { get }
    var resolvedMetrics: ResolvedFontMetrics { get }
    var identifier: String { get }

    func isEqual(to: any Typeface) -> Bool
    func hashIdentity(into hasher: inout Hasher)
    func purgeResources(reason: ResourcePurgeReason)
}

extension Typeface {
    func glyphMetrics(for c: UnicodeScalar) -> TypefaceGlyphMetrics? {
        guard let glyph = glyph(for: c) else { return nil }
        switch glyph {
        case let .texture(data):
            return TypefaceGlyphMetrics(
                advance: data.advance,
                ascender: data.ascender,
                descender: data.descender
            )
        case let .vector(data):
            return TypefaceGlyphMetrics(
                advance: data.metrics.advance,
                ascender: data.metrics.ascender,
                descender: data.metrics.descender
            )
        }
    }

    var resolvedMetrics: ResolvedFontMetrics {
        ResolvedFontMetrics(
            capHeight: ascender,
            ascender: ascender,
            descender: descender,
            leading: max(lineHeight - (ascender - descender), 0)
        )
    }

    var decorationMetrics: TypefaceDecorationMetrics? { nil }

    func purgeResources(reason: ResourcePurgeReason) {}
}

struct ResolvedFontMetrics: Equatable, Sendable {
    var capHeight: CGFloat
    var ascender: CGFloat
    var descender: CGFloat
    var leading: CGFloat
    var outsets: EdgeInsets

    init(
        capHeight: CGFloat,
        ascender: CGFloat,
        descender: CGFloat,
        leading: CGFloat,
        outsets: EdgeInsets = EdgeInsets()
    ) {
        self.capHeight = capHeight
        self.ascender = ascender
        self.descender = descender
        self.leading = leading
        self.outsets = outsets
    }

    func scaled(by scale: CGFloat) -> ResolvedFontMetrics {
        guard scale != 0, scale != 1 else { return self }
        return ResolvedFontMetrics(
            capHeight: capHeight / scale,
            ascender: ascender / scale,
            descender: descender / scale,
            leading: leading / scale,
            outsets: EdgeInsets(
                top: outsets.top / scale,
                leading: outsets.leading / scale,
                bottom: outsets.bottom / scale,
                trailing: outsets.trailing / scale
            )
        )
    }

    mutating func formUnion(_ other: ResolvedFontMetrics) {
        capHeight = max(capHeight, other.capHeight)
        ascender = max(ascender, other.ascender)
        descender = min(descender, other.descender)
        leading = max(leading, other.leading)
        outsets.top = max(outsets.top, other.outsets.top)
        outsets.leading = max(outsets.leading, other.outsets.leading)
        outsets.bottom = max(outsets.bottom, other.outsets.bottom)
        outsets.trailing = max(outsets.trailing, other.outsets.trailing)
    }
}

private protocol VVDFontBackedTypeface: Typeface {
    var font: VVD.Font { get }
}

extension VVDFontBackedTypeface {
    var lineHeight: CGFloat { font.height }
    var ascender: CGFloat { font.ascender }
    var descender: CGFloat { font.descender }
    var decorationMetrics: TypefaceDecorationMetrics? {
        typefaceDecorationMetrics(for: font)
    }

    var resolvedMetrics: ResolvedFontMetrics {
        let metrics = font.baseMetrics
        let capHeight = font.glyphMetrics(for: UnicodeScalar("H"))?.bearing.y
            ?? metrics.ascender
        return ResolvedFontMetrics(
            capHeight: capHeight,
            ascender: metrics.ascender,
            descender: metrics.descender,
            leading: max(metrics.height - (metrics.ascender - metrics.descender), 0)
        )
    }

    var identifier: String {
        if let data = font.fontData {
            return "\(font.familyName):\(unsafeBitCast(data.address, to: Int.self))"
        } else {
            return "<\(font.filePath)>"
        }
    }

    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        font.kernAdvance(left: left, right: right)
    }

    func isEqual(to: any Typeface) -> Bool {
        if let other = to as? Self {
            return font === other.font
        }
        return false
    }

    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(Self.self))
        hasher.combine(ObjectIdentifier(font))
    }
}

private struct ScaleInvariantTypefaceMetrics {
    let font: VVD.Font
    let renderScale: CGFloat
    let embolden: CGFloat
    let decorationMetrics: TypefaceDecorationMetrics?

    init(
        font: VVD.Font,
        renderScale: CGFloat,
        embolden: CGFloat
    ) {
        self.font = font
        self.renderScale = renderScale
        self.embolden = embolden
        self.decorationMetrics = typefaceDecorationMetrics(
            for: font
        )?.scaled(by: renderScale)
    }

    var lineHeight: CGFloat { font.height * renderScale }
    var ascender: CGFloat { font.ascender * renderScale }
    var descender: CGFloat { font.descender * renderScale }

    var resolvedMetrics: ResolvedFontMetrics {
        let metrics = font.baseMetrics
        let capHeight = font.glyphMetrics(
            for: UnicodeScalar("H"),
            embolden: embolden
        )?.bearing.y ?? metrics.ascender
        return ResolvedFontMetrics(
            capHeight: capHeight * renderScale,
            ascender: metrics.ascender * renderScale,
            descender: metrics.descender * renderScale,
            leading: max(
                metrics.height - (metrics.ascender - metrics.descender),
                0
            ) * renderScale
        )
    }

    func glyphMetrics(for scalar: UnicodeScalar) -> TypefaceGlyphMetrics? {
        guard let metrics = font.glyphMetrics(
            for: scalar,
            embolden: embolden
        ) else {
            return nil
        }
        return TypefaceGlyphMetrics(
            advance: metrics.advance * renderScale,
            ascender: metrics.ascender * renderScale,
            descender: metrics.descender * renderScale
        )
    }

    func kernAdvance(
        left: UnicodeScalar,
        right: UnicodeScalar
    ) -> CGPoint {
        font.kernAdvance(left: left, right: right) * renderScale
    }
}

struct TextureTypeface: VVDFontBackedTypeface {
    let textureFont: VVD.TextureFont
    private let layoutMetrics: ScaleInvariantTypefaceMetrics?
    let decorationMetrics: TypefaceDecorationMetrics?
    typealias GlyphData = VVD.TextureFont.GlyphData

    init(
        textureFont: VVD.TextureFont,
        layoutFont: VVD.Font? = nil,
        renderScale: CGFloat = 1,
        logicalEmbolden: CGFloat = 0
    ) {
        let layoutMetrics = layoutFont.map {
            ScaleInvariantTypefaceMetrics(
                font: $0,
                renderScale: renderScale,
                embolden: logicalEmbolden
            )
        }
        self.textureFont = textureFont
        self.layoutMetrics = layoutMetrics
        self.decorationMetrics = layoutMetrics?.decorationMetrics ??
            typefaceDecorationMetrics(for: textureFont)
    }

    var font: VVD.Font { textureFont }

    var lineHeight: CGFloat {
        layoutMetrics?.lineHeight ?? font.height
    }

    var ascender: CGFloat {
        layoutMetrics?.ascender ?? font.ascender
    }

    var descender: CGFloat {
        layoutMetrics?.descender ?? font.descender
    }

    var resolvedMetrics: ResolvedFontMetrics {
        layoutMetrics?.resolvedMetrics ?? {
            let metrics = font.baseMetrics
            let capHeight = font.glyphMetrics(
                for: UnicodeScalar("H")
            )?.bearing.y ?? metrics.ascender
            return ResolvedFontMetrics(
                capHeight: capHeight,
                ascender: metrics.ascender,
                descender: metrics.descender,
                leading: max(
                    metrics.height - (metrics.ascender - metrics.descender),
                    0
                )
            )
        }()
    }

    func hasGlyph(for c: UnicodeScalar) -> Bool {
        textureFont.hasGlyph(for: c)
    }

    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? {
        if let data = textureFont.glyphData(for: c) {
            return .texture(data)
        }
        return nil
    }

    func glyphMetrics(for c: UnicodeScalar) -> TypefaceGlyphMetrics? {
        if let layoutMetrics {
            return layoutMetrics.glyphMetrics(for: c)
        }
        guard let metrics = textureFont.glyphMetrics(
            for: c,
            embolden: textureFont.boldStrength
        ) else {
            return nil
        }
        return TypefaceGlyphMetrics(
            advance: metrics.advance,
            ascender: metrics.ascender,
            descender: metrics.descender
        )
    }

    func kernAdvance(
        left: UnicodeScalar,
        right: UnicodeScalar
    ) -> CGPoint {
        layoutMetrics?.kernAdvance(left: left, right: right)
            ?? font.kernAdvance(left: left, right: right)
    }

    func purgeResources(reason: ResourcePurgeReason) {
        textureFont.clearCache()
    }
}

final class VectorTypeface: VVDFontBackedTypeface {
    let font: VVD.Font
    let embolden: CGFloat
    let outlineThickness: CGFloat
    private let layoutMetrics: ScaleInvariantTypefaceMetrics?
    let decorationMetrics: TypefaceDecorationMetrics?

    struct GlyphData: @unchecked Sendable {
        let metrics: VVD.Font.GlyphMetrics
        let path: Path
    }

    private enum CacheEntry: Sendable {
        case glyph(GlyphData)
        case unavailable
    }

    private let cache = Mutex<[UnicodeScalar: CacheEntry]>([:])

    init(font: VVD.Font,
         embolden: CGFloat = 0,
         outlineThickness: CGFloat = 0,
         layoutFont: VVD.Font? = nil,
         renderScale: CGFloat = 1,
         logicalEmbolden: CGFloat? = nil) {
        let layoutMetrics = layoutFont.map {
            ScaleInvariantTypefaceMetrics(
                font: $0,
                renderScale: renderScale,
                embolden: logicalEmbolden ?? embolden
            )
        }
        self.font = font
        self.embolden = embolden
        self.outlineThickness = outlineThickness
        self.layoutMetrics = layoutMetrics
        self.decorationMetrics = layoutMetrics?.decorationMetrics ??
            typefaceDecorationMetrics(for: font)
    }

    var lineHeight: CGFloat {
        layoutMetrics?.lineHeight ?? font.height
    }

    var ascender: CGFloat {
        layoutMetrics?.ascender ?? font.ascender
    }

    var descender: CGFloat {
        layoutMetrics?.descender ?? font.descender
    }

    var resolvedMetrics: ResolvedFontMetrics {
        layoutMetrics?.resolvedMetrics ?? {
            let metrics = font.baseMetrics
            let capHeight = font.glyphMetrics(
                for: UnicodeScalar("H"),
                embolden: embolden
            )?.bearing.y ?? metrics.ascender
            return ResolvedFontMetrics(
                capHeight: capHeight,
                ascender: metrics.ascender,
                descender: metrics.descender,
                leading: max(
                    metrics.height - (metrics.ascender - metrics.descender),
                    0
                )
            )
        }()
    }

    func hasGlyph(for c: UnicodeScalar) -> Bool {
        font.hasGlyph(for: c)
    }

    func glyphMetrics(for c: UnicodeScalar) -> TypefaceGlyphMetrics? {
        if let layoutMetrics {
            return layoutMetrics.glyphMetrics(for: c)
        }
        guard let metrics = font.glyphMetrics(
            for: c,
            embolden: embolden
        ) else {
            return nil
        }
        return TypefaceGlyphMetrics(
            advance: metrics.advance,
            ascender: metrics.ascender,
            descender: metrics.descender
        )
    }

    func kernAdvance(
        left: UnicodeScalar,
        right: UnicodeScalar
    ) -> CGPoint {
        layoutMetrics?.kernAdvance(left: left, right: right)
            ?? font.kernAdvance(left: left, right: right)
    }

    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? {
        if let cached = cache.withLock({ $0[c] }) {
            switch cached {
            case let .glyph(data):
                return .vector(data)
            case .unavailable:
                return nil
            }
        }

        var path = Path()
        var hasOpenContour = false

        let metrics = font.decomposeGlyphOutline(
            for: c,
            embolden: embolden,
            outline: outlineThickness) { command in
            switch command {
            case .move(to: let p):
                if hasOpenContour {
                    path.closeSubpath()
                }
                path.move(to: p)
                hasOpenContour = true
            case .line(to: let p):
                path.addLine(to: p)
            case .quadCurve(to: let p, control: let c):
                path.addQuadCurve(to: p, control: c)
            case .curve(to: let p, control1: let c1, control2: let c2):
                path.addCurve(to: p, control1: c1, control2: c2)
            }
        }
        if hasOpenContour {
            path.closeSubpath()
        }
        path = path.applying(CGAffineTransform(scaleX: 1, y: -1))
        guard let metrics else {
            cache.withLock { cache in
                cache[c] = cache[c] ?? .unavailable
            }
            return nil
        }

        let result = GlyphData(metrics: metrics, path: path)
        let cached = cache.withLock { cache in
            let cached = cache[c] ?? .glyph(result)
            cache[c] = cached
            return cached
        }
        switch cached {
        case let .glyph(data):
            return .vector(data)
        case .unavailable:
            return nil
        }
    }

    func purgeResources(reason: ResourcePurgeReason) {
        font.clearCache()
        cache.withLock { $0.removeAll() }
    }
}

protocol TypefaceProvider {
    func isEqual(to: any TypefaceProvider) -> Bool
    func hash(into hasher: inout Hasher)
    func resolved(in environment: EnvironmentValues) -> Self

    func makeTypeface(
        _: AppContext,
        dpi: UInt32
    ) -> Typeface?

    var isShareable: Bool { get }
}

extension TypefaceProvider {
    var isShareable: Bool { true }

    func resolved(in environment: EnvironmentValues) -> Self {
        self
    }
}

struct SystemFontProvider: TypefaceProvider {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let renderingMode: Font.RenderingMode
    let isItalic: Bool

    init(size: CGFloat,
         weight: Font.Weight,
         design: Font.Design,
         renderingMode: Font.RenderingMode = .automatic,
         isItalic: Bool = false) {
        self.size = size
        self.weight = weight
        self.design = design
        self.renderingMode = renderingMode
        self.isItalic = isItalic
    }

    static func embolden(for weight: Font.Weight) -> CGFloat {
        let emboldenFactor = 1.0
        return ((weight.value - 400.0) / 300.0) * emboldenFactor
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
                    isItalic: isItalic)
    }

    func isEqual(to: any TypefaceProvider) -> Bool {
        if let other = to as? Self {
            return self.size == other.size && 
                   self.weight == other.weight &&
                   self.design == other.design &&
                   self.renderingMode == other.renderingMode &&
                   self.isItalic == other.isItalic
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(size)
        hasher.combine(weight)
        hasher.combine(design)
        hasher.combine(renderingMode)
        hasher.combine(isItalic)
    }

    func makeTypeface(
        _ context: AppContext,
        dpi: UInt32
    ) -> Typeface? {
        precondition(dpi > 0, "The font DPI must be positive.")
        let contentScaleFactor = CGFloat(dpi) / CGFloat(defaultDPI)
        if let url = isItalic ? defaultItalicFontURL : defaultFontURL {
            var data = context.resourceData(forURL: url)
            if data == nil {
                do {
                    Log.debug("Loading font resource: \(url)")
                    let d = try Data(contentsOf: url, options: [])
                    data = d.makeFixedAddressStorage()
                    if data != nil {
                        context.setResource(data: data, forURL: url)
                    }
                } catch {
                    Log.error("Error on loading data: \(error)")
                }
            }
            if let data {
                let logicalEmbolden = Self.embolden(for: self.weight)
                guard let layoutFont = VVD.Font(data: data) else {
                    return nil
                }
                layoutFont.setStyle(
                    pointSize: self.size,
                    dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
                )
                switch renderingMode {
                case .automatic:
                    fatalError("Unresolved font rendering mode")
                case let .bitmap(options):
                    guard let device = context.graphicsDeviceContext,
                          let font = VVD.TextureFont(deviceContext: device,
                                                     data: data) else {
                        return nil
                    }
                    font.boldStrength =
                        logicalEmbolden * contentScaleFactor
                    font.outlineThickness =
                        options.outlineThickness * contentScaleFactor
                    font.isBitmapPreferred = options.isBitmapPreferred
                    font.isColorEnabled = options.isColorEnabled
                    font.setStyle(pointSize: self.size,
                                  dpi: (dpi, dpi))
                    return TextureTypeface(
                        textureFont: font,
                        layoutFont: layoutFont,
                        renderScale: contentScaleFactor,
                        logicalEmbolden: logicalEmbolden
                    )
                case let .vector(options):
                    guard let font = VVD.Font(data: data) else {
                        return nil
                    }
                    font.setStyle(pointSize: self.size,
                                  dpi: (dpi, dpi))
                    return VectorTypeface(
                        font: font,
                        embolden:
                            logicalEmbolden * contentScaleFactor,
                        outlineThickness:
                            options.outlineThickness * contentScaleFactor,
                        layoutFont: layoutFont,
                        renderScale: contentScaleFactor,
                        logicalEmbolden: logicalEmbolden
                    )
                }
            }
        }
        return nil
    }
}

struct CustomFontProvider: TypefaceProvider {
    let name: String
    let size: CGFloat

    init(name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    func isEqual(to: any TypefaceProvider) -> Bool {
        if let other = to as? Self {
            return self.name == other.name &&
                   self.size == other.size
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(size)
    }

    func makeTypeface(
        _ context: AppContext,
        dpi: UInt32
    ) -> Typeface? {
        nil
    }
}

struct FixedFontProvider: TypefaceProvider {
    let face: any Typeface

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

    var fallbackTypefaces: [Typeface] {
        []
    }

    func resolved(in environment: EnvironmentValues) -> Font {
        Font(provider: provider.resolved(in: environment))
    }

    var pointSizeForSymbolMetrics: CGFloat? {
        switch provider.fontBox {
        case let system as SystemFontProvider:
            system.size
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

    public enum Design: Hashable {
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
        guard let system = provider.fontBox as? SystemFontProvider else {
            return self
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
        guard isActive,
              let system = provider.fontBox as? SystemFontProvider else {
            return self
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

    public static let largeTitle = Font.system(Font.TextStyle.largeTitle)
    public static let title = Font.system(Font.TextStyle.title)
    public static let headline = Font.system(Font.TextStyle.headline)
    public static let subheadline = Font.system(Font.TextStyle.subheadline)
    public static let body = Font.system(Font.TextStyle.body)
    public static let callout = Font.system(Font.TextStyle.callout)
    public static let footnote = Font.system(Font.TextStyle.footnote)
    public static let caption = Font.system(Font.TextStyle.caption)
}
