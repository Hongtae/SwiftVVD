import Foundation

private typealias WindowProtocol = Window

extension macOS {
    public class Window : WindowProtocol {

        public var contentRect: CGRect = .null
        public var windowRect: CGRect = .null
        public var contentScaleFactor: Float = 1.0

        public var origin: CGPoint = .zero
        public var contentSize: CGSize = .zero

        public private(set) weak var delegate: WindowDelegate?

        public init () {
            
        }
        public func show() {}
        public func hide() {}
        public func activate() {}
        public func minimize() {}
    }
}
