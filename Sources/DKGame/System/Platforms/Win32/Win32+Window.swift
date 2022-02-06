import WinSDK

private let IDC_ARROW: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!
private let IDI_APPLICATION: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!

private func WindowProc(
  _ hWnd: HWND?, _ uMsg: UINT, _ wParam: WPARAM,
  _ lParam: LPARAM
) -> LRESULT {

    return DefWindowProcW(hWnd, uMsg, wParam, lParam)
}

private typealias WindowProtocol = Window

extension Win32 {
    public class Window : WindowProtocol {
        public private(set) var hWnd : HWND?
        private let windowClass = "_DKWindowClass"

        public init() {

            OleInitialize(nil)

            let name : Array<WCHAR> = windowClass.withCString(encodedAs: UTF16.self) { buffer in 
                Array<WCHAR>(unsafeUninitializedCapacity: windowClass.utf16.count + 1) {
                    wcscpy_s($0.baseAddress, $0.count, buffer)
                    $1 = $0.count
                }
            }

            var wc : WNDCLASSEXW = name.withUnsafeBufferPointer {
                WNDCLASSEXW(
                    cbSize: UINT(MemoryLayout<WNDCLASSEXW>.size),
                    style: UINT(CS_OWNDC),
                    lpfnWndProc: WindowProc,
                    cbClsExtra: 0,
                    cbWndExtra: 0,
                    hInstance: GetModuleHandleW(nil),
                    hIcon: LoadIconW(nil, IDI_APPLICATION),
                    hCursor: LoadCursorW(nil, IDC_ARROW),
                    hbrBackground: nil,
                    lpszMenuName: nil,
                    lpszClassName: $0.baseAddress!,
                    hIconSm: nil)
            }
        
            let atom: ATOM? = RegisterClassExW(&wc)
            if atom == nil { 
                print("RegisterClassExW failed.")
            } else {
                print("WindowClass: \"\(windowClass)\" registered!")
            }
        }

        public func show() {}
        public func hide() {}
    }

}