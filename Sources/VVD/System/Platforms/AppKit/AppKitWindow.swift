//
//  File: AppKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
@_implementationOnly import AppKit

nonisolated(unsafe) private var hideCursorCount = 0

@MainActor
final class AppKitWindow: Window {
    
    var activated: Bool { self.view.activated }
    var visible: Bool { self.view.visible }
    
    var resolution: CGSize {
        get {
            let pixelBounds = nsView.convertToBacking(nsView.bounds)
            return CGSize(width: pixelBounds.width, height: pixelBounds.height)
        }
        set (value) {
            if nsView.window?.contentView === self.view {
                let window = nsView.window!
                let origin = self.origin
                let pixelBounds = nsView.window!.convertFromBacking(NSMakeRect(0, 0, value.width, value.height))
                let rect = CGRect(origin: .zero, size: CGSize(width: pixelBounds.width, height: pixelBounds.height))
                let frame = window.frameRect(forContentRect: rect)
                window.setContentSize(frame.size)
                if origin == self.origin {
                    window.displayIfNeeded()
                } else {
                    self.origin = origin
                }
            } else {
                let s = nsView.convertFromBacking(value)
                nsView.frame.size = s
                nsView.window?.layoutIfNeeded()
            }
        }
    }

    var contentBounds: CGRect { self.view.contentBounds }
    var windowFrame: CGRect { self.view.windowFrame }
    var contentScaleFactor: CGFloat { self.view.contentScaleFactor }

    var title: String {
        get { nsView.window?.title ?? "" }
        set { nsView.window?.title = newValue }
    }

    fileprivate var window: NSWindow
    var view: AppKitView

    var origin: CGPoint {
        get {
            if nsView.window?.contentView === self.view {
                let frame = nsView.window!.frame
                if let screen = nsView.window?.screen {
                    let height = screen.frame.height
                    return CGPoint(x: frame.minX, y: height - frame.maxY)
                }
                return frame.origin
            } else {
                return nsView.frame.origin
            }
        }
        set(value) {
            if nsView.window?.contentView === self.view {
                let window = nsView.window!
                if let screen = window.screen {
                    let height = screen.frame.height
                    let y = height - value.y
                    window.setFrameTopLeftPoint(NSPoint(x: value.x, y: y))
                } else {
                    window.setFrameOrigin(value)
                }
                window.displayIfNeeded()
            } else {
                nsView.frame.origin = value
                nsView.window?.layoutIfNeeded()
            }
        }
    }

    var contentSize: CGSize {
        get {
            var bounds = nsView.bounds
            if nsView.window != nil {
                bounds = nsView.convert(bounds, to: nil)
            }
            return CGSize(width: bounds.width, height: bounds.height)
        }
        set(value) {
            if nsView.window?.contentView === self.view {
                let origin = self.origin
                let window = nsView.window!
                let rect = CGRect(origin: .zero, size: value)
                let frame = window.frameRect(forContentRect: rect)
                window.setContentSize(frame.size)
                if origin == self.origin {
                    window.displayIfNeeded()
                } else {
                    self.origin = origin
                }
            } else {
                nsView.frame.size = value
                nsView.window?.layoutIfNeeded()
            }
        }
    }

    var delegate: WindowDelegate?
    var platformHandle: OpaquePointer? {
        unsafeBitCast(view as AnyObject, to: OpaquePointer.self)
    }

    private var nsView: NSView { view as! NSView }
    
    required init?(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) {
        var styleMask: NSWindow.StyleMask = []
        let backingStoreType: NSWindow.BackingStoreType = .buffered
        let contentRect = NSMakeRect(0, 0, 640, 480)
        
        if style.contains(.title)           { styleMask.insert(.titled) }
        if style.contains(.closeButton)     { styleMask.insert(.closable) }
        if style.contains(.minimizeButton)  { styleMask.insert(.miniaturizable) }
        if style.contains(.maximizeButton)  {  }
        if style.contains(.resizableBorder) { styleMask.insert(.resizable) }
        
        var windowType: NSWindow.Type = NSWindow.self
        
        if style.contains(.utilityWindow) {
            styleMask.insert(.utilityWindow)
            windowType = NSPanel.self
        }
        
        self.window = windowType.init(contentRect: contentRect,
                                      styleMask: styleMask,
                                      backing: backingStoreType,
                                      defer: true)
        
        self.delegate = delegate
        self.view = makeAppKitView(frame: contentRect)
        self.view.proxyWindow = self
        
        self.window.contentView = (self.view as! NSView)
        self.window.delegate = (self.view as! NSWindowDelegate)
        self.window.isReleasedWhenClosed = false
        self.window.acceptsMouseMovedEvents = true
        self.window.allowsConcurrentViewDrawing = true
        self.window.title = name
        self.window.hasShadow = true
        
        if style.contains(.acceptFileDrop) {
            (view as! NSView).registerForDraggedTypes([.fileURL])
        }
        if style.contains(.utilityWindow) {
            let levelKey: CGWindowLevelKey = .utilityWindow
            self.window.level = .init(Int(levelKey.rawValue))
        }
        
        self.postWindowEvent(
            WindowEvent(type: .created,
                        window: self,
                        windowFrame: self.windowFrame,
                        contentBounds: self.contentBounds,
                        contentScaleFactor: self.contentScaleFactor))
    }

    func show() {
        if let window = nsView.window {
            window.orderFront(nil)

            self.postWindowEvent(type: .shown)
        }
    }

    func hide() {
        if let window = nsView.window {
            window.resignKey()
            window.orderOut(nil)

            self.postWindowEvent(type: .hidden)
        }
    }

    func activate() {
        if let window = nsView.window {
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

    func minimize() {
        nsView.window?.miniaturize(nil)
    }

    func showMouse(_ show: Bool, forDeviceID deviceID: Int) {
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

    func isMouseVisible(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return hideCursorCount >= 0
        }
        return false
    }

    func lockMouse(_ hold: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            self.view.mouseLocked = hold
        }
    }

    func isMouseLocked(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return self.view.mouseLocked
        }
        return false
    }

    func setMousePosition(_ pos: CGPoint, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            self.view.mousePosition = pos
        }
    }

    func mousePosition(forDeviceID deviceID: Int) -> CGPoint? {
        if deviceID == 0 {
            return self.view.mousePosition
        }
        return nil
    }
 
    func enableTextInput(_ enable: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            self.view.textInput = enable
        }
    }
    
    func isTextInputEnabled(forDeviceID deviceID: Int) -> Bool {
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

    func addEventObserver(_ observer: AnyObject, handler: @escaping (_: WindowEvent)->Void) {
        let key = ObjectIdentifier(observer)
        if var handlers = self.eventObservers[key] {
            handlers.windowEventHandler = handler
            self.eventObservers[key] = handlers
        } else {
            self.eventObservers[key] = EventHandlers(observer: observer, windowEventHandler: handler)
        }
    }
    func addEventObserver(_ observer: AnyObject, handler: @escaping (_: MouseEvent)->Void) {
        let key = ObjectIdentifier(observer)
        if var handlers = self.eventObservers[key] {
            handlers.mouseEventHandler = handler
            self.eventObservers[key] = handlers
        } else {
            self.eventObservers[key] = EventHandlers(observer: observer, mouseEventHandler: handler)
        }
    }
    func addEventObserver(_ observer: AnyObject, handler: @escaping (_: KeyboardEvent)->Void) {
        let key = ObjectIdentifier(observer)
        if var handlers = self.eventObservers[key] {
            handlers.keyboardEventHandler = handler
            self.eventObservers[key] = handlers
        } else {
            self.eventObservers[key] = EventHandlers(observer: observer, keyboardEventHandler: handler)
        }
    }
    func removeEventObserver(_ observer: AnyObject) {
        let key = ObjectIdentifier(observer)
        self.eventObservers[key] = nil
    }
    
    func convertPointToScreen(_ point: CGPoint) -> CGPoint {
        let view = self.view as! NSView
        let ptWindow = view.convert(point, to: nil)
        var ptScreen = self.window.convertPoint(toScreen: ptWindow)
        if let frame = self.window.screen?.frame {
            ptScreen.y = frame.height - ptScreen.y
        }
        return ptScreen
    }
    
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint {
        var point = point
        if let frame = self.window.screen?.frame {
            point.y = frame.minY + (frame.height - point.y)
        }
        let ptWindow = self.window.convertPoint(fromScreen: point)
        let view = self.view as! NSView
        return view.convert(ptWindow, from: nil)
    }
}

#endif //if ENABLE_APPKIT
