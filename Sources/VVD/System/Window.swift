//
//  File: Window.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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
    func draggingEntered(target: any Window, position: CGPoint, files: [String]) -> DragOperation
    func draggingUpdated(target: any Window, position: CGPoint, files: [String]) -> DragOperation
    func draggingDropped(target: any Window, position: CGPoint, files: [String]) -> DragOperation
    func draggingExited(target: any Window, files: [String])
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
    public weak var window: (any Window)?
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
    public weak var window: (any Window)?
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
    public weak var window: (any Window)?
    public var windowFrame: CGRect
    public var contentBounds: CGRect
    public var contentScaleFactor: CGFloat
}

public protocol WindowDelegate: AnyObject, DragTargetDelegate {
    func shouldClose(window: any Window) -> Bool
    func minimumContentSize(window: any Window) -> CGSize?
    func maximumContentSize(window: any Window) -> CGSize?
}

extension WindowDelegate {
    public func shouldClose(window: any Window) -> Bool { true }
    public func minimumContentSize(window: any Window) -> CGSize? { nil }
    public func maximumContentSize(window: any Window) -> CGSize? { nil }

    // DragTargetDelegate 
    public func draggingEntered(target: any Window, position: CGPoint, files: [String]) -> DragOperation { .reject }
    public func draggingUpdated(target: any Window, position: CGPoint, files: [String]) -> DragOperation { .reject }
    public func draggingDropped(target: any Window, position: CGPoint, files: [String]) -> DragOperation { .reject }
    public func draggingExited(target: any Window, files: [String]) {}
}

public struct WindowStyle: OptionSet, Sendable {
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
    
    public static let auxiliaryWindow   = WindowStyle(rawValue: 1 << 9)
}

public protocol WindowEventObserver {
    mutating func addEventObserver(_: AnyObject, handler: @escaping (_: WindowEvent)->Void)
    mutating func addEventObserver(_: AnyObject, handler: @escaping (_: MouseEvent)->Void)
    mutating func addEventObserver(_: AnyObject, handler: @escaping (_: KeyboardEvent)->Void)
    mutating func removeEventObserver(_: AnyObject)
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
    
    var title: String { get set }

    var delegate: WindowDelegate? { get }

    init?(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any])

    func show()
    func hide()
    func activate()
    func minimize()

    @discardableResult
    func requestToClose() -> Bool
    func close()

    func showMouse(_: Bool, forDeviceID: Int)
    func isMouseVisible(forDeviceID: Int) -> Bool
    func lockMouse(_: Bool, forDeviceID: Int)
    func isMouseLocked(forDeviceID: Int) -> Bool
    func setMousePosition(_: CGPoint, forDeviceID: Int)
    func mousePosition(forDeviceID: Int) -> CGPoint?

    func enableTextInput(_: Bool, forDeviceID: Int)
    func isTextInputEnabled(forDeviceID: Int) -> Bool

    func convertPointToScreen(_: CGPoint) -> CGPoint
    func convertPointFromScreen(_: CGPoint) -> CGPoint

    var canPresentModalWindow: Bool { get }
    var modalWindows: [any Window] { get }
    @discardableResult
    func presentModalWindow(_: any Window, completionHandler: (()->Void)?) -> Bool
    @discardableResult
    func dismissModalWindow(_: any Window) -> Bool
    
    var isValid: Bool { get }
    var platformHandle: OpaquePointer? { get }

    associatedtype EventObserver: WindowEventObserver
    var eventObservers: Self.EventObserver { get set }
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

    public var canPresentModalWindow: Bool { false }
    public var modalWindows: [any Window] { [] }
    public func presentModalWindow(_: any Window, completionHandler: (()->Void)?) -> Bool { false }
    public func presentModalWindow(_ window: any Window) -> Bool {
        self.presentModalWindow(window, completionHandler: nil) 
    }
    public func dismissModalWindow(_: any Window) -> Bool { false }
}

public extension Window {
    func addEventObserver(_ observer: AnyObject, handler: @escaping (_: WindowEvent)->Void) {
        self.eventObservers.addEventObserver(observer, handler: handler)
    }

    func addEventObserver(_ observer: AnyObject, handler: @escaping (_: MouseEvent)->Void) {
        self.eventObservers.addEventObserver(observer, handler: handler)
    }

    func addEventObserver(_ observer: AnyObject, handler: @escaping (_: KeyboardEvent)->Void) {
        self.eventObservers.addEventObserver(observer, handler: handler)
    }

    func removeEventObserver(_ observer: AnyObject) {
        self.eventObservers.removeEventObserver(observer)
    }
}

@MainActor
public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]? = nil) -> (any Window)? {
    Platform.makeWindow(name: name, style: style, delegate: delegate, data: data ?? [:])
}

public struct WindowEventObserverContainer: WindowEventObserver {
    fileprivate struct Handler {
        weak var observer: AnyObject?
        var windowEventHandler: ((_ event: WindowEvent) -> Void)? = nil
        var mouseEventHandler: ((_ event: MouseEvent) -> Void)? = nil
        var keyboardEventHandler: ((_ event: KeyboardEvent) -> Void)? = nil
    }
    private var handlers: [ObjectIdentifier: Handler] = [:]

    fileprivate mutating func activeHandlers() -> [Handler] {
        self.handlers = self.handlers.filter {
            $0.value.observer != nil 
        }
        return self.handlers.values.map(\.self)
    }

    public init() {
    }

    public mutating func addEventObserver(_ observer: AnyObject, handler: @escaping (_: WindowEvent)->Void) {
        let key = ObjectIdentifier(observer)
        if var handlers = self.handlers[key] {
            handlers.windowEventHandler = handler
            self.handlers[key] = handlers
        } else {
            self.handlers[key] = Handler(observer: observer, windowEventHandler: handler)
        }
    }

    public mutating func addEventObserver(_ observer: AnyObject, handler: @escaping (_: MouseEvent)->Void) {
        let key = ObjectIdentifier(observer)
        if var handlers = self.handlers[key] {
            handlers.mouseEventHandler = handler
            self.handlers[key] = handlers
        } else {
            self.handlers[key] = Handler(observer: observer, mouseEventHandler: handler)
        }
    }

    public mutating func addEventObserver(_ observer: AnyObject, handler: @escaping (_: KeyboardEvent)->Void) {
        let key = ObjectIdentifier(observer)
        if var handlers = self.handlers[key] {
            handlers.keyboardEventHandler = handler
            self.handlers[key] = handlers
        } else {
            self.handlers[key] = Handler(observer: observer, keyboardEventHandler: handler)
        }
    }

    public mutating func removeEventObserver(_ observer: AnyObject) {
        let key = ObjectIdentifier(observer)
        self.handlers[key] = nil
    }
}

extension Window where Self.EventObserver == WindowEventObserverContainer {
    func postWindowEvent(type: WindowEventType) {
        self.postWindowEvent(
            WindowEvent(type: type,
                        window: self,
                        windowFrame: self.windowFrame,
                        contentBounds: self.contentBounds,
                        contentScaleFactor: self.contentScaleFactor))
    }
    
    func postWindowEvent(_ event: WindowEvent) {
        assert(event.window === self)
        self.eventObservers.activeHandlers().forEach {
            $0.windowEventHandler?(event)
        }
    }

    func postKeyboardEvent(_ event: KeyboardEvent) {
        assert(event.window === self)
        self.eventObservers.activeHandlers().forEach {
            $0.keyboardEventHandler?(event)
        }
    }

    func postMouseEvent(_ event: MouseEvent) {
        assert(event.window === self)
        self.eventObservers.activeHandlers().forEach {
            $0.mouseEventHandler?(event)
        }
    }
}
