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

protocol FontBox: AnyObject {
    var identifier: String { get }
    var style: FaceStyle { get }
}

class CustomFontBox: FontBox {
    let identifier: String
    let style: FaceStyle

    init(identifier: String, style: FaceStyle) {
        self.identifier = identifier
        self.style = style
    }
}

class FixedFontBox: FontBox {
    let identifier: String
    let style: FaceStyle

    let font: DKGame.Font

    init(_ font: DKGame.Font) {
        self.font = font
        self.identifier = font.identifier
        self.style = FaceStyle(pointSize: font.pointSize,
                               outilne: font.outline,
                               embolden: font.embolden,
                               dpi: Int(font.dpi.x))

    }
}

class AnyFontBox {
    let fontBox: FontBox

    var identifier: String  { fontBox.identifier }
    var style: FaceStyle    { fontBox.style }

    init(_ fontBox: FontBox) {
        self.fontBox = fontBox
    }
}

public struct Font: Hashable {
    let provider: AnyFontBox

    init(provider: AnyFontBox) {
        self.provider = provider
    }

    public static func == (lhs: Font, rhs: Font) -> Bool {
        lhs.provider.identifier == rhs.provider.identifier &&
        lhs.provider.style == rhs.provider.style
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(provider.identifier)
        hasher.combine(provider.style)
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

    public static func system(_ style: Font.TextStyle, design: Font.Design = .default) -> Font {
        let style = FaceStyle(pointSize: 16,
                              outilne: 0,
                              embolden: 0)
        let fontBox = CustomFontBox(identifier: "system-default", style: style)
        return Font(provider: AnyFontBox(fontBox))
    }

    public static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let style = FaceStyle(pointSize: 16,
                              outilne: 0,
                              embolden: 0)
        let fontBox = CustomFontBox(identifier: "system-default", style: style)
        return Font(provider: AnyFontBox(fontBox))
    }

    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        let style = FaceStyle(pointSize: 16,
                              outilne: 0,
                              embolden: 0)
        let fontBox = CustomFontBox(identifier: "system-default", style: style)
        return Font(provider: AnyFontBox(fontBox))
    }

    public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
        let style = FaceStyle(pointSize: fixedSize,
                              outilne: 0,
                              embolden: 0)
        let fontBox = CustomFontBox(identifier: "system-default", style: style)
        return Font(provider: AnyFontBox(fontBox))
    }

    public static func custom(_ name: String, size: CGFloat) -> Font {
        let style = FaceStyle(pointSize: 16,
                              outilne: 0,
                              embolden: 0)
        let fontBox = CustomFontBox(identifier: "system-default", style: style)
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
