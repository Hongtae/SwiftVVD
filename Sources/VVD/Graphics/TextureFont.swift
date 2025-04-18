//
//  File: TextureFont.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public class TextureFont: Font {
    
    public struct GlyphData {
        public let texture: Texture?
        public let offset: CGPoint      // glyph offset from baseline
        public let advance: CGSize      // distance to next glyph
        public let frame: CGRect        // texture uv frame
        public let ascender: CGFloat    // upper distance from baseline
        public let descender: CGFloat   // lower distance from baseline (negative direction)
    }

    private struct GlyphTextureAtlas {
        let texture: Texture
        var filledVertical: Int
        var currentLineWidth: Int
        var currentLineMaxHeight: Int
    }

    private var glyphMap: [UnicodeScalar: GlyphData] = [:]
    private var textures: [GlyphTextureAtlas] = []
    private var numGlyphsLoaded: Int = 0

    public let deviceContext: GraphicsDeviceContext

    private var _embolden: CGFloat = .zero
    private var _outline: CGFloat = .zero
    private var _kerningEnabled: Bool = true
    private var _forceBitmap: Bool = false

    public var embolden: CGFloat {
        get { _embolden }
        set {
            self.withFaceLock {
                _embolden = newValue
                glyphMap.removeAll()
                textures.removeAll()
            }
        }
    }

    public var outline: CGFloat {
        get { _outline }
        set {
            self.withFaceLock {
                _outline = newValue
                glyphMap.removeAll()
                textures.removeAll()
            }
        }
    }

    public override var kerningEnabled: Bool {
        get { _kerningEnabled }
        set {
            self.withFaceLock {
                _kerningEnabled = newValue
                glyphMap.removeAll()
                textures.removeAll()
            }
        }
    }

    public override var forceBitmap: Bool {
        get { _forceBitmap }
        set {
            self.withFaceLock {
                _forceBitmap = newValue
                glyphMap.removeAll()
                textures.removeAll()
            }
        }
    }

    public init?(deviceContext: GraphicsDeviceContext, data: any DataProtocol) {
        self.deviceContext = deviceContext
        super.init(data: data)
    }

    public init?(deviceContext: GraphicsDeviceContext, path: String) {
        self.deviceContext = deviceContext
        super.init(path: path)
    }

    override func clearCacheInternal() {
        super.clearCacheInternal()
        glyphMap.removeAll()
        textures.removeAll()
        numGlyphsLoaded = 0
    }

    /// text bounding box.
    public override func bounds(of text: String) -> CGRect {
        var bboxMin: CGPoint = .zero
        var bboxMax: CGPoint = .zero
        var offset: CGFloat = 0.0
        var c1 = UnicodeScalar(UInt8(0))
        for c2 in text.unicodeScalars {
            if let glyph = self.glyphData(for: c2) {
                if offset > 0.0 {
                    let posMin = CGPoint(x: offset + glyph.offset.x,
                                         y: glyph.offset.y - glyph.frame.height)
                    let posMax = CGPoint(x: posMin.x + glyph.frame.width,
                                         y: glyph.offset.y)

                    if bboxMin.x > posMin.x { bboxMin.x = posMin.x }
                    if bboxMin.y > posMin.y { bboxMin.y = posMin.y }
                    if bboxMax.x < posMax.x { bboxMax.x = posMax.x }
                    if bboxMax.y < posMax.y { bboxMax.y = posMax.y }
                } else {
                    bboxMin.x = glyph.offset.x
                    bboxMin.y = glyph.offset.y - glyph.frame.height
                    bboxMax.x = glyph.offset.x + glyph.frame.width
                    bboxMax.y = glyph.offset.y
                }

                offset += glyph.advance.width
                if self.kerningEnabled {
                    offset += self.kernAdvance(left: c1, right: c2).x
                }
            }
            c1 = c2
        }
        let size = CGSize(width: ceil(bboxMax.x - bboxMin.x), height: ceil(bboxMax.y - bboxMin.y))
        return CGRect(x: bboxMin.x,
                      y: self.ascender - bboxMax.y, // adjust coordinates from baseline to bitmap
                      width: size.width,
                      height: size.height)
    }

    public func glyphData(for c: UnicodeScalar) -> GlyphData? {
        if c.value == 0 { return nil }
        var cachedData = self.withFaceLock { self.glyphMap[c] }
        if let cachedData {
            return cachedData
        }

        let loaded = self.loadBitmap(for: c,
                                     embolden: self.embolden,
                                     outline: self.outline) { data, glyph, bmp, metrics in
            var frame: CGRect = .zero
            let offset = CGPoint(x: bmp.left, y: bmp.top)
            let texture = self.cacheGlyphTexture(width: bmp.width,
                                                 height: bmp.rows,
                                                 data: data,
                                                 metrics: metrics,
                                                 frame: &frame)
            self.glyphMap[c] = GlyphData(texture: texture,
                                         offset: offset,
                                         advance: glyph.advance,
                                         frame: frame,
                                         ascender: glyph.ascender,
                                         descender: glyph.descender)
            cachedData = self.glyphMap[c]
        }
        if loaded {
            return cachedData
        }
        return nil
    }

    private func cacheGlyphTexture(width: UInt32, height: UInt32, data: UnsafePointer<UInt8>?, metrics: SizeMetrics, frame: inout CGRect) -> Texture? {
        // keep padding between each glyphs.
        if width == 0 || height == 0 {
            frame = .zero
            return nil
        }
        let data = data!
        let width = Int(width)
        let height = Int(height)

        let device = deviceContext.device
        let queue = deviceContext.copyQueue()!
        var texture: Texture? = nil

        let updateTexture = { (queue: CommandQueue, texture: Texture, rect: CGRect, data: UnsafePointer<UInt8>) in
            let x = Int(rect.minX.rounded())
            let y = Int(rect.minY.rounded())
            let width = Int(rect.width.rounded())
            let height = Int(rect.height.rounded())

            let bufferLength = width * height

            let device = queue.device
            if let stagingBuffer = device.makeBuffer(length: bufferLength, storageMode: .shared, cpuCacheMode: .writeCombined) {
                let buff = stagingBuffer.contents()!

                for i in 0..<height {
                    let src = data.advanced(by: i * width)
                    let dst = buff.advanced(by: i * width)

                    dst.copyMemory(from: src, byteCount: width)
                }

                let cb = queue.makeCommandBuffer()!
                let encoder = cb.makeCopyCommandEncoder()!
                encoder.copy(from: stagingBuffer,
                             sourceOffset: BufferImageOrigin(offset: 0, imageWidth: width, imageHeight: height),
                             to: texture,
                             destinationOffset: TextureOrigin(layer: 0, level: 0, x: x, y: y, z: 0),
                             size: TextureSize(width: width, height: height, depth: 1))
                encoder.endEncoding()
                cb.commit()
            }
        }

        let haveEnoughSpace = { (atlas: GlyphTextureAtlas, width: Int, height: Int) -> Bool in
            let texWidth = atlas.texture.width
            let texHeight = atlas.texture.height

            if texWidth < width || texHeight < (atlas.filledVertical + height) {
                return false
            }

            if texWidth < (atlas.currentLineWidth + width) {
                if texHeight < (atlas.filledVertical + atlas.currentLineMaxHeight + height) {
                    // not enough space.
                    return false
                }
            }
            return true
        }

        let leftMargin: Int = 1
        let rightMargin: Int = 1
        let topMargin: Int = 1
        let bottomMargin: Int = 1
        let hPadding = leftMargin + rightMargin
        let vPadding = topMargin + bottomMargin

        var createNewTexture = true
        for i in 0..<self.textures.count {
            var gta: GlyphTextureAtlas = self.textures[i]
            if haveEnoughSpace(gta, width + hPadding, height + vPadding) {
                if (gta.currentLineWidth + width + leftMargin + rightMargin) > gta.texture.width {
                    // move to next line!
                    assert(gta.currentLineMaxHeight > 0)
                    gta.filledVertical += gta.currentLineMaxHeight
                    gta.currentLineWidth = 0
                    gta.currentLineMaxHeight = 0
                }
                frame = CGRect(x: gta.currentLineWidth + leftMargin,
                               y: gta.filledVertical + topMargin,
                               width: width,
                               height: height)
                updateTexture(queue, gta.texture, frame, data)

                gta.currentLineWidth += width + hPadding
                if (height + vPadding > gta.currentLineMaxHeight) {
                    gta.currentLineMaxHeight = height + vPadding
                }
                self.textures[i] = gta  // update
                texture = gta.texture
                createNewTexture = false
                break
            }
        }
        if createNewTexture {
            // create new texture.
            let glyphWidth = Int(ceil(metrics.maxAdvance)) + hPadding
            let glyphHeight = Int(ceil(metrics.height)) + vPadding
            let glyphsToLoad = self.numGlyphs - self.numGlyphsLoaded
            assert(glyphsToLoad > 0)

            let desiredArea: Int = glyphWidth * glyphHeight * glyphsToLoad
            // let maxTextureSize:Int = 4096
            let maxTextureSize:Int = 1024
            let minTextureSize = { (minReq: Int) -> Int in
                assert(maxTextureSize > minReq)
                var size = 32
                while (size < maxTextureSize && size < minReq) {
                    size = size * 2
                }
                return size
            } (max(glyphWidth, glyphHeight))

            var desiredWidth = minTextureSize
            var desiredHeight = minTextureSize
            while (desiredWidth * desiredHeight) < desiredArea {
                if desiredWidth > desiredHeight {
                    desiredHeight = desiredHeight << 1
                } else if desiredHeight > desiredWidth {
                    desiredWidth = desiredWidth << 1
                } else if desiredWidth < maxTextureSize {
                    desiredWidth = desiredWidth << 1
                } else if desiredHeight < maxTextureSize {
                    desiredHeight = desiredHeight << 1
                } else { break }
            }
            Log.info("Create new texture atlas with resolution: \(desiredWidth) x \(desiredHeight)")

            // create texture object..
            let desc = TextureDescriptor(textureType: .type2D,
                                         pixelFormat: .r8Unorm,
                                         width: desiredWidth,
                                         height: desiredHeight,
                                         depth: 1,
                                         mipmapLevels: 1,
                                         sampleCount: 1,
                                         arrayLength: 1,
                                         usage: [.copyDestination, .sampled])
            texture = device.makeTexture(descriptor: desc)

            if let texture = texture {
                // Array<UInt8>(repeating: 0, count: desc.width * desc.height).withUnsafeBytes {
                //     let ptr = $0.baseAddress!.assumingMemoryBound(to: UInt8.self)
                //     updateTexture(queue, texture, CGRect(x: 0, y: 0, width: desc.width, height: desc.height),ptr)
                // }

                frame = CGRect(x: CGFloat(leftMargin),
                               y: CGFloat(topMargin),
                               width: CGFloat(width),
                               height: CGFloat(height))
                updateTexture(queue, texture, frame, data)

                let gta = GlyphTextureAtlas(
                    texture: texture,
                    filledVertical: 0,
                    currentLineWidth: width + hPadding,
                    currentLineMaxHeight: height + vPadding)
                textures.append(gta)
            } else {
                assertionFailure("Failed to create new texture with resolution: \(desc.width)x\(desc.height).")
                frame = .zero
                return nil
            }
        }
        assert(texture != nil)
        self.numGlyphsLoaded += 1
        return texture
    }
}

public extension TextureFont {
    // screen space vertex (2d)
    struct Vertex {
        var position: Vector2
        var texcoord: Vector2
    }
    struct Quad {
        var lt: Vertex
        var rt: Vertex
        var lb: Vertex
        var rb: Vertex
    }
    struct GlyphQuad {
        let char: UnicodeScalar
        let quad: Quad
        let texture: Texture
    }

    func drawableQuads(for text: String, boundingBox: UnsafeMutablePointer<CGRect>? = nil) -> [GlyphQuad] {
        var quads: [GlyphQuad] = []
        let str = text.unicodeScalars
        quads.reserveCapacity(str.count)

        var bboxMin = Vector2(0, 0)
        var bboxMax = Vector2(0, 0)
        var offset: CGFloat = 0.0        // accumulated text width (pixel)

        var c1 = UnicodeScalar(UInt8(0)) 
        for c2 in str {
            // get glyph info from font object
            if let glyph = self.glyphData(for: c2) {
                let posMin = Vector2(Scalar(glyph.offset.x + offset), Scalar(glyph.offset.y))
                let posMax = Vector2(Scalar(glyph.frame.width), Scalar(glyph.frame.height)) + posMin

                if offset > 0.0 {
                    if (bboxMin.x > posMin.x) { bboxMin.x = posMin.x }
                    if (bboxMin.y > posMin.y) { bboxMin.y = posMin.y }
                    if (bboxMax.x < posMax.x) { bboxMax.x = posMax.x }
                    if (bboxMax.y < posMax.y) { bboxMax.y = posMax.y }
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

                        let quad = Quad(lt: Vertex(position: Vector2(posMin.x, posMin.y),
                                                   texcoord: Vector2(uvMinX, uvMinY)),
                                        rt: Vertex(position: Vector2(posMax.x, posMin.y),
                                                   texcoord: Vector2(uvMaxX, uvMinY)),
                                        lb: Vertex(position: Vector2(posMin.x, posMax.y),
                                                   texcoord: Vector2(uvMinX, uvMaxY)),
                                        rb: Vertex(position: Vector2(posMax.x, posMax.y),
                                                   texcoord: Vector2(uvMaxX, uvMaxY)))
                        let q = GlyphQuad(char: c2, quad: quad, texture: texture)
                        quads.append(q)
                    }
                }
                offset += glyph.advance.width + self.kernAdvance(left: c1, right: c2).x
            }
            c1 = c2
        }
        if let bbox = boundingBox {
            bbox.pointee = CGRect(x: CGFloat(bboxMin.x),
                                  y: CGFloat(bboxMin.y),
                                  width: CGFloat(bboxMax.x - bboxMin.x),
                                  height: CGFloat(bboxMax.y - bboxMin.y))
        }
        return quads
    }

    typealias DrawQuds = (_ quads: [Quad], _ texture: Texture) -> Void

    func drawText(_ text: String, bounds: CGRect, transform: Matrix3 = .identity, _ draw: DrawQuds) {
        var bbox: CGRect = .zero
        var quads = self.drawableQuads(for: text, boundingBox: &bbox)
        if quads.isEmpty { return }

        let width = bbox.width
        let height = bbox.height
        if width <= .ulpOfOne || height <= .ulpOfOne { return }

        // sort by texture order
        quads.sort {
            ObjectIdentifier($0.texture) > ObjectIdentifier($1.texture)
        }

        // calculate transform matrix
        var trans = AffineTransform2(x: -bbox.minX, y: -bbox.minY)    // move origin
        trans *= LinearTransform2(scaleX: 1.0 / width, y: 1.0 / height) // normalize size
        trans *= LinearTransform2(scaleX: Scalar(bounds.width), y: Scalar(bounds.height)) // scale to bounds
        trans.translate(x: Scalar(bounds.minX), y: Scalar(bounds.minY)) // move to bounds origin

        var matrix = trans.matrix3
        matrix *= transform         // user transform

        var lastTexture: Texture? = nil
        var drawableQuads: [Quad] = []
        drawableQuads.reserveCapacity(quads.count * 6)
        for q in quads {
            if q.texture !== lastTexture {
                if drawableQuads.count > 0 {
                    draw(drawableQuads, lastTexture!)
                }
                drawableQuads.removeAll(keepingCapacity: true)
                lastTexture = q.texture
            }
            var q2 = q.quad
            q2.lt.position.apply(matrix)
            q2.rt.position.apply(matrix)
            q2.lb.position.apply(matrix)
            q2.rb.position.apply(matrix)
            drawableQuads.append(q2)
        }
        if drawableQuads.count > 0 {
            draw(drawableQuads, lastTexture!)
        }
    }

    func drawText(_ text: String, baselineBegin: CGPoint, baselineEnd: CGPoint, _ draw: DrawQuds) {
        if text.isEmpty { return }
        if (baselineEnd - baselineBegin).magnitude < .ulpOfOne { return }

        let ascender = self.ascender
        // let lineHeight = self.lineHeight()
        let lineWidth = self.lineWidth(of: text)
        let textBounds = self.bounds(of: text)

        let scale = (baselineEnd - baselineBegin).magnitude
        let baselineDir = Vector2(baselineEnd - baselineBegin).normalized().float2
        let angle = acosf(baselineDir.0) * ((baselineDir.1 < 0) ? -1.0 : 1.0)

        // calculate transform (matrix)
        var transform = AffineTransform2(x: 0, y: Scalar(-ascender))    // move pivot to baseline
        transform *= LinearTransform2()
            .scaled(by: Scalar(scale / lineWidth))          // scale
            .rotated(by: Scalar(angle))                     // rotate
        transform.translate(by: Vector2(baselineBegin))

        self.drawText(text, bounds: textBounds, transform: transform.matrix3, draw)
    }
}
