//
//  File: Win32Window.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_WIN32
import Foundation
import WinSDK

// MARK: - Win32 Helpers

private func win32ErrorString(_ code: DWORD) -> String {

    var buffer: UnsafeMutablePointer<WCHAR>?

    let MAKELANGID = { (p: Int32, s: Int32) -> DWORD in
        return DWORD((DWORD(s) << 10) | DWORD(p))
    }

    let numChars = withUnsafeMutablePointer(to: &buffer) {
        $0.withMemoryRebound(to: WCHAR.self, capacity: 1) {
            FormatMessageW(
                DWORD(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM),
                nil, code,
                MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                $0,
                0, nil)
        }
    }

    if numChars > 0 {
        let ret = String(decodingCString: buffer!, as: UTF16.self)
        LocalFree(buffer)
        return ret
    }
    return "Unknown error: \(code)"
}

@inline(__always)
private func dpiScaleForWindow(_ hWnd: HWND) -> CGFloat {
    let dpi = GetDpiForWindow(hWnd)
    if dpi != 0 {
        return CGFloat(dpi) / 96.0
    }
    return 1.0
}

// Timer settings.
private let updateKeyboardMouseTimerId: UINT_PTR = 10
private let updateKeyboardMouseTimeInterval: UINT = 10

// Custom window messages.
private let WM_VVDWINDOW_SHOWCURSOR = (WM_USER + 0x1175)
private let WM_VVDWINDOW_UPDATEMOUSECAPTURE = (WM_USER + 0x1180)

// Converts GID_ROTATE ullArguments to a cumulative angle in radians.
// Maps WORD range 0...65535 to -2 * Double.pi ... +2 * Double.pi.
@inline(__always)
private func gestureRotateAngle(_ arg: ULONGLONG) -> Double {
    let word = Double(arg & 0xFFFF)
    return (word / 65535.0) * (4.0 * Double.pi) - 2.0 * Double.pi
}


nonisolated(unsafe) private let HWND_TOP:HWND? = nil
nonisolated(unsafe) private let HWND_TOPMOST:HWND = HWND(bitPattern: -1)!
nonisolated(unsafe) private let HWND_NOTOPMOST:HWND = HWND(bitPattern: -2)!

// MARK: - Win32Window

@MainActor
final class Win32Window: Window {

    // MARK: - Types

    private struct MouseButtonDownMask: OptionSet {
        let rawValue: UInt8
        init(rawValue: UInt8) { self.rawValue = rawValue }

        static let button1 = MouseButtonDownMask(rawValue: 1)
        static let button2 = MouseButtonDownMask(rawValue: 1 << 1)
        static let button3 = MouseButtonDownMask(rawValue: 1 << 2)
        static let button4 = MouseButtonDownMask(rawValue: 1 << 3)
        static let button5 = MouseButtonDownMask(rawValue: 1 << 4)
        static let button6 = MouseButtonDownMask(rawValue: 1 << 5)
        static let button7 = MouseButtonDownMask(rawValue: 1 << 6)
        static let button8 = MouseButtonDownMask(rawValue: 1 << 7)
    }

    typealias HWND = WinSDK.HWND

    // MARK: - Stored Properties

    nonisolated(unsafe) 
    private(set) var hWnd: HWND?
    private(set) var style: WindowStyle
    private(set) var contentBounds: CGRect = .null
    private(set) var windowFrame: CGRect = .null
    private(set) var contentScaleFactor: CGFloat = 1.0

    var name: String

    weak var delegate: WindowDelegate?

    var platformHandle: OpaquePointer? { OpaquePointer(hWnd) }
    var isValid: Bool { hWnd != nil }

    var eventObservers = WindowEventObserverContainer()

    private(set) var resizing: Bool = false
    private var resizeEventActive: Bool = false
    private var geometryInvalidatedInMoveSizeLoop: Bool = false
    private(set) var activated: Bool = false
    private(set) var visible: Bool = false
    private(set) var minimized: Bool = false
    
    private var mousePosition: CGPoint = .zero
    private var lockedMousePosition: CGPoint = .zero
    private var mouseButtonDownMask: MouseButtonDownMask = []
    private var mouseLocked: Bool = false
    private var textCompositionMode: Bool = false
    private var keyboardStates: [UInt8] = [UInt8](repeating: 0, count: 256)
    private var pendingKeyRepeat: Int? = nil

    // WM_GESTURE tracking values for incremental delta computation.
    private var _lastGestureDistance: DWORD = 0
    private var _lastGestureAngle: Double = 0.0

    private var dropTarget: UnsafeMutablePointer<Win32DropTarget>?

    // MARK: - Resize Tracking

    private func beginResizeEventIfNeeded() {
        guard self.resizing && self.resizeEventActive == false else { return }
        self.resizeEventActive = true
        self.postWindowEvent(type: .resizeBegan)
    }

    private func invalidateMoveGeometryIfNeeded() {
        guard self.resizing &&
              self.resizeEventActive == false &&
              self.geometryInvalidatedInMoveSizeLoop == false else {
            return
        }
        self.geometryInvalidatedInMoveSizeLoop = true
        self.postWindowEvent(type: .geometryInvalidated)
    }

    private func endMoveSizeLoop() {
        if self.resizeEventActive {
            self.postWindowEvent(type: .resizeEnded)
        }
        self.resizing = false
        self.resizeEventActive = false
        self.geometryInvalidatedInMoveSizeLoop = false
    }

    // MARK: - Modal State

    private struct ModalEntry: @unchecked Sendable {
        let window: Win32Window
        let completionHandler: (()->Void)?
    }
    private var modalEntries: [ModalEntry] = []

    // MARK: - Window Class Registration

    private static let windowClassName = "_SwiftVVD_WndClass"
    private static let registeredClassAtom: ATOM? = {
        let atom: ATOM? = windowClassName.withCString(encodedAs: UTF16.self) { className in

            let IDC_ARROW: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!
            let IDI_APPLICATION: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!

            var wc = WNDCLASSEXW(
                cbSize: UINT(MemoryLayout<WNDCLASSEXW>.size),
                style: UINT(CS_OWNDC),
                lpfnWndProc: { (hWnd, uMsg, wParam, lParam) -> LRESULT in
                    let box = UnsafeBox(hWnd)
                    return MainActor.assumeIsolated {
                        Win32Window.windowProc(box.value, uMsg, wParam, lParam)
                    }
                },
                cbClsExtra: 0,
                cbWndExtra: 0,
                hInstance: GetModuleHandleW(nil),
                hIcon: LoadIconW(nil, IDI_APPLICATION),
                hCursor: LoadCursorW(nil, IDC_ARROW),
                hbrBackground: nil,
                lpszMenuName: nil,
                lpszClassName: className,
                hIconSm: nil)

            return RegisterClassExW(&wc)
        }
        if atom == nil { 
            let lastError = GetLastError()
            if lastError != DWORD(ERROR_CLASS_ALREADY_EXISTS) {
                Log.err("RegisterClassExW failed with error: \(win32ErrorString(lastError))")
            }
        } else {
            Log.debug("WindowClass: \"\(windowClassName)\" registered successfully.")
        }
        return atom
    }()

    private static var windowMap: [WinSDK.HWND: WeakObject<Win32Window>] = [:]

    enum NonClientAreaRenderingPolicy {
        case `default`
        case disabled
        case enabled
    }

    // MARK: - Lifecycle

    required init?(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) {

        OleInitialize(nil)

        self.name = name
        self.style = style
        self.delegate = delegate    

        guard Self.registeredClassAtom != nil || GetLastError() == DWORD(ERROR_CLASS_ALREADY_EXISTS) else {
            return nil
        }

        assert(Thread.isMainThread, "A window must be created on the main thread.")

        var dwStyle: DWORD = 0
        var dwStyleEx: DWORD = 0
        var ncRenderingPolicy: NonClientAreaRenderingPolicy = .default

        if style.contains(.title)           { dwStyle |= DWORD(WS_CAPTION) }
        if style.contains(.closeButton)     { dwStyle |= DWORD(WS_SYSMENU) }
        if style.contains(.minimizeButton)  { dwStyle |= DWORD(WS_MINIMIZEBOX) }
        if style.contains(.maximizeButton)  { dwStyle |= DWORD(WS_MAXIMIZEBOX) }
        if style.contains(.resizableBorder) { dwStyle |= DWORD(WS_THICKFRAME) }
        let isUtilityOrPopup = style.contains(.utilityWindow) || style.contains(.popupWindow)
        if isUtilityOrPopup {
            dwStyle |= DWORD(WS_POPUP) 
            dwStyleEx |= DWORD(WS_EX_NOACTIVATE)
            dwStyleEx |= DWORD(WS_EX_TOOLWINDOW)
            dwStyleEx |= DWORD(WS_EX_TOPMOST)

            ncRenderingPolicy = .enabled // Enable Windows theme.
        }
        let anyTitlebarStyle: WindowStyle = [.title, .closeButton, .minimizeButton, .maximizeButton]
        if style.intersection(anyTitlebarStyle).isEmpty {
            dwStyle |= DWORD(WS_POPUP)  // Window without title bar.
            ncRenderingPolicy = .enabled // Enable Windows theme.
        }

        let hWnd = name.withCString(encodedAs: UTF16.self) { title in
            Self.windowClassName.withCString(encodedAs: UTF16.self) { className in
                CreateWindowExW(dwStyleEx, className, title, dwStyle,
                CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,
                nil, nil, GetModuleHandleW(nil), nil)
            }
        }
        guard let hWnd else {
            Log.err("CreateWindow failed: \(win32ErrorString(GetLastError()))")
            return nil 
        }

        SetLastError(0)

        var rc1: RECT = RECT()
        GetClientRect(hWnd, &rc1)
        if rc1.right - rc1.left < 1 || rc1.bottom - rc1.top < 1 {
            SetWindowPos(hWnd, nil, 0, 0, 640, 480, UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
        }

        if ncRenderingPolicy != .default {
            var policy: DWMNCRENDERINGPOLICY = switch ncRenderingPolicy {
            case .default:      DWMNCRP_USEWINDOWSTYLE
            case .disabled:     DWMNCRP_DISABLED
            case .enabled:      DWMNCRP_ENABLED
            }
            DwmSetWindowAttribute(hWnd, DWORD(DWMWA_NCRENDERING_POLICY.rawValue), &policy, DWORD(MemoryLayout.size(ofValue: policy)));

            var margins = MARGINS(cxLeftWidth: -1, cxRightWidth: 0, cyTopHeight: 0, cyBottomHeight: 0)
            DwmExtendFrameIntoClientArea(hWnd, &margins)
        }

        self.hWnd = hWnd
        Self.windowMap[hWnd] = WeakObject(self)

        if style.contains(.acceptFileDrop) {
            let dropTargetPtr = Win32DropTarget.makeMutablePointer(target: self)
            let result = dropTargetPtr.withMemoryRebound(to: IDropTarget.self, capacity:1) {
                RegisterDragDrop(hWnd, $0)
            }
            if result == S_OK {
                self.dropTarget = dropTargetPtr
            } else {
                Log.err("RegisterDragDrop failed: \(win32ErrorString(DWORD(result)))")
            }
        }
        
        rc1 = RECT()
        var rc2: RECT = RECT()
        GetClientRect(hWnd, &rc1)
        GetWindowRect(hWnd, &rc2)

        self.contentScaleFactor = dpiScaleForWindow(hWnd)
        let invScale = 1.0 / self.contentScaleFactor

        self.contentBounds = CGRect(x: CGFloat(rc1.left),
                                    y: CGFloat(rc1.top),
                                    width: CGFloat(rc1.right - rc1.left) * invScale,
                                    height: CGFloat(rc1.bottom - rc1.top) * invScale)
        self.windowFrame = CGRect(x: Int(rc2.left),
                                  y: Int(rc2.top),
                                  width: Int(rc2.right - rc2.left),
                                  height: Int(rc2.bottom - rc2.top))

        SetWindowPos(hWnd, nil, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED))
        SetTimer(hWnd, updateKeyboardMouseTimerId, updateKeyboardMouseTimeInterval, nil)
        postWindowEvent(type: .created)
    }

    deinit {
        let modals = self.modalEntries.map { $0.window }
        let hWnd = self.hWnd

        Task { @MainActor in
            modals.forEach { $0.close() }

            if let hWnd {
                KillTimer(hWnd, updateKeyboardMouseTimerId)
                Self.windowMap.removeValue(forKey: hWnd)
                PostMessageW(hWnd, UINT(WM_CLOSE), 0, 0)
            }
            OleUninitialize()
        }
    }

    // MARK: - Visibility

    func show() {
        if let hWnd = self.hWnd {
            if IsIconic(hWnd) {
                ShowWindow(hWnd, SW_RESTORE)
            } else {
                ShowWindow(hWnd, SW_SHOWNA)
            }
        }
    }

    func hide() {
        if let hWnd = self.hWnd {
            ShowWindow(hWnd, SW_HIDE)
        }
    }

    func activate() {
        if let hWnd = self.hWnd {
            if IsIconic(hWnd) {
                ShowWindow(hWnd, SW_RESTORE)
            }

            let styleEx = DWORD(bitPattern: GetWindowLongW(hWnd, GWL_EXSTYLE))
            if styleEx & DWORD(WS_EX_NOACTIVATE) == 0 {
                ShowWindow(hWnd, SW_SHOW)
                SetForegroundWindow(hWnd)
            } else {
                ShowWindow(hWnd, SW_SHOWNA)
            }
        }
    }

    // MARK: - Geometry

    var origin: CGPoint {
        get { self.windowFrame.origin }
        set (value) {
            if let hWnd = self.hWnd {
                let x = Int32(value.x)
                let y = Int32(value.y)
                var flags = UINT(SWP_NOSIZE | SWP_NOOWNERZORDER | SWP_NOACTIVATE)
                if style.contains(.utilityWindow) || style.contains(.popupWindow) {
                    flags |= UINT(SWP_NOZORDER)
                }
                SetWindowPos(hWnd, HWND_TOP, x, y, 0, 0, flags)
            }
        }
    }

    var contentSize: CGSize {
        get { self.contentBounds.size }
        set (value) {
            self.resolution = value * self.contentScaleFactor
        }
    }

    var resolution: CGSize {
        get {
            return self.contentSize * self.contentScaleFactor
        }
        set (value) {
            if let hWnd = self.hWnd {
                var w = max(Int32(value.width), 1)
                var h = max(Int32(value.height), 1)

                let style = DWORD(bitPattern: GetWindowLongW(hWnd, GWL_STYLE))
                let styleEx = DWORD(bitPattern: GetWindowLongW(hWnd, GWL_EXSTYLE))
                let menu: Bool = GetMenu(hWnd) != nil

                var rc = RECT(left: 0, top: 0, right: LONG(w), bottom: LONG(h))
                if AdjustWindowRectEx(&rc, style, menu, styleEx) {
                    let size: CGSize = CGSize(width: Int(w), height: Int(h))
                    self.contentBounds.size = size * (1.0 / self.contentScaleFactor)

                    w = rc.right - rc.left
                    h = rc.bottom - rc.top
                    var flags = UINT(SWP_NOMOVE | SWP_NOOWNERZORDER | SWP_NOACTIVATE)
                    if self.style.contains(.utilityWindow) || self.style.contains(.popupWindow) {
                        flags |= UINT(SWP_NOZORDER)
                    }
                    SetWindowPos(hWnd, HWND_TOP, 0, 0, w, h, flags)
                }
            }
        }
    }

    func minimize() {
        if let hWnd = self.hWnd {
            ShowWindow(hWnd, SW_MINIMIZE)
        }
    }

    // MARK: - Close Handling

    func requestToClose() -> Bool {
        var close = true
        if self.isValid {
            close = self.delegate?.shouldClose(window: self) ?? true
        }
        if close {
            self.close()
        }
        return close
    }
    
    func close() {
        // Close all modal windows.
        let entries = self.modalEntries
        self.modalEntries.removeAll()
        let completionHandlers = entries.compactMap { $0.completionHandler }
        entries.forEach { 
            $0.window.removeEventObserver(self)
            $0.window.close()
        }
        if !completionHandlers.isEmpty {
            Task { completionHandlers.forEach { $0() } }
        }

        if let hWnd = self.hWnd {
            if let dt = self.dropTarget {
                RevokeDragDrop(hWnd)
                let refCount = dt.withMemoryRebound(to: IDropTarget.self, capacity: 1) {
                    dt.pointee.vtbl.Release($0)
                }
                if refCount > 0 {
                    Log.warn("DropTarget for Window:\(self.name) in use! refCount:\(refCount)")
                }
            }
            self.dropTarget = nil

            KillTimer(hWnd, updateKeyboardMouseTimerId)
            Self.windowMap.removeValue(forKey: hWnd)

            // Post WM_CLOSE to destroy window from DefWindowProc().
            PostMessageW(hWnd, UINT(WM_CLOSE), 0, 0)

            Log.verbose("Window: \(self.name) destroyed")

            // Post the final close event.
            self.postWindowEvent(type: .closed)
        }
        self.hWnd = nil
    }

    var title: String {
        get {
            if let hWnd = self.hWnd {
                let len = GetWindowTextLengthW(hWnd)
                if len > 0 {
                    var tmp = [WCHAR](repeating: 0, count: Int(len + 2))
                    return tmp.withUnsafeMutableBufferPointer { (ptr) -> String in
                        GetWindowTextW(hWnd, ptr.baseAddress, len + 2)
                        return String(decodingCString: ptr.baseAddress!, as: UTF16.self)
                    }
                }
                return String()             
            }
            return self.name
        }
        set (value) {
            if let hWnd = self.hWnd {
                _ = value.withCString(encodedAs: UTF16.self) {
                    SetWindowTextW(hWnd, $0)
                }
            }
            self.name = value
        }
    }

    // MARK: - Input State

    func showMouse(_ show: Bool, forDeviceID deviceID: Int) {
        if let hWnd = self.hWnd, deviceID == 0 {
            let wParam = show ? WPARAM(1) : WPARAM(0)
            PostMessageW(hWnd, UINT(WM_VVDWINDOW_SHOWCURSOR), wParam, 0)
        }
    }

    func isMouseVisible(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            var info = CURSORINFO()
            info.cbSize = UINT(MemoryLayout<CURSORINFO>.size)
            if GetCursorInfo(&info) {
                return info.flags != 0
            }
        }
        return false
    }

    func lockMouse(_ lock: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0, let pos = self.mousePosition(forDeviceID: 0) {
            self.mouseLocked = lock
            self.mousePosition = pos
            self.lockedMousePosition = pos
            PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
        }
    }

    func isMouseLocked(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return self.mouseLocked
        }
        return false
    }

    func mousePosition(forDeviceID deviceID: Int) -> CGPoint? {
        if let hWnd = self.hWnd, deviceID == 0 {
            var pt = POINT()
            GetCursorPos(&pt)
            ScreenToClient(hWnd, &pt)
            return CGPoint(x: Int(pt.x), y: Int(pt.y)) * (1.0 / self.contentScaleFactor)
        }
        return nil
    }

    func setMousePosition(_ pos: CGPoint, forDeviceID deviceID: Int) {
        if let hWnd = self.hWnd, deviceID == 0 {
            let pixel = pos * self.contentScaleFactor
            var pt = POINT(x: LONG(pixel.x.rounded()), y: LONG(pixel.y.rounded()))
            ClientToScreen(hWnd, &pt)
            SetCursorPos(pt.x, pt.y)
            self.mousePosition = pos
        }
    }

    func enableTextInput(_ enable: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            self.textCompositionMode = enable
        }
    }

    func isTextInputEnabled(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return self.textCompositionMode
        }
        return false
    }

    // MARK: - Input Synchronization

    private func synchronizeMouse() {
        guard self.visible else { return }
        guard self.resizing == false else { return }
        let styleEx = DWORD(bitPattern: GetWindowLongW(hWnd, GWL_EXSTYLE))
        if styleEx & DWORD(WS_EX_NOACTIVATE) == 0 {
            guard self.activated else { return }
        }

        // Check whether the mouse moved outside the window region.
        if let hWnd = self.hWnd, GetCapture() != hWnd {
            var pt = POINT()
            GetCursorPos(&pt)
            ScreenToClient(hWnd, &pt)

            var rc = RECT()
            GetClientRect(hWnd, &rc)
            if pt.x < rc.left || pt.x > rc.right || pt.y > rc.bottom || pt.y < rc.top {

                let MAKELPARAM = {(a:Int32, b:Int32) -> LPARAM in
                    LPARAM(a & 0xffff) | (LPARAM(b & 0xffff) << 16)
                }
                SendMessageW(hWnd, UINT(WM_MOUSEMOVE), 0, MAKELPARAM(pt.x, pt.y))
            }
        }
    }

    private func resetMouse() {
        if let hWnd = self.hWnd {
            var pt = POINT()
            GetCursorPos(&pt)
            ScreenToClient(hWnd, &pt)
            mousePosition = CGPoint(x: Int(pt.x), y: Int(pt.y)) * (1.0 / self.contentScaleFactor)
        }
    }

    private func keyboardModifiers(from keyStates: [UInt8]) -> KeyboardModifierFlags {
        let capsLock = keyStates[Int(VK_CAPITAL)] & 0x01 != 0
        let leftShift = keyStates[Int(VK_LSHIFT)] & 0x80 != 0
        let rightShift = keyStates[Int(VK_RSHIFT)] & 0x80 != 0
        let leftControl = keyStates[Int(VK_LCONTROL)] & 0x80 != 0
        let rightControl = keyStates[Int(VK_RCONTROL)] & 0x80 != 0
        let leftAlt = keyStates[Int(VK_LMENU)] & 0x80 != 0
        let rightAlt = keyStates[Int(VK_RMENU)] & 0x80 != 0
        let leftWin = keyStates[Int(VK_LWIN)] & 0x80 != 0
        let rightWin = keyStates[Int(VK_RWIN)] & 0x80 != 0

        var modifiers: KeyboardModifierFlags = []
        if capsLock { modifiers.insert(.capsLock) }
        if leftShift || rightShift { modifiers.insert(.shift) }
        if leftControl || rightControl { modifiers.insert(.control) }
        if leftAlt || rightAlt { modifiers.insert(.option) }
        if leftWin || rightWin { modifiers.insert(.command) }
        return modifiers
    }

    private func synchronizeKeyStates() {
        guard self.activated else { return }

        var keyStates: [UInt8] = [UInt8](repeating: 0, count: 256)
        GetKeyboardState(&keyStates)

        let modifiers = self.keyboardModifiers(from: keyStates)

        for key in 0..<256 {
            if key == VK_CAPITAL { continue }

            let virtualKey: VirtualKey = .from(win32VK: key)
            if virtualKey == .none { continue }

            let isDown = keyStates[key] & 0x80 != 0

            if keyStates[key] & 0x80 != self.keyboardStates[key] & 0x80 {
                if keyStates[key] & 0x80 != 0 {
                    // Post key-down event.
                    postKeyboardEvent(KeyboardEvent(type: .keyDown,
                                                    window: self,
                                                    deviceID: 0,
                                                    key: virtualKey,
                                                    text: "",
                                                    modifiers: modifiers))
                    if self.pendingKeyRepeat == key {
                        self.pendingKeyRepeat = nil
                    }
                } else {
                    // Post key-up event.
                    postKeyboardEvent(KeyboardEvent(type: .keyUp,
                                                    window: self,
                                                    deviceID: 0,
                                                    key: virtualKey,
                                                    text: "",
                                                    modifiers: modifiers))
                    if self.pendingKeyRepeat == key {
                        self.pendingKeyRepeat = nil
                    }
                }
            } else if isDown && self.pendingKeyRepeat == key {
                postKeyboardEvent(KeyboardEvent(type: .keyDown,
                                                window: self,
                                                deviceID: 0,
                                                key: virtualKey,
                                                text: "",
                                                isRepeat: true,
                                                modifiers: modifiers))
                self.pendingKeyRepeat = nil
            } else if isDown == false && self.pendingKeyRepeat == key {
                self.pendingKeyRepeat = nil
            }
        }

        let capslock = Int(VK_CAPITAL)
        if keyStates[capslock] & 0x01 != self.keyboardStates[capslock] & 0x01 {
            if keyStates[capslock] & 0x01 != 0 {
                // Caps Lock on.
                postKeyboardEvent(KeyboardEvent(type: .keyDown,
                                                window: self,
                                                deviceID: 0,
                                                key: .capslock,
                                                text: "",
                                                modifiers: modifiers))
            } else {
                // Caps Lock off.
                postKeyboardEvent(KeyboardEvent(type: .keyUp,
                                                window: self,
                                                deviceID: 0,
                                                key: .capslock,
                                                text: "",
                                                modifiers: modifiers))
            }
        }
        self.keyboardStates = keyStates
    }

    private func resetKeyStates() {
        for key in 0..<256 {
            if key == VK_CAPITAL { continue }

            let virtualKey: VirtualKey = .from(win32VK: key)
            if virtualKey == .none { continue }

            if keyboardStates[key] & 0x80 != 0 {
                postKeyboardEvent(KeyboardEvent(type: .keyUp,
                                                window: self,
                                                deviceID: 0,
                                                key: virtualKey,
                                                text: ""))
            }
        }

        let capslock = Int(VK_CAPITAL)
        if keyboardStates[capslock] & 0x01 != 0 {
            postKeyboardEvent(KeyboardEvent(type: .keyUp,
                                            window: self,
                                            deviceID: 0,
                                            key: .capslock,
                                            text: ""))
        }

        GetKeyboardState(&keyboardStates) // Empty the keyboard queue.
        self.keyboardStates = [UInt8](repeating: 0, count: 256)
        self.pendingKeyRepeat = nil
    }

    // MARK: - Coordinate Conversion

    func convertPointToScreen(_ point: CGPoint) -> CGPoint {
        let x = LONG(point.x * self.contentScaleFactor)
        let y = LONG(point.y * self.contentScaleFactor)
        var pt = POINT(x: x, y: y)
        ClientToScreen(self.hWnd, &pt)
        return CGPoint(x: Int(pt.x), y: Int(pt.y))
    }
    
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint {
        var pt = POINT(x: LONG(point.x), y: LONG(point.y))
        ScreenToClient(self.hWnd, &pt)
        return CGPoint(x: Int(pt.x), y: Int(pt.y)) * (1.0 / self.contentScaleFactor)
    }

    // MARK: - Screen

    var screen: (any Screen)? {
        if let hWnd {
            let monitor = MonitorFromWindow(hWnd, DWORD(MONITOR_DEFAULTTONULL))
            return Win32Screen(monitor)
        }
        return nil
    }

    // MARK: - Modal Presentation

    var canPresentModalWindow: Bool {
        hWnd != nil
    }

    var modalWindows: [any Window] {
        self.modalEntries.map { $0.window }
    }

    func presentModalWindow(_ window: any Window, completionHandler: (()->Void)?) -> Bool {
        guard let modalWindow = window as? Win32Window else {
            Log.err("Window.presentModalWindow failed: incompatible window type.")
            return false
        }

        if modalWindow.isValid {
            let present = self.modalEntries.isEmpty
            self.modalEntries.append(
                ModalEntry(window: modalWindow,
                           completionHandler: completionHandler))
            if present {
                self.presentNextModal()
            }
            return true
        }
        Log.err("Window.presentModalWindow failed: invalid window.")
       return false
    }

    func dismissModalWindow(_ window: any Window) -> Bool {
        guard let modalWindow = window as? Win32Window else {
            Log.err("Window.dismissModalWindow failed: incompatible window type.")
            return false
        }

        var presentNext = false
        modalWindow.removeEventObserver(self)

        // Check whether the dismissed window is the current modal window.
        if let current = self.modalEntries.first {
            if current.window === modalWindow {
                presentNext = true
            }
        }
        // Remove modal entries and collect completion handlers.
        var completionHandlers: [(() -> Void)] = []
        self.modalEntries = self.modalEntries.filter {
            if $0.window !== modalWindow {
                return true
            }
            if let handler = $0.completionHandler {
                completionHandlers.append(handler)
            }
            return false
        }
        // Enable the host window when no modal windows remain.
        if self.modalEntries.isEmpty {
            presentNext = true
        }
        if presentNext {
            if let hWnd = modalWindow.hWnd {
                ShowWindow(hWnd, SW_HIDE)
            }

            self.presentNextModal()
        }
        // Call completion handlers after presenting the next modal.
        if !completionHandlers.isEmpty {
            Task { completionHandlers.forEach { $0() } }
        }
        return true
    }

    private func presentNextModal() {
        // Remove invalid windows from the modal list.
        var cancelledHandlers: [()->Void] = []
        self.modalEntries = self.modalEntries.filter {
            if $0.window.isValid { return true }
            if let handler = $0.completionHandler {
                cancelledHandlers.append(handler)
            }
            return false
        }
        if !cancelledHandlers.isEmpty {
            Task { cancelledHandlers.forEach { $0() } }
        }
        if let hWnd = self.hWnd {
            if let next = self.modalEntries.first?.window {
                if let modal = next.hWnd {
                    next.addEventObserver(self) { (event: WindowEvent) in
                        if event.type == .closed {
                            next.removeEventObserver(self)
                            Task {
                                self.dismissModalWindow(next)
                            }
                        }
                    }

                    SetForegroundWindow(hWnd)
                    EnableWindow(hWnd, false)

                    var rcHost = RECT()
                    GetWindowRect(hWnd, &rcHost)
                    var rcModal = RECT()
                    GetWindowRect(modal, &rcModal)
                    
                    let centerX = (rcHost.left + rcHost.right) / 2
                    let centerY = (rcHost.top + rcHost.bottom) / 2
                    let modalWidth = rcModal.right - rcModal.left
                    let modalHeight = rcModal.bottom - rcModal.top
                    let left = centerX - (modalWidth / 2)
                    let top = centerY - (modalHeight / 2)
                    
                    Log.debug("Presenting modal window at (\(left), \(top))")
                    SetWindowPos(modal, hWnd, left, top, 0, 0,  UINT(SWP_NOSIZE | SWP_SHOWWINDOW))

                    SetActiveWindow(modal)
                }
            } else {
                EnableWindow(hWnd, true)
                SetForegroundWindow(hWnd)
            }
        }
    }

    // MARK: - Window Procedure

    private static func windowProc(_ hWnd: HWND?, _ uMsg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        let window: Win32Window? = if let hWnd {
            Self.windowMap[hWnd]?.value
        } else {
            nil
        }

        let MAKEPOINTS = { (lParam: LPARAM) -> POINTS in
            var pt: POINTS = POINTS()
            withUnsafeBytes(of: lParam) {
                let pts = $0.bindMemory(to: POINTS.self)
                pt = pts[0]
            }
            return pt
        }

        func HIWORD(_ value: LPARAM) -> WORD {
            return WORD((value >> 16) & 0xffff)
        }
        func HIWORD(_ value: WPARAM) -> WORD {
            return WORD((value >> 16) & 0xffff)
        }
        func LOWORD(_ value: LPARAM) -> WORD {
            return WORD(value & 0xffff)
        }
        func LOWORD(_ value: WPARAM) -> WORD {
            return WORD(value & 0xffff)
        }

        if let window = window, window.hWnd == hWnd {
            let activateWindow = {
                if window.activated == false {
                    window.activated = true
                    numActiveWindows += 1
                    window.postWindowEvent(type: .activated)
                    window.resetKeyStates()
                    window.resetMouse()
                    Log.debug("VVD.numActiveWindows: \(numActiveWindows)")
                }
            }
            let inactivateWindow = {
                if window.activated {
                    numActiveWindows -= 1
                    window.resetKeyStates()
                    window.resetMouse()
                    window.activated = false
                    window.postWindowEvent(type: .inactivated)                            
                    Log.debug("VVD.numActiveWindows: \(numActiveWindows)")
                }
            }

            switch uMsg {
            case UINT(WM_NCACTIVATE):
                let activated = wParam != 0
                if activated {
                    let foreground = GetForegroundWindow() == hWnd
                    if foreground {
                        activateWindow()
                    }
                } else {
                    inactivateWindow()
                }
                return DefWindowProcW(hWnd, uMsg, wParam, lParam)
            case UINT(WM_ACTIVATE):
                let activation = LOWORD(wParam)
                if activation == WA_ACTIVE || activation == WA_CLICKACTIVE {
                    let minimized = HIWORD(wParam) != 0
                    let foreground = GetForegroundWindow() == hWnd
                    if foreground && minimized == false {
                        activateWindow()
                    }
                } else {
                    inactivateWindow()
                }
                return 0
            case UINT(WM_SHOWWINDOW):
                if wParam != 0 {
                    if window.visible == false {
                        window.visible = true
                        window.minimized = false
                        window.postWindowEvent(type: .shown)
                    }
                } else {
                    if window.visible {
                        window.visible = false
                        window.postWindowEvent(type: .hidden)
                    }
                }
                return 0
            case UINT(WM_MOUSEACTIVATE):
                let styleEx = DWORD(bitPattern: GetWindowLongW(hWnd, GWL_EXSTYLE))
                if styleEx & DWORD(WS_EX_NOACTIVATE) != 0 {
                    return LRESULT(MA_NOACTIVATE)
                }
                return LRESULT(MA_ACTIVATE)
            case UINT(WM_ENTERSIZEMOVE):
                window.resizing = true
                window.resizeEventActive = false
                window.geometryInvalidatedInMoveSizeLoop = false
                return 0
            case UINT(WM_EXITSIZEMOVE):
                var rcClient = RECT(), rcWindow = RECT()
                GetClientRect(hWnd, &rcClient)
                GetWindowRect(hWnd, &rcWindow)
                var resized = false
                var moved = false
                let resolution = window.resolution
                if (rcClient.right - rcClient.left) != LONG(resolution.width.rounded()) ||
                    (rcClient.bottom - rcClient.top) != LONG(resolution.height.rounded()) {
                    resized = true
                }
                if rcWindow.left != LONG(window.windowFrame.minX) || rcWindow.top != LONG(window.windowFrame.minY) {
                    moved = true
                }
                if resized || moved {
                    window.windowFrame = CGRect(x: Int(rcWindow.left),
                                                y: Int(rcWindow.top),
                                                width: Int(rcWindow.right - rcWindow.left),
                                                height: Int(rcWindow.bottom - rcWindow.top))
                    let invScale = 1.0 / window.contentScaleFactor
                    window.contentBounds = CGRect(x: CGFloat(rcClient.left),
                                                  y: CGFloat(rcClient.top),
                                                  width: CGFloat(rcClient.right - rcClient.left) * invScale,
                                                  height: CGFloat(rcClient.bottom - rcClient.top) * invScale)
                    if resized {
                        window.beginResizeEventIfNeeded()
                        window.postWindowEvent(type: .resized)
                    }
                    if moved {
                        if window.resizeEventActive == false {
                            window.invalidateMoveGeometryIfNeeded()
                        }
                        window.postWindowEvent(type: .moved)
                    }
                }
                window.endMoveSizeLoop()
                return 0
            case UINT(WM_SIZING):
                window.beginResizeEventIfNeeded()
                return 1
            case UINT(WM_SIZE):
                if wParam == SIZE_MAXHIDE {
                    if window.visible {
                        window.visible = false
                        window.postWindowEvent(type: .hidden)
                    }
                } else if wParam == SIZE_MINIMIZED {
                    if window.minimized == false {
                        window.minimized = true
                        window.postWindowEvent(type: .minimized)
                    }
                } else {
                    if window.minimized || window.visible == false {
                        window.minimized = false
                        window.visible = true
                        window.postWindowEvent(type: .shown)
                    } else {
                        let w = Int(LOWORD(lParam))
                        let h = Int(HIWORD(lParam))
                        let size = CGSize(width: w, height: h)  // Pixel size.
                        window.beginResizeEventIfNeeded()
                        window.contentBounds.size = size * (1.0 / window.contentScaleFactor) // DPI-scaled size.

                        var rc = RECT()
                        GetWindowRect(hWnd, &rc)
                        window.windowFrame = CGRect(x: Int(rc.left),
                                                    y: Int(rc.top),
                                                    width: Int(rc.right - rc.left),
                                                    height: Int(rc.bottom - rc.top))
                        window.postWindowEvent(type: .resized)
                    }
                }
                return 0
            case UINT(WM_MOVING):
                window.invalidateMoveGeometryIfNeeded()
                return 1
            case UINT(WM_MOVE):
                if window.resizing == false {
                    let x = Int(Int16(bitPattern: LOWORD(lParam)))
                    let y = Int(Int16(bitPattern: HIWORD(lParam)))

                    window.windowFrame.origin = CGPoint(x: x, y: y)
                    window.postWindowEvent(type: .moved)
                }
                return 0
            case UINT(WM_DPICHANGED):
                // xDPI and yDPI are identical for Windows apps.
                let xDPI = LOWORD(wParam)
                let yDPI = HIWORD(wParam)

                let tmp: UnsafePointer<RECT>? = UnsafePointer<RECT>(bitPattern: UInt(lParam))
                let suggestedWindowFrame: RECT = tmp!.pointee

                let scaleFactor: CGFloat = CGFloat(max(xDPI, yDPI)) / 96.0
                window.contentScaleFactor = scaleFactor

                if window.style.contains(.autoResize) {
                    SetWindowPos(hWnd, nil,
                                 suggestedWindowFrame.left,
                                 suggestedWindowFrame.top,
                                 suggestedWindowFrame.right - suggestedWindowFrame.left,
                                 suggestedWindowFrame.bottom - suggestedWindowFrame.top,
                                 UINT(SWP_NOZORDER | SWP_NOACTIVATE))
                } else {
                    var rcClient = RECT(), rcWindow = RECT()
                    GetClientRect(hWnd, &rcClient)
                    GetWindowRect(hWnd, &rcWindow)

                    window.windowFrame = CGRect(x: Int(rcWindow.left),
                                                y: Int(rcWindow.top),
                                                width: Int(rcWindow.right - rcWindow.left),
                                                height: Int(rcWindow.bottom - rcWindow.top))
                    let invScale = 1.0 / scaleFactor
                    window.contentBounds = CGRect(x: CGFloat(rcClient.left),
                                                  y: CGFloat(rcClient.top),
                                                  width: CGFloat(rcClient.right - rcClient.left) * invScale,
                                                  height: CGFloat(rcClient.bottom - rcClient.top) * invScale)
                    window.postWindowEvent(type: .resized)
                }
                return 0    
            case UINT(WM_GETMINMAXINFO):
                let style = DWORD(bitPattern: GetWindowLongW(hWnd, GWL_STYLE))
                let styleEx = DWORD(bitPattern: GetWindowLongW(hWnd, GWL_EXSTYLE))
                let menu: Bool = GetMenu(hWnd) != nil

                var minSize = CGSize(width: 1, height: 1)
                if let size = window.delegate?.minimumContentSize(window: window) {
                    minSize.width = size.width
                    minSize.height = size.height
                }
                var rc = RECT(left: 0, top: 0, right: LONG(max(minSize.width, 1)), bottom: LONG(max(minSize.height, 1)))
                if AdjustWindowRectEx(&rc, style, menu, styleEx) {
                    let tmp: UnsafeMutablePointer<MINMAXINFO> = UnsafeMutablePointer<MINMAXINFO>(bitPattern: UInt(lParam))!
                    tmp.pointee.ptMinTrackSize.x = rc.right - rc.left
                    tmp.pointee.ptMinTrackSize.y = rc.bottom - rc.top
                }
                if let maxSize = window.delegate?.maximumContentSize(window: window) {
                    rc = RECT(left: 0, top: 0, right: LONG(max(maxSize.width, 1)), bottom: LONG(max(maxSize.height, 1)))
                    if AdjustWindowRectEx(&rc, style, menu, styleEx) {
                        let tmp: UnsafeMutablePointer<MINMAXINFO> = UnsafeMutablePointer<MINMAXINFO>(bitPattern: UInt(lParam))!
                        if maxSize.width > 0 {
                            tmp.pointee.ptMaxTrackSize.x = rc.right - rc.left
                        }
                        if maxSize.height > 0 {
                            tmp.pointee.ptMaxTrackSize.y = rc.bottom - rc.top
                        }
                    }
                }
                return 0
            case UINT(WM_TIMER):
                if wParam == updateKeyboardMouseTimerId {
                    window.synchronizeKeyStates()
                    window.synchronizeMouse()
                    return 0
                }
            case UINT(WM_MOUSEMOVE):
                let pt = MAKEPOINTS(lParam)
                let oldPtX = Int((window.mousePosition.x * window.contentScaleFactor).rounded())
                let oldPtY = Int((window.mousePosition.y * window.contentScaleFactor).rounded())
                if pt.x != oldPtX || pt.y != oldPtY {
                    let delta = CGPoint(x: Int(pt.x) - oldPtX,
                                        y: Int(pt.y) - oldPtY) * (1.0 / window.contentScaleFactor)

                    var postEvent = true
                    if window.mouseLocked {
                        if window.activated {
                            let lockedPtX = Int((window.lockedMousePosition.x * window.contentScaleFactor).rounded())
                            let lockedPtY = Int((window.lockedMousePosition.y * window.contentScaleFactor).rounded())
                            if pt.x == lockedPtX && pt.y == lockedPtY {
                                postEvent = false
                            } else {
                                window.setMousePosition(window.mousePosition, forDeviceID: 0)
                                // On Windows 8 or later in scaled-DPI mode, setting the
                                // mouse position can be inaccurate. Keep the resulting
                                // position while the mouse is locked.
                                window.lockedMousePosition = window.mousePosition(forDeviceID: 0)!
                            }
                        } else {
                            postEvent = false
                        }
                    } else {
                        window.mousePosition = CGPoint(x: Int(pt.x), y: Int(pt.y)) * (1.0 / window.contentScaleFactor)
                    }

                    if postEvent {
                        window.postMouseEvent(MouseEvent(type: .move,
                                                         window: window,
                                                         device: .genericMouse,
                                                         deviceID: 0,
                                                         buttonID: 0,
                                                         location: window.mousePosition,
                                                         delta: delta))
                    }
                }
                return 0
            case UINT(WM_LBUTTONDOWN):
                window.mouseButtonDownMask.insert(.button1)
                let pts = MAKEPOINTS(lParam)
                let pos = CGPoint(x: Int(pts.x), y: Int(pts.y)) * (1.0 / window.contentScaleFactor)

                window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: 0,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_LBUTTONUP):
                window.mouseButtonDownMask.remove(.button1)
                let pts = MAKEPOINTS(lParam)
                let pos = CGPoint(x: Int(pts.x), y: Int(pts.y)) * (1.0 / window.contentScaleFactor)

                window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: 0,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_RBUTTONDOWN):
                window.mouseButtonDownMask.insert(.button2)
                let pts = MAKEPOINTS(lParam)
                let pos = CGPoint(x: Int(pts.x), y: Int(pts.y)) * (1.0 / window.contentScaleFactor)

                window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: 1,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_RBUTTONUP):
                window.mouseButtonDownMask.remove(.button2)
                let pts = MAKEPOINTS(lParam)
                let pos = CGPoint(x: Int(pts.x), y: Int(pts.y)) * (1.0 / window.contentScaleFactor)

                window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: 1,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_MBUTTONDOWN):
                window.mouseButtonDownMask.insert(.button3)
                let pts = MAKEPOINTS(lParam)
                let pos = CGPoint(x: Int(pts.x), y: Int(pts.y)) * (1.0 / window.contentScaleFactor)

                window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: 2,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_MBUTTONUP):
                window.mouseButtonDownMask.remove(.button3)
                let pts = MAKEPOINTS(lParam)
                let pos = CGPoint(x: Int(pts.x), y: Int(pts.y)) * (1.0 / window.contentScaleFactor)

                window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: 2,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_XBUTTONDOWN):
                let pts = MAKEPOINTS(lParam)
                let pos = CGPoint(x: Int(pts.x), y: Int(pts.y)) * (1.0 / window.contentScaleFactor)

                let xButton = HIWORD(wParam)
                if xButton == XBUTTON1 {
                    window.mouseButtonDownMask.insert(.button4)

                    window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                     window: window,
                                                     device: .genericMouse,
                                                     deviceID: 0,
                                                     buttonID: 3,
                                                     location: pos))
                } else if xButton == XBUTTON2 {
                    window.mouseButtonDownMask.insert(.button5)

                    window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                     window: window,
                                                     device: .genericMouse,
                                                     deviceID: 0,
                                                     buttonID: 4,
                                                     location: pos))
                }
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 1 // Return TRUE.
            case UINT(WM_XBUTTONUP):
                let pts = MAKEPOINTS(lParam)
                let pos = CGPoint(x: Int(pts.x), y: Int(pts.y)) * (1.0 / window.contentScaleFactor)

                let xButton = HIWORD(wParam)
                if xButton == XBUTTON1 {
                    window.mouseButtonDownMask.remove(.button4)

                    window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                     window: window,
                                                     device: .genericMouse,
                                                     deviceID: 0,
                                                     buttonID: 3,
                                                     location: pos))
                } else if xButton == XBUTTON2 {
                    window.mouseButtonDownMask.remove(.button5)

                    window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                     window: window,
                                                     device: .genericMouse,
                                                     deviceID: 0,
                                                     buttonID: 4,
                                                     location: pos))
                }
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)                  
                return 1 // Return TRUE.
            case UINT(WM_GESTURENOTIFY):
                // Enable Zoom and Rotate. Block Pan so it falls through as WM_MOUSEWHEEL.
                var configs: [GESTURECONFIG] = [
                    GESTURECONFIG(dwID: DWORD(GID_ZOOM),   dwWant: DWORD(GC_ZOOM),   dwBlock: 0),
                    GESTURECONFIG(dwID: DWORD(GID_ROTATE), dwWant: DWORD(GC_ROTATE), dwBlock: 0),
                ]
                _ = configs.withUnsafeMutableBufferPointer {
                    SetGestureConfig(hWnd, 0, UINT($0.count), $0.baseAddress!,
                                     UINT(MemoryLayout<GESTURECONFIG>.size))
                }
                return 0

            case UINT(WM_GESTURE):
                let hGesture = HGESTUREINFO(bitPattern: Int(lParam))
                guard let hGesture else { break }
                var gi = GESTUREINFO()
                gi.cbSize = UINT(MemoryLayout<GESTUREINFO>.size)
                guard GetGestureInfo(hGesture, &gi) else { break }
                defer { _ = CloseGestureInfoHandle(hGesture) }

                var pt = POINT(x: LONG(gi.ptsLocation.x), y: LONG(gi.ptsLocation.y))
                ScreenToClient(hWnd, &pt)
                let location = CGPoint(x: Int(pt.x), y: Int(pt.y)) * (1.0 / window.contentScaleFactor)

                let isBegin = gi.dwFlags & DWORD(GF_BEGIN) != 0
                let isEnd   = gi.dwFlags & DWORD(GF_END)   != 0
                let phase: GestureEventPhase = isBegin ? .began : (isEnd ? .ended : .changed)

                switch gi.dwID {
                case DWORD(GID_ZOOM):
                    let dist = DWORD(gi.ullArguments & 0xFFFFFFFF)
                    if isBegin { window._lastGestureDistance = dist }
                    // Incremental magnification: current/previous ratio - 1, matching NSEvent.magnification.
                    let magnification: CGFloat = window._lastGestureDistance > 0
                        ? CGFloat(dist) / CGFloat(window._lastGestureDistance) - 1.0
                        : 0.0
                    window._lastGestureDistance = dist
                    window.postGestureEvent(GestureEvent(
                        type: .magnify, window: window, phase: phase,
                        location: location, magnification: magnification))

                case DWORD(GID_ROTATE):
                    let angle = gestureRotateAngle(gi.ullArguments)
                    if isBegin { window._lastGestureAngle = angle }
                    // Incremental delta in degrees, negated to match macOS convention.
                    let rotationDeg = CGFloat(-(angle - window._lastGestureAngle) * 180.0 / .pi)
                    window._lastGestureAngle = angle
                    window.postGestureEvent(GestureEvent(
                        type: .rotate, window: window, phase: phase,
                        location: location, rotation: rotationDeg))

                default:
                    break
                }
                return 0

            case UINT(WM_MOUSEWHEEL):
                let pts = MAKEPOINTS(lParam)
                var pt = POINT(x: LONG(pts.x), y: LONG(pts.y))
                ScreenToClient(hWnd, &pt)
                let pos = CGPoint(x: Int(pt.x), y: Int(pt.y)) * (1.0 / window.contentScaleFactor)

                let deltaY = Int16(bitPattern: UInt16(HIWORD(wParam)))
                let deltaYScaled = CGFloat(deltaY) / window.contentScaleFactor

                window.postMouseEvent(MouseEvent(type: .wheel,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: 2,
                                                 location: pos,
                                                 delta: CGPoint(x: 0, y: Int(deltaYScaled))))
                return 0
            case UINT(WM_CHAR):
                window.synchronizeKeyStates()
                if window.textCompositionMode {

                    var str: [WCHAR] = [WCHAR](repeating: 0, count: 2)
                    str[0] = WCHAR(wParam)

                    let inputText = String(decoding: str, as: UTF16.self)

                    window.postKeyboardEvent(KeyboardEvent(type: .textInput,
                                                           window: window,
                                                           deviceID: 0,
                                                           key: .none,
                                                           text: inputText))
                }
                return 0
            case UINT(WM_IME_STARTCOMPOSITION):
                return 0
            case UINT(WM_IME_ENDCOMPOSITION):
                return 0
            case UINT(WM_IME_COMPOSITION):
                window.synchronizeKeyStates()
                if lParam & LPARAM(GCS_RESULTSTR) != 0 {
                    // Composition finished. Result characters will arrive through
                    // WM_CHAR, so reset input-candidate characters here.
                    window.postKeyboardEvent(KeyboardEvent(type: .textComposition,
                                                           window: window,
                                                           deviceID: 0,
                                                           key: .none,
                                                           text: ""))  
                }
                if lParam & LPARAM(GCS_COMPSTR) != 0 {
                    // Composition in progress.
                    if let hIMC = ImmGetContext(hWnd) {
                        if window.textCompositionMode {
                            let bufferLength = ImmGetCompositionStringW(hIMC, DWORD(GCS_COMPSTR), nil, 0)
                            if bufferLength > 0 {
                                var tmp = [UInt8](repeating: 0, count: Int(bufferLength + 4))
                                let compositionText = tmp.withUnsafeMutableBytes {
                                    (ptr) -> String in
                                    ImmGetCompositionStringW(hIMC, DWORD(GCS_COMPSTR), ptr.baseAddress, UInt32(bufferLength + 2))
                                    return String(decodingCString: ptr.baseAddress!.assumingMemoryBound(to: WCHAR.self),
                                                    as: UTF16.self)
                                }

                                window.postKeyboardEvent(KeyboardEvent(type: .textComposition,
                                                                       window: window,
                                                                       deviceID: 0,
                                                                       key: .none,
                                                                       text: compositionText))  

                            } else {    // Composition character length became zero.
                                window.postKeyboardEvent(KeyboardEvent(type: .textComposition,
                                                                       window: window,
                                                                       deviceID: 0,
                                                                       key: .none,
                                                                       text: ""))  
                            }
                        } else {        // Text input mode is disabled.
                            ImmNotifyIME(hIMC, DWORD(NI_COMPOSITIONSTR), DWORD(CPS_CANCEL), 0)
                        }
                        ImmReleaseContext(hWnd, hIMC)
                    }
                }
                break
            case UINT(WM_PAINT):
                if window.resizing == false {
                    window.postWindowEvent(type: .update)
                }
                break
            case UINT(WM_SETCURSOR):
                if IsWindowEnabled(hWnd) == false &&
                     (HIWORD(lParam) == WM_LBUTTONDOWN || HIWORD(lParam) == WM_RBUTTONDOWN) &&
                     (LOWORD(lParam) & WORD(HTCLIENT | HTCAPTION)) != 0 {
                    if let currentModal = window.modalEntries.first?.window, let modal = currentModal.hWnd {
                        MessageBeep(UINT(MB_OK))
                        SetForegroundWindow(hWnd)
                        SetActiveWindow(modal)
                        
                        var fi = FLASHWINFO()
                        fi.cbSize = UINT(MemoryLayout<FLASHWINFO>.size)
                        fi.hwnd = modal
                        fi.dwFlags = DWORD(FLASHW_ALL | FLASHW_TIMERNOFG)
                        fi.uCount = 3
                        fi.dwTimeout = 0
                        FlashWindowEx(&fi)
                        return 1
                    }
                }
                break
            case UINT(WM_CLOSE):
                var close = true
                if let answer = window.delegate?.shouldClose(window: window) {
                    close = answer
                }
                if close {
                    window.close()
                }
                return 0
            case UINT(WM_COMMAND):
                break
            case UINT(WM_SYSCOMMAND):
                switch wParam {
                case WPARAM(SC_CONTEXTHELP), // Help menu.
                     WPARAM(SC_KEYMENU),     // Alt key.
                     WPARAM(SC_HOTKEY):      // Hot key.
                    return 0
                default:
                    break
                }
            case UINT(WM_SYSKEYDOWN), UINT(WM_KEYDOWN):
                if (lParam & LPARAM(1 << 30)) != 0 {
                    window.pendingKeyRepeat = Int(wParam)
                } else {
                    window.pendingKeyRepeat = nil
                }
                return 0
            case UINT(WM_SYSKEYUP), UINT(WM_KEYUP):
                window.pendingKeyRepeat = nil
                return 0
            case UINT(WM_VVDWINDOW_SHOWCURSOR):
                // Mouse-position control from another thread would need
                // AttachThreadInput(). Cursor visibility can be controlled by
                // this window message.
                if wParam != 0 {
                    while ShowCursor(true) < 0 {}
                } else {
                    while ShowCursor(false) >= 0 {}
                }
                return 0
            case UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE):
                if GetCapture() == hWnd {
                    if window.mouseButtonDownMask.rawValue == 0 && !window.mouseLocked {
                        ReleaseCapture()
                    }
                } else {
                    if window.mouseButtonDownMask.rawValue != 0 || window.mouseLocked {
                        SetCapture(hWnd)
                    }
                }
                return 0
            default:
                break
            }
        }
        return DefWindowProcW(hWnd, uMsg, wParam, lParam)
    }
}
#endif // ENABLE_WIN32
