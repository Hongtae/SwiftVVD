//
//  File: AppKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
import AppKit

class MainKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private var hideCursorCount = 0

@MainActor
public class AppKitWindow: Window {

    public var activated: Bool { self.view.activated }
    public var visible: Bool { self.view.visible }

    public var resolution: CGSize {
        get {
            let pixelBounds = self.view.convertToBacking(self.view.bounds)
            return CGSize(width: pixelBounds.width, height: pixelBounds.height)
        }
        set (value) {
            if self.view.window?.contentView === self.view {
                let pixelBounds = self.view.window!.convertFromBacking(NSMakeRect(0, 0, value.width, value.height))
                self.view.window?.setContentSize(CGSize(width: pixelBounds.width, height: pixelBounds.height))
                self.view.window?.displayIfNeeded()
            } else {
                let s = self.view.convertFromBacking(value)
                self.view.frame.size = s
                self.view.window?.layoutIfNeeded()
            }
        }
    }

    public var contentBounds: CGRect { self.view.contentBounds }
    public var windowFrame: CGRect { self.view.windowFrame }
    public var contentScaleFactor: CGFloat { self.view.contentScaleFactor }

    public var title: String {
        get { self.view.window?.title ?? "" }
        set { self.view.window?.title = newValue }
    }

    var window: NSWindow
    var view: AppKitView

    public var origin: CGPoint {
        get {
            if self.view.window?.contentView === self.view {
                return self.view.window!.frame.origin
            } else {
                return self.view.frame.origin
            }
        }
        set(value) {
            if self.view.window?.contentView === self.view {
                self.view.window?.setFrameOrigin(value)
                self.view.window?.displayIfNeeded()
            } else {
                self.view.frame.origin = origin
                self.view.window?.layoutIfNeeded()
            }
        }
    }

    public var contentSize: CGSize {
        get {
            var bounds = self.view.bounds
            if self.view.window != nil {
                bounds = view.convert(bounds, to: nil)
            }
            return CGSize(width: bounds.width, height: bounds.height)
        }
        set(value) {
            if self.view.window?.contentView === self.view {
                self.view.window?.setContentSize(value)
                self.view.window?.displayIfNeeded()
            } else {
                self.view.frame.size = contentSize
                self.view.window?.layoutIfNeeded()
            }
        }
    }

    public var delegate: WindowDelegate?

    public required init?(name: String, style: WindowStyle, delegate: WindowDelegate?) {
        var styleMask: NSWindow.StyleMask = []
        let backingStoreType: NSWindow.BackingStoreType = .buffered
        let contentRect = NSMakeRect(0, 0, 640, 480)

        if style.contains(.title)           { styleMask.insert(.titled) }
        if style.contains(.closeButton)     { styleMask.insert(.closable) }
        if style.contains(.minimizeButton)  { styleMask.insert(.miniaturizable) }
        if style.contains(.maximizeButton)  {  }
        if style.contains(.resizableBorder) { styleMask.insert(.resizable) }

        self.window = MainKeyWindow(contentRect: contentRect,
                                    styleMask: styleMask,
                                    backing: backingStoreType,
                                    defer: true)

        self.delegate = delegate
        self.view = AppKitView(frame: contentRect)
        self.view.proxyWindow = self

        self.window.contentView = self.view
        self.window.delegate = self.view
        self.window.isReleasedWhenClosed = false
        self.window.acceptsMouseMovedEvents = true
        self.window.allowsConcurrentViewDrawing = true
        self.window.title = name

        if style.contains(.acceptFileDrop) {
            view.registerForDraggedTypes([.fileURL])
        }

        self.postWindowEvent(
            WindowEvent(type: .created,
                        window: self,
                        windowFrame: self.windowFrame,
                        contentBounds: self.contentBounds,
                        contentScaleFactor: self.contentScaleFactor))
    }

    public func show() {
        if let window = self.view.window {
            window.orderFront(nil)

            self.postWindowEvent(type: .shown)
        }
    }

    public func hide() {
        if let window = self.view.window {
            window.resignKey()
            window.orderOut(nil)

            self.postWindowEvent(type: .hidden)
        }
    }

    public func activate() {
        if let window = self.view.window {
            window.makeKeyAndOrderFront(nil)
            self.view.visible = true
            self.view.activated = true

            if window.isKeyWindow == false {
                if window.isVisible {
                    // failed to become key window, but displayed.
                    self.postWindowEvent(type: .shown)
                }
            }
        }
    }

    public func minimize() {
        self.view.window?.miniaturize(nil)
    }

    public func showMouse(_ show: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            if show {
                if CGDisplayShowCursor(CGMainDisplayID()) == .success {
                    hideCursorCount -= 1
                }
            } else {
                if CGDisplayHideCursor(CGMainDisplayID()) == .success {
                    hideCursorCount += 1
                }
            }
        }
    }

    public func isMouseVisible(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return hideCursorCount >= 0
        }
        return false
    }

    public func lockMouse(_ hold: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            self.view.mouseLocked = hold
        }
    }

    public func isMouseLocked(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return self.view.mouseLocked
        }
        return false
    }

    public func setMousePosition(_ pos: CGPoint, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            self.view.mousePosition = pos
        }
    }

    public func mousePosition(forDeviceID deviceID: Int) -> CGPoint? {
        if deviceID == 0 {
            return self.view.mousePosition
        }
        return nil
    }
 
    public func enableTextInput(_ enable: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            self.view.textInput = enable
        }
    }
    
    public func isTextInputEnabled(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return self.view.textInput
        }
        return false
    }

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

#endif //if ENABLE_APPKIT
