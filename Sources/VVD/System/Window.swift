//
//  File: Window.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

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
    public var type: MouseEventType
    public weak var window: Window?
    public var device: MouseEventDevice
    public var deviceID: Int
    public var buttonID: Int
    public var location: CGPoint
    public var delta: CGPoint = .zero
    public var tilt: CGPoint = .zero
    public var pressure: CGFloat = 0.0
}

public enum KeyboardEventType {
    case keyDown
    case keyUp
    case textInput
    case textComposition
}

public struct KeyboardEvent {
    public var type: KeyboardEventType
    public weak var window: Window?
    public var deviceID: Int
    public var key: VirtualKey
    public var text: String
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
    public var type: WindowEventType
    public weak var window: Window?
    public var windowFrame: CGRect
    public var contentBounds: CGRect
    public var contentScaleFactor: CGFloat
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

@MainActor
public protocol Window: AnyObject {

    var activated: Bool { get }
    var visible: Bool { get }

    var contentBounds: CGRect { get }
    var windowFrame: CGRect { get }
    var contentScaleFactor: CGFloat { get }
    var resolution: CGSize { get set }

    var origin: CGPoint { get set }
    var contentSize: CGSize { get set }

    var delegate: WindowDelegate? { get }

    init?(name: String, style: WindowStyle, delegate: WindowDelegate?)

    func show()
    func hide()
    func activate()
    func minimize()

    func showMouse(_: Bool, forDeviceID: Int)
    func isMouseVisible(forDeviceID: Int) -> Bool
    func lockMouse(_: Bool, forDeviceID: Int)
    func isMouseLocked(forDeviceID: Int) -> Bool
    func setMousePosition(_: CGPoint, forDeviceID: Int)
    func mousePosition(forDeviceID: Int) -> CGPoint?

    func enableTextInput(_: Bool, forDeviceID: Int)
    func isTextInputEnabled(forDeviceID: Int) -> Bool

    func addEventObserver(_: AnyObject, handler: @escaping (_: WindowEvent)->Void)
    func addEventObserver(_: AnyObject, handler: @escaping (_: MouseEvent)->Void)
    func addEventObserver(_: AnyObject, handler: @escaping (_: KeyboardEvent)->Void)
    func removeEventObserver(_: AnyObject)
}

extension Window {
    public func showMouse(_: Bool, forDeviceID: Int) {}
    public func isMouseVisible(forDeviceID: Int) -> Bool { false }
    public func lockMouse(_: Bool, forDeviceID: Int) {}
    public func isMouseLocked(forDeviceID: Int) -> Bool { false }
    public func setMousePosition(_: CGPoint, forDeviceID: Int) {}
    public func mousePosition(forDeviceID: Int) -> CGPoint? { nil }

    public func enableTextInput(_: Bool, forDeviceID: Int) {}
    public func isTextInputEnabled(forDeviceID: Int) -> Bool { false }
}

@MainActor
public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window? {
    Platform.makeWindow(name: name, style: style, delegate: delegate)
}
