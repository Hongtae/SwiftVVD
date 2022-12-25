//
//  File: WaylandWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation
import Wayland


var xdgSurfaceListener = xdg_surface_listener(
    configure: { data, surface, serial in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow

        Log.debug("xdg_surface_listener.configure (serial:\(serial))")

        xdg_surface_ack_configure(surface, serial)

        Task { @MainActor in 
            window.xdgSurfaceConfigured = true
        }
    }
)
var xdgToplevelListener = xdg_toplevel_listener(
    configure: { data, topLevel, width, height, states in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow
        Log.debug("xdg_toplevel_listener.configure (width:\(width), height:\(height))")
    },
    close: { data, topLevel in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow
        Log.debug("xdg_toplevel_listener.close")
    },
    configure_bounds: { data, topLevel, width, height in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow
        Log.debug("xdg_toplevel_listener.configure_bounds (width:\(width), height:\(height))")
    }
)


@MainActor
public class WaylandWindow: Window {

    public private(set) var activated: Bool = false
    public private(set) var visible: Bool = false

    public private(set) var contentBounds: CGRect = .null
    public private(set) var windowFrame: CGRect = .null
    public private(set) var contentScaleFactor: CGFloat = 1

    public var resolution: CGSize {
        get { _resolution }
        set { _resolution = CGSize(width: max(newValue.width, 1), height: max(newValue.height, 1)) }
    }
    private var _resolution: CGSize {
        didSet {
            if oldValue != _resolution {
                self.postWindowEvent(type: .resized)
            }
        }
    }

    public var origin: CGPoint = .zero
    public var contentSize: CGSize {
        get { self.contentBounds.size }
        set { self.resolution = newValue * self.contentScaleFactor }
    }

    public private(set) var delegate: WindowDelegate?

    private(set) var display: OpaquePointer?
    private(set) var surface: OpaquePointer?

    private var xdgSurface: OpaquePointer?
    private var xdgToplevel: OpaquePointer?

    fileprivate var xdgSurfaceConfigured = false

    public required init?(name: String, style: WindowStyle, delegate: WindowDelegate?) {
        guard let app = (WaylandApplication.shared as? WaylandApplication) else {
            Log.error("Unable to identify Application class")
            return nil
        }
        let display = app.display
        let compositor = app.compositor
        let shell = app.shell

        self.display = display
        self.surface = wl_compositor_create_surface(compositor)
        if self.surface == nil {
            Log.error("wl_compositor_create_surface failed")
            return nil
        }
        self.xdgSurface = xdg_wm_base_get_xdg_surface(shell, surface)
        if self.xdgSurface == nil {
            Log.error("xdg_wm_base_get_xdg_surface failed")
            wl_surface_destroy(self.surface)
            return nil
        }

        self.delegate = delegate
        self._resolution = CGSize(width: 800, height: 600)
        self.contentScaleFactor = 1.0
        self.contentBounds = CGRect(origin: .zero, size: self._resolution * (1.0 / self.contentScaleFactor))
        self.windowFrame = self.contentBounds

        let context = unsafeBitCast(self as AnyObject, to: UnsafeMutableRawPointer.self)
        xdg_surface_add_listener(self.xdgSurface, &xdgSurfaceListener, context)

        self.xdgToplevel = xdg_surface_get_toplevel(self.xdgSurface)
        xdg_toplevel_add_listener(self.xdgToplevel, &xdgToplevelListener, context)
        xdg_toplevel_set_title(self.xdgToplevel, name)
        wl_surface_commit(self.surface)

        Task { @MainActor in
            app.bindSurface(self.surface, with: self)
            self.postWindowEvent(type: .created) 
        }
    }

    deinit {
        Task { @MainActor in 
            if let app = (WaylandApplication.shared as? WaylandApplication) {
                app.updateSurfaces()
            }
        }

        xdg_toplevel_destroy(self.xdgToplevel)
        xdg_surface_destroy(self.xdgSurface)
        wl_surface_destroy(self.surface)
    }

    public func show() {
        self.visible = true
        Task { self.postWindowEvent(type: .shown) }
    }

    public func hide() {
        self.activated = false
        self.visible = false
        Task { self.postWindowEvent(type: .hidden) }
    }

    public func activate() {
        self.activated = true
        self.visible = true
        Task { self.postWindowEvent(type: .activated) }
    }

    public func minimize() {
        self.activated = false
        self.visible = false
        Task { self.postWindowEvent(type: .minimized) }
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

#endif //if ENABLE_WAYLAND
