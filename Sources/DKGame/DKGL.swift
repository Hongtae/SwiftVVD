import FreeType

public struct DKGame {
    public private(set) var text = "Hello, DKGL!"

    public init() {
        let library : FT_Library
        FT_Init_FreeType(nil)
    }
}
