import WinSDK
import Foundation

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
    public struct DropTarget {
        var vtbl: IDropTargetVtbl?

        func queryInterface(_ riid: GUID?, _ ppv:UnsafeMutableRawPointer) {
            NSLog("queryInterface")
        }
        func addRef() {
            NSLog("addRef")
        }
        func release() {
            NSLog("release")
        }
        func dragEnter(_ pdto: IDataObject?, _ grfKeyState: DWORD, _ ptl: POINTL, _ pdwEffect: DWORD?) {
            NSLog("dragEnter")
        }
        func dragOver(_ grfKeyState: DWORD, _ ptl: POINTL, _ pdwEffect: DWORD?) {
            NSLog("dragOver")
        }
        func dragLeave() {
            NSLog("dragLeave")
        }
        func drop(_ pdto: IDataObject?, _ grfKeyState: DWORD, _ ptl: POINTL, _ pdwEffect: DWORD?) {
            NSLog("drop")
        }
    }
    public class Window : WindowProtocol {
        public private(set) var hWnd : HWND?

        var dropTarget: DropTarget?

        public init() {

            OleInitialize(nil)

            let windowClass = "_SwiftDKGame_WndClass"
            let atom: ATOM? = windowClass.withCString(encodedAs: UTF16.self) {
                className in
                var wc = WNDCLASSEXW(
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
                    lpszClassName: className,
                    hIconSm: nil)

                return RegisterClassExW(&wc)
            }

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