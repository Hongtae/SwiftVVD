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

@inline(__always)
private func ft26d6ToFloat(_ value: FT_F26Dot6) -> CGFloat {
    CGFloat(value >> 6) + CGFloat(value & 63) / 64.0
}

@inline(__always)
private func ft26d6(_ value: CGFloat) -> FT_F26Dot6 {
    FT_F26Dot6(value * 64.0)
}

@inline(__always)
private func ft26d6Floor(_ value: FT_F26Dot6) -> FT_F26Dot6 {
    value & ~63
}

@inline(__always)
private func ft26d6Round(_ value: FT_F26Dot6) -> FT_F26Dot6 {
    ft26d6Floor(value + 32)
}

@inline(__always)
private func ft26d6Ceil(_ value: FT_F26Dot6) -> FT_F26Dot6 {
    ft26d6Floor(value + 63)
}

@inline(__always)
private func ft16d16ToFloat(_ value: FT_Fixed) -> CGFloat {
    CGFloat(value >> 16) + CGFloat(value & 65535) / 65536.0
}

@inline(__always)
private func ft16d16(_ value: CGFloat) -> FT_Fixed {
    FT_Fixed(value * 65536.0)
}

@inline(__always)
private func FT_HAS_KERNING(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_KERNING != 0
}

@inline(__always)
private func FT_IS_SCALABLE(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_SCALABLE != 0
}

@inline(__always)
private func FT_IS_FIXED_WIDTH(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_FIXED_WIDTH != 0
}

@inline(__always)
private func FT_HAS_FIXED_SIZES(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_FIXED_SIZES != 0
}

@inline(__always)
private func FT_HAS_COLOR(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_COLOR != 0
}

private extension CGPoint {
    init(_ vector: FT_Vector) {
        self.init(x: CGFloat(vector.x), y: CGFloat(vector.y))
    }
    init(ft26d6: FT_Vector) {
        self.init(x: ft26d6ToFloat(ft26d6.x), y: ft26d6ToFloat(ft26d6.y))
    }
    init(ft16d16: FT_Vector) {
        self.init(x: ft16d16ToFloat(ft16d16.x), y: ft16d16ToFloat(ft16d16.y))
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

    public var isBitmapPreferred: Bool = false {
        didSet { if oldValue != isBitmapPreferred { self.clearCache() } }
    }
    public var isKerningEnabled: Bool = true {
        didSet { if oldValue != isKerningEnabled { self.clearCache() } }
    }
    public var isColorEnabled: Bool = true {
        didSet { if oldValue != isColorEnabled { self.clearCache() } }
    }
    public var hasColor: Bool {
        self.face.withLock { FT_HAS_COLOR($0.face) }
    }

    private var _size26d6: FT_F26Dot6
    private var _dpi: DPI

    public struct GlyphMetrics: Sendable {
        public let index: UInt32        // glyph index (FT_UInt)
        public let advance: CGSize      // distance to next glyph
        public let bearing: CGPoint     // offset from baseline (left, top)
        public let size: CGSize         // glyph size (width, height)
        public let ascender: CGFloat    // upper distance from baseline
        public let descender: CGFloat   // lower distance from baseline (negative direction)
    }

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

    internal func clearCacheLocked() {
    }

    public func clearCache() {
        self.withFaceLock {
            self.clearCacheLocked()
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
                self.clearCacheLocked()
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
    public func lineWidth(of text: String,
                          embolden: CGFloat = 0) -> CGFloat {
        var length: CGFloat = 0.0
        if self.isKerningEnabled {
            var c1 = UnicodeScalar(UInt8(0))
            for c2 in text.unicodeScalars {
                if let metrics = self.glyphMetrics(for: c2,
                                                   embolden: embolden) {
                    length += metrics.advance.width
                    length += self.kernAdvance(left: c1, right: c2).x
                }
                c1 = c2
            }
        } else {
            text.unicodeScalars.forEach {
                if let metrics = self.glyphMetrics(for: $0,
                                                   embolden: embolden) {
                    length += metrics.advance.width
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

    private func _glyphMetrics(from face: FT_Face,
                               index: UInt32,
                               embolden: CGFloat = 0) -> GlyphMetrics {
        assert(face.pointee.glyph != nil)
        let metrics = face.pointee.glyph.pointee.metrics
        let strength = ft26d6ToFloat(ft26d6(embolden))
        let advance = CGSize(
            width: ft26d6ToFloat(metrics.horiAdvance) + strength,
            height: ft26d6ToFloat(metrics.vertAdvance) + strength)
        let bearing = CGPoint(
            x: ft26d6ToFloat(metrics.horiBearingX),
            y: ft26d6ToFloat(metrics.horiBearingY) + strength)
        let size = CGSize(
            width: ft26d6ToFloat(metrics.width) + strength,
            height: ft26d6ToFloat(metrics.height) + strength)

        let faceMetrics = face.pointee.size.pointee.metrics
        let ascender = ft26d6ToFloat(faceMetrics.ascender)
        let descender = ft26d6ToFloat(faceMetrics.descender)

        return GlyphMetrics(index: index,
                            advance: advance,
                            bearing: bearing,
                            size: size,
                            ascender: ascender,
                            descender: descender)
    }

    public func glyphMetrics(for c: UnicodeScalar,
                             embolden: CGFloat = 0) -> GlyphMetrics? {
        if c.value == 0 { return nil }
        return self.face.withLock {
            let face = $0.face
            let index = if face.pointee.charmap != nil {
                FT_Get_Char_Index(face, FT_ULong(c.value))
            } else {
                FT_UInt(c.value)
            }
            // loading font.
            var loadFlags = self.isBitmapPreferred ? FT_Int32(FT_LOAD_RENDER) : FT_Int32(FT_LOAD_DEFAULT)
            if self.isColorEnabled && FT_HAS_COLOR(face) { loadFlags |= FT_Int32(FT_LOAD_COLOR) }
            if FT_Load_Glyph(face, index, loadFlags) != 0 {
                Log.err("Failed to load glyph for char=\(c)(0x\(String(format: "%x", c.value)))")
                return nil
            }

            return _glyphMetrics(from: face,
                                 index: UInt32(index),
                                 embolden: embolden)
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

    private func _makeStrokedOutline(
        from source: inout FT_Outline,
        radius: CGFloat) -> FT_Outline? {
        guard radius > .ulpOfOne else { return nil }

        var stroker: FT_Stroker? = nil
        guard FT_Stroker_New(library.library, &stroker) == 0,
              let stroker else {
            return nil
        }
        defer { FT_Stroker_Done(stroker) }

        FT_Stroker_Set(stroker,
                       ft26d6(radius),
                       FT_STROKER_LINECAP_ROUND,
                       FT_STROKER_LINEJOIN_ROUND,
                       0)
        guard FT_Stroker_ParseOutline(stroker, &source, 0) == 0 else {
            return nil
        }

        var points: FT_UInt = 0
        var contours: FT_UInt = 0
        guard FT_Stroker_GetCounts(stroker, &points, &contours) == 0 else {
            return nil
        }

        var outline = FT_Outline()
        guard FT_Outline_New(library.library,
                             points,
                             FT_Int(contours),
                             &outline) == 0 else {
            return nil
        }
        outline.n_contours = 0
        outline.n_points = 0
        FT_Stroker_Export(stroker, &outline)
        return outline
    }

    public func withGlyphBitmap(
        for c: UnicodeScalar,
        embolden: CGFloat,
        outline: CGFloat,
        _ body: (UnsafePointer<UInt8>,
                 GlyphMetrics,
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
            var loadFlags = self.isBitmapPreferred ? FT_Int32(FT_LOAD_RENDER) : FT_Int32(FT_LOAD_DEFAULT)
            if self.isColorEnabled && FT_HAS_COLOR(face) { loadFlags |= FT_Int32(FT_LOAD_COLOR) }
            if FT_Load_Glyph(face, index, loadFlags) != 0 {
                Log.err("Failed to load glyph for char=\(c)(0x\(String(format: "%x", c.value)))")
                return false
            }

            let advance = CGSize(width: ft26d6ToFloat(face.pointee.glyph.pointee.advance.x),
                                 height: ft26d6ToFloat(face.pointee.glyph.pointee.advance.y))
            var bitmapInfo = BitmapInfo(left: 0, top: 0, width: 0, rows: 0, pixelMode: .gray)
            var bitmapData: [UInt8] = []
            var bitmapLoaded = false

            let copyBitmapRows = { (bitmap: FT_Bitmap, bytesPerPixel: Int) -> [UInt8]? in
                let width = Int(bitmap.width)
                let rows = Int(bitmap.rows)
                if width == 0 || rows == 0 { return [] }
                guard let buffer = bitmap.buffer else { return nil }

                let rowBytes = width * bytesPerPixel
                let pitch = Int(bitmap.pitch)
                guard abs(pitch) >= rowBytes else { return nil }

                var data = [UInt8](repeating: 0, count: rowBytes * rows)
                var src = buffer
                if pitch < 0 {
                    src = src.advanced(by: -pitch * (rows - 1))
                }
                data.withUnsafeMutableBytes {
                    guard let base = $0.baseAddress else { return }
                    for row in 0..<rows {
                        let dst = base.advanced(by: row * rowBytes)
                        dst.copyMemory(from: src, byteCount: rowBytes)
                        src = src.advanced(by: pitch)
                    }
                }
                return data
            }

            let normalizeGrayLevels = { (data: inout [UInt8], numGrays: UInt32) in
                let levels = Int(numGrays)
                if levels > 1 && levels < 256 {
                    for i in data.indices {
                        data[i] = UInt8((Int(data[i]) * 255) / (levels - 1))
                    }
                }
            }

            let normalizedBitmap = { (bitmap: FT_Bitmap) -> (data: [UInt8], width: UInt32, rows: UInt32, pixelMode: BitmapPixelMode)? in
                switch bitmap.pixel_mode {
                case UInt8(FT_PIXEL_MODE_GRAY.rawValue):
                    guard var data = copyBitmapRows(bitmap, 1) else { return nil }
                    normalizeGrayLevels(&data, UInt32(bitmap.num_grays))
                    return (data, bitmap.width, bitmap.rows, .gray)
                case UInt8(FT_PIXEL_MODE_BGRA.rawValue):
                    guard let data = copyBitmapRows(bitmap, 4) else { return nil }
                    return (data, bitmap.width, bitmap.rows, .bgra)
                default:
                    var source = bitmap
                    var converted = FT_Bitmap()
                    FT_Bitmap_Init(&converted)
                    defer { FT_Bitmap_Done(self.library.library, &converted) }

                    if FT_Bitmap_Convert(self.library.library, &source, &converted, 1) != 0 {
                        Log.err("Failed to convert glyph bitmap pixel mode: \(bitmap.pixel_mode)")
                        return nil
                    }
                    guard var data = copyBitmapRows(converted, 1) else { return nil }
                    normalizeGrayLevels(&data, UInt32(converted.num_grays))
                    return (data, converted.width, converted.rows, .gray)
                }
            }

            let setBitmap = { (bitmap: FT_Bitmap, left: Int, top: Int) -> Bool in
                guard let normalized = normalizedBitmap(bitmap) else { return false }
                bitmapInfo.left = left
                bitmapInfo.top = top
                bitmapInfo.width = normalized.width
                bitmapInfo.rows = normalized.rows
                bitmapInfo.pixelMode = normalized.pixelMode
                bitmapData = normalized.data
                return true
            }

            let boldStrength = ft26d6(embolden)

            if face.pointee.glyph.pointee.format == FT_GLYPH_FORMAT_OUTLINE {
                face.pointee.glyph.pointee.outline.flags |= FT_OUTLINE_HIGH_PRECISION
                if outline > .ulpOfOne {
                    // create outline stroker, drawing outline as bitmap.
                    FT_Outline_Embolden(&face.pointee.glyph.pointee.outline, boldStrength)
                    guard var ftOutline = _makeStrokedOutline(
                        from: &face.pointee.glyph.pointee.outline,
                        radius: outline) else {
                        return false
                    }
                    defer {
                        FT_Outline_Done(library.library, &ftOutline)
                    }

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
                        bitmapLoaded = setBitmap(ftBitmap, left, top)
                    }

                    ftBitmap.buffer.deallocate()
                    ftBitmap.buffer = nil
                    FT_Bitmap_Done(library.library, &ftBitmap)
                } else {
                    FT_Outline_Embolden(&face.pointee.glyph.pointee.outline, boldStrength)

                    var glyph: FT_Glyph? = nil
                    FT_Get_Glyph(face.pointee.glyph, &glyph)
                    if FT_Glyph_To_Bitmap(&glyph, FT_RENDER_MODE_NORMAL, nil, 1) == 0 {
                        let glyphBitmap: FT_BitmapGlyph = withUnsafeBytes(of: glyph!) {
                            $0.baseAddress!.assumingMemoryBound(to: FT_BitmapGlyph.self).pointee
                        }

                        bitmapLoaded = setBitmap(glyphBitmap.pointee.bitmap,
                                                 Int(glyphBitmap.pointee.left),
                                                 Int(glyphBitmap.pointee.top))
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
                        bitmapLoaded = setBitmap(outer,
                                                 Int(face.pointee.glyph.pointee.bitmap_left) - Int(outline),
                                                 Int(face.pointee.glyph.pointee.bitmap_top) - Int(outline))

                        FT_Bitmap_Done(library.library, &inner)
                        FT_Bitmap_Done(library.library, &outer)

                    } else {
                        FT_Bitmap_Embolden(library.library, &(face.pointee.glyph.pointee.bitmap), boldStrength, boldStrength)
                        bitmapLoaded = setBitmap(face.pointee.glyph.pointee.bitmap,
                                                 Int(face.pointee.glyph.pointee.bitmap_left),
                                                 Int(face.pointee.glyph.pointee.bitmap_top))
                    }
                }
            }
            guard bitmapLoaded else {
                Log.warn("Failed to load bitmap for char=\(c)(0x\(String(format: "%x", c.value)))")
                return false
            }

            let metrics = baseMetrics(for: face)
            let slotMetrics = face.pointee.glyph.pointee.metrics
            let glyphMetrics = GlyphMetrics(
                index: UInt32(index),
                advance: advance,
                bearing: CGPoint(
                    x: ft26d6ToFloat(slotMetrics.horiBearingX),
                    y: ft26d6ToFloat(slotMetrics.horiBearingY)),
                size: CGSize(
                    width: ft26d6ToFloat(slotMetrics.width),
                    height: ft26d6ToFloat(slotMetrics.height)),
                ascender: metrics.ascender,
                descender: metrics.descender)
            body(bitmapData, glyphMetrics, bitmapInfo, metrics)
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

    public enum OutlineCommand: Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    }

    /// Decomposes an optionally emboldened or stroked glyph outline into path
    /// commands and returns its metrics.
    /// Contours are implicitly closed. Coordinates are baseline-relative with +Y up.
    public func decomposeGlyphOutline(
        for c: UnicodeScalar,
        embolden: CGFloat = 0,
        outline: CGFloat = 0,
        _ body: (OutlineCommand) -> Void) -> GlyphMetrics? {
        var commands: [OutlineCommand] = []
        let metrics: GlyphMetrics? = self.face.withLock {
            let face = $0.face

            let index = face.pointee.charmap != nil
                ? FT_Get_Char_Index(face, FT_ULong(c.value)) : FT_UInt(c.value)

            guard index != 0 else { return nil }

            let loadFlags = FT_Int32(FT_LOAD_DEFAULT) |
                            FT_Int32(FT_LOAD_NO_BITMAP)
            guard FT_Load_Glyph(face, index, loadFlags) == 0 else {
                return nil
            }
            guard face.pointee.glyph.pointee.format == FT_GLYPH_FORMAT_OUTLINE else {
                return nil
            }

            let strength = ft26d6(embolden)
            if strength != 0 {
                guard FT_Outline_Embolden(
                    &face.pointee.glyph.pointee.outline,
                    strength) == 0 else {
                    return nil
                }
            }

            var sourceOutline = face.pointee.glyph.pointee.outline
            var decomposedOutline = sourceOutline
            var ownsDecomposedOutline = false
            if outline > .ulpOfOne {
                guard let strokedOutline = _makeStrokedOutline(
                    from: &sourceOutline,
                    radius: outline) else {
                    return nil
                }
                decomposedOutline = strokedOutline
                ownsDecomposedOutline = true
            }
            defer {
                if ownsDecomposedOutline {
                    FT_Outline_Done(library.library, &decomposedOutline)
                }
            }

            var fn = FT_Outline_Funcs()
            fn.move_to = { (to: UnsafePointer<FT_Vector>?,
                            ctxt: UnsafeMutableRawPointer?)->Int32 in
                let commands = ctxt!.assumingMemoryBound(to: [OutlineCommand].self)
                let v = to!.pointee
                commands.pointee.append(.move(to: CGPoint(ft26d6: v)))
                return 0
            }
            fn.line_to = { (to: UnsafePointer<FT_Vector>?,
                            ctxt: UnsafeMutableRawPointer?)->Int32 in
                let commands = ctxt!.assumingMemoryBound(to: [OutlineCommand].self)
                let v = to!.pointee
                commands.pointee.append(.line(to: CGPoint(ft26d6: v)))
                return 0
            }
            fn.conic_to = { (ctl: UnsafePointer<FT_Vector>?,
                             to: UnsafePointer<FT_Vector>?,
                             ctxt: UnsafeMutableRawPointer?)->Int32 in
                let commands = ctxt!.assumingMemoryBound(to: [OutlineCommand].self)
                let v = to!.pointee
                let c = ctl!.pointee
                commands.pointee.append(
                    .quadCurve(to: CGPoint(ft26d6: v),
                               control: CGPoint(ft26d6: c)))
                return 0
            }
            fn.cubic_to = { (ctl1: UnsafePointer<FT_Vector>?,
                             ctl2: UnsafePointer<FT_Vector>?,
                             to: UnsafePointer<FT_Vector>?,
                             ctxt: UnsafeMutableRawPointer?)->Int32 in
                let commands = ctxt!.assumingMemoryBound(to: [OutlineCommand].self)
                let v = to!.pointee
                let c1 = ctl1!.pointee
                let c2 = ctl2!.pointee
                commands.pointee.append(
                    .curve(to: CGPoint(ft26d6: v),
                           control1: CGPoint(ft26d6: c1),
                           control2: CGPoint(ft26d6: c2)))
                return 0
            }
            fn.shift = 0
            fn.delta = 0

            let error = withUnsafeMutablePointer(to: &commands) {
                FT_Outline_Decompose(&decomposedOutline,
                                     &fn,
                                     UnsafeMutableRawPointer($0))
            }
            if error == 0 {
                return _glyphMetrics(from: face,
                                     index: UInt32(index),
                                     embolden: embolden)
            }
            return nil
        }
        guard let metrics else { return nil }

        commands.forEach(body)
        return metrics
    }
}
