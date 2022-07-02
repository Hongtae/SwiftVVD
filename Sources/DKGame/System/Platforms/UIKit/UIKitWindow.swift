//
//  File: UIKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
import UIKit

public class UIKitWindow: Window {
    public var activated: Bool = false
    public var visible: Bool = false

    public var contentBounds: CGRect { self.view.contentBounds }
    public var windowFrame: CGRect { self.view.windowFrame }
    public var contentScaleFactor: CGFloat { self.view.contentScaleFactor }

    public var origin: CGPoint {
        get { self.view.frame.origin }
        set(value) { self.view.frame.origin = value }
    }

    public var contentSize: CGSize {
        get {
            let bounds = self.view.bounds
            return CGSize(width: bounds.width, height: bounds.height)
        }
        set(value) {
            self.view.bounds.size = value
        }
    }

    public var resolution: CGSize {
        get {
            let bounds = self.view.bounds
            let scale = self.view.contentScaleFactor
            return CGSize(width: bounds.width * scale, height: bounds.height * scale)
        }
        set(value) {
            let scale = 1.0 / self.view.contentScaleFactor
            let size = CGSize(width: value.width * scale, height: value.height * scale)
            self.view.bounds.size = size
        }
    }

    public var delegate: WindowDelegate?

    var window: UIWindow
    var view: UIKitView

    public required init(name: String, style: WindowStyle, delegate: WindowDelegate?) {

        let viewController = UIKitViewController()
        self.view = viewController.view as! UIKitView

        if style.contains(.autoResize) {
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        } else {
            view.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
        }
        viewController.title = name

        if let scene = activeWindowScenes.first {
            self.window = UIWindow(windowScene: scene)
        } else {
            self.window = UIWindow()
        }
        self.window.isHidden = true
        self.window.rootViewController = viewController

        (self.view as! UIKitView).proxyWindow = self

        activeWindows.append(window)
    }

    deinit {
        let window = self.window
        window.windowScene = nil
        activeWindows.removeAll { $0 === window }
    }

    public func show() {
        self.view.isHidden = false
    }

    public func hide() {
        self.view.isHidden = true
    }

    public func activate() {
        self.view.isHidden = false
        self.window.makeKeyAndVisible()
        self.view.becomeFirstResponder()
    }

    public func minimize() {
        self.view.isHidden = true
    }

    public func showMouse(_ show: Bool, forDeviceID deviceID: Int) {

    }
    public func isMouseVisible(forDeviceID deviceID: Int) -> Bool {
        false
    }
    public func holdMouse(_ hold: Bool, forDeviceID deviceID: Int) {

    }
    public func isMouseHeld(forDeviceID deviceID: Int) -> Bool {
        false
    }
    public func setMousePosition(_ pos: CGPoint, forDeviceID deviceID: Int) {

    }
    public func mousePosition(forDeviceID deviceID: Int) -> CGPoint {
        .zero
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
        self.postWindowEvent(WindowEvent(type: type,
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

#endif //if ENABLE_UIKIT
