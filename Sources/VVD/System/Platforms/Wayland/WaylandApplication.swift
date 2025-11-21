//
//  File: WaylandApplication.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation
@preconcurrency
import Wayland

private let BTN_MOUSE		= 0x110
private let BTN_LEFT		= 0x110
private let BTN_RIGHT		= 0x111
private let BTN_MIDDLE		= 0x112
private let BTN_SIDE		= 0x113
private let BTN_EXTRA		= 0x114
private let BTN_FORWARD		= 0x115
private let BTN_BACK		= 0x116
private let BTN_TASK		= 0x117

nonisolated(unsafe)
private var registryListener = wl_registry_listener(
    global: { data, registry, name, interface, version in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication

        let interfaceName = String(utf8String: interface!)!
        Log.debug("wl_registry_listener.global (interface:\"\(interfaceName)\", version:\(version))")

        if strcmp(interface!, wl_compositor_interface.name) == 0 {
            let compositor = wl_registry_bind(registry, name, wl_compositor_interface_ptr, min(version, 4))
            app.compositor = .init(compositor)
        }
        else if strcmp(interface!, xdg_wm_base_interface.name) == 0 {
            let shell = wl_registry_bind(registry, name, xdg_wm_base_interface_ptr, min(version, 4))
            app.shell = .init(shell)
            xdg_wm_base_add_listener(app.shell, &xdgWmBaseListener, data)
        }
        else if strcmp(interface!, xdg_activation_v1_interface.name) == 0 {
            let activationManager = wl_registry_bind(registry, name, xdg_activation_v1_interface_ptr, min(version, 1))
            app.activationManager = .init(activationManager)
        }
        else if strcmp(interface!, wp_fractional_scale_manager_v1_interface.name) == 0 {
            let fractionalScaleManager = wl_registry_bind(registry, name, wp_fractional_scale_manager_v1_interface_ptr, min(version, 1))
            app.fractionalScaleManager = .init(fractionalScaleManager)
        }
        else if strcmp(interface!, zxdg_decoration_manager_v1_interface.name) == 0 {
            let decorationManager = wl_registry_bind(registry, name, zxdg_decoration_manager_v1_interface_ptr, min(version, 1))
            app.decorationManager = .init(decorationManager)
        }
        else if strcmp(interface!, wl_seat_interface.name) == 0 {
            let seat = wl_registry_bind(registry, name, wl_seat_interface_ptr, min(version, 5))
            app.seat = .init(seat)
            wl_seat_add_listener(app.seat, &seatListener, data)
        }
    },
    global_remove: { (data, registry, name) in
        Log.debug("wl_registry_listener.global_remove (name: \(String(describing: name)))")
    }
)

nonisolated(unsafe)
private var xdgWmBaseListener = xdg_wm_base_listener(
    ping: { data, shell, serial in
        Log.debug("xdg_wm_base_listener.ping (serial:\(serial))")
        xdg_wm_base_pong(shell, serial)
    }
)

nonisolated(unsafe)
private var seatListener = wl_seat_listener(
    capabilities: { data, seat, capabilities in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("wl_seat_listener.capabilities: \(capabilities)")

        if capabilities & WL_SEAT_CAPABILITY_POINTER.rawValue != 0 {
            if app.pointer == nil {
                app.pointer = wl_seat_get_pointer(seat)
                wl_pointer_add_listener(app.pointer, &pointerListener, data)
            }
        } else {
            if app.pointer != nil {
                wl_pointer_destroy(app.pointer)
                app.pointer = nil
            }
        }

        if capabilities & WL_SEAT_CAPABILITY_KEYBOARD.rawValue != 0 {
            if app.keyboard == nil {
                app.keyboard = wl_seat_get_keyboard(seat)
                wl_keyboard_add_listener(app.keyboard, &keyboardListener, data)
            }
        } else {
            if app.keyboard != nil {
                wl_keyboard_destroy(app.keyboard)
                app.keyboard = nil
            }
        }
    },
    name: { data, seat, name in
        let n = if let name { String(cString: name) } else { "" }
        Log.debug("wl_seat_listener.name: \(n)")
    }
)

nonisolated(unsafe)
private var pointerListener = wl_pointer_listener(
    enter: { data, pointer, serial, surface, x, y in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.pointerEnter(serial: serial, surface: surface, x: wl_fixed_to_double(x), y: wl_fixed_to_double(y))
    },
    leave: { data, pointer, serial, surface in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.pointerLeave(serial: serial, surface: surface)
    },
    motion: { data, pointer, time, x, y in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.pointerMotion(time: time, x: wl_fixed_to_double(x), y: wl_fixed_to_double(y))
    },
    button: { data, pointer, serial, time, button, state in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.pointerButton(serial: serial, time: time, button: button, state: state)
    },
    axis: {data, pointer, time, axis, value in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.pointerAxis(time: time, axis: axis, value: wl_fixed_to_double(value))
    },
    frame: { data, pointer in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.pointerFrame()
    },
    axis_source: { data, pointer, source in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.pointerAxis(source: source)
    },
    axis_stop: { data, pointer, time, axis in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.pointerAxisStop(time: time, axis: axis)
    },
    axis_discrete: { data, pointer, axis, discrete in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.pointerAxis(axis, discrete: discrete)
    },
    axis_value120: { data, pointer, axis, value120 in
    },
    axis_relative_direction: { data, pointer, axis, direction in
    }
)

nonisolated(unsafe)
private var keyboardListener = wl_keyboard_listener(
    keymap: { data, keyboard, format, fd, size in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.keyboardKeymap(format: format, fd: fd, size: size)
    },
    enter: { data, keyboard, serial, surface, keys in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        var keyArray: [UInt8] = []
        let keyCount = keys?.pointee.size ?? 0
        if keyCount > 0 {
            let ptr = keys?.pointee.data.assumingMemoryBound(to: UInt8.self)
            keyArray = Array(UnsafeBufferPointer(start: ptr, count: Int(keyCount)))
        }
        app.keyboardEnter(serial: serial, surface: surface, keys: keyArray)
    },
    leave: { data, keyboard, serial, surface in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.keyboardLeave(serial: serial, surface: surface)
    },
    key: { data, keyboard, serial, time, key, state in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.keyboardKey(serial: serial, time: time, key: key, state: state)
    },
    modifiers: { data, keyboard, serial, depressed, latched, locked, group in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.keyboardModifiers(serial: serial, depressed: depressed, latched: latched, locked: locked, group: group)
    },
    repeat_info: { data, keyboard, rate, delay in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.keyboardRepeatInfo(rate: rate, delay: delay)
    }
)


final class WaylandApplication: Application, @unchecked Sendable {

    var activationPolicy: ActivationPolicy = .regular
    var isActive: Bool {
        activeWindow != nil
    }

    private(set) var display: OpaquePointer?
    private(set) var registry: OpaquePointer?
    fileprivate(set) var compositor: OpaquePointer?
    fileprivate(set) var shell: OpaquePointer?
    fileprivate(set) var activationManager: OpaquePointer?
    fileprivate(set) var fractionalScaleManager: OpaquePointer?
    fileprivate(set) var decorationManager: OpaquePointer?
    fileprivate(set) var seat: OpaquePointer?
    fileprivate(set) var pointer: OpaquePointer?
    fileprivate(set) var keyboard: OpaquePointer?
    
    private var xkbContext: XKBContext? = nil

    private var requestExitWithCode: Int? = nil

    static func run(delegate: ApplicationDelegate?) -> Int {
        precondition(Thread.isMainThread, "\(#function) must be called on the main thread.")

        guard let app = WaylandApplication() else {
            Log.error("Failed to initialize wayland client.")
            return -1
        }

        self.shared = app
        delegate?.initialize(application: app)

        let display = app.display
        var result = 0

        while true {
            wl_display_flush(display)

            while wl_display_prepare_read(display) != 0 {
                wl_display_dispatch_pending(display)
            }

            wl_display_read_events(display)
            wl_display_dispatch_pending(display)
            
            if let code = app.requestExitWithCode {
                result = code
                break
            }

            let next = RunLoop.main.limitDate(forMode: .default)
            let s = next?.timeIntervalSinceNow ?? 1.0
            if s > 0.0 {
                Platform.threadYield()
            }
        }

        delegate?.finalize(application: app)
        self.shared = nil        
        return result
    }

    func terminate(exitCode : Int) {
        Task { @MainActor in requestExitWithCode = exitCode }
    }
    
    nonisolated(unsafe)
    static var shared: WaylandApplication? = nil

    typealias WeakWindow = WeakObject<WaylandWindow>
    private var windowSurfaceMap: [OpaquePointer: WeakWindow] = [:]

    func bindSurface(_ surface: OpaquePointer?, with window: WaylandWindow) {
        if let surface = surface {
            windowSurfaceMap[surface] = WeakWindow(window)
        }
    }
    func window(forSurface surface: OpaquePointer?) -> WaylandWindow? {
        if let surface = surface { return windowSurfaceMap[surface]?.value }
        return nil
    }
    func updateSurfaces() {
        let activeWindows = self.windowSurfaceMap.compactMapValues { $0.value }
        self.windowSurfaceMap = activeWindows.mapValues { WeakWindow($0) }
    }

    @MainActor
    func updateActivation() {
        let active = self.windowSurfaceMap.values.first {
            $0.value?.activated ?? false
        }
        let wasActive = self.isActive
        if let active = active?.value {
            self.activeWindow = active
        } else {
            self.activeWindow = nil            
        }
        let nowActive = self.isActive
        if nowActive != wasActive {
            Log.info("Application activation state changed: \(nowActive)")
        }
    }

    private init?() {
        Log.info("Wayland version: \(WAYLAND_VERSION)")

        self.display = wl_display_connect(nil)
        if self.display == nil {
            Log.error("wl_display_connect failed.")
            return nil
        }
        self.registry = wl_display_get_registry(self.display)
        if self.registry == nil {
            Log.error("wl_display_get_registry failed.")
            return nil
        }

        self.xkbContext = XKBContext()

        wl_registry_add_listener(registry, &registryListener, unsafeBitCast(self as AnyObject, to: UnsafeMutableRawPointer.self))
        wl_display_roundtrip(display)

        if self.compositor == nil || self.shell == nil {
            Log.err("Cannot bind wayland protocols.")

            if pointer != nil { wl_pointer_destroy(pointer) }
            if seat != nil { wl_seat_destroy(seat) }

            if shell != nil { xdg_wm_base_destroy(shell) }
            if compositor != nil { wl_compositor_destroy(compositor) }
            
            wl_registry_destroy(registry)
            wl_display_disconnect(display)

            return nil
        }
    }

    deinit {
        if pointer != nil { wl_pointer_destroy(pointer) }
        if keyboard != nil { wl_keyboard_destroy(keyboard) }
        if seat != nil { wl_seat_destroy(seat) }
        if activationManager != nil { xdg_activation_v1_destroy(activationManager) }
        if fractionalScaleManager != nil { wp_fractional_scale_manager_v1_destroy(fractionalScaleManager) }
        if decorationManager != nil { zxdg_decoration_manager_v1_destroy(decorationManager) }
        if shell != nil { xdg_wm_base_destroy(shell) }

        if compositor != nil { wl_compositor_destroy(compositor) }
        if registry != nil { wl_registry_destroy(registry) }
        if display != nil { wl_display_disconnect(display) }
    }

    var pointerTarget: WaylandWindow? = nil
    var pointerLocation: CGPoint = .zero    // location in target surface
    weak var activeWindow: WaylandWindow? = nil

    fileprivate func pointerEnter(serial: UInt32, surface: OpaquePointer?, x: Double, y: Double) {
        pointerTarget = self.window(forSurface: surface)
        Log.debug("wl_pointer_listener.enter (serial:\(serial), x:\(x), y:\(y))")
    }

    fileprivate func pointerLeave(serial: UInt32, surface: OpaquePointer?) {
        pointerTarget = nil
        Log.debug("wl_pointer_listener.leave (serial:\(serial))")
    }

    fileprivate func pointerMotion(time: UInt32, x: Double, y: Double) {
        if let target = pointerTarget {
            pointerLocation = CGPoint(x: x, y: y)
            MainActor.assumeIsolated {
                target.postMouseEvent(MouseEvent(type: .move,
                                      window: target,
                                      device: .genericMouse,
                                      deviceID: 0,
                                      buttonID: 0,
                                      location: pointerLocation))
            }
        }
        //Log.debug("wl_pointer_listener.motion (time:\(time), x:\(x), y:\(y))")
    }

    fileprivate func pointerButton(serial: UInt32, time: UInt32, button: UInt32, state: UInt32) {
        if let target = pointerTarget {

            // alt+ctrl+click to move window if server-side decoration is not used.
            if self.decorationManager == nil && target.isServerSideDecoration == false {
                if (button == BTN_LEFT && state == WL_POINTER_BUTTON_STATE_PRESSED.rawValue) {
                    let alt = self.xkbContext?.isModifierActive(XKB_MOD_NAME_ALT)
                    let ctrl = self.xkbContext?.isModifierActive(XKB_MOD_NAME_CTRL)
                    if alt == true && ctrl == true {
                        let movable: WindowStyle = [.title, .closeButton, .minimizeButton, .maximizeButton]
                        if target.style.intersection(movable).isEmpty == false {
                            xdg_toplevel_move(target.xdgToplevel, self.seat, serial)
                            return
                        }
                    }
                }                
            }

            let buttonID = Int(button) - BTN_MOUSE
            let type: MouseEventType = state == 0 ? .buttonUp : .buttonDown
            MainActor.assumeIsolated {
                target.postMouseEvent(MouseEvent(type: type,
                                                 window: target,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: buttonID,
                                                 location: pointerLocation))
            }
        }
        Log.debug("wl_pointer_listener.button (serial:\(serial), time:\(time), button:\(button), state:\(state))")
    }

    fileprivate func pointerAxis(time: UInt32, axis: UInt32, value: Double) {
        if let target = pointerTarget {
            let delta = CGPoint(x: 0, y: value)
            MainActor.assumeIsolated {
                target.postMouseEvent(MouseEvent(type: .wheel,
                                                 window: target,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: 2,
                                                 location: pointerLocation,
                                                 delta: delta))
            }
        }
        //Log.debug("wl_pointer_listener.axis (time:\(time), axis:\(axis), value:\(value))")
    }

    fileprivate func pointerFrame() { // end of single-frame of event sequence.
        //Log.debug("wl_pointer_listener.frame")
    }

    fileprivate func pointerAxis(source: UInt32) {
        Log.debug("wl_pointer_listener.axis_source (source:\(source))")
    }

    fileprivate func pointerAxisStop(time: UInt32, axis: UInt32) {
        Log.debug("wl_pointer_listener.axis_top (time:\(time), axis:\(axis))")
    }

    fileprivate func pointerAxis(_ axis: UInt32, discrete: Int32) {
        Log.debug("wl_pointer_listener.axis_discrete (axis:\(axis), discrete:\(discrete))")
    }

    fileprivate func keyboardKeymap(format: UInt32, fd: Int32, size: UInt32) {
        self.xkbContext?.updateKeyMap(fromFD: fd, size: Int(size))
        Log.debug("wl_keyboard_listener.keymap (format:\(format), fd:\(fd), size:\(size))")
    }

    fileprivate func keyboardEnter(serial: UInt32, surface: OpaquePointer?, keys: [UInt8]) {
        let symbols = keys.map {
            self.xkbContext?.symbol(forKey: UInt32($0))
        }
        symbols.indices.forEach {
            let symbol = symbols[$0]
            Log.debug("Symbol[\($0)]: \(String(describing: symbol))")
        }
        Log.debug("wl_keyboard_listener.enter (serial:\(serial))")
    }

    fileprivate func keyboardLeave(serial: UInt32, surface: OpaquePointer?) {
        Log.debug("wl_keyboard_listener.leave (serial:\(serial))")
    }

    fileprivate func keyboardKey(serial: UInt32, time: UInt32, key: UInt32, state: UInt32) {
        if let state = self.xkbContext?.updateKey(key, state: state) {
            Log.debug("xkb_state_component: \(state)")
        }
        if let symbol = self.xkbContext?.symbol(forKey: key) {
            let code = VirtualKey.from(scanCode: key)
            let pressed = state == WL_KEYBOARD_KEY_STATE_PRESSED.rawValue
            Log.debug("Key: \(key), Symbol: \(String(describing: symbol)), VirtualKey: \(code), pressed: \(pressed)")
            let keyEvent = KeyboardEvent(type: pressed ? .keyDown : .keyUp,
                                         window: self.activeWindow,
                                         deviceID: 0,
                                         key: code,
                                         text: "")
            MainActor.assumeIsolated {
                self.activeWindow?.postKeyboardEvent(keyEvent)
            }
        } else {
            Log.debug("Key: \(key), Symbol: nil, VirtualKey: .none")
        }
        Log.debug("wl_keyboard_listener.key (serial:\(serial), time:\(time), key:\(key), state:\(state))")
    }

    fileprivate func keyboardModifiers(serial: UInt32, depressed: UInt32, latched: UInt32, locked: UInt32, group: UInt32) {
        if let state = self.xkbContext?.updateModifiers(depressed: depressed, latched: latched, locked: locked, group: group) {
            Log.debug("xkb_state_component: \(state)")
        }
        Log.debug("wl_keyboard_listener.modifiers (serial:\(serial), depressed:\(depressed), latched:\(latched), locked:\(locked), group:\(group))")
    }

    fileprivate func keyboardRepeatInfo(rate: Int32, delay: Int32) {
        Log.debug("wl_keyboard_listener.repeat_info (rate:\(rate), delay:\(delay))")
    }
}

#endif //if ENABLE_WAYLAND
