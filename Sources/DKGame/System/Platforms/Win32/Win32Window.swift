#if ENABLE_WIN32
import WinSDK
import Foundation

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
                0, nil);
        }
    }

    if numChars > 0 {
        let ret = String(decodingCString: buffer!, as: UTF16.self)
        LocalFree(buffer)
        return ret
    }
    return "Unknown error: \(code)"
}

private func dpiScaleForWindow(_ hWnd: HWND) -> CGFloat {
    let dpi = GetDpiForWindow(hWnd)
    if dpi != 0 {
        return CGFloat(dpi) / 96.0
    }
    return 1.0
}

private let windowClass = "_SwiftDKGame_WndClass"

// TIMER ID
private let updateKeyboardMouseTimerId: UINT_PTR = 10
private let updateKeyboardMouseTimeInterval: UINT = 10
// WINDOW MESSAGE
private let WM_DKWINDOW_SHOWCURSOR = (WM_USER + 0x1175)
private let WM_DKWINDOW_UPDATEMOUSECAPTURE = (WM_USER + 0x1180)

private let HWND_TOP:HWND? = nil
private let HWND_TOPMOST:HWND = HWND(bitPattern: -1)!
private let HWND_NOTOPMOST:HWND = HWND(bitPattern: -2)!


public class Win32Window : Window {

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

    public private(set) var hWnd : HWND?
    public private(set) var style: WindowStyle
    public private(set) var contentBounds: CGRect = .null
    public private(set) var windowFrame: CGRect = .null
    public private(set) var contentScaleFactor: CGFloat = 1.0

    public var name: String

    public private(set) weak var delegate: WindowDelegate?

    public private(set) var resizing: Bool = false
    public private(set) var activated: Bool = false
    public private(set) var visible: Bool = false
    public private(set) var minimized: Bool = false
    
    private var mousePosition: CGPoint = .zero
    private var holdingMousePosition: CGPoint = .zero
    private var mouseButtonDownMask: MouseButtonDownMask = []
    private var holdMouse: Bool = false
    private var textCompositionMode: Bool = false
    private var keyboardStates: [UInt8] = [UInt8](repeating: 0, count: 256)

    private var dropTarget: UnsafeMutablePointer<Win32DropTarget>?

    private lazy var registeredWindowClass: ATOM? = {      
        let atom: ATOM? = windowClass.withCString(encodedAs: UTF16.self) {
            className in

            let IDC_ARROW: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!
            let IDI_APPLICATION: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!

            var wc = WNDCLASSEXW(
                cbSize: UINT(MemoryLayout<WNDCLASSEXW>.size),
                style: UINT(CS_OWNDC),
                lpfnWndProc: { (hWnd, uMsg, wParam, lParam) -> LRESULT in Win32Window.windowProc(hWnd, uMsg, wParam, lParam) },
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
            Log.err("RegisterClassExW failed.")
        } else {
            Log.debug("WindowClass: \"\(windowClass)\" registered!")
        }
        return atom
    }()
    public required init(name: String, style: WindowStyle, delegate: WindowDelegate?) {

        OleInitialize(nil)

        self.name = name
        self.style = style
        self.delegate = delegate    

        _ = self.registeredWindowClass

        if self.create() == nil {
            Log.err("CreateWindow failed: \(win32ErrorString(GetLastError()))")
        }
    }
    deinit {
        OleUninitialize()
    }

    public func show() {
        if let hWnd = self.hWnd {
            if IsIconic(hWnd) {
                ShowWindow(hWnd, SW_RESTORE)
            } else {
                ShowWindow(hWnd, SW_SHOWNA)
            }
        }
    }

    public func hide() {
        if let hWnd = self.hWnd {
            ShowWindow(hWnd, SW_HIDE);
        }
    }

    public func activate() {
        if let hWnd = self.hWnd {
            if IsIconic(hWnd) {
                ShowWindow(hWnd, SW_RESTORE);
            }
            ShowWindow(hWnd, SW_SHOW);
            SetWindowPos(hWnd, HWND_TOP, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW));
            SetForegroundWindow(hWnd);
        }
    }

    public var origin: CGPoint {
        get { self.windowFrame.origin }
        set (value) {
            if let hWnd = self.hWnd {
                let x = Int32(value.x)
                let y = Int32(value.y)
                SetWindowPos(hWnd, HWND_TOP, x, y, 0, 0, UINT(SWP_NOSIZE | SWP_NOOWNERZORDER | SWP_NOACTIVATE));
            }
        }
    }

    public var contentSize: CGSize {
        get { self.contentBounds.size }
        set (value) {
            if let hWnd = self.hWnd {
                var w = Int32(value.width)
                var h = Int32(value.height)

                let style: DWORD = DWORD(GetWindowLongW(hWnd, GWL_STYLE))
                let styleEx: DWORD = DWORD(GetWindowLongW(hWnd, GWL_EXSTYLE))
                let menu: Bool = GetMenu(hWnd) != nil

                var rc = RECT(left: 0,
                                top: 0,
                                right: LONG(max(w, 1)),
                                bottom: LONG(max(h, 1)))
                if AdjustWindowRectEx(&rc, style, menu, styleEx) {
                    w = rc.right - rc.left
                    h = rc.bottom - rc.top
                    SetWindowPos(hWnd, HWND_TOP, 0, 0, w, h, UINT(SWP_NOMOVE | SWP_NOOWNERZORDER | SWP_NOACTIVATE))
                }
            }  
        }
    }

    public func minimize() {
        if let hWnd = self.hWnd {
            ShowWindow(hWnd, SW_MINIMIZE);
        }
    }

    func create() -> HWND? {
        if let hWnd = self.hWnd {
            return hWnd
        }

        var dwStyle: DWORD = 0
        if style.contains(.title)           { dwStyle |= UInt32(WS_CAPTION) }
        if style.contains(.closeButton)     { dwStyle |= UInt32(WS_SYSMENU) }
        if style.contains(.minimizeButton)  { dwStyle |= UInt32(WS_MINIMIZEBOX) }
        if style.contains(.maximizeButton)  { dwStyle |= UInt32(WS_MAXIMIZEBOX) }
        if style.contains(.resizableBorder) { dwStyle |= UInt32(WS_THICKFRAME) }

        let dwStyleEx: DWORD = 0

        let hWnd = name.withCString(encodedAs: UTF16.self) { title in
            windowClass.withCString(encodedAs: UTF16.self) { className in
                CreateWindowExW(dwStyleEx, className, title, dwStyle,
                CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,
                nil, nil, GetModuleHandleW(nil), nil)
            }
        }
        if hWnd == nil {  return nil }

        SetLastError(0)

        if SetWindowLongPtrW(hWnd, GWLP_USERDATA, unsafeBitCast(self as AnyObject, to: LONG_PTR.self)) == 0 {
            let err: DWORD = GetLastError()
            if err != 0 {
                Log.err("SetWindowLongPtr failed with error: \(win32ErrorString(err))")
                DestroyWindow(hWnd)
                SetLastError(err)
                return nil
            }
        }

        self.hWnd = hWnd

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
        
        var rc1: RECT = RECT()
        var rc2: RECT = RECT()
        GetClientRect(hWnd, &rc1)
        GetWindowRect(hWnd, &rc2)

        self.contentBounds = CGRect(x: Int(rc1.left),
                                    y: Int(rc1.top),
                                    width: Int(rc1.right - rc1.left),
                                    height: Int(rc1.bottom - rc1.top))
        self.windowFrame = CGRect(x: Int(rc2.left),
                                  y: Int(rc2.top),
                                  width: Int(rc2.right - rc2.left),
                                  height: Int(rc2.bottom - rc2.top))
        self.contentScaleFactor = dpiScaleForWindow(hWnd!)
        
        SetWindowPos(hWnd, HWND_TOP, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED))
        SetTimer(hWnd, updateKeyboardMouseTimerId, updateKeyboardMouseTimeInterval, nil);
        postWindowEvent(type: .created)

        return hWnd
    }

    func destroy() {
        if let hWnd = self.hWnd {
            if let dt = self.dropTarget {
                RevokeDragDrop(hWnd)
                let refCount = dt.withMemoryRebound(to: IDropTarget.self, capacity: 1) {
                    // $0.pointee.lpVtbl.pointee.Release($0)
                    dt.pointee.vtbl.Release($0)
                }
                if refCount > 0 {
                    Log.warn("DropTarget for Window:\(self.name) in use! refCount:\(refCount)")
                }
            }
            self.dropTarget = nil

            KillTimer(hWnd, updateKeyboardMouseTimerId);

            // set GWLP_USERDATA to 0, to forwarding messages to DefWindowProc.
            SetWindowLongPtrW(hWnd, GWLP_USERDATA, 0);
            SetWindowPos(hWnd, HWND_TOP, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED));

            // Post WM_CLOSE to destroy window from DefWindowProc().
            PostMessageW(hWnd, UINT(WM_CLOSE), 0, 0);

            Log.verbose("Window: \(self.name) destroyed")

            // post event!

        }
        self.hWnd = nil
    }

    public var title: String {
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

    public func showMouse(_ show: Bool, forDeviceId deviceId: Int) {
        if let hWnd = self.hWnd, deviceId == 0 {
            let wParam = show ? WPARAM(1) : WPARAM(0)
            PostMessageW(hWnd, UINT(WM_DKWINDOW_SHOWCURSOR), wParam, 0)
        }
    }

    public func isMouseVisible(forDeviceId deviceId: Int) -> Bool {
        if deviceId == 0 {
            var info: CURSORINFO = CURSORINFO()
            if GetCursorInfo(&info) {
                return info.flags != 0;
            }
        }
        return false
    }

    public func holdMouse(_ hold: Bool, forDeviceId deviceId: Int) {
        if deviceId == 0 {
            self.holdMouse = hold

            self.mousePosition = self.mousePosition(forDeviceId: 0);
            self.holdingMousePosition = mousePosition;

            PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
        }
    }

    public func isMouseHeld(forDeviceId deviceId: Int) -> Bool {
        if deviceId == 0 {
            return self.holdMouse
        }
        return false
    }

    public func mousePosition(forDeviceId deviceId: Int) -> CGPoint {
        if let hWnd = self.hWnd, deviceId == 0 {
            var pt: POINT = POINT()
            GetCursorPos(&pt)
            ScreenToClient(hWnd, &pt)
            return CGPoint(x: Int(pt.x), y: Int(pt.y))
        }
        return CGPoint(x: -1, y: -1)
    }

    public func setMousePosition(_ pos: CGPoint, forDeviceId deviceId: Int) {
        if let hWnd = self.hWnd, deviceId == 0 {
            var pt: POINT = POINT()
            pt.x = LONG(pos.x)
            pt.y = LONG(pos.y)
            ClientToScreen(hWnd, &pt)
            SetCursorPos(pt.x, pt.y)

            self.mousePosition = pos
        }
    }

    public func enableTextInput(_ enable: Bool, forDeviceId deviceId: Int) {
        if deviceId == 0 {
            self.textCompositionMode = enable
        }
    }

    public func isTextInputEnabled(forDeviceId deviceId: Int) -> Bool {
        if deviceId == 0 {
            return self.textCompositionMode
        }
        return false
    }

    private func synchronizeMouse() {
        guard !self.activated else { return }
        // check mouse has gone out of window region.
        if let hWnd = self.hWnd, GetCapture() != hWnd {
            var pt: POINT = POINT()
            GetCursorPos(&pt)
            ScreenToClient(hWnd, &pt)

            var rc: RECT = RECT()
            GetClientRect(hWnd, &rc)
            if pt.x < rc.left || pt.x > rc.right || pt.y > rc.bottom || pt.y < rc.top {

                let MAKELPARAM = {(a:Int32, b:Int32) -> LPARAM in
                    LPARAM(a & 0xffff) | (LPARAM(b & 0xffff) << 16)
                }
                PostMessageW(hWnd, UINT(WM_MOUSEMOVE), 0, MAKELPARAM(pt.x, pt.y))
            }
        }
    }

    private func resetMouse() {
        if let hWnd = self.hWnd {
            var pt: POINT = POINT()
            GetCursorPos(&pt)
            ScreenToClient(hWnd, &pt)
            mousePosition = CGPoint(x: Int(pt.x), y: Int(pt.y))
        }
    }

    private func synchronizeKeyStates() {
        guard !self.activated else { return }

        var keyStates: [UInt8] = [UInt8](repeating: 0, count: 256)
        GetKeyboardState(&keyStates)

        for key in 0..<256 {
            if key == VK_CAPITAL { continue }

            let virtualKey: VirtualKey = .fromWin32VK(key)
            if virtualKey == .none { continue }

            if keyStates[key] & 0x80 != self.keyboardStates[key] & 0x80 {
                if keyStates[key] & 0x80 != 0 {
                    // post keydown event
                    postKeyboardEvent(KeyboardEvent(type: .keyDown,
                                                    window: self,
                                                    deviceId: 0,
                                                    key: virtualKey,
                                                    text: ""))
                } else {
                    // post keyup event
                    postKeyboardEvent(KeyboardEvent(type: .keyUp,
                                                    window: self,
                                                    deviceId: 0,
                                                    key: virtualKey,
                                                    text: ""))
                }
            }
        } 

        let capslock = Int(VK_CAPITAL)
        if keyStates[capslock] & 0x01 != self.keyboardStates[capslock] & 0x01 {
            if keyStates[capslock] & 0x01 != 0 {
                // capslock on
                postKeyboardEvent(KeyboardEvent(type: .keyDown,
                                                window: self,
                                                deviceId: 0,
                                                key: .capslock,
                                                text: ""))
            } else {
                // capslock off
                postKeyboardEvent(KeyboardEvent(type: .keyUp,
                                                window: self,
                                                deviceId: 0,
                                                key: .capslock,
                                                text: ""))
            }
        }
        self.keyboardStates = keyStates
    }

    private func resetKeyStates() {
        for key in 0..<256 {
            if key == VK_CAPITAL { continue }

            let virtualKey: VirtualKey = .fromWin32VK(key)
            if virtualKey == .none { continue }

            if keyboardStates[key] & 0x80 != 0 {
                postKeyboardEvent(KeyboardEvent(type: .keyUp,
                                                window: self,
                                                deviceId: 0,
                                                key: virtualKey,
                                                text: ""))
            }
        }

        let capslock = Int(VK_CAPITAL)
        if keyboardStates[capslock] & 0x01 != 0 {
            postKeyboardEvent(KeyboardEvent(type: .keyUp,
                                            window: self,
                                            deviceId: 0,
                                            key: .capslock,
                                            text: ""))
        }

        GetKeyboardState(&keyboardStates) // to empty keyboard queue
        self.keyboardStates = [UInt8](repeating: 0, count: 256)
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
        self.eventObservers.forEach { _, handlers in
            if let handler = handlers.windowEventHandler { handler(event) }
        }
    }

    func postKeyboardEvent(_ event: KeyboardEvent) {
        assert(event.window === self)
        self.eventObservers.forEach { _, handlers in
            if let handler = handlers.keyboardEventHandler { handler(event) }
        }
    }

    func postMouseEvent(_ event: MouseEvent) {        
        assert(event.window === self)
        self.eventObservers.forEach { _, handlers in
            if let handler = handlers.mouseEventHandler { handler(event) }
        }
    }

    private struct EventHandlers {
        var windowEventHandler: ((_: WindowEvent)->Void)?
        var mouseEventHandler: ((_: MouseEvent)->Void)?
        var keyboardEventHandler: ((_: KeyboardEvent)->Void)?
    }
    private var eventObservers: [ObjectIdentifier: EventHandlers] = [:]

    public func addEventObserver(_ key: AnyObject, handler: @escaping (_: WindowEvent)->Void) {
        let key = ObjectIdentifier(key)
        if var handlers = self.eventObservers[key] {
            handlers.windowEventHandler = handler
            self.eventObservers[key] = handlers
        } else {
            self.eventObservers[key] = EventHandlers(windowEventHandler: handler)
        }
    }
    public func addEventObserver(_ key: AnyObject, handler: @escaping (_: MouseEvent)->Void) {
        let key = ObjectIdentifier(key)
        if var handlers = self.eventObservers[key] {
            handlers.mouseEventHandler = handler
            self.eventObservers[key] = handlers
        } else {
            self.eventObservers[key] = EventHandlers(mouseEventHandler: handler)
        }
    }
    public func addEventObserver(_ key: AnyObject, handler: @escaping (_: KeyboardEvent)->Void) {
        let key = ObjectIdentifier(key)
        if var handlers = self.eventObservers[key] {
            handlers.keyboardEventHandler = handler
            self.eventObservers[key] = handlers
        } else {
            self.eventObservers[key] = EventHandlers(keyboardEventHandler: handler)
        }
    }
    public func removeEventObserver(_ key: AnyObject) {
        let key = ObjectIdentifier(key)
        self.eventObservers[key] = nil
    }

    private static func windowProc(_ hWnd: HWND?, _ uMsg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        let userData = GetWindowLongPtrW(hWnd, GWLP_USERDATA)
        let obj: AnyObject? = unsafeBitCast(userData, to: AnyObject.self)

        let MAKEPOINTS = { (lParam: LPARAM) -> POINTS in
            var pt: POINTS = POINTS()
            withUnsafeBytes(of: lParam) {
                let pts = $0.bindMemory(to: POINTS.self)
                pt = pts[0]
            }
            return pt
        }

        if let window = obj as? Win32Window, window.hWnd == hWnd {
            switch (uMsg){
            case UINT(WM_ACTIVATE):
                if wParam == WA_ACTIVE || wParam == WA_CLICKACTIVE {
                    if window.activated == false {
                        numActiveWindows += 1
                        window.activated = true
                        window.postWindowEvent(type: .activated)
                        window.resetKeyStates()
                        window.resetMouse()
                        Log.debug("DKGame.numActiveWindows: \(numActiveWindows)")
                    }
                } else {
                    if window.activated {
                        numActiveWindows -= 1
                        window.resetKeyStates()
                        window.resetMouse()
                        window.activated = false
                        window.postWindowEvent(type: .inactivated)                            
                        Log.debug("DKGame.numActiveWindows: \(numActiveWindows)")
                    }
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
            case UINT(WM_ENTERSIZEMOVE):
                window.resizing = true;
                return 0
            case UINT(WM_EXITSIZEMOVE):
                window.resizing = false;
                var rcClient: RECT = RECT(), rcWindow: RECT = RECT()
                GetClientRect(hWnd, &rcClient)
                GetWindowRect(hWnd, &rcWindow)
                var resized = false
                var moved = false
                if (rcClient.right - rcClient.left) != LONG(window.contentBounds.width) ||
                    (rcClient.bottom - rcClient.top) != LONG(window.contentBounds.height) {
                    resized = true
                }
                if rcWindow.left != LONG(window.windowFrame.origin.x) || rcWindow.top != LONG(window.windowFrame.origin.y) {
                    moved = true
                }
                if resized || moved {
                    window.windowFrame = CGRect(x: Int(rcWindow.left),
                                                y: Int(rcWindow.top),
                                                width: Int(rcWindow.right - rcWindow.left),
                                                height: Int(rcWindow.bottom - rcWindow.top))
                    window.contentBounds = CGRect(x: Int(rcClient.left),
                                                  y: Int(rcClient.top),
                                                  width: Int(rcClient.right - rcClient.left),
                                                  height: Int(rcClient.bottom - rcClient.top))

                    if resized {
                        window.postWindowEvent(type: .resized)
                    }
                    if moved {
                        window.postWindowEvent(type: .moved)
                    }
                }
                return 0
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
                        let w: Int = Int(lParam & 0xffff)
                        let h: Int = Int((lParam >> 16) & 0xffff)
                        let size: CGSize = CGSize(width: w, height: h)
                        window.contentBounds.size = size

                        var rc: RECT = RECT()
                        GetWindowRect(hWnd, &rc)
                        window.windowFrame = CGRect(x: Int(rc.left),
                                                    y: Int(rc.top),
                                                    width: Int(rc.right - rc.left),
                                                    height: Int(rc.bottom - rc.top))
                        window.postWindowEvent(type: .resized)
                    }
                }
                return 0
            case UINT(WM_MOVE):
                if window.resizing == false {
                    let x: Int = Int(lParam & 0xffff)         // horizontal position 
                    let y: Int = Int((lParam >> 16) & 0xffff) // vertical position 

                    window.windowFrame.origin = CGPoint(x: x, y: y);
                    window.postWindowEvent(type: .moved)
                }
                return 0
            case UINT(WM_DPICHANGED):
                // Note: xDPI, yDPI are identical for Windows apps
                let xDPI: Int = Int(wParam & 0xffff)
                let yDPI: Int = Int((wParam >> 16) & 0xffff)

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
                    window.postWindowEvent(type: .resized)
                }
                return 0    
            case UINT(WM_GETMINMAXINFO):
                let style: DWORD = DWORD(GetWindowLongW(hWnd, GWL_STYLE))
                let styleEx: DWORD = DWORD(GetWindowLongW(hWnd, GWL_EXSTYLE))
                let menu: Bool = GetMenu(hWnd) != nil

                var minSize: CGSize = CGSize(width: 1, height: 1)
                if let size = window.delegate?.minimumContentSize(window: window) {
                    minSize.width = size.width
                    minSize.height = size.height
                }
                var rc = RECT(left: 0,
                                top: 0,
                                right: LONG(max(minSize.width, 1)),
                                bottom: LONG(max(minSize.height, 1)))
                if AdjustWindowRectEx(&rc, style, menu, styleEx) {
                    let tmp: UnsafeMutablePointer<MINMAXINFO> = UnsafeMutablePointer<MINMAXINFO>(bitPattern: UInt(lParam))!
                    tmp.pointee.ptMinTrackSize.x = rc.right - rc.left
                    tmp.pointee.ptMinTrackSize.y = rc.bottom - rc.top
                }
                if let maxSize = window.delegate?.maximumContentSize(window: window) {
                    rc = RECT(left: 0,
                                top: 0,
                                right: LONG(max(maxSize.width, 1)),
                                bottom: LONG(max(maxSize.height, 1)))
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
                    return 0;
                }
                break
            case UINT(WM_MOUSEMOVE):
                if window.activated {
                    let pt = MAKEPOINTS(lParam)
                    if pt.x != LONG(window.mousePosition.x) || pt.y != LONG(window.mousePosition.y) {
                        let delta: CGPoint = CGPoint(x: CGFloat(pt.x) - window.mousePosition.x,
                                                        y: CGFloat(pt.y) - window.mousePosition.y)

                        var postEvent = true
                        if window.holdMouse {
                            if pt.x == LONG(window.holdingMousePosition.x) &&
                            pt.y == LONG(window.holdingMousePosition.y) {
                                postEvent = false
                            } else {
                                window.setMousePosition(window.mousePosition, forDeviceId: 0)
                                // In Windows8 (or later) with scaled-DPI mode, setting mouse position generate inaccurate result.
                                // We need to keep new position in hold-mouse state. (non-movable mouse)
                                window.holdingMousePosition = window.mousePosition(forDeviceId: 0);
                            }
                        } else {
                            window.mousePosition = CGPoint(x: Int(pt.x), y: Int(pt.y))
                        }

                        if postEvent {
                            window.postMouseEvent(MouseEvent(type: .move,
                                                             window: window,
                                                             device: .genericMouse,
                                                             deviceId: 0,
                                                             buttonId: 0,
                                                             location: window.mousePosition,
                                                             delta: delta))
                        }
                    }
                }
                return 0
            case UINT(WM_LBUTTONDOWN):
                window.mouseButtonDownMask.insert(.button1)
                let pts = MAKEPOINTS(lParam)
                let pos: CGPoint = CGPoint(x: Int(pts.x), y: Int(pts.y))

                window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceId: 0,
                                                 buttonId: 0,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                return 0
            case UINT(WM_LBUTTONUP):
                window.mouseButtonDownMask.remove(.button1)
                let pts = MAKEPOINTS(lParam)
                let pos: CGPoint = CGPoint(x: Int(pts.x), y: Int(pts.y))

                window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceId: 0,
                                                 buttonId: 0,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                return 0
            case UINT(WM_RBUTTONDOWN):
                window.mouseButtonDownMask.insert(.button2)
                let pts = MAKEPOINTS(lParam)
                let pos: CGPoint = CGPoint(x: Int(pts.x), y: Int(pts.y))

                window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceId: 0,
                                                 buttonId: 1,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                return 0
            case UINT(WM_RBUTTONUP):
                window.mouseButtonDownMask.remove(.button2)
                let pts = MAKEPOINTS(lParam)
                let pos: CGPoint = CGPoint(x: Int(pts.x), y: Int(pts.y))

                window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceId: 0,
                                                 buttonId: 1,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                return 0
            case UINT(WM_MBUTTONDOWN):
                window.mouseButtonDownMask.insert(.button3)
                let pts = MAKEPOINTS(lParam)
                let pos: CGPoint = CGPoint(x: Int(pts.x), y: Int(pts.y))

                window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceId: 0,
                                                 buttonId: 2,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                return 0
            case UINT(WM_MBUTTONUP):
                window.mouseButtonDownMask.remove(.button3)
                let pts = MAKEPOINTS(lParam)
                let pos: CGPoint = CGPoint(x: Int(pts.x), y: Int(pts.y))

                window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceId: 0,
                                                 buttonId: 2,
                                                 location: pos))
                PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                return 0
            case UINT(WM_XBUTTONDOWN):
                let pts = MAKEPOINTS(lParam)
                let pos: CGPoint = CGPoint(x: Int(pts.x), y: Int(pts.y))

                let xButton = DWORD_PTR(wParam) >> 16 & 0xffff
                if xButton == XBUTTON1 {
                    window.mouseButtonDownMask.insert(.button4)

                    window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                     window: window,
                                                     device: .genericMouse,
                                                     deviceId: 0,
                                                     buttonId: 3,
                                                     location: pos))
                } else if xButton == XBUTTON2 {
                    window.mouseButtonDownMask.insert(.button5)

                    window.postMouseEvent(MouseEvent(type: .buttonDown,
                                                     window: window,
                                                     device: .genericMouse,
                                                     deviceId: 0,
                                                     buttonId: 4,
                                                     location: pos))
                }
                PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);                    
                return 1 // should return TRUE
            case UINT(WM_XBUTTONUP):
                let pts = MAKEPOINTS(lParam)
                let pos: CGPoint = CGPoint(x: Int(pts.x), y: Int(pts.y))

                let xButton = DWORD_PTR(wParam) >> 16 & 0xffff
                if xButton == XBUTTON1 {
                    window.mouseButtonDownMask.remove(.button4)

                    window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                     window: window,
                                                     device: .genericMouse,
                                                     deviceId: 0,
                                                     buttonId: 3,
                                                     location: pos))
                } else if xButton == XBUTTON2 {
                    window.mouseButtonDownMask.remove(.button5)

                    window.postMouseEvent(MouseEvent(type: .buttonUp,
                                                     window: window,
                                                     device: .genericMouse,
                                                     deviceId: 0,
                                                     buttonId: 4,
                                                     location: pos))
                }
                PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);                    
                return 1 // should return TRUE
            case UINT(WM_MOUSEWHEEL):
                var origin: POINT = POINT(x:0, y:0)
                ClientToScreen(hWnd, &origin)

                let pts = MAKEPOINTS(lParam)
                let pos: CGPoint = CGPoint(x: Int(pts.x), y: Int(pts.y))

                let deltaY: Int16 = Int16(bitPattern: UInt16(DWORD_PTR(wParam) >> 16 & 0xffff))

                window.postMouseEvent(MouseEvent(type: .wheel,
                                                 window: window,
                                                 device: .genericMouse,
                                                 deviceId: 0,
                                                 buttonId: 2,
                                                 location: pos,
                                                 delta: CGPoint(x: 0, y: Int(deltaY))))
                return 0
            case UINT(WM_CHAR):
                window.synchronizeKeyStates()
                if window.textCompositionMode {

                    var str: [WCHAR] = [WCHAR](repeating: 0, count: 2)
                    str[0] = WCHAR(wParam)

                    let inputText = String(decodingCString: str, as: UTF16.self)

                    window.postKeyboardEvent(KeyboardEvent(type: .textInput,
                                                           window: window,
                                                           deviceId: 0,
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
                    // composition finished.
                    // Result characters will be received via WM_CHAR,
                    // reset input-candidate characters here.
                    window.postKeyboardEvent(KeyboardEvent(type: .textComposition,
                                                           window: window,
                                                           deviceId: 0,
                                                           key: .none,
                                                           text: ""))  
                }
                if lParam & LPARAM(GCS_COMPSTR) != 0 {
                    // composition in progress.
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
                                                                       deviceId: 0,
                                                                       key: .none,
                                                                       text: compositionText))  

                            } else {    // composition character's length become 0. (erased)
                                window.postKeyboardEvent(KeyboardEvent(type: .textComposition,
                                                                       window: window,
                                                                       deviceId: 0,
                                                                       key: .none,
                                                                       text: ""))  
                            }
                        } else {        // not text-input mode.
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
            case UINT(WM_CLOSE):
                var close = true
                if let answer = window.delegate?.shouldClose(window: window) {
                    close = answer
                }
                if close {
                    window.destroy()
                }
                return 0
            case UINT(WM_COMMAND):
                break
            case UINT(WM_SYSCOMMAND):
                switch (wParam)
                {
                case WPARAM(SC_CONTEXTHELP), // help menu
                     WPARAM(SC_KEYMENU),     // alt-key
                     WPARAM(SC_HOTKEY):                  // hotkey
                    return 0
                default:
                    break
                }
            case UINT(WM_SYSKEYDOWN),
                 UINT(WM_SYSKEYUP):
                return 0    // block ALT-key
            case UINT(WM_KEYDOWN),
                 UINT(WM_KEYUP):
                return 0
            case UINT(WM_DKWINDOW_SHOWCURSOR):
                // If we need to control mouse position from other thread,
                // we should call AttachThreadInput() to synchronize threads.
                // but we are not going to control position, but control visibility
                // only, we can use window message.
                if wParam != 0 {
                    while ShowCursor(true) < 0 {}
                } else {
                    while ShowCursor(false) >= 0 {}
                }
                return 0;
            case UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE):
                if GetCapture() == hWnd {
                    if window.mouseButtonDownMask.rawValue == 0 && !window.holdMouse {
                        ReleaseCapture()
                    }
                } else {
                    if window.mouseButtonDownMask.rawValue != 0 && window.holdMouse {
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
#endif //if ENABLE_WIN32