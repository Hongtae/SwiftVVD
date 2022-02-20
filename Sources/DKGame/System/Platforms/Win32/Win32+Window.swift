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

private func dpiScaleForWindow(_ hWnd: HWND) -> Float {
    let dpi = GetDpiForWindow(hWnd)
    if dpi != 0 {
        return Float(dpi) / 96.0
    }
    return 1.0
}

struct MouseButtonDownMask: OptionSet {
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

private let windowClass = "_SwiftDKGame_WndClass"

// TIMER ID
private let updateKeyboardMouseTimerId: UINT_PTR = 10
private let updateKeyboardMouseTimeInterval: UINT = 10
// WINDOW MESSAGE
private let WM_DKWINDOW_SHOWCURSOR = (WM_USER + 0x1175)
private let WM_DKWINDOW_UPDATEMOUSECAPTURE = (WM_USER + 0x1180)

private typealias WindowProtocol = Window

extension Win32 {
    public class Window : WindowProtocol {
        public private(set) var hWnd : HWND?
        public var name: String = ""
        public private(set) var style: WindowStyle
        public private(set) var contentRect: CGRect = .null
        public private(set) var windowRect: CGRect = .null
        public private(set) var contentScaleFactor: Float = 1.0

        public private(set) weak var delegate: WindowDelegate?

        public private(set) var resizing: Bool = false
        public private(set) var activated: Bool = false
        
        private var mousePosition: CGPoint = .zero
        private var holdingMousePosition: CGPoint = .zero
        private var mouseButtonDownMask: MouseButtonDownMask = []
        private var holdMouse: Bool = false
        private var textCompositionMode: Bool = false
        private var keyboardStates: [UInt8] = [UInt8](repeating: 0, count: 256)

        private var dropTarget: UnsafeMutablePointer<DropTarget>?

        private lazy var registeredWindowClass: ATOM? = {      
            let atom: ATOM? = windowClass.withCString(encodedAs: UTF16.self) {
                className in

                let IDC_ARROW: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!
                let IDI_APPLICATION: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!

                var wc = WNDCLASSEXW(
                    cbSize: UINT(MemoryLayout<WNDCLASSEXW>.size),
                    style: UINT(CS_OWNDC),
                    lpfnWndProc: { (hWnd, uMsg, wParam, lParam) -> LRESULT in Win32.Window.windowProc(hWnd, uMsg, wParam, lParam) },
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
                print("RegisterClassExW failed.")
            } else {
                print("WindowClass: \"\(windowClass)\" registered!")
            }
            return atom
        }()
        public init(name: String, style: WindowStyle, delegate: WindowDelegate?) {

            OleInitialize(nil)

            self.name = name
            self.style = style
            self.delegate = delegate    

            _ = self.registeredWindowClass

            if self.create() == nil {
                NSLog("CreateWindow failed: \(win32ErrorString(GetLastError()))")
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
                    NSLog("SetWindowLongPtr failed with error: \(win32ErrorString(err))")
                    DestroyWindow(hWnd)
                    SetLastError(err)
                    return nil
                }
            }

            self.hWnd = hWnd

            if style.contains(.acceptFileDrop) {
                let dropTargetPtr = DropTarget.makeMutablePointer()
                let result = dropTargetPtr.withMemoryRebound(to: IDropTarget.self, capacity:1) {
                    RegisterDragDrop(hWnd, $0)
                }
                if result == S_OK {
                    self.dropTarget = dropTargetPtr
                } else {
                    NSLog("RegisterDragDrop failed: \(win32ErrorString(DWORD(result)))")
                }
            }
            var rc1: RECT = RECT()
            var rc2: RECT = RECT()
            GetClientRect(hWnd, &rc1)
            GetWindowRect(hWnd, &rc2)

            self.contentRect = CGRect(x: Int(rc1.left),
                                        y: Int(rc1.top),
                                        width: Int(rc1.right - rc1.left),
                                        height: Int(rc1.bottom - rc1.top))
            self.windowRect = CGRect(x: Int(rc2.left),
                                        y: Int(rc2.top),
                                        width: Int(rc2.right - rc2.left),
                                        height: Int(rc2.bottom - rc2.top))
            self.contentScaleFactor = dpiScaleForWindow(hWnd!)
            
            SetTimer(hWnd, updateKeyboardMouseTimerId, updateKeyboardMouseTimeInterval, nil);
            return hWnd
        }

        func destroy() {
            if let hWnd = self.hWnd {
                if let dt = self.dropTarget {
                    RevokeDragDrop(hWnd)
                    var dropTarget: IDropTarget = dt.pointee.dropTarget
                    let refCount = dt.pointee.vtbl.Release(&dropTarget)
                    if refCount > 0 {
                        NSLog("Warning! DropTarget for Window:\(self.name) in use! refCount:\(refCount)")
                    }
                }
                self.dropTarget = nil

			    KillTimer(hWnd, updateKeyboardMouseTimerId);

			    // set GWLP_USERDATA to 0, to forwarding messages to DefWindowProc.
                SetWindowLongPtrW(hWnd, GWLP_USERDATA, 0);
                let HWND_TOP:HWND = HWND(bitPattern: 32512)!
                SetWindowPos(hWnd, HWND_TOP, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED));

			    // Post WM_CLOSE to destroy window from DefWindowProc().
    			PostMessageW(hWnd, UINT(WM_CLOSE), 0, 0);

			    NSLog("Window: \(self.name) destroyed")

                // post event!

            }
            self.hWnd = nil
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

        private func synchronizeKeyStates() {
            guard !self.activated else { return }

            var keyStates: [UInt8] = [UInt8](repeating: 0, count: 256)
    	    GetKeyboardState(&keyStates)

            for key in 0..<256 {
                if key == VK_CAPITAL { continue }

                if keyStates[key] & 0x80 != self.keyboardStates[key] & 0x80 {
                    if keyStates[key] & 0x80 != 0 {
                        // post keydown event

                        /* PostKeyboardEvent({ KeyboardEvent::KeyDown, 0,lKey, "" }); */
                    } else {
                        // post keyup event

                        /* PostKeyboardEvent({ KeyboardEvent::KeyUp, 0, lKey, "" }); */
                    }
                }
            } 

            let capsLock = Int(VK_CAPITAL)
            if keyStates[capsLock] & 0x01 != self.keyboardStates[capsLock] & 0x01 {
                if keyStates[capsLock] & 0x01 != 0 {
                    // capslock on

                    /* PostKeyboardEvent({ KeyboardEvent::KeyDown, 0, DKVirtualKey::Capslock, "" }); */ 
                } else {
                    // capslock off

                    /* PostKeyboardEvent({ KeyboardEvent::KeyUp, 0, DKVirtualKey::Capslock, "" }); */
                }
            }
            self.keyboardStates = keyStates
        }

        func postWindowEvent(_ event: WindowEvent) {

        }

        func postKeyboardEvent(_ event: KeyboardEvent) {

        }

        func postMouseEvent(_ event: MouseEvent) {

        }

        private static func windowProc(_ hWnd: HWND?, _ uMsg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
            let userData = GetWindowLongPtrW(hWnd, GWLP_USERDATA)
            let obj: AnyObject? = unsafeBitCast(userData, to: AnyObject.self)

            if let window = obj as? Win32.Window, window.hWnd == hWnd {
                switch (uMsg){
                case UINT(WM_ACTIVATE):
                    return 0
                case UINT(WM_SHOWWINDOW):
                    return 0
                case UINT(WM_ENTERSIZEMOVE):
                    window.resizing = true;
                    return 0
                case UINT(WM_EXITSIZEMOVE):
                    window.resizing = false;
                    return 0
    			case UINT(WM_SIZE):
                    return 0
                case UINT(WM_MOVE):
                    return 0
                case UINT(WM_DPICHANGED):
                    return 0    
                case UINT(WM_GETMINMAXINFO):
                    break
                case UINT(WM_TIMER):
                    break
                case UINT(WM_MOUSEMOVE):
                    return 0
                case UINT(WM_LBUTTONDOWN):
                    window.mouseButtonDownMask.insert(.button1)
                    withUnsafeBytes(of: lParam) {
                        let pts = $0.bindMemory(to: POINTS.self)
                        let pos: CGPoint = CGPoint(x: Int(pts[0].x), y: Int(pts[0].y))

                        NSLog("WM_LBUTTONDOWN: \(pos)")
                        /* PostMouseEvent({ MouseEvent::ButtonDown, MouseEvent::GenericMouse, 0, 0, pt, DKVector2(0,0), 0, 0 }); */
                    }
                    PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                    return 0
                case UINT(WM_LBUTTONUP):
                    window.mouseButtonDownMask.remove(.button1)
                    withUnsafeBytes(of: lParam) {
                        let pts = $0.bindMemory(to: POINTS.self)
                        let pos: CGPoint = CGPoint(x: Int(pts[0].x), y: Int(pts[0].y))

                        NSLog("WM_LBUTTONUP: \(pos)")
                        /* PostMouseEvent({ MouseEvent::ButtonUp, MouseEvent::GenericMouse, 0, 0, pt, DKVector2(0,0), 0, 0 }); */
                    }
                    PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                    return 0
                case UINT(WM_RBUTTONDOWN):
                    window.mouseButtonDownMask.insert(.button2)
                    withUnsafeBytes(of: lParam) {
                        let pts = $0.bindMemory(to: POINTS.self)
                        let pos: CGPoint = CGPoint(x: Int(pts[0].x), y: Int(pts[0].y))

                        NSLog("WM_RBUTTONDOWN: \(pos)")
                        /* PostMouseEvent({ MouseEvent::ButtonDown, MouseEvent::GenericMouse, 0, 1, pt, DKVector2(0, 0), 0, 0 }); */
                    }
                    PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                    return 0
                case UINT(WM_RBUTTONUP):
                    window.mouseButtonDownMask.remove(.button2)
                    withUnsafeBytes(of: lParam) {
                        let pts = $0.bindMemory(to: POINTS.self)
                        let pos: CGPoint = CGPoint(x: Int(pts[0].x), y: Int(pts[0].y))

                        NSLog("WM_RBUTTONUP: \(pos)")
                        /* PostMouseEvent({ MouseEvent::ButtonUp, MouseEvent::GenericMouse, 0, 1, pt, DKVector2(0, 0), 0,0 }); */
                    }
                    PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                    return 0
                case UINT(WM_MBUTTONDOWN):
                    window.mouseButtonDownMask.insert(.button3)
                    withUnsafeBytes(of: lParam) {
                        let pts = $0.bindMemory(to: POINTS.self)
                        let pos: CGPoint = CGPoint(x: Int(pts[0].x), y: Int(pts[0].y))

                        NSLog("WM_MBUTTONDOWN: \(pos)")
                        /* PostMouseEvent({ MouseEvent::ButtonDown, MouseEvent::GenericMouse, 0, 2, pt, DKVector2(0,0), 0, 0 }); */
                    }
                    PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                    return 0
                case UINT(WM_MBUTTONUP):
                    window.mouseButtonDownMask.remove(.button3)
                    withUnsafeBytes(of: lParam) {
                        let pts = $0.bindMemory(to: POINTS.self)
                        let pos: CGPoint = CGPoint(x: Int(pts[0].x), y: Int(pts[0].y))

                        NSLog("WM_MBUTTONUP: \(pos)")
                        /* PostMouseEvent({ MouseEvent::ButtonUp, MouseEvent::GenericMouse, 0, 2, pt, DKVector2(0, 0), 0,0 }); */
                    }
                    PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);
                    return 0
                case UINT(WM_XBUTTONDOWN):
                    withUnsafeBytes(of: lParam) {
                        let pts = $0.bindMemory(to: POINTS.self)
                        let pos: CGPoint = CGPoint(x: Int(pts[0].x), y: Int(pts[0].y))

                        let xButton = DWORD_PTR(wParam) >> 16 & 0xffff
                        if xButton == XBUTTON1 {
                            window.mouseButtonDownMask.insert(.button4)
                            NSLog("WM_XBUTTONDOWN (XBUTTON1): \(pos)")
                            /* PostMouseEvent({ MouseEvent::ButtonDown, MouseEvent::GenericMouse, 0, 3, pt, DKVector2(0, 0), 0,0 }); */
                        } else if xButton == XBUTTON2 {
                            window.mouseButtonDownMask.insert(.button5)
                            NSLog("WM_XBUTTONDOWN (XBUTTON2): \(pos)")
                            /* PostMouseEvent({ MouseEvent::ButtonDown, MouseEvent::GenericMouse, 0, 4, pt, DKVector2(0, 0), 0,0 }); */
                        }
                    }
                    PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);                    
                    return 1 // should return TRUE
                case UINT(WM_XBUTTONUP):
                    withUnsafeBytes(of: lParam) {
                        let pts = $0.bindMemory(to: POINTS.self)
                        let pos: CGPoint = CGPoint(x: Int(pts[0].x), y: Int(pts[0].y))

                        let xButton = DWORD_PTR(wParam) >> 16 & 0xffff
                        if xButton == XBUTTON1 {
                            window.mouseButtonDownMask.remove(.button4)
                            NSLog("WM_XBUTTONUP (XBUTTON1): \(pos)")
                            /* PostMouseEvent({ MouseEvent::ButtonUp, MouseEvent::GenericMouse, 0, 3, pt, DKVector2(0, 0), 0,0 }); */
                        } else if xButton == XBUTTON2 {
                            window.mouseButtonDownMask.remove(.button5)
                            NSLog("WM_XBUTTONUP (XBUTTON2): \(pos)")
                            /* PostMouseEvent({ MouseEvent::ButtonUp, MouseEvent::GenericMouse, 0, 4, pt, DKVector2(0, 0), 0,0 }); */
                        }
                    }
                    PostMessageW(hWnd, UINT(WM_DKWINDOW_UPDATEMOUSECAPTURE), 0, 0);                    
                    return 1 // should return TRUE
                case UINT(WM_MOUSEWHEEL):
                    var origin: POINT = POINT(x:0, y:0)
                    ClientToScreen(hWnd, &origin)
                    withUnsafeBytes(of: lParam) {
                        let pts = $0.bindMemory(to: POINTS.self)
                        let pos: CGPoint = CGPoint(x: Int(pts[0].x) - Int(origin.x), y: Int(pts[0].y) - Int(origin.y))
                        let delta: Int16 = Int16(bitPattern: UInt16(DWORD_PTR(wParam) >> 16 & 0xffff))

                        NSLog("WM_MOUSEWHEEL pos:\(pos), delta:\(delta)")
                        /* PostMouseEvent({ MouseEvent::Wheel, MouseEvent::GenericMouse, 0, 2, pt, delta, 0,0 }); */
                    }
                    return 0
                case UINT(WM_CHAR):
                    window.synchronizeKeyStates()
                    if window.textCompositionMode {

                        var str: [WCHAR] = [WCHAR](repeating: 0, count: 2)
                        str[0] = WCHAR(wParam)

                        let inputText = String(decodingCString: str, as: UTF16.self)
                        NSLog("WM_CHAR: \(inputText)")

                        /* PostKeyboardEvent({ KeyboardEvent::TextInput, 0, DKVirtualKey::None, text }); */
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

                        /* PostKeyboardEvent({ KeyboardEvent::TextComposition, 0, DKVirtualKey::None, "" }); */
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

                                    /* PostKeyboardEvent({ KeyboardEvent::TextComposition, 0, DKVirtualKey::None, compositionText }); */

                                    NSLog("WM_IME_COMPOSITION: \(compositionText)")

                                } else {    // composition character's length become 0. (erased)

                                    /* PostKeyboardEvent({ KeyboardEvent::TextComposition, 0, DKVirtualKey::None, "" }); */
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
					    /* PostWindowEvent({ WindowEvent::WindowUpdate, window->windowRect, window->contentRect, window->contentScaleFactor }); */
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
                    case WPARAM(SC_CONTEXTHELP): fallthrough // help menu
                    case WPARAM(SC_KEYMENU): fallthrough     // alt-key
                    case WPARAM(SC_HOTKEY):                  // hotkey
                        return 0
                    default:
                        break
                    }
                case UINT(WM_SYSKEYDOWN): fallthrough
                case UINT(WM_SYSKEYUP):
                    return 0    // block ALT-key
                case UINT(WM_KEYDOWN): fallthrough
                case UINT(WM_KEYUP):
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
}