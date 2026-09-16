//
//  File: AttributedText.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension AttributeScopes {
    public var core: CoreAttributes.Type { CoreAttributes.self }

    public struct CoreAttributes: AttributeScope {
        public let font: FontAttribute
        public let foregroundColor: ForegroundColorAttribute
        public let backgroundColor: BackgroundColorAttribute
        public let strikethroughStyle: StrikethroughStyleAttribute
        public let underlineStyle: UnderlineStyleAttribute
        public let kern: KerningAttribute
        public let tracking: TrackingAttribute
        public let baselineOffset: BaselineOffsetAttribute
        public let foundation: AttributeScopes.FoundationAttributes
        let glyphInfo: TextGlyphInfoAttribute
        let adaptiveImageGlyph: TextAdaptiveImageGlyphAttribute
        let textScale: TextScaleAttribute
        let superscript: TextSuperscriptAttribute
        let paragraphAlignment: TextParagraphAlignmentAttribute
        let paragraphWritingDirection: TextParagraphWritingDirectionAttribute
        let lineHeight: TextLineHeightAttribute
    }
}

extension AttributeScopes.CoreAttributes {
    public enum FontAttribute: AttributedStringKey {
        public typealias Value = Font
        public static let name = "VUI.Font"
    }

    public enum ForegroundColorAttribute: AttributedStringKey {
        public typealias Value = Color
        public static let name = "VUI.ForegroundColor"
    }

    public enum BackgroundColorAttribute: AttributedStringKey {
        public typealias Value = Color
        public static let name = "VUI.BackgroundColor"
    }

    public enum StrikethroughStyleAttribute: AttributedStringKey {
        public typealias Value = Text.LineStyle
        public static let name = "VUI.StrikethroughStyle"
    }

    public enum UnderlineStyleAttribute: AttributedStringKey {
        public typealias Value = Text.LineStyle
        public static let name = "VUI.UnderlineStyle"
    }

    public enum KerningAttribute: CodableAttributedStringKey {
        public typealias Value = CGFloat
        public static let name = "VUI.Kern"
    }

    public enum TrackingAttribute: CodableAttributedStringKey {
        public typealias Value = CGFloat
        public static let name = "VUI.Tracking"
    }

    public enum BaselineOffsetAttribute: CodableAttributedStringKey {
        public typealias Value = CGFloat
        public static let name = "VUI.BaselineOffset"
    }
}

extension AttributeDynamicLookup {
    public subscript<T>(
        dynamicMember keyPath: KeyPath<AttributeScopes.CoreAttributes, T>
    ) -> T where T: AttributedStringKey {
        self[T.self]
    }
}

extension AttributedString {
    mutating func _setCoreAttributes(_ attributes: _ResolvedTextRunAttributes) {
        if let value = attributes.font { self.font = value }
        if let value = attributes.foregroundColor { self.foregroundColor = value }
        if let value = attributes.backgroundColor { self.backgroundColor = value }
        if let value = attributes.strikethroughStyle { self.strikethroughStyle = value }
        if let value = attributes.underlineStyle { self.underlineStyle = value }
        if let value = attributes.kern { self.kern = value }
        if let value = attributes.tracking { self.tracking = value }
        if let value = attributes.baselineOffset { self.baselineOffset = value }
    }

    var isStyled: Bool {
        // Command labels classify the presence of supported run attributes;
        // render-time precedence and whether an attribute looks inactive do
        // not change this structural result.
        let hasSupportedAttribute: (AttributedString.Runs.Run) -> Bool = { run in
            run.font != nil ||
                run.foregroundColor != nil ||
                run.backgroundColor != nil ||
                run.strikethroughStyle != nil ||
                run.underlineStyle != nil ||
                run.kern != nil ||
                run.tracking != nil ||
                run.baselineOffset != nil ||
                run.inlinePresentationIntent != nil ||
                run.link != nil
        }

#if os(Windows)
        return AnySequence(runs).contains(where: hasSupportedAttribute)
#else
        return runs.contains(where: hasSupportedAttribute)
#endif
    }
}

extension NSAttributedString.Key {
    static let coreFont = Self(AttributeScopes.CoreAttributes.FontAttribute.name)
    static let coreForegroundColor = Self(
        AttributeScopes.CoreAttributes.ForegroundColorAttribute.name
    )
    static let coreBackgroundColor = Self(
        AttributeScopes.CoreAttributes.BackgroundColorAttribute.name
    )
    static let coreStrikethroughStyle = Self(
        AttributeScopes.CoreAttributes.StrikethroughStyleAttribute.name
    )
    static let coreUnderlineStyle = Self(
        AttributeScopes.CoreAttributes.UnderlineStyleAttribute.name
    )
    static let coreKern = Self(AttributeScopes.CoreAttributes.KerningAttribute.name)
    static let coreTracking = Self(
        AttributeScopes.CoreAttributes.TrackingAttribute.name
    )
    static let coreBaselineOffset = Self(
        AttributeScopes.CoreAttributes.BaselineOffsetAttribute.name
    )
}

/// Run values and shared resources produced by text-style and attributed conversion.
struct _ResolvedTextRunAttributes: Equatable {
    var font: Font?
    var foregroundColor: Color?
    var backgroundColor: Color?
    var strikethroughStyle: Text.LineStyle?
    var underlineStyle: Text.LineStyle?
    var kern: CGFloat?
    var tracking: CGFloat?
    var baselineOffset: CGFloat?
    var fontResource: FontResource?
    var language: String?
    var paragraphStyle: TextParagraphStyle?
    var glyphInfo: TextGlyphInfo?
    var encapsulation: TextEncapsulationResource?
    var adaptiveImageProvider: TextAdaptiveImageProvider?
    var textScale: Text.Scale?
    var superscript: Text.Superscript?
    var shadow: _ShadowEffect?
    var transitionIndex: Int?
    var customAttachment: AnyCustomTextAttachment?

    init(
        font: Font? = nil,
        foregroundColor: Color? = nil,
        backgroundColor: Color? = nil,
        strikethroughStyle: Text.LineStyle? = nil,
        underlineStyle: Text.LineStyle? = nil,
        kern: CGFloat? = nil,
        tracking: CGFloat? = nil,
        baselineOffset: CGFloat? = nil
    ) {
        self.font = font
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.strikethroughStyle = strikethroughStyle
        self.underlineStyle = underlineStyle
        self.kern = kern
        self.tracking = tracking
        self.baselineOffset = baselineOffset
    }

    var isEmpty: Bool {
        font == nil && foregroundColor == nil && backgroundColor == nil &&
            strikethroughStyle == nil && underlineStyle == nil && kern == nil &&
            tracking == nil && baselineOffset == nil && customAttachment == nil
    }

    var nsAttributes: [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [:]
        if let font { result[.coreFont] = font }
        if let foregroundColor {
            result[.coreForegroundColor] = foregroundColor
        }
        if let backgroundColor {
            result[.coreBackgroundColor] = backgroundColor
        }
        if let strikethroughStyle {
            result[.coreStrikethroughStyle] = strikethroughStyle
        }
        if let underlineStyle {
            result[.coreUnderlineStyle] = underlineStyle
        }
        if let kern { result[.coreKern] = kern }
        if let tracking { result[.coreTracking] = tracking }
        if let baselineOffset {
            result[.coreBaselineOffset] = baselineOffset
        }
        if let language { result[NSAttributedString.Key("NSLanguage")] = language }
        if let paragraphStyle { result[NSAttributedString.Key("VUI.ParagraphStyle")] = paragraphStyle }
        if let glyphInfo { result[NSAttributedString.Key("VUI.GlyphInfo")] = glyphInfo }
        if let encapsulation { result[NSAttributedString.Key("VUI.Encapsulation")] = encapsulation }
        if let adaptiveImageProvider { result[NSAttributedString.Key("VUI.AdaptiveImageProvider")] = adaptiveImageProvider }
        if let textScale { result[NSAttributedString.Key("VUI.TextScale")] = textScale }
        if let superscript { result[NSAttributedString.Key("VUI.Superscript")] = superscript }
        if let shadow { result[NSAttributedString.Key("VUI.TextShadow")] = shadow }
        if let transitionIndex { result[NSAttributedString.Key("VUI.TextTransition")] = transitionIndex }
        if let customAttachment { result[.customTextAttachment] = customAttachment }
        return result
    }

    init(nsAttributes: [NSAttributedString.Key: Any]) {
        font = nsAttributes[.coreFont] as? Font
        foregroundColor = nsAttributes[.coreForegroundColor] as? Color
        backgroundColor = nsAttributes[.coreBackgroundColor] as? Color
        strikethroughStyle =
            nsAttributes[.coreStrikethroughStyle] as? Text.LineStyle
        underlineStyle = nsAttributes[.coreUnderlineStyle] as? Text.LineStyle
        kern = nsAttributes[.coreKern] as? CGFloat
        tracking = nsAttributes[.coreTracking] as? CGFloat
        baselineOffset = nsAttributes[.coreBaselineOffset] as? CGFloat
        customAttachment = nsAttributes[.customTextAttachment] as? AnyCustomTextAttachment
    }
}

func _attributedStringFromResolvedTextStorage(
    _ value: NSAttributedString
) -> AttributedString {
#if canImport(Darwin)
    try! AttributedString(value, including: AttributeScopes.CoreAttributes.self)
#else
    var result = AttributedString()
    value.enumerateAttributes(
        in: NSRange(location: 0, length: value.length),
        options: []
    ) { attributes, range, _ in
        var segment = AttributedString(
            value.attributedSubstring(from: range).string
        )
        segment._setCoreAttributes(
            _ResolvedTextRunAttributes(nsAttributes: attributes)
        )
        result.append(segment)
    }
    return result
#endif
}

private func _resolvedAttributedRuns(
    _ value: AttributedString,
    style: Text.Style,
    properties: inout Text.ResolvedProperties,
    text: inout String,
    options: Text.ResolveOptions = .includeTransitions,
    context: any TextResolutionContext
) -> [ResolvedTextSource.Run] {
    var result: [ResolvedTextSource.Run] = []
#if os(Windows)
    let runs = AnySequence(value.runs)
#else
    let runs = value.runs
#endif
    for run in runs {
        let string = String(value.characters[run.range])
        guard !string.isEmpty else { continue }
        var attributes = _ResolvedTextRunAttributes(
            font: run.font, foregroundColor: run.foregroundColor, backgroundColor: run.backgroundColor,
            strikethroughStyle: run.strikethroughStyle, underlineStyle: run.underlineStyle,
            kern: run.kern, tracking: run.tracking, baselineOffset: run.baselineOffset).nsAttributes
        if let value = run[TextGlyphInfoAttribute.self] { attributes[.init(TextGlyphInfoAttribute.name)] = value }
        if let value = run[TextAdaptiveImageGlyphAttribute.self] { attributes[.init(TextAdaptiveImageGlyphAttribute.name)] = value }
        if let value = run[TextScaleAttribute.self] { attributes[.init(TextScaleAttribute.name)] = value }
        if let value = run[TextSuperscriptAttribute.self] { attributes[.init(TextSuperscriptAttribute.name)] = value }
        if let value = run[TextParagraphAlignmentAttribute.self] { attributes[.init(TextParagraphAlignmentAttribute.name)] = value }
        if let value = run[TextParagraphWritingDirectionAttribute.self] { attributes[.init(TextParagraphWritingDirectionAttribute.name)] = value }
        if let value = run[TextLineHeightAttribute.self] { attributes[.init(TextLineHeightAttribute.name)] = value }
        if let intent = run.inlinePresentationIntent { attributes[.init("NSInlinePresentationIntent")] = intent }
        if let language = run.languageIdentifier { attributes[.init("NSLanguage")] = language }
        var childStyle = style
        attributes.transferAttributedStringStyles(to: &childStyle)
        if let resolved = childStyle.resolveRun(string, context: context, properties: &properties, text: &text, options: options) {
            result.append(resolved)
        }
    }
    return result
}

final class AttributedStringTextStorage: AnyTextStorage {
    let str: AttributedString

    init(_ str: AttributedString) {
        self.str = str
    }

    override func resolve(
        style: Text.Style,
        properties: inout Text.ResolvedProperties,
        text: inout String,
        options: Text.ResolveOptions,
        context: any TextResolutionContext
    ) -> ResolvedTextSource? {
        ResolvedTextSource(
            runs: _resolvedAttributedRuns(
                str,
                style: style, properties: &properties, text: &text, options: options,
                context: context
            ),
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale,
            drawMissingGlyphs: true
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        String(str.characters)
    }

    override func contentHash(
        into hasher: inout Hasher,
        environment: EnvironmentValues,
        referenceDate: Date
    ) {
        hasher.combine(str)
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        guard let other = other as? AttributedStringTextStorage else { return false }
        return str == other.str
    }

    override func isStyled(options: Text.ResolveOptions) -> Bool {
        str.isStyled
    }

    override func allowsTypesettingLanguage() -> Bool {
        true
    }
}

func _resolvedAttributedText(
    _ value: AttributedString,
    style: Text.Style,
    properties: inout Text.ResolvedProperties,
    text: inout String,
    options: Text.ResolveOptions = .includeTransitions,
    context: any TextResolutionContext
) -> ResolvedTextSource {
    ResolvedTextSource(
        runs: _resolvedAttributedRuns(
            value,
            style: style, properties: &properties, text: &text, options: options,
            context: context
        ),
        scaleFactor: context.contentScaleFactor,
        displayScale: context.displayScale,
        drawMissingGlyphs: true
    )
}

extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    mutating func transferAttributedStringStyles(to style: inout Text.Style) {
        if let font = self[.coreFont] as? Font { style.baseFont = .explicit(font); removeValue(forKey: .coreFont) }
        if let color = self[.coreForegroundColor] as? Color { style.color = .explicit(AnyShapeStyle(color)); removeValue(forKey: .coreForegroundColor) }
        if let color = self[.coreBackgroundColor] as? Color { style.backgroundColor = color; removeValue(forKey: .coreBackgroundColor) }
        if let value = self[.coreKern] as? CGFloat { style.kerning = value; removeValue(forKey: .coreKern) }
        if let value = self[.coreTracking] as? CGFloat { style.tracking = value; removeValue(forKey: .coreTracking) }
        if let value = self[.coreBaselineOffset] as? CGFloat { style.baselineOffset = value; removeValue(forKey: .coreBaselineOffset) }
        if let value = self[.coreUnderlineStyle] as? Text.LineStyle { style.underline = .explicit(value); removeValue(forKey: .coreUnderlineStyle) }
        if let value = self[.coreStrikethroughStyle] as? Text.LineStyle { style.strikethrough = .explicit(value); removeValue(forKey: .coreStrikethroughStyle) }
        if let language = self[.init("NSLanguage")] as? String, case .automatic = style.typesettingConfiguration.language.storage {
            style.typesettingConfiguration.language = TypesettingLanguage(storage: .explicit(Locale.Language(identifier: language), .init(rawValue: 0)))
        }
        if let value = self[.init(TextGlyphInfoAttribute.name)] as? TextGlyphInfo {
            style.glyphInfo = value; removeValue(forKey: .init(TextGlyphInfoAttribute.name))
        }
        if let value = self[.init(TextAdaptiveImageGlyphAttribute.name)] as? TextAdaptiveImageGlyph {
            style.adaptiveImageGlyph = value; removeValue(forKey: .init(TextAdaptiveImageGlyphAttribute.name))
        }
        if let value = self[.init(TextScaleAttribute.name)] as? Text.Scale {
            style.scale = value; removeValue(forKey: .init(TextScaleAttribute.name))
        }
        if let value = self[.init(TextSuperscriptAttribute.name)] as? Text.Superscript {
            style.superscript = value; removeValue(forKey: .init(TextSuperscriptAttribute.name))
        }
        if let value = self[.init(TextParagraphAlignmentAttribute.name)] as? TextParagraphAlignment {
            style.alignment = value; removeValue(forKey: .init(TextParagraphAlignmentAttribute.name))
        }
        if let value = self[.init(TextParagraphWritingDirectionAttribute.name)] as? AttributedString.WritingDirection {
            style.writingDirection = value; removeValue(forKey: .init(TextParagraphWritingDirectionAttribute.name))
        }
        if let value = self[.init(TextLineHeightAttribute.name)] as? TextLineHeight {
            style.lineHeight = value; removeValue(forKey: .init(TextLineHeightAttribute.name))
        }
        if let intent = self[.init("NSInlinePresentationIntent")] as? InlinePresentationIntent {
            if intent.contains(.emphasized) { style.addFontModifier(.static(Font.ItalicModifier.self)) }
            if intent.contains(.stronglyEmphasized) { style.addFontModifier(.static(Font.BoldModifier.self)) }
            if intent.contains(.code) { style.addFontModifier(.static(Font.MonospacedModifier.self)) }
            if intent.contains(.strikethrough) { style.strikethrough = .explicit(.single) }
            removeValue(forKey: .init("NSInlinePresentationIntent"))
        }
    }
}

// Internal keys carry typed backend payloads without exposing platform overlay types.
enum TextGlyphInfoAttribute: AttributedStringKey {
    typealias Value = TextGlyphInfo
    static let name = "VUI.GlyphInfo"
}
enum TextAdaptiveImageGlyphAttribute: AttributedStringKey {
    typealias Value = TextAdaptiveImageGlyph
    static let name = "VUI.AdaptiveImageGlyph"
}
enum TextScaleAttribute: AttributedStringKey {
    typealias Value = Text.Scale
    static let name = "VUI.TextScale"
}
enum TextSuperscriptAttribute: AttributedStringKey {
    typealias Value = Text.Superscript
    static let name = "VUI.Superscript"
}
enum TextParagraphAlignmentAttribute: AttributedStringKey {
    typealias Value = TextParagraphAlignment
    static let name = "VUI.ParagraphAlignment"
}
enum TextParagraphWritingDirectionAttribute: AttributedStringKey {
    typealias Value = AttributedString.WritingDirection
    static let name = "VUI.ParagraphWritingDirection"
}
enum TextLineHeightAttribute: AttributedStringKey {
    typealias Value = TextLineHeight
    static let name = "VUI.LineHeight"
}
