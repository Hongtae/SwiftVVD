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
        if let font { result[NSAttributedString.Key("VUI.Font")] = font }
        if let foregroundColor {
            result[NSAttributedString.Key("VUI.ForegroundColor")] = foregroundColor
        }
        if let backgroundColor {
            result[NSAttributedString.Key("VUI.BackgroundColor")] = backgroundColor
        }
        if let strikethroughStyle {
            result[NSAttributedString.Key("VUI.StrikethroughStyle")] = strikethroughStyle
        }
        if let underlineStyle {
            result[NSAttributedString.Key("VUI.UnderlineStyle")] = underlineStyle
        }
        if let kern { result[NSAttributedString.Key("VUI.Kern")] = kern }
        if let tracking { result[NSAttributedString.Key("VUI.Tracking")] = tracking }
        if let baselineOffset {
            result[NSAttributedString.Key("VUI.BaselineOffset")] = baselineOffset
        }
        return result
    }
}

private func _resolvedAttributedRuns(
    _ value: AttributedString,
    defaultTypefaces: [Typeface],
    context: GraphicsContext
) -> [GraphicsContext.ResolvedText.Run] {
    #if os(Windows)
    // The Windows Foundation dynamic library does not currently expose the
    // metadata implementation required by attributed-run enumeration. Keep
    // arbitrary attributed values renderable as text; localized placeholders
    // are decomposed before they reach this generic storage boundary.
    let text = String(value.characters)
    guard !text.isEmpty, !defaultTypefaces.isEmpty else { return [] }
    return [.text(defaultTypefaces, text)]
    #else
    value.runs.compactMap { run -> GraphicsContext.ResolvedText.Run? in
        let text = String(value.characters[run.range])
        guard !text.isEmpty else { return nil }

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
            font = font
                .resolved(in: context.environment)
                .displayScale(context.sceneResources.contentScaleFactor)
            attributes.font = font
            typefaces = ([font.typeface(forContext: context.sceneResources)] +
                font.fallbackTypefaces).compactMap { $0 }
        } else {
            typefaces = defaultTypefaces
        }
        guard !typefaces.isEmpty else { return nil }
        if attributes.isEmpty {
            return .text(typefaces, text)
        }
        return .styledText(typefaces, text, _TextAttributeValues(), attributes)
    }
    #endif
}

final class AttributedStringTextStorage: AnyTextStorage {
    let str: AttributedString

    init(_ str: AttributedString) {
        self.str = str
    }

    override func resolve(
        typefaces: [Typeface],
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText {
        GraphicsContext.ResolvedText(
            runs: _resolvedAttributedRuns(
                str,
                defaultTypefaces: typefaces,
                context: context
            ),
            scaleFactor: context.contentScaleFactor
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
}

func _resolvedAttributedText(
    _ value: AttributedString,
    defaultTypefaces: [Typeface],
    context: GraphicsContext
) -> GraphicsContext.ResolvedText {
    GraphicsContext.ResolvedText(
        runs: _resolvedAttributedRuns(
            value,
            defaultTypefaces: defaultTypefaces,
            context: context
        ),
        scaleFactor: context.contentScaleFactor
    )
}
