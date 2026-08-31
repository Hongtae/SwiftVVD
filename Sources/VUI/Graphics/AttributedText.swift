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

private extension NSAttributedString.Key {
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

struct _ResolvedTextRunAttributes: Equatable {
    var font: Font?
    var foregroundColor: Color?
    var backgroundColor: Color?
    var strikethroughStyle: Text.LineStyle?
    var underlineStyle: Text.LineStyle?
    var kern: CGFloat?
    var tracking: CGFloat?
    var baselineOffset: CGFloat?

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
            tracking == nil && baselineOffset == nil
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
    defaultTypefaces: [Typeface],
    context: any TextResolutionContext
) -> [GraphicsContext.ResolvedText.Run] {
    var result: [GraphicsContext.ResolvedText.Run] = []
    let resolveRun: (AttributedString.Runs.Run) -> Void = { run in
        let text = String(value.characters[run.range])
        guard !text.isEmpty else { return }

        var attributes = _ResolvedTextRunAttributes(
            font: run.font,
            foregroundColor: run.foregroundColor,
            backgroundColor: run.backgroundColor,
            strikethroughStyle: run.strikethroughStyle,
            underlineStyle: run.underlineStyle,
            kern: run.kern,
            tracking: run.tracking,
            baselineOffset: run.baselineOffset
        )
        let typefaces: [Typeface]
        let presentationIntent = run.inlinePresentationIntent
        if attributes.font != nil || presentationIntent != nil {
            var font = attributes.font ?? context.environment.font ?? .system(.body)
            if presentationIntent?.contains(.stronglyEmphasized) == true {
                font = font.bold()
            }
            if presentationIntent?.contains(.emphasized) == true {
                font = font.italic()
            }
            font = font.resolved(in: context.environment)
            attributes.font = font
            typefaces = font.typefaceCascade(
                in: context.environment,
                forContext: context.sceneResources,
                contentScaleFactor: context.contentScaleFactor
            ).runFaces
        } else {
            typefaces = defaultTypefaces
        }
        guard !typefaces.isEmpty else { return }
        if attributes.isEmpty {
            result.append(.text(typefaces, text))
        } else {
            result.append(
                .styledText(typefaces, text, _TextAttributeValues(), attributes)
            )
        }
    }

#if os(Windows)
    // Type erasure keeps the debug client from materializing an implementation
    // index type that the Windows Foundation dynamic library does not export.
    AnySequence(value.runs).forEach(resolveRun)
#else
    value.runs.forEach(resolveRun)
#endif
    return result
}

final class AttributedStringTextStorage: AnyTextStorage {
    let str: AttributedString

    init(_ str: AttributedString) {
        self.str = str
    }

    override func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        GraphicsContext.ResolvedText(
            runs: _resolvedAttributedRuns(
                str,
                defaultTypefaces: typefaces,
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
}

func _resolvedAttributedText(
    _ value: AttributedString,
    defaultTypefaces: [Typeface],
    context: any TextResolutionContext
) -> GraphicsContext.ResolvedText {
    GraphicsContext.ResolvedText(
        runs: _resolvedAttributedRuns(
            value,
            defaultTypefaces: defaultTypefaces,
            context: context
        ),
        scaleFactor: context.contentScaleFactor,
        displayScale: context.displayScale,
        drawMissingGlyphs: true
    )
}
