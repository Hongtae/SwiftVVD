import Foundation

public class Frame {
    public var rect: CGRect        { .zero }
    public var bounds: CGRect       { .zero }
    public var transform: Matrix3   { .identity }

    public var resolution: CGSize   { .zero }
    public var contentScale: CGSize { .zero }

    public var color: Color = .black
    public var pixelFormat: PixelFormat = .rgba8Unorm

    public init() {
    }
}
