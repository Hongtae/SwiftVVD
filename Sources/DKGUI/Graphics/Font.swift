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
                      subdirectory: "Fonts")
}

struct FaceStyle: Hashable {
    var pointSize: CGFloat
    var outilne: CGFloat
    var embolden: CGFloat
    var dpiScale: CGFloat
}

typealias GlyphData = DKGame.Font.GlyphData

extension DKGame.Font {
    func setStyle(_ style: FaceStyle) {
        let dpiX = CGFloat(DKGame.Font.defaultDPI.x) * style.dpiScale
        let dpiY = CGFloat(DKGame.Font.defaultDPI.y) * style.dpiScale
        self.setStyle(pointSize: style.pointSize,
                      dpi: (UInt32(dpiX), UInt32(dpiY)),
                      embolden: 0,
                      outline: 0,
                      enableKerning: true,
                      forceBitmap: true)
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

class AnyFontBox {
    var font: DKGame.Font?
    var fallbackFonts: [DKGame.Font] = []

    let identifier: String
    let style: FaceStyle

    init(identifier: String, style: FaceStyle) {
        self.identifier = identifier
        self.style = style
    }

    func loadFont(_ context: SharedContext) {
        if self.font == nil {
            if let url = context.fontIdentifierURLs[self.identifier] ?? defaultFontURL {
                var data = context.appContext.resourceData(forURL: url)
                if data == nil {
                    do {
                        print("Loading font resource: \(url)")
                        let d = try Data(contentsOf: url, options: [])
                        data = RawBufferStorage(d)
                    } catch {
                        print("Error on loading data: \(error)")
                    }
                }
                if let data, let device = context.appContext.graphicsDeviceContext {
                    self.font = DKGame.Font(deviceContext: device, data: data)
                }
            } else {
                fatalError("font URL cannot be nil")
            }
        }
    }

    func glyphData(for c: UnicodeScalar) -> GlyphData? {
        if let font, font.hasGlyph(for: c) == false {
            for ft in self.fallbackFonts {
                if ft.hasGlyph(for: c) {
                    return ft.glyphData(for: c)
                }
            }
        }
        return font?.glyphData(for: c)
    }

    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        if let font {
            unowned var font1 = font
            unowned var font2 = font

            if font1.hasGlyph(for: left) == false {
                font1 = self.fallbackFonts.first {
                    $0.hasGlyph(for: left)
                } ?? font1
            }
            if font2.hasGlyph(for: right) == false {
                font2 = self.fallbackFonts.first {
                    $0.hasGlyph(for: right)
                } ?? font2
            }
            if font1 === font2 {
                return font1.kernAdvance(left: left, right: right)
            }
        }
        return .zero
    }

    func lineWidth(of text: String) -> CGFloat {
        var length: CGFloat = 0.0
        var c1 = UnicodeScalar(UInt8(0))
        for c2 in text.unicodeScalars {
            if let glyph = self.glyphData(for: c2) {
                length += glyph.advance.width
                length += self.kernAdvance(left: c1, right: c2).x
            }
            c1 = c2
        }
        return length
    }

    var lineHeight: CGFloat {
        font?.lineHeight() ?? 0
    }

    public func bounds(of text: String) -> CGRect {
        var bboxMin: CGPoint = .zero
        var bboxMax: CGPoint = .zero
        var offset: CGFloat = 0.0
        var c1 = UnicodeScalar(UInt8(0))
        for c2 in text.unicodeScalars {
            if let glyph = self.glyphData(for: c2) {
                if offset > 0.0 {
                    let posMin = CGPoint(x: offset + glyph.position.x,
                                         y: glyph.position.y - glyph.ascender)
                    let posMax = CGPoint(x: posMin.x + glyph.frame.width,
                                         y: posMin.y + glyph.frame.height - glyph.ascender)

                    bboxMin = .minimum(bboxMin, posMin)
                    bboxMax = .maximum(bboxMax, posMax)
                } else {
                    bboxMin = glyph.position
                    bboxMax.x = bboxMin.x + glyph.frame.width
                    bboxMax.y = bboxMin.y + glyph.frame.height - glyph.ascender
                }

                offset += glyph.advance.width + self.kernAdvance(left: c1, right: c2).x
            }
            c1 = c2
        }
        let size = CGSize(width: ceil(bboxMax.x - bboxMin.x), height: ceil(bboxMax.y - bboxMin.y))
        return CGRect(origin: bboxMin, size: size)
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
    func load(_ context: SharedContext) {
        provider.loadFont(context)
    }

    func glyphData(for c: UnicodeScalar) -> GlyphData? {
        provider.glyphData(for: c)
    }

    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        provider.kernAdvance(left: left, right: right)
    }

    var lineHeight: CGFloat {
        provider.lineHeight
    }
}
