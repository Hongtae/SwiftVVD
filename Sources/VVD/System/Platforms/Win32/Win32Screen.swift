//
//  File: Win32Screen.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_WIN32
import Foundation
import WinSDK

struct Win32Screen: Screen {
    let id: ScreenID
    let monitor: HMONITOR
    private let info: MONITORINFO

    var frame: CGRect {
        Self.rect(info.rcMonitor)
    }

    var visibleFrame: CGRect {
        Self.rect(info.rcWork)
    }

    var safeAreaInsets: ScreenInsets {
        .zero
    }

    var scaleFactor: CGFloat {
        Self.scaleFactor(for: monitor)
    }

    var displayModeResolution: CGSize {
        frame.size
    }

    var isPrimary: Bool {
        info.dwFlags != 0
    }

    init?(_ monitor: HMONITOR?) {
        guard let monitor else {
            return nil
        }

        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        guard GetMonitorInfoW(monitor, &info) else {
            return nil
        }

        self.id = ScreenID(rawValue: UInt64(UInt(bitPattern: monitor)))
        self.monitor = monitor
        self.info = info
    }

    static func allScreens() -> [Win32Screen] {
        var screens: [Win32Screen] = []
        withUnsafeMutablePointer(to: &screens) { pointer in
            let context = LPARAM(UInt(bitPattern: pointer))
            EnumDisplayMonitors(nil, nil, { monitor, _, _, context in
                guard let screen = Win32Screen(monitor),
                      let screens = UnsafeMutablePointer<[Win32Screen]>(bitPattern: UInt(context)) else {
                    return true
                }
                screens.pointee.append(screen)
                return true
            }, context)
        }
        return screens
    }

    private static func rect(_ rect: RECT) -> CGRect {
        CGRect(x: Int(rect.left),
               y: Int(rect.top),
               width: Int(rect.right - rect.left),
               height: Int(rect.bottom - rect.top))
    }

    private static func scaleFactor(for monitor: HMONITOR) -> CGFloat {
        var xDPI: UINT = 0
        var yDPI: UINT = 0
        if GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &xDPI, &yDPI) == S_OK {
            let dpi = max(xDPI, yDPI)
            if dpi > 0 {
                return CGFloat(dpi) / 96.0
            }
        }
        return 1.0
    }
}

#endif //if ENABLE_WIN32
