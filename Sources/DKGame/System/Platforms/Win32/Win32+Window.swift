import WinSDK
import Foundation

private let IDC_ARROW: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!
private let IDI_APPLICATION: UnsafePointer<WCHAR> = UnsafePointer<WCHAR>(bitPattern: 32512)!

private func windowProc(_ hWnd: HWND?, _ uMsg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {

    return DefWindowProcW(hWnd, uMsg, wParam, lParam)
}

private typealias WindowProtocol = Window

extension Win32 {
    public class Window : WindowProtocol {
        public private(set) var hWnd : HWND?

        public init() {

            OleInitialize(nil)

            let windowClass = "_SwiftDKGame_WndClass"
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


            if hWnd != nil {
                let result = DropTarget.makeMutablePointer().withMemoryRebound(to: IDropTarget.self, capacity:1) {
                    dropTarget in
                    RegisterDragDrop(hWnd!, dropTarget)
                }
                if result != S_OK {
                    NSLog("ERROR!")
                }
            }
        }

        public func show() {}
        public func hide() {}
    }

}