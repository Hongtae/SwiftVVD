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
    case entered
    case exited
    case wheel
    case pointing
    case cancelled
}

public enum MouseEventDevice {
    case unknown
    case genericMouse
    case stylus
    case touch
}

public enum ScrollEventPhase: Sendable, Hashable {
    case mayBegin
    case began
    case stationary
    case changed
    case ended
    case cancelled
}

public enum ScrollEventSource: Sendable, Hashable {
    case unknown
    case wheel
    case finger
    case continuous
    case wheelTilt
}

public struct ScrollEventData: Sendable, Hashable {
    /// Direct-manipulation phase supplied by the platform, when available.
    public var phase: ScrollEventPhase? = nil
    /// Native inertial phase is preserved separately so higher layers can choose
    /// between platform momentum and their own cross-platform simulation.
    public var nativeMomentumPhase: ScrollEventPhase? = nil
    public var source: ScrollEventSource = .unknown
    public var isPrecise: Bool = false
    public var isDirectionInvertedFromDevice: Bool = false
}

public struct TouchEventData: Sendable, Hashable {
    /// Major-axis contact radius in the same logical coordinate units as location.
    public var majorRadius: CGFloat = 0.0
    /// Platform-reported uncertainty for `majorRadius`, when available.
    public var majorRadiusTolerance: CGFloat = 0.0
    public var maximumPossiblePressure: CGFloat = 1.0
}

public struct MouseEvent {
    public var type: MouseEventType
    public weak var window: (any Window)?
    public var device: MouseEventDevice
    public var deviceID: Int
    public var buttonID: Int
    public var location: CGPoint
    /// Relative pointer movement or scroll displacement.
    public var delta: CGPoint = .zero
    public var tilt: CGPoint = .zero
    public var pressure: CGFloat = 0.0
    /// Event occurrence time in the platform's monotonic clock.
    public var timestamp: TimeInterval
    /// Additional raw semantics for wheel input. Non-nil when `type == .wheel`.
    public var scrollData: ScrollEventData? = nil
    /// Additional contact semantics for direct touch or stylus input.
    public var touchData: TouchEventData? = nil
}

public enum KeyboardEventType {
    case keyDown
    case keyUp
    case textInput
    case textComposition
}

public struct KeyboardModifierFlags: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let capsLock = KeyboardModifierFlags(rawValue: 1 << 0)
    public static let shift = KeyboardModifierFlags(rawValue: 1 << 1)
    public static let control = KeyboardModifierFlags(rawValue: 1 << 2)
    public static let option = KeyboardModifierFlags(rawValue: 1 << 3)
    public static let command = KeyboardModifierFlags(rawValue: 1 << 4)
    public static let numericPad = KeyboardModifierFlags(rawValue: 1 << 5)
    public static let function = KeyboardModifierFlags(rawValue: 1 << 6)
}

public struct KeyboardEvent {
    public var type: KeyboardEventType
    public weak var window: (any Window)?
    public var deviceID: Int
    public var key: VirtualKey
    public var text: String
    public var isRepeat: Bool = false
    public var modifiers: KeyboardModifierFlags = []
}

public enum GestureEventType {
    case pan
    case magnify
    case rotate
}

public enum GestureEventPhase {
    case began
    case changed
    case ended
    case cancelled
}

public struct GestureEvent {
    public var type: GestureEventType
    public weak var window: (any Window)?
    public var phase: GestureEventPhase
    public var location: CGPoint
    public var delta: CGPoint = .zero
    public var magnification: CGFloat = 0.0
    public var rotation: CGFloat = 0.0
}

public enum WindowEventType {
    case created
    case closed
    case hidden
    case shown
    case activated
    case inactivated
    case minimized
    case geometryInvalidated
    case moved
    case resizeBegan
    case resized
    case resizeEnded
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
    
    public static let utilityWindow     = WindowStyle(rawValue: 1 << 9)
    public static let popupWindow       = WindowStyle(rawValue: 1 << 10)
}

public protocol WindowEventObserver {
    mutating func addEventObserver(_: AnyObject, handler: @escaping (_: WindowEvent)->Void)
    mutating func addEventObserver(_: AnyObject, handler: @escaping (_: MouseEvent)->Void)
    mutating func addEventObserver(_: AnyObject, handler: @escaping (_: KeyboardEvent)->Void)
    mutating func addEventObserver(_: AnyObject, handler: @escaping (_: GestureEvent)->Void)
    mutating func removeEventObserver(_: AnyObject)
}

@MainActor
public protocol Window: AnyObject {

    var activated: Bool { get }
    var visible: Bool { get }

    /// Content bounds in scale-adjusted logical content coordinates.
    var contentBounds: CGRect { get }
    /// Outer window frame in the platform's external screen coordinates.
    var windowFrame: CGRect { get }
    var contentScaleFactor: CGFloat { get }
    var resolution: CGSize { get set }

    /// Outer window origin in the same external coordinates as `windowFrame`.
    var origin: CGPoint { get set }
    /// Content size in scale-adjusted logical content coordinates.
    var contentSize: CGSize { get set }
    
    var title: String { get set }

    /// The platform system-menu capability for this window, when supported.
    var menuController: (any WindowMenuController)? { get }

    var delegate: WindowDelegate? { get }

    init?(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any])

    func show()
    func hide()
    func activate()
    func minimize()
    func center()

    @discardableResult
    func requestToClose() -> Bool
    func close()

    func showMouse(_: Bool, forDeviceID: Int)
    func isMouseVisible(forDeviceID: Int) -> Bool

    /// Sets a window-local cursor override for the specified pointing device.
    /// Pass `nil` to restore the platform default.
    func setCursor(_ cursor: Cursor?, forDeviceID: Int)

    /// Returns the current window-local override, or `nil` when using the
    /// platform default.
    func cursor(forDeviceID: Int) -> Cursor?

    /// Enables or disables relative mouse input for the specified device.
    ///
    /// While locked, the mouse position remains fixed, but physical movement
    /// is still reported through the `delta` of each move event.
    func lockMouse(_: Bool, forDeviceID: Int)
    func isMouseLocked(forDeviceID: Int) -> Bool

    func setMousePosition(_: CGPoint, forDeviceID: Int)
    func mousePosition(forDeviceID: Int) -> CGPoint?

    func enableTextInput(_: Bool, forDeviceID: Int)
    func isTextInputEnabled(forDeviceID: Int) -> Bool

    /// Ends the active text composition and returns its pending text.
    ///
    /// Text input does not need to be enabled when this method is called, and
    /// the method does not change the text-input enabled state. This permits
    /// pending platform state to be drained after an input or focus transition.
    ///
    /// When `emitEvents` is `true` and text input is enabled for the device, a
    /// text-input event followed by an empty text-composition event is emitted
    /// before the method returns. Returns `nil` when the device has no pending
    /// composition.
    @discardableResult
    func resetTextComposition(_ emitEvents: Bool, forDeviceID: Int) -> String?

    func convertPointToScreen(_: CGPoint) -> CGPoint
    func convertPointFromScreen(_: CGPoint) -> CGPoint

    // The screen containing most of the window.
    // Returns nil if the window is completely offscreen,
    // or if no platform window/screen is available.
    var screen: (any Screen)? { get }

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
    public func center() {
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        let outerSize = windowFrame.size
        origin = CGPoint(
            x: visibleFrame.minX
                + (visibleFrame.width - outerSize.width) * 0.5,
            y: visibleFrame.minY
                + (visibleFrame.height - outerSize.height) * 0.5
        )
    }

    public func setCursor(_ cursor: Cursor?, forDeviceID: Int) {}
    public func cursor(forDeviceID: Int) -> Cursor? { nil }

    public func showMouse(_: Bool, forDeviceID: Int) {}
    public func isMouseVisible(forDeviceID: Int) -> Bool { false }

    public func lockMouse(_: Bool, forDeviceID: Int) {}
    public func isMouseLocked(forDeviceID: Int) -> Bool { false }

    public func setMousePosition(_: CGPoint, forDeviceID: Int) {}
    public func mousePosition(forDeviceID: Int) -> CGPoint? { nil }

    public func enableTextInput(_: Bool, forDeviceID: Int) {}
    public func isTextInputEnabled(forDeviceID: Int) -> Bool { false }
    public func resetTextComposition(_ emitEvents: Bool, forDeviceID: Int) -> String? {
        nil
    }

    public var menuController: (any WindowMenuController)? { nil }

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

    func addEventObserver(_ observer: AnyObject, handler: @escaping (_: GestureEvent)->Void) {
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
        var gestureEventHandler: ((_ event: GestureEvent) -> Void)? = nil
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

    public mutating func addEventObserver(_ observer: AnyObject, handler: @escaping (_: GestureEvent)->Void) {
        let key = ObjectIdentifier(observer)
        if var handlers = self.handlers[key] {
            handlers.gestureEventHandler = handler
            self.handlers[key] = handlers
        } else {
            self.handlers[key] = Handler(observer: observer, gestureEventHandler: handler)
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

    func postGestureEvent(_ event: GestureEvent) {
        assert(event.window === self)
        self.eventObservers.activeHandlers().forEach {
            $0.gestureEventHandler?(event)
        }
    }
}
