//
//  File: GraphicsContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

public struct GraphicsContext {

    public struct BlendMode: RawRepresentable, Equatable, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        public static var normal            = BlendMode(rawValue: 0)
        public static var multiply          = BlendMode(rawValue: 1)
        public static var screen            = BlendMode(rawValue: 2)
        public static var overlay           = BlendMode(rawValue: 3)
        public static var darken            = BlendMode(rawValue: 4)
        public static var lighten           = BlendMode(rawValue: 5)
        public static var colorDodge        = BlendMode(rawValue: 6)
        public static var colorBurn         = BlendMode(rawValue: 7)
        public static var softLight         = BlendMode(rawValue: 8)
        public static var hardLight         = BlendMode(rawValue: 9)
        public static var difference        = BlendMode(rawValue: 10)
        public static var exclusion         = BlendMode(rawValue: 11)
        public static var hue               = BlendMode(rawValue: 12)
        public static var saturation        = BlendMode(rawValue: 13)
        public static var color             = BlendMode(rawValue: 14)
        public static var luminosity        = BlendMode(rawValue: 15)
        public static var clear             = BlendMode(rawValue: 16)
        public static var copy              = BlendMode(rawValue: 17)
        public static var sourceIn          = BlendMode(rawValue: 18)
        public static var sourceOut         = BlendMode(rawValue: 19)
        public static var sourceAtop        = BlendMode(rawValue: 20)
        public static var destinationOver   = BlendMode(rawValue: 21)
        public static var destinationIn     = BlendMode(rawValue: 22)
        public static var destinationOut    = BlendMode(rawValue: 23)
        public static var destinationAtop   = BlendMode(rawValue: 24)
        public static var xor               = BlendMode(rawValue: 25)
        public static var plusDarker        = BlendMode(rawValue: 26)
        public static var plusLighter       = BlendMode(rawValue: 27)
    }

    public var opacity: Double
    public var blendMode: BlendMode
    public var environment: EnvironmentValues
    public var transform: CGAffineTransform

    let viewTransform: CGAffineTransform
    let commandBuffer: CommandBuffer
    // render targets
    var backBuffer: Texture
    var stencilBuffer: Texture

    init(opacity: Double = 1.0,
         blendMode: BlendMode = .normal,
         environment: EnvironmentValues,
         transform: CGAffineTransform = .identity,
         viewOffset: CGPoint,
         viewSize: CGSize,
         viewScaleFactor: CGFloat,
         commandBuffer: CommandBuffer,
         backBuffer: Texture,
         stencilBuffer: Texture) {
        self.opacity = opacity
        self.blendMode = blendMode
        self.environment = environment
        self.transform = transform
        self.commandBuffer = commandBuffer
        self.backBuffer = backBuffer
        self.stencilBuffer = stencilBuffer

        let dim = { (tex: Texture) in (tex.width, tex.height, tex.depth) }
        assert(dim(backBuffer) == dim(stencilBuffer))

        let scale = CGSize.maximum(viewSize, CGSize(width: 1, height: 1))
        let offset = CGAffineTransform(translationX: viewOffset.x, y: viewOffset.y)
        let normalize = CGAffineTransform(scaleX: 1.0 / scale.width, y: 1.0 / scale.height)

        // transform to screen viewport space.
        let clipSpace = CGAffineTransform(scaleX: 2.0, y: -2.0)
            .concatenating(CGAffineTransform(translationX: -1.0, y: 1.0))

        self.viewTransform = CGAffineTransform.identity
            .concatenating(offset)
            .concatenating(normalize)
            .concatenating(clipSpace)
    }

    public mutating func scaleBy(x: CGFloat, y: CGFloat) {
        self.transform = self.transform.scaledBy(x: x, y: y)
    }

    public mutating func translateBy(x: CGFloat, y: CGFloat) {
        self.transform = self.transform.translatedBy(x: x, y: y)
    }

    public mutating func rotate(by angle: Angle) {
        self.transform = self.transform.rotated(by: angle.radians)
    }

    public mutating func concatenate(_ matrix: CGAffineTransform) {
        self.transform = self.transform.concatenating(matrix)
    }

    public struct ClipOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var inverse = ClipOptions(rawValue: 1)
    }

    public var clipBoundingRect: CGRect { .zero }

    public mutating func clip(to path: Path,
                              style: FillStyle = FillStyle(),
                              options: ClipOptions = ClipOptions()) {
        fatalError()
    }

    public mutating func clipToLayer(opacity: Double = 1,
                                     options: ClipOptions = ClipOptions(),
                                     content: (inout GraphicsContext) throws -> Void) rethrows {
        fatalError()
    }

    public struct Filter {
        public static func projectionTransform(_ matrix: ProjectionTransform) -> Filter {
            fatalError()
        }

        public static func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33),
                                  radius: CGFloat,
                                  x: CGFloat = 0,
                                  y: CGFloat = 0,
                                  blendMode: BlendMode = .normal,
                                  options: ShadowOptions = ShadowOptions()) -> Filter {
            fatalError()
        }

        public static func colorMultiply(_ color: Color) -> Filter {
            fatalError()
        }

        public static func colorMatrix(_ matrix: ColorMatrix) -> Filter {
            fatalError()
        }

        public static func hueRotation(_ angle: Angle) -> Filter {
            fatalError()
        }

        public static func saturation(_ amount: Double) -> Filter {
            fatalError()
        }

        public static func brightness(_ amount: Double) -> Filter {
            fatalError()
        }

        public static func contrast(_ amount: Double) -> Filter {
            fatalError()
        }

        public static func colorInvert(_ amount: Double = 1) -> Filter {
            fatalError()
        }

        public static func grayscale(_ amount: Double) -> Filter {
            fatalError()
        }

        public static var luminanceToAlpha: Filter { .init() }

        public static func blur(radius: CGFloat,
                                options: BlurOptions = BlurOptions()) -> Filter {
            fatalError()
        }

        public static func alphaThreshold(min: Double,
                                          max: Double = 1,
                                          color: Color = Color.black) -> Filter {
            fatalError()
        }
    }

    public struct ShadowOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var shadowAbove   = ShadowOptions(rawValue: 1)
        public static var shadowOnly    = ShadowOptions(rawValue: 2)
        public static var invertsAlpha  = ShadowOptions(rawValue: 4)
        public static var disablesGroup = ShadowOptions(rawValue: 8)
    }

    public struct BlurOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var opaque        = BlurOptions(rawValue: 1)
        public static var dithersResult = BlurOptions(rawValue: 2)
    }

    public struct FilterOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var linearColor = FilterOptions(rawValue: 1)
    }

    public mutating func addFilter(_ filter: Filter,
                                   options: FilterOptions = FilterOptions()) {
        fatalError()
    }

    public struct Shading {
        public static var backdrop: Shading     { fatalError() }
        public static var foreground: Shading   { fatalError() }

        public static func palette(_ array: [Shading]) -> Shading {
            fatalError()
        }
        public static func color(_ color: Color) -> Shading {
            return .init()
        }
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) -> Shading {
            return color(Color(colorSpace, red: red, green: green, blue: blue, opacity: opacity))
        }
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) -> Shading {
            return color(Color(colorSpace, white: white, opacity: opacity))
        }
        public static func style<S>(_ style: S) -> Shading where S: ShapeStyle {
            fatalError()
        }
        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions = GradientOptions()) -> Shading {
            fatalError()
        }
        public static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GradientOptions = GradientOptions()) -> Shading {
            fatalError()
        }
        public static func conicGradient(_ gradient: Gradient, center: CGPoint, angle: Angle = Angle(), options: GradientOptions = GradientOptions()) -> Shading {
            fatalError()
        }
        public static func tiledImage(_ image: Image, origin: CGPoint = .zero, sourceRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale: CGFloat = 1) -> Shading {
            fatalError()
        }
    }

    public struct GradientOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var `repeat`      = GradientOptions(rawValue: 1)
        public static var mirror        = GradientOptions(rawValue: 2)
        public static var linearColor   = GradientOptions(rawValue: 4)
    }

    public func resolve(_ shading: Shading) -> Shading {
        fatalError()
    }

    public struct ResolvedImage {
        public var size: CGSize { .zero }
        public let baseline: CGFloat
        public var shading: Shading?
    }

    public func resolve(_ image: Image) -> ResolvedImage {
        fatalError()
    }
    public func draw(_ image: ResolvedImage, in rect: CGRect, style: FillStyle = FillStyle()) {
        fatalError()
    }
    public func draw(_ image: ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) {
        fatalError()
    }
    public func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) {
        fatalError()
    }
    public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
        fatalError()
    }

    public struct ResolvedText {
        public var shading: Shading
        public func measure(in size: CGSize) -> CGSize { .zero }
        public func firstBaseline(in size: CGSize) -> CGFloat { .zero }
        public func lastBaseline(in size: CGSize) -> CGFloat { .zero }
    }

    public func resolve(_ text: Text) -> ResolvedText {
        fatalError()
    }
    public func draw(_ text: ResolvedText, in rect: CGRect) {
        fatalError()
    }
    public func draw(_ text: ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) {
        fatalError()
    }
    public func draw(_ text: Text, in rect: CGRect) {
        fatalError()
    }
    public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
        fatalError()
    }

    public struct ResolvedSymbol {
        public var size: CGSize { .zero }
    }

    public func resolveSymbol<ID>(id: ID) -> ResolvedSymbol? where ID: Hashable {
        fatalError()
    }

    public func draw(_ symbol: ResolvedSymbol, in rect: CGRect) {
        fatalError()
    }
    public func draw(_ symbol: ResolvedSymbol, at point: CGPoint, anchor: UnitPoint = .center) {
        fatalError()
    }
}
