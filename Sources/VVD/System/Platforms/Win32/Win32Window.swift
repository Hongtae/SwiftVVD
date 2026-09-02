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
private func dpiForWindow(_ hWnd: HWND) -> UINT {
    let dpi = GetDpiForWindow(hWnd)
    return dpi != 0 ? dpi : 96
}

@inline(__always)
private func dpiScaleForWindow(_ hWnd: HWND) -> CGFloat {
    CGFloat(dpiForWindow(hWnd)) / 96.0
}

// Timer settings.
private let updateKeyboardTimerId: UINT_PTR = 10
private let updateKeyboardTimeInterval: UINT = 10

// Custom window messages.
private let WM_VVDWINDOW_SHOWCURSOR = (WM_USER + 0x1175)
private let WM_VVDWINDOW_UPDATEMOUSECAPTURE = (WM_USER + 0x1180)

// Windows marks mouse messages synthesized from pen/touch input with this
// signature in GetMessageExtraInfo(). The low byte carries source details.
private let pointerCompatibilityMouseSignature: UInt64 = 0xFF51_5700
private let pointerCompatibilityMouseSignatureMask: UInt64 = 0xFFFF_FF00
private let win32PointerPressureMaximum: CGFloat = 1024.0

// Converts GID_ROTATE ullArguments to a cumulative angle in radians.
// Maps WORD range 0...65535 to -2 * Double.pi ... +2 * Double.pi.
@inline(__always)
private func gestureRotateAngle(_ arg: ULONGLONG) -> Double {
    let word = Double(arg & 0xFFFF)
    return (word / 65535.0) * (4.0 * Double.pi) - 2.0 * Double.pi
}

@inline(__always)
private func GET_POINTERID_WPARAM(_ wParam: WPARAM) -> UINT32 {
    UINT32(wParam & 0xFFFF)
}

@inline(__always)
private func isPointerCompatibilityMouseMessage() -> Bool {
    let extraInfo = UInt64(bitPattern: GetMessageExtraInfo()) & 0xFFFF_FFFF
    return (extraInfo & pointerCompatibilityMouseSignatureMask) ==
        pointerCompatibilityMouseSignature
}

@inline(__always)
private func timestampFromLow32Uptime(_ low32: DWORD) -> TimeInterval {
    let messageTime = UInt64(low32)
    let uptime = UInt64(GetTickCount64())
    let cycle = UInt64(UInt32.max) + 1
    var fullTime = (uptime & ~(cycle - 1)) | messageTime
    if fullTime > uptime {
        fullTime -= cycle
    }
    return TimeInterval(fullTime) / 1_000
}

@inline(__always)
private func degreesToRadians(_ degrees: CGFloat) -> CGFloat {
    degrees * .pi / 180.0
}

@inline(__always)
private func penAzimuthAltitude(
    tiltXDegrees: CGFloat,
    tiltYDegrees: CGFloat
) -> CGPoint {
    // Windows reports independent axis inclinations. Reconstruct the pen's
    // screen-plane direction before converting to azimuth and altitude.
    let projectedX = tan(degreesToRadians(tiltXDegrees))
    let projectedY = tan(degreesToRadians(tiltYDegrees))
    let altitude = atan2(1.0, hypot(projectedX, projectedY))

    guard projectedX != 0.0 || projectedY != 0.0 else {
        return CGPoint(x: 0.0, y: altitude)
    }
    var azimuth = atan2(projectedY, projectedX)
    if azimuth < 0.0 {
        azimuth += 2.0 * .pi
    }
    return CGPoint(x: azimuth, y: altitude)
}

func win32PenButtonID(
    pointerFlags: POINTER_FLAGS,
    penFlags: PEN_FLAGS,
    buttonChange: POINTER_BUTTON_CHANGE_TYPE,
    activeButtonID: Int?
) -> Int {
    // Keep one logical button for the complete contact sequence. Pointer-up
    // samples may no longer carry the button flag that selected the contact.
    if let activeButtonID {
        return activeButtonID
    }
    if buttonChange == POINTER_CHANGE_SECONDBUTTON_DOWN ||
        buttonChange == POINTER_CHANGE_SECONDBUTTON_UP {
        return 1
    }
    if buttonChange == POINTER_CHANGE_FIRSTBUTTON_DOWN ||
        buttonChange == POINTER_CHANGE_FIRSTBUTTON_UP {
        return 0
    }
    if pointerFlags & DWORD(POINTER_FLAG_SECONDBUTTON) != 0 ||
        penFlags & DWORD(PEN_FLAG_BARREL) != 0 {
        return 1
    }
    return 0
}

func win32RetainsPointerStateAfterEvent(
    type: MouseEventType,
    device: MouseEventDevice
) -> Bool {
    if type == .cancelled {
        return false
    }
    if type == .buttonUp {
        // A pen can return to hover after contact ends. Direct touch has no
        // independent post-contact hover phase in this backend.
        return device == .stylus
    }
    return true
}

private let HIGH_SURROGATE_START: WCHAR = 0xd800
private let HIGH_SURROGATE_END: WCHAR = 0xdbff
private let LOW_SURROGATE_START: WCHAR = 0xdc00
private let LOW_SURROGATE_END: WCHAR = 0xdfff


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

    private static let mouseButtonMappings: [(MouseButtonDownMask, Int)] = [
        (.button1, 0),
        (.button2, 1),
        (.button3, 2),
        (.button4, 3),
        (.button5, 4),
        (.button6, 5),
        (.button7, 6),
        (.button8, 7),
    ]

    private struct PointerInputState {
        var device: MouseEventDevice
        var buttonID: Int
        var clickCount: Int
        var location: CGPoint
        var tilt: CGPoint
        var pressure: CGFloat
        var timestamp: TimeInterval
        var touchData: TouchEventData?
        var hasActiveContact: Bool
    }

    private struct MouseClickSample {
        var buttonID: Int
        var pixelLocation: CGPoint
        var timestamp: TimeInterval
        var clickCount: Int
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
    private var mouseButtonClickCounts: [Int: Int] = [:]
    private var previousMouseClick: MouseClickSample?
    private var mouseLocked: Bool = false
    private var mouseInsideClient: Bool = false
    private var mouseLeaveTrackingArmed: Bool = false
    private var mouseBoundaryTrackingSuspended: Bool = false
    private var pointerStates: [UINT32: PointerInputState] = [:]
    private var cursorOverride: Cursor?
    private var cursorHandle: Win32CursorHandle?
    private var _menuController: Win32WindowMenuController?
    private var applyingNativeMenuGeometry = false
    private var textCompositionMode: Bool = false
    private var suppressTextCompositionEvents = false
    private var keyboardStates: [UInt8] = [UInt8](repeating: 0, count: 256)
    private var pendingKeyRepeat: Int? = nil
    
    private var utf16HighSurrogate: WCHAR? = nil

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

    private enum ModalPlacementMode {
        case attached
        case independent
    }

    private final class ModalPresentationContext: @unchecked Sendable {
        weak var host: Win32Window?
        let mode: ModalPlacementMode
        let hostWasEnabled: Bool
        let hostMouseWasLocked: Bool
        var previousOwner: HWND?

        // Attached SetWindowPos calls synchronously reenter the window
        // procedure. Coalesce that reentrancy into one final geometry pass.
        var applyingPlacement = false
        var placementPending = false

        // Placement suspension is Attached-specific. Visibility grouping is
        // common to both modes because owner SW_HIDE is not propagated by Win32.
        var hostPlacementSuspended = false
        var modalHiddenWithHost = false

        init(host: Win32Window,
             mode: ModalPlacementMode,
             hostWasEnabled: Bool,
             hostMouseWasLocked: Bool) {
            self.host = host
            self.mode = mode
            self.hostWasEnabled = hostWasEnabled
            self.hostMouseWasLocked = hostMouseWasLocked
        }
    }

    private final class ModalEntry: @unchecked Sendable {
        let window: Win32Window
        let completionHandler: (()->Void)?
        var context: ModalPresentationContext?

        init(window: Win32Window, completionHandler: (()->Void)?) {
            self.window = window
            self.completionHandler = completionHandler
        }
    }
    private var modalEntries: [ModalEntry] = []
    private weak var modalQueueHost: Win32Window?
    private var modalPresentationContext: ModalPresentationContext?

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

        self.contentBounds = CGRect(rc1, scale: invScale)
        self.windowFrame = CGRect(rc2)

        SetWindowPos(hWnd, nil, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED))
        SetTimer(hWnd, updateKeyboardTimerId, updateKeyboardTimeInterval, nil)
        postWindowEvent(type: .created)
    }

    deinit {
        let modals = self.modalEntries.map { $0.window }
        let hWnd = self.hWnd
        let menuController = self._menuController
        self._menuController = nil

        // windowMap retains only a weak reference, so the last owner may release
        // an active window without calling close(). Balance the activation count
        // before the asynchronous native-window cleanup loses this state.
        if self.activated && hWnd != nil {
            numActiveWindows -= 1
            Log.debug("VVD.numActiveWindows: \(numActiveWindows)")
        }

        Task { @MainActor in
            modals.forEach { $0.close() }

            if let hWnd {
                menuController?.invalidate(detachingFrom: hWnd)
                KillTimer(hWnd, updateKeyboardTimerId)
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
            if self.modalPresentationContext?.mode == .attached {
                self.repositionAttachedModal()
                return
            }
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
                let dpi = dpiForWindow(hWnd)

                var rc = RECT(left: 0, top: 0, right: LONG(w), bottom: LONG(h))
                if AdjustWindowRectExForDpi(&rc, style, menu, styleEx, dpi) {
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

    var menuController: (any WindowMenuController)? {
        guard hWnd != nil,
              !style.contains(.utilityWindow),
              !style.contains(.popupWindow) else {
            return nil
        }
        if let _menuController { return _menuController }
        let controller = Win32WindowMenuController(window: self)
        _menuController = controller
        return controller
    }

    func installNativeMenu(
        _ menu: HMENU?,
        preserveClientSize: Bool
    ) -> Bool {
        guard let hWnd else { return false }

        var desiredClient = RECT()
        guard GetClientRect(hWnd, &desiredClient) else { return false }
        let desiredWidth = desiredClient.right - desiredClient.left
        let desiredHeight = desiredClient.bottom - desiredClient.top
        let shouldPreserve = preserveClientSize &&
            desiredWidth > 0 && desiredHeight > 0 && !IsIconic(hWnd)

        applyingNativeMenuGeometry = true
        guard SetMenu(hWnd, menu) else {
            applyingNativeMenuGeometry = false
            return false
        }
        DrawMenuBar(hWnd)

        if shouldPreserve {
            for _ in 0..<4 {
                var client = RECT()
                var frame = RECT()
                guard GetClientRect(hWnd, &client), GetWindowRect(hWnd, &frame) else {
                    break
                }
                let widthDelta = desiredWidth - (client.right - client.left)
                let heightDelta = desiredHeight - (client.bottom - client.top)
                if widthDelta == 0 && heightDelta == 0 { break }

                SetWindowPos(
                    hWnd,
                    nil,
                    0,
                    0,
                    frame.right - frame.left + widthDelta,
                    frame.bottom - frame.top + heightDelta,
                    UINT(
                        SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE |
                        SWP_NOOWNERZORDER | SWP_FRAMECHANGED
                    )
                )
            }
        }

        var client = RECT()
        var frame = RECT()
        if GetClientRect(hWnd, &client) {
            contentBounds = CGRect(
                client,
                scale: 1.0 / contentScaleFactor
            )
        }
        if GetWindowRect(hWnd, &frame) {
            windowFrame = CGRect(frame)
        }
        applyingNativeMenuGeometry = false
        repositionActiveAttachedModal()
        repositionAttachedModal()
        return true
    }

    func minimize() {
        if let hWnd = self.hWnd {
            ShowWindow(hWnd, SW_MINIMIZE)
        }
    }

    func center() {
        guard self.modalPresentationContext?.mode != .attached,
              let hWnd,
              let screen = Win32Screen(
                MonitorFromWindow(hWnd, DWORD(MONITOR_DEFAULTTONEAREST))
              ) else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let outerSize = self.windowFrame.size
        self.origin = CGPoint(
            x: visibleFrame.minX
                + (visibleFrame.width - outerSize.width) * 0.5,
            y: visibleFrame.minY
                + (visibleFrame.height - outerSize.height) * 0.5
        )
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
        // A presented modal must leave its host queue while its HWND is still
        // valid. This restores the previous owner and the host enabled/focus
        // state before DefWindowProc destroys the owned window. Waiting for the
        // later `.closed` event can let Windows perform owner activation with a
        // stale disabled relationship.
        if let modalHost = self.modalQueueHost, modalHost !== self {
            _ = modalHost.dismissModalWindow(self)
        }

        // Close all modal windows.
        let entries = self.modalEntries
        self.modalEntries.removeAll()
        let completionHandlers = entries.compactMap { $0.completionHandler }
        entries.forEach { entry in
            self.endModalPresentation(entry, restoreHostActivation: false)
            entry.window.modalQueueHost = nil
            entry.window.removeEventObserver(self)
            entry.window.close()
        }
        if !completionHandlers.isEmpty {
            Task { completionHandlers.forEach { $0() } }
        }

        if let hWnd = self.hWnd {
            self._menuController?.invalidate()
            self._menuController = nil

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

            KillTimer(hWnd, updateKeyboardTimerId)

            // The HWND is removed from windowMap before the queued WM_CLOSE is
            // dispatched, so a later WA_INACTIVE message cannot update this
            // window's activation bookkeeping. Balance the count here while
            // the last known activation state is still available.
            if self.activated {
                numActiveWindows -= 1
                self.activated = false
                Log.debug("VVD.numActiveWindows: \(numActiveWindows)")
            }
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

    func setCursor(_ cursor: Cursor?, forDeviceID deviceID: Int) {
        guard deviceID == 0 else { return }

        let nextHandle = cursor.flatMap(Win32CursorHandle.init)
        if cursor != nil && nextHandle == nil {
            Log.error("Unable to create Win32 cursor for window: \(name)")
            return
        }

        let previousHandle = self.cursorHandle
        self.cursorOverride = cursor
        self.cursorHandle = nextHandle
        self.applyCursorIfInsideClient()
        _ = previousHandle
    }

    func cursor(forDeviceID deviceID: Int) -> Cursor? {
        deviceID == 0 ? cursorOverride : nil
    }

    private func applyCursorIfInsideClient() {
        guard let hWnd else { return }
        var screenPoint = POINT()
        guard GetCursorPos(&screenPoint), WindowFromPoint(screenPoint) == hWnd else {
            return
        }
        var clientPoint = screenPoint
        guard ScreenToClient(hWnd, &clientPoint),
              mouseLocationIsInsideClient(x: clientPoint.x, y: clientPoint.y) else {
            return
        }

        if let handle = cursorHandle?.handle {
            SetCursor(handle)
        } else {
            let arrow = UnsafePointer<WCHAR>(bitPattern: 32512)
            SetCursor(LoadCursorW(nil, arrow))
        }
    }

    func lockMouse(_ lock: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0, let pos = self.mousePosition(forDeviceID: 0) {
            if lock || self.mouseLocked {
                // Keep boundary notifications suspended until the window
                // thread has reconciled capture and TrackMouseEvent state.
                self.mouseBoundaryTrackingSuspended = true
            }
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
        if let pointerID = UINT32(exactly: deviceID),
           let state = self.pointerStates[pointerID] {
            return state.location
        }
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
            if self.textCompositionMode != enable {
                self.textCompositionMode = enable
                self.utf16HighSurrogate = nil
            }
        }
    }

    func isTextInputEnabled(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return self.textCompositionMode
        }
        return false
    }

    func resetTextComposition(
        _ emitEvents: Bool,
        forDeviceID deviceID: Int
    ) -> String? {
        guard deviceID == 0,
              let hWnd = self.hWnd,
              let hIMC = ImmGetContext(hWnd) else {
            return nil
        }

        let bufferLength = ImmGetCompositionStringW(
            hIMC,
            DWORD(GCS_COMPSTR),
            nil,
            0
        )
        let text: String
        if bufferLength > 0 {
            var buffer = [UInt8](
                repeating: 0,
                count: Int(bufferLength + 4)
            )
            text = buffer.withUnsafeMutableBytes { ptr in
                ImmGetCompositionStringW(
                    hIMC,
                    DWORD(GCS_COMPSTR),
                    ptr.baseAddress,
                    UInt32(bufferLength + 2)
                )
                return String(
                    decodingCString: ptr.baseAddress!
                        .assumingMemoryBound(to: WCHAR.self),
                    as: UTF16.self
                )
            }
        } else {
            text = ""
        }

        self.suppressTextCompositionEvents = true
        let didReset = ImmNotifyIME(
            hIMC,
            DWORD(NI_COMPOSITIONSTR),
            DWORD(CPS_CANCEL),
            0
        )
        ImmReleaseContext(hWnd, hIMC)

        guard didReset else {
            self.suppressTextCompositionEvents = false
            return nil
        }

        self.utf16HighSurrogate = nil
        if emitEvents && self.textCompositionMode {
            self.postKeyboardEvent(KeyboardEvent(
                type: .textInput,
                window: self,
                deviceID: 0,
                key: .none,
                text: text
            ))
            self.postKeyboardEvent(KeyboardEvent(
                type: .textComposition,
                window: self,
                deviceID: 0,
                key: .none,
                text: ""
            ))
        }
        return text.isEmpty ? nil : text
    }

    // MARK: - Input Synchronization

    private func resetMouse() {
        self.disarmMouseLeaveTracking()
        if let hWnd = self.hWnd {
            var pt = POINT()
            GetCursorPos(&pt)
            ScreenToClient(hWnd, &pt)
            mousePosition = CGPoint(x: Int(pt.x), y: Int(pt.y)) * (1.0 / self.contentScaleFactor)
        }
        self.mouseButtonDownMask = []
        self.resetMouseClickTracking()
        self.mouseInsideClient = false
        self.mouseBoundaryTrackingSuspended = self.mouseLocked
        self.pointerStates.removeAll()
    }

    private func mouseLocationIsInsideClient(x: LONG, y: LONG) -> Bool {
        guard let hWnd else { return false }
        var rect = RECT()
        guard GetClientRect(hWnd, &rect) else { return false }
        return x >= rect.left && x < rect.right &&
            y >= rect.top && y < rect.bottom
    }

    @discardableResult
    private func armMouseLeaveTracking() -> Bool {
        if mouseLeaveTrackingArmed { return true }
        guard let hWnd else { return false }
        var tracking = TRACKMOUSEEVENT()
        tracking.cbSize = DWORD(MemoryLayout<TRACKMOUSEEVENT>.size)
        tracking.dwFlags = DWORD(TME_LEAVE)
        tracking.hwndTrack = hWnd
        guard TrackMouseEvent(&tracking) else {
            Log.err("TrackMouseEvent failed: \(win32ErrorString(GetLastError()))")
            return false
        }
        mouseLeaveTrackingArmed = true
        return true
    }

    private func disarmMouseLeaveTracking() {
        guard mouseLeaveTrackingArmed else { return }
        defer { mouseLeaveTrackingArmed = false }
        guard let hWnd else { return }
        var tracking = TRACKMOUSEEVENT()
        tracking.cbSize = DWORD(MemoryLayout<TRACKMOUSEEVENT>.size)
        tracking.dwFlags = DWORD(TME_CANCEL) | DWORD(TME_LEAVE)
        tracking.hwndTrack = hWnd
        _ = TrackMouseEvent(&tracking)
    }

    private func updateMouseBoundaryTracking(
        at location: CGPoint,
        isInsideClient: Bool,
        timestamp: TimeInterval
    ) {
        // A locked mouse is a relative-input device: its reported location is
        // intentionally fixed and only move deltas are meaningful. Physical
        // motion must therefore not start or end client-boundary hover state.
        guard !mouseLocked, !mouseBoundaryTrackingSuspended else { return }

        guard isInsideClient else {
            endMouseBoundaryTracking(timestamp: timestamp)
            return
        }

        guard armMouseLeaveTracking(), !mouseInsideClient else { return }
        mouseInsideClient = true
        postMouseEvent(MouseEvent(
            type: .entered,
            window: self,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            modifiers: currentKeyboardModifiers(),
            location: location,
            timestamp: timestamp
        ))
    }

    private func endMouseBoundaryTracking(timestamp: TimeInterval) {
        disarmMouseLeaveTracking()
        guard mouseInsideClient else { return }
        mouseInsideClient = false
        let location = mousePosition(forDeviceID: 0) ?? mousePosition
        mousePosition = location
        postMouseEvent(MouseEvent(
            type: .exited,
            window: self,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            modifiers: currentKeyboardModifiers(),
            location: location,
            timestamp: timestamp
        ))
    }

    private func reconcileMouseBoundaryTracking(timestamp: TimeInterval) {
        guard let hWnd else { return }
        if mouseLocked {
            // TrackMouseEvent observes the physical cursor. Suspend it while
            // the window owns relative mouse input, but retain the logical
            // inside/outside state until ordinary positioning resumes.
            disarmMouseLeaveTracking()
            return
        }

        mouseBoundaryTrackingSuspended = false
        var point = POINT()
        guard GetCursorPos(&point), ScreenToClient(hWnd, &point) else { return }
        let location = CGPoint(x: Int(point.x), y: Int(point.y)) *
            (1.0 / contentScaleFactor)
        updateMouseBoundaryTracking(
            at: location,
            isInsideClient: mouseLocationIsInsideClient(x: point.x, y: point.y),
            timestamp: timestamp
        )
    }

    private func suspendMouseCaptureForModal() {
        // A modal may be presented synchronously from the host's button-down
        // callback. The matching button-up will then go to the modal, so keeping
        // the host's old button mask/capture would redirect later caption clicks
        // back into the host client area. End every host-owned pointer sequence
        // before transferring focus, then preserve only the intentional locked-
        // mouse state and rebuild it after the modal presentation ends.
        let timestamp = TimeInterval(GetTickCount64()) / 1_000
        self.cancelActiveMouseButtons(timestamp: timestamp)
        self.resetMouseClickTracking()
        self.cancelActivePointerEvents(timestamp: timestamp)
        self.mouseLocked = false
        if let hWnd = self.hWnd, GetCapture() == hWnd {
            ReleaseCapture()
        }
    }

    private func restoreMouseCaptureAfterModal(_ wasLocked: Bool) {
        guard wasLocked else { return }
        self.mouseLocked = true
        PostMessageW(self.hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
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

    private func currentKeyboardModifiers() -> KeyboardModifierFlags {
        func isDown(_ key: Int32) -> Bool {
            GetKeyState(key) < 0
        }

        var modifiers: KeyboardModifierFlags = []
        if GetKeyState(VK_CAPITAL) & 1 != 0 { modifiers.insert(.capsLock) }
        if isDown(VK_SHIFT) { modifiers.insert(.shift) }
        if isDown(VK_CONTROL) { modifiers.insert(.control) }
        if isDown(VK_MENU) { modifiers.insert(.option) }
        if isDown(VK_LWIN) || isDown(VK_RWIN) { modifiers.insert(.command) }
        return modifiers
    }

    private func beginMouseClick(
        buttonID: Int,
        pixelLocation: CGPoint,
        timestamp: TimeInterval
    ) -> Int {
        // Count ordinary down messages instead of enabling CS_DBLCLKS so the
        // sequence can continue through triple and higher-order clicks.
        let maximumMovement = CGSize(
            width: max(CGFloat(GetSystemMetrics(SM_CXDOUBLECLK)) * 0.5, 0.0),
            height: max(CGFloat(GetSystemMetrics(SM_CYDOUBLECLK)) * 0.5, 0.0)
        )
        let maximumInterval = TimeInterval(GetDoubleClickTime()) / 1_000
        let clickCount: Int
        if let previousMouseClick,
           previousMouseClick.buttonID == buttonID,
           timestamp >= previousMouseClick.timestamp,
           timestamp - previousMouseClick.timestamp <= maximumInterval,
           abs(pixelLocation.x - previousMouseClick.pixelLocation.x) <= maximumMovement.width,
           abs(pixelLocation.y - previousMouseClick.pixelLocation.y) <= maximumMovement.height,
           previousMouseClick.clickCount < Int.max {
            clickCount = previousMouseClick.clickCount + 1
        } else {
            clickCount = 1
        }
        previousMouseClick = MouseClickSample(
            buttonID: buttonID,
            pixelLocation: pixelLocation,
            timestamp: timestamp,
            clickCount: clickCount
        )
        mouseButtonClickCounts[buttonID] = clickCount
        return clickCount
    }

    private func endMouseClick(buttonID: Int) -> Int {
        mouseButtonClickCounts.removeValue(forKey: buttonID) ?? 0
    }

    private func postMouseButtonEvent(
        type: MouseEventType,
        buttonID: Int,
        pixelLocation: CGPoint,
        timestamp: TimeInterval
    ) {
        let clickCount: Int
        if type == .buttonDown {
            clickCount = beginMouseClick(
                buttonID: buttonID,
                pixelLocation: pixelLocation,
                timestamp: timestamp
            )
        } else {
            assert(type == .buttonUp)
            clickCount = endMouseClick(buttonID: buttonID)
        }
        postMouseEvent(MouseEvent(
            type: type,
            window: self,
            device: .genericMouse,
            deviceID: 0,
            buttonID: buttonID,
            clickCount: clickCount,
            modifiers: currentKeyboardModifiers(),
            location: pixelLocation * (1.0 / contentScaleFactor),
            timestamp: timestamp
        ))
    }

    private func resetMouseClickTracking() {
        previousMouseClick = nil
        mouseButtonClickCounts.removeAll()
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

    // MARK: - Pointer Input

    private func pointFromScreenPixel(_ point: POINT) -> CGPoint? {
        guard let hWnd = self.hWnd else { return nil }
        var pt = point
        guard ScreenToClient(hWnd, &pt) else { return nil }
        return CGPoint(x: Int(pt.x), y: Int(pt.y)) *
            (1.0 / self.contentScaleFactor)
    }

    private func pointerEventType(
        for message: UINT,
        flags: POINTER_FLAGS
    ) -> MouseEventType? {
        if flags & DWORD(POINTER_FLAG_CANCELED) != 0 {
            return .cancelled
        }
        switch message {
        case UINT(WM_POINTERDOWN):
            return .buttonDown
        case UINT(WM_POINTERUP):
            return .buttonUp
        case UINT(WM_POINTERUPDATE):
            if flags & DWORD(POINTER_FLAG_INCONTACT) != 0 {
                return .move
            }
            return .pointing
        default:
            return nil
        }
    }

    private func pointerDelta(for pointerID: UINT32,
                              type: MouseEventType,
                              location: CGPoint) -> CGPoint {
        guard type == .move || type == .pointing ||
                type == .buttonUp || type == .cancelled,
              let previous = self.pointerStates[pointerID]?.location else {
            return .zero
        }
        return CGPoint(x: location.x - previous.x,
                       y: location.y - previous.y)
    }

    @discardableResult
    private func cancelActiveMouseButtons(timestamp: TimeInterval) -> Bool {
        let downMask = self.mouseButtonDownMask
        guard downMask.rawValue != 0 else { return false }

        self.mouseButtonDownMask = []
        self.resetMouseClickTracking()
        let location = self.mousePosition(forDeviceID: 0) ?? self.mousePosition
        let modifiers = self.currentKeyboardModifiers()
        for (mask, buttonID) in Self.mouseButtonMappings where downMask.contains(mask) {
            self.postMouseEvent(MouseEvent(
                type: .cancelled,
                window: self,
                device: .genericMouse,
                deviceID: 0,
                buttonID: buttonID,
                modifiers: modifiers,
                location: location,
                timestamp: timestamp
            ))
        }
        return true
    }

    private func postPointerMouseEvent(type: MouseEventType,
                                       pointerID: UINT32,
                                       state: PointerInputState,
                                       delta: CGPoint) {
        self.pointerStates[pointerID] = state
        self.postMouseEvent(MouseEvent(
            type: type,
            window: self,
            device: state.device,
            deviceID: Int(pointerID),
            buttonID: state.buttonID,
            clickCount: type == .buttonDown || type == .buttonUp
                ? state.clickCount
                : 0,
            modifiers: self.currentKeyboardModifiers(),
            location: state.location,
            delta: delta,
            tilt: state.tilt,
            pressure: state.pressure,
            timestamp: state.timestamp,
            touchData: state.touchData
        ))
        if !win32RetainsPointerStateAfterEvent(type: type, device: state.device) {
            self.pointerStates.removeValue(forKey: pointerID)
        }
    }

    @discardableResult
    private func cancelPointerEvent(pointerID: UINT32,
                                    timestamp: TimeInterval,
                                    includingHover: Bool = false) -> Bool {
        guard let state = self.pointerStates.removeValue(forKey: pointerID) else {
            return false
        }
        if state.hasActiveContact || includingHover {
            self.postMouseEvent(MouseEvent(
                type: .cancelled,
                window: self,
                device: state.device,
                deviceID: Int(pointerID),
                buttonID: state.buttonID,
                modifiers: self.currentKeyboardModifiers(),
                location: state.location,
                delta: .zero,
                tilt: state.tilt,
                pressure: state.pressure,
                timestamp: timestamp,
                touchData: state.touchData
            ))
        }
        return true
    }

    @discardableResult
    private func cancelActivePointerEvents(timestamp: TimeInterval) -> Bool {
        var cancelled = false
        for pointerID in self.pointerStates.keys.sorted() {
            if self.cancelPointerEvent(
                pointerID: pointerID,
                timestamp: timestamp,
                includingHover: true
            ) {
                cancelled = true
            }
        }
        return cancelled
    }

    private func pointerContactMajorRadius(_ rect: RECT) -> CGFloat {
        let width = max(0, CGFloat(rect.right - rect.left))
        let height = max(0, CGFloat(rect.bottom - rect.top))
        return max(width, height) * 0.5 / self.contentScaleFactor
    }

    @discardableResult
    private func postPointerEvent(_ message: UINT,
                                  wParam: WPARAM,
                                  timestamp fallbackTimestamp: TimeInterval) -> Bool {
        let pointerID = GET_POINTERID_WPARAM(wParam)
        var pointerType = POINTER_INPUT_TYPE()
        guard GetPointerType(pointerID, &pointerType) else { return false }

        switch pointerType {
        case POINTER_INPUT_TYPE(PT_TOUCH.rawValue):
            var info = POINTER_TOUCH_INFO()
            guard GetPointerTouchInfo(pointerID, &info),
                  let type = self.pointerEventType(
                    for: message,
                    flags: info.pointerInfo.pointerFlags
                  ),
                  type != .pointing,
                  let location = self.pointFromScreenPixel(
                    info.pointerInfo.ptPixelLocation
                  ) else {
                return false
            }

            let hasContactArea =
                info.touchMask & DWORD(TOUCH_MASK_CONTACTAREA) != 0
            let hasPressure =
                info.touchMask & DWORD(TOUCH_MASK_PRESSURE) != 0
            let pressure = hasPressure ? CGFloat(info.pressure) : 0.0
            let timestamp = info.pointerInfo.dwTime != 0
                ? timestampFromLow32Uptime(info.pointerInfo.dwTime)
                : fallbackTimestamp
            let delta = self.pointerDelta(for: pointerID,
                                          type: type,
                                          location: location)
            let clickCount = type == .buttonDown
                ? 1
                : self.pointerStates[pointerID]?.clickCount ?? 0
            let touchData = TouchEventData(
                majorRadius: hasContactArea
                    ? self.pointerContactMajorRadius(info.rcContact)
                    : 0.0,
                maximumPossiblePressure: win32PointerPressureMaximum
            )
            self.postPointerMouseEvent(
                type: type,
                pointerID: pointerID,
                state: PointerInputState(
                    device: .touch,
                    buttonID: 0,
                    clickCount: clickCount,
                    location: location,
                    tilt: .zero,
                    pressure: pressure,
                    timestamp: timestamp,
                    touchData: touchData,
                    hasActiveContact: type != .buttonUp && type != .cancelled
                ),
                delta: delta
            )
            return true

        case POINTER_INPUT_TYPE(PT_PEN.rawValue):
            var info = POINTER_PEN_INFO()
            guard GetPointerPenInfo(pointerID, &info),
                  let type = self.pointerEventType(
                    for: message,
                    flags: info.pointerInfo.pointerFlags
                  ),
                  let location = self.pointFromScreenPixel(
                    info.pointerInfo.ptPixelLocation
                  ) else {
                return false
            }

            let hasPressure = info.penMask & DWORD(PEN_MASK_PRESSURE) != 0
            let hasTiltX = info.penMask & DWORD(PEN_MASK_TILT_X) != 0
            let hasTiltY = info.penMask & DWORD(PEN_MASK_TILT_Y) != 0
            let pressure = hasPressure ? CGFloat(info.pressure) : 0.0
            let tilt = penAzimuthAltitude(
                tiltXDegrees: hasTiltX ? CGFloat(info.tiltX) : 0.0,
                tiltYDegrees: hasTiltY ? CGFloat(info.tiltY) : 0.0
            )
            let timestamp = info.pointerInfo.dwTime != 0
                ? timestampFromLow32Uptime(info.pointerInfo.dwTime)
                : fallbackTimestamp
            let delta = self.pointerDelta(for: pointerID,
                                          type: type,
                                          location: location)
            let clickCount = type == .buttonDown
                ? 1
                : self.pointerStates[pointerID]?.clickCount ?? 0
            let activeButtonID = self.pointerStates[pointerID].flatMap {
                $0.hasActiveContact ? $0.buttonID : nil
            }
            let buttonID = win32PenButtonID(
                pointerFlags: info.pointerInfo.pointerFlags,
                penFlags: info.penFlags,
                buttonChange: info.pointerInfo.ButtonChangeType,
                activeButtonID: activeButtonID
            )
            self.postPointerMouseEvent(
                type: type,
                pointerID: pointerID,
                state: PointerInputState(
                    device: .stylus,
                    buttonID: buttonID,
                    clickCount: clickCount,
                    location: location,
                    tilt: tilt,
                    pressure: pressure,
                    timestamp: timestamp,
                    touchData: TouchEventData(
                        maximumPossiblePressure: win32PointerPressureMaximum
                    ),
                    hasActiveContact: type != .pointing &&
                        type != .buttonUp &&
                        type != .cancelled
                ),
                delta: delta
            )
            return true

        default:
            return false
        }
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

    /*
     Win32 modal presentation deliberately has two behaviors. Both are real
     modal presentations and both use a Win32 owner/owned-window relationship;
     "independent" describes placement and host interaction, not modality.

     The distinction lets a UI framework use one platform-neutral modal API for
     two native presentation styles. Attached mode reproduces AppKit sheet
     behavior. Independent mode is an AppKit/Win32 hybrid: it keeps modal
     ownership, lifetime, and visibility grouped with the host while using a
     Win32-style disabled owner and a freely movable dialog. There is no public
     mode switch. The mode is selected when an entry reaches the head of the
     modal queue, using the actual HWND styles rather than the requested VVD
     styles:

         (captioned host or Attached host) + captionless modal -> Attached
         every other combination                               -> Independent

     Reading WS_CAPTION from both HWNDs is important because the final native
     style is the authoritative indication that a system title bar exists.
     An Attached modal is also an eligible host so a captionless nested modal
     continues the same sheet chain whose ancestor owns the system title bar.
     A standalone borderless/custom-skinned host, or a host presented as
     Independent, still uses Independent mode even when its application-level
     appearance resembles a normal window.

     Shared rules
     ------------
     - The active modal is installed as an owned top-level window with
       GWLP_HWNDPARENT. The previous owner is restored on dismissal. Passing the
       host as SetWindowPos's hWndInsertAfter changes Z-order only and is not a
       substitute for this owner relationship.
     - Only the first queued entry owns a ModalPresentationContext. A later
       entry chooses its mode only when it becomes active, so transitions
       between Attached and Independent cannot inherit stale state.
     - The host's previous enabled state, mouse-lock state, and foreground
       ownership are preserved. Dismissal must not enable a host that was
       already disabled or steal focus from another application.
     - A host hide/minimize hides the active modal in both modes, and showing or
       restoring the host reveals it again. Explicit hide is handled here
       because Win32 automatically groups owned windows for minimization, but
       does not guarantee the same grouping when an owner is merely hidden.
     - Native close requests are modal interaction and are blocked. A direct
       programmatic host.close() remains an explicit lifetime operation: it
       dismisses/cleans up queued modals and then closes the host.
     - Presentation may begin inside a host mouse-down callback. Host capture
       and its pressed-button mask are cleared so the missing button-up cannot
       leave capture stuck; an intentional locked-mouse state is restored after
       dismissal.
     - Popup and utility-window activation/lifetime rules are unrelated to this
       path and must not be changed as part of modal presentation.

     Attached mode -- AppKit sheet semantics
     ----------------------------------------
     AppKit keeps a sheet attached to its parent content area while allowing
     native operations on the parent frame. To reproduce that behavior, the
     host HWND remains enabled. Disabling it with EnableWindow would also
     disable caption dragging, resize borders, and minimize/maximize buttons.
     Instead, client mouse, wheel, gesture, keyboard, IME, and drag/drop input
     are gated while selected non-client interactions remain native.

     Caption dragging, resizing, minimizing, maximizing, and restoring the host
     are allowed. User close requests and content interaction are blocked; a
     blocked click produces modal feedback and returns foreground/activation/
     focus to the modal. Windows may need to activate the host temporarily to
     enter a native move/size loop, so the modal is reactivated when that loop
     ends. The host can consequently look inactive, matching the AppKit sheet
     presentation, without being disabled. Do not synthesize an active host or
     keep its active render interval: Window.activated and frame pacing continue
     to follow native foreground activation while the modal owns focus.

     The platform continuously owns the Attached modal origin. The modal outer
     frame is horizontally centered in the host's screen-space client rect. It
     is vertically centered while it fits; if it is taller than the client
     area, its top is aligned with the client top. This is the Win32-coordinate
     equivalent of AppKit's rule that a large sheet may extend below and beyond
     the parent, but must not cover the parent's system title bar. Attached
     placement is intentionally not clamped to the monitor work area because
     attachment to the parent takes precedence.

         left = clientLeft + (clientWidth - modalOuterWidth) / 2
         centeredTop = clientTop + (clientHeight - modalOuterHeight) / 2
         top = max(clientTop, centeredTop)

     GetClientRect plus ClientToScreen supplies the host rectangle; GetWindowRect
     supplies the modal outer size. Mixing client size with outer size would
     offset a captioned or bordered modal and break the title-bar guarantee.

     Host/modal move, resize, DPI, maximize, and restore events recompute the
     position from current native rectangles rather than accumulating a delta.
     A direct origin setter is ignored, and external SetWindowPos movement is
     corrected in WM_WINDOWPOSCHANGING while still accepting size changes. The
     reentrancy/pending flags ensure that nested move/size messages do not either
     oscillate or lose the final placement. This continuous policy also supports
     a UI framework's normal creation sequence, where a modal starts at a small
     placeholder size and receives its fitted content size only after layout.
     Repositioning preserves Z-order: the owner chain already keeps each modal
     above its host, while raising an intermediate modal in a nested chain can
     expose it above its child until the child's subsequent WM_MOVE is handled.

     Independent mode -- AppKit/Win32 hybrid dialog semantics
     --------------------------------------------------------
     The entire host is disabled with EnableWindow for the duration of the
     presentation, so client and non-client operations are both unavailable.
     A click attempt on the disabled host produces feedback, restores an iconic
     modal if necessary, and brings the modal to the foreground with focus.

     The platform owns only the initial position: center the modal outer frame
     on the host outer frame, then clamp it to the nearest monitor work area.
     If the modal is larger than the work area on an axis, it is not resized;
     that axis is aligned to the work-area start so its top/left controls remain
     reachable. The clamp is never repeated after initial presentation.
     After presentation, user dragging and programmatic origin changes are
     authoritative. Host movement, modal resizing, and later application moves
     must not recenter or clamp it again.

     Message-routing invariants
     --------------------------
     - Attached content messages are gated before normal event translation.
       OLE IDropTarget callbacks bypass the window procedure, so the drop target
       separately checks blocksModalContentInput.
     - A disabled Independent host does not receive ordinary button-down
       messages. WM_SETCURSOR's triggering mouse message is therefore used to
       detect a click attempt. Hit-test constants such as HTCLIENT/HTCAPTION are
       integer values, not bit flags.
     - WM_MOVE.lParam for a top-level window identifies the client-area origin,
       not the outer-frame origin. GetWindowRect is the source of truth for both
       stored windowFrame state and Attached placement.
     - While the host is minimized or hidden, screen-space Attached placement is
       suspended and SWP_HIDEWINDOW is never corrected back into a move. Restore
       first reveals the modal, then recomputes placement from final rectangles.
     - WM_DPICHANGED applies the suggested frame before final placement. Host and
       modal DPI messages may arrive in either order, so each pass rereads native
       geometry and the pending flag requests a final pass after reentrancy.

     Keep these policies separate. In particular, disabling an Attached host
     breaks AppKit-compatible frame interaction, while continuously tracking an
     Independent modal takes control away from the user.
     */

    var canPresentModalWindow: Bool {
        hWnd != nil
    }

    var modalWindows: [any Window] {
        self.modalEntries.map { $0.window }
    }

    private var activeModalEntry: ModalEntry? {
        guard let entry = self.modalEntries.first, entry.context != nil else {
            return nil
        }
        return entry
    }

    private var activeModalMode: ModalPlacementMode? {
        self.activeModalEntry?.context?.mode
    }

    var blocksModalContentInput: Bool {
        // Independent hosts are already disabled, but Attached hosts remain
        // enabled. The OLE drop target uses this common flag because drag/drop
        // callbacks do not pass through blocksAttachedHostContentMessage().
        self.activeModalEntry != nil
    }

    private static func hasSystemCaption(_ hWnd: HWND) -> Bool {
        let style = DWORD(bitPattern: GetWindowLongW(hWnd, GWL_STYLE))
        return style & DWORD(WS_CAPTION) == DWORD(WS_CAPTION)
    }

    private func modalMode(for modal: Win32Window) -> ModalPlacementMode {
        guard let host = self.hWnd, let modal = modal.hWnd else {
            return .independent
        }
        let supportsAttachedPresentation = Self.hasSystemCaption(host) ||
            self.modalPresentationContext?.mode == .attached
        if supportsAttachedPresentation && !Self.hasSystemCaption(modal) {
            return .attached
        }
        return .independent
    }

    private func modalGroupOwnsForeground(_ entry: ModalEntry) -> Bool {
        let foreground = GetForegroundWindow()
        return foreground == self.hWnd || foreground == entry.window.hWnd
    }

    private func activateModal(_ modalWindow: Win32Window, feedback: Bool) {
        guard let modal = modalWindow.hWnd else { return }

        if feedback { MessageBeep(UINT(MB_OK)) }
        if IsIconic(modal) {
            ShowWindow(modal, SW_RESTORE)
        }
        SetForegroundWindow(modal)
        SetActiveWindow(modal)
        SetFocus(modal)

        if feedback {
            var info = FLASHWINFO()
            info.cbSize = UINT(MemoryLayout<FLASHWINFO>.size)
            info.hwnd = modal
            info.dwFlags = DWORD(FLASHW_ALL | FLASHW_TIMERNOFG)
            info.uCount = 3
            info.dwTimeout = 0
            FlashWindowEx(&info)
        }
    }

    private func notifyActiveModal() {
        guard let entry = self.activeModalEntry else { return }
        self.activateModal(entry.window, feedback: true)
    }

    private func blocksAttachedHostContentMessage(_ message: UINT) -> Bool {
        guard self.activeModalMode == .attached else { return false }
        switch message {
        case UINT(WM_MOUSEMOVE),
             UINT(WM_LBUTTONDOWN), UINT(WM_LBUTTONUP), UINT(WM_LBUTTONDBLCLK),
             UINT(WM_RBUTTONDOWN), UINT(WM_RBUTTONUP), UINT(WM_RBUTTONDBLCLK),
             UINT(WM_MBUTTONDOWN), UINT(WM_MBUTTONUP), UINT(WM_MBUTTONDBLCLK),
             UINT(WM_XBUTTONDOWN), UINT(WM_XBUTTONUP), UINT(WM_XBUTTONDBLCLK),
             UINT(WM_POINTERDOWN), UINT(WM_POINTERUPDATE), UINT(WM_POINTERUP),
             UINT(WM_POINTERWHEEL), UINT(WM_POINTERHWHEEL),
             UINT(WM_MOUSEWHEEL), UINT(WM_MOUSEHWHEEL),
             UINT(WM_GESTURENOTIFY), UINT(WM_GESTURE),
             UINT(WM_KEYDOWN), UINT(WM_KEYUP),
             UINT(WM_SYSKEYDOWN), UINT(WM_SYSKEYUP),
             UINT(WM_CHAR), UINT(WM_DEADCHAR),
             UINT(WM_SYSCHAR), UINT(WM_SYSDEADCHAR),
             UINT(WM_IME_STARTCOMPOSITION), UINT(WM_IME_ENDCOMPOSITION),
             UINT(WM_IME_COMPOSITION), UINT(WM_IME_CHAR),
             UINT(WM_IME_KEYDOWN), UINT(WM_IME_KEYUP),
             UINT(WM_DROPFILES):
            return true
        default:
            return false
        }
    }

    private static func isPointerDownMessage(_ message: UINT) -> Bool {
        switch message {
        case UINT(WM_LBUTTONDOWN), UINT(WM_RBUTTONDOWN),
             UINT(WM_MBUTTONDOWN), UINT(WM_XBUTTONDOWN),
             UINT(WM_POINTERDOWN), UINT(WM_NCPOINTERDOWN),
             UINT(WM_NCLBUTTONDOWN), UINT(WM_NCRBUTTONDOWN),
             UINT(WM_NCMBUTTONDOWN), UINT(WM_NCXBUTTONDOWN):
            return true
        default:
            return false
        }
    }

    private func reactivateAttachedModalAfterHostInteraction() {
        guard let entry = self.activeModalEntry,
              entry.context?.mode == .attached,
              let host = self.hWnd,
              !IsIconic(host),
              self.modalGroupOwnsForeground(entry) else {
            return
        }
        self.activateModal(entry.window, feedback: false)
    }

    private func attachedModalOrigin(outerWidth: LONG? = nil,
                                     outerHeight: LONG? = nil) -> POINT? {
        guard let context = self.modalPresentationContext,
              context.mode == .attached,
              !context.hostPlacementSuspended,
              let host = context.host?.hWnd,
              let modal = self.hWnd,
              !IsIconic(host) else {
            return nil
        }

        var clientRect = RECT()
        guard GetClientRect(host, &clientRect) else { return nil }
        var topLeft = POINT(x: clientRect.left, y: clientRect.top)
        var bottomRight = POINT(x: clientRect.right, y: clientRect.bottom)
        guard ClientToScreen(host, &topLeft), ClientToScreen(host, &bottomRight) else {
            return nil
        }

        var modalRect = RECT()
        guard GetWindowRect(modal, &modalRect) else { return nil }
        let width = outerWidth ?? (modalRect.right - modalRect.left)
        let height = outerHeight ?? (modalRect.bottom - modalRect.top)
        let clientWidth = bottomRight.x - topLeft.x
        let clientHeight = bottomRight.y - topLeft.y
        let left = topLeft.x + (clientWidth - width) / 2
        let centeredTop = topLeft.y + (clientHeight - height) / 2
        return POINT(x: left, y: max(topLeft.y, centeredTop))
    }

    private func repositionAttachedModal(show: Bool = false) {
        guard let context = self.modalPresentationContext,
              context.mode == .attached,
              let modal = self.hWnd,
              !IsIconic(modal) else {
            return
        }
        if context.applyingPlacement {
            context.placementPending = true
            return
        }

        context.applyingPlacement = true
        defer { context.applyingPlacement = false }

        var shouldShow = show
        repeat {
            context.placementPending = false
            guard let target = self.attachedModalOrigin() else { return }
            var current = RECT()
            guard GetWindowRect(modal, &current) else { return }
            if current.left != target.x || current.top != target.y || shouldShow {
                var flags = UINT(SWP_NOSIZE | SWP_NOZORDER |
                                 SWP_NOOWNERZORDER | SWP_NOACTIVATE)
                if shouldShow { flags |= UINT(SWP_SHOWWINDOW) }
                shouldShow = false
                SetWindowPos(modal, HWND_TOP, target.x, target.y, 0, 0, flags)
            }
        } while context.placementPending
    }

    private func constrainAttachedWindowPosition(_ position: UnsafeMutablePointer<WINDOWPOS>) {
        guard let context = self.modalPresentationContext,
              context.mode == .attached,
              !context.hostPlacementSuspended,
              position.pointee.flags & UINT(SWP_HIDEWINDOW) == 0 else {
            return
        }

        var rect = RECT()
        guard let modal = self.hWnd, GetWindowRect(modal, &rect) else { return }
        let changesOrigin = position.pointee.flags & UINT(SWP_NOMOVE) == 0
        let changesSize = position.pointee.flags & UINT(SWP_NOSIZE) == 0
        if changesOrigin || changesSize {
            // Geometry synchronization must not promote an intermediate modal
            // above its active nested child. Pure activation/Z-order requests
            // have neither geometry flag and remain unaffected.
            position.pointee.flags |= UINT(SWP_NOZORDER)
        }
        let width = changesSize ? position.pointee.cx : rect.right - rect.left
        let height = changesSize ? position.pointee.cy : rect.bottom - rect.top
        guard let target = self.attachedModalOrigin(outerWidth: width,
                                                    outerHeight: height) else {
            return
        }
        position.pointee.x = target.x
        position.pointee.y = target.y
        position.pointee.flags &= ~UINT(SWP_NOMOVE)
    }

    private func repositionActiveAttachedModal() {
        guard let entry = self.activeModalEntry,
              entry.context?.mode == .attached else {
            return
        }
        entry.window.repositionAttachedModal()
    }

    private func setActiveAttachedHostPlacementSuspended(_ suspended: Bool) {
        guard let context = self.activeModalEntry?.context,
              context.mode == .attached else {
            return
        }
        context.hostPlacementSuspended = suspended
    }

    private func hideActiveModalWithHost() {
        guard let entry = self.activeModalEntry,
              let context = entry.context,
              let modal = entry.window.hWnd else {
            return
        }
        if context.mode == .attached {
            context.hostPlacementSuspended = true
        }
        context.modalHiddenWithHost = true
        ShowWindow(modal, SW_HIDE)
    }

    private func restoreActiveModalWithHost(restoreActivation: Bool) {
        guard let entry = self.activeModalEntry,
              let context = entry.context,
              context.modalHiddenWithHost else {
            return
        }
        context.modalHiddenWithHost = false
        switch context.mode {
        case .attached:
            context.hostPlacementSuspended = false
            entry.window.repositionAttachedModal(show: true)
        case .independent:
            if let modal = entry.window.hWnd {
                SetWindowPos(modal, HWND_TOP, 0, 0, 0, 0,
                             UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOOWNERZORDER |
                                  SWP_NOACTIVATE | SWP_SHOWWINDOW))
            }
        }
        if restoreActivation && self.modalGroupOwnsForeground(entry) {
            self.activateModal(entry.window, feedback: false)
        }
    }

    private func positionIndependentModal(_ modalWindow: Win32Window) {
        guard let host = self.hWnd, let modal = modalWindow.hWnd else { return }
        var hostRect = RECT()
        var modalRect = RECT()
        guard GetWindowRect(host, &hostRect), GetWindowRect(modal, &modalRect) else {
            return
        }

        let width = modalRect.right - modalRect.left
        let height = modalRect.bottom - modalRect.top
        var left = hostRect.left + ((hostRect.right - hostRect.left) - width) / 2
        var top = hostRect.top + ((hostRect.bottom - hostRect.top) - height) / 2

        if let monitor = MonitorFromWindow(host, DWORD(MONITOR_DEFAULTTONEAREST)) {
            var info = MONITORINFO()
            info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
            if GetMonitorInfoW(monitor, &info) {
                let workWidth = info.rcWork.right - info.rcWork.left
                let workHeight = info.rcWork.bottom - info.rcWork.top
                if width <= workWidth {
                    left = min(max(left, info.rcWork.left), info.rcWork.right - width)
                } else {
                    left = info.rcWork.left
                }
                if height <= workHeight {
                    top = min(max(top, info.rcWork.top), info.rcWork.bottom - height)
                } else {
                    top = info.rcWork.top
                }
            }
        }

        SetWindowPos(modal, HWND_TOP, left, top, 0, 0,
                     UINT(SWP_NOSIZE | SWP_NOOWNERZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW))
    }

    private func endModalPresentation(_ entry: ModalEntry,
                                      restoreHostActivation: Bool) {
        guard let context = entry.context else { return }
        let modalWindow = entry.window

        if let modal = modalWindow.hWnd {
            let ownerValue = context.previousOwner.map {
                LONG_PTR(Int64(Int(bitPattern: $0)))
            } ?? 0
            SetWindowLongPtrW(modal, GWLP_HWNDPARENT, ownerValue)
        }
        if context.mode == .independent,
           context.hostWasEnabled,
           let host = context.host?.hWnd {
            EnableWindow(host, true)
        }
        context.host?.restoreMouseCaptureAfterModal(context.hostMouseWasLocked)

        if modalWindow.modalPresentationContext === context {
            modalWindow.modalPresentationContext = nil
        }
        entry.context = nil

        if restoreHostActivation,
           context.hostWasEnabled,
           let host = context.host?.hWnd,
           !IsIconic(host) {
            SetForegroundWindow(host)
            SetActiveWindow(host)
            SetFocus(host)
        }
    }

    func presentModalWindow(_ window: any Window, completionHandler: (()->Void)?) -> Bool {
        guard let modalWindow = window as? Win32Window else {
            Log.err("Window.presentModalWindow failed: incompatible window type.")
            return false
        }

        if modalWindow.isValid,
           modalWindow !== self,
           modalWindow.modalQueueHost == nil,
           modalWindow.modalPresentationContext == nil {
            let present = self.modalEntries.isEmpty
            modalWindow.modalQueueHost = self
            self.modalEntries.append(
                ModalEntry(window: modalWindow,
                           completionHandler: completionHandler))
            if present {
                self.presentNextModal()
            }
            return true
        }
        Log.err("Window.presentModalWindow failed: invalid or already presented window.")
        return false
    }

    func dismissModalWindow(_ window: any Window) -> Bool {
        guard let modalWindow = window as? Win32Window else {
            Log.err("Window.dismissModalWindow failed: incompatible window type.")
            return false
        }

        let current = self.modalEntries.first
        let dismissingCurrent = current?.window === modalWindow
        let restoreActivation = current.map(self.modalGroupOwnsForeground) ?? false
        modalWindow.removeEventObserver(self)

        var removedEntries: [ModalEntry] = []
        var completionHandlers: [(() -> Void)] = []
        self.modalEntries = self.modalEntries.filter {
            if $0.window !== modalWindow {
                return true
            }
            removedEntries.append($0)
            if let handler = $0.completionHandler {
                completionHandlers.append(handler)
            }
            return false
        }

        guard !removedEntries.isEmpty else { return false }
        removedEntries.forEach {
            self.endModalPresentation($0, restoreHostActivation: false)
            $0.window.modalQueueHost = nil
        }

        if dismissingCurrent {
            if let hWnd = modalWindow.hWnd { ShowWindow(hWnd, SW_HIDE) }
            self.presentNextModal(activate: restoreActivation)
            if self.modalEntries.isEmpty,
               restoreActivation,
               let host = self.hWnd,
               IsWindowEnabled(host),
               !IsIconic(host) {
                SetForegroundWindow(host)
                SetActiveWindow(host)
                SetFocus(host)
            }
        }

        if !completionHandlers.isEmpty {
            Task { completionHandlers.forEach { $0() } }
        }
        return true
    }

    private func presentNextModal(activate: Bool = true) {
        // Remove invalid windows from the modal list.
        var cancelledHandlers: [()->Void] = []
        self.modalEntries = self.modalEntries.filter {
            if $0.window.isValid { return true }
            self.endModalPresentation($0, restoreHostActivation: false)
            $0.window.modalQueueHost = nil
            if let handler = $0.completionHandler {
                cancelledHandlers.append(handler)
            }
            return false
        }
        if !cancelledHandlers.isEmpty {
            Task { cancelledHandlers.forEach { $0() } }
        }
        if let hWnd = self.hWnd {
            if let entry = self.modalEntries.first,
               let modal = entry.window.hWnd {
                let next = entry.window
                let mode = self.modalMode(for: next)
                let context = ModalPresentationContext(
                    host: self,
                    mode: mode,
                    hostWasEnabled: IsWindowEnabled(hWnd),
                    hostMouseWasLocked: self.mouseLocked
                )
                context.hostPlacementSuspended = IsIconic(hWnd)
                self.suspendMouseCaptureForModal()
                let previousOwnerValue = GetWindowLongPtrW(modal, GWLP_HWNDPARENT)
                context.previousOwner = previousOwnerValue == 0
                    ? nil
                    : HWND(bitPattern: Int(previousOwnerValue))
                SetWindowLongPtrW(modal, GWLP_HWNDPARENT,
                                  LONG_PTR(Int64(Int(bitPattern: hWnd))))
                entry.context = context
                next.modalPresentationContext = context

                next.addEventObserver(self) { (event: WindowEvent) in
                    if event.type == .closed {
                        next.removeEventObserver(self)
                        Task {
                            self.dismissModalWindow(next)
                        }
                    }
                }

                switch mode {
                case .attached:
                    next.repositionAttachedModal(show: true)
                case .independent:
                    if context.hostWasEnabled { EnableWindow(hWnd, false) }
                    self.positionIndependentModal(next)
                }

                Log.debug("Presenting \(mode) modal window")
                if activate {
                    self.activateModal(next, feedback: false)
                }
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

        @inline(__always) func HIWORD(_ value: LPARAM) -> WORD {
            return WORD((value >> 16) & 0xffff)
        }
        @inline(__always) func HIWORD(_ value: WPARAM) -> WORD {
            return WORD((value >> 16) & 0xffff)
        }
        @inline(__always) func LOWORD(_ value: LPARAM) -> WORD {
            return WORD(value & 0xffff)
        }
        @inline(__always) func LOWORD(_ value: WPARAM) -> WORD {
            return WORD(value & 0xffff)
        }

        @inline(__always) func IS_HIGH_SURROGATE(_ wch: WCHAR) -> Bool {
            ((wch) >= HIGH_SURROGATE_START) && ((wch) <= HIGH_SURROGATE_END)
        }
        @inline(__always) func IS_LOW_SURROGATE(_ wch: WCHAR) -> Bool {
            ((wch) >= LOW_SURROGATE_START) && ((wch) <= LOW_SURROGATE_END)
        }
        @inline(__always) func IS_SURROGATE_PAIR(_ hs: WCHAR, _ ls: WCHAR) -> Bool {
            IS_HIGH_SURROGATE(hs) && IS_LOW_SURROGATE(ls)
        }

        func messageTimestamp() -> TimeInterval {
            // GetMessageTime carries the low 32 bits of the uptime at which the
            // message entered the queue. Reconstruct the most recent matching
            // 64-bit epoch so timestamps remain monotonic across its rollover.
            timestampFromLow32Uptime(UInt32(truncatingIfNeeded: GetMessageTime()))
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
                    let timestamp = messageTimestamp()
                    window.cancelActiveMouseButtons(timestamp: timestamp)
                    window.cancelActivePointerEvents(timestamp: timestamp)
                    window.resetKeyStates()
                    window.resetMouse()
                    window.activated = false
                    window.postWindowEvent(type: .inactivated)                            
                    Log.debug("VVD.numActiveWindows: \(numActiveWindows)")
                }
            }

            if window.blocksAttachedHostContentMessage(uMsg) {
                if Self.isPointerDownMessage(uMsg) ||
                    (uMsg == UINT(WM_SYSKEYDOWN) && wParam == WPARAM(VK_F4)) {
                    window.notifyActiveModal()
                }
                return 0
            }

            switch uMsg {
            case UINT(WM_WINDOWPOSCHANGING):
                if let position = UnsafeMutablePointer<WINDOWPOS>(bitPattern: UInt(lParam)) {
                    window.constrainAttachedWindowPosition(position)
                }
                return DefWindowProcW(hWnd, uMsg, wParam, lParam)
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
                // Owned windows follow owner minimization, but an explicit
                // SW_HIDE of the owner does not reliably hide them. Mirror host
                // visibility for both modal modes without activating on show.
                if wParam != 0 {
                    window.setActiveAttachedHostPlacementSuspended(false)
                    if window.visible == false {
                        window.visible = true
                        window.minimized = false
                        window.postWindowEvent(type: .shown)
                    }
                    window.restoreActiveModalWithHost(restoreActivation: false)
                } else {
                    window.hideActiveModalWithHost()
                    if window.visible {
                        window.visible = false
                        window.postWindowEvent(type: .hidden)
                    }
                }
                return 0
            case UINT(WM_MOUSEACTIVATE):
                if window.activeModalMode == .attached {
                    let hitTest = LOWORD(lParam)
                    switch hitTest {
                    case WORD(HTCAPTION),
                         WORD(HTLEFT), WORD(HTRIGHT),
                         WORD(HTTOP), WORD(HTBOTTOM),
                         WORD(HTTOPLEFT), WORD(HTTOPRIGHT),
                         WORD(HTBOTTOMLEFT), WORD(HTBOTTOMRIGHT),
                         WORD(HTMINBUTTON), WORD(HTMAXBUTTON):
                        // A disabled-looking but enabled owner may still need to
                        // become active briefly for DefWindowProc to enter the
                        // native move/size or caption-button command loop. Client
                        // input remains gated, and activation returns to the modal
                        // when the native interaction completes.
                        return LRESULT(MA_ACTIVATE)
                    default:
                        window.notifyActiveModal()
                        return LRESULT(MA_NOACTIVATEANDEAT)
                    }
                }
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
                    window.windowFrame = CGRect(rcWindow)
                    let invScale = 1.0 / window.contentScaleFactor
                    window.contentBounds = CGRect(rcClient, scale: invScale)

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
                window.repositionActiveAttachedModal()
                window.reactivateAttachedModalAfterHostInteraction()
                return 0
            case UINT(WM_SIZING):
                window.beginResizeEventIfNeeded()
                return 1
            case UINT(WM_SIZE):
                let hostMinimized = wParam == SIZE_MINIMIZED || wParam == SIZE_MAXHIDE
                window.setActiveAttachedHostPlacementSuspended(hostMinimized)
                if hostMinimized {
                    window.hideActiveModalWithHost()
                }
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
                    let size = CGSize(width: Int(LOWORD(lParam)),
                                      height: Int(HIWORD(lParam)))
                    window.contentBounds.size =
                        size * (1.0 / window.contentScaleFactor) // DPI-scaled size.

                    var rc = RECT()
                    if GetWindowRect(hWnd, &rc) {
                        window.windowFrame = CGRect(rc)
                    } else {
                        let err = win32ErrorString(GetLastError())
                        Log.error("WM_SIZE: GetWindowRect failed: \(err)")
                    }

                    if window.applyingNativeMenuGeometry {
                        return 0
                    } else if window.minimized || window.visible == false {
                        window.minimized = false
                        window.visible = true
                        window.postWindowEvent(type: .shown)
                    } else {
                        window.beginResizeEventIfNeeded()
                        window.postWindowEvent(type: .resized)
                    }
                }
                if !hostMinimized {
                    window.restoreActiveModalWithHost(restoreActivation: true)
                }
                if wParam != SIZE_MINIMIZED && wParam != SIZE_MAXHIDE {
                    window.repositionActiveAttachedModal()
                    window.repositionAttachedModal()
                }
                return 0
            case UINT(WM_MOVING):
                window.invalidateMoveGeometryIfNeeded()
                return 1
            case UINT(WM_MOVE):
                // Reposition the active Attached child even inside a native
                // move/size loop. WM_MOVE.lParam is the client origin for a top-
                // level window, so outer-frame state is read with GetWindowRect.
                window.repositionActiveAttachedModal()
                if window.resizing == false {
                    var rect = RECT()
                    if GetWindowRect(hWnd, &rect) {
                        window.windowFrame = CGRect(rect)
                        window.postWindowEvent(type: .moved)
                    } else {
                        let err = win32ErrorString(GetLastError())
                        Log.error("WM_MOVE: GetWindowRect failed: \(err)")
                    }
                }
                window.repositionAttachedModal()
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

                    window.windowFrame = CGRect(rcWindow)
                    let invScale = 1.0 / scaleFactor
                    window.contentBounds = CGRect(rcClient, scale: invScale)

                    window.postWindowEvent(type: .resized)
                }
                window.repositionActiveAttachedModal()
                window.repositionAttachedModal()
                return 0    
            case UINT(WM_GETMINMAXINFO):
                let style = DWORD(bitPattern: GetWindowLongW(hWnd, GWL_STYLE))
                let styleEx = DWORD(bitPattern: GetWindowLongW(hWnd, GWL_EXSTYLE))
                let menu: Bool = GetMenu(hWnd) != nil
                let dpi = hWnd.map(dpiForWindow) ?? 96
                let scaleFactor = CGFloat(dpi) / 96.0

                var minSize = CGSize(width: 1, height: 1)
                if let size = window.delegate?.minimumContentSize(window: window) {
                    minSize.width = size.width
                    minSize.height = size.height
                }
                // Delegate constraints use logical content coordinates, while
                // MINMAXINFO requires physical window tracking sizes.
                let minWidth = LONG(max((minSize.width * scaleFactor).rounded(.up), 1))
                let minHeight = LONG(max((minSize.height * scaleFactor).rounded(.up), 1))
                var rc = RECT(left: 0, top: 0, right: minWidth, bottom: minHeight)
                if AdjustWindowRectExForDpi(&rc, style, menu, styleEx, dpi) {
                    let tmp: UnsafeMutablePointer<MINMAXINFO> = UnsafeMutablePointer<MINMAXINFO>(bitPattern: UInt(lParam))!
                    tmp.pointee.ptMinTrackSize.x = rc.right - rc.left
                    tmp.pointee.ptMinTrackSize.y = rc.bottom - rc.top
                }
                if let maxSize = window.delegate?.maximumContentSize(window: window) {
                    let maxWidth = LONG(max((maxSize.width * scaleFactor).rounded(.down), 1))
                    let maxHeight = LONG(max((maxSize.height * scaleFactor).rounded(.down), 1))
                    rc = RECT(left: 0, top: 0, right: maxWidth, bottom: maxHeight)
                    if AdjustWindowRectExForDpi(&rc, style, menu, styleEx, dpi) {
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
                if wParam == updateKeyboardTimerId {
                    window.synchronizeKeyStates()
                    return 0
                }
            case UINT(WM_POINTERDOWN), UINT(WM_POINTERUPDATE), UINT(WM_POINTERUP):
                // Keep the default pointer path alive so DefWindowProc can
                // synthesize higher-level gesture messages.
                _ = window.postPointerEvent(uMsg,
                                            wParam: wParam,
                                            timestamp: messageTimestamp())
                break
            case UINT(WM_POINTERCAPTURECHANGED):
                _ = window.cancelPointerEvent(
                    pointerID: GET_POINTERID_WPARAM(wParam),
                    timestamp: messageTimestamp(),
                    includingHover: true
                )
                break
            case UINT(WM_POINTERLEAVE):
                _ = window.cancelPointerEvent(
                    pointerID: GET_POINTERID_WPARAM(wParam),
                    timestamp: messageTimestamp(),
                    includingHover: true
                )
                break
            case UINT(WM_CAPTURECHANGED):
                _ = window.cancelActiveMouseButtons(timestamp: messageTimestamp())
                // The new capture owner controls the transition. Scheduling the
                // application's capture reconciler here can run after a native
                // move/size loop acquires capture and release that capture again.
                return 0
            case UINT(WM_CANCELMODE):
                let timestamp = messageTimestamp()
                _ = window.cancelActiveMouseButtons(timestamp: timestamp)
                window.resetMouseClickTracking()
                _ = window.cancelActivePointerEvents(timestamp: timestamp)
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                break
            case UINT(WM_MOUSEMOVE):
                if isPointerCompatibilityMouseMessage() { return 0 }
                let pt = MAKEPOINTS(lParam)
                let timestamp = messageTimestamp()
                let oldPtX = Int((window.mousePosition.x * window.contentScaleFactor).rounded())
                let oldPtY = Int((window.mousePosition.y * window.contentScaleFactor).rounded())
                let location = CGPoint(x: Int(pt.x), y: Int(pt.y)) *
                    (1.0 / window.contentScaleFactor)
                window.updateMouseBoundaryTracking(
                    at: location,
                    isInsideClient: window.mouseLocationIsInsideClient(
                        x: LONG(pt.x),
                        y: LONG(pt.y)
                    ),
                    timestamp: timestamp
                )
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
                                                         modifiers: window.currentKeyboardModifiers(),
                                                         location: window.mousePosition,
                                                         delta: delta,
                                                         timestamp: timestamp))
                    }
                }
                return 0
            case UINT(WM_MOUSELEAVE):
                // Windows cancels the TrackMouseEvent request before posting
                // this message. Locked relative input retains its logical
                // boundary state and rearms tracking after it is unlocked.
                guard window.mouseLeaveTrackingArmed else { return 0 }
                window.mouseLeaveTrackingArmed = false
                if window.mouseLocked || window.mouseBoundaryTrackingSuspended {
                    return 0
                }
                window.endMouseBoundaryTracking(timestamp: messageTimestamp())
                return 0
            case UINT(WM_LBUTTONDOWN):
                if isPointerCompatibilityMouseMessage() { return 0 }
                window.mouseButtonDownMask.insert(.button1)
                let pts = MAKEPOINTS(lParam)
                window.postMouseButtonEvent(
                    type: .buttonDown,
                    buttonID: 0,
                    pixelLocation: CGPoint(x: Int(pts.x), y: Int(pts.y)),
                    timestamp: messageTimestamp()
                )
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_LBUTTONUP):
                if isPointerCompatibilityMouseMessage() { return 0 }
                window.mouseButtonDownMask.remove(.button1)
                let pts = MAKEPOINTS(lParam)
                window.postMouseButtonEvent(
                    type: .buttonUp,
                    buttonID: 0,
                    pixelLocation: CGPoint(x: Int(pts.x), y: Int(pts.y)),
                    timestamp: messageTimestamp()
                )
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_RBUTTONDOWN):
                if isPointerCompatibilityMouseMessage() { return 0 }
                window.mouseButtonDownMask.insert(.button2)
                let pts = MAKEPOINTS(lParam)
                window.postMouseButtonEvent(
                    type: .buttonDown,
                    buttonID: 1,
                    pixelLocation: CGPoint(x: Int(pts.x), y: Int(pts.y)),
                    timestamp: messageTimestamp()
                )
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_RBUTTONUP):
                if isPointerCompatibilityMouseMessage() { return 0 }
                window.mouseButtonDownMask.remove(.button2)
                let pts = MAKEPOINTS(lParam)
                window.postMouseButtonEvent(
                    type: .buttonUp,
                    buttonID: 1,
                    pixelLocation: CGPoint(x: Int(pts.x), y: Int(pts.y)),
                    timestamp: messageTimestamp()
                )
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_MBUTTONDOWN):
                if isPointerCompatibilityMouseMessage() { return 0 }
                window.mouseButtonDownMask.insert(.button3)
                let pts = MAKEPOINTS(lParam)
                window.postMouseButtonEvent(
                    type: .buttonDown,
                    buttonID: 2,
                    pixelLocation: CGPoint(x: Int(pts.x), y: Int(pts.y)),
                    timestamp: messageTimestamp()
                )
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_MBUTTONUP):
                if isPointerCompatibilityMouseMessage() { return 0 }
                window.mouseButtonDownMask.remove(.button3)
                let pts = MAKEPOINTS(lParam)
                window.postMouseButtonEvent(
                    type: .buttonUp,
                    buttonID: 2,
                    pixelLocation: CGPoint(x: Int(pts.x), y: Int(pts.y)),
                    timestamp: messageTimestamp()
                )
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 0
            case UINT(WM_XBUTTONDOWN):
                if isPointerCompatibilityMouseMessage() { return 1 }
                let pts = MAKEPOINTS(lParam)
                let pixelLocation = CGPoint(x: Int(pts.x), y: Int(pts.y))

                let xButton = HIWORD(wParam)
                if xButton == XBUTTON1 {
                    window.mouseButtonDownMask.insert(.button4)
                    window.postMouseButtonEvent(
                        type: .buttonDown,
                        buttonID: 3,
                        pixelLocation: pixelLocation,
                        timestamp: messageTimestamp()
                    )
                } else if xButton == XBUTTON2 {
                    window.mouseButtonDownMask.insert(.button5)
                    window.postMouseButtonEvent(
                        type: .buttonDown,
                        buttonID: 4,
                        pixelLocation: pixelLocation,
                        timestamp: messageTimestamp()
                    )
                }
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)
                return 1 // Return TRUE.
            case UINT(WM_XBUTTONUP):
                if isPointerCompatibilityMouseMessage() { return 1 }
                let pts = MAKEPOINTS(lParam)
                let pixelLocation = CGPoint(x: Int(pts.x), y: Int(pts.y))

                let xButton = HIWORD(wParam)
                if xButton == XBUTTON1 {
                    window.mouseButtonDownMask.remove(.button4)
                    window.postMouseButtonEvent(
                        type: .buttonUp,
                        buttonID: 3,
                        pixelLocation: pixelLocation,
                        timestamp: messageTimestamp()
                    )
                } else if xButton == XBUTTON2 {
                    window.mouseButtonDownMask.remove(.button5)
                    window.postMouseButtonEvent(
                        type: .buttonUp,
                        buttonID: 4,
                        pixelLocation: pixelLocation,
                        timestamp: messageTimestamp()
                    )
                }
                PostMessageW(hWnd, UINT(WM_VVDWINDOW_UPDATEMOUSECAPTURE), 0, 0)                  
                return 1 // Return TRUE.
            case UINT(WM_GESTURENOTIFY):
                // Enable zoom and rotation. Raw pointer contacts drive panning,
                // so GID_PAN is deliberately consumed below.
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

                case DWORD(GID_PAN):
                    // The raw pointer sequence already feeds pan recognition.
                    break

                default:
                    // DefWindowProc owns the gesture handle for forwarded
                    // messages, including GID_BEGIN and GID_END.
                    return DefWindowProcW(hWnd, uMsg, wParam, lParam)
                }
                _ = CloseGestureInfoHandle(hGesture)
                return 0

            case UINT(WM_MOUSEWHEEL), UINT(WM_MOUSEHWHEEL):
                let pts = MAKEPOINTS(lParam)
                var pt = POINT(x: LONG(pts.x), y: LONG(pts.y))
                ScreenToClient(hWnd, &pt)
                let pos = CGPoint(x: Int(pt.x), y: Int(pt.y)) * (1.0 / window.contentScaleFactor)

                // Both messages store their single-axis wheel delta in the high
                // word. The message kind determines which logical axis it drives;
                // the low word contains modifier/button flags, not another delta.
                let rawDelta = Int16(bitPattern: UInt16(HIWORD(wParam)))
                let scaledDelta = CGFloat(rawDelta) / window.contentScaleFactor
                let delta: CGPoint
                let source: ScrollEventSource
                if uMsg == UINT(WM_MOUSEHWHEEL) {
                    delta = CGPoint(x: Int(scaledDelta), y: 0)
                    source = .wheelTilt
                } else {
                    delta = CGPoint(x: 0, y: Int(scaledDelta))
                    source = .wheel
                }

                window.postMouseEvent(MouseEvent(type: .wheel,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceID: 0,
                                                 buttonID: 2,
                                                 modifiers: window.currentKeyboardModifiers(),
                                                 location: pos,
                                                 delta: delta,
                                                 timestamp: messageTimestamp(),
                                                 scrollData: ScrollEventData(
                                                    source: source,
                                                    isPrecise: abs(Int(rawDelta)) % 120 != 0
                                                 )))
                return 0
            case UINT(WM_CHAR), UINT(WM_IME_CHAR):
                window.synchronizeKeyStates()
                if window.textCompositionMode {

                    let codeUnit = WCHAR(wParam)
                    let inputText: String?

                    if let high = window.utf16HighSurrogate {
                        window.utf16HighSurrogate = nil

                        if IS_LOW_SURROGATE(codeUnit) {
                            inputText = String(decoding: [high, codeUnit],
                                               as: UTF16.self)
                        } else if IS_HIGH_SURROGATE(codeUnit) {
                            inputText = String(decoding: [high],
                                               as: UTF16.self)
                            window.utf16HighSurrogate = codeUnit
                        } else {
                            inputText = String(decoding: [high, codeUnit],
                                               as: UTF16.self)
                        }
                    } else if IS_HIGH_SURROGATE(codeUnit) {
                        window.utf16HighSurrogate = codeUnit
                        inputText = nil
                    } else {
                        inputText = String(decoding: [codeUnit],
                                           as: UTF16.self)
                    }

                    if let inputText {
                        window.postKeyboardEvent(KeyboardEvent(type: .textInput,
                                                               window: window,
                                                               deviceID: 0,
                                                               key: .none,
                                                               text: inputText))
                    }
                }
                return 0
            case UINT(WM_IME_STARTCOMPOSITION):
                window.suppressTextCompositionEvents = false
                return 0
            case UINT(WM_IME_ENDCOMPOSITION):
                window.suppressTextCompositionEvents = false
                return 0
            case UINT(WM_IME_COMPOSITION):
                if window.suppressTextCompositionEvents {
                    return 0
                }
                window.synchronizeKeyStates()
                if lParam & LPARAM(GCS_RESULTSTR) != 0 {
                    // Composition finished. Result characters will arrive through
                    // character messages, so reset input-candidate characters here.
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
            case UINT(WM_INITMENU):
                window._menuController?.menuWillOpen(
                    HMENU(bitPattern: UInt(wParam))
                )
                return 0
            case UINT(WM_INITMENUPOPUP):
                window._menuController?.menuWillOpen(
                    HMENU(bitPattern: UInt(wParam))
                )
                return 0
            case UINT(WM_ENTERMENULOOP):
                window._menuController?.menuTrackingDidBegin()
                return 0
            case UINT(WM_EXITMENULOOP):
                window._menuController?.menuTrackingDidEnd()
                return 0
            case UINT(WM_SETCURSOR):
                // A disabled Independent host receives no normal button-down.
                // WM_SETCURSOR still reports the triggering mouse message in
                // HIWORD(lParam), which lets the host redirect attention to the
                // active modal (including restoring an iconic modal).
                if window.activeModalMode == .independent,
                   IsWindowEnabled(hWnd) == false,
                   Self.isPointerDownMessage(UINT(HIWORD(lParam))) {
                    window.notifyActiveModal()
                    return 1
                }
                if LOWORD(lParam) == WORD(HTCLIENT),
                   let cursor = window.cursorHandle?.handle {
                    SetCursor(cursor)
                    return 1
                }
                break
            case UINT(WM_CLOSE):
                if window.activeModalEntry != nil {
                    window.notifyActiveModal()
                    return 0
                }
                var close = true
                if let answer = window.delegate?.shouldClose(window: window) {
                    close = answer
                }
                if close {
                    window.close()
                }
                return 0
            case UINT(WM_COMMAND):
                let source = HIWORD(wParam)
                let commandID = UINT(LOWORD(wParam))
                if source == 0,
                   window._menuController?.performCommand(commandID) == true {
                    return 0
                }
                break
            case UINT(WM_SYSCOMMAND):
                let command = wParam & WPARAM(0xfff0)
                if let mode = window.activeModalMode {
                    if mode == .attached && command == WPARAM(SC_MINIMIZE) {
                        window.hideActiveModalWithHost()
                    }
                    if mode == .independent || command == WPARAM(SC_CLOSE) {
                        window.notifyActiveModal()
                        return 0
                    }
                }
                switch command {
                case WPARAM(SC_KEYMENU):
                    if window._menuController?.hasAttachedMenu == true {
                        break
                    }
                    return 0
                case WPARAM(SC_CONTEXTHELP), // Help menu.
                     WPARAM(SC_HOTKEY):      // Hot key.
                    return 0
                default:
                    break
                }
            case UINT(WM_SYSKEYDOWN), UINT(WM_KEYDOWN):
                if window._menuController?.performShortcut(
                    virtualKey: UINT(wParam)
                ) == true {
                    return 0
                }
                if window._menuController?.hasAttachedMenu == true,
                   uMsg == UINT(WM_SYSKEYDOWN) || wParam == WPARAM(VK_F10) {
                    return DefWindowProcW(hWnd, uMsg, wParam, lParam)
                }
                if (lParam & LPARAM(1 << 30)) != 0 {
                    window.pendingKeyRepeat = Int(wParam)
                } else {
                    window.pendingKeyRepeat = nil
                }
                return 0
            case UINT(WM_SYSKEYUP), UINT(WM_KEYUP):
                window.pendingKeyRepeat = nil
                if window._menuController?.hasAttachedMenu == true,
                   uMsg == UINT(WM_SYSKEYUP) || wParam == WPARAM(VK_F10) {
                    return DefWindowProcW(hWnd, uMsg, wParam, lParam)
                }
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
                window.reconcileMouseBoundaryTracking(
                    timestamp: messageTimestamp()
                )
                return 0
            default:
                break
            }
        }
        return DefWindowProcW(hWnd, uMsg, wParam, lParam)
    }
}

fileprivate extension CGRect {
    init(_ rect: RECT) {
        self.init(
            x: Int(rect.left),
            y: Int(rect.top),
            width: Int(rect.right - rect.left),
            height: Int(rect.bottom - rect.top)
        )
    }

    init(_ rect: RECT, scale: CGFloat) {
        self.init(
            x: CGFloat(rect.left) * scale,
            y: CGFloat(rect.top) * scale,
            width: CGFloat(rect.right - rect.left) * scale,
            height: CGFloat(rect.bottom - rect.top) * scale
        )
    }
}
#endif // ENABLE_WIN32
