public class Color {
    public var red : Float = 0.0
    public var green : Float = 0.0
    public var blue : Float = 0.0
    public var alpha : Float = 1.0

    public init() {
        self.red = 0.0
        self.green = 0.0
        self.blue = 0.0
        self.alpha = 1.0
    }

    public init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static func make(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float) -> Color {
        return Color(red: red, green: green, blue: blue, alpha: alpha)
    }
    static var black: Color { return .make(0.0, 0.0, 0.0, 1.0) }
    static var white: Color { return .make(1.0, 1.0, 1.0, 1.0) }
}
