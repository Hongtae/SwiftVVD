//
//  File: WaylandApplication.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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
private var outputListener = wl_output_listener(
    geometry: { data, output, x, y, _, _, _, _, _, _ in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.outputGeometry(output, x: x, y: y)
    },
    mode: { data, output, flags, width, height, _ in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.outputMode(output, flags: flags, width: width, height: height)
    },
    done: { data, output in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.outputDone(output)
    },
    scale: { data, output, factor in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.outputScale(output, factor: factor)
    },
    name: { data, output, name in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.outputName(output, name: name)
    },
    description: { data, output, description in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.outputDescription(output, description: description)
    }
)

nonisolated(unsafe)
private var registryListener = wl_registry_listener(
    global: { data, registry, name, interface, version in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication

        let interfaceName = String(utf8String: interface!)!
        Log.debug("wl_registry_listener.global (interface:\"\(interfaceName)\", version:\(version))")

        if strcmp(interface!, wl_compositor_interface.name) == 0 {
            let compositor = wl_registry_bind(registry, name, wl_compositor_interface_ptr, min(version, 4))
            app.compositor = .init(compositor)
            app.configureCursorManager()
        }
        else if strcmp(interface!, wl_shm_interface.name) == 0 {
            let sharedMemory = wl_registry_bind(
                registry,
                name,
                wl_shm_interface_ptr,
                min(version, 1)
            )
            app.sharedMemory = .init(sharedMemory)
            app.configureCursorManager()
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
        else if strcmp(interface!, wl_data_device_manager_interface.name) == 0 {
            let manager = wl_registry_bind(
                registry,
                name,
                wl_data_device_manager_interface_ptr,
                min(version, 3)
            )
            app.dataDeviceManager = .init(manager)
            app.configureClipboard()
        }
        else if strcmp(interface!, wl_seat_interface.name) == 0 {
            let seat = wl_registry_bind(registry, name, wl_seat_interface_ptr, min(version, 5))
            app.seat = .init(seat)
            wl_seat_add_listener(app.seat, &seatListener, data)
            app.configureClipboard()
        }
        else if strcmp(interface!, wl_output_interface.name) == 0 {
            let output = wl_registry_bind(registry, name, wl_output_interface_ptr, min(version, 4))
            app.bindOutput(name: name, output: .init(output))
            if let output = app.output(forName: name) {
                wl_output_add_listener(output, &outputListener, data)
            }
        }
    },
    global_remove: { (data, registry, name) in
        let app = unsafeBitCast(data, to: AnyObject.self) as! WaylandApplication
        app.removeOutput(name: name)
        Log.debug("wl_registry_listener.global_remove (name: \(String(describing: name)))")
    }
)

nonisolated(unsafe)
private var xdgWmBaseListener = xdg_wm_base_listener(
    ping: { data, shell, serial in
        //Log.debug("xdg_wm_base_listener.ping (serial:\(serial))")
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
                app.cancelActivePointerButtons()
                app.pointerEnterSerial = nil
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

    private let outputModeCurrentFlag: UInt32 = 0x1

    private struct KeyRepeatState {
        let key: UInt32
        let virtualKey: VirtualKey
        weak var window: WaylandWindow?
        var nextFireTime: Date
    }

    var activationPolicy: ActivationPolicy = .regular
    var isActive: Bool {
        activeWindow != nil
    }

    private(set) var display: OpaquePointer?
    private(set) var registry: OpaquePointer?
    fileprivate(set) var compositor: OpaquePointer?
    fileprivate(set) var sharedMemory: OpaquePointer?
    fileprivate(set) var shell: OpaquePointer?
    fileprivate(set) var activationManager: OpaquePointer?
    fileprivate(set) var fractionalScaleManager: OpaquePointer?
    fileprivate(set) var decorationManager: OpaquePointer?
    fileprivate(set) var dataDeviceManager: OpaquePointer?
    fileprivate(set) var seat: OpaquePointer?
    fileprivate(set) var pointer: OpaquePointer?
    fileprivate(set) var keyboard: OpaquePointer?
    
    private var xkbContext: XKBContext? = nil

    private var requestExitWithCode: Int? = nil
    private var keyRepeatRate: Int32 = 0
    private var keyRepeatDelay: Int32 = 0
    private var keyRepeatState: KeyRepeatState? = nil
    private var waylandClipboard: WaylandClipboard?
    private var cursorManager: WaylandCursorManager?

    var clipboard: (any Clipboard)? {
        waylandClipboard
    }

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
            app.processKeyRepeat()

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
        appFinalize()

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

    private struct OutputInfo {
        let registryName: UInt32
        var output: OpaquePointer?
        var origin: CGPoint = .zero
        var scaleFactor: CGFloat = 1
        var displayModeResolution: CGSize = .zero
        var name: String?
        var description: String?

        var screen: WaylandScreen? {
            guard displayModeResolution.width > 0,
                  displayModeResolution.height > 0 else {
                return nil
            }

            let scale = max(scaleFactor, 1)
            let frame = CGRect(x: origin.x,
                               y: origin.y,
                               width: displayModeResolution.width / scale,
                               height: displayModeResolution.height / scale)
            return WaylandScreen(id: ScreenID(rawValue: UInt64(registryName)),
                                 frame: frame,
                                 scaleFactor: scale,
                                 displayModeResolution: displayModeResolution)
        }
    }

    private var outputMap: [UInt32: OutputInfo] = [:]
    private var outputNameMap: [OpaquePointer: UInt32] = [:]

    var screens: [any Screen] {
        screenSnapshots()
    }

    var mainScreen: (any Screen)? {
        screenSnapshots().first
    }

    private func screenSnapshots() -> [WaylandScreen] {
        outputMap.values
            .sorted { $0.registryName < $1.registryName }
            .compactMap(\.screen)
    }

    func screen(matchingScaleFactor scaleFactor: CGFloat) -> WaylandScreen? {
        let screens = screenSnapshots()
        return screens.first { abs($0.scaleFactor - scaleFactor) < CGFloat.ulpOfOne } ?? screens.first
    }

    func bindOutput(name: UInt32, output: OpaquePointer?) {
        guard let output else { return }
        outputMap[name] = OutputInfo(registryName: name, output: output)
        outputNameMap[output] = name
    }

    func output(forName name: UInt32) -> OpaquePointer? {
        outputMap[name]?.output
    }

    func removeOutput(name: UInt32) {
        guard let info = outputMap.removeValue(forKey: name) else {
            return
        }
        if let output = info.output {
            outputNameMap[output] = nil
            wl_output_destroy(output)
        }
    }

    private func updateOutput(_ output: OpaquePointer?, _ update: (inout OutputInfo) -> Void) {
        guard let output,
              let name = outputNameMap[output],
              var info = outputMap[name] else {
            return
        }
        update(&info)
        outputMap[name] = info
    }

    func outputGeometry(_ output: OpaquePointer?, x: Int32, y: Int32) {
        updateOutput(output) {
            // Wayland does not expose toplevel window positions. Output geometry
            // is only an approximate global frame for fullscreen/screen metadata.
            $0.origin = CGPoint(x: Int(x), y: Int(y))
        }
    }

    func outputMode(_ output: OpaquePointer?, flags: UInt32, width: Int32, height: Int32) {
        updateOutput(output) {
            if flags & outputModeCurrentFlag != 0 || $0.displayModeResolution == .zero {
                $0.displayModeResolution = CGSize(width: Int(width), height: Int(height))
            }
        }
    }

    func outputDone(_ output: OpaquePointer?) {
    }

    func outputScale(_ output: OpaquePointer?, factor: Int32) {
        updateOutput(output) {
            $0.scaleFactor = CGFloat(max(factor, 1))
        }
    }

    func outputName(_ output: OpaquePointer?, name: UnsafePointer<CChar>?) {
        updateOutput(output) {
            $0.name = name.map { String(cString: $0) }
        }
    }

    func outputDescription(_ output: OpaquePointer?, description: UnsafePointer<CChar>?) {
        updateOutput(output) {
            $0.description = description.map { String(cString: $0) }
        }
    }

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
        let previousActiveWindow = self.activeWindow
        let active = self.windowSurfaceMap.values.first {
            $0.value?.activated ?? false
        }
        let wasActive = self.isActive
        if let active = active?.value {
            self.activeWindow = active
        } else {
            self.activeWindow = nil            
        }
        if previousActiveWindow !== self.activeWindow {
            previousActiveWindow?.resetMouseClickTracking()
            self.activeWindow?.resetMouseClickTracking()
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
            cursorManager = nil
            waylandClipboard?.invalidate()
            waylandClipboard = nil
            if dataDeviceManager != nil {
                wl_data_device_manager_destroy(dataDeviceManager)
            }
            if seat != nil { wl_seat_destroy(seat) }

            if shell != nil { xdg_wm_base_destroy(shell) }
            if sharedMemory != nil { wl_shm_destroy(sharedMemory) }
            if compositor != nil { wl_compositor_destroy(compositor) }
            
            wl_registry_destroy(registry)
            wl_display_disconnect(display)

            return nil
        }
    }

    deinit {
        if pointer != nil { wl_pointer_destroy(pointer) }
        if keyboard != nil { wl_keyboard_destroy(keyboard) }
        cursorManager = nil
        waylandClipboard?.invalidate()
        waylandClipboard = nil
        if dataDeviceManager != nil {
            wl_data_device_manager_destroy(dataDeviceManager)
        }
        if seat != nil { wl_seat_destroy(seat) }
        if activationManager != nil { xdg_activation_v1_destroy(activationManager) }
        if fractionalScaleManager != nil { wp_fractional_scale_manager_v1_destroy(fractionalScaleManager) }
        if decorationManager != nil { zxdg_decoration_manager_v1_destroy(decorationManager) }
        outputMap.values.forEach {
            if let output = $0.output {
                wl_output_destroy(output)
            }
        }
        if shell != nil { xdg_wm_base_destroy(shell) }

        if sharedMemory != nil { wl_shm_destroy(sharedMemory) }
        if compositor != nil { wl_compositor_destroy(compositor) }
        if registry != nil { wl_registry_destroy(registry) }
        if display != nil { wl_display_disconnect(display) }
    }

    var pointerTarget: WaylandWindow? = nil
    var pointerLocation: CGPoint = .zero    // location in target surface
    weak var activeWindow: WaylandWindow? = nil

    private struct PointerButtonState {
        weak var target: WaylandWindow?
        var buttonID: Int
        var clickCount: Int
        var location: CGPoint
        var timestamp: TimeInterval
    }

    private struct PointerAxisFrame {
        var delta = CGPoint.zero
        var axes: UInt8 = 0
        var stoppedAxes: UInt8 = 0
        var source = ScrollEventSource.unknown
        var timestamp: TimeInterval?
    }

    private var pointerAxisFrame = PointerAxisFrame()
    private var pointerAxisActiveAxes: UInt8 = 0
    private var pointerAxisSource = ScrollEventSource.unknown
    private var pointerEventClock = MillisecondTimestampExtender()
    private var pointerButtonStates: [Int: PointerButtonState] = [:]
    fileprivate var pointerEnterSerial: UInt32?

    fileprivate func configureCursorManager() {
        guard cursorManager == nil,
              let compositor,
              let sharedMemory else {
            return
        }
        cursorManager = WaylandCursorManager(
            compositor: compositor,
            sharedMemory: sharedMemory
        )
    }

    @MainActor
    func updateCursor(for window: WaylandWindow) {
        guard pointerTarget === window,
              let pointer,
              let serial = pointerEnterSerial,
              let cursorManager else {
            return
        }
        let applied = cursorManager.apply(
            window.cursorOverride,
            visible: window.mouseVisible,
            pointer: pointer,
            serial: serial,
            scale: Int32(max(ceil(window.contentScaleFactor), 1))
        )
        if !applied {
            Log.error("Unable to apply Wayland cursor for window: \(window.title)")
        }
    }

    fileprivate func configureClipboard() {
        guard waylandClipboard == nil,
              let display,
              let dataDeviceManager,
              let seat else {
            return
        }
        waylandClipboard = WaylandClipboard(
            display: display,
            manager: dataDeviceManager,
            seat: seat
        )
    }

    private func updateClipboardInputSerial(_ serial: UInt32) {
        waylandClipboard?.updateInputSerial(serial)
    }

    fileprivate func pointerEnter(serial: UInt32, surface: OpaquePointer?, x: Double, y: Double) {
        updateClipboardInputSerial(serial)
        pointerEnterSerial = serial
        pointerTarget = self.window(forSurface: surface)
        pointerLocation = CGPoint(x: x, y: y)
        let modifiers = keyboardModifierFlags()
        if let target = pointerTarget {
            MainActor.assumeIsolated {
                target.resetMouseClickTracking()
                updateCursor(for: target)
                target.postMouseEvent(MouseEvent(
                    type: .entered,
                    window: target,
                    device: .genericMouse,
                    deviceID: 0,
                    buttonID: 0,
                    modifiers: modifiers,
                    location: pointerLocation,
                    timestamp: ProcessInfo.processInfo.systemUptime
                ))
            }
        }
        Log.debug("wl_pointer_listener.enter (serial:\(serial), x:\(x), y:\(y))")
    }

    fileprivate func pointerLeave(serial: UInt32, surface: OpaquePointer?) {
        let modifiers = keyboardModifierFlags()
        if let target = pointerTarget {
            MainActor.assumeIsolated {
                target.postMouseEvent(MouseEvent(
                    type: .exited,
                    window: target,
                    device: .genericMouse,
                    deviceID: 0,
                    buttonID: 0,
                    modifiers: modifiers,
                    location: pointerLocation,
                    timestamp: ProcessInfo.processInfo.systemUptime
                ))
                target.resetMouseClickTracking()
            }
        }
        cancelActivePointerButtons()
        pointerTarget = nil
        pointerEnterSerial = nil
        pointerAxisFrame = PointerAxisFrame()
        pointerAxisActiveAxes = 0
        pointerAxisSource = .unknown
        Log.debug("wl_pointer_listener.leave (serial:\(serial))")
    }

    fileprivate func pointerMotion(time: UInt32, x: Double, y: Double) {
        let timestamp = pointerEventClock.timestamp(for: time)
        let modifiers = keyboardModifierFlags()
        if let target = pointerTarget {
            pointerLocation = CGPoint(x: x, y: y)
            for buttonID in Array(pointerButtonStates.keys) {
                pointerButtonStates[buttonID]?.location = pointerLocation
                pointerButtonStates[buttonID]?.timestamp = timestamp
            }
            MainActor.assumeIsolated {
                target.postMouseEvent(MouseEvent(type: .move,
                                      window: target,
                                      device: .genericMouse,
                                      deviceID: 0,
                                      buttonID: 0,
                                      modifiers: modifiers,
                                      location: pointerLocation,
                                      timestamp: timestamp))
            }
        }
        //Log.debug("wl_pointer_listener.motion (time:\(time), x:\(x), y:\(y))")
    }

    fileprivate func pointerButton(serial: UInt32, time: UInt32, button: UInt32, state: UInt32) {
        updateClipboardInputSerial(serial)
        let timestamp = pointerEventClock.timestamp(for: time)
        let buttonID = Int(button) - BTN_MOUSE
        let previousState = pointerButtonStates[buttonID]
        let modifiers = keyboardModifierFlags()
        if let target = pointerTarget ?? previousState?.target {
            let location = pointerTarget == nil
                ? previousState?.location ?? pointerLocation
                : pointerLocation

            // alt+ctrl+click to move window if server-side decoration is not used.
            if self.decorationManager == nil && target.isServerSideDecoration == false {
                if (button == BTN_LEFT && state == WL_POINTER_BUTTON_STATE_PRESSED.rawValue) {
                    let alt = self.xkbContext?.isModifierActive(XKB_MOD_NAME_ALT)
                    let ctrl = self.xkbContext?.isModifierActive(XKB_MOD_NAME_CTRL)
                    if alt == true && ctrl == true {
                        let movable: WindowStyle = [.title, .closeButton, .minimizeButton, .maximizeButton]
                        if target.style.intersection(movable).isEmpty == false {
                            MainActor.assumeIsolated {
                                target.resetMouseClickTracking()
                            }
                            xdg_toplevel_move(target.xdgToplevel, self.seat, serial)
                            return
                        }
                    }
                }
            }

            let type: MouseEventType = state == 0 ? .buttonUp : .buttonDown
            let clickCount: Int
            if type == .buttonDown {
                clickCount = MainActor.assumeIsolated {
                    target.registerMouseButtonDown(
                        buttonID: buttonID,
                        location: location,
                        timestamp: timestamp
                    )
                }
                pointerButtonStates[buttonID] = PointerButtonState(
                    target: target,
                    buttonID: buttonID,
                    clickCount: clickCount,
                    location: location,
                    timestamp: timestamp
                )
            } else {
                clickCount = previousState?.clickCount ?? 0
                pointerButtonStates.removeValue(forKey: buttonID)
            }
            MainActor.assumeIsolated {
                target.postMouseEvent(MouseEvent(type: type,
                                                  window: target,
                                                  device: .genericMouse,
                                                  deviceID: 0,
                                                  buttonID: buttonID,
                                                  clickCount: clickCount,
                                                  modifiers: modifiers,
                                                  location: location,
                                                  timestamp: timestamp))
            }
        }
        Log.debug("wl_pointer_listener.button (serial:\(serial), time:\(time), button:\(button), state:\(state))")
    }

    fileprivate func cancelActivePointerButtons() {
        if let pointerTarget {
            MainActor.assumeIsolated {
                pointerTarget.resetMouseClickTracking()
            }
        }
        let states = pointerButtonStates.values.sorted { $0.buttonID < $1.buttonID }
        guard !states.isEmpty else { return }

        pointerButtonStates.removeAll()
        let modifiers = keyboardModifierFlags()
        for state in states {
            guard let target = state.target else { continue }
            MainActor.assumeIsolated {
                target.resetMouseClickTracking()
                target.postMouseEvent(MouseEvent(
                    type: .cancelled,
                    window: target,
                    device: .genericMouse,
                    deviceID: 0,
                    buttonID: state.buttonID,
                    modifiers: modifiers,
                    location: state.location,
                    timestamp: state.timestamp
                ))
            }
        }
    }

    fileprivate func pointerAxis(time: UInt32, axis: UInt32, value: Double) {
        let axisBit: UInt8
        if axis == 0 { // WL_POINTER_AXIS_VERTICAL_SCROLL
            pointerAxisFrame.delta.y += value
            axisBit = 1 << 0
        } else { // WL_POINTER_AXIS_HORIZONTAL_SCROLL
            pointerAxisFrame.delta.x += value
            axisBit = 1 << 1
        }
        pointerAxisFrame.axes |= axisBit
        pointerAxisFrame.timestamp = pointerEventClock.timestamp(for: time)
        //Log.debug("wl_pointer_listener.axis (time:\(time), axis:\(axis), value:\(value))")
    }

    fileprivate func pointerFrame() { // end of single-frame of event sequence.
        defer { pointerAxisFrame = PointerAxisFrame() }
        guard let target = pointerTarget else { return }

        let source = pointerAxisFrame.source == .unknown
            ? pointerAxisSource
            : pointerAxisFrame.source
        let wasActive = pointerAxisActiveAxes != 0
        pointerAxisActiveAxes |= pointerAxisFrame.axes
        pointerAxisActiveAxes &= ~pointerAxisFrame.stoppedAxes

        let phase: ScrollEventPhase?
        if source == .finger {
            if pointerAxisActiveAxes == 0 && pointerAxisFrame.stoppedAxes != 0 {
                phase = .ended
            } else if wasActive {
                phase = .changed
            } else if pointerAxisFrame.axes != 0 {
                phase = .began
            } else {
                phase = nil
            }
        } else {
            // Wheel, tilt, and continuous sources are not guaranteed to send
            // axis_stop, so keep them discrete instead of inventing a session.
            phase = nil
        }

        guard pointerAxisFrame.delta != .zero || phase != nil,
              let timestamp = pointerAxisFrame.timestamp else { return }
        let modifiers = keyboardModifierFlags()
        MainActor.assumeIsolated {
            target.postMouseEvent(MouseEvent(
                type: .wheel,
                window: target,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 2,
                modifiers: modifiers,
                location: pointerLocation,
                delta: pointerAxisFrame.delta,
                timestamp: timestamp,
                scrollData: ScrollEventData(
                    phase: phase,
                    source: source,
                    isPrecise: source == .finger || source == .continuous
                )
            ))
        }
        //Log.debug("wl_pointer_listener.frame")
    }

    fileprivate func pointerAxis(source: UInt32) {
        switch source {
        case 0: pointerAxisFrame.source = .wheel
        case 1: pointerAxisFrame.source = .finger
        case 2: pointerAxisFrame.source = .continuous
        case 3: pointerAxisFrame.source = .wheelTilt
        default: pointerAxisFrame.source = .unknown
        }
        pointerAxisSource = pointerAxisFrame.source
        Log.debug("wl_pointer_listener.axis_source (source:\(source))")
    }

    fileprivate func pointerAxisStop(time: UInt32, axis: UInt32) {
        let axisBit: UInt8 = axis == 0 ? 1 << 0 : 1 << 1
        pointerAxisFrame.stoppedAxes |= axisBit
        pointerAxisFrame.timestamp = pointerEventClock.timestamp(for: time)
        Log.debug("wl_pointer_listener.axis_top (time:\(time), axis:\(axis))")
    }

    fileprivate func pointerAxis(_ axis: UInt32, discrete: Int32) {
        if pointerAxisFrame.source == .unknown {
            pointerAxisFrame.source = .wheel
            pointerAxisSource = .wheel
        }
        Log.debug("wl_pointer_listener.axis_discrete (axis:\(axis), discrete:\(discrete))")
    }

    fileprivate func keyboardKeymap(format: UInt32, fd: Int32, size: UInt32) {
        self.xkbContext?.updateKeyMap(fromFD: fd, size: Int(size))
        Log.debug("wl_keyboard_listener.keymap (format:\(format), fd:\(fd), size:\(size))")
    }

    fileprivate func keyboardEnter(serial: UInt32, surface: OpaquePointer?, keys: [UInt8]) {
        updateClipboardInputSerial(serial)
        Log.debug("wl_keyboard_listener.enter (num keys: \(keys.count))")
        keys.indices.forEach { index in
            let key = keys[index]
            let symbol = self.xkbContext?.symbol(forKey: UInt32(key))
            Log.debug(" + Key[\(index)]: \(key), Symbol: \(String(describing: symbol))")
        }
        Log.debug("wl_keyboard_listener.enter (serial:\(serial))")
    }

    fileprivate func keyboardLeave(serial: UInt32, surface: OpaquePointer?) {
        self.keyRepeatState = nil
        Log.debug("wl_keyboard_listener.leave (serial:\(serial))")
    }

    fileprivate func keyboardKey(serial: UInt32, time: UInt32, key: UInt32, state: UInt32) {
        updateClipboardInputSerial(serial)
        if let state = self.xkbContext?.updateKey(key, state: state) {
            Log.debug("xkb_state_component: \(state)")
        }

        let code = VirtualKey.from(scanCode: key)
        let pressed = state == WL_KEYBOARD_KEY_STATE_PRESSED.rawValue
        let symbol = self.xkbContext?.symbol(forKey: key)
        let inputText = Self.inputText(from: symbol)
        let modifiers = self.keyboardModifierFlags()

        MainActor.assumeIsolated {
            if let window = self.activeWindow {
                if code != .none {
                    window.postKeyboardEvent(KeyboardEvent(
                        type: pressed ? .keyDown : .keyUp,
                        window: window,
                        deviceID: 0,
                        key: code,
                        text: "",
                        modifiers: modifiers
                    ))
                }
                if pressed,
                   window.isTextInputEnabled(forDeviceID: 0),
                   let inputText {
                    window.postKeyboardEvent(KeyboardEvent(
                        type: .textInput,
                        window: window,
                        deviceID: 0,
                        key: .none,
                        text: inputText
                    ))
                }
            }
        }

        if pressed {
            self.scheduleKeyRepeat(for: key, virtualKey: code)
        } else if self.keyRepeatState?.key == key {
            self.keyRepeatState = nil
        }

        if let symbol {
            Log.debug("Key: \(key), Symbol: \(String(describing: symbol)), VirtualKey: \(code), pressed: \(pressed)")
        } else {
            Log.debug("Key: \(key), Symbol: nil, VirtualKey: \(code), pressed: \(pressed)")
        }
        Log.debug("wl_keyboard_listener.key (serial:\(serial), time:\(time), key:\(key), state:\(state))")
    }

    fileprivate func keyboardModifiers(serial: UInt32, depressed: UInt32, latched: UInt32, locked: UInt32, group: UInt32) {
        updateClipboardInputSerial(serial)
        if let state = self.xkbContext?.updateModifiers(depressed: depressed, latched: latched, locked: locked, group: group) {
            Log.debug("xkb_state_component: \(state)")
        }
        Log.debug("wl_keyboard_listener.modifiers (serial:\(serial), depressed:\(depressed), latched:\(latched), locked:\(locked), group:\(group))")
    }

    fileprivate func keyboardRepeatInfo(rate: Int32, delay: Int32) {
        self.keyRepeatRate = rate
        self.keyRepeatDelay = delay
        if rate <= 0 {
            self.keyRepeatState = nil
        }
        Log.debug("wl_keyboard_listener.repeat_info (rate:\(rate), delay:\(delay))")
    }

    private func scheduleKeyRepeat(for key: UInt32, virtualKey: VirtualKey) {
        guard self.keyRepeatRate > 0,
              self.xkbContext?.shouldRepeats(key) == true,
              let window = self.activeWindow else {
            return
        }

        self.keyRepeatState = KeyRepeatState(
            key: key,
            virtualKey: virtualKey,
            window: window,
            nextFireTime: Date().addingTimeInterval(Double(max(0, self.keyRepeatDelay)) / 1000.0)
        )
    }

    private func processKeyRepeat() {
        guard self.keyRepeatRate > 0, var state = self.keyRepeatState else { return }

        let now = Date()
        guard now >= state.nextFireTime else { return }
        guard let window = state.window else {
            self.keyRepeatState = nil
            return
        }
        let isActive = MainActor.assumeIsolated { window.activated }
        guard isActive else {
            self.keyRepeatState = nil
            return
        }

        let inputText = Self.inputText(from: self.xkbContext?.symbol(forKey: state.key))
        let modifiers = self.keyboardModifierFlags()
        MainActor.assumeIsolated {
            if state.virtualKey != .none {
                window.postKeyboardEvent(KeyboardEvent(
                    type: .keyDown,
                    window: window,
                    deviceID: 0,
                    key: state.virtualKey,
                    text: "",
                    isRepeat: true,
                    modifiers: modifiers
                ))
            }
            if window.isTextInputEnabled(forDeviceID: 0),
               let inputText {
                window.postKeyboardEvent(KeyboardEvent(
                    type: .textInput,
                    window: window,
                    deviceID: 0,
                    key: .none,
                    text: inputText,
                    isRepeat: true
                ))
            }
        }

        state.nextFireTime = now.addingTimeInterval(1.0 / Double(self.keyRepeatRate))
        self.keyRepeatState = state
    }

    private func keyboardModifierFlags() -> KeyboardModifierFlags {
        var modifiers: KeyboardModifierFlags = []
        if self.xkbContext?.isModifierActive(XKB_MOD_NAME_CAPS) == true {
            modifiers.insert(.capsLock)
        }
        if self.xkbContext?.isModifierActive(XKB_MOD_NAME_SHIFT) == true {
            modifiers.insert(.shift)
        }
        if self.xkbContext?.isModifierActive(XKB_MOD_NAME_CTRL) == true {
            modifiers.insert(.control)
        }
        if self.xkbContext?.isModifierActive(XKB_MOD_NAME_ALT) == true {
            modifiers.insert(.option)
        }
        if self.xkbContext?.isModifierActive(XKB_MOD_NAME_LOGO) == true {
            modifiers.insert(.command)
        }
        return modifiers
    }

    private static func inputText(from symbol: XKBContext.Symbol?) -> String? {
        guard let text = symbol?.name,
              !text.isEmpty,
              !text.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            return nil
        }
        return text
    }
}

#endif //if ENABLE_WAYLAND
