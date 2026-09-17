//
//  File: ParagraphStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Carries the paragraph's automatic or balanced typesetting request.
struct ParagraphTypesetting: Equatable {
    enum Storage: Hashable { case automatic, balanced }
    var storage: Storage
    static let automatic = Self(storage: .automatic)
    static let balanced = Self(storage: .balanced)
}

extension Text {
    /// Selects whether logical alignment follows layout or writing direction.
    /// An unset strategy defers to the paragraph producer's fallback.
    struct AlignmentStrategy: Hashable {
        enum Storage: Hashable, Codable { case layoutBased, writingDirectionBased }
        var storage: Storage?
        static let `default` = Self(storage: nil)
        static let layoutBased = Self(storage: .layoutBased)
        static let writingDirectionBased = Self(storage: .writingDirectionBased)
        enum EnvironmentKey: VUI.EnvironmentKey {
            static var defaultValue: AlignmentStrategy { .default }
        }
    }
    /// Requests layout-derived or content-derived paragraph direction.
    /// An unset strategy defers to the paragraph producer's fallback.
    struct WritingDirectionStrategy: Hashable {
        enum Storage: Hashable, Codable { case layoutBased, contentBased }
        var storage: Storage?
        static let `default` = Self(storage: nil)
        static let layoutBased = Self(storage: .layoutBased)
        static let contentBased = Self(storage: .contentBased)
    }
}
private enum ParagraphTypesettingKey: EnvironmentKey { static var defaultValue: ParagraphTypesetting { .automatic } }
private enum AvoidsOrphansKey: EnvironmentKey { static var defaultValue: Bool { true } }
private enum TextWritingDirectionKey: EnvironmentKey { static var defaultValue: Text.WritingDirectionStrategy { .default } }
private enum AllowsTighteningKey: EnvironmentKey { static var defaultValue: Bool { false } }
private enum TextLineHeightKey: EnvironmentKey { static var defaultValue: TextLineHeight? { nil } }
extension EnvironmentValues {
    var allowsTightening: Bool {
        get { self[AllowsTighteningKey.self] }
        set { self[AllowsTighteningKey.self] = newValue }
    }
    var paragraphTypesetting: ParagraphTypesetting {
        get { self[ParagraphTypesettingKey.self] }
        set { self[ParagraphTypesettingKey.self] = newValue }
    }
    var avoidsOrphans: Bool {
        get { self[AvoidsOrphansKey.self] }
        set { self[AvoidsOrphansKey.self] = newValue }
    }
    var textWritingDirection: Text.WritingDirectionStrategy {
        get { self[TextWritingDirectionKey.self] }
        set { self[TextWritingDirectionKey.self] = newValue }
    }
    var textAlignmentStrategy: Text.AlignmentStrategy {
        get { self[Text.AlignmentStrategy.EnvironmentKey.self] }
        set { self[Text.AlignmentStrategy.EnvironmentKey.self] = newValue }
    }
    var lineHeight: TextLineHeight? {
        get { self[TextLineHeightKey.self] }
        set { self[TextLineHeightKey.self] = newValue }
    }
}

/// Snapshots the environment inputs used to construct a paragraph style.
struct ParagraphStyleResolutionContext {
    var textJustification: TextJustification
    var paragraphTypesetting: ParagraphTypesetting
    var avoidsOrphans: Bool
    var bodyHeadOutdent: CGFloat
    var writingMode: Text.WritingMode
    var textWritingDirection: Text.WritingDirectionStrategy
    var layoutDirection: LayoutDirection
    var allowsTightening: Bool
    var lineHeight: TextLineHeight?
    var truncationMode: Text.TruncationMode
    var lineSpacing: CGFloat
    var lineHeightMultiple: CGFloat
    var maximumLineHeight: CGFloat
    var minimumLineHeight: CGFloat
    var hyphenationFactor: CGFloat
    var hyphenationDisabled: Bool
    var multilineTextAlignment: TextAlignment
    var textAlignmentStrategy: Text.AlignmentStrategy

    init(_ environment: EnvironmentValues) {
        textJustification = environment.textJustification
        paragraphTypesetting = environment.paragraphTypesetting
        avoidsOrphans = environment.avoidsOrphans
        bodyHeadOutdent = environment.bodyHeadOutdent
        writingMode = environment.writingMode
        textWritingDirection = environment.textWritingDirection
        layoutDirection = environment.layoutDirection
        allowsTightening = environment.allowsTightening
        lineHeight = environment.lineHeight
        truncationMode = environment.truncationMode
        lineSpacing = environment.lineSpacing
        lineHeightMultiple = environment.lineHeightMultiple
        maximumLineHeight = environment.maximumLineHeight
        minimumLineHeight = environment.minimumLineHeight
        hyphenationFactor = environment.hyphenationFactor
        hyphenationDisabled = environment.hyphenationDisabled
        multilineTextAlignment = environment.multilineTextAlignment
        textAlignmentStrategy = environment.textAlignmentStrategy
    }
}

/// Mutable paragraph attributes shared by all runs in a paragraph.
/// Finalization updates this same instance before clearing the paragraph cache.
final class TextParagraphStyle: Codable, Equatable {
    /// Keeps logical leading/trailing separate from physical left/right alignment.
    enum HorizontalAlignment: Int, Codable {
        case leading, trailing, left, right, center
        func textAlignment(for layoutDirection: LayoutDirection) -> TextAlignment {
            switch self {
            case .leading: .leading
            case .trailing: .trailing
            case .left: layoutDirection == .leftToRight ? .leading : .trailing
            case .right: layoutDirection == .leftToRight ? .trailing : .leading
            case .center: .center
            }
        }
    }
    enum WritingDirection: Int, Codable { case natural = -1, leftToRight = 0, rightToLeft = 1 }
    var horizontalAlignment: HorizontalAlignment = .left
    var baseWritingDirection: WritingDirection = .natural
    var fullyJustified = false
    var spansAllLines = false
    var lineBreakMode = 4
    var secondaryLineBreakMode = 0
    var lineBreakStrategy: UInt16 = .max
    var lineSpacing: CGFloat = 0
    var lineHeightMultiple: CGFloat = 0
    var maximumLineHeight: CGFloat = 0
    var minimumLineHeight: CGFloat = 0
    var hyphenationFactor: Float = 0
    var firstLineHeadIndent: CGFloat = 0
    var allowsTightening = false
    var baselineInterval: TextLineHeight = .variable
    var compositionLanguage: Int = 0

    static func == (lhs: TextParagraphStyle, rhs: TextParagraphStyle) -> Bool { lhs === rhs }
}

func makeParagraphStyle(
    context: ParagraphStyleResolutionContext,
    alignment: TextParagraphAlignment?,
    fallbackAlignment: Text.AlignmentStrategy.Storage,
    writingDirection: AttributedString.WritingDirection?,
    fallbackWritingDirection: Text.WritingDirectionStrategy.Storage,
    lineHeight: TextLineHeight?
) -> TextParagraphStyle {
    let result = TextParagraphStyle()
    let vertical = context.writingMode == .verticalRightToLeft
    let layoutRTL = !vertical && context.layoutDirection == .rightToLeft
    if let alignment {
        switch alignment {
        case .left: result.horizontalAlignment = .left
        case .right: result.horizontalAlignment = .right
        case .center: result.horizontalAlignment = .center
        }
    } else if (context.textAlignmentStrategy.storage ?? fallbackAlignment) == .writingDirectionBased {
        switch context.multilineTextAlignment {
        case .leading: result.horizontalAlignment = .leading
        case .trailing: result.horizontalAlignment = .trailing
        case .center: result.horizontalAlignment = .center
        }
    } else {
        switch context.multilineTextAlignment {
        case .leading: result.horizontalAlignment = layoutRTL ? .right : .left
        case .trailing: result.horizontalAlignment = layoutRTL ? .left : .right
        case .center: result.horizontalAlignment = .center
        }
    }
    if context.bodyHeadOutdent > 0 {
        result.baseWritingDirection = layoutRTL ? .rightToLeft : .leftToRight
    } else if let writingDirection {
        result.baseWritingDirection = writingDirection == .rightToLeft ? .rightToLeft : .leftToRight
    } else if (context.textWritingDirection.storage ?? fallbackWritingDirection) == .layoutBased {
        result.baseWritingDirection = layoutRTL ? .rightToLeft : .leftToRight
    }
    var allLines = false
    if case let .full(full) = context.textJustification.storage {
        result.fullyJustified = true
        allLines = full.allLines
    }
    result.spansAllLines = allLines || context.paragraphTypesetting == .balanced
    switch context.truncationMode {
    case .head: result.lineBreakMode = 3
    case .tail: result.lineBreakMode = 4
    case .middle: result.lineBreakMode = 5
    }
    if !context.avoidsOrphans { result.lineBreakStrategy &= ~1 }
    result.lineSpacing = context.lineSpacing
    result.lineHeightMultiple = context.lineHeightMultiple
    result.maximumLineHeight = context.maximumLineHeight
    result.minimumLineHeight = context.minimumLineHeight
    result.allowsTightening = context.allowsTightening
    result.hyphenationFactor = context.hyphenationDisabled ? 0 : Float(context.hyphenationFactor)
    result.secondaryLineBreakMode = context.hyphenationDisabled ? 2 : 0
    result.firstLineHeadIndent = context.bodyHeadOutdent
    result.baselineInterval = lineHeight ?? context.lineHeight ?? .variable
    return result
}

extension Text.ResolvedProperties {
    mutating func style(environment: EnvironmentValues, alignment: TextParagraphAlignment?,
                        writingDirection: AttributedString.WritingDirection?, lineHeight: TextLineHeight?) -> TextParagraphStyle {
        // Aggregate every run, including runs that reuse the paragraph's cached style.
        if let height = lineHeight ?? environment.lineHeight {
            lineHeightMetrics.update(height)
        }
        return paragraph.style(environment: environment, alignment: alignment,
            writingDirection: writingDirection, lineHeight: lineHeight)
    }
}

extension Text.ResolvedProperties.Paragraph {
    mutating func style(environment: EnvironmentValues, alignment: TextParagraphAlignment?,
                        writingDirection: AttributedString.WritingDirection?, lineHeight: TextLineHeight?) -> TextParagraphStyle {
        if let cachedStyle { return cachedStyle }
        let result = makeParagraphStyle(context: ParagraphStyleResolutionContext(environment),
            alignment: alignment, fallbackAlignment: .layoutBased,
            writingDirection: writingDirection, fallbackWritingDirection: .contentBased, lineHeight: lineHeight)
        result.compositionLanguage = compositionLanguage
        if environment.shouldRedactContent {
            result.fullyJustified = true
            if result.baseWritingDirection == .natural {
                result.baseWritingDirection = environment.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
            }
            result.lineBreakMode = 1
        }
        cachedStyle = result
        return result
    }
}

func textCompositionLanguage(_ identifier: String) -> Int {
    guard ["zh", "wuu", "yue", "ja"].contains(where: identifier.hasPrefix) else { return 1 }
    let localizations = ["zxx", "zh-Hans", "wuu-Hans", "yue-Hans", "zh-Hant", "yue-Hant", "wuu-Hant", "ja"]
    let selected = Bundle.preferredLocalizations(from: localizations, forPreferences: [identifier]).first
    switch selected {
    case "ja": return 2
    case "zh-Hans", "wuu-Hans", "yue-Hans": return 3
    case "zh-Hant", "wuu-Hant", "yue-Hant": return 4
    default: return 1
    }
}

extension Text.ResolvedProperties.Paragraph {
    mutating func markParagraphBoundary(at index: Int, in text: String,
                                       environment: EnvironmentValues) -> TextParagraphStyle? {
        let cached = cachedStyle
        if let cached, cached.baseWritingDirection == .natural,
           cached.horizontalAlignment == .leading || cached.horizontalAlignment == .trailing {
            let directions = Set(languageIdentifiers.map { language -> Int? in
                switch Locale.Language(identifier: language).characterDirection {
                case .leftToRight: 0
                case .rightToLeft: 1
                default: nil
                }
            })
            if directions.count == 1, let direction = directions.first, let direction {
                cached.baseWritingDirection = direction == 1 ? .rightToLeft : .leftToRight
            } else if index == startIndex {
                cached.baseWritingDirection = environment.writingMode == .verticalRightToLeft || environment.layoutDirection == .leftToRight
                    ? .leftToRight : .rightToLeft
            } else {
                preconditionFailure("Content-based paragraph direction requires a statistical writing-direction backend.")
            }
        }
        markParagraphBoundary(at: index)
        return cached
    }
}

extension Text.ResolvedProperties {
    mutating func markParagraphBoundary(at index: Int, in text: String, environment: EnvironmentValues) {
        let oldStart = paragraph.startIndex
        let cached = paragraph.markParagraphBoundary(at: index, in: text, environment: environment)
        guard let cached else { return }
        if oldStart > 0 && multilineTextAlignment == nil { return }
        let alignment = cached.horizontalAlignment.textAlignment(for: environment.layoutDirection)
        if oldStart == 0 { multilineTextAlignment = alignment }
        else if multilineTextAlignment != alignment { multilineTextAlignment = nil }
    }
}
