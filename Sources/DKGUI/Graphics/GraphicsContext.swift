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
    public internal(set) var environment: EnvironmentValues
    public var transform: CGAffineTransform

    // MARK: -
    var viewTransform: CGAffineTransform
    var contentOffset: CGPoint {
        didSet {
            let origin = self.contentOffset
            let scale = self.contentScale
            let offset = CGAffineTransform(translationX: origin.x, y: origin.y)
            let normalize = CGAffineTransform(scaleX: 1.0 / scale.width, y: 1.0 / scale.height)

            // transform to screen viewport space.
            let clipSpace = CGAffineTransform(scaleX: 2.0, y: -2.0)
                .concatenating(CGAffineTransform(translationX: -1.0, y: 1.0))

            self.viewTransform = CGAffineTransform.identity
                .concatenating(offset)
                .concatenating(normalize)
                .concatenating(clipSpace)
        }
    }
    let contentScale: CGSize
    let commandBuffer: CommandBuffer
    let backBuffer: Texture
    let stencilBuffer: Texture
    var maskTexture: Texture

    var resolution: CGSize {
        CGSize(width: self.backBuffer.width, height: self.backBuffer.height)
    }

    let sharedContext: SharedContext

    init?(sharedContext: SharedContext,
          environment: EnvironmentValues,
          contentOffset: CGPoint,
          contentScale: CGSize,
          transform: CGAffineTransform = .identity,
          resolution: CGSize,
          commandBuffer: CommandBuffer,
          backBuffer: Texture? = nil,
          stencilBuffer: Texture? = nil) {
        self.sharedContext = sharedContext
        self.opacity = 1
        self.blendMode = .normal
        self.transform = transform
        self.environment = environment
        self.commandBuffer = commandBuffer
        self.contentScale = .maximum(contentScale, CGSize(width: 1, height: 1))

        let device = commandBuffer.device

        let width = Int(resolution.width.rounded())
        let height = Int(resolution.height.rounded())
        assert(width > 0 && height > 0)

        if let backBuffer = backBuffer {
            assert(backBuffer.dimensions == (width, height, 1))
            self.backBuffer = backBuffer
        } else {

            guard let backBuffer = device.makeTexture(
                descriptor: TextureDescriptor(textureType: .type2D,
                                              pixelFormat: .rgba8Unorm,
                                              width: width,
                                              height: height,
                                              usage: [.renderTarget, .sampled])) else {
                Log.err("GraphicsContext error: makeTexture failed.")
                return nil
            }
            if let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: RenderPassDescriptor(colorAttachments: [
                    RenderPassColorAttachmentDescriptor(renderTarget: backBuffer,
                                                        loadAction: .clear,
                                                        storeAction: .store)])) {
                encoder.endEncoding()
            } else {
                Log.err("GraphicsContext warning: makeRenderCommandEncoder failed.")
            }
            self.backBuffer = backBuffer
        }

        if let stencilBuffer {
            assert(stencilBuffer.dimensions == (width, height, 1))
            self.stencilBuffer = stencilBuffer
        } else {
            let width = self.backBuffer.width
            let height = self.backBuffer.height
            if let stencilBuffer = device.makeTexture(
                descriptor: TextureDescriptor(textureType: .type2D,
                                              pixelFormat: .stencil8,
                                              width: width,
                                              height: height,
                                              usage: [.renderTarget])) {
                self.stencilBuffer = stencilBuffer
            } else {
                Log.err("GraphicsContext error: makeTexture failed.")
                return nil
            }
        }
        assert(self.backBuffer.dimensions == self.stencilBuffer.dimensions)

        let queue = commandBuffer.commandQueue
        guard let maskTexture = GraphicsPipelineStates.sharedInstance(
            commandQueue: queue)?.defaultMaskTexture
        else {
            Log.err("GraphicsPipelineStates error")
            return nil
        }
        self.maskTexture = maskTexture

        self.contentOffset = .zero
        self.viewTransform = .identity

        defer {
            // contentOffset.didSet will be called.
            self.contentOffset = contentOffset
        }
    }

    // MARK: - Context Layer
    func makeLayerContext() -> Self? {
        return GraphicsContext(sharedContext: self.sharedContext,
                               environment: self.environment,
                               contentOffset: self.contentOffset,
                               contentScale: self.contentScale,
                               transform: self.transform,
                               resolution: self.resolution,
                               commandBuffer: self.commandBuffer,
                               backBuffer: nil, /* to make new buffer */
                               stencilBuffer: self.stencilBuffer)
    }

    func makeRegionLayerContext(_ frame: CGRect) -> Self? {
        let frame = frame.standardized

        let resolution = self.resolution
        let width = resolution.width * (frame.width / self.contentScale.width)
        let height = resolution.height * (frame.height / self.contentScale.height)

        var stencil: Texture? = nil
        if width.rounded() == resolution.width.rounded() &&
           height.rounded() == resolution.height.rounded() {
            stencil = self.stencilBuffer
        }
        return GraphicsContext(sharedContext: self.sharedContext,
                               environment: self.environment,
                               contentOffset: .zero,
                               contentScale: frame.size,
                               transform: self.transform,
                               resolution: CGSize(width: width, height: height),
                               commandBuffer: self.commandBuffer,
                               backBuffer: nil,
                               stencilBuffer: stencil)
    }

    public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        if var context = self.makeLayerContext() {
            do {
                try content(&context)
                let offset = -context.contentOffset
                let scale = context.contentScale
                let texture = context.backBuffer
                self._draw(texture: texture,
                           in: CGRect(origin: offset, size: scale),
                           transform: .identity,
                           textureFrame: CGRect(x: 0, y: 0,
                                                width: texture.width,
                                                height: texture.height),
                           textureTransform: .identity,
                           blendMode: context.blendMode,
                           color: .white)
            } catch {
                Log.err("GraphicsContext error: \(error)")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    // MARK: - Transformation Matrix
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

    // MARK: - Clipping
    public struct ClipOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var inverse = ClipOptions(rawValue: 1)
    }

    public var clipBoundingRect: CGRect = .zero

    public mutating func clip(to path: Path,
                              style: FillStyle = FillStyle(),
                              options: ClipOptions = ClipOptions()) {
        let resolution = self.resolution
        let width = Int(resolution.width.rounded())
        let height = Int(resolution.height.rounded())
        let device = self.commandBuffer.device
        if let maskTexture = device.makeTexture(
            descriptor: TextureDescriptor(textureType: .type2D,
                                          pixelFormat: .r8Unorm,
                                          width: width,
                                          height: height,
                                          usage: [.renderTarget, .sampled])) {
            if let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: RenderPassDescriptor(colorAttachments: [
                    RenderPassColorAttachmentDescriptor(renderTarget: backBuffer,
                                                        loadAction: .clear,
                                                        storeAction: .store,
                                                        clearColor: .white)])) {
                encoder.endEncoding()
            } else {
                Log.err("GraphicsContext warning: makeRenderCommandEncoder failed.")
            }
            // Create a new context to draw paths to a new mask texture
            let drawn = self._drawPathFillWithStencil(path, backBuffer: maskTexture) { encoder in
                let makeVertex = { x, y in
                    _Vertex(position: Vector2(x, y).float2,
                            texcoord: Vector2.zero.float2,
                            color: DKGame.Color.white.float4)
                }
                let vertices: [_Vertex] = [
                    makeVertex(-1, -1), makeVertex(-1, 1), makeVertex(1, -1),
                    makeVertex(1, -1), makeVertex(-1, 1), makeVertex(1, 1)
                ]

                let stencil: _Stencil
                if options.contains(.inverse) {
                    stencil = style.isEOFilled ? .testOdd : .testZero
                } else {
                    stencil = style.isEOFilled ? .testEven : .testNonZero
                }
                self._encodeDrawCommand(shader: .vertexColor,
                                        stencil: stencil,
                                        vertices: vertices,
                                        indices: nil,
                                        texture: nil,
                                        blendState: .defaultAlpha,
                                        pushConstantData: nil,
                                        encoder: encoder)
                return true
            }
            if drawn {
                self.clipBoundingRect = self.clipBoundingRect.union(path.boundingBoxOfPath)
                self.maskTexture = maskTexture
            }
        } else {
            Log.err("GraphicsContext error: makeTexture failed.")
        }
    }

    public mutating func clipToLayer(opacity: Double = 1,
                                     options: ClipOptions = ClipOptions(),
                                     content: (inout GraphicsContext) throws -> Void) rethrows {
        if var context = self.makeLayerContext() {
            do {
                try content(&context)
                if let maskTexture = self._resolveMaskTexture(
                    self.maskTexture,
                    context.backBuffer,
                    opacity: opacity,
                    inverse: options.contains(.inverse)) {
                    self.maskTexture = maskTexture
                } else {
                    Log.err("GraphicsContext error: unable to resolve mask image.")
                }
            } catch {
                Log.err("GraphicsContext error: \(error)")
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    // MARK: - Filter Rendering
    public struct Filter {
        enum FilterStyle {
            case transformMatrix(matrix: ProjectionTransform)
            case colorMatrix(matrix: ColorMatrix)
            case blur(radius: CGFloat, options: BlurOptions)
            case shadow(color: Color, radius: CGFloat, offset: CGPoint, blendMode: BlendMode, options: ShadowOptions)
        }
        let style: FilterStyle

        public static func projectionTransform(_ matrix: ProjectionTransform) -> Filter {
            Filter(style: .transformMatrix(matrix: matrix))
        }

        public static func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33),
                                  radius: CGFloat,
                                  x: CGFloat = 0,
                                  y: CGFloat = 0,
                                  blendMode: BlendMode = .normal,
                                  options: ShadowOptions = ShadowOptions()) -> Filter {
            Filter(style: .shadow(color: color,
                                  radius: radius,
                                  offset: CGPoint(x: x, y: y),
                                  blendMode: blendMode,
                                  options: options))
        }

        public static func colorMultiply(_ color: Color) -> Filter {
            let cc = color.dkColor
            var cm = ColorMatrix.identity
            cm.r1 = Float(cc.r)
            cm.g2 = Float(cc.g)
            cm.b3 = Float(cc.b)
            cm.a4 = Float(cc.a)
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func colorMatrix(_ matrix: ColorMatrix) -> Filter {
            Filter(style: .colorMatrix(matrix: matrix))
        }

        public static func hueRotation(_ angle: Angle) -> Filter {
            let c = Float(cos(angle.radians))
            let s = Float(sin(angle.radians))
            var cm = ColorMatrix.identity

            cm.r1 = 0.213 + c * 0.787 - s * 0.213
            cm.r2 = 0.715 - c * 0.715 - s * 0.715
            cm.r3 = 0.072 - c * 0.072 + s * 0.928

            cm.g1 = 0.213 - c * 0.213 + s * 0.143
            cm.g2 = 0.715 + c * 0.285 + s * 0.140
            cm.g3 = 0.072 - c * 0.072 - s * 0.283

            cm.b1 = 0.213 - c * 0.213 - s * 0.787
            cm.b2 = 0.715 - c * 0.715 + s * 0.715
            cm.b3 = 0.072 + c * 0.928 + s * 0.072

            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func saturation(_ amount: Double) -> Filter {
            let s = Float(amount)
            let sr = (1 - s) * 0.213
            let sg = (1 - s) * 0.715
            let sb = (1 - s) * 0.072
            var cm = ColorMatrix.identity
            cm.r1 = sr + s
            cm.r2 = sg
            cm.r3 = sb
            cm.g1 = sr
            cm.g2 = sg + s
            cm.g3 = sb
            cm.b1 = sr
            cm.b2 = sg
            cm.b3 = sb + s
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func brightness(_ amount: Double) -> Filter {
            let b = Float(amount)
            var cm = ColorMatrix.identity
            cm.r5 = b
            cm.g5 = b
            cm.b5 = b
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func contrast(_ amount: Double) -> Filter {
            let c = Float(amount)
            let t = (1 - c) * 0.5
            var cm = ColorMatrix.identity
            cm.r1 = c
            cm.g2 = c
            cm.b3 = c
            cm.r5 = t
            cm.g5 = t
            cm.b5 = t
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func colorInvert(_ amount: Double = 1) -> Filter {
            let c = Float(amount)
            let r = 1.0 - c * 2.0
            var cm = ColorMatrix.identity
            cm.r1 = r
            cm.g2 = r
            cm.b2 = r
            cm.r5 = c
            cm.g5 = c
            cm.b5 = c
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func grayscale(_ amount: Double) -> Filter {
            let a = Float(1 - amount)
            var cm = ColorMatrix.identity
            cm.r1 = 0.213 + 0.787 * a
            cm.r2 = 0.715 - 0.715 * a
            cm.r3 = 0.072 - 0.072 * a
            cm.g1 = 0.213 - 0.213 * a
            cm.g2 = 0.715 + 0.285 * a
            cm.g3 = 0.072 - 0.072 * a
            cm.b1 = 0.213 - 0.213 * a
            cm.b2 = 0.715 - 0.715 * a
            cm.b3 = 0.072 + 0.928 * a
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static var luminanceToAlpha: Filter {
            var cm = ColorMatrix.zero
            cm.a1 = 0.2126
            cm.a2 = 0.7152
            cm.a3 = 0.0722
            return Filter(style: .colorMatrix(matrix: cm))
        }

        public static func blur(radius: CGFloat,
                                options: BlurOptions = BlurOptions()) -> Filter {
            Filter(style: .blur(radius: radius, options: options))
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

    var unfilteredBackBuffer: Texture? = nil
    var filters: [(Filter, FilterOptions)] = []

    public mutating func addFilter(_ filter: Filter,
                                   options: FilterOptions = FilterOptions()) {
        filters.append((filter, options))
        if unfilteredBackBuffer == nil {
            // If any filters are present, they must be rendered in two passes.

            // TODO: create new render-target! (rgba8)
            fatalError("Not implemented yet")
        }
    }

    // MARK: - Shading Options
    public struct Shading {
        enum Property {
            case color(color: Color)
            case style(style: ShapeStyle)
            case linearGradient(gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions)
            case radialGradient(gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GradientOptions)
            case conicGradient(gradient: Gradient, center: CGPoint, angle: Angle, options: GradientOptions)
            case tiledImage(image: Image, origin: CGPoint, sourceRect: CGRect, scale: CGFloat)
        }
        let properties: [Property]

        init(property: Property) {
            self.properties = [property]
        }
        init(palette: [Shading]) {
            self.properties = palette.flatMap { $0.properties }
        }

        public static var backdrop: Shading     { fatalError() }
        public static var foreground: Shading   { fatalError() }

        public static func palette(_ array: [Shading]) -> Shading {
            Shading(palette: array)
        }
        public static func color(_ color: Color) -> Shading {
            Shading(property: .color(color: color))
        }
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) -> Shading {
            color(Color(colorSpace, red: red, green: green, blue: blue, opacity: opacity))
        }
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) -> Shading {
            color(Color(colorSpace, white: white, opacity: opacity))
        }
        public static func style<S>(_ style: S) -> Shading where S: ShapeStyle {
            Shading(property: .style(style: style))
        }
        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions = GradientOptions()) -> Shading {
            Shading(property: .linearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint, options: options))
        }
        public static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GradientOptions = GradientOptions()) -> Shading {
            Shading(property: .radialGradient(gradient: gradient, center: center, startRadius: startRadius, endRadius: endRadius, options: options))
        }
        public static func conicGradient(_ gradient: Gradient, center: CGPoint, angle: Angle = Angle(), options: GradientOptions = GradientOptions()) -> Shading {
            Shading(property: .conicGradient(gradient: gradient, center: center, angle: angle, options: options))
        }
        public static func tiledImage(_ image: Image, origin: CGPoint = .zero, sourceRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale: CGFloat = 1) -> Shading {
            Shading(property: .tiledImage(image: image, origin: origin, sourceRect: sourceRect, scale: scale))
        }
    }

    public func resolve(_ shading: Shading) -> Shading {
        shading
    }

    public struct GradientOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var `repeat`      = GradientOptions(rawValue: 1)
        public static var mirror        = GradientOptions(rawValue: 2)
        public static var linearColor   = GradientOptions(rawValue: 4)
    }

    // MARK: - Path Rendering
    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        if shading.properties.isEmpty { return }
        self._drawPathFillWithStencil(path, backBuffer: self.backBuffer) {
            encoder in
            let stencil: _Stencil = style.isEOFilled ? .testEven : .testNonZero
            self._encodeFillCommand(with: shading,
                                    stencil: stencil,
                                    encoder: encoder)
            return true
        }
    }

    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        if shading.properties.isEmpty { return }
        self._drawPathStrokeWithStencil(path,
                                        style: style,
                                        backBuffer: self.backBuffer) {
            encoder in
            self._encodeFillCommand(with: shading,
                                    stencil: .testNonZero,
                                    encoder: encoder)
            return true
        }
    }

    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }

    // MARK: - Image Rendering
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
        draw(resolve(image), in: rect, style: style)
    }
    public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(image), at: point, anchor: anchor)
    }

    // MARK: - Text Rendering
    public struct ResolvedText {
        public func measure(in size: CGSize) -> CGSize {
            lines.reduce(CGSize.zero) { size, line in
                CGSize(width: max(size.width, line.size.width),
                       height: size.height + line.lineHeight)
            }
        }
        public func firstBaseline(in size: CGSize) -> CGFloat {
            lines.first?.baseline ?? 0
        }
        public func lastBaseline(in size: CGSize) -> CGFloat {
            var height: CGFloat = 0
            for line in lines[0..<(lines.count - 1)] {
                height = height + line.lineHeight
            }
            return height + (lines.last?.baseline ?? 0)
        }
        public var shading: Shading

        struct GlyphVertex {
            let pos: Vector2
            let tex: Float2
        }
        struct GlyphGroup {
            let texture: Texture
            let vertices: [GlyphVertex] // relative position per line (origin: 0,0)
        }

        struct Line {
            let size: CGSize
            let baseline: CGFloat
            let lineHeight: CGFloat
        }
        let lines: [Line]
        let glyphGroups: [GlyphGroup]
    }

    public func resolve(_ text: Text) -> ResolvedText {
        var font = text.font
        if font == nil {
            font = self.environment.font
        }
        var lines: [ResolvedText.Line] = []
        typealias GlyphGroup = ResolvedText.GlyphGroup
        var glyphGroups: [GlyphGroup] = []

        if let font {
            font.load(self.sharedContext)

            typealias GlyphVertex = ResolvedText.GlyphVertex
            struct Quad {
                let lt: GlyphVertex
                let rt: GlyphVertex
                let lb: GlyphVertex
                let rb: GlyphVertex
                let texture: Texture
            }
            let str = text.storage.unicodeScalars
            var quads: [Quad] = []
            quads.reserveCapacity(str.count)

            var bboxMin = Vector2(0, 0)
            var bboxMax = Vector2(0, 0)
            var offset: CGFloat = 0.0        // accumulated text width (pixel)

            var c1: UnicodeScalar = UnicodeScalar(0)
            for char in str {
                let c2 = char as! UnicodeScalar

                // get glyph info from font object
                if let glyph = font.glyphData(for: c2) {
                    let posMin = Vector2(Scalar(glyph.position.x + offset),
                                         Scalar(glyph.position.y - glyph.ascender))
                    let posMax = Vector2(Scalar(glyph.frame.width),
                                         Scalar(glyph.frame.height)) + posMin

                    if offset > 0.0 {
                        bboxMin = .minimum(bboxMin, posMin)
                        bboxMax = .maximum(bboxMax, posMax)
                    } else {
                        bboxMin = posMin
                        bboxMax = posMax
                    }
                    if let texture = glyph.texture {
                        let textureWidth = texture.width
                        let textureHeight = texture.height
                        if textureWidth > 0 && textureHeight > 0 {
                            let invW = 1.0 / Float(textureWidth)
                            let invH = 1.0 / Float(textureHeight)

                            let uvMinX = Float(glyph.frame.minX) * invW
                            let uvMinY = Float(glyph.frame.minY) * invH
                            let uvMaxX = Float(glyph.frame.maxX) * invW
                            let uvMaxY = Float(glyph.frame.maxY) * invH

                            let q = Quad(
                                lt: GlyphVertex(
                                    pos: Vector2(posMin.x, posMin.y),
                                    tex: (uvMinX, uvMinY)),
                                rt: GlyphVertex(
                                    pos: Vector2(posMax.x, posMin.y),
                                    tex: (uvMaxX, uvMinY)),
                                lb: GlyphVertex(
                                    pos: Vector2(posMin.x, posMax.y),
                                    tex: (uvMinX, uvMaxY)),
                                rb: GlyphVertex(
                                    pos: Vector2(posMax.x, posMax.y),
                                    tex: (uvMaxX, uvMaxY)),
                                texture: texture)
                            quads.append(q)
                        }
                    }
                    offset += glyph.advance.width + font.kernAdvance(left: c1, right: c2).x
                }
                c1 = c2
            }
            if quads.isEmpty == false {
                let width = bboxMax.x - bboxMin.x
                let height = bboxMax.y - bboxMin.y
                let ascender = 0 - bboxMin.y
                let offset = Vector2(0, ascender)

                if width > .ulpOfOne, height > .ulpOfOne {
                    // sort by texture order
                    quads.sort {
                        // unsafeBitCast($0.texture, to: UInt.self) > unsafeBitCast($1.texture, to: UInt.self)
                        ObjectIdentifier($0.texture) > ObjectIdentifier($1.texture)
                    }

                    var size: CGSize = .zero
                    var baseline: CGFloat = .zero
                    var lineHeight: CGFloat = .zero

                    var glyphTexture: Texture? = nil
                    var vertices: [GlyphVertex] = []
                    vertices.reserveCapacity(quads.count * 6)
                    for q in quads {
                        if q.texture !== glyphTexture {
                            if vertices.isEmpty == false {
                                glyphGroups.append(GlyphGroup(texture: q.texture,
                                                              vertices: vertices))
                            }
                            vertices.removeAll(keepingCapacity: true)
                            glyphTexture = q.texture
                        }
                        vertices.append(contentsOf: [q.lb, q.lt, q.rb].map {
                                GlyphVertex(pos: $0.pos + offset, tex: $0.tex)
                            })
                        vertices.append(contentsOf: [q.rb, q.lt, q.rt].map {
                                GlyphVertex(pos: $0.pos + offset, tex: $0.tex)
                            })
                    }
                    if let glyphTexture, vertices.isEmpty == false {
                        glyphGroups.append(GlyphGroup(texture: glyphTexture,
                                                      vertices: vertices))
                    }
                    size = CGSize(width: width, height: height)
                    baseline = ascender
                    lineHeight = font.lineHeight

                    lines.append(ResolvedText.Line(size: size,
                                                   baseline: baseline,
                                                   lineHeight: lineHeight))
                }
            }
        }
        return ResolvedText(shading: .color(.black), lines: lines, glyphGroups: glyphGroups)
    }

    public func draw(_ text: ResolvedText, in rect: CGRect) {
        fatalError()
    }
    public func draw(_ text: ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) {
        guard let shading = text.shading.properties.first else {
            fatalError()
        }
        if text.glyphGroups.isEmpty {
            return
        }

        if case let .color(color) = shading {
            let c = color.dkColor.float4
            let scale = self.contentScale / self.resolution
            let transform2 = CGAffineTransform(scaleX: scale.width, y: scale.height)
                .concatenating(CGAffineTransform(translationX: point.x, y: point.y))
                .concatenating(self.transform)
                .concatenating(self.viewTransform)

            let renderPass = RenderPassDescriptor(
                colorAttachments: [
                    RenderPassColorAttachmentDescriptor(
                        renderTarget: backBuffer,
                        loadAction: .load,
                        storeAction: .store)
                ])
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
                Log.err("GraphicsContext error: makeRenderCommandEncoder failed.")
                return
            }

            for glyphGroup in text.glyphGroups {
                let texture = glyphGroup.texture
                let vertices = glyphGroup.vertices.map {
                    return _Vertex(position: $0.pos.applying(transform2).float2,
                            texcoord: $0.tex,
                            color: c)
                }
                self._encodeDrawCommand(shader: .rcImage,
                                        stencil: .ignore,
                                        vertices: vertices,
                                        indices: nil,
                                        texture: texture,
                                        blendState: .defaultAlpha,
                                        pushConstantData: nil,
                                        encoder: encoder)
            }
            encoder.endEncoding()
        } else {
            fatalError()
        }
    }
    public func draw(_ text: Text, in rect: CGRect) {
        draw(resolve(text), in: rect)
    }
    public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(text), at: point, anchor: anchor)
    }

    // MARK: - Symbol Rendering
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
