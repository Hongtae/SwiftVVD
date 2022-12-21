//
//  File: WaylandApplication.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation
import Wayland


private var registryListener = wl_registry_listener(
    global: { data, registry, name, interface, version in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication

        let interfaceName = String(utf8String: interface!)!
        Log.debug("Waynald-Registry interface:\"\(interfaceName)\", version:\(version)")

        if strcmp(interface!, wl_compositor_interface.name) == 0 {
            let compositor = wl_registry_bind(registry, name, wl_compositor_interface_ptr, min(version, 4))
            app.compositor = .init(compositor)
        }
        else if strcmp(interface!, xdg_wm_base_interface.name) == 0 {
            let shell = wl_registry_bind(registry, name, xdg_wm_base_interface_ptr, min(version, 1))
            app.shell = .init(shell)
            xdg_wm_base_add_listener(app.shell, &xdgWmBaseListener, data)
        }
        else if strcmp(interface!, wl_seat_interface.name) == 0 {
            let seat = wl_registry_bind(registry, name, wl_seat_interface_ptr, min(version, 2))
            app.seat = .init(seat)
            wl_seat_add_listener(app.seat, &seatListener, data)
        }
    },
    global_remove: { (data, registry, name) in
    }
)

private var xdgWmBaseListener = xdg_wm_base_listener(
    ping: { data, shell, serial in
        Log.debug("xdg_wm_base_listener.ping (serial:\(serial))")
        xdg_wm_base_pong(shell, serial)
    }
)

private var seatListener = wl_seat_listener(
    capabilities: { data, seat, capabilities in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Seat.Listener capabilities: \(capabilities)")

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
    }
)

private var pointerListener = wl_pointer_listener(
    enter: { data, pointer, serial, surface, x, y in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Pointer.enter (serial:\(serial), x:\(x), y:\(y))")
    },
    leave: { data, pointer, serial, surface in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Pointer.leave (serial:\(serial))")
    },
    motion: { data, pointer, time, x, y in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Pointer.motion (x:\(x), y:\(y))")
    },
    button: { data, pointer, serial, time, button, state in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Pointer.button (serial:\(serial), state:\(state))")
    },
    axis: {data, pointer, time, axis, value in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Pointer.axis (axis:\(axis), value:\(value))")
    },
    frame: { data, pointer in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Pointer.frame")
    },
    axis_source: { data, pointer, axis_source in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Pointer.axis_source (axis_source:\(axis_source))")
    },
    axis_stop: { data, pointer, time, axis in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Pointer.axis_top (axis:\(axis))")
    },
    axis_discrete: { data, pointer, axis, discrete in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Pointer.axis_discrete (axis:\(axis), discrete:\(discrete))")
    }
)

private var keyboardListener = wl_keyboard_listener(
    keymap: { data, keyboard, format, fd, size in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Keyboard.keymap (format:\(format), fd:\(fd), size:\(size))")
    },
    enter: { data, keyboard, serial, surface, keys in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Keyboard.enter (serial:\(serial))")
    },
    leave: { data, keyboard, serial, surface in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Keyboard.leave (serial:\(serial))")
    },
    key: { data, keyboard, serial, time, key, state in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Keyboard.key (serial:\(serial), time:\(time), key:\(key), state:\(state))")
    },
    modifiers: { data, keyboard, serial, depressed, latched, locked, group in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Keyboard.modifiers (serial:\(serial), depressed:\(depressed), latched:\(latched), locked:\(locked), group:\(group))")
    },
    repeat_info: { data, keyboard, rate, delay in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        Log.debug("Keyboard.repeat_info (rate:\(rate), delay:\(delay))")
    }
)


public class WaylandApplication: Application {

    private(set) var display: OpaquePointer?
    private(set) var registry: OpaquePointer?
    fileprivate(set) var compositor: OpaquePointer?
    fileprivate(set) var shell: OpaquePointer?
    fileprivate(set) var seat: OpaquePointer?
    fileprivate(set) var pointer: OpaquePointer?
    fileprivate(set) var keyboard: OpaquePointer?

    private var terminateRequestedWithExitCode: Int? = nil

    public static func run(delegate: ApplicationDelegate?) -> Int {
        guard let app = WaylandApplication() else {
            Log.error("Failed to initialize wayland client.")
            return -1
        }

        self.shared = app
        app.terminateRequestedWithExitCode = nil
        delegate?.initialize(application: app)

        let display = app.display
        var result = 0

        // while true {
        //     Log.debug("wl_display_dispatch")
        //     if wl_display_dispatch(display) < 0 {
        //         break
        //     }
        // }

        while true {
            while wl_display_prepare_read(display) != 0 {
                wl_display_dispatch_pending(display)
            }
            wl_display_flush(display)
            wl_display_read_events(display)
            wl_display_dispatch_pending(display)

            if let code = app.terminateRequestedWithExitCode {
                result = code
                break
            }

            let next = RunLoop.main.limitDate(forMode: .default)
            let s = next?.timeIntervalSinceNow ?? 1.0
            if s > 0.0 {
                // sleep for s
            }
        }


        // Log.debug("LOG - \(#file):\(#line)")
        // let fd = wl_display_get_fd(display)
        // let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.main)
        // src.setEventHandler(qos: .userInteractive) {
        //     wl_display_flush(display)
        //     wl_display_read_events(display)
        //     wl_display_dispatch_pending(display)
        //     Log.info("wl_display_dispatch_pending")
        // }
        // dispatchMain()

        delegate?.finalize(application: app)
        self.shared = nil        
        return result
    }

    public func terminate(exitCode : Int) {
        terminateRequestedWithExitCode = exitCode
    }
    
    public static var shared: Application? = nil

    private struct WeakWindow {
        weak var window: WaylandWindow?
    }
    private var windowList: [WeakWindow] = []

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
        wl_display_dispatch(display)
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

        wl_compositor_destroy(compositor)
        wl_registry_destroy(registry)
        wl_display_disconnect(display)
    }
}

#endif //if ENABLE_WAYLAND
