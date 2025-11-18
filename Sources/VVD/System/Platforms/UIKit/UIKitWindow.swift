//
//  File: UIKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
@_implementationOnly import UIKit

@MainActor
final class UIKitWindow: Window {
    var activated: Bool = false
    var visible: Bool = false

    var contentBounds: CGRect { self.view.contentBounds }
    var windowFrame: CGRect { self.view.windowFrame }
    var contentScaleFactor: CGFloat { self.view.contentScaleFactor }

    var origin: CGPoint {
        get { uiView.frame.origin }
        set(value) { uiView.frame.origin = value }
    }

    var contentSize: CGSize {
        get {
            let bounds = uiView.bounds
            return CGSize(width: bounds.width, height: bounds.height)
        }
        set(value) {
            uiView.bounds.size = value
        }
    }

    var resolution: CGSize {
        get {
            let bounds = uiView.bounds
            let scale = self.view.contentScaleFactor
            return CGSize(width: bounds.width * scale, height: bounds.height * scale)
        }
        set(value) {
            let scale = 1.0 / self.view.contentScaleFactor
            let size = CGSize(width: value.width * scale, height: value.height * scale)
            uiView.bounds.size = size
        }
    }

    var title: String {
        get { uiView.window?.rootViewController?.title ?? "" }
        set { uiView.window?.rootViewController?.title = newValue }
    }

    var delegate: WindowDelegate?
    
    var platformHandle: OpaquePointer? {
        unsafeBitCast(view as AnyObject, to: OpaquePointer.self)
    }
    var isValid: Bool { true }

    private var window: UIWindow
    var view: UIKitView
    
    private var uiView: UIView { self.view as! UIView }

    required init?(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) {

        let viewController = makeUIKitViewController() as! UIViewController
        let uiView: UIView = viewController.view
        self.view = uiView as! UIKitView

        if style.contains(.autoResize) {
            uiView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        } else {
            uiView.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
        }
        viewController.title = name

        if let scene = anyWindowScene() as? UIWindowScene {
            self.window = UIWindow(windowScene: scene)
        } else {
            self.window = UIWindow()
        }
        self.window.isHidden = true
        self.window.rootViewController = viewController
        self.view.proxyWindow = self

        setActiveWindow(window)
    }

    deinit {
        let window = self.window
        Task { @MainActor in window.windowScene = nil }
        unsetActiveWindow(window)
    }

    func show() {
        uiView.isHidden = false
    }

    func hide() {
        uiView.isHidden = true
    }

    func activate() {
        uiView.isHidden = false
        self.window.makeKeyAndVisible()
        _ = uiView.becomeFirstResponder()
    }

    func minimize() {
        uiView.isHidden = true
    }

    func showMouse(_ show: Bool, forDeviceID deviceID: Int) {
    }

    func isMouseVisible(forDeviceID deviceID: Int) -> Bool {
        return false
    }

    func lockMouse(_ hold: Bool, forDeviceID deviceID: Int) {
    }

    func isMouseLocked(forDeviceID deviceID: Int) -> Bool {
        return false
    }

    func setMousePosition(_ pos: CGPoint, forDeviceID deviceID: Int) {
    }

    func mousePosition(forDeviceID deviceID: Int) -> CGPoint? {
        return self.view.touchLocation(atIndex: deviceID)
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
            WindowEvent(
                type: type,
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
        let ptWindow = self.uiView.convert(point, to: nil)
        return self.window.convert(ptWindow, to: nil)
    }
    
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint {
        let ptWindow = self.window.convert(point, from: nil)
        return self.uiView.convert(ptWindow, from: nil)
    }
}

#endif //if ENABLE_UIKIT
