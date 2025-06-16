//
//  File: Font.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension View {
    public func font(_ font: Font?) -> some View {
        return environment(\.font, font)
    }
}

enum FontEnvironmentKey: EnvironmentKey {
    static var defaultValue: Font? { return nil }
}

extension EnvironmentValues {
    public var font: Font? {
        set { self[FontEnvironmentKey.self] = newValue }
        get { self[FontEnvironmentKey.self] }
    }
}

var defaultFontURL: URL? {
    Bundle.module.url(forResource: "Roboto-Regular",
                      withExtension: "ttf",
                      subdirectory: "Fonts/Roboto")
}

let defaultDPI = 72

typealias GlyphData = TextureFont.GlyphData

protocol TypeFace {
    func glyphData(for c: UnicodeScalar) -> GlyphData?
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint
    func hasGlyph(for: UnicodeScalar) -> Bool

    var lineHeight: CGFloat { get }
    var ascender: CGFloat { get }
    var descender: CGFloat { get }

    func isEqual(to: any TypeFace) -> Bool
}

extension TextureFont: TypeFace {
    var lineHeight: CGFloat {
        self.lineHeight()
    }

    var identifier: String {
        if let data = self.fontData {
            return "\(self.familyName):\(unsafeBitCast(data.address, to: Int.self))"            
        } else {
            return "<\(self.filePath)>"
        }
    }

    func isEqual(to: any TypeFace) -> Bool {
        if let other = to as? TextureFont {
            return self === other
        }
        return false
    }
}

protocol TypeFaceProvider {    
    func isEqual(to: any TypeFaceProvider) -> Bool
    func hash(into hasher: inout Hasher)

    func makeTypeFace(_: AppContext, displayScale: CGFloat) -> TypeFace?

    var isShareable: Bool { get }
}

extension TypeFaceProvider {
    func makeTypeFace(_: SharedContext) -> TypeFace? { nil }
    var isShareable: Bool { true }
}

struct SystemFontProvider: TypeFaceProvider {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        self.size = size
        self.weight = weight
        self.design = design
    }

    func isEqual(to: any TypeFaceProvider) -> Bool {
        if let other = to as? Self {
            return self.size == other.size && 
                   self.weight == other.weight &&
                   self.design == other.design
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(size)
        hasher.combine(weight)
        hasher.combine(design)
    }

    func makeTypeFace(_ context: AppContext,
                      displayScale: CGFloat) -> TypeFace? {
        if let url = defaultFontURL {
            var data = context.resourceData(forURL: url)
            if data == nil {
                do {
                    Log.debug("Loading font resource: \(url)")
                    let d = try Data(contentsOf: url, options: [])
                    data = d.makeFixedAddressStorage()
                    if data != nil {
                        context.setResource(data: data, forURL: url)
                    }
                } catch {
                    Log.error("Error on loading data: \(error)")
                }
            }
            if let data, let device = context.graphicsDeviceContext {
                let dpi = CGFloat(defaultDPI) * displayScale
                let font = TextureFont(deviceContext: device, data: data)
                font?.setStyle(pointSize: self.size,
                               dpi: (UInt32(dpi), UInt32(dpi)))
                return font
            }
        }
        return nil
    }
}

struct CustomFontProvider: TypeFaceProvider {
    let name: String
    let size: CGFloat

    init(name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    func isEqual(to: any TypeFaceProvider) -> Bool {
        if let other = to as? Self {
            return self.name == other.name &&
                   self.size == other.size
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(size)
    }

    func makeTypeFace(_ context: AppContext,
                      displayScale: CGFloat) -> TypeFace? {
        nil
    }
}

struct FixedFontProvider: TypeFaceProvider {
    let font: TextureFont

    init(_ font: TextureFont) {
        self.font = font
    }

    var identifier: String {
        font.identifier        
    }

    func isEqual(to: any TypeFaceProvider) -> Bool {
        if let other = to as? Self {
            return ObjectIdentifier(self.font) == ObjectIdentifier(other.font)
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self.font))
    }

    func makeTypeFace(_: AppContext,
                      displayScale: CGFloat) -> TypeFace? { self.font }

    var isShareable: Bool { false }
}

class AnyFontBox: @unchecked Sendable {
    let fontBox: any TypeFaceProvider

    init(_ fontBox: any TypeFaceProvider) {
        self.fontBox = fontBox
    }

    func isEqual(to other: AnyFontBox) -> Bool {
        self.fontBox.isEqual(to: other.fontBox)
    }

    func hash(into hasher: inout Hasher) {
        fontBox.hash(into: &hasher)
    }

    func makeTypeFace(_ context: AppContext,
                      displayScale: CGFloat) -> TypeFace? {
        fontBox.makeTypeFace(context, displayScale: displayScale)
    }
    var isShareable: Bool { fontBox.isShareable }
}

public struct Font: Hashable, Sendable {
    let provider: AnyFontBox
    let displayScale: CGFloat

    init(provider: AnyFontBox, displayScale: CGFloat) {
        self.provider = provider
        self.displayScale = displayScale
    }

    public static func == (lhs: Font, rhs: Font) -> Bool {
        lhs.provider.isEqual(to: rhs.provider) &&
        lhs.displayScale == rhs.displayScale
    }

    public func hash(into hasher: inout Hasher) {
        provider.hash(into: &hasher)
        hasher.combine(displayScale)
    }

    func typeFace(forContext context: SharedContext) -> TypeFace? {
        if provider.isShareable {
            if let typeFace = context.cachedTypeFaces[self] {
                return typeFace
            }
            if let typeFace = provider.makeTypeFace(
                context.app,
                displayScale: self.displayScale) {
                context.cachedTypeFaces[self] = typeFace
                return typeFace
            }
        } else {
            return provider.makeTypeFace(context.app,
                                         displayScale: self.displayScale)
        }
        return nil
    }

    var fallbackTypeFaces: [TypeFace] {
        []
    }

    func displayScale(_ scale: CGFloat) -> Font {
        Font(provider: self.provider, displayScale: scale)
    }
}

extension Font {
    public enum Design: Hashable {
        case `default`
        case serif
        case rounded
        case monospaced
    }

    public enum TextStyle: CaseIterable {
        case largeTitle
        case title
        case headline
        case subheadline
        case body
        case callout
        case footnote
        case caption
    }
}

extension Font {

    public init(_ font: TextureFont) {
        let fontBox = FixedFontProvider(font)
        self.init(provider: AnyFontBox(fontBox), displayScale: 1)
    }

    static func pointSize(for style: TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:   return 26
        case .title:        return 24
        case .headline:     return 21
        case .subheadline:  return 18
        case .body:         return 14
        case .callout:      return 12
        case .footnote:     return 8
        case .caption:      return 8
        }
    }

    public static func system(_ style: Font.TextStyle, design: Font.Design = .default) -> Font {
        let provider = SystemFontProvider(size: pointSize(for: style), weight: .regular, design: design)
        return Font(provider: AnyFontBox(provider), displayScale: 1)
    }

    public static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let provider = SystemFontProvider(size: size, weight: weight, design: design)
        return Font(provider: AnyFontBox(provider), displayScale: 1)
    }

    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        let provider = CustomFontProvider(name: name, size: pointSize(for: textStyle) + size)
        return Font(provider: AnyFontBox(provider), displayScale: 1)
    }

    public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
        let provider = CustomFontProvider(name: name, size: fixedSize)
        return Font(provider: AnyFontBox(provider), displayScale: 1)
    }

    public static func custom(_ name: String, size: CGFloat) -> Font {
        let provider = CustomFontProvider(name: name, size: size)
        return Font(provider: AnyFontBox(provider), displayScale: 1)
    }
}

extension Font {
    public struct Weight: Hashable, Sendable {
        public var value: CGFloat

        public static let ultraLight = Weight(value: 100)
        public static let thin = Weight(value: 200)
        public static let light = Weight(value: 300)
        public static let regular = Weight(value: 400)
        public static let medium = Weight(value: 500)
        public static let semibold = Weight(value: 600)
        public static let bold = Weight(value: 700)
        public static let heavy = Weight(value: 800)
        public static let black = Weight(value: 900)
    }

    public static let largeTitle = Font.system(Font.TextStyle.largeTitle)
    public static let title = Font.system(Font.TextStyle.title)
    public static let headline = Font.system(Font.TextStyle.headline)
    public static let subheadline = Font.system(Font.TextStyle.subheadline)
    public static let body = Font.system(Font.TextStyle.body)
    public static let callout = Font.system(Font.TextStyle.callout)
    public static let footnote = Font.system(Font.TextStyle.footnote)
    public static let caption = Font.system(Font.TextStyle.caption)
}
