//
//  File: WaylandWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation
import Wayland


nonisolated(unsafe)
var xdgSurfaceListener = xdg_surface_listener(
    configure: { data, surface, serial in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow

        Log.debug("xdg_surface_listener.configure (serial:\(serial))")

        xdg_surface_ack_configure(surface, serial)

        MainActor.assumeIsolated {
            window.postWindowEvent(type: .resized)
        }
    }
)

nonisolated(unsafe)
var xdgToplevelListener = xdg_toplevel_listener(
    configure: { data, topLevel, width, height, states in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow
        if width > 0 && height > 0 && window.style.contains(.resizableBorder) {
            MainActor.assumeIsolated {
                window.contentSize = CGSize(width: CGFloat(width), height: CGFloat(height))
            }
        }
        Log.debug("xdg_toplevel_listener.configure (width:\(width), height:\(height))")
    },
    close: { data, topLevel in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow
        let closed = MainActor.assumeIsolated {
            window.requestToClose()
        }
        Log.debug("xdg_toplevel_listener.close (closed: \(closed))")
    },
    configure_bounds: { data, topLevel, width, height in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow
        Log.debug("xdg_toplevel_listener.configure_bounds (width:\(width), height:\(height))")
    },
    wm_capabilities: { data, topLevel, capabilities in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow
        Log.debug("xdg_toplevel_listener.wm_capabilities")
    }
)

nonisolated(unsafe)
var xdgToplevelDecorationListener = zxdg_toplevel_decoration_v1_listener(
    configure: { data, decoration, mode in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow
        let modeStr = mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE.rawValue ? "server-side" : "client-side"
        Log.debug("zxdg_toplevel_decoration_v1_listener.configure (mode: \(modeStr))")
        
        MainActor.assumeIsolated {
            window.decorationMode = mode
        }
    }
)

nonisolated(unsafe)
var fractionalScaleListener = wp_fractional_scale_v1_listener(
    preferred_scale: { data, fractionalScale, scale in
        let window = unsafeBitCast(data, to: AnyObject.self) as! WaylandWindow
        // The scale is the numerator of a fraction with a denominator of 120
        let scaleFactor = Double(scale) / 120.0
        Log.debug("wp_fractional_scale_v1_listener.preferred_scale (scale: \(scale)/120 = \(scaleFactor))")
        
        MainActor.assumeIsolated {
            let newScaleFactor = CGFloat(scaleFactor)
            window.contentScaleFactor = newScaleFactor
        }
    }
)

@MainActor
final class WaylandWindow: Window {

    private(set) var activated: Bool = false
    private(set) var visible: Bool = false

    private(set) var contentBounds: CGRect = .null
    private(set) var windowFrame: CGRect = .null
    fileprivate(set) var contentScaleFactor: CGFloat = 1 {
        didSet {
            if oldValue != contentScaleFactor {
                assert(contentScaleFactor > 0)
                let size = self.contentSize
                self.contentSize = size
            }
        }
    }

    let style: WindowStyle

    var resolution: CGSize {
        get { _resolution }
        set { _resolution = CGSize(width: max(newValue.width, 1), height: max(newValue.height, 1)) }
    }
    private var _resolution: CGSize {
        didSet {
            if oldValue != _resolution {
                assert(_resolution.width >= 1 && _resolution.height >= 1)
                self.contentBounds.size = _resolution * (1.0 / self.contentScaleFactor)
                self.windowFrame.size = self.contentBounds.size
                self.postWindowEvent(type: .resized)
            }
        }
    }

    var origin: CGPoint = .zero
    var contentSize: CGSize {
        get { self.contentBounds.size }
        set { self.resolution = newValue * self.contentScaleFactor }
    }

    var title: String {
        didSet {
            if oldValue != title {
                if let xdgToplevel = self.xdgToplevel {
                    xdg_toplevel_set_title(xdgToplevel, title)
                    wl_surface_commit(self.surface)
                }
            }
        }
    }

    private(set) var delegate: WindowDelegate?
    
    var platformHandle: OpaquePointer? { surface }
    var isValid: Bool { surface != nil }

    private(set) var display: OpaquePointer?
    nonisolated(unsafe) private(set) var surface: OpaquePointer?

    nonisolated(unsafe) private var xdgSurface: OpaquePointer?
    nonisolated(unsafe) private(set) var xdgToplevel: OpaquePointer?
    nonisolated(unsafe) private var xdgToplevelDecoration: OpaquePointer?
    nonisolated(unsafe) private var fractionalScaleObject: OpaquePointer?

    nonisolated(unsafe) fileprivate var decorationMode: UInt32 = ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE.rawValue

    nonisolated var isServerSideDecoration: Bool {
        return decorationMode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE.rawValue
    }

    required init?(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) {
        guard let app = WaylandApplication.shared else {
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
        self.style = style
        self._resolution = CGSize(width: 800, height: 600)
        self.contentScaleFactor = 1.0
        self.contentBounds = CGRect(origin: .zero, size: self._resolution * (1.0 / self.contentScaleFactor))
        self.windowFrame = self.contentBounds
        self.title = name

        let context = unsafeBitCast(self as AnyObject, to: UnsafeMutableRawPointer.self)
        xdg_surface_add_listener(self.xdgSurface, &xdgSurfaceListener, context)

        self.xdgToplevel = xdg_surface_get_toplevel(self.xdgSurface)
        xdg_toplevel_add_listener(self.xdgToplevel, &xdgToplevelListener, context)
        xdg_toplevel_set_title(self.xdgToplevel, name)
        
        // Request fractional scale if available
        if let fractionalScaleManager = app.fractionalScaleManager {
            self.fractionalScaleObject = wp_fractional_scale_manager_v1_get_fractional_scale(fractionalScaleManager, self.surface)
            if let fractionalScale = self.fractionalScaleObject {
                wp_fractional_scale_v1_add_listener(fractionalScale, &fractionalScaleListener, context)
                Log.debug("Requested fractional scale for window: \(name)")
            }
        }

        let decorationStyles: WindowStyle = [.title, .closeButton, .minimizeButton, .maximizeButton, .resizableBorder]
        if style.intersection(decorationStyles).isEmpty == false {
            // Request server-side decoration if available
            if let decorationManager = app.decorationManager {
                self.xdgToplevelDecoration = zxdg_decoration_manager_v1_get_toplevel_decoration(decorationManager, self.xdgToplevel)
                if let decoration = self.xdgToplevelDecoration {
                    zxdg_toplevel_decoration_v1_add_listener(decoration, &xdgToplevelDecorationListener, context)
                    zxdg_toplevel_decoration_v1_set_mode(decoration, ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE.rawValue)
                    Log.debug("Requested server-side decoration for window: \(name)")
                }
            }
        }
        
        wl_surface_commit(self.surface)
    
        app.bindSurface(self.surface, with: self)
        self.postWindowEvent(type: .created)

        Task { @MainActor [weak self] in
            if let self, self.surface != nil {
                if let minSize = self.delegate?.minimumContentSize(window: self) {
                    xdg_toplevel_set_min_size(self.xdgToplevel, Int32(minSize.width), Int32(minSize.height))
                }
                if let maxSize = self.delegate?.maximumContentSize(window: self) {
                    xdg_toplevel_set_max_size(self.xdgToplevel, Int32(maxSize.width), Int32(maxSize.height))
                }
            }
        }
    }

    deinit {
        self.destroy()
    }

    nonisolated func destroy() {
        if self.surface == nil {
            return
        }

        // Destroy in reverse order of creation
        // The decoration and fractional scale objects must be destroyed before their associated objects
        if let decoration = self.xdgToplevelDecoration {
            zxdg_toplevel_decoration_v1_destroy(decoration)
        }
        if let fractionalScale = self.fractionalScaleObject {
            wp_fractional_scale_v1_destroy(fractionalScale)
        }
        xdg_toplevel_destroy(self.xdgToplevel)
        xdg_surface_destroy(self.xdgSurface)
        wl_surface_destroy(self.surface)

        self.fractionalScaleObject = nil
        self.xdgToplevelDecoration = nil
        self.xdgToplevel = nil
        self.xdgSurface = nil
        self.surface = nil

        Task { @MainActor [weak self] in 
            if let app = WaylandApplication.shared {
                app.updateSurfaces()
            }
            if let self {
                self.postWindowEvent(type: .closed)
            }
        }
    }

    func show() {
        self.visible = true
        Task { self.postWindowEvent(type: .shown) }
    }

    func hide() {
        self.activated = false
        self.visible = false
        Task { self.postWindowEvent(type: .hidden) }
    }

    func activate() {
        self.activated = true
        self.visible = true
        Task { self.postWindowEvent(type: .activated) }
    }

    func minimize() {
        self.activated = false
        self.visible = false
        Task { self.postWindowEvent(type: .minimized) }
    }

    @discardableResult
    func requestToClose() -> Bool {
        var close = true
        if let answer = self.delegate?.shouldClose(window: self) {
            close = answer
        }
        if close {
            self.destroy()
        }
        return close
    }

    func showMouse(_: Bool, forDeviceID: Int) {

    }

    func isMouseVisible(forDeviceID: Int) -> Bool {
        false 
    }

    func lockMouse(_: Bool, forDeviceID: Int) {

    }

    func isMouseLocked(forDeviceID: Int) -> Bool {
        false
    }

    func setMousePosition(_: CGPoint, forDeviceID: Int) {

    }

    func mousePosition(forDeviceID: Int) -> CGPoint? {
        nil
    }

    func enableTextInput(_ enable: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            
        }
    }

    func isTextInputEnabled(forDeviceID deviceID: Int) -> Bool {
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
        let offset = self.windowFrame.origin + self.contentBounds.origin
        return point + offset
    }
    
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint {
        let offset = self.windowFrame.origin + self.contentBounds.origin
        return point - offset
    }
}

#endif //if ENABLE_WAYLAND
