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
        Log.debug("wl_seat_listener.name: \(String(describing: name))")
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
        Log.debug("wl_keyboard_listener.keymap (format:\(format), fd:\(fd), size:\(size))")
    },
    enter: { data, keyboard, serial, surface, keys in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("wl_keyboard_listener.enter (serial:\(serial))")
    },
    leave: { data, keyboard, serial, surface in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("wl_keyboard_listener.leave (serial:\(serial))")
    },
    key: { data, keyboard, serial, time, key, state in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("wl_keyboard_listener.key (serial:\(serial), time:\(time), key:\(key), state:\(state))")
    },
    modifiers: { data, keyboard, serial, depressed, latched, locked, group in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("wl_keyboard_listener.modifiers (serial:\(serial), depressed:\(depressed), latched:\(latched), locked:\(locked), group:\(group))")
    },
    repeat_info: { data, keyboard, rate, delay in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("wl_keyboard_listener.repeat_info (rate:\(rate), delay:\(delay))")
    }
)


final class WaylandApplication: Application, @unchecked Sendable {

    var activationPolicy: ActivationPolicy = .regular

    private(set) var display: OpaquePointer?
    private(set) var registry: OpaquePointer?
    fileprivate(set) var compositor: OpaquePointer?
    fileprivate(set) var shell: OpaquePointer?
    fileprivate(set) var seat: OpaquePointer?
    fileprivate(set) var pointer: OpaquePointer?
    fileprivate(set) var keyboard: OpaquePointer?

    private var requestExitWithCode: Int? = nil

    static func run(delegate: ApplicationDelegate?) -> Int {
        guard let app = WaylandApplication() else {
            Log.error("Failed to initialize wayland client.")
            return -1
        }

        self.shared = app
        delegate?.initialize(application: app)

        let display = app.display
        var result = 0

        while true {
            while wl_display_prepare_read(display) != 0 {
                wl_display_dispatch_pending(display)
            }
            wl_display_flush(display)
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
            windowSurfaceMap[surface] = WeakWindow(window: window)
        }
    }
    func window(forSurface surface: OpaquePointer?) -> WaylandWindow? {
        if let surface = surface { return windowSurfaceMap[surface]?.window }
        return nil
    }
    func updateSurfaces() {
        let activeWindows = self.windowSurfaceMap.compactMapValues { $0.window }
        self.windowSurfaceMap = activeWindows.mapValues { WeakWindow(window: $0) }
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

        wl_registry_add_listener(registry, &registryListener, unsafeBitCast(self as AnyObject, to: UnsafeMutableRawPointer.self))
        // wl_display_dispatch(display)
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
        if shell != nil { xdg_wm_base_destroy(shell) }

        if compositor != nil { wl_compositor_destroy(compositor) }
        if registry != nil { wl_registry_destroy(registry) }
        if display != nil { wl_display_disconnect(display) }
    }

    var pointerTarget: WaylandWindow? = nil
    var pointerLocation: CGPoint = .zero    // location in target surface

    fileprivate func pointerEnter(serial: UInt32, surface: OpaquePointer?, x: Double, y: Double) {
        pointerTarget = self.window(forSurface: surface)
        //Log.debug("wl_pointer_listener.enter (serial:\(serial), x:\(x), y:\(y))")
    }

    fileprivate func pointerLeave(serial: UInt32, surface: OpaquePointer?) {
        pointerTarget = nil
        //Log.debug("wl_pointer_listener.leave (serial:\(serial))")
    }

    fileprivate func pointerMotion(time: UInt32, x: Double, y: Double) {
        if let target = pointerTarget {
            pointerLocation = CGPoint(x: x, y: y)
            Task { @MainActor in
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
            let buttonID = Int(button) - BTN_MOUSE
            let type: MouseEventType = state == 0 ? .buttonUp : .buttonDown
            Task { @MainActor in
                target.postMouseEvent(MouseEvent(type: type,
                                                 window: target,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: buttonID,
                                                 location: pointerLocation))
            }
        }
        //Log.debug("wl_pointer_listener.button (serial:\(serial), time:\(time), button:\(button), state:\(state))")
    }

    fileprivate func pointerAxis(time: UInt32, axis: UInt32, value: Double) {
        if let target = pointerTarget {
            let delta = CGPoint(x: 0, y: value)
            Task { @MainActor in
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
        // Log.debug("wl_pointer_listener.frame")
    }

    fileprivate func pointerAxis(source: UInt32) {
        //Log.debug("wl_pointer_listener.axis_source (source:\(source))")
    }

    fileprivate func pointerAxisStop(time: UInt32, axis: UInt32) {
        //Log.debug("wl_pointer_listener.axis_top (time:\(time), axis:\(axis))")
    }

    fileprivate func pointerAxis(_ axis: UInt32, discrete: Int32) {
        //Log.debug("wl_pointer_listener.axis_discrete (axis:\(axis), discrete:\(discrete))")
    }
}

#endif //if ENABLE_WAYLAND
