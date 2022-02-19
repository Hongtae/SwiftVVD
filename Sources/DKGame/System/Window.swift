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

public protocol WindowDelegate: DragTargetDelegate {
    func shouldClose() -> Bool
}

extension WindowDelegate {
    public func shouldClose() -> Bool { true }
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
    func show()
    func hide()
}

public func makeWindow(name: String = "", style: WindowStyle = .genericWindow, delegate: WindowDelegate? = nil) -> Window { 
    return Platform.makeWindow(name: name, style: style, delegate: delegate)
}
