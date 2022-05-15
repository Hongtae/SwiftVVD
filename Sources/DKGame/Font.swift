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
    private var face: FT_Face?
    private var fontData: Data?

    public let device: GraphicsDevice

    public private(set) var outline: Float
    public private(set) var embolden: Float
    public private(set) var size26d6: UInt32
    public private(set) var dpi: (UInt32, UInt32)
    public private(set) var kerningEnabled: Bool
    public private(set) var forceBitmap: Bool


    public init(device: GraphicsDevice, path: String) {
        self.library = sharedFTLibrary()
        self.device = device
        self.outline = 0.0
        self.embolden = 0.0
        self.size26d6 = 10 * 64
        self.dpi = (72, 72)
        self.kerningEnabled = true
        self.forceBitmap = false
    }

    public init(device: GraphicsDevice, data: Data) {
        self.library = sharedFTLibrary()
        self.device = device
        self.outline = 0.0
        self.embolden = 0.0
        self.size26d6 = 10 * 64
        self.dpi = (72, 72)
        self.kerningEnabled = true
        self.forceBitmap = false
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
    public var familyName: String { "" }
    public var styleName: String { "" }
    public var width: Float { 0.0 }
    public var height: Float { 0.0 }

    public func clearCache() {}
}