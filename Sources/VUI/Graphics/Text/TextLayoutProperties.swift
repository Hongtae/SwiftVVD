//
//  File: TextLayoutProperties.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Text {
    public enum TruncationMode: Hashable, Sendable {
        case head
        case tail
        case middle

        fileprivate var protobufValue: UInt {
            switch self {
            case .head: 1
            case .tail: 2
            case .middle: 3
            }
        }

        fileprivate init?(protobufValue: UInt) {
            switch protobufValue {
            case 1: self = .head
            case 2: self = .tail
            case 3: self = .middle
            default: return nil
            }
        }
    }

    struct Sizing: Equatable, @unchecked Sendable {
        enum Storage: UInt8, Hashable {
            case standard = 0
            case uniformLineHeight = 1
            case adjustsForOversizedCharacters = 2
        }

        var storage: Storage
        var modifiers: [AnyTextSizingModifier]

        init(_ storage: Storage) {
            self.storage = storage
            self.modifiers = []
        }

        static let standard = Sizing(.standard)
        static let uniformLineHeight = Sizing(.uniformLineHeight)
        static let adjustsForOversizedCharacters = Sizing(.adjustsForOversizedCharacters)
    }

    struct Baseline: Equatable {
        enum Storage: UInt8, Hashable {
            case standard = 0
            case balanced = 1
        }

        var storage: Storage

        static let standard = Baseline(storage: .standard)
        static let balanced = Baseline(storage: .balanced)
    }

    struct WritingMode: Hashable {
        enum Storage: UInt8, Hashable {
            case horizontalTopToBottom = 0
            case verticalRightToLeft = 1
        }

        var storage: Storage

        static let horizontalTopToBottom = WritingMode(storage: .horizontalTopToBottom)
        static let verticalRightToLeft = WritingMode(storage: .verticalRightToLeft)
    }
}

struct TextLayoutMargins: Equatable {
    var sizing: Text.Sizing = .standard
    var baseline: Text.Baseline = .standard
}

protocol TextSizingModifier {
    func updateLayoutMargins(_ margins: inout EdgeInsets)
}

class AnyTextSizingModifier: TextSizingModifier, Equatable {
    func updateLayoutMargins(_ margins: inout EdgeInsets) {
        fatalError("AnyTextSizingModifier.updateLayoutMargins must be overridden")
    }

    func isEqual(to other: AnyTextSizingModifier) -> Bool {
        fatalError("AnyTextSizingModifier.isEqual must be overridden")
    }

    static func == (lhs: AnyTextSizingModifier, rhs: AnyTextSizingModifier) -> Bool {
        lhs.isEqual(to: rhs)
    }
}

struct TextShape: Equatable {
    private enum Exclusion: Equatable {
        case top(HorizontalEdge, CGSize)
    }

    private var exclusion: Exclusion?

    static var bounds: TextShape {
        TextShape(exclusion: nil)
    }

    static func excludeTop(_ edge: HorizontalEdge, size: CGSize) -> TextShape {
        TextShape(exclusion: .top(edge, size))
    }
}

struct TextJustification: Hashable {
    struct Full: Hashable {
        var allLines: Bool
        var flexible: Bool
    }

    enum Storage: Hashable {
        case full(Full)
        case none
    }

    var storage: Storage

    static var none: TextJustification {
        TextJustification(storage: .none)
    }

    static var full: TextJustification {
        TextJustification(storage: .full(Full(allLines: false, flexible: false)))
    }

    static var stretched: TextJustification {
        stretched(true)
    }

    static func stretched(_ flexible: Bool) -> TextJustification {
        TextJustification(storage: .full(Full(allLines: true, flexible: flexible)))
    }

    static func full(allLines: Bool, flexible: Bool) -> TextJustification {
        TextJustification(storage: .full(Full(allLines: allLines, flexible: flexible)))
    }
}

private struct LineLimitKey: EnvironmentKey {
    static var defaultValue: Int? { nil }
}

private struct LowerLineLimitKey: EnvironmentKey {
    static var defaultValue: Int? { nil }
}

private struct TruncationModeKey: EnvironmentKey {
    static var defaultValue: Text.TruncationMode { .tail }
}

private struct MinimumScaleFactorKey: EnvironmentKey {
    static var defaultValue: CGFloat { 1 }
}

private struct LineSpacingKey: EnvironmentKey {
    static var defaultValue: CGFloat { 0 }
}

private struct LineHeightMultipleKey: EnvironmentKey {
    static var defaultValue: CGFloat { 0 }
}

private struct MaximumLineHeightKey: EnvironmentKey {
    static var defaultValue: CGFloat { 0 }
}

private struct MinimumLineHeightKey: EnvironmentKey {
    static var defaultValue: CGFloat { 0 }
}

private struct HyphenationFactorKey: EnvironmentKey {
    static var defaultValue: CGFloat { 0 }
}

private struct HyphenationDisabledKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

private struct BodyHeadOutdentKey: EnvironmentKey {
    static var defaultValue: CGFloat { 0 }
}

private struct WritingModeKey: EnvironmentKey {
    static var defaultValue: Text.WritingMode { .horizontalTopToBottom }
}

private struct TextLayoutMarginsKey: EnvironmentKey {
    static var defaultValue: TextLayoutMargins { TextLayoutMargins() }
}

private struct TextShapeKey: EnvironmentKey {
    static var defaultValue: TextShape { .bounds }
}

private struct TextJustificationKey: EnvironmentKey {
    static var defaultValue: TextJustification { .none }
}

extension EnvironmentValues {
    public var lineLimit: Int? {
        get { self[LineLimitKey.self] }
        set { self[LineLimitKey.self] = newValue }
    }

    var lowerLineLimit: Int? {
        get { self[LowerLineLimitKey.self] }
        set { self[LowerLineLimitKey.self] = newValue }
    }

    public var truncationMode: Text.TruncationMode {
        get { self[TruncationModeKey.self] }
        set { self[TruncationModeKey.self] = newValue }
    }

    public var minimumScaleFactor: CGFloat {
        get { self[MinimumScaleFactorKey.self] }
        set {
            self[MinimumScaleFactorKey.self] = newValue > 1 || newValue <= 0 ? 1 : newValue
        }
    }

    public var lineSpacing: CGFloat {
        get { self[LineSpacingKey.self] }
        set { self[LineSpacingKey.self] = newValue }
    }

    var lineHeightMultiple: CGFloat {
        get { self[LineHeightMultipleKey.self] }
        set { self[LineHeightMultipleKey.self] = newValue }
    }

    var maximumLineHeight: CGFloat {
        get { self[MaximumLineHeightKey.self] }
        set { self[MaximumLineHeightKey.self] = newValue }
    }

    var minimumLineHeight: CGFloat {
        get { self[MinimumLineHeightKey.self] }
        set { self[MinimumLineHeightKey.self] = newValue }
    }

    var hyphenationFactor: CGFloat {
        get { self[HyphenationFactorKey.self] }
        set { self[HyphenationFactorKey.self] = newValue }
    }

    var hyphenationDisabled: Bool {
        get { self[HyphenationDisabledKey.self] }
        set { self[HyphenationDisabledKey.self] = newValue }
    }

    var bodyHeadOutdent: CGFloat {
        get { self[BodyHeadOutdentKey.self] }
        set { self[BodyHeadOutdentKey.self] = newValue }
    }

    var writingMode: Text.WritingMode {
        get { self[WritingModeKey.self] }
        set { self[WritingModeKey.self] = newValue }
    }

    var textLayoutMargins: TextLayoutMargins {
        get { self[TextLayoutMarginsKey.self] }
        set { self[TextLayoutMarginsKey.self] = newValue }
    }

    var textSizing: Text.Sizing {
        get { textLayoutMargins.sizing }
        set { textLayoutMargins.sizing = newValue }
    }

    var textBaseline: Text.Baseline {
        get { textLayoutMargins.baseline }
        set { textLayoutMargins.baseline = newValue }
    }

    var textShape: TextShape {
        get { self[TextShapeKey.self] }
        set { self[TextShapeKey.self] = newValue }
    }

    var textJustification: TextJustification {
        get { self[TextJustificationKey.self] }
        set { self[TextJustificationKey.self] = newValue }
    }
}

extension View {
    @inlinable public func lineLimit(_ number: Int?) -> some View {
        environment(\.lineLimit, number)
    }

    @inlinable public func truncationMode(_ mode: Text.TruncationMode) -> some View {
        environment(\.truncationMode, mode)
    }

    @inlinable public func lineSpacing(_ lineSpacing: CGFloat) -> some View {
        environment(\.lineSpacing, lineSpacing)
    }

    @inlinable public func minimumScaleFactor(_ factor: CGFloat) -> some View {
        environment(\.minimumScaleFactor, factor)
    }
}

struct TextLayoutProperties: Equatable {
    struct Key: DerivedEnvironmentKey {
        static func value(in environment: EnvironmentValues) -> TextLayoutProperties {
            TextLayoutProperties(from: environment)
        }
    }

    private struct Flags: OptionSet, Equatable {
        let rawValue: UInt8

        static let widthIsFlexible = Flags(rawValue: 1)
        static let sizeFitting = Flags(rawValue: 1 << 1)

        mutating func set(_ member: Flags, to value: Bool) {
            if value {
                insert(member)
            } else {
                remove(member)
            }
        }
    }

    var lineLimit: Int?
    var lowerLineLimit: Int?
    var truncationMode: Text.TruncationMode
    var multilineTextAlignment: TextAlignment
    var layoutDirection: LayoutDirection
    var transitionStyle: ContentTransition.Style
    var minScaleFactor: CGFloat
    var lineSpacing: CGFloat
    var lineHeightMultiple: CGFloat
    var maximumLineHeight: CGFloat
    var minimumLineHeight: CGFloat
    var hyphenationFactor: CGFloat
    var hyphenationDisabled: Bool
    var writingMode: Text.WritingMode
    var bodyHeadOutdent: CGFloat
    var pixelLength: CGFloat
    var textSizing: Text.Sizing
    var textBaseline: Text.Baseline
    var textShape: TextShape
    private var flags: Flags

    var widthIsFlexible: Bool {
        get { flags.contains(.widthIsFlexible) }
        set { flags.set(.widthIsFlexible, to: newValue) }
    }

    var sizeFitting: Bool {
        get { flags.contains(.sizeFitting) }
        set { flags.set(.sizeFitting, to: newValue) }
    }

    init() {
        lineLimit = nil
        lowerLineLimit = nil
        truncationMode = .tail
        multilineTextAlignment = .leading
        layoutDirection = .leftToRight
        transitionStyle = .default
        minScaleFactor = 1
        lineSpacing = 0
        lineHeightMultiple = 0
        maximumLineHeight = 0
        minimumLineHeight = 0
        hyphenationFactor = 0
        hyphenationDisabled = false
        writingMode = .horizontalTopToBottom
        bodyHeadOutdent = 0
        pixelLength = 1
        textSizing = .standard
        textBaseline = .standard
        textShape = .bounds
        flags = []
    }

    init(from environment: EnvironmentValues) {
        lineLimit = environment.lineLimit.map { max($0, 1) }
        lowerLineLimit = environment.lowerLineLimit.map { max($0, 0) }
        truncationMode = environment.truncationMode
        multilineTextAlignment = environment.multilineTextAlignment
        layoutDirection = environment.layoutDirection
        transitionStyle = environment.contentTransitionState.style
        minScaleFactor = environment.minimumScaleFactor
        lineSpacing = environment.lineSpacing
        lineHeightMultiple = environment.lineHeightMultiple
        maximumLineHeight = environment.maximumLineHeight
        minimumLineHeight = environment.minimumLineHeight
        hyphenationFactor = environment.hyphenationFactor
        hyphenationDisabled = environment.hyphenationDisabled
        writingMode = environment.writingMode
        bodyHeadOutdent = environment.bodyHeadOutdent
        pixelLength = environment.animationPixelLength
        let margins = environment.textLayoutMargins
        textSizing = margins.sizing
        textBaseline = margins.baseline
        textShape = environment.textShape
        flags = []
        if case let .full(full) = environment.textJustification.storage {
            widthIsFlexible = full.flexible
        }
    }
}

extension TextLayoutProperties: ProtobufEncodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        if truncationMode != .tail {
            encoder.encodeVarint(1 << 3)
            encoder.encodeVarint(truncationMode.protobufValue)
        }
        if let lineLimit {
            encoder.encodeVarint(2 << 3)
            encoder.encodeSignedVarint(lineLimit)
        }
        if let lowerLineLimit {
            encoder.encodeVarint(3 << 3)
            encoder.encodeSignedVarint(lowerLineLimit)
        }
        if minScaleFactor != 1 {
            encoder.encodeCGFloatFieldAlways(4, minScaleFactor)
        }
        if lineSpacing != 0 {
            encoder.encodeCGFloatFieldAlways(5, lineSpacing)
        }
        if lineHeightMultiple != 0 {
            encoder.encodeCGFloatFieldAlways(6, lineHeightMultiple)
        }
        if maximumLineHeight != 0 {
            encoder.encodeCGFloatFieldAlways(7, maximumLineHeight)
        }
        if minimumLineHeight != 0 {
            encoder.encodeCGFloatFieldAlways(8, minimumLineHeight)
        }
        if hyphenationFactor != 0 {
            encoder.encodeCGFloatFieldAlways(9, hyphenationFactor)
        }
        if bodyHeadOutdent != 0 {
            encoder.encodeCGFloatFieldAlways(10, bodyHeadOutdent)
        }
        if pixelLength != 1 {
            encoder.encodeCGFloatFieldAlways(11, pixelLength)
        }
        if multilineTextAlignment != .leading {
            encoder.encodeVarint(12 << 3)
            encoder.encodeVarint(UInt(multilineTextAlignment.protobufValue))
        }
        if layoutDirection == .rightToLeft {
            encoder.encodeVarint(13 << 3)
            encoder.encodeVarint(1)
        }
        if transitionStyle != .default {
            try encoder.encodeMessageField(14, transitionStyle)
        }
        if writingMode != .horizontalTopToBottom {
            encoder.encodeVarint(16 << 3)
            encoder.encodeVarint(UInt(writingMode.storage.rawValue))
        }
        if widthIsFlexible {
            encoder.encodeVarint(17 << 3)
            encoder.encodeVarint(1)
        }
        if textSizing.storage != .standard {
            encoder.encodeVarint(18 << 3)
            encoder.encodeVarint(UInt(textSizing.storage.rawValue))
        }
        if sizeFitting {
            encoder.encodeVarint(19 << 3)
            encoder.encodeVarint(1)
        }
        if hyphenationDisabled {
            encoder.encodeVarint(20 << 3)
            encoder.encodeVarint(1)
        }
    }
}

extension TextLayoutProperties: ProtobufDecodableMessage {
    init(from decoder: inout ProtobufDecoder) throws {
        self.init()

        while let field = try decoder.nextField() {
            let fieldNumber = field.tag
            let wireType = field.wireType.rawValue

            switch fieldNumber {
            case 1:
                guard wireType == 0,
                      let value = Text.TruncationMode(protobufValue: try decoder.decodeVarint())
                else { throw ProtobufDecoder.DecodingError.failed }
                truncationMode = value
            case 2:
                guard wireType == 0 else { throw ProtobufDecoder.DecodingError.failed }
                lineLimit = try decoder.intField(field)
            case 3:
                guard wireType == 0 else { throw ProtobufDecoder.DecodingError.failed }
                lowerLineLimit = try decoder.intField(field)
            case 4:
                minScaleFactor = try decoder.cgFloatField(field)
            case 5:
                lineSpacing = try decoder.cgFloatField(field)
            case 6:
                lineHeightMultiple = try decoder.cgFloatField(field)
            case 7:
                maximumLineHeight = try decoder.cgFloatField(field)
            case 8:
                minimumLineHeight = try decoder.cgFloatField(field)
            case 9:
                hyphenationFactor = try decoder.cgFloatField(field)
            case 10:
                bodyHeadOutdent = try decoder.cgFloatField(field)
            case 11:
                pixelLength = try decoder.cgFloatField(field)
            case 12:
                guard wireType == 0,
                      let value = TextAlignment(protobufValue: try decoder.decodeVarint())
                else { throw ProtobufDecoder.DecodingError.failed }
                multilineTextAlignment = value
            case 13:
                guard wireType == 0 else { throw ProtobufDecoder.DecodingError.failed }
                layoutDirection = try decoder.decodeVarint() == 1 ? .rightToLeft : .leftToRight
            case 14:
                guard wireType == 2 else { throw ProtobufDecoder.DecodingError.failed }
                transitionStyle = try decoder.messageField(field) as ContentTransition.Style
            case 16:
                guard wireType == 0,
                      let storage = Text.WritingMode.Storage(rawValue: UInt8(try decoder.decodeVarint()))
                else { throw ProtobufDecoder.DecodingError.failed }
                writingMode = Text.WritingMode(storage: storage)
            case 17:
                guard wireType == 0 else { throw ProtobufDecoder.DecodingError.failed }
                widthIsFlexible = try decoder.decodeVarint() == 1
            case 18:
                guard wireType == 0,
                      let storage = Text.Sizing.Storage(rawValue: UInt8(try decoder.decodeVarint()))
                else { throw ProtobufDecoder.DecodingError.failed }
                textSizing = Text.Sizing(storage)
            case 19:
                guard wireType == 0 else { throw ProtobufDecoder.DecodingError.failed }
                sizeFitting = try decoder.decodeVarint() == 1
            case 20:
                guard wireType == 0 else { throw ProtobufDecoder.DecodingError.failed }
                hyphenationDisabled = try decoder.decodeVarint() == 1
            default:
                try decoder.skipField(field)
            }
        }
    }
}

private extension TextAlignment {
    var protobufValue: UInt8 {
        switch self {
        case .leading: 1
        case .center: 2
        case .trailing: 3
        }
    }

    init?(protobufValue: UInt) {
        switch protobufValue {
        case 1: self = .leading
        case 2: self = .center
        case 3: self = .trailing
        default: return nil
        }
    }
}
