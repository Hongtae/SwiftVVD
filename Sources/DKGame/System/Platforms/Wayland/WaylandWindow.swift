//
//  File: WaylandWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation

@MainActor
public class WaylandWindow: Window {

    public var activated: Bool = false
    public var visible: Bool = false

    public var contentBounds: CGRect = .zero
    public var windowFrame: CGRect = .zero
    public var contentScaleFactor: CGFloat = 1.0
    public var resolution: CGSize = .zero

    public var origin: CGPoint = .zero
    public var contentSize: CGSize = .zero

    public var delegate: WindowDelegate?

    public required init(name: String, style: WindowStyle, delegate: WindowDelegate?) {

    }

    public func show() {

    }

    public func hide() {

    }

    public func activate() {

    }

    public func minimize() {

    }

    public func showMouse(_: Bool, forDeviceID: Int) {

    }

    public func isMouseVisible(forDeviceID: Int) -> Bool {
        false 
    }

    public func holdMouse(_: Bool, forDeviceID: Int) {

    }

    public func isMouseHeld(forDeviceID: Int) -> Bool {
        false
    }

    public func setMousePosition(_: CGPoint, forDeviceID: Int) {

    }

    public func mousePosition(forDeviceID: Int) -> CGPoint? {
        nil
    }

    public func enableTextInput(_ enable: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            
        }
    }

    public func isTextInputEnabled(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return false
        }
        return false
    }

    func postWindowEvent(type: WindowEventType) {
        self.postWindowEvent(
            WindowEvent(type: type,
                        window: self,
                        windowFrame: self.windowFrame,
                        contentBounds: self.contentBounds,
                        contentScaleFactor: self.contentScaleFactor
            )
        )
    }

    func postWindowEvent(_ event: WindowEvent) {
        assert(event.window === self)
        var invalidHandlers: [ObjectIdentifier] = []
        self.eventObservers.forEach { key, handlers in
            if let _ = handlers.observer {
                handlers.windowEventHandler?(event)
            } else {
                invalidHandlers.append(key)
            }
        }
        for key in invalidHandlers { self.eventObservers[key] = nil }
    }

    func postKeyboardEvent(_ event: KeyboardEvent) {
        assert(event.window === self)
        var invalidHandlers: [ObjectIdentifier] = []
        self.eventObservers.forEach { key, handlers in
            if let _ = handlers.observer {
                handlers.keyboardEventHandler?(event)
            } else {
                invalidHandlers.append(key)
            }
        }
        for key in invalidHandlers { self.eventObservers[key] = nil }
    }

    func postMouseEvent(_ event: MouseEvent) {
        assert(event.window === self)
        var invalidHandlers: [ObjectIdentifier] = []
        self.eventObservers.forEach { key, handlers in
            if let _ = handlers.observer {
                handlers.mouseEventHandler?(event)
            } else {
                invalidHandlers.append(key)
            }
        }
        for key in invalidHandlers { self.eventObservers[key] = nil }
    }

    private struct EventHandlers {
        weak var observer: AnyObject?
        var windowEventHandler: ((_: WindowEvent)->Void)?
        var mouseEventHandler: ((_: MouseEvent)->Void)?
        var keyboardEventHandler: ((_: KeyboardEvent)->Void)?
    }
    private var eventObservers: [ObjectIdentifier: EventHandlers] = [:]

    public func addEventObserver(_ observer: AnyObject, handler: @escaping (_: WindowEvent)->Void) {
        let key = ObjectIdentifier(observer)
        if var handlers = self.eventObservers[key] {
            handlers.windowEventHandler = handler
            self.eventObservers[key] = handlers
        } else {
            self.eventObservers[key] = EventHandlers(observer: observer, windowEventHandler: handler)
        }
    }
    public func addEventObserver(_ observer: AnyObject, handler: @escaping (_: MouseEvent)->Void) {
        let key = ObjectIdentifier(observer)
        if var handlers = self.eventObservers[key] {
            handlers.mouseEventHandler = handler
            self.eventObservers[key] = handlers
        } else {
            self.eventObservers[key] = EventHandlers(observer: observer, mouseEventHandler: handler)
        }
    }
    public func addEventObserver(_ observer: AnyObject, handler: @escaping (_: KeyboardEvent)->Void) {
        let key = ObjectIdentifier(observer)
        if var handlers = self.eventObservers[key] {
            handlers.keyboardEventHandler = handler
            self.eventObservers[key] = handlers
        } else {
            self.eventObservers[key] = EventHandlers(observer: observer, keyboardEventHandler: handler)
        }
    }
    public func removeEventObserver(_ observer: AnyObject) {
        let key = ObjectIdentifier(observer)
        self.eventObservers[key] = nil
    }
}

#endif //if ENABLE_UIKIT
