//
//  File: Font.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import FreeType

//////////////////////////////////////////////////////////////////////////////
// The coordinate system of the font has a positive Y value
// in the upward direction, based on the 'baseline'.
// This means that in a coordinate system where the top left is the origin,
// the Y value must be inverted relative to the 'baseline'.
//
//
//                                       offset +--------+
//                              (from baseline) | Glyph  |
//   +Y                                         | Bitmap |
//    |    |< advance >|                        +--------+ extent
//    |    |           |
//    |    ooooooooooooo  - - - - - - - - - - - - - - - - - - - ascender (+y)
//    |    8'   888   `8
//    |         888      oooo    ooo oo.ooooo.   .ooooo.
//    |         888       `88.  .8'   888' `88b d88' `88b
//    |         888        `88..8'    888   888 888ooo888
//    |         888         `888'     888   888 888    .o
// ___|________o888o_________.8'______888bod8P'_`Y8bod8P'______ baseline
//  origin                .o..P'      888
//    |                   `Y8P'      o888o _ _ _ _ _ _ _ _ _ _ descender (-y)
//    |
//   -Y
//                               (The ASCII font design is taken from FIGlet)

private final class FTLibrary: @unchecked Sendable {
    var library: FT_Library?
    init() {
        FT_Init_FreeType(&library)
    }
    deinit {
        FT_Done_FreeType(library)
    }
}

private let library = Mutex<WeakObject<FTLibrary>>(nil)

private func sharedFTLibrary() -> FTLibrary {
    library.withLock {
        if let lib = $0.value {
            return lib
        }
        let lib = FTLibrary()
        $0.value = lib
        return lib
    }
}

private func ft26d6ToFloat(_ value: FT_F26Dot6) -> CGFloat {
    CGFloat(value >> 6) + CGFloat(value & 63) / 64.0
}

private func ft26d6(_ value: CGFloat) -> FT_F26Dot6 {
    FT_F26Dot6(value * 64.0)
}

private func ft26d6Floor(_ value: FT_F26Dot6) -> FT_F26Dot6 {
    value & ~63
}

private func ft26d6Round(_ value: FT_F26Dot6) -> FT_F26Dot6 {
    ft26d6Floor(value + 32)
}

private func ft26d6Ceil(_ value: FT_F26Dot6) -> FT_F26Dot6 {
    ft26d6Floor(value + 63)
}

private func ft16d16ToFloat(_ value: FT_Fixed) -> CGFloat {
    CGFloat(value >> 16) + CGFloat(value & 65535) / 65536.0
}

private func ft16d16(_ value: CGFloat) -> FT_Fixed {
    FT_Fixed(value * 65536.0)
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

private extension CGPoint {
    init(_ vector: FT_Vector) {
        self.init(x: CGFloat(vector.x), y: CGFloat(vector.y))
    }
}

public class Font {
    public typealias DPI = (x: UInt32, y: UInt32)
    //public static let defaultDPI = DPI(x: 96, y: 96)
    public static let defaultDPI = DPI(x: 72, y: 72)

    private let library: FTLibrary

    private struct NonisolatedFace: @unchecked Sendable {
        let face: FT_Face
    }

    private let face: Mutex<NonisolatedFace>

    func withFaceLock<T>(_ body: () throws -> T) rethrows -> T {
        try face.withLock { _ in try body() }
    }
    public private(set) var fontData: (any FixedAddressStorageData)?

    public let familyName: String
    public let styleName: String
    public let filePath: String
    public let numGlyphs: Int

    public let maxPointSize: CGFloat = CGFloat(1<<25) - CGFloat(1.0/64.0)

    public var pointSize: CGFloat {
        get { ft26d6ToFloat(_size26d6) }
        set(p) { self.setStyle(pointSize: p, dpi: _dpi) }
    }

    public var dpi: DPI {
        get { _dpi }
        set(v) { self.setStyle(pointSize: self.pointSize, dpi: v) }
    }

    public var forceBitmap: Bool { false }
    public var kerningEnabled: Bool { true }

    private var _size26d6: FT_F26Dot6
    private var _dpi: DPI

    public struct Glyph: Sendable {
        public let advance: CGSize      // distance to next glyph
        public let ascender: CGFloat    // upper distance from baseline
        public let descender: CGFloat   // lower distance from baseline (negative direction)
    }

    private var loadedGlyphs: [UnicodeScalar: Glyph] = [:]

    public init?(path: String) {
        self._size26d6 = 10 * 64
        self._dpi = Self.defaultDPI

        let library = sharedFTLibrary()
        var face: FT_Face? = nil
        let err: FT_Error = FT_New_Face(library.library, path, 0, &face)
        if err != 0 {
            return nil
        }
        guard let face else { return nil }
        if face.pointee.charmap == nil {
            if FT_Set_Charmap(face, face.pointee.charmaps[0]) != 0 {
                FT_Done_Face(face)
                return nil
            }
        }
        if FT_Set_Char_Size(face, 0, _size26d6, _dpi.x, _dpi.y) != 0 {
            Log.warn("Failed to initialize font style, You should call Font.setStyle() manually.")
        }
        self.library = library
        self.familyName = .init(cString: face.pointee.family_name)
        self.styleName = .init(cString: face.pointee.style_name)
        self.numGlyphs = Int(face.pointee.num_glyphs)
        self.face = .init(.init(face: face))
        self.filePath = path
    }

    public init?(data: any DataProtocol) {
        if data.isEmpty { return nil }

        self._size26d6 = 10 * 64
        self._dpi = Self.defaultDPI

        let data = data.makeFixedAddressStorage()
        self.fontData = data

        let library = sharedFTLibrary()
        var face: FT_Face? = nil
        let err: FT_Error = FT_New_Memory_Face(library.library, data.address, FT_Long(data.count), 0, &face)
        if err != 0 {
            return nil
        }
        guard let face else { return nil }
        if face.pointee.charmap == nil {
            if FT_Set_Charmap(face, face.pointee.charmaps[0]) != 0 {
                FT_Done_Face(face)
                return nil
            }
        }
        if FT_Set_Char_Size(face, 0, _size26d6, _dpi.x, _dpi.y) != 0 {
            Log.warn("Failed to initialize font style, You should call Font.setStyle() manually.")
        }
        self.library = library
        self.familyName = .init(cString: face.pointee.family_name)
        self.styleName = .init(cString: face.pointee.style_name)
        self.numGlyphs = Int(face.pointee.num_glyphs)
        self.face = .init(.init(face: face))
        self.filePath = ""
    }

    deinit {
        self.face.withLock {
            _=FT_Done_Face($0.face)
        }
    }

    internal func clearCacheInternal() {
        loadedGlyphs = [:]
    }

    public func clearCache() {
        self.withFaceLock {
            self.clearCacheInternal()
        }
    }

    /// point, embolden is point-size, outline is pixel-size.
    /// 1/64 <= pointSize <= 0x7fffffff / 64
    public func setStyle(pointSize: CGFloat, dpi: DPI) {
        let resX = max(dpi.x, 1)
        let resY = max(dpi.y, 1)

        // clamp pointSize (26.6 signed-fixed) from 1/64 to 2^25-(1/64)
        let dp: Double = clamp(Double(pointSize) * 64.0, min:1.0, max:Double(0x7fffffff))
        let charSize: FT_F26Dot6 = FT_F26Dot6(floor(dp))

        if charSize != self._size26d6 || resX != self._dpi.x || resY != self._dpi.y {
            self.face.withLock {
                let face = $0.face
                if charSize != _size26d6 || resX != _dpi.x || resY != _dpi.y {
                    if FT_Set_Char_Size(face, 0, charSize, resX, resY) != 0 {
                        Log.err("FT_Set_Char_Size failed! (size:\(String(format:"0x%x", charSize)), dpi:\(resX)x\(resY))")
                        return
                    }
                }
                self._size26d6 = charSize
                self._dpi = (resX, resY)
                assert(self.numGlyphs == Int(face.pointee.num_glyphs))
                self.clearCacheInternal()
            }
        }
    }

    /// calculate kern advance between characters.
    public func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        var point: CGPoint = .zero
        self.face.withLock {
            let face = $0.face
            if FT_HAS_KERNING(face) {
                let index1 = FT_Get_Char_Index(face, FT_ULong(left.value))
                let index2 = FT_Get_Char_Index(face, FT_ULong(right.value))
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
        if self.kerningEnabled {
            var c1 = UnicodeScalar(UInt8(0))
            for c2 in text.unicodeScalars {
                if let glyph = self.glyph(for: c2) {
                    length += glyph.advance.width
                    length += self.kernAdvance(left: c1, right: c2).x
                }
                c1 = c2
            }
        } else {
            text.unicodeScalars.forEach {
                if let glyph = self.glyph(for: $0) {
                    length += glyph.advance.width
                }
            }
        }
        return length
    }

    var metrics: FT_Size_Metrics {
        self.face.withLock {
            $0.face.pointee.size.pointee.metrics
        }
    }

    /// pixel-height of text. not includes outline.
    public func lineHeight() -> CGFloat {
        return ft26d6ToFloat(self.metrics.height)
    }

    /// text bounding box.
    public func bounds(of text: String) -> CGRect {
        CGRect(x: 0, y: 0, width: lineWidth(of: text), height: lineHeight())
    }

    /// The distance from the baseline to the highest or upper grid coordinate used to place an outline point.
    public var ascender: CGFloat {
        return ft26d6ToFloat(self.metrics.ascender)
    }

    /// The distance from the baseline to the lowest grid coordinate used to place an outline point.
    public var descender: CGFloat {
        return ft26d6ToFloat(self.metrics.descender)
    }

    public var maxAdvance: CGFloat  {
        return ft26d6ToFloat(self.metrics.max_advance)
    }

    public var height: CGFloat  {
        return ft26d6ToFloat(self.metrics.height)
    }

    /// font pixel-width (includes outline)
    public var glyphMaxWidth: CGFloat {
        return ft26d6ToFloat(self.metrics.max_advance)
    }

    /// font pixel-height (includes outline)
    public var glyphMaxHeight: CGFloat  {
        return ft26d6ToFloat(self.metrics.height)
    }

    public var xScale: CGFloat {
        return ft16d16ToFloat(self.metrics.x_scale)
    }

    public var yScale: CGFloat {
        return ft16d16ToFloat(self.metrics.y_scale)
    }

    public var xPixelsPerEM: Int {
        return Int(self.metrics.x_ppem)
    }

    public var yPixelsPerEM: Int {
        return Int(self.metrics.y_ppem)
    }

    public func hasGlyph(for c: UnicodeScalar) -> Bool {
        self.face.withLock {
            FT_Get_Char_Index($0.face, FT_ULong(c.value)) != 0
        }
    }

    public func glyph(for c: UnicodeScalar) -> Glyph? {
        if c.value == 0 { return nil }
        return self.face.withLock {
            let face = $0.face
            if let glyph = self.loadedGlyphs[c] {
                return glyph
            }

            let index = if face.pointee.charmap != nil {
                FT_Get_Char_Index(face, FT_ULong(c.value))
            } else {
                FT_UInt(c.value)
            }
            // loading font.
            let loadFlags = self.forceBitmap ? FT_Int32(FT_LOAD_RENDER) : FT_Int32(FT_LOAD_DEFAULT)
            if FT_Load_Glyph(face, index, loadFlags) != 0 {
                Log.err("Failed to load glyph for char=\(c)(0x\(String(format: "%x", c.value)))")
                return nil
            }

            let advance = CGSize(width: ft26d6ToFloat(face.pointee.glyph.pointee.advance.x),
                                 height: ft26d6ToFloat(face.pointee.glyph.pointee.advance.y))

            let metrics = face.pointee.size.pointee.metrics
            let ascender = ft26d6ToFloat(metrics.ascender)
            let descender = ft26d6ToFloat(metrics.descender)

            self.loadedGlyphs[c] = Glyph(advance: advance,
                                         ascender: ascender,
                                         descender: descender)
            return self.loadedGlyphs[c]
        }
    }

    public enum BitmapPixelMode: Sendable{
        case gray
        case bgra
    }

    public struct BitmapInfo {
        public var left: Int
        public var top: Int         // distance from baseline
        public var width: UInt32    // bitmap width
        public var rows: UInt32     // bitmap height
        public var pixelMode: BitmapPixelMode
    }

    public func loadBitmap(for c: UnicodeScalar,
                           embolden: CGFloat,
                           outline: CGFloat,
                           callback: (UnsafePointer<UInt8>,
                                      Glyph,
                                      BitmapInfo,
                                      SizeMetrics)->Void) -> Bool {
        if c.value == 0 { return false }
        return self.face.withLock {
            let face = $0.face
            let index = if face.pointee.charmap != nil {
                FT_Get_Char_Index(face, FT_ULong(c.value))
            } else {
                FT_UInt(c.value)
            }
            // loading font.
            let loadFlags = self.forceBitmap ? FT_Int32(FT_LOAD_RENDER) : FT_Int32(FT_LOAD_DEFAULT)
            if FT_Load_Glyph(face, index, loadFlags) != 0 {
                Log.err("Failed to load glyph for char=\(c)(0x\(String(format: "%x", c.value)))")
                return false
            }

            let advance = CGSize(width: ft26d6ToFloat(face.pointee.glyph.pointee.advance.x),
                                 height: ft26d6ToFloat(face.pointee.glyph.pointee.advance.y))
            var bitmapInfo = BitmapInfo(left: 0, top: 0, width: 0, rows: 0, pixelMode: .gray)
            var bitmapData: [UInt8] = []

            let boldStrength = ft26d6(embolden)

            if face.pointee.glyph.pointee.format == FT_GLYPH_FORMAT_OUTLINE {
                face.pointee.glyph.pointee.outline.flags |= FT_OUTLINE_HIGH_PRECISION
                if outline > 0.0 {
                    // create outline stroker, drawing outline as bitmap.
                    FT_Outline_Embolden(&face.pointee.glyph.pointee.outline, boldStrength)
                    var stroker: FT_Stroker? = nil
                    FT_Stroker_New(library.library, &stroker)
                    FT_Stroker_Set(stroker, ft26d6(outline), FT_STROKER_LINECAP_ROUND, FT_STROKER_LINEJOIN_ROUND, 0)
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
                    let left  = Int(cbox.xMin >> 6)  // left offset of glyph
                    let top   = Int(cbox.yMax >> 6)  // upper of offset of glyph (height for origin)

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
                        bitmapInfo.left = left
                        bitmapInfo.top = top
                        bitmapInfo.width = ftBitmap.width
                        bitmapInfo.rows = ftBitmap.rows
                        bitmapInfo.pixelMode = .gray
                        bitmapData = .init(UnsafeMutableBufferPointer(start: ftBitmap.buffer,
                                                                      count: bufferSize))
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

                        bitmapInfo.left = Int(glyphBitmap.pointee.left)
                        bitmapInfo.top = Int(glyphBitmap.pointee.top)
                        bitmapInfo.width = glyphBitmap.pointee.bitmap.width
                        bitmapInfo.rows = glyphBitmap.pointee.bitmap.rows
                        bitmapInfo.pixelMode = .gray
                        var bufferSize = Int(bitmapInfo.width) * Int(bitmapInfo.rows)
                        if glyphBitmap.pointee.bitmap.pixel_mode == FT_PIXEL_MODE_BGRA.rawValue {
                            bitmapInfo.pixelMode = .bgra
                            bufferSize = bufferSize * 4
                        }
                        bitmapData = .init(UnsafeMutableBufferPointer(start: glyphBitmap.pointee.bitmap.buffer,
                                                                      count: bufferSize))
                    }
                    FT_Done_Glyph(glyph)
                }
            } else {
                if FT_Render_Glyph(face.pointee.glyph, FT_RENDER_MODE_NORMAL) == 0 {
                    let outline = outline.rounded()
                    if outline > 0.0 {
                        let outerSize = ft26d6(embolden + (outline * 2))
                        let innerSize = ft26d6(embolden - (outline * 2))
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
                        bitmapInfo.left = Int(face.pointee.glyph.pointee.bitmap_left) - Int(outline)
                        bitmapInfo.top = Int(face.pointee.glyph.pointee.bitmap_top) - Int(outline)
                        bitmapInfo.width = outer.width
                        bitmapInfo.rows = outer.rows
                        bitmapInfo.pixelMode = .gray
                        let bufferSize = Int(bitmapInfo.width) * Int(bitmapInfo.rows)
                        bitmapData = .init(UnsafeMutableBufferPointer(start: outer.buffer,
                                                                      count: bufferSize))

                        FT_Bitmap_Done(library.library, &inner)
                        FT_Bitmap_Done(library.library, &outer)

                    } else {
                        FT_Bitmap_Embolden(library.library, &(face.pointee.glyph.pointee.bitmap), boldStrength, boldStrength)
                        bitmapInfo.width = face.pointee.glyph.pointee.bitmap.width
                        bitmapInfo.rows = face.pointee.glyph.pointee.bitmap.rows
                        bitmapInfo.left = Int(face.pointee.glyph.pointee.bitmap_left)
                        bitmapInfo.top = Int(face.pointee.glyph.pointee.bitmap_top)
                        bitmapInfo.pixelMode = .gray
                        var bufferSize = Int(bitmapInfo.width) * Int(bitmapInfo.rows)
                        if face.pointee.glyph.pointee.bitmap.pixel_mode == FT_PIXEL_MODE_BGRA.rawValue {
                            bitmapInfo.pixelMode = .bgra
                            bufferSize = bufferSize * 4
                        }
                        bitmapData = .init(UnsafeMutableBufferPointer(start: face.pointee.glyph.pointee.bitmap.buffer,
                                                                      count: bufferSize))
                    }
                }
            }

            let metrics = baseMetrics(for: face)
            let glyph = Glyph(advance: advance,
                              ascender: metrics.ascender,
                              descender: metrics.descender)
            self.loadedGlyphs[c] = glyph
            callback(bitmapData, glyph, bitmapInfo, metrics)
            return true
        }
    }

    public struct SizeMetrics: Sendable {
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
        self.face.withLock { baseMetrics(for: $0.face) }
    }

    private func baseMetrics(for face: FT_Face) -> SizeMetrics {
        let metrics = face.pointee.size.pointee.metrics
        return SizeMetrics(xPixelsPerEM: Int(metrics.x_ppem),
                           yPixelsPerEM: Int(metrics.y_ppem),
                           xScale: ft16d16ToFloat(metrics.x_scale),
                           yScale: ft16d16ToFloat(metrics.y_scale),
                           ascender: ft26d6ToFloat(metrics.ascender),
                           descender: ft26d6ToFloat(metrics.descender),
                           height: ft26d6ToFloat(metrics.height),
                           maxAdvance: ft26d6ToFloat(metrics.max_advance))
    }

    public enum Path {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    }

    @discardableResult
    public func decompose(callback: (Path)->Void) -> Bool {
        self.face.withLock {
            let face = $0.face
            typealias Callback = (Path)->Void

            var fn = FT_Outline_Funcs()
            fn.move_to = { (to: UnsafePointer<FT_Vector>?,
                            ctxt: UnsafeMutableRawPointer?)->Int32 in
                let cb = unsafeBitCast(ctxt!, to: AnyObject.self) as! Callback
                let v = to!.pointee
                cb(.move(to: CGPoint(v)))
                return 0
            }
            fn.line_to = { (to: UnsafePointer<FT_Vector>?,
                            ctxt: UnsafeMutableRawPointer?)->Int32 in
                let cb = unsafeBitCast(ctxt!, to: AnyObject.self) as! Callback
                let v = to!.pointee
                cb(.line(to: CGPoint(v)))
                return 0
            }
            fn.conic_to = { (ctl: UnsafePointer<FT_Vector>?,
                             to: UnsafePointer<FT_Vector>?,
                             ctxt: UnsafeMutableRawPointer?)->Int32 in
                let cb = unsafeBitCast(ctxt!, to: AnyObject.self) as! Callback
                let v = to!.pointee
                let c = ctl!.pointee
                cb(.quadCurve(to: CGPoint(v), control: CGPoint(c)))
                return 0
            }
            fn.cubic_to = { (ctl1: UnsafePointer<FT_Vector>?,
                             ctl2: UnsafePointer<FT_Vector>?,
                             to: UnsafePointer<FT_Vector>?,
                             ctxt: UnsafeMutableRawPointer?)->Int32 in
                let cb = unsafeBitCast(ctxt!, to: AnyObject.self) as! Callback
                let v = to!.pointee
                let c1 = ctl1!.pointee
                let c2 = ctl2!.pointee
                cb(.curve(to: CGPoint(v), control1: CGPoint(c1), control2: CGPoint(c2)))
                return 0
            }
            fn.shift = 0
            fn.delta = 0

            var outline = face.pointee.glyph.pointee.outline
            let ctxt = unsafeBitCast(callback as AnyObject, to: UnsafeMutableRawPointer.self)
            let error = FT_Outline_Decompose(&outline, &fn, ctxt)
            return error == 0
        }
    }
}
