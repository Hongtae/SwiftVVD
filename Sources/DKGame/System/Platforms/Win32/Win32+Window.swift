import WinSDK
import Foundation


// #define MAKELANGID(p, s)       ((((WORD  )(s)) << 10) | (WORD  )(p))

private func win32ErrorString(_ code: DWORD) -> String {

    var buffer: UnsafeMutablePointer<WCHAR>?

    let MAKELANGID = { (p: DWORD, s: DWORD) -> DWORD in
        return DWORD((s << 10) | p)
    }

    let numChars = withUnsafeMutablePointer(to: &buffer) {
        $0.withMemoryRebound(to: WCHAR.self, capacity: 1) {
            FormatMessageW(
                DWORD(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM),
                nil, code,
                MAKELANGID(DWORD(LANG_NEUTRAL), DWORD(SUBLANG_DEFAULT)),
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

private let IDC_ARROW: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!
private let IDI_APPLICATION: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!

private func windowProc(_ hWnd: HWND?, _ uMsg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {

    return DefWindowProcW(hWnd, uMsg, wParam, lParam)
}

private let windowClass = "_SwiftDKGame_WndClass"

private typealias WindowProtocol = Window

extension Win32 {
    public class Window : WindowProtocol {
        public private(set) var hWnd : HWND?
        private var autoResize: Bool = false
        private var contentRect: CGRect = .null
        private var windowRect: CGRect = .null
        private var contentScaleFactor: Float = 1.0

        private lazy var registeredWindowClass: ATOM? = {      
            let atom: ATOM? = windowClass.withCString(encodedAs: UTF16.self) {
                className in
                var wc = WNDCLASSEXW(
                    cbSize: UINT(MemoryLayout<WNDCLASSEXW>.size),
                    style: UINT(CS_OWNDC),
                    lpfnWndProc: windowProc,
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

            _ = self.registeredWindowClass    

            var dwStyle: DWORD = 0
            if style.contains(.title)           { dwStyle |= UInt32(WS_CAPTION) }
            if style.contains(.closeButton)     { dwStyle |= UInt32(WS_SYSMENU) }
            if style.contains(.minimizeButton)  { dwStyle |= UInt32(WS_MINIMIZEBOX) }
            if style.contains(.maximizeButton)  { dwStyle |= UInt32(WS_MAXIMIZEBOX) }
            if style.contains(.resizableBorder) { dwStyle |= UInt32(WS_THICKFRAME) }

            let dwStyleEx: DWORD = 0

            self.hWnd = name.withCString(encodedAs: UTF16.self) { title in
                windowClass.withCString(encodedAs: UTF16.self) { className in
                    CreateWindowExW(dwStyleEx, className, title, dwStyle,
                    CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,
                    nil, nil, GetModuleHandleW(nil), nil)
                }
            }
            if self.hWnd == nil {
                NSLog("CreateWindow failed.")
            } else {
            	SetLastError(0)

                if SetWindowLongPtrW(self.hWnd, GWLP_USERDATA, 
                    unsafeBitCast(self as AnyObject, to: LONG_PTR.self)) == 0 {
                    let err: DWORD = GetLastError()
                    if err != 0 {

                        NSLog("SetWindowLongPtr failed with error: \(win32ErrorString(err))")

                        DestroyWindow(self.hWnd)
                        self.hWnd = nil
                    }
                }
            }

            if let hWnd = self.hWnd {
                if style.contains(.acceptFileDrop) {
                    let result = DropTarget.makeMutablePointer().withMemoryRebound(to: IDropTarget.self, capacity:1) {
                        dropTarget in
                        RegisterDragDrop(hWnd, dropTarget)
                    }
                    if result != S_OK {
                        NSLog("ERROR!")
                    }
                }
                self.autoResize = style.contains(.autoResize)

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
                self.contentScaleFactor = dpiScaleForWindow(hWnd)
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
    }

}