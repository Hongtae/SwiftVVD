//
//  File: TextStylePayloads.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Groups language and line-height ratio requests passed into text resolution.
struct TypesettingConfiguration: Hashable {
    var language: TypesettingLanguage = .automatic
    var languageAwareLineHeightRatio: TypesettingLanguageAwareLineHeightRatio = .automatic

    func hash(into hasher: inout Hasher) {
        hasher.combine(language.storage)
        hasher.combine(languageAwareLineHeightRatio)
    }
}

/// Specifies the language source while retaining its font-resolution flags.
public struct TypesettingLanguage: Equatable, Sendable {
    struct Flags: OptionSet, Hashable {
        var rawValue: UInt8
    }
    enum Storage: Hashable {
        case explicit(Locale.Language, Flags)
        case automatic
        case contentAware
    }
    enum Resolved: Hashable {
        case explicit(String, Flags)
        case detected(String)
        case automatic
    }
    var storage: Storage
    public static let automatic = Self(storage: .automatic)
    static let contentAware = Self(storage: .contentAware)
    public static func explicit(_ language: Locale.Language) -> Self {
        Self(storage: .explicit(language, Flags(rawValue: 1)))
    }
    func resolve() -> Resolved {
        switch storage {
        case let .explicit(language, flags): .explicit(language.maximalIdentifier, flags)
        case .automatic: .automatic
        case .contentAware:
            preconditionFailure("Content-aware typesetting requires a language detection service.")
        }
    }
}

/// Retains a typesetting ratio request independently of measured line metrics.
struct TypesettingLanguageAwareLineHeightRatio: Hashable {
    enum Storage: Hashable { case custom(Double), automatic, disable, legacy }
    var storage: Storage
    static let automatic = Self(storage: .automatic)
    static let disable = Self(storage: .disable)
    static let legacy = Self(storage: .legacy)
    static func custom(_ value: Double) -> Self {
        Self(storage: .custom(min(max(value, 0), 1)))
    }
    var ratio: Double? {
        switch storage {
        case let .custom(value): value
        case .automatic: nil
        case .disable: 0
        case .legacy: 0.33
        }
    }
}

enum AccessibilityAnnouncementPriority: Hashable { case low, `default`, high }
enum AccessibilityHeadingLevel: Hashable { case unspecified, h1, h2, h3, h4, h5, h6 }
/// Describes the semantic category of text for accessibility services.
struct AccessibilityTextContentType: Hashable {
    enum RawValue: Hashable {
        case plain, console, fileSystem, messaging, narrative, sourceCode, spreadsheet, wordProcessing
    }
    var rawValue: RawValue
}
/// Optional speech settings merged into the current text style.
struct AccessibilitySpeechAttributes: Equatable {
    var alwaysIncludesPunctuation: Bool?
    var spellsOutCharacters: Bool?
    var adjustedPitch: Double?
    var announcementsPriority: AccessibilityAnnouncementPriority?
    var phoneticRepresentation: String?

    mutating func merge(_ value: Self) {
        if let v = value.alwaysIncludesPunctuation { alwaysIncludesPunctuation = v }
        if let v = value.spellsOutCharacters { spellsOutCharacters = v }
        if let v = value.adjustedPitch { adjustedPitch = v }
        if let v = value.announcementsPriority { announcementsPriority = v }
        if let v = value.phoneticRepresentation { phoneticRepresentation = v }
    }
}
/// Semantic accessibility metadata retained by the text style.
struct AccessibilityTextAttributes: Equatable {
    var contentType: AccessibilityTextContentType?
    var headingLevel: AccessibilityHeadingLevel?
    var durationTimeMMSS: Bool?
    var label: Text?

    mutating func merge(_ value: Self) {
        if let v = value.contentType { contentType = v }
        if let v = value.headingLevel { headingLevel = v }
        if let v = value.durationTimeMMSS { durationTimeMMSS = v }
        if let v = value.label { label = v }
    }
}

extension Text {
    /// A relative text-size request retained separately from the base font.
    public struct Scale: Hashable, Sendable {
        enum Storage: Hashable { case `default`, secondary }
        var storage: Storage
        public static let `default` = Self(storage: .default)
        public static let secondary = Self(storage: .secondary)
    }
    /// Marks a superscript request carried by resolved run attributes.
    struct Superscript: Hashable {}
    /// Unresolved appearance values for an inline text enclosure.
    struct Encapsulation: Equatable {
        struct Scale: Equatable { let rawValue: Int }
        struct Shape: Equatable { let rawValue: Int }
        struct Style: Equatable { let rawValue: Int }
        struct PlatterSize: Equatable { let rawValue: Int }
        var scale: Scale?
        var shape: Shape?
        var style: Style?
        var lineWeight: CGFloat?
        var color: Color?
        var minimumWidth: CGFloat?
        var platterSize: PlatterSize?

        func resolve(in environment: EnvironmentValues) -> TextEncapsulationResource {
            TextEncapsulationResource(
                scale: scale?.rawValue ?? 0, shape: shape?.rawValue ?? 0,
                style: style?.rawValue ?? 0, lineWeight: lineWeight ?? 0,
                color: color?.resolve(in: environment), minimumWidth: minimumWidth ?? 0,
                platterSize: platterSize?.rawValue ?? 0)
        }
    }
}

// These resource owners are internal attribute transport for the rendering backend.
// They preserve identity independently of a Text.Style value's lifetime.
/// Binds a glyph identifier and source text to a retained font resource.
final class TextGlyphInfo: NSObject {
    let font: FontResource
    let glyphIndex: UInt32
    let baseString: String
    init(font: FontResource, glyphIndex: UInt32, baseString: String) {
        self.font = font
        self.glyphIndex = glyphIndex
        self.baseString = baseString
    }
}

/// Encoded image content and descriptive metadata retained as a text glyph.
struct TextAdaptiveImageGlyph: Hashable {
    let imageContent: Data
    let contentIdentifier: String
    let contentDescription: String
}
/// Retains an adaptive image glyph through attributed text conversion.
final class TextAdaptiveImageProvider: NSObject {
    let glyph: TextAdaptiveImageGlyph
    init(_ glyph: TextAdaptiveImageGlyph) { self.glyph = glyph }
}
/// Resolved enclosure values retained independently of the originating text style.
final class TextEncapsulationResource: NSObject {
    let scale: Int
    let shape: Int
    let style: Int
    let lineWeight: CGFloat
    let color: Color.Resolved?
    let minimumWidth: CGFloat
    let platterSize: Int
    init(scale: Int, shape: Int, style: Int, lineWeight: CGFloat,
         color: Color.Resolved?, minimumWidth: CGFloat, platterSize: Int) {
        self.scale = scale
        self.shape = shape
        self.style = style
        self.lineWeight = lineWeight
        self.color = color
        self.minimumWidth = minimumWidth
        self.platterSize = platterSize
    }
}

/// Physical paragraph alignment, independent of leading/trailing resolution.
enum TextParagraphAlignment: Hashable, Codable { case left, right, center }
/// A line-height request retained separately from measured glyph metrics.
enum TextLineHeight: Hashable, Codable {
    case variable
    case multiple(factor: Double)
    case leading(increase: Double)
    case exact(points: Double)
    static let normal = Self.multiple(factor: 1.2)
    static let tight = Self.multiple(factor: 1)
    static let loose = Self.multiple(factor: 1.5)
}

/// Writes a language request into Text.Style before font resolution.
final class LanguageTextModifier: AnyTextModifier {
    let language: TypesettingLanguage
    init(_ language: TypesettingLanguage) { self.language = language }
    override func modify(style: inout Text.Style, environment: EnvironmentValues) {
        style.typesettingConfiguration.language = language
        style.typesettingConfiguration.languageAwareLineHeightRatio = .automatic
    }
    override func isEqual(to other: AnyTextModifier) -> Bool { (other as? Self)?.language == language }
}
/// Sets the typesetting ratio request used to construct the font cache key.
final class LanguageAwareLineHeightRatioTextModifier: AnyTextModifier {
    let value: TypesettingLanguageAwareLineHeightRatio
    init(_ value: TypesettingLanguageAwareLineHeightRatio) { self.value = value }
    override func modify(style: inout Text.Style, environment: EnvironmentValues) { style.typesettingConfiguration.languageAwareLineHeightRatio = value }
    override func isEqual(to other: AnyTextModifier) -> Bool { (other as? Self)?.value == value }
}
/// Applies a text-scale request only while the modifier is enabled.
final class TextScaleModifier: AnyTextModifier {
    var isEnabled: Bool
    var scale: Text.Scale
    init(_ scale: Text.Scale, isEnabled: Bool) { self.scale = scale; self.isEnabled = isEnabled }
    override func modify(style: inout Text.Style, environment: EnvironmentValues) { if isEnabled { style.scale = scale } }
    override func isEqual(to other: AnyTextModifier) -> Bool {
        guard let other = other as? Self else { return false }
        return scale == other.scale && isEnabled == other.isEnabled
    }
}

extension Text {
    public func typesettingLanguage(
        _ language: Locale.Language,
        isEnabled: Bool = true
    ) -> Text {
        typesettingLanguage(.explicit(language), isEnabled: isEnabled)
    }

    public func typesettingLanguage(
        _ language: TypesettingLanguage,
        isEnabled: Bool = true
    ) -> Text {
        guard isEnabled else { return self }
        return modified(with: .anyTextModifier(LanguageTextModifier(language)))
    }

    public func textScale(_ scale: Scale, isEnabled: Bool = true) -> Text {
        modified(with: .anyTextModifier(TextScaleModifier(scale, isEnabled: isEnabled)))
    }
}

extension View {
    nonisolated public func typesettingLanguage(
        _ language: Locale.Language,
        isEnabled: Bool = true
    ) -> some View {
        typesettingLanguage(.explicit(language), isEnabled: isEnabled)
    }

    nonisolated public func typesettingLanguage(
        _ language: TypesettingLanguage,
        isEnabled: Bool = true
    ) -> some View {
        transformEnvironment(\.typesettingConfiguration) { configuration in
            guard isEnabled else { return }
            configuration.language = language
            configuration.languageAwareLineHeightRatio = .automatic
        }
    }

    nonisolated public func textScale(
        _ scale: Text.Scale,
        isEnabled: Bool = true
    ) -> some View {
        transformEnvironment(\.textScale) { value in
            guard isEnabled else { return }
            value = scale
        }
    }
}
/// Merges specified speech settings while retaining other inherited values.
final class SpeechModifier: AnyTextModifier {
    let value: AccessibilitySpeechAttributes
    init(_ value: AccessibilitySpeechAttributes) { self.value = value }
    override func modify(style: inout Text.Style, environment: EnvironmentValues) {
        var speech = style.speech ?? AccessibilitySpeechAttributes()
        speech.merge(value)
        style.speech = speech
    }
    override func isEqual(to other: AnyTextModifier) -> Bool { (other as? Self)?.value == value }
}
/// Merges specified accessibility metadata into the inherited style.
final class AccessibilityTextModifier: AnyTextModifier {
    let value: AccessibilityTextAttributes
    init(_ value: AccessibilityTextAttributes) { self.value = value }
    override func modify(style: inout Text.Style, environment: EnvironmentValues) {
        var accessibility = style.accessibility ?? AccessibilityTextAttributes()
        accessibility.merge(value)
        style.accessibility = accessibility
    }
    override func isEqual(to other: AnyTextModifier) -> Bool { (other as? Self)?.value == value }
}
/// Retains a shadow effect for run attributes and layout inset calculation.
final class TextShadowModifier: AnyTextModifier {
    let shadow: _ShadowEffect
    init(_ shadow: _ShadowEffect) { self.shadow = shadow }
    override func modify(style: inout Text.Style, environment: EnvironmentValues) { style.shadow = self }
    override func isEqual(to other: AnyTextModifier) -> Bool { (other as? Self)?.shadow == shadow }
}
/// Retains the transition value later indexed by resolved text properties.
final class TextTransitionModifier: AnyTextModifier {
    let resolved: Text.ResolvedProperties.Transition
    init(_ resolved: Text.ResolvedProperties.Transition) { self.resolved = resolved }
    override func modify(style: inout Text.Style, environment: EnvironmentValues) { style.transition = self }
    override func isEqual(to other: AnyTextModifier) -> Bool { (other as? Self)?.resolved == resolved }
}

private enum TypesettingConfigurationKey: EnvironmentKey {
    static var defaultValue: TypesettingConfiguration { .init() }
}
private enum TextScaleKey: EnvironmentKey { static var defaultValue: Text.Scale? { nil } }
extension EnvironmentValues {
    var typesettingConfiguration: TypesettingConfiguration {
        get { self[TypesettingConfigurationKey.self] }
        set { self[TypesettingConfigurationKey.self] = newValue }
    }
    var textScale: Text.Scale? {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}
