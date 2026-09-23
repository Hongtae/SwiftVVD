//
//  File: Typeface.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

enum TypefaceGlyph {
    case texture(TextureTypeface.GlyphData, scale: CGFloat = 1)
    case vector(VectorTypeface.GlyphData)
}

struct TypefaceGlyphMetrics {
    var advance: CGSize
    var ascender: CGFloat
    var descender: CGFloat
}

typealias TypefaceDesignMetrics = VVD.Font.DesignMetrics
typealias TypefaceFaceTraits = VVD.Font.FaceTraits
typealias TypefaceShapingDirection = VVD.Font.ShapingDirection
typealias TypefaceShapingFeature = VVD.Font.ShapingFeature

struct TypefaceShapedGlyph {
    var index: UInt32
    var sourceIndex: Int
    var sourceRange: Range<Int>
    var advance: CGSize
    var offset: CGPoint
}

struct TypefaceShapedText {
    var glyphs: [TypefaceShapedGlyph]
    var direction: TypefaceShapingDirection
}

protocol Typeface {
    func glyph(for c: UnicodeScalar) -> TypefaceGlyph?
    func glyph(at index: UInt32) -> TypefaceGlyph?
    func glyphMetrics(for c: UnicodeScalar) -> TypefaceGlyphMetrics?
    func glyphMetrics(at index: UInt32) -> TypefaceGlyphMetrics?
    func glyphBounds(at index: UInt32) -> CGRect?
    func glyphOutline(at index: UInt32) -> Path?
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint
    func hasGlyph(for: UnicodeScalar) -> Bool
    func shape(
        _ text: String,
        direction: TypefaceShapingDirection?,
        language: String?,
        features: [TypefaceShapingFeature],
        optionalLigatureBoundaries: [Int],
        retainsDeletedGlyphs: Bool,
        characterInput: VVD.CharacterComposer.Input?
    ) -> TypefaceShapedText?

    var selectedFont: SelectedFont? { get }
    var featureCatalog: VVD.FontFeatures? { get }
    var lineHeight: CGFloat { get }
    var ascender: CGFloat { get }
    var descender: CGFloat { get }
    var decorationMetrics: TypefaceDecorationMetrics? { get }
    var resolvedMetrics: ResolvedFontMetrics { get }
    /// Unscaled selected-face metrics, separate from rounded layout and glyph metrics.
    var designMetrics: TypefaceDesignMetrics? { get }
    var outsetAttributes: FontOutsetAttributes? { get }
    var identifier: String { get }
    var isEmojiFallback: Bool { get }
    var hasColorGlyphs: Bool { get }

    func isEqual(to: any Typeface) -> Bool
    func hashIdentity(into hasher: inout Hasher)
    func purgeResources(reason: ResourcePurgeReason)
}

extension Typeface {
    var selectedFont: SelectedFont? { nil }
    var featureCatalog: VVD.FontFeatures? { nil }
    var isEmojiFallback: Bool { false }
    var hasColorGlyphs: Bool { false }
    func glyph(at index: UInt32) -> TypefaceGlyph? { nil }
    func glyphBounds(at index: UInt32) -> CGRect? { nil }
    func glyphOutline(at index: UInt32) -> Path? { nil }

    func shape(
        _ text: String,
        direction: TypefaceShapingDirection?,
        language: String?,
        features: [TypefaceShapingFeature],
        optionalLigatureBoundaries: [Int],
        retainsDeletedGlyphs: Bool,
        characterInput: VVD.CharacterComposer.Input?
    ) -> TypefaceShapedText? {
        nil
    }

    func shape(_ text: String, direction: TypefaceShapingDirection?, language: String?,
               features: [TypefaceShapingFeature]) -> TypefaceShapedText? {
        shape(text, direction: direction, language: language, features: features,
              optionalLigatureBoundaries: [])
    }

    func shape(_ text: String, direction: TypefaceShapingDirection?, language: String?,
               features: [TypefaceShapingFeature], optionalLigatureBoundaries: [Int]) -> TypefaceShapedText? {
        shape(text, direction: direction, language: language, features: features,
              optionalLigatureBoundaries: optionalLigatureBoundaries, retainsDeletedGlyphs: false, characterInput: nil)
    }

    func shape(_ text: String, direction: TypefaceShapingDirection?, language: String?,
               features: [TypefaceShapingFeature], optionalLigatureBoundaries: [Int],
               retainsDeletedGlyphs: Bool) -> TypefaceShapedText? {
        shape(text, direction: direction, language: language, features: features,
              optionalLigatureBoundaries: optionalLigatureBoundaries,
              retainsDeletedGlyphs: retainsDeletedGlyphs, characterInput: nil)
    }

    func glyphMetrics(for c: UnicodeScalar) -> TypefaceGlyphMetrics? {
        guard let glyph = glyph(for: c) else { return nil }
        switch glyph {
        case let .texture(data, scale):
            return TypefaceGlyphMetrics(
                advance: data.advance * scale,
                ascender: data.ascender * scale,
                descender: data.descender * scale
            )
        case let .vector(data):
            return TypefaceGlyphMetrics(
                advance: data.metrics.advance,
                ascender: data.metrics.ascender,
                descender: data.metrics.descender
            )
        }
    }

    func glyphMetrics(at index: UInt32) -> TypefaceGlyphMetrics? {
        guard let glyph = glyph(at: index) else { return nil }
        switch glyph {
        case let .texture(data, scale):
            return TypefaceGlyphMetrics(
                advance: data.advance * scale,
                ascender: data.ascender * scale,
                descender: data.descender * scale
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
    var designMetrics: TypefaceDesignMetrics? { nil }
    var outsetAttributes: FontOutsetAttributes? { nil }

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

protocol VVDFontBackedTypeface: Typeface {
    var font: VVD.Font { get }
    var outlineSource: (font: VVD.Font, scale: CGFloat) { get }
}

extension VVDFontBackedTypeface {
    var featureCatalog: VVD.FontFeatures? { outlineSource.font.featureCatalog }
    private var outlineTransform: CGAffineTransform? {
        let (font, scale) = outlineSource
        guard let metrics = font.designMetrics else { return nil }
        let unit = font.pointSize * scale / CGFloat(metrics.unitsPerEM)
        let dpi = font.dpi
        return CGAffineTransform(scaleX: unit * CGFloat(dpi.x) / 72,
                                 y: unit * CGFloat(dpi.y) / 72)
    }

    func glyphBounds(at index: UInt32) -> CGRect? {
        guard let transform = outlineTransform else { return nil }
        return outlineSource.font.designGlyphBounds(at: index)?.applying(transform)
    }

    func glyphOutline(at index: UInt32) -> Path? {
        guard let transform = outlineTransform else { return nil }
        var path = Path()
        var hasContour = false
        let supported = outlineSource.font.decomposeDesignGlyphOutline(at: index) { command in
            switch command {
            case let .move(point):
                if hasContour { path.closeSubpath() }
                path.move(to: point.applying(transform))
                hasContour = true
            case let .line(point): path.addLine(to: point.applying(transform))
            case let .quadCurve(point, control):
                path.addQuadCurve(to: point.applying(transform), control: control.applying(transform))
            case let .curve(point, a, b):
                path.addCurve(to: point.applying(transform), control1: a.applying(transform),
                              control2: b.applying(transform))
            }
        }
        guard supported else { return nil }
        if hasContour { path.closeSubpath() }
        return path
    }

    var hasColorGlyphs: Bool { font.hasColor }
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
        self.renderScale = renderScale * font.bitmapScale
        self.embolden = embolden
        self.decorationMetrics = typefaceDecorationMetrics(
            for: font
        )?.scaled(by: self.renderScale)
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

    func glyphMetrics(at index: UInt32) -> TypefaceGlyphMetrics? {
        guard let metrics = font.glyphMetrics(
            at: index,
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

    func shape(
        _ text: String,
        direction: TypefaceShapingDirection?,
        language: String?,
        features: [TypefaceShapingFeature],
        optionalLigatureBoundaries: [Int],
        retainsDeletedGlyphs: Bool,
        characterInput: VVD.CharacterComposer.Input?
    ) -> TypefaceShapedText? {
        guard let shaped = font.shape(
            text,
            direction: direction,
            language: language,
            features: features,
            optionalLigatureBoundaries: optionalLigatureBoundaries,
            retainsDeletedGlyphs: retainsDeletedGlyphs,
            characterInput: characterInput
        ) else {
            return nil
        }
        return TypefaceShapedText(
            glyphs: shaped.glyphs.map { glyph in
                TypefaceShapedGlyph(
                    index: glyph.index,
                    sourceIndex: glyph.sourceIndex,
                    sourceRange: glyph.sourceRange,
                    advance: CGSize(
                        width: (glyph.advance.width + (glyph.index == 65535 ? 0 : embolden)) * renderScale,
                        height: glyph.advance.height * renderScale
                    ),
                    offset: glyph.offset * renderScale
                )
            },
            direction: shaped.direction
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
    let selectedFont: SelectedFont?
    let textureFont: VVD.TextureFont
    private let layoutMetrics: ScaleInvariantTypefaceMetrics?
    let decorationMetrics: TypefaceDecorationMetrics?
    typealias GlyphData = VVD.TextureFont.GlyphData

    init(
        textureFont: VVD.TextureFont,
        layoutFont: VVD.Font? = nil,
        renderScale: CGFloat = 1,
        logicalEmbolden: CGFloat = 0,
        selectedFont: SelectedFont? = nil
    ) {
        let metricsFont = layoutFont ?? (textureFont.isScalable ? nil : textureFont)
        let layoutMetrics = metricsFont.map {
            ScaleInvariantTypefaceMetrics(
                font: $0,
                renderScale: layoutFont == nil ? 1 : renderScale,
                embolden: logicalEmbolden
            )
        }
        self.textureFont = textureFont
        self.selectedFont = selectedFont ?? SelectedFont(supplied: layoutFont ?? textureFont,
                                                         syntheticWeight: logicalEmbolden)
        self.layoutMetrics = layoutMetrics
        self.decorationMetrics = layoutMetrics?.decorationMetrics ??
            typefaceDecorationMetrics(for: textureFont)
    }

    var font: VVD.Font { textureFont }

    func withSize(_ size: CGFloat, selectedFont: SelectedFont? = nil,
                  coordinates requestedCoordinates: [UInt32: CGFloat]? = nil) -> Self? {
        guard let copy = textureFont.copy(pointSize: size) as? VVD.TextureFont else { return nil }
        let selected = selectedFont ?? self.selectedFont?.withSize(size)
        let coordinates = requestedCoordinates ?? selected?.opticalConstruction?.selection.rasterCoordinates
        if let coordinates, coordinates != copy.variationCoordinates,
           !copy.setVariationCoordinates(coordinates) { return nil }
        var layoutFont: VVD.Font?
        if let metrics = layoutMetrics {
            guard let resized = metrics.font === textureFont ? copy : metrics.font.copy(pointSize: size) else { return nil }
            layoutFont = resized
            if let coordinates, resized !== copy, coordinates != resized.variationCoordinates,
               !resized.setVariationCoordinates(coordinates) { return nil }
        }
        return Self(textureFont: copy, layoutFont: layoutFont,
                    renderScale: layoutMetrics.map { $0.renderScale / $0.font.bitmapScale } ?? 1,
                    logicalEmbolden: layoutMetrics?.embolden ?? self.selectedFont?.syntheticWeight ?? 0,
                    selectedFont: selected)
    }

    var outlineSource: (font: VVD.Font, scale: CGFloat) {
        (layoutMetrics?.font ?? font, layoutMetrics?.renderScale ?? 1)
    }

    var designMetrics: TypefaceDesignMetrics? {
        (layoutMetrics?.font ?? font).designMetrics
    }

    var outsetAttributes: FontOutsetAttributes? {
        let selected = layoutMetrics?.font ?? font
        let scale = layoutMetrics.map { $0.renderScale / selected.bitmapScale } ?? 1
        return FontOutsetAttributes(face: selected.faceTraits, scale: scale)
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
            return .texture(data, scale: textureFont.bitmapScale)
        }
        return nil
    }

    func glyph(at index: UInt32) -> TypefaceGlyph? {
        textureFont.glyphData(at: index).map {
            .texture($0, scale: textureFont.bitmapScale)
        }
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

    func glyphMetrics(at index: UInt32) -> TypefaceGlyphMetrics? {
        if let layoutMetrics {
            return layoutMetrics.glyphMetrics(at: index)
        }
        guard let metrics = textureFont.glyphMetrics(
            at: index,
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

    func shape(
        _ text: String,
        direction: TypefaceShapingDirection?,
        language: String?,
        features: [TypefaceShapingFeature],
        optionalLigatureBoundaries: [Int],
        retainsDeletedGlyphs: Bool,
        characterInput: VVD.CharacterComposer.Input?
    ) -> TypefaceShapedText? {
        if let layoutMetrics {
            return layoutMetrics.shape(
                text,
                direction: direction,
                language: language,
                features: features,
                optionalLigatureBoundaries: optionalLigatureBoundaries,
                retainsDeletedGlyphs: retainsDeletedGlyphs,
                characterInput: characterInput
            )
        }
        guard let shaped = font.shape(
            text,
            direction: direction,
            language: language,
            features: features,
            optionalLigatureBoundaries: optionalLigatureBoundaries,
            retainsDeletedGlyphs: retainsDeletedGlyphs,
            characterInput: characterInput
        ) else {
            return nil
        }
        return TypefaceShapedText(
            glyphs: shaped.glyphs.map { glyph in
                TypefaceShapedGlyph(
                    index: glyph.index,
                    sourceIndex: glyph.sourceIndex,
                    sourceRange: glyph.sourceRange,
                    advance: CGSize(
                        width: glyph.advance.width + (glyph.index == 65535 ? 0 : textureFont.boldStrength),
                        height: glyph.advance.height
                    ),
                    offset: glyph.offset
                )
            },
            direction: shaped.direction
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

/// Keeps metrics available before a graphics device is needed for glyph artwork.
final class DeferredGlyphTypeface: Typeface {
    private struct State: @unchecked Sendable {
        var glyphs: Typeface?
    }

    let metrics: Typeface
    private let loadGlyphs: () -> Typeface?
    private let state = Mutex(State())

    init(metrics: Typeface, loadGlyphs: @escaping () -> Typeface?) {
        self.metrics = metrics
        self.loadGlyphs = loadGlyphs
    }

    private var glyphs: Typeface? {
        state.withLock {
            if let glyphs = $0.glyphs { return glyphs }
            let glyphs = loadGlyphs()
            $0.glyphs = glyphs
            return glyphs
        }
    }

    func glyph(for scalar: UnicodeScalar) -> TypefaceGlyph? { glyphs?.glyph(for: scalar) }
    func glyph(at index: UInt32) -> TypefaceGlyph? { glyphs?.glyph(at: index) }
    func glyphMetrics(for scalar: UnicodeScalar) -> TypefaceGlyphMetrics? { metrics.glyphMetrics(for: scalar) }
    func glyphMetrics(at index: UInt32) -> TypefaceGlyphMetrics? { metrics.glyphMetrics(at: index) }
    func glyphBounds(at index: UInt32) -> CGRect? { metrics.glyphBounds(at: index) }
    func glyphOutline(at index: UInt32) -> Path? { metrics.glyphOutline(at: index) }
    func hasGlyph(for scalar: UnicodeScalar) -> Bool { metrics.hasGlyph(for: scalar) }
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        metrics.kernAdvance(left: left, right: right)
    }
    func shape(_ text: String, direction: TypefaceShapingDirection?, language: String?,
               features: [TypefaceShapingFeature], optionalLigatureBoundaries: [Int],
               retainsDeletedGlyphs: Bool, characterInput: VVD.CharacterComposer.Input?) -> TypefaceShapedText? {
        metrics.shape(text, direction: direction, language: language, features: features,
                      optionalLigatureBoundaries: optionalLigatureBoundaries,
                      retainsDeletedGlyphs: retainsDeletedGlyphs, characterInput: characterInput)
    }
    var selectedFont: SelectedFont? { metrics.selectedFont }
    var featureCatalog: VVD.FontFeatures? { metrics.featureCatalog }
    var lineHeight: CGFloat { metrics.lineHeight }
    var ascender: CGFloat { metrics.ascender }
    var descender: CGFloat { metrics.descender }
    var decorationMetrics: TypefaceDecorationMetrics? { metrics.decorationMetrics }
    var resolvedMetrics: ResolvedFontMetrics { metrics.resolvedMetrics }
    var designMetrics: TypefaceDesignMetrics? { metrics.designMetrics }
    var outsetAttributes: FontOutsetAttributes? { metrics.outsetAttributes }
    var identifier: String { "deferred-glyphs:\(metrics.identifier)" }
    var hasColorGlyphs: Bool { metrics.hasColorGlyphs }
    func isEqual(to other: Typeface) -> Bool { (other as? Self) === self }
    func hashIdentity(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    func purgeResources(reason: ResourcePurgeReason) {
        metrics.purgeResources(reason: reason)
        state.withLock { $0.glyphs?.purgeResources(reason: reason) }
    }
}

final class VectorTypeface: VVDFontBackedTypeface {
    let selectedFont: SelectedFont?
    let font: VVD.Font
    let embolden: CGFloat
    let outlineThickness: CGFloat
    private let layoutMetrics: ScaleInvariantTypefaceMetrics?
    let decorationMetrics: TypefaceDecorationMetrics?

    var outlineSource: (font: VVD.Font, scale: CGFloat) {
        (layoutMetrics?.font ?? font, layoutMetrics?.renderScale ?? 1)
    }

    struct GlyphData: @unchecked Sendable {
        let metrics: VVD.Font.GlyphMetrics
        let path: Path
    }

    private enum CacheEntry: Sendable {
        case glyph(GlyphData)
        case unavailable
    }

    private let cache = Mutex<[UInt32: CacheEntry]>([:])

    init(font: VVD.Font,
         embolden: CGFloat = 0,
         outlineThickness: CGFloat = 0,
         layoutFont: VVD.Font? = nil,
         renderScale: CGFloat = 1,
         logicalEmbolden: CGFloat? = nil,
         selectedFont: SelectedFont? = nil) {
        let layoutMetrics = layoutFont.map {
            ScaleInvariantTypefaceMetrics(
                font: $0,
                renderScale: renderScale,
                embolden: logicalEmbolden ?? embolden
            )
        }
        self.font = font
        self.embolden = embolden
        self.selectedFont = selectedFont ?? SelectedFont(supplied: layoutFont ?? font,
                                                         syntheticWeight: logicalEmbolden ?? embolden)
        self.outlineThickness = outlineThickness
        self.layoutMetrics = layoutMetrics
        self.decorationMetrics = layoutMetrics?.decorationMetrics ??
            typefaceDecorationMetrics(for: font)
    }

    func withSize(_ size: CGFloat, selectedFont: SelectedFont? = nil,
                  coordinates requestedCoordinates: [UInt32: CGFloat]? = nil) -> VectorTypeface? {
        guard let copy = font.copy(pointSize: size) else { return nil }
        let selected = selectedFont ?? self.selectedFont?.withSize(size)
        let coordinates = requestedCoordinates ?? selected?.opticalConstruction?.selection.rasterCoordinates
        if let coordinates, coordinates != copy.variationCoordinates,
           !copy.setVariationCoordinates(coordinates) { return nil }
        var layoutFont: VVD.Font?
        if let metrics = layoutMetrics {
            guard let resized = metrics.font === font ? copy : metrics.font.copy(pointSize: size) else { return nil }
            layoutFont = resized
            if let coordinates, resized !== copy, coordinates != resized.variationCoordinates,
               !resized.setVariationCoordinates(coordinates) { return nil }
        }
        return VectorTypeface(font: copy, embolden: embolden, outlineThickness: outlineThickness,
                    layoutFont: layoutFont,
                    renderScale: layoutMetrics.map { $0.renderScale / $0.font.bitmapScale } ?? 1,
                    logicalEmbolden: layoutMetrics?.embolden ?? self.selectedFont?.syntheticWeight ?? embolden,
                    selectedFont: selected)
    }

    var designMetrics: TypefaceDesignMetrics? {
        (layoutMetrics?.font ?? font).designMetrics
    }

    var outsetAttributes: FontOutsetAttributes? {
        let selected = layoutMetrics?.font ?? font
        let scale = layoutMetrics.map { $0.renderScale / selected.bitmapScale } ?? 1
        return FontOutsetAttributes(face: selected.faceTraits, scale: scale)
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

    func glyphMetrics(at index: UInt32) -> TypefaceGlyphMetrics? {
        if let layoutMetrics {
            return layoutMetrics.glyphMetrics(at: index)
        }
        guard let metrics = font.glyphMetrics(
            at: index,
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

    func shape(
        _ text: String,
        direction: TypefaceShapingDirection?,
        language: String?,
        features: [TypefaceShapingFeature],
        optionalLigatureBoundaries: [Int],
        retainsDeletedGlyphs: Bool,
        characterInput: VVD.CharacterComposer.Input?
    ) -> TypefaceShapedText? {
        if let layoutMetrics {
            return layoutMetrics.shape(
                text,
                direction: direction,
                language: language,
                features: features,
                optionalLigatureBoundaries: optionalLigatureBoundaries,
                retainsDeletedGlyphs: retainsDeletedGlyphs,
                characterInput: characterInput
            )
        }
        guard let shaped = font.shape(
            text,
            direction: direction,
            language: language,
            features: features,
            optionalLigatureBoundaries: optionalLigatureBoundaries,
            retainsDeletedGlyphs: retainsDeletedGlyphs,
            characterInput: characterInput
        ) else {
            return nil
        }
        return TypefaceShapedText(
            glyphs: shaped.glyphs.map { glyph in
                TypefaceShapedGlyph(
                    index: glyph.index,
                    sourceIndex: glyph.sourceIndex,
                    sourceRange: glyph.sourceRange,
                    advance: CGSize(
                        width: glyph.advance.width + (glyph.index == 65535 ? 0 : embolden),
                        height: glyph.advance.height
                    ),
                    offset: glyph.offset
                )
            },
            direction: shaped.direction
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
        guard let metrics = font.glyphMetrics(
            for: c,
            embolden: embolden
        ) else {
            return nil
        }
        return glyph(at: metrics.index)
    }

    func glyph(at index: UInt32) -> TypefaceGlyph? {
        if let cached = cache.withLock({ $0[index] }) {
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
            at: index,
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
                cache[index] = cache[index] ?? .unavailable
            }
            return nil
        }

        let result = GlyphData(metrics: metrics, path: path)
        let cached = cache.withLock { cache in
            let cached = cache[index] ?? .glyph(result)
            cache[index] = cached
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
