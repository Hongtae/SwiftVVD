import Foundation
import FreeType

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

private func ft26d6ToFloat(_ value: FT_F26Dot6) -> Float {
    Float(value >> 6) + Float(value & 63) / 64.0
}

private func ft16d16ToFloat(_ value: FT_Fixed) -> Float {
    Float(value >> 16) + Float(value & 65535) / 65536.0
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

    private let library: FTLibrary
    private var face: FT_Face
    private let faceLock = SpinLock()
    private var fontData: Data?

    public let device: GraphicsDevice
    public let familyName: String
    public let styleName: String

    public let maxPointSize: Float = Float(1<<25) - Float(1.0/64.0)

    public var pointSize: Float {
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

    public var outline: Float {
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

    public var embolden: Float {
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
    private var _outline: Float
    private var _embolden: Float
    private var _dpi: DPI
    private var _kerningEnabled: Bool
    private var _forceBitmap: Bool

    public struct GlyphData {
        public let texture: Texture
        public let position: CGPoint
        public let advance: CGSize
        public let frame: CGRect
    }

    private struct GlyphTextureAtlas {
        let texture: Texture
        var filledVertical: UInt32
        var currentLineWidth: UInt32
        var currentLineHeight: UInt32
    }

    private var glyphMap: [UnicodeScalar: GlyphData] = [:]
    private var charIndexMap: [UnicodeScalar: UInt32] = [:]
    private var textures: [GlyphTextureAtlas] = []
    private var numGlyphLoaded: UInt = 0

    public init?(device: GraphicsDevice, path: String) {
        
        self._outline = 0.0
        self._embolden = 0.0
        self._size26d6 = 10 * 64
        self._dpi = (72, 72)
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
        self.device = device
        self.face = face!
        self.familyName = .init(cString: face!.pointee.family_name)
        self.styleName = .init(cString: face!.pointee.style_name)
    }

    public init?(device: GraphicsDevice, data: Data) {

        self._outline = 0.0
        self._embolden = 0.0
        self._size26d6 = 10 * 64
        self._dpi = (72, 72)
        self._kerningEnabled = true
        self._forceBitmap = false

        self.fontData = data

        let library = sharedFTLibrary()
        var face: FT_Face? = nil
        let err: FT_Error = self.fontData!.withUnsafeBytes {
            FT_New_Memory_Face(library.library, $0.baseAddress, FT_Long($0.count), 0, &face)
        }
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
        self.device = device
        self.face = face!
        self.familyName = .init(cString: face!.pointee.family_name)
        self.styleName = .init(cString: face!.pointee.style_name)
    }

    deinit {
        FT_Done_Face(self.face)
    }

    /// point, embolden is point-size, outline is pixel-size.
    /// 1/64 <= pointSize <= 0x7fffffff / 64
    public func setStyle(pointSize: Float,
                         dpi: DPI,
                         embolden: Float = 0.0,
                         outline: Float = 0.0,
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
            self.charIndexMap = [:]
            self.textures = []
            self.numGlyphLoaded = 0
        }
        self._kerningEnabled = enableKerning
    }

    /// calculate kern advance between characters.
    public func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        var point: CGPoint = .zero
        if self._kerningEnabled && FT_HAS_KERNING(face) {
            synchronizedBy(locking: self.faceLock) {

                let charIndex = { (c: UnicodeScalar) -> UInt32 in 
                    var index = self.charIndexMap[c]
                    if index == nil {
                        index = FT_Get_Char_Index(self.face, c.value)
                        self.charIndexMap[c] = index!
                    }
                    return index!
                }

                let index1 = charIndex(left)
                let index2 = charIndex(right)
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
    public func lineWidth(text: String) -> Float {
        var length: Float = 0.0
        var c1 = UnicodeScalar(UInt8(0))
        for c2 in text.unicodeScalars {
            if let glyph = self.glyphData(forChar: c2) {
                length += Float(glyph.advance.width)
                length += Float(self.kernAdvance(left: c1, right: c2).x)
            }
            c1 = c2
        }
        return length
    }

    /// pixel-height from baseline. not includes outline.
    public func lineHeight() -> Float {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.height) + ceil(_embolden) * 2.0
    }

    /// text bounding box.
    public func bounds(text: String) -> CGRect {
        var bboxMin: CGPoint = .zero
        var bboxMax: CGPoint = .zero
        var offset: CGFloat = 0.0
        var c1 = UnicodeScalar(UInt8(0)) 
        for c2 in text.unicodeScalars {
            if let glyph = self.glyphData(forChar: c2) {
                if offset > 0.0 {
                    let posMin = CGPoint(x: offset + glyph.position.x, y: glyph.position.y)
                    let posMax = CGPoint(x: posMin.x + glyph.frame.size.width, y: posMin.y + glyph.frame.size.height)

                    if bboxMin.x > posMin.x { bboxMin.x = posMin.x }
                    if bboxMin.y > posMin.y { bboxMin.y = posMin.y }
                    if bboxMax.x < posMax.x { bboxMax.x = posMax.x }
                    if bboxMax.y < posMax.y { bboxMax.y = posMax.y }
                } else {
                    bboxMin = glyph.position
                    bboxMax.x = bboxMin.x + glyph.frame.size.width
                    bboxMax.y = bboxMin.y + glyph.frame.size.height
                }

                offset += glyph.advance.width + self.kernAdvance(left: c1, right: c2).x
            }
            c1 = c2
        }
        let size = CGSize(width: ceil(bboxMax.x - bboxMin.x), height: ceil(bboxMax.y - bboxMin.y))
        return CGRect(origin: bboxMin, size: size)
    }

    /// The distance from the baseline to the highest or upper grid coordinate used to place an outline point.
    public var ascender: Float {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.ascender)
    }

    /// The distance from the baseline to the lowest grid coordinate used to place an outline point.
    public var descender: Float {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.descender)
    }

    public var maxAdvance: Float  {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.max_advance)
    }

    public var height: Float  {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.height) + ceil(_embolden) * 2.0
    }

    /// font pixel-width (includes outline)
    public var glyphMaxWidth: Float {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.max_advance) + (ceil(_embolden) + ceil(_outline)) * 2.0
    }

    /// font pixel-height (includes outline)
    public var glyphMaxHeight: Float  {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.height) + (ceil(_embolden) + ceil(_outline)) * 2.0
    }

    public var xScale: Float {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft16d16ToFloat(metrics.x_scale)
    }

    public var yScale: Float {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft16d16ToFloat(metrics.y_scale)
    }

    public var xPixelsPerEM: UInt {
        let metrics = self.face.pointee.size.pointee.metrics
        return UInt(metrics.x_ppem)
    }

    public var yPixelsPerEM: UInt {
        let metrics = self.face.pointee.size.pointee.metrics
        return UInt(metrics.y_ppem)
    }

    public func clearCache() {
        synchronizedBy(locking: self.faceLock) {
            self.glyphMap = [:]
            self.charIndexMap = [:]
            self.textures = []
            self.numGlyphLoaded = 0
        }
    }

    public func glyphData(forChar c: UnicodeScalar) -> GlyphData? {
        if c.value == 0 { return nil }
        self.faceLock.lock()
        defer { self.faceLock.unlock() }

        let index = FT_Get_Char_Index(face, c.value)
        // loading font.
        let loadFlags: FT_Int32 = _forceBitmap ? FT_LOAD_RENDER : FT_LOAD_DEFAULT
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

            } else {

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
                    position.x = CGFloat(face.pointee.glyph.pointee.bitmap_left) - CGFloat(_outline)
                    position.y = CGFloat(ascender) - CGFloat(face.pointee.glyph.pointee.bitmap_top) + CGFloat(_outline)
                    texture = self.cacheGlyphTexture(width: outer.width,
                                                     height: outer.rows,
                                                     data: outer.buffer,
                                                     frame: &frame)

                    FT_Bitmap_Done(library.library, &inner)
                    FT_Bitmap_Done(library.library, &outer)
                } else {
                    FT_Bitmap_Embolden(library.library, &(face.pointee.glyph.pointee.bitmap), boldStrength, boldStrength)
                    position.x = CGFloat(face.pointee.glyph.pointee.bitmap_left)
                    position.y = CGFloat(ascender - Float(face.pointee.glyph.pointee.bitmap_top) + _embolden)
                    texture = self.cacheGlyphTexture(width: face.pointee.glyph.pointee.bitmap.width,
                                                    height: face.pointee.glyph.pointee.bitmap.rows,
                                                    data: face.pointee.glyph.pointee.bitmap.buffer,
                                                    frame: &frame)
                }
            }
        }

        if let texture = texture {
            self.glyphMap[c] = GlyphData(texture: texture, position: position, advance: advance, frame: frame)
        }
        return self.glyphMap[c]
    }

    private func cacheGlyphTexture(width: UInt32, height: UInt32, data: UnsafePointer<UInt8>, frame: inout CGRect) -> Texture? {
        return nil
    }
}
