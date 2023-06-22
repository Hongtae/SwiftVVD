//
//  File: Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

class AnyTextStorage: Equatable {
    let content: any StringProtocol

    init(content: any StringProtocol) {
        self.content = content
    }

    static func == (lhs: AnyTextStorage, rhs: AnyTextStorage) -> Bool {
        String(lhs.content) == String(rhs.content)
    }
}

public struct Text: Equatable {
    enum Storage: Equatable {
        case verbatim(String)
        case anyTextStorage(AnyTextStorage)
    }

    let storage: Storage

    var unicodeScalars: any BidirectionalCollection {
        switch self.storage {
        case let .verbatim(text):
            return text
        case let .anyTextStorage(anyTextStorage):
            return anyTextStorage.content.unicodeScalars as any BidirectionalCollection
        }
    }

    public enum Case: Hashable {
        case lowercase
        case uppercase
    }

    public struct LineStyle: Hashable {
        public struct Pattern: Equatable {
            enum UnderlineStyle {
                case solid
                case dot
                case dash
                case dashDot
                case dashDotDot
            }
            let underlineStyle: UnderlineStyle
            let color: Color?

            init(_ underlineStyle: UnderlineStyle) {
                self.underlineStyle = underlineStyle
                self.color = nil
            }

            public static let solid = Pattern(.solid)
            public static let dot = Pattern(.dot)
            public static let dash = Pattern(.dash)
            public static let dashDot = Pattern(.dashDot)
            public static let dashDotDot = Pattern(.dashDotDot)

            public init(pattern: Text.LineStyle.Pattern = .solid,
                        color: Color? = nil) {
                self.underlineStyle = pattern.underlineStyle
                self.color = color
            }
        }
    }

    enum Modifier: Equatable {
        case font(Font)
        case fontWeight(Font.Weight)
        case foregroundColor(Color)
        case bold(Bool)
        case italic(Bool)
        case strikethrough(Bool, LineStyle.Pattern, Color?)
        case underline(Bool, LineStyle.Pattern, Color?)
        case monospacedDigit
        case kerning(CGFloat)
        case tracking(CGFloat)
        case baselineOffset(CGFloat)
        case textCase(Case)
    }

    let modifiers: [Modifier]

    public init<S>(_ content: S) where S : StringProtocol {
        self.storage = .anyTextStorage(AnyTextStorage(content: content))
        self.modifiers = []
    }

    public init(verbatim content: String) {
        self.storage = .verbatim(content)
        self.modifiers = []
    }

    init(storage: Storage, modifiers: [Modifier]) {
        self.storage = storage
        self.modifiers = modifiers
    }
}

extension Text {
    public func font(_ font: Font?) -> Text {
        var modifiers: [Modifier] = []
        self.modifiers.forEach {
            if case .font(_) = $0 { } else {
                modifiers.append($0)
            }
        }
        if let font {
            modifiers.append(.font(font))
        }
        return Text(storage: self.storage, modifiers: modifiers)
    }

    var font: Font? {
        self.modifiers.compactMap {
            if case let .font(font) = $0 { return font }
            return nil
        }.first
    }

    public func fontWeight(_ weight: Font.Weight?) -> Text {
        var modifiers: [Modifier] = []
        self.modifiers.forEach {
            if case .fontWeight(_) = $0 { } else {
                modifiers.append($0)
            }
        }
        if let weight {
            modifiers.append(.fontWeight(weight))
        }
        return Text(storage: self.storage, modifiers: modifiers)
    }

    var fontWeight: Font.Weight? {
        self.modifiers.compactMap {
            if case let .fontWeight(weight) = $0 { return weight }
            return nil
        }.first
    }
    
    var ellipsis: String { "..." }
}

extension Text: View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = view.value.makeViewProxy(inputs: inputs)
        return _ViewOutputs(item: .view(view))
    }
}

extension Text: PrimitiveView {
}

extension Text: ViewProxyProvider {
    func makeViewProxy(inputs: _ViewInputs) -> ViewProxy {
        return TextContext(view: self, inputs: inputs)
    }
}

class TextContext: ViewProxy {
    var view: Text
    var resolvedText: GraphicsContext.ResolvedText?

    init(view: Text, inputs: _ViewInputs) {
        self.view = inputs.environmentValues._resolve(view)
        super.init(inputs: inputs)

        if self.environmentValues.font == nil {
            self.environmentValues.font = .system(.body)
        }
    }

    override func loadView(context: GraphicsContext) {
        self.resolvedText = context.resolve(self.view)
        self.sharedContext.needsLayout = true
        super.loadView(context: context)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if let resolvedText {
            if proposal == .zero {
                if let glyph = resolvedText.lines.first?.glyphs.first {
                    let bounds = GraphicsContext.ResolvedText.Glyph.bounds([glyph])
                    return CGSize(width: bounds.width, height: bounds.height)
                } else {
                    let proposed = proposal.replacingUnspecifiedDimensions()
                    return resolvedText.measure(in: proposed)
                }
            } else if proposal == .infinity {
                let frame = resolvedText.frame
                return CGSize(width: frame.maxX, height: frame.maxY)
            } else {
                let frame = resolvedText.frame
                return CGSize(width: frame.maxX, height: frame.maxY)
            }
        }
        return proposal.replacingUnspecifiedDimensions()
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        if self.frame.width > 0 && self.frame.height > 0 {
            if self.resolvedText == nil {
                self.resolvedText = context.resolve(self.view)
                self.sharedContext.needsLayout = true
            }
            if let resolvedText {
                context.draw(resolvedText, in: frame)
            }
        }
    }
}
