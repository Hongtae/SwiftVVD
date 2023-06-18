//
//  File: Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

struct AnyTextStorage {
    let content: any StringProtocol
}

public struct Text: View {
    struct Storage {
        let anyTextStorage: AnyTextStorage

        var unicodeScalars: any BidirectionalCollection {
            anyTextStorage.content.unicodeScalars as any BidirectionalCollection
        }
    }
    let storage: Storage

    public enum Case: Hashable {
        case lowercase
        case uppercase
    }

    public struct LineStyle {
        public struct Pattern {
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

    enum Modifier {
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
        self.storage = Storage(anyTextStorage: AnyTextStorage(content: content))
        self.modifiers = []
    }

    public init(verbatim content: String) {
        self.storage = Storage(anyTextStorage: AnyTextStorage(content: content))
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

class TextContext: ViewProxy {
    var view: _GraphValue<Text>
    var modifiers: [ObjectIdentifier: any ViewModifier]
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext
    var frame: CGRect

    var resolvedText: GraphicsContext.ResolvedText?

    init(view: _GraphValue<Text>, inputs: _ViewInputs) {
        self.modifiers = inputs.modifiers
        self.environmentValues = inputs.environmentValues
        self.view = self.environmentValues._resolve(view)
        self.sharedContext = inputs.sharedContext
        self.frame = .zero

        if self.environmentValues.font == nil {
            self.environmentValues.font = .system(.body)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
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

    func draw(frame: CGRect, context: GraphicsContext) {
        if self.frame.width > 0 && self.frame.height > 0 {
            if self.resolvedText == nil {
                self.resolvedText = context.resolve(self.view.value)
                self.sharedContext.needsLayout = true
            }
            if let resolvedText {
                context.draw(resolvedText, in: frame)
            }
        }
    }

    func modifier<K>(key: K.Type) -> K? where K : ViewModifier {
        modifiers[ObjectIdentifier(key)] as? K
    }

    func updateEnvironment(_ environmentValues: EnvironmentValues) {
        //self.environmentValues = environmentValues._resolve(modifiers: modifiers)
        // TODO: redraw
    }
}

extension Text: _PrimitiveView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = TextContext(view: view, inputs: inputs)
        return _ViewOutputs(item: .view(view))
    }
}
