//
//  File: Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

class AnyTextStorage {
    func resolve(typeFaces: [TypeFace], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        fatalError()
    }
    func resolveText(in environment: EnvironmentValues) -> String {
        fatalError()
    }
    func isEqual(to other: AnyTextStorage) -> Bool {
        self === other
    }
}

// NOTE: No String.LocalizationValue for non-Apple platforms.
//typealias LocalizedStringKey = String.LocalizationValue
public typealias LocalizedStringKey = String

class LocalizedTextStorage: AnyTextStorage {
    let key: LocalizedStringKey
    let table: String?
    let bundle: Bundle?
    init(key: LocalizedStringKey, table: String?, bundle: Bundle?) {
        self.key = key
        self.table = table
        self.bundle = bundle
    }

    override func resolve(typeFaces: [TypeFace], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        //let text = String(localized: self.key)
        let text = self.key
        return .init(storage: [.text(typeFaces, text)], scaleFactor: context.contentScaleFactor)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        //String(localized: key)
        self.key
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.key == other.key && self.table == other.table && self.bundle == other.bundle
        }
        return false
    }
}

class ConcatenatedTextStorage: AnyTextStorage {
    let first: Text
    let second: Text
    init(first: Text, second: Text) {
        self.first = first
        self.second = second
    }

    override func resolve(typeFaces: [TypeFace], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let first = first._resolve(context: context)
        let second = second._resolve(context: context)
        return .init(storage: first.storage + second.storage, scaleFactor: context.contentScaleFactor)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        first._resolveText(in: environment) + second._resolveText(in: environment)
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.first == other.first && self.second == other.second
        }
        return false
    }
}

class AttachmentTextStorage : AnyTextStorage {
    let image: Image
    init(_ image: Image) {
        self.image = image
    }

    override func resolve(typeFaces: [TypeFace], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let image = context.resolve(self.image)
        return .init(storage: [.attachment(typeFaces, image)], scaleFactor: context.contentScaleFactor)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        String()
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.image == other.image
        }
        return false
    }
}

public struct Text: Equatable {
    enum Storage: Equatable {
        case verbatim(String)
        case anyTextStorage(AnyTextStorage)

        static func == (lhs: Text.Storage, rhs: Text.Storage) -> Bool {
            if case let .verbatim(s1) = lhs, case let .verbatim(s2) = rhs {
                return s1 == s2
            }
            if case let .anyTextStorage(s1) = lhs, case let .anyTextStorage(s2) = rhs {
                return s1.isEqual(to: s2)
            }
            return false
        }
    }

    let storage: Storage

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
        let key = LocalizedStringKey(String(content))
        self.storage = .anyTextStorage(LocalizedTextStorage(key: key, table: nil, bundle: nil))
        self.modifiers = []
    }

    public init(verbatim content: String) {
        self.storage = .verbatim(content)
        self.modifiers = []
    }

    public init(_ image: Image) {
        self.storage = .anyTextStorage(AttachmentTextStorage(image))
        self.modifiers = []
    }

    init(storage: Storage, modifiers: [Modifier]) {
        self.storage = storage
        self.modifiers = modifiers
    }

    public func _resolveText(in environment: EnvironmentValues) -> String {
        if case let .verbatim(text) = self.storage {
            return text
        }
        if case let .anyTextStorage(storage) = self.storage {
            return storage.resolveText(in: environment)
        }
        return String()
    }

    func _resolve(context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let displayScale = context.sharedContext.contentScaleFactor
        var font = self.font ?? context.environment.font
        if font == nil {
            font = .system(.body)
        }
        font = font?.displayScale(displayScale)
        let defaultFace = font?.typeFace(forContext: context.sharedContext)
        let fallbackFaces = font?.fallbackTypeFaces ?? []
        let faces = ([defaultFace] + fallbackFaces).compactMap {$0 }

        if faces.isEmpty == false {
            var storage: [GraphicsContext.ResolvedText.Storage] = []
            if case let .verbatim(text) = self.storage {
                storage = [.text(faces, text)]
                return GraphicsContext.ResolvedText(storage: storage, scaleFactor: context.contentScaleFactor)
            }
            else if case let .anyTextStorage(text) = self.storage {
                return text.resolve(typeFaces: faces, context: context)
            }
        }
        return .init(storage: [], scaleFactor: context.contentScaleFactor)
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
}

extension Text {
    public static func + (lhs: Text, rhs: Text) -> Text {
        .init(storage: .anyTextStorage(ConcatenatedTextStorage(first: lhs,
                                                               second: rhs)),
              modifiers: [])
    }
}

extension Text: View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let generator = TextViewContext.Generator(graph: view,
                                                  baseInputs: inputs.base,
                                                  preferences: inputs.preferences)
        return _ViewOutputs(view: generator, preferences: PreferenceOutputs(preferences: []))
    }
}

extension Text: _PrimitiveView {
}

private class TextViewContext: ViewContext {
    var text: Text
    var resolvedText: GraphicsContext.ResolvedText?

    struct Generator : ViewGenerator {
        let graph: _GraphValue<Text>
        var baseInputs: _GraphInputs
        var preferences: PreferenceInputs
        var traits: ViewTraitKeys = ViewTraitKeys()

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let view = graph.value(atPath: self.graph, from: encloser) {
                return TextViewContext(view: view, inputs: baseInputs, graph: self.graph)
            }
            fatalError("Unable to recover view")
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            baseInputs.mergedInputs.append(inputs)
        }
    }

    init(view: Text, inputs: _GraphInputs, graph: _GraphValue<Text>) {
        self.text = view
        super.init(inputs: inputs, graph: graph)

        if self.inputs.environment.font == nil {
            self.inputs.environment.font = .system(.body)
        }
    }

    override func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        graph.value(atPath: self.graph, from: encloser) is Text
    }

    override func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
        if let view = graph.value(atPath: self.graph, from: encloser) as? Text {
            self.text = view
        } else {
            fatalError("Unable to recover Text")
        }
    }

    override func loadResources(_ context: GraphicsContext) {
        self.resolvedText = context.resolve(self.text)
        self.sharedContext.needsLayout = true
        super.loadResources(context)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if let resolvedText {
            if proposal == .zero {
                let lineGlyphs = resolvedText.makeGlyphs(maxWidth: 0, maxHeight: 0)
                if let glyph = lineGlyphs.first?.glyphs.first {
                    return glyph.advance / resolvedText.scaleFactor
                }
            } else if proposal == .infinity {
                return resolvedText.size()
            } else {
                var width: Int = .max
                var height: Int = .max
                if let pw = proposal.width, pw != .infinity {
                    width = Int(pw * resolvedText.scaleFactor)
                }
                if let ph = proposal.height, ph != .infinity {
                    height = Int(ph * resolvedText.scaleFactor)
                }
                return resolvedText.size(maxWidth: width, maxHeight: height)
            }
        }
        return proposal.replacingUnspecifiedDimensions()
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        if self.frame.width > 0 && self.frame.height > 0 {
            if self.resolvedText == nil {
                self.resolvedText = context.resolve(self.text)
                self.sharedContext.needsLayout = true
            }
            if let resolvedText {
                if let style = foregroundStyle.primary {
                    context.draw(resolvedText, in: frame, shading: .style(style))
                } else {
                    context.draw(resolvedText, in: frame)
                }
            }
        }
    }
}
