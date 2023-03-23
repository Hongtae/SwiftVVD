//
//  File: Font.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

struct FaceStyle: Hashable {
    var pointSize: CGFloat
    var outilne: CGFloat
    var embolden: CGFloat
    var dpiX: UInt32
    var dpiY: UInt32
    var enableKerning: Bool
    var forceBitmap: Bool
}

typealias GlyphData = DKGame.Font.GlyphData

func faceStyle(from font: DKGame.Font) -> FaceStyle {
    FaceStyle(pointSize: font.pointSize,
              outilne: font.outline,
              embolden: font.embolden,
              dpiX: font.dpi.x,
              dpiY: font.dpi.y,
              enableKerning: font.kerningEnabled,
              forceBitmap: font.forceBitmap)
}

class AnyFontBox {
    var font: DKGame.Font?

    let identifier: String
    let style: FaceStyle

    init(font: DKGame.Font? = nil, identifier: String, style: FaceStyle) {
        self.font = font
        self.identifier = identifier
        self.style = style
    }

    func loadFont(_ graphicsDevice: GraphicsDeviceContext) -> DKGame.Font? {
        if self.font == nil {
            //TODO: load font with identifier or URL
        }
        return self.font
    }

    func glyphData(forChar c: UnicodeScalar) -> GlyphData? {
        self.font?.glyphData(forChar: c)
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
        fatalError()
    }

    public static func system(_ style: Font.TextStyle, design: Font.Design = .default) -> Font {
        fatalError()
    }

    public static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        fatalError()
    }

    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        fatalError()
    }

    public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
        fatalError()
    }

    public static func custom(_ name: String, size: CGFloat) -> Font {
        fatalError()
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
    func load(_ graphicsDevice: GraphicsDeviceContext) -> DKGame.Font? {
        provider.loadFont(graphicsDevice)
    }

    func glyphData(forChar c: UnicodeScalar) -> GlyphData? {
        provider.glyphData(forChar: c)
    }
}
