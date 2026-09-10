//
//  File: FontFallback.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
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
        features: [TypefaceShapingFeature]
    ) -> TypefaceShapedText? {
        base.shape(
            text,
            direction: direction,
            language: language,
            features: features
        )
    }

    var lineHeight: CGFloat { base.lineHeight }
    var ascender: CGFloat { base.ascender }
    var descender: CGFloat { base.descender }
    var decorationMetrics: TypefaceDecorationMetrics? {
        base.decorationMetrics
    }
    var resolvedMetrics: ResolvedFontMetrics { base.resolvedMetrics }
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
    let base: Typeface
    let features: [TypefaceShapingFeature]
    var isEmojiFallback: Bool { base.isEmojiFallback }
    var hasColorGlyphs: Bool { base.hasColorGlyphs }

    init(_ base: Typeface, features: [TypefaceShapingFeature]) {
        precondition(!features.isEmpty)
        self.base = base
        self.features = features
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
        features requestedFeatures: [TypefaceShapingFeature]
    ) -> TypefaceShapedText? {
        base.shape(
            text,
            direction: direction,
            language: language,
            features: features + requestedFeatures
        )
    }

    var lineHeight: CGFloat { base.lineHeight }
    var ascender: CGFloat { base.ascender }
    var descender: CGFloat { base.descender }
    var decorationMetrics: TypefaceDecorationMetrics? {
        base.decorationMetrics
    }
    var resolvedMetrics: ResolvedFontMetrics { base.resolvedMetrics }
    var identifier: String {
        "features:\(features):\(base.identifier)"
    }

    func isEqual(to other: any Typeface) -> Bool {
        guard let other = other as? ShapingFeatureTypeface else {
            return false
        }
        return features == other.features && base.isEqual(to: other.base)
    }

    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(ShapingFeatureTypeface.self))
        hasher.combine(features)
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
        features: [TypefaceShapingFeature]
    ) -> TypefaceShapedText? {
        resolved.shape(
            text,
            direction: direction,
            language: language,
            features: features
        )
    }

    var lineHeight: CGFloat { resolved.lineHeight }
    var ascender: CGFloat { resolved.ascender }
    var descender: CGFloat { resolved.descender }
    var decorationMetrics: TypefaceDecorationMetrics? {
        resolved.decorationMetrics
    }
    var resolvedMetrics: ResolvedFontMetrics { resolved.resolvedMetrics }

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
    var shapingFeatures: [TypefaceShapingFeature] = []

    var runFaces: [Typeface] {
        let ordinaryFaces = ordinaryFaces.map(applyingShapingFeatures)
        guard let missingGlyphFace else { return ordinaryFaces }
        return ordinaryFaces + [TerminalFallbackTypeface(
            applyingShapingFeatures(missingGlyphFace)
        )]
    }

    private func applyingShapingFeatures(_ face: Typeface) -> Typeface {
        guard !shapingFeatures.isEmpty else { return face }
        return ShapingFeatureTypeface(face, features: shapingFeatures)
    }
}
