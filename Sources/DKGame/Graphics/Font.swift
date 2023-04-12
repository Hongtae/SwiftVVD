//
//  File: Font.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import FreeType_static

private class FTLibrary {
    var library: FT_Library?

    init() {
        FT_Init_FreeType(&library)
    }
    deinit {
        FT_Done_FreeType(library)
    }
}
private weak var library: FTLibrary? = nil
private var libraryLock = NSLock()

private func sharedFTLibrary() -> FTLibrary {
    libraryLock.lock()
    defer { libraryLock.unlock() }

    var lib: FTLibrary? = library
    if lib == nil {
        lib = FTLibrary()
        library = lib
    }
    return lib!
}

private func ft26d6ToFloat(_ value: FT_F26Dot6) -> CGFloat {
    CGFloat(value >> 6) + CGFloat(value & 63) / 64.0
}

private func ft16d16ToFloat(_ value: FT_Fixed) -> CGFloat {
    CGFloat(value >> 16) + CGFloat(value & 65535) / 65536.0
}

private func FT_HAS_KERNING(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_KERNING != 0
}

private func FT_IS_SCALABLE(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_SCALABLE != 0
}

private func FT_IS_FIXED_WIDTH(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_FIXED_WIDTH != 0
}

private func FT_HAS_FIXED_SIZES(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_FIXED_SIZES != 0
}

public class Font {
    public typealias DPI = (x: UInt32, y: UInt32)
    //public static let defaultDPI = DPI(x: 96, y: 96)
    public static let defaultDPI = DPI(x: 72, y: 72)

    private let library: FTLibrary
    private var face: FT_Face
    private let faceLock = SpinLock()
    public private(set) var fontData: RawBufferStorage?

    public let deviceContext: GraphicsDeviceContext
    public let familyName: String
    public let styleName: String
    public let filePath: String

    public let maxPointSize: CGFloat = CGFloat(1<<25) - CGFloat(1.0/64.0)

    public var pointSize: CGFloat {
        get { ft26d6ToFloat(_size26d6) }
        set(p) {
            self.setStyle(pointSize: p,
                          dpi: _dpi,
                          embolden: _embolden,
                          outline: _outline,
                          enableKerning: _kerningEnabled,
                          forceBitmap: _forceBitmap)
        }
    }

    public var outline: CGFloat {
        get { _outline }
        set(v) {
            self.setStyle(pointSize: self.pointSize,
                          dpi: _dpi,
                          embolden: _embolden,
                          outline: v,
                          enableKerning: _kerningEnabled,
                          forceBitmap: _forceBitmap)
        }
    }

    public var embolden: CGFloat {
        get { _embolden }
        set(v) {
            self.setStyle(pointSize: self.pointSize,
                          dpi: _dpi,
                          embolden: v,
                          outline: _outline,
                          enableKerning: _kerningEnabled,
                          forceBitmap: _forceBitmap)
        }
    }

    public var dpi: DPI {
        get { _dpi }
        set(v) {
            self.setStyle(pointSize: self.pointSize,
                          dpi: v,
                          embolden: _embolden,
                          outline: _outline,
                          enableKerning: _kerningEnabled,
                          forceBitmap: _forceBitmap)
        }
    }

    public var kerningEnabled: Bool {
        get { _kerningEnabled }
        set(v) {
            self.setStyle(pointSize: self.pointSize,
                          dpi: _dpi,
                          embolden: _embolden,
                          outline: _outline,
                          enableKerning: v,
                          forceBitmap: _forceBitmap)
        }
    }

    public var forceBitmap: Bool {
        get { _forceBitmap }
        set(v) {
            self.setStyle(pointSize: self.pointSize,
                          dpi: _dpi,
                          embolden: _embolden,
                          outline: _outline,
                          enableKerning: _kerningEnabled,
                          forceBitmap: v)
        }
    }

    private var _size26d6: FT_F26Dot6
    private var _outline: CGFloat
    private var _embolden: CGFloat
    private var _dpi: DPI
    private var _kerningEnabled: Bool
    private var _forceBitmap: Bool

    public struct GlyphData {
        public let texture: Texture?
        public let position: CGPoint
        public let advance: CGSize
        public let frame: CGRect
        public let ascender: CGFloat
        public let descender: CGFloat
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

    public init?(deviceContext: GraphicsDeviceContext, path: String) {
        self._outline = 0.0
        self._embolden = 0.0
        self._size26d6 = 10 * 64
        self._dpi = Self.defaultDPI
        self._kerningEnabled = true
        self._forceBitmap = false

        let library = sharedFTLibrary()
        var face: FT_Face? = nil
        let err: FT_Error = FT_New_Face(library.library, path, 0, &face)
        if err != 0 {
            return nil
        }
        if face!.pointee.charmap == nil {
            if FT_Set_Charmap(face, face!.pointee.charmaps[0]) != 0 {
                FT_Done_Face(face)
                return nil
            }
        }
        if FT_Set_Char_Size(face, 0, _size26d6, _dpi.x, _dpi.y) != 0 {
            Log.warn("Failed to initialize font style, You should call Font.setStyle() manually.")
        }
        self.library = library
        self.deviceContext = deviceContext
        self.face = face!
        self.familyName = .init(cString: face!.pointee.family_name)
        self.styleName = .init(cString: face!.pointee.style_name)
        self.filePath = path
    }

    public convenience init?<D>(deviceContext: GraphicsDeviceContext,
                                data: D) where D: DataProtocol {
        if data.isEmpty { return nil }
        let buffer = RawBufferStorage(data) // copy font data
        self.init(deviceContext: deviceContext, data: buffer)
    }

    public init?(deviceContext: GraphicsDeviceContext, data: RawBufferStorage) {
        if data.isEmpty { return nil }

        self._outline = 0.0
        self._embolden = 0.0
        self._size26d6 = 10 * 64
        self._dpi = Self.defaultDPI
        self._kerningEnabled = true
        self._forceBitmap = false

        self.fontData = data

        let library = sharedFTLibrary()
        var face: FT_Face? = nil
        let err: FT_Error = FT_New_Memory_Face(library.library, data.baseAddress, FT_Long(data.count), 0, &face)
        if err != 0 {
            return nil
        }
        if face!.pointee.charmap == nil {
            if FT_Set_Charmap(face, face!.pointee.charmaps[0]) != 0 {
                FT_Done_Face(face)
                return nil
            }
        }
        if FT_Set_Char_Size(face, 0, _size26d6, _dpi.x, _dpi.y) != 0 {
            Log.warn("Failed to initialize font style, You should call Font.setStyle() manually.")
        }
        self.library = library
        self.deviceContext = deviceContext
        self.face = face!
        self.familyName = .init(cString: face!.pointee.family_name)
        self.styleName = .init(cString: face!.pointee.style_name)
        self.filePath = ""
    }

    deinit {
        FT_Done_Face(self.face)
    }

    /// point, embolden is point-size, outline is pixel-size.
    /// 1/64 <= pointSize <= 0x7fffffff / 64
    public func setStyle(pointSize: CGFloat,
                         dpi: DPI,
                         embolden: CGFloat = 0.0,
                         outline: CGFloat = 0.0,
                         enableKerning: Bool = true,
                         forceBitmap: Bool = false) {
        let embolden = max(embolden, 0.0)
        let outline = max(outline, 0.0)
        let resX = max(dpi.x, 1)
        let resY = max(dpi.y, 1)

        // clamp pointSize (26.6 signed-fixed) from 1/64 to 2^25-(1/64)
        let dp: Double = clamp(Double(pointSize) * 64.0, min:1.0, max:Double(0x7fffffff))
        let charSize: FT_F26Dot6 = FT_F26Dot6(floor(dp))

        if charSize != self._size26d6 ||
           embolden != self._embolden ||
           outline != self._outline ||
           resX != self._dpi.x || resY != self._dpi.y ||
           forceBitmap != self._forceBitmap {

            self.faceLock.lock()
            defer { self.faceLock.unlock() }

            if charSize != _size26d6 || resX != _dpi.x || resY != _dpi.y {
                if FT_Set_Char_Size(self.face, 0, charSize, resX, resY) != 0 {
                    Log.err("FT_Set_Char_Size failed! (size:\(String(format:"0x%x", charSize)), dpi:\(resX)x\(resY))")
                    return
                }
            }

            self._size26d6 = charSize
            self._dpi = (resX, resY)
            self._outline = outline
            self._embolden = embolden
            self._forceBitmap = forceBitmap
            self._kerningEnabled = enableKerning
            
            self.glyphMap = [:]
            self.textures = []
            self.numGlyphsLoaded = 0
        }
        self._kerningEnabled = enableKerning
    }

    /// calculate kern advance between characters.
    public func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        var point: CGPoint = .zero
        if self._kerningEnabled && FT_HAS_KERNING(face) {
            synchronizedBy(locking: self.faceLock) {
                let index1 = FT_Get_Char_Index(self.face, FT_ULong(left.value))
                let index2 = FT_Get_Char_Index(self.face, FT_ULong(right.value))
                if index1 != 0 && index2 != 0 {
                    var advance = FT_Vector()
                    if FT_Get_Kerning(face, index1, index2, FT_UInt(FT_KERNING_DEFAULT.rawValue), &advance) == 0 {
                        point.x = CGFloat(advance.x) / 64.0
                        point.y = CGFloat(advance.y) / 64.0
                    }
                }
            }
        }
        return point
    }

    /// text pixel-width from baseline. not includes outline.
    public func lineWidth(of text: String) -> CGFloat {
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

    /// pixel-height from baseline. not includes outline.
    public func lineHeight() -> CGFloat {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.height) + ceil(_embolden) * 2.0
    }

    /// text bounding box.
    public func bounds(of text: String) -> CGRect {
        var bboxMin: CGPoint = .zero
        var bboxMax: CGPoint = .zero
        var offset: CGFloat = 0.0
        var c1 = UnicodeScalar(UInt8(0)) 
        for c2 in text.unicodeScalars {
            if let glyph = self.glyphData(for: c2) {
                if offset > 0.0 {
                    let posMin = CGPoint(x: offset + glyph.position.x, y: glyph.position.y)
                    let posMax = CGPoint(x: posMin.x + glyph.frame.width, y: posMin.y + glyph.frame.height)

                    if bboxMin.x > posMin.x { bboxMin.x = posMin.x }
                    if bboxMin.y > posMin.y { bboxMin.y = posMin.y }
                    if bboxMax.x < posMax.x { bboxMax.x = posMax.x }
                    if bboxMax.y < posMax.y { bboxMax.y = posMax.y }
                } else {
                    bboxMin = glyph.position
                    bboxMax.x = bboxMin.x + glyph.frame.width
                    bboxMax.y = bboxMin.y + glyph.frame.height
                }

                offset += glyph.advance.width + self.kernAdvance(left: c1, right: c2).x
            }
            c1 = c2
        }
        let size = CGSize(width: ceil(bboxMax.x - bboxMin.x), height: ceil(bboxMax.y - bboxMin.y))
        return CGRect(origin: bboxMin, size: size)
    }

    /// The distance from the baseline to the highest or upper grid coordinate used to place an outline point.
    public var ascender: CGFloat {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.ascender) + _embolden
    }

    /// The distance from the baseline to the lowest grid coordinate used to place an outline point.
    public var descender: CGFloat {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.descender) + _embolden
    }

    public var maxAdvance: CGFloat  {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.max_advance) + ceil(_embolden * 2.0)
    }

    public var height: CGFloat  {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.height) + ceil(_embolden * 2.0) + ceil(_outline) * 2.0
    }

    /// font pixel-width (includes outline)
    public var glyphMaxWidth: CGFloat {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.max_advance) + ceil(_embolden * 2.0) + ceil(_outline) * 2.0
    }

    /// font pixel-height (includes outline)
    public var glyphMaxHeight: CGFloat  {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.height) + ceil(_embolden * 2.0) + ceil(_outline) * 2.0
    }

    public var xScale: CGFloat {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft16d16ToFloat(metrics.x_scale)
    }

    public var yScale: CGFloat {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft16d16ToFloat(metrics.y_scale)
    }

    public var xPixelsPerEM: Int {
        let metrics = self.face.pointee.size.pointee.metrics
        return Int(metrics.x_ppem)
    }

    public var yPixelsPerEM: Int {
        let metrics = self.face.pointee.size.pointee.metrics
        return Int(metrics.y_ppem)
    }

    public func clearCache() {
        synchronizedBy(locking: self.faceLock) {
            self.glyphMap = [:]
            self.textures = []
            self.numGlyphsLoaded = 0
        }
    }

    public func hasGlyph(for c: UnicodeScalar) -> Bool {
        synchronizedBy(locking: self.faceLock) {
            FT_Get_Char_Index(self.face, FT_ULong(c.value)) != 0
        }
    }

    public func glyphData(for c: UnicodeScalar) -> GlyphData? {
        if c.value == 0 { return nil }
        self.faceLock.lock()
        defer { self.faceLock.unlock() }

        if let data = self.glyphMap[c] {
            return data
        }

        let index = FT_Get_Char_Index(face, FT_ULong(c.value))
        // loading font.
        let loadFlags = _forceBitmap ? FT_Int32(FT_LOAD_RENDER) : FT_Int32(FT_LOAD_DEFAULT)
        if FT_Load_Glyph(face, index, loadFlags) != 0 {
            Log.err("Failed to load glyph for char=\(c)(0x\(String(format: "%x", c.value)))")
            return nil
        }

        let ascender = self.ascender
        let boldStrength = FT_Pos(_embolden * 64.0)
        var outlineWidth = FT_Pos(_outline * 64.0)

        let advance = CGSize(width: CGFloat(face.pointee.glyph.pointee.advance.x + boldStrength) / 64.0,
                             height: CGFloat(face.pointee.glyph.pointee.advance.y + boldStrength) / 64.0)
        var position: CGPoint = .zero
        var frame: CGRect = .zero
        var texture: Texture? = nil

        if face.pointee.glyph.pointee.format == FT_GLYPH_FORMAT_OUTLINE {
            face.pointee.glyph.pointee.outline.flags |= FT_OUTLINE_HIGH_PRECISION

            if _outline > 0.0 {
                // create outline stroker, drawing outline as bitmap.
                FT_Outline_Embolden(&face.pointee.glyph.pointee.outline, boldStrength)
                var stroker: FT_Stroker? = nil
                FT_Stroker_New(library.library, &stroker)
                FT_Stroker_Set(stroker, outlineWidth, FT_STROKER_LINECAP_ROUND, FT_STROKER_LINEJOIN_ROUND, 0)
                FT_Stroker_ParseOutline(stroker, &face.pointee.glyph.pointee.outline, 0)
                var ftOutline = FT_Outline()
                var points: FT_UInt = 0
                var contours: FT_UInt = 0
                FT_Stroker_GetCounts(stroker, &points, &contours)
                FT_Outline_New(library.library, points, FT_Int(contours), &ftOutline)
                ftOutline.n_contours = 0
                ftOutline.n_points = 0
                FT_Stroker_Export(stroker, &ftOutline)
                FT_Stroker_Done(stroker)

                var ftBitmap = FT_Bitmap()
                FT_Bitmap_Init(&ftBitmap)

                var cbox = FT_BBox()
                FT_Outline_Get_CBox(&ftOutline, &cbox)

                cbox.xMin = cbox.xMin & ~63
                cbox.yMin = cbox.yMin & ~63
                cbox.xMax = (cbox.xMax + 63) & ~63
                cbox.yMax = (cbox.yMax + 63) & ~63

                let width = UInt32(cbox.xMax - cbox.xMin) >> 6
                let height = UInt32(cbox.yMax - cbox.yMin) >> 6

                let xShift = FT_Pos(cbox.xMin) 
                let yShift = FT_Pos(cbox.yMin) 
                let left  = CGFloat(cbox.xMin >> 6)  // left offset of glyph
                let top   = CGFloat(cbox.yMax >> 6)  // upper of offset of glyph (height for origin)

                ftBitmap.width = width
                ftBitmap.rows = height
                ftBitmap.pitch = Int32(width)
                ftBitmap.num_grays = 256
                ftBitmap.pixel_mode = UInt8(FT_PIXEL_MODE_GRAY.rawValue)
                let bufferSize = Int(ftBitmap.pitch) * Int(ftBitmap.rows)
                ftBitmap.buffer = .allocate(capacity: bufferSize)
                ftBitmap.buffer.initialize(repeating: 0, count: bufferSize)

                FT_Outline_Translate(&ftOutline, -xShift, -yShift)

                if FT_Outline_Get_Bitmap(library.library, &ftOutline, &ftBitmap) == 0 {
                    // left: bitmap starting point from origin
                    // top: height from origin
                    position.x = left
                    position.y = ascender - top
                    texture = self.cacheGlyphTexture(width: ftBitmap.width,
                                                     height: ftBitmap.rows,
                                                     data: ftBitmap.buffer,
                                                     frame: &frame)
                }

                ftBitmap.buffer.deallocate()
                ftBitmap.buffer = nil
                FT_Bitmap_Done(library.library, &ftBitmap)
                FT_Outline_Done(library.library, &ftOutline)
            } else {
                FT_Outline_Embolden(&face.pointee.glyph.pointee.outline, boldStrength)

                var glyph: FT_Glyph? = nil
                FT_Get_Glyph(face.pointee.glyph, &glyph)
                if FT_Glyph_To_Bitmap(&glyph, FT_RENDER_MODE_NORMAL, nil, 1) == 0 {

                    let glyphBitmap: FT_BitmapGlyph = withUnsafeBytes(of: glyph!) {
                        $0.baseAddress!.assumingMemoryBound(to: FT_BitmapGlyph.self).pointee
                    }
                    // bitmap.left: bitmap offset from origin
                    // bitmap.top: height from origin
                    position.x = CGFloat(glyphBitmap.pointee.left)
                    position.y = ascender - CGFloat(glyphBitmap.pointee.top)
                    texture = self.cacheGlyphTexture(width: glyphBitmap.pointee.bitmap.width,
                                                     height: glyphBitmap.pointee.bitmap.rows,
                                                     data: glyphBitmap.pointee.bitmap.buffer,
                                                     frame: &frame)
                }
                FT_Done_Glyph(glyph)
            }
        } else {
            if FT_Render_Glyph(face.pointee.glyph, FT_RENDER_MODE_NORMAL) == 0 {
                if _outline > 0.0 {
                    outlineWidth = outlineWidth * 2
                    let outerSize = boldStrength + outlineWidth
                    let innerSize = boldStrength - outlineWidth
                    // create two bitmaps, generate outline from bigger subtract smaller
                    var inner = FT_Bitmap()
                    var outer = FT_Bitmap()
                    FT_Bitmap_New(&inner)
                    FT_Bitmap_New(&outer)
                    FT_Bitmap_Copy(library.library, &face.pointee.glyph.pointee.bitmap, &inner)
                    FT_Bitmap_Copy(library.library, &face.pointee.glyph.pointee.bitmap, &outer)
                    FT_Bitmap_Embolden(library.library, &inner, innerSize, innerSize)
                    FT_Bitmap_Embolden(library.library, &outer, outerSize, outerSize)

                    let offsetX = (outer.width - inner.width) >> 1
                    let offsetY = (outer.rows - inner.rows) >> 1

                    for y in 0..<inner.rows {
                        for x in 0..<inner.width {
                            let value1 = outer.buffer[ Int((y + offsetY) * outer.width + x + offsetX) ]
                            let value2 = inner.buffer[ Int(y * inner.width + x) ]

                            outer.buffer[ Int((y + offsetY) * outer.width + x + offsetX) ] = max(value1 - value2, 0)
                        }
                    }
                    position.x = CGFloat(face.pointee.glyph.pointee.bitmap_left) - _outline
                    position.y = ascender - (CGFloat(face.pointee.glyph.pointee.bitmap_top) + _outline)
                    texture = self.cacheGlyphTexture(width: outer.width,
                                                     height: outer.rows,
                                                     data: outer.buffer,
                                                     frame: &frame)

                    FT_Bitmap_Done(library.library, &inner)
                    FT_Bitmap_Done(library.library, &outer)
                } else {
                    FT_Bitmap_Embolden(library.library, &(face.pointee.glyph.pointee.bitmap), boldStrength, boldStrength)
                    position.x = CGFloat(face.pointee.glyph.pointee.bitmap_left)
                    position.y = ascender - CGFloat(face.pointee.glyph.pointee.bitmap_top) + _embolden
                    texture = self.cacheGlyphTexture(width: face.pointee.glyph.pointee.bitmap.width,
                                                     height: face.pointee.glyph.pointee.bitmap.rows,
                                                     data: face.pointee.glyph.pointee.bitmap.buffer,
                                                     frame: &frame)
                }
            }
        }

        self.glyphMap[c] = GlyphData(texture: texture,
                                     position: position,
                                     advance: advance,
                                     frame: frame,
                                     ascender: self.ascender,
                                     descender: self.descender)
        return self.glyphMap[c]
    }

    private func cacheGlyphTexture(width: UInt32, height: UInt32, data: UnsafePointer<UInt8>?, frame: inout CGRect) -> Texture? {
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
            let glyphWidth = Int(ceil(self.glyphMaxWidth)) + hPadding
            let glyphHeight = Int(ceil(self.glyphMaxHeight)) + vPadding
            let glyphsToLoad = Int(face.pointee.num_glyphs) - self.numGlyphsLoaded
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
            let desc = TextureDescriptor(
                textureType: .type2D,
                pixelFormat: .r8Unorm,
                width: desiredWidth,
                height: desiredHeight,
                depth: 1,
                mipmapLevels: 1,
                sampleCount: 1,
                arrayLength: 1,
                usage: [.copyDestination, .sampled]
            )
            texture = device.makeTexture(descriptor: desc)

            if let texture = texture {
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

    public struct SizeMetrics {
        public let xPixelsPerEM: Int
        public let yPixelsPerEM: Int
        public let xScale: CGFloat
        public let yScale: CGFloat
        public let ascender: CGFloat
        public let descender: CGFloat
        public let height: CGFloat
        public let maxAdvance: CGFloat
    }

    public var baseMetrics: SizeMetrics {
        let metrics = self.face.pointee.size.pointee.metrics
        return SizeMetrics(xPixelsPerEM: Int(metrics.x_ppem),
                           yPixelsPerEM: Int(metrics.y_ppem),
                           xScale: ft16d16ToFloat(metrics.x_scale),
                           yScale: ft16d16ToFloat(metrics.y_scale),
                           ascender: ft26d6ToFloat(metrics.ascender),
                           descender: ft26d6ToFloat(metrics.descender),
                           height: ft26d6ToFloat(metrics.height),
                           maxAdvance: ft26d6ToFloat(metrics.max_advance))
    }
}
