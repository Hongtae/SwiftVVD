//
//  File: Font.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

var defaultFontURL: URL? {
    Bundle.module.url(forResource: "Roboto-Regular",
                      withExtension: "ttf",
                      subdirectory: "Fonts/Roboto")
}

struct FaceStyle: Hashable {
    var pointSize: CGFloat
    var outilne: CGFloat
    var embolden: CGFloat
    var dpi: Int = 96
}

protocol TypeFace {
    func glyphData(for c: UnicodeScalar) -> GlyphData?
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint
    var lineHeight: CGFloat { get }
}

typealias GlyphData = DKGame.Font.GlyphData

extension DKGame.Font {
    func setStyle(_ style: FaceStyle, scale: CGFloat) {
        let dpi = CGFloat(style.dpi) * scale
        self.setStyle(pointSize: style.pointSize,
                      dpi: (UInt32(dpi), UInt32(dpi)),
                      embolden: 0,
                      outline: 0,
                      enableKerning: true,
                      forceBitmap: true)
    }

    var identifier: String {
        if let data = self.fontData {
            return "\(self.familyName):\(ObjectIdentifier(data))"            
        } else {
            return "<\(self.filePath)>"
        }
    }
}

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

protocol FontBox {    
    func isEqual(to: any FontBox) -> Bool
    func hash(into hasher: inout Hasher)
}

struct SystemFontBox: FontBox {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        self.size = size
        self.weight = weight
        self.design = design
    }

    func isEqual(to: any FontBox) -> Bool {
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
}

struct CustomFontBox: FontBox {
    let name: String
    let size: CGFloat

    init(name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    func isEqual(to: any FontBox) -> Bool {
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
}

struct FixedFontBox: FontBox {
    let font: DKGame.Font

    init(_ font: DKGame.Font) {
        self.font = font
    }

    var identifier: String {
        font.identifier        
    }
    var faceStyle: FaceStyle {
        FaceStyle(pointSize: font.pointSize,
                  outilne: font.outline,
                  embolden: font.embolden,
                  dpi: Int(font.dpi.x))
    }

    func isEqual(to: any FontBox) -> Bool {
        if let other = to as? Self {
            return ObjectIdentifier(self.font) == ObjectIdentifier(other.font)
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self.font))
    }
}

class AnyFontBox {
    let fontBox: any FontBox

    init(_ fontBox: any FontBox) {
        self.fontBox = fontBox
    }

    func isEqual(to other: AnyFontBox) -> Bool {
        self.fontBox.isEqual(to: other.fontBox) && other.fontBox.isEqual(to: self.fontBox)
    }

    func hash(into hasher: inout Hasher) {
        fontBox.hash(into: &hasher)
    }
}

public struct Font: Hashable {
    let provider: AnyFontBox

    init(provider: AnyFontBox) {
        self.provider = provider
    }

    public static func == (lhs: Font, rhs: Font) -> Bool {
        lhs.provider.isEqual(to: rhs.provider)
    }

    public func hash(into hasher: inout Hasher) {
        provider.hash(into: &hasher)
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

    public init(_ font: DKGame.Font) {
        let fontBox = FixedFontBox(font)
        self.init(provider: AnyFontBox(fontBox))
    }

    static func pointSize(for style: TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:   return 26
        case .title:        return 24
        case .headline:     return 21
        case .subheadline:  return 18
        case .body:         return 16
        case .callout:      return 12
        case .footnote:     return 8
        case .caption:      return 8
        }
    }

    public static func system(_ style: Font.TextStyle, design: Font.Design = .default) -> Font {
        let fontBox = SystemFontBox(size: pointSize(for: style), weight: .regular, design: design)
        return Font(provider: AnyFontBox(fontBox))
    }

    public static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let fontBox = SystemFontBox(size: size, weight: weight, design: design)
        return Font(provider: AnyFontBox(fontBox))
    }

    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        let fontBox = CustomFontBox(name: name, size: pointSize(for: textStyle) + size)
        return Font(provider: AnyFontBox(fontBox))
    }

    public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
        let fontBox = CustomFontBox(name: name, size: fixedSize)
        return Font(provider: AnyFontBox(fontBox))
    }

    public static func custom(_ name: String, size: CGFloat) -> Font {
        let fontBox = CustomFontBox(name: name, size: size)
        return Font(provider: AnyFontBox(fontBox))
    }
}

extension Font {
    public struct Weight: Hashable {
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
    public static var headline = Font.system(Font.TextStyle.headline)
    public static var subheadline = Font.system(Font.TextStyle.subheadline)
    public static var body = Font.system(Font.TextStyle.body)
    public static var callout = Font.system(Font.TextStyle.callout)
    public static var footnote = Font.system(Font.TextStyle.footnote)
    public static var caption = Font.system(Font.TextStyle.caption)
}

extension Font {
    func load(_ context: SharedContext) {
        //provider.load(context)
    }

    func glyphData(for c: UnicodeScalar) -> GlyphData? {
        nil
    }

    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        .zero
    }

    var lineHeight: CGFloat {
        0
    }

}

