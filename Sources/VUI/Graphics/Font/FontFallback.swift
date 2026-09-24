//
//  File: FontFallback.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD
import Synchronization

/// A terminal face is intentionally invisible to ordinary glyph lookup. Its
/// wrapped glyph is used only by the explicit missing-glyph branch.
final class TerminalFallbackTypeface: Typeface {
    let base: Typeface

    init(_ base: Typeface) {
        self.base = base
    }

    func glyph(for scalar: UnicodeScalar) -> TypefaceGlyph? {
        base.glyph(for: scalar)
    }

    func glyph(at index: UInt32) -> TypefaceGlyph? {
        base.glyph(at: index)
    }

    func glyphMetrics(for scalar: UnicodeScalar) -> TypefaceGlyphMetrics? {
        base.glyphMetrics(for: scalar)
    }

    func glyphMetrics(at index: UInt32) -> TypefaceGlyphMetrics? {
        base.glyphMetrics(at: index)
    }

    func glyphBounds(at index: UInt32) -> CGRect? { base.glyphBounds(at: index) }
    func allowsMarkComposition(at index: UInt32) -> Bool {
        base.allowsMarkComposition(at: index)
    }
    func glyphOutline(at index: UInt32) -> Path? { base.glyphOutline(at: index) }

    func kernAdvance(
        left: UnicodeScalar,
        right: UnicodeScalar
    ) -> CGPoint {
        base.kernAdvance(left: left, right: right)
    }

    func hasGlyph(for _: UnicodeScalar) -> Bool {
        false
    }

    func shape(
        _ text: String,
        direction: TypefaceShapingDirection?,
        language: String?,
        features: [TypefaceShapingFeature],
        optionalLigatureBoundaries: [Int],
        positioningRunBoundaries: [Int],
        sourceRunBoundaries: [Int],
        retainsDeletedGlyphs: Bool,
        allowsLeadingMarkBase: Bool,
        characterInput: VVD.CharacterComposer.Input?
    ) -> TypefaceShapedText? {
        base.shape(
            text,
            direction: direction,
            language: language,
            features: features,
            optionalLigatureBoundaries: optionalLigatureBoundaries,
            positioningRunBoundaries: positioningRunBoundaries,
            sourceRunBoundaries: sourceRunBoundaries,
            retainsDeletedGlyphs: retainsDeletedGlyphs,
            allowsLeadingMarkBase: allowsLeadingMarkBase,
            characterInput: characterInput
        )
    }

    var selectedFont: SelectedFont? { base.selectedFont }
    var featureCatalog: VVD.FontFeatures? { base.featureCatalog }
    var lineHeight: CGFloat { base.lineHeight }
    var ascender: CGFloat { base.ascender }
    var descender: CGFloat { base.descender }
    var decorationMetrics: TypefaceDecorationMetrics? {
        base.decorationMetrics
    }
    var resolvedMetrics: ResolvedFontMetrics { base.resolvedMetrics }
    var glyphCompositionMetrics: VVD.GlyphComposer.Metrics? {
        base.glyphCompositionMetrics
    }
    var designMetrics: TypefaceDesignMetrics? { base.designMetrics }
    var outsetAttributes: FontOutsetAttributes? { base.outsetAttributes }
    var identifier: String { "terminal:\(base.identifier)" }

    func isEqual(to other: any Typeface) -> Bool {
        guard let other = other as? TerminalFallbackTypeface else {
            return false
        }
        return base.isEqual(to: other.base)
    }

    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(TerminalFallbackTypeface.self))
        base.hashIdentity(into: &hasher)
    }

    func purgeResources(reason: ResourcePurgeReason) {
        base.purgeResources(reason: reason)
    }
}

final class ShapingFeatureTypeface: Typeface {
    private struct Selection: Sendable {
        let catalog: VVD.FontFeatures
        let settings: [VVD.FontFeatures.Setting]
    }

    private let selection = Mutex<Selection?>(nil)
    let base: Typeface
    let features: [TypefaceShapingFeature]
    let isSystemFont: Bool
    let descriptorFeatures: [TypefaceShapingFeature]?
    let originalFeatures: [TypefaceShapingFeature]
    let descriptorLanguage: String?
    let fontLanguage: String?
    let fontFlags: UInt32
    var isEmojiFallback: Bool { base.isEmojiFallback }
    var hasColorGlyphs: Bool { base.hasColorGlyphs }

    init(_ base: Typeface, features: [TypefaceShapingFeature],
         isSystemFont: Bool = false, isFallback: Bool = false,
         fontLanguage: String? = nil, fontFlags: UInt32? = nil,
         retainsDescriptorAttributes: Bool = true) {
        let wrapped = base as? ShapingFeatureTypeface
        let ownFeatures = retainsDescriptorAttributes ? wrapped?.features ?? [] : []
        self.base = wrapped?.base ?? base
        self.isSystemFont = isSystemFont
        self.descriptorLanguage = isFallback && retainsDescriptorAttributes ? wrapped?.fontLanguage : nil
        self.fontLanguage = isFallback ? nil : fontLanguage ?? wrapped?.fontLanguage
        self.fontFlags = fontFlags ?? SelectedFont.constructionFlags(language: self.fontLanguage)
        if isFallback {
            self.descriptorFeatures = retainsDescriptorAttributes ? wrapped?.features : nil
            self.features = self.fontFlags & 8 != 0 ? [] : features.isEmpty ? ownFeatures : features
            self.originalFeatures = self.fontFlags & 8 == 0 && isSystemFont && features.isEmpty
                ? VVD.FontFeatures.cascadeRequests(ownFeatures) : []
        } else {
            self.descriptorFeatures = nil
            self.features = ownFeatures + features
            self.originalFeatures = isSystemFont
                ? VVD.FontFeatures.cascadeRequests(self.features) : []
        }
    }

    func glyph(for scalar: UnicodeScalar) -> TypefaceGlyph? {
        base.glyph(for: scalar)
    }

    func glyph(at index: UInt32) -> TypefaceGlyph? {
        base.glyph(at: index)
    }

    func glyphMetrics(for scalar: UnicodeScalar) -> TypefaceGlyphMetrics? {
        base.glyphMetrics(for: scalar)
    }

    func glyphMetrics(at index: UInt32) -> TypefaceGlyphMetrics? {
        base.glyphMetrics(at: index)
    }

    func glyphBounds(at index: UInt32) -> CGRect? { base.glyphBounds(at: index) }
    func allowsMarkComposition(at index: UInt32) -> Bool {
        base.allowsMarkComposition(at: index)
    }
    func glyphOutline(at index: UInt32) -> Path? { base.glyphOutline(at: index) }

    func kernAdvance(
        left: UnicodeScalar,
        right: UnicodeScalar
    ) -> CGPoint {
        base.kernAdvance(left: left, right: right)
    }

    func hasGlyph(for scalar: UnicodeScalar) -> Bool {
        base.hasGlyph(for: scalar)
    }

    func shape(
        _ text: String,
        direction: TypefaceShapingDirection?,
        language: String?,
        features requestedFeatures: [TypefaceShapingFeature],
        optionalLigatureBoundaries: [Int],
        positioningRunBoundaries: [Int],
        sourceRunBoundaries: [Int],
        retainsDeletedGlyphs: Bool,
        allowsLeadingMarkBase: Bool,
        characterInput: VVD.CharacterComposer.Input?
    ) -> TypefaceShapedText? {
        let selectedFeatures: [TypefaceShapingFeature]
        let selected = features.isEmpty ? nil : resolvedSelection
        if let selected {
            selectedFeatures = selected.catalog.shapingFeatures(selected.settings,
                vertical: direction == .topToBottom || direction == .bottomToTop)
        } else {
            selectedFeatures = features
        }
        return base.shape(
            text,
            direction: direction,
            language: language,
            features: selectedFeatures + requestedFeatures,
            optionalLigatureBoundaries: optionalLigatureBoundaries,
            positioningRunBoundaries: positioningRunBoundaries,
            sourceRunBoundaries: sourceRunBoundaries,
            retainsDeletedGlyphs: retainsDeletedGlyphs,
            allowsLeadingMarkBase: allowsLeadingMarkBase,
            characterInput: characterInput
        )
    }

    private var resolvedSelection: Selection? {
        selection.withLock { selected in
            if let selected { return selected }
            guard let catalog = base.featureCatalog else { return nil }
            let resolved = Selection(catalog: catalog, settings: catalog.select(features))
            selected = resolved
            return resolved
        }
    }

    var selectedFont: SelectedFont? {
        guard var font = base.selectedFont else { return nil }
        if !features.isEmpty {
            guard let selection = resolvedSelection else { return nil }
            font.features = selection.settings
        }
        font.descriptor.isSystemFont = isSystemFont
        font.descriptor.featureRequests = descriptorFeatures
        font.descriptor.language = descriptorLanguage
        font.originalFeatures = originalFeatures
        font.language = fontLanguage
        font.flags = fontFlags
        if fontFlags & 8 != 0 { font.variationExtras = nil }
        return font
    }

    var featureCatalog: VVD.FontFeatures? { base.featureCatalog }
    var lineHeight: CGFloat { base.lineHeight }
    var ascender: CGFloat { base.ascender }
    var descender: CGFloat { base.descender }
    var decorationMetrics: TypefaceDecorationMetrics? {
        base.decorationMetrics
    }
    var resolvedMetrics: ResolvedFontMetrics { base.resolvedMetrics }
    var glyphCompositionMetrics: VVD.GlyphComposer.Metrics? {
        base.glyphCompositionMetrics
    }
    var designMetrics: TypefaceDesignMetrics? { base.designMetrics }
    var outsetAttributes: FontOutsetAttributes? { base.outsetAttributes }
    var identifier: String {
        "features:\(features):\(base.identifier)"
    }

    func isEqual(to other: any Typeface) -> Bool {
        guard let other = other as? ShapingFeatureTypeface else {
            return false
        }
        return features == other.features && isSystemFont == other.isSystemFont &&
            descriptorFeatures == other.descriptorFeatures && originalFeatures == other.originalFeatures &&
            descriptorLanguage == other.descriptorLanguage && fontLanguage == other.fontLanguage &&
            fontFlags == other.fontFlags &&
            base.isEqual(to: other.base)
    }

    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(ShapingFeatureTypeface.self))
        hasher.combine(features)
        hasher.combine(isSystemFont)
        hasher.combine(descriptorFeatures)
        hasher.combine(originalFeatures)
        hasher.combine(descriptorLanguage)
        hasher.combine(fontLanguage)
        hasher.combine(fontFlags)
        base.hashIdentity(into: &hasher)
    }

    func purgeResources(reason: ResourcePurgeReason) {
        base.purgeResources(reason: reason)
    }
}

final class DeferredTypeface: Typeface {
    private struct State: @unchecked Sendable {
        var resolved: Typeface? = nil
    }

    private let font: Font
    private let context: SceneResources
    private let dpi: UInt32
    private let state = Mutex(State())
    let identifier: String
    let isEmojiFallback: Bool
    var hasColorGlyphs: Bool { resolved.hasColorGlyphs }

    init(
        font: Font,
        context: SceneResources,
        dpi: UInt32,
        identifier: String,
        isEmojiFallback: Bool = false
    ) {
        self.font = font
        self.context = context
        self.dpi = dpi
        self.identifier = "deferred:\(identifier)"
        self.isEmojiFallback = isEmojiFallback
    }

    private var resolved: Typeface {
        state.withLock { state in
            if let resolved = state.resolved {
                return resolved
            }
            guard let resolved = font.typeface(
                forContext: context,
                dpi: dpi
            ) else {
                fatalError("Unable to load bundled font: \(identifier)")
            }
            state.resolved = resolved
            return resolved
        }
    }

    func glyph(for scalar: UnicodeScalar) -> TypefaceGlyph? {
        resolved.glyph(for: scalar)
    }

    func glyph(at index: UInt32) -> TypefaceGlyph? {
        resolved.glyph(at: index)
    }

    func glyphMetrics(for scalar: UnicodeScalar) -> TypefaceGlyphMetrics? {
        resolved.glyphMetrics(for: scalar)
    }

    func glyphMetrics(at index: UInt32) -> TypefaceGlyphMetrics? {
        resolved.glyphMetrics(at: index)
    }

    func glyphBounds(at index: UInt32) -> CGRect? { resolved.glyphBounds(at: index) }
    func allowsMarkComposition(at index: UInt32) -> Bool {
        resolved.allowsMarkComposition(at: index)
    }
    func glyphOutline(at index: UInt32) -> Path? { resolved.glyphOutline(at: index) }

    func kernAdvance(
        left: UnicodeScalar,
        right: UnicodeScalar
    ) -> CGPoint {
        resolved.kernAdvance(left: left, right: right)
    }

    func hasGlyph(for scalar: UnicodeScalar) -> Bool {
        resolved.hasGlyph(for: scalar)
    }

    func shape(
        _ text: String,
        direction: TypefaceShapingDirection?,
        language: String?,
        features: [TypefaceShapingFeature],
        optionalLigatureBoundaries: [Int],
        positioningRunBoundaries: [Int],
        sourceRunBoundaries: [Int],
        retainsDeletedGlyphs: Bool,
        allowsLeadingMarkBase: Bool,
        characterInput: VVD.CharacterComposer.Input?
    ) -> TypefaceShapedText? {
        resolved.shape(
            text,
            direction: direction,
            language: language,
            features: features,
            optionalLigatureBoundaries: optionalLigatureBoundaries,
            positioningRunBoundaries: positioningRunBoundaries,
            sourceRunBoundaries: sourceRunBoundaries,
            retainsDeletedGlyphs: retainsDeletedGlyphs,
            allowsLeadingMarkBase: allowsLeadingMarkBase,
            characterInput: characterInput
        )
    }

    var selectedFont: SelectedFont? { resolved.selectedFont }
    var featureCatalog: VVD.FontFeatures? { resolved.featureCatalog }
    var lineHeight: CGFloat { resolved.lineHeight }
    var ascender: CGFloat { resolved.ascender }
    var descender: CGFloat { resolved.descender }
    var decorationMetrics: TypefaceDecorationMetrics? {
        resolved.decorationMetrics
    }
    var resolvedMetrics: ResolvedFontMetrics { resolved.resolvedMetrics }
    var glyphCompositionMetrics: VVD.GlyphComposer.Metrics? {
        resolved.glyphCompositionMetrics
    }
    var designMetrics: TypefaceDesignMetrics? { resolved.designMetrics }
    var outsetAttributes: FontOutsetAttributes? { resolved.outsetAttributes }

    func isEqual(to other: any Typeface) -> Bool {
        guard let other = other as? DeferredTypeface else { return false }
        return font == other.font &&
            isEmojiFallback == other.isEmojiFallback &&
            dpi == other.dpi &&
            context === other.context
    }

    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(font)
        hasher.combine(isEmojiFallback)
        hasher.combine(dpi)
        hasher.combine(ObjectIdentifier(context))
    }

    func purgeResources(reason: ResourcePurgeReason) {
        state.withLock { state in
            state.resolved?.purgeResources(reason: reason)
        }
    }
}

struct TypefaceCascade {
    let ordinaryFaces: [Typeface]
    let missingGlyphFace: Typeface?
    var primaryIndex: Int? = 0
    var isSystemFont = false
    var fontLanguage: String?
    var shapingFeatures: [TypefaceShapingFeature] = []
    var fallbackFeatures: [TypefaceShapingFeature] = []
    // Indices refer to the immutable ordinary-face array. Locale/user entries
    // and backend defaults retain distinct construction requests after ordering.
    var defaultFallbackIndices = IndexSet()

    var runFaces: [Typeface] {
        let language = fontLanguage ?? primaryIndex.flatMap { index in
            ordinaryFaces.indices.contains(index)
                ? (ordinaryFaces[index] as? ShapingFeatureTypeface)?.fontLanguage : nil
        }
        let primary = primaryIndex.flatMap { index -> Typeface? in
            guard ordinaryFaces.indices.contains(index) else { return nil }
            return applyingShapingFeatures(ordinaryFaces[index], isPrimary: true,
                language: language, flags: SelectedFont.constructionFlags(language: language))
        }
        let selected = primary?.selectedFont
        let inheritedFlags = selected?.flags ?? SelectedFont.constructionFlags(language: language)
        let hasExtras = selected?.hasExtras == true
        func fallback(_ face: Typeface, isDefault: Bool) -> Typeface {
            let request: UInt32 = isDefault ? 8 : 0
            // The primary's retained extras gate the request independently of
            // the selected descriptor. Supported descriptors use default options.
            let flags = inheritedFlags | (hasExtras ? 0 : request) | 0xc0
            return applyingShapingFeatures(face, isPrimary: false, language: language,
                flags: flags, retainsDescriptorAttributes: request & 8 == 0)
        }
        let ordinaryFaces = ordinaryFaces.enumerated().map { index, face in
            index == primaryIndex ? primary! : fallback(face, isDefault: defaultFallbackIndices.contains(index))
        }
        guard let missingGlyphFace else { return ordinaryFaces }
        return ordinaryFaces + [TerminalFallbackTypeface(
            fallback(missingGlyphFace, isDefault: true)
        )]
    }

    private func applyingShapingFeatures(_ face: Typeface, isPrimary: Bool,
                                        language: String?, flags: UInt32,
                                        retainsDescriptorAttributes: Bool = true) -> Typeface {
        let features = isPrimary ? shapingFeatures : fallbackFeatures
        guard flags != 0xc0 || isSystemFont || language != nil || !features.isEmpty ||
                (!isPrimary && face is ShapingFeatureTypeface)
        else { return face }
        return ShapingFeatureTypeface(face, features: features,
            isSystemFont: isSystemFont, isFallback: !isPrimary,
            fontLanguage: isPrimary ? language : nil, fontFlags: flags,
            retainsDescriptorAttributes: retainsDescriptorAttributes)
    }
}
