import Foundation
import FreeType

class FTLibrary {
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

    struct GlyphData {

    }
    struct GlyphTextureAtlas {

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

    public func lineWidth(text: String) -> Float {
        return 0.0
    }

    public func lineHeight() -> Float {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.height) + ceil(_embolden) * 2.0
    }

    public func bounds(text: String) -> CGRect {
        return .zero
    }

    public var ascender: Float {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.ascender)
    }

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

    public var glyphMaxWidth: Float {
        let metrics = self.face.pointee.size.pointee.metrics
        return ft26d6ToFloat(metrics.max_advance) + (ceil(_embolden) + ceil(_outline)) * 2.0
    }

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
}
