//
//  File: TextStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
#if canImport(CoreText)
import CoreText
#endif

extension Text {
    /// Style values copied through nested text before producing font and run attributes.
    /// Paragraph state is accumulated separately in ResolvedProperties.
    struct Style {
        /// Distinguishes an explicit font, an inherited font, and a reset to the default.
        enum TextStyleFont {
            case explicit(Font), implicit, `default`
            func resolve(in environment: EnvironmentValues, includeDefaultAttributes: Bool) -> Font? {
                switch self {
                case let .explicit(font): font
                case .implicit: includeDefaultAttributes ? environment.effectiveFont : nil
                case .default: includeDefaultAttributes ? environment.defaultFont ?? .system(.body) : nil
                }
            }
        }
        /// Preserves the foreground source until the current environment resolves it.
        enum TextStyleColor {
            case explicit(AnyShapeStyle), foregroundKeyColor(base: AnyShapeStyle), implicit, `default`
            func baseStyle(in environment: EnvironmentValues) -> AnyShapeStyle {
                switch self {
                case let .explicit(base), let .foregroundKeyColor(base): base
                case .implicit: environment.foregroundStyleLevels?.primary ?? Self.primary
                case .default: environment.defaultForegroundStyle ?? Self.primary
                }
            }
            func resolve(in environment: EnvironmentValues, with options: ResolveOptions,
                         properties: inout ResolvedProperties,
                         includeDefaultAttributes: Bool) -> Color.ResolvedHDR? {
                let base: AnyShapeStyle
                switch self {
                case let .explicit(style): base = style
                case let .foregroundKeyColor(style):
                    if options.contains(.allowsKeyColors) { return Self.keyColor }
                    base = style
                case .implicit, .default:
                    guard includeDefaultAttributes else { return nil }
                    if options.contains(.foregroundKeyColor) { return Self.keyColor }
                    let inherited: AnyShapeStyle?
                    if case .implicit = self { inherited = environment.foregroundStyleLevels?.primary }
                    else { inherited = environment.defaultForegroundStyle }
                    var shape = _ShapeStyle_Shape(operation: .fallbackColor(level: 0), environment: environment)
                    inherited?._apply(to: &shape)
                    if case let .color(color) = shape.result { base = AnyShapeStyle(color) }
                    else { base = Self.primary }
                }
                if options.contains(.allowsKeyColors) {
                    var shape = _ShapeStyle_Shape(operation: .resolveStyle(name: .foreground, levels: 0..<1),
                        environment: environment)
                    base._apply(to: &shape)
                    let style: _ShapeStyle_Pack.Style
                    if case let .pack(pack) = shape.result,
                       let value = pack.styles.first(where: { $0.key == .init(.foreground, 0) })?.style {
                        style = value
                    } else {
                        style = _ShapeStyle_Pack.Style(.color(Color.clear.resolveHDR(in: environment)))
                    }
                    return properties.addCustomStyle(style)
                }
                var shape = _ShapeStyle_Shape(operation: .fallbackColor(level: 0), environment: environment)
                base._apply(to: &shape)
                if case let .color(color) = shape.result { return color.resolveHDR(in: environment) }
                ForegroundStyle()._apply(to: &shape)
                if case let .color(color) = shape.result { return color.resolveHDR(in: environment) }
                return Color.primary.resolveHDR(in: environment)
            }
            private static let keyColor = Color.ResolvedHDR(.init(colorSpace: .sRGBLinear,
                red: -1, green: -1, blue: -1, opacity: 1))
            private static let primary = AnyShapeStyle(HierarchicalShapeStyle.primary)
        }
        /// Preserves an explicit decoration, inheritance, or an explicit reset.
        enum LineStyle {
            case explicit(Text.LineStyle), implicit, `default`
            func resolve(fallback: @autoclosure () -> Text.LineStyle?) -> Text.LineStyle? {
                switch self {
                case let .explicit(value): value
                case .implicit: fallback()
                case .default: nil
                }
            }
        }

        var baseFont: TextStyleFont = .implicit
        var fontModifiers: [AnyFontModifier] = []
        var color: TextStyleColor = .implicit
        var backgroundColor: Color?
        var baselineOffset: CGFloat?
        var kerning: CGFloat?
        var tracking: CGFloat?
        var strikethrough: LineStyle = .implicit
        var underline: LineStyle = .implicit
        var encapsulation: Text.Encapsulation?
        var speech: AccessibilitySpeechAttributes?
        var accessibility: AccessibilityTextAttributes?
        var glyphInfo: TextGlyphInfo?
        var shadow: TextShadowModifier?
        var transition: TextTransitionModifier?
        var scale: Text.Scale?
        var superscript: Text.Superscript?
        var typesettingConfiguration = TypesettingConfiguration()
        var customAttributes: [TextAttributeModifierBase] = []
        var adaptiveImageGlyph: TextAdaptiveImageGlyph?
        var alignment: TextParagraphAlignment?
        var writingDirection: AttributedString.WritingDirection?
        var lineHeight: AttributedString.LineHeight?
        var clearedFontModifiers: Set<ObjectIdentifier> = []

        mutating func addFontModifier(_ modifier: AnyFontModifier) { fontModifiers.append(modifier) }
        mutating func removeFontModifier<M>(_ type: M.Type) {
            let identifier = ObjectIdentifier(type)
            fontModifiers.removeAll { $0.modifierType == identifier }
            clearedFontModifiers.insert(identifier)
        }

        func fontKey(in environment: EnvironmentValues, includeDefaultAttributes: Bool = true) -> Font.FontCache.Key? {
            guard let font = baseFont.resolve(in: environment, includeDefaultAttributes: includeDefaultAttributes) else { return nil }
            var context = environment.fontResolutionContext
            var modifiers = context.fontModifiers.filter { !clearedFontModifiers.contains($0.modifierType) }
            modifiers += fontModifiers
            if case let .explicit(identifier, flags) = typesettingConfiguration.language.resolve(), flags.rawValue & 1 != 0 {
                modifiers.append(.dynamic(LanguageFontModifier(identifier: identifier)))
            }
            if let ratio = typesettingConfiguration.languageAwareLineHeightRatio.ratio {
                modifiers.append(.dynamic(LanguageAwareLineHeightRatioFontModifier(ratio: ratio)))
            }
            context.fontModifiers = []
            return Font.FontCache.Key(font: font, modifiers: modifiers, context: context)
        }

        func fontTraits(in environment: EnvironmentValues) -> Font.ResolvedTraits {
            let font = baseFont.resolve(in: environment, includeDefaultAttributes: true)!
            let context = environment.fontResolutionContext
            if context.fontModifiers.isEmpty && fontModifiers.isEmpty {
                return font.resolveTraits(in: context)
            }
            var descriptor = font.resolveDescriptor(in: context)
            for modifier in context.fontModifiers + fontModifiers {
                modifier.modify(descriptor: &descriptor, in: context)
            }
            return Font.ResolvedTraits(descriptor)
        }

        func nsAttributes(in environment: EnvironmentValues,
                          properties: inout ResolvedProperties,
                          options: ResolveOptions = [],
                          includeDefaultAttributes: Bool = true) -> _ResolvedTextRunAttributes {
            var attributes = _ResolvedTextRunAttributes()
            if let key = fontKey(in: environment, includeDefaultAttributes: includeDefaultAttributes) {
                let resource = Font.FontCache.shared[key]
                properties.fonts.storage.insert(resource)
                attributes.font = Font(provider: FontBox(Font.PlatformFontProvider(font: resource)))
                attributes.fontResource = resource
            }
            let language = typesettingConfiguration.language.resolve()
            properties.paragraph.compositionLanguage = 0
            if case let .explicit(identifier, _) = language {
                attributes.language = identifier
                properties.paragraph.languageIdentifiers.insert(identifier)
                properties.paragraph.compositionLanguage = textCompositionLanguage(identifier)
            }
            attributes.paragraphStyle = properties.style(environment: environment,
                alignment: alignment, writingDirection: writingDirection, lineHeight: lineHeight)
            if let resolved = color.resolve(in: environment, with: options, properties: &properties,
                                            includeDefaultAttributes: includeDefaultAttributes) {
                attributes.foregroundColor = Color(resolved)
                properties.addColor(resolved)
            }
            attributes.backgroundColor = backgroundColor
            attributes.baselineOffset = baselineOffset
            attributes.kern = kerning
            attributes.tracking = tracking
            attributes.underlineStyle = underline.resolve(fallback: nil)
            attributes.strikethroughStyle = strikethrough.resolve(fallback: nil)
            attributes.glyphInfo = glyphInfo
            attributes.encapsulation = encapsulation?.resolve(in: environment)
            attributes.adaptiveImageProvider = adaptiveImageGlyph.map(TextAdaptiveImageProvider.init)
            attributes.textScale = (scale ?? environment.textScale) == .secondary ? .secondary : nil
            attributes.superscript = superscript
            if let shadow {
                attributes.shadow = shadow.shadow
                let radius = 2.8 * shadow.shadow.radius
                let x = shadow.shadow.offset.width
                let y = shadow.shadow.offset.height
                properties.insets.top = min(properties.insets.top, -radius + y)
                properties.insets.leading = min(properties.insets.leading, -radius + x)
                properties.insets.bottom = min(properties.insets.bottom, -radius - y)
                properties.insets.trailing = min(properties.insets.trailing, -radius - x)
            } else if let transition, options.contains(.includeTransitions) {
                attributes.transitionIndex = properties.transitions.count
                properties.transitions.append(transition.resolved)
            }
            return attributes
        }

        func resolveRun(_ string: String, context: any TextResolutionContext,
                        properties: inout ResolvedProperties, text: inout String, options: ResolveOptions = .includeTransitions) -> ResolvedTextSource.Run? {
            let string = string.caseConvertedIfNeeded(context.environment)
            let attributes = nsAttributes(in: context.environment, properties: &properties,
                options: options, includeDefaultAttributes: context.includeDefaultAttributes)
            guard !string.isEmpty else { return nil }
            let faces = typefaces(attributes: attributes, context: context)
            guard !faces.isEmpty else { return nil }
            var custom = _TextAttributeValues()
            for modifier in customAttributes { modifier.apply(to: &custom) }
            text += string
            if let last = string.unicodeScalars.last, [10, 13, 0x2029].contains(last.value) {
                properties.markParagraphBoundary(at: text.utf16.count, in: text, environment: context.environment)
            }
            return .styledText(faces, string, custom, attributes)
        }

        func typefaces(attributes: _ResolvedTextRunAttributes, context: any TextResolutionContext) -> [Typeface] {
            let font: Font
            if let attributeFont = attributes.font {
                font = attributeFont
            } else if let key = fontKey(in: context.environment) {
                // Glyph resources are still needed when exported text omits its
                // inherited font. Keep that resource out of the run attributes.
                font = Font(provider: FontBox(Font.PlatformFontProvider(font: Font.FontCache.shared[key])))
            } else {
                return []
            }
            // The shared resource already consumed inherited modifiers. Keep the
            // original environment and its dependency tracker while creating glyph resources.
            return font.typefaceCascade(in: context.environment, forContext: context.sceneResources,
                contentScaleFactor: context.contentScaleFactor, applyEnvironmentModifiers: false).runFaces
        }
    }
}

extension String {
    func caseConvertedIfNeeded(_ environment: EnvironmentValues) -> String {
        guard let textCase = environment.textCase else { return self }
        let locale = environment.locale
        switch textCase {
        case .uppercase:
            return uppercased(with: locale)
        case .lowercase:
            return lowercased(with: locale)
        }
    }
}

extension Text.Modifier {
    func modify(style: inout Text.Style, environment: EnvironmentValues) {
        switch self {
        case let .font(font): style.baseFont = font.map(Text.Style.TextStyleFont.explicit) ?? .default
        case let .color(color): style.color = color.map { .explicit(AnyShapeStyle($0)) } ?? .default
        case .italic: style.addFontModifier(.static(Font.ItalicModifier.self))
        case let .weight(weight):
            if let weight { style.addFontModifier(.dynamic(Font.WeightModifier(weight: weight))) }
            else { style.removeFontModifier(Font.WeightModifier.self) }
        case let .kerning(value): style.kerning = value
        case let .tracking(value): style.tracking = value
        case let .baseline(value): style.baselineOffset = value
        case let .anyTextModifier(modifier): modifier.modify(style: &style, environment: environment)
        case .rounded: preconditionFailure("Rounded text styling requires a resolved modifier contract.")
        }
    }
}

extension Text.Style {
    func resolve(_ string: String, context: any TextResolutionContext,
                 properties: inout Text.ResolvedProperties, text: inout String, options: Text.ResolveOptions = .includeTransitions) -> ResolvedTextSource {
        let run = resolveRun(string, context: context, properties: &properties, text: &text, options: options)
        return ResolvedTextSource(runs: run.map { [$0] } ?? [],
            scaleFactor: context.contentScaleFactor, displayScale: context.displayScale, drawMissingGlyphs: true)
    }
}
