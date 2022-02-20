import Foundation

private typealias WindowProtocol = Window

extension Linux {
    public class Window : WindowProtocol {

        public var contentRect: CGRect = .null
        public var windowRect: CGRect = .null
        public var contentScaleFactor: Float = 1.0
        public private(set) weak var delegate: WindowDelegate?

        public init () {
            
        }
        public func show() {}
        public func hide() {}
    }
}
