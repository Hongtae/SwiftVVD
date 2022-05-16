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

public class Font {

    private let library: FTLibrary
    private var face: FT_Face
    private var fontData: Data?

    public let device: GraphicsDevice
    public let familyName: String
    public let styleName: String

    public private(set) var outline: Float
    public private(set) var embolden: Float
    public private(set) var dpi: (x: UInt32, y: UInt32)
    public private(set) var kerningEnabled: Bool
    public private(set) var forceBitmap: Bool

    private var size26d6: FT_F26Dot6
    public var pointSize: Float {
        Float(size26d6 >> 6) + Float(size26d6 & 63) / 64.0
    }

    public init?(device: GraphicsDevice, path: String) {
        
        self.outline = 0.0
        self.embolden = 0.0
        self.size26d6 = 10 * 64
        self.dpi = (72, 72)
        self.kerningEnabled = true
        self.forceBitmap = false

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
        if FT_Set_Char_Size(face, 0, size26d6, dpi.x, dpi.y) != 0 {
            Log.warn("Failed to initialize font style, You should call Font.setStyle() manually.")
        }
        self.library = library
        self.device = device
        self.face = face!
        self.familyName = .init(cString: face!.pointee.family_name)
        self.styleName = .init(cString: face!.pointee.style_name)
    }

    public init?(device: GraphicsDevice, data: Data) {

        self.outline = 0.0
        self.embolden = 0.0
        self.size26d6 = 10 * 64
        self.dpi = (72, 72)
        self.kerningEnabled = true
        self.forceBitmap = false
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
        if FT_Set_Char_Size(face, 0, size26d6, dpi.x, dpi.y) != 0 {
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

    public func lineWidth(text: String) -> Float {
        return 0.0        
    }

    public func lineHeight() -> Float {
        return 0.0
    }

    public func bounds(text: String) -> CGRect {
        return .zero
    }

    public var ascender: Float { 0.0 }
    public var descender: Float { 0.0 }
    public var width: Float { 0.0 }
    public var height: Float { 0.0 }

    public func clearCache() {}
}