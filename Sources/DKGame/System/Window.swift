import Foundation

public enum DragOperation {
    case none, copy, move, link
}

public protocol DragTargetDelegate {
    func draggingEntered(files: [String], keyState: [Int], pt: CGPoint) -> DragOperation
    func draggingUpdated(files: [String], keyState: [Int], pt: CGPoint) -> DragOperation
    func draggingExited(files: [String], pt: CGPoint) -> DragOperation
    func draggingDropped(files: [String], pt: CGPoint) -> DragOperation
}

extension DragTargetDelegate {
    public func draggingEntered(files: [String], keyState: [Int], pt: CGPoint) -> DragOperation {
        return .none
    }
    public func draggingUpdated(files: [String], keyState: [Int], pt: CGPoint) -> DragOperation {
        return .none
    }
    public func draggingExited(files: [String], pt: CGPoint) -> DragOperation {
        return .none
    }
    public func draggingDropped(files: [String], pt: CGPoint) -> DragOperation {
        return .none
    }
}

public enum MouseEventType {
    case buttonDown, buttonUp, move, wheel, pointing
}

public enum MouseEventDevice {
    case unknown
    case genericMouse, stylus, touch
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
    case keyDown, keyUp, textInput, textComposition
}

public struct KeyboardEvent {
    var type: KeyboardEventType
    var deviceId: Int
    var key: UInt8 // virtual-key
    var text: String
}

public enum WindowEventType {
    case created, closed
    case hidden, shown
    case activated, inactivated
    case minimized, moved, resized, updated
}

public struct WindowEvent {
    var type: WindowEventType
    var windowRect: CGRect
    var contentRect: CGRect
    var contentScaleFactor: Float
}

public protocol WindowDelegate: AnyObject, DragTargetDelegate {
    func shouldClose(window: Window) -> Bool
}

extension WindowDelegate {
    public func shouldClose(window: Window) -> Bool { true }
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

    var delegate: WindowDelegate? { get }

    func show()
    func hide()

    var contentRect: CGRect { get }
    var windowRect: CGRect { get }
    var contentScaleFactor: Float { get }

    func enableTextInput(_: Bool, forDeviceId: Int)
    func isTextInputEnabled(forDeviceId: Int) -> Bool
}

extension Window {
    public func enableTextInput(_: Bool, forDeviceId: Int) {}
    public func isTextInputEnabled(forDeviceId: Int) -> Bool { return false }
}

public func makeWindow(name: String = "", style: WindowStyle = .genericWindow, delegate: WindowDelegate? = nil) -> Window { 
    return Platform.makeWindow(name: name, style: style, delegate: delegate)
}
