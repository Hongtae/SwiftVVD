//
//  File: GraphicsContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct GraphicsContext {

    public struct BlendMode : RawRepresentable, Equatable, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        public static var normal: GraphicsContext.BlendMode             { .init(rawValue: 0) }
        public static var multiply: GraphicsContext.BlendMode           { .init(rawValue: 1) }
        public static var screen: GraphicsContext.BlendMode             { .init(rawValue: 2) }
        public static var overlay: GraphicsContext.BlendMode            { .init(rawValue: 3) }
        public static var darken: GraphicsContext.BlendMode             { .init(rawValue: 4) }
        public static var lighten: GraphicsContext.BlendMode            { .init(rawValue: 5) }
        public static var colorDodge: GraphicsContext.BlendMode         { .init(rawValue: 6) }
        public static var colorBurn: GraphicsContext.BlendMode          { .init(rawValue: 7) }
        public static var softLight: GraphicsContext.BlendMode          { .init(rawValue: 8) }
        public static var hardLight: GraphicsContext.BlendMode          { .init(rawValue: 9) }
        public static var difference: GraphicsContext.BlendMode         { .init(rawValue: 10) }
        public static var exclusion: GraphicsContext.BlendMode          { .init(rawValue: 11) }
        public static var hue: GraphicsContext.BlendMode                { .init(rawValue: 12) }
        public static var saturation: GraphicsContext.BlendMode         { .init(rawValue: 13) }
        public static var color: GraphicsContext.BlendMode              { .init(rawValue: 14) }
        public static var luminosity: GraphicsContext.BlendMode         { .init(rawValue: 15) }
        public static var clear: GraphicsContext.BlendMode              { .init(rawValue: 16) }
        public static var copy: GraphicsContext.BlendMode               { .init(rawValue: 17) }
        public static var sourceIn: GraphicsContext.BlendMode           { .init(rawValue: 18) }
        public static var sourceOut: GraphicsContext.BlendMode          { .init(rawValue: 19) }
        public static var sourceAtop: GraphicsContext.BlendMode         { .init(rawValue: 20) }
        public static var destinationOver: GraphicsContext.BlendMode    { .init(rawValue: 21) }
        public static var destinationIn: GraphicsContext.BlendMode      { .init(rawValue: 22) }
        public static var destinationOut: GraphicsContext.BlendMode     { .init(rawValue: 23) }
        public static var destinationAtop: GraphicsContext.BlendMode    { .init(rawValue: 24) }
        public static var xor: GraphicsContext.BlendMode                { .init(rawValue: 25) }
        public static var plusDarker: GraphicsContext.BlendMode         { .init(rawValue: 26) }
        public static var plusLighter: GraphicsContext.BlendMode        { .init(rawValue: 27) }

        public typealias RawValue = Int32
    }

    public var opacity: Double
    public var blendMode: GraphicsContext.BlendMode
    public var environment: EnvironmentValues { EnvironmentValues() }

    public var transform: CGAffineTransform

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

    public struct ClipOptions : OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var inverse: GraphicsContext.ClipOptions { .init(rawValue: 1) }

        public typealias ArrayLiteralElement = GraphicsContext.ClipOptions
        public typealias Element = GraphicsContext.ClipOptions
        public typealias RawValue = UInt32
    }

    public var clipBoundingRect: CGRect { .zero }

    public mutating func clip(to path: Path,
                              style: FillStyle = FillStyle(),
                              options: GraphicsContext.ClipOptions = ClipOptions()) {
        fatalError()
    }

    public mutating func clipToLayer(opacity: Double = 1,
                                     options: GraphicsContext.ClipOptions = ClipOptions(),
                                     content: (inout GraphicsContext) throws -> Void) rethrows {
        fatalError()
    }

    public struct Filter {
        public static func projectionTransform(_ matrix: ProjectionTransform) -> GraphicsContext.Filter {
            fatalError()
        }

        public static func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33),
                                  radius: CGFloat,
                                  x: CGFloat = 0,
                                  y: CGFloat = 0,
                                  blendMode: GraphicsContext.BlendMode = .normal,
                                  options: GraphicsContext.ShadowOptions = ShadowOptions()) -> GraphicsContext.Filter {
            fatalError()
        }

        public static func colorMultiply(_ color: Color) -> GraphicsContext.Filter {
            fatalError()
        }

        public static func colorMatrix(_ matrix: ColorMatrix) -> GraphicsContext.Filter {
            fatalError()
        }

        public static func hueRotation(_ angle: Angle) -> GraphicsContext.Filter {
            fatalError()
        }

        public static func saturation(_ amount: Double) -> GraphicsContext.Filter {
            fatalError()
        }

        public static func brightness(_ amount: Double) -> GraphicsContext.Filter {
            fatalError()
        }

        public static func contrast(_ amount: Double) -> GraphicsContext.Filter {
            fatalError()
        }

        public static func colorInvert(_ amount: Double = 1) -> GraphicsContext.Filter {
            fatalError()
        }

        public static func grayscale(_ amount: Double) -> GraphicsContext.Filter {
            fatalError()
        }

        public static var luminanceToAlpha: GraphicsContext.Filter { .init() }

        public static func blur(radius: CGFloat,
                                options: GraphicsContext.BlurOptions = BlurOptions()) -> GraphicsContext.Filter {
            fatalError()
        }

        public static func alphaThreshold(min: Double,
                                          max: Double = 1,
                                          color: Color = Color.black) -> GraphicsContext.Filter {
            fatalError()
        }
    }

    public struct ShadowOptions : OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var shadowAbove: GraphicsContext.ShadowOptions    { .init(rawValue: 1) }
        public static var shadowOnly: GraphicsContext.ShadowOptions     { .init(rawValue: 2) }
        public static var invertsAlpha: GraphicsContext.ShadowOptions   { .init(rawValue: 4) }
        public static var disablesGroup: GraphicsContext.ShadowOptions  { .init(rawValue: 8) }

        public typealias ArrayLiteralElement = GraphicsContext.ShadowOptions
        public typealias Element = GraphicsContext.ShadowOptions
        public typealias RawValue = UInt32
    }

    public struct BlurOptions : OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var opaque: GraphicsContext.BlurOptions           { .init(rawValue: 1) }
        public static var dithersResult: GraphicsContext.BlurOptions    { .init(rawValue: 2) }

        public typealias ArrayLiteralElement = GraphicsContext.BlurOptions
        public typealias Element = GraphicsContext.BlurOptions
        public typealias RawValue = UInt32
    }

    public struct FilterOptions : OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var linearColor: GraphicsContext.FilterOptions { .init(rawValue: 1) }

        public typealias ArrayLiteralElement = GraphicsContext.FilterOptions
        public typealias Element = GraphicsContext.FilterOptions
        public typealias RawValue = UInt32
    }

    public mutating func addFilter(_ filter: GraphicsContext.Filter,
                                   options: GraphicsContext.FilterOptions = FilterOptions()) {
        fatalError()
    }

    public struct Shading {
        public static var backdrop: GraphicsContext.Shading     { fatalError() }
        public static var foreground: GraphicsContext.Shading   { fatalError() }

        public static func palette(_ array: [GraphicsContext.Shading]) -> GraphicsContext.Shading {
            fatalError()
        }
        public static func color(_ color: Color) -> GraphicsContext.Shading {
            fatalError()
        }
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) -> GraphicsContext.Shading {
            fatalError()
        }
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) -> GraphicsContext.Shading {
            fatalError()
        }
        public static func style<S>(_ style: S) -> GraphicsContext.Shading where S : ShapeStyle {
            fatalError()
        }
        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading {
            fatalError()
        }
        public static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading {
            fatalError()
        }
        public static func conicGradient(_ gradient: Gradient, center: CGPoint, angle: Angle = Angle(), options: GraphicsContext.GradientOptions = GradientOptions()) -> GraphicsContext.Shading {
            fatalError()
        }
        public static func tiledImage(_ image: Image, origin: CGPoint = .zero, sourceRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale: CGFloat = 1) -> GraphicsContext.Shading {
            fatalError()
        }
    }

    public struct GradientOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var `repeat`: GraphicsContext.GradientOptions     { .init(rawValue: 1) }
        public static var mirror: GraphicsContext.GradientOptions       { .init(rawValue: 2) }
        public static var linearColor: GraphicsContext.GradientOptions  { .init(rawValue: 4) }

        public typealias ArrayLiteralElement = GraphicsContext.GradientOptions
        public typealias Element = GraphicsContext.GradientOptions
        public typealias RawValue = UInt32
    }

    public func resolve(_ shading: GraphicsContext.Shading) -> GraphicsContext.Shading {
        fatalError()
    }
    public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        fatalError()
    }
    public func fill(_ path: Path, with shading: GraphicsContext.Shading, style: FillStyle = FillStyle()) {
        fatalError()
    }
    public func stroke(_ path: Path, with shading: GraphicsContext.Shading, style: StrokeStyle) {
        fatalError()
    }
    public func stroke(_ path: Path, with shading: GraphicsContext.Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }

    public struct ResolvedImage {
        public var size: CGSize { fatalError() }
        public let baseline: CGFloat
        public var shading: GraphicsContext.Shading?
    }

    public func resolve(_ image: Image) -> GraphicsContext.ResolvedImage {
        fatalError()
    }
    public func draw(_ image: GraphicsContext.ResolvedImage, in rect: CGRect, style: FillStyle = FillStyle()) {
        fatalError()
    }
    public func draw(_ image: GraphicsContext.ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) {
        fatalError()
    }
    public func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) {
        fatalError()
    }
    public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
        fatalError()
    }

    public struct ResolvedText {
        public var shading: GraphicsContext.Shading
        public func measure(in size: CGSize) -> CGSize { .zero }
        public func firstBaseline(in size: CGSize) -> CGFloat { .zero }
        public func lastBaseline(in size: CGSize) -> CGFloat { .zero }
    }

    public func resolve(_ text: Text) -> GraphicsContext.ResolvedText {
        fatalError()
    }
    public func draw(_ text: GraphicsContext.ResolvedText, in rect: CGRect) {
        fatalError()
    }
    public func draw(_ text: GraphicsContext.ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) {
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

    public func resolveSymbol<ID>(id: ID) -> GraphicsContext.ResolvedSymbol? where ID : Hashable {
        fatalError()
    }

    public func draw(_ symbol: GraphicsContext.ResolvedSymbol, in rect: CGRect) {
        fatalError()
    }
    public func draw(_ symbol: GraphicsContext.ResolvedSymbol, at point: CGPoint, anchor: UnitPoint = .center) {
        fatalError()
    }
}
