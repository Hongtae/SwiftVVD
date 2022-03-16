public struct Color {
    public var r : Float = 0.0
    public var g : Float = 0.0
    public var b : Float = 0.0
    public var a : Float = 1.0

    public static func make(_ r: Float, _ g: Float, _ b: Float, _ a: Float) -> Color {
        return Color(r: r, g: g, b: b, a: a)
    }

    public static let black: Color = .make(0.0, 0.0, 0.0, 1.0)
    public static let white: Color = .make(1.0, 1.0, 1.0, 1.0)
}
