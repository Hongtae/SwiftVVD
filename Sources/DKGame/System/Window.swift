import Foundation

public enum DragOperation {
    case reject
    case none
    case copy
    case move
    case link
}

public protocol DragTargetDelegate {
    func draggingEntered(target: Window, position: CGPoint, files: [String]) -> DragOperation
    func draggingUpdated(target: Window, position: CGPoint, files: [String]) -> DragOperation
    func draggingDropped(target: Window, position: CGPoint, files: [String]) -> DragOperation
    func draggingExited(target: Window, files: [String])
}

public enum MouseEventType {
    case buttonDown
    case buttonUp
    case move
    case wheel
    case pointing
}

public enum MouseEventDevice {
    case unknown
    case genericMouse
    case stylus
    case touch
}

public struct MouseEvent {
    var type: MouseEventType
    var device: MouseEventDevice
    var deviceId: Int
    var buttonId: Int
    var location: CGPoint
    var delta: CGPoint = .zero
    var pressure: Float = 0.0
    var tilt: Float = 0.0
}

public enum KeyboardEventType {
    case keyDown
    case keyUp
    case textInput
    case textComposition
}

public struct KeyboardEvent {
    var type: KeyboardEventType
    var deviceId: Int
    var key: VirtualKey
    var text: String
}

public enum WindowEventType {
    case created
    case closed
    case hidden
    case shown
    case activated
    case inactivated
    case minimized
    case moved
    case resized
    case update
}

public struct WindowEvent {
    var type: WindowEventType
    var windowRect: CGRect
    var contentRect: CGRect
    var contentScaleFactor: Float
}

public protocol WindowDelegate: AnyObject, DragTargetDelegate {
    func shouldClose(window: Window) -> Bool
    func minimumContentSize(window: Window) -> CGSize?
    func maximumContentSize(window: Window) -> CGSize?
}

extension WindowDelegate {
    public func shouldClose(window: Window) -> Bool { true }
    public func minimumContentSize(window: Window) -> CGSize? { nil }
    public func maximumContentSize(window: Window) -> CGSize? { nil }

    // DragTargetDelegate 
    public func draggingEntered(target: Window, position: CGPoint, files: [String]) -> DragOperation { .reject }
    public func draggingUpdated(target: Window, position: CGPoint, files: [String]) -> DragOperation { .reject }
    public func draggingDropped(target: Window, position: CGPoint, files: [String]) -> DragOperation { .reject }
    public func draggingExited(target: Window, files: [String]) {}
}

public struct WindowStyle: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let title             = WindowStyle(rawValue: 1)
    public static let closeButton       = WindowStyle(rawValue: 1 << 1)
    public static let minimizeButton    = WindowStyle(rawValue: 1 << 2)
    public static let maximizeButton    = WindowStyle(rawValue: 1 << 3)
    public static let resizableBorder   = WindowStyle(rawValue: 1 << 4)
    public static let autoResize        = WindowStyle(rawValue: 1 << 5) // resize on rotate or DPI change, etc.

    public static let genericWindow     = WindowStyle(rawValue: 0xff)   // includes all but StyleAcceptFileDrop
    public static let acceptFileDrop    = WindowStyle(rawValue: 1 << 8) // enables file drag & drop
}

public protocol Window {

    var contentRect: CGRect { get }
    var windowRect: CGRect { get }
    var contentScaleFactor: Float { get }

    var origin: CGPoint { get set }
    var contentSize: CGSize { get set }

    var delegate: WindowDelegate? { get }

    init(name: String, style: WindowStyle, delegate: WindowDelegate?)

    func show()
    func hide()
    func activate()
    func minimize()

    func showMouse(_: Bool, forDeviceId: Int)
    func isMouseVisible(forDeviceId: Int) -> Bool
    func holdMouse(_: Bool, forDeviceId: Int)
    func isMouseHeld(forDeviceId: Int) -> Bool
    func setMousePosition(_: CGPoint, forDeviceId: Int)
    func mousePosition(forDeviceId: Int) -> CGPoint

    func enableTextInput(_: Bool, forDeviceId: Int)
    func isTextInputEnabled(forDeviceId: Int) -> Bool

    func addEventObserver(_: AnyObject, handler: @escaping (_: WindowEvent)->Void)
    func addEventObserver(_: AnyObject, handler: @escaping (_: MouseEvent)->Void)
    func addEventObserver(_: AnyObject, handler: @escaping (_: KeyboardEvent)->Void)
    func removeEventObserver(_: AnyObject)
}

extension Window {
    public func showMouse(_: Bool, forDeviceId: Int) {}
    public func isMouseVisible(forDeviceId: Int) -> Bool { false }
    public func holdMouse(_: Bool, forDeviceId: Int) {}
    public func isMouseHeld(forDeviceId: Int) -> Bool { false }
    public func setMousePosition(_: CGPoint, forDeviceId: Int) {}
    public func mousePosition(forDeviceId: Int) -> CGPoint { .zero }

    public func enableTextInput(_: Bool, forDeviceId: Int) {}
    public func isTextInputEnabled(forDeviceId: Int) -> Bool { return false }
}


public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window {
    Platform.makeWindow(name: name, style: style, delegate: delegate)
}
