import WinSDK

private func WindowProc(
  _ hWnd: HWND?, _ uMsg: UINT, _ wParam: WPARAM,
  _ lParam: LPARAM
) -> LRESULT {

    return DefWindowProcW(hWnd, uMsg, wParam, lParam)
}

struct Win32 {
    class Window {
        func Create() {

            OleInitialize(nil)

            let wcName = "DKWindowClass"
            let name : Array<WCHAR> = wcName.withCString(encodedAs: UTF16.self) { buffer in 
                Array<WCHAR>(unsafeUninitializedCapacity: wcName.utf16.count + 1) {
                    wcscpy_s($0.baseAddress, $0.count, buffer)
                    $1 = $0.count
                }
            }

            let IDC_ARROW: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!
            let IDI_APPLICATION: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!

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
                print("DKWondowClass registered!")
            }

            print("Create DK-Window!")
        }
    }
}
