//
//  File: Win32Application.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_WIN32
import WinSDK
import Foundation

nonisolated(unsafe) private var keyboardHook: HHOOK? = nil
nonisolated(unsafe) var numActiveWindows: Int = 0
private let disableWindowKey: Bool = true

private func keyboardHookProc(_ nCode: Int32, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
    let hook = disableWindowKey && numActiveWindows > 0
    if nCode == HC_ACTION && hook {
        let pkbhs = UnsafeMutablePointer<KBDLLHOOKSTRUCT>(bitPattern: UInt(lParam))?.pointee
        if let code = pkbhs?.vkCode {
            if code == VK_LWIN || code == VK_RWIN {
                var keyStates: [UInt8] = [UInt8](repeating: 0, count: 256)
                if wParam == WM_KEYDOWN {
                    GetKeyboardState(&keyStates)
                    keyStates[Int(code)] = 0x80
                    SetKeyboardState(&keyStates)
                } else if wParam == WM_KEYUP {
                    GetKeyboardState(&keyStates)
                    keyStates[Int(code)] = 0x00
                    SetKeyboardState(&keyStates)
                }
                return 1
            }
        }
    }

    return CallNextHookEx(keyboardHook, nCode, wParam, lParam)
}

@discardableResult
private func processRunLoop() -> Int {
    var processed = 0
    while true {
        let next = RunLoop.main.limitDate(forMode: .default)
        let s = next?.timeIntervalSinceNow ?? 1.0
        if s > 0.0 {
            break
        }
        processed += 1
    }
    return processed
}

final class Win32Application: Application, @unchecked Sendable {

    let mainLoopMaximumInterval: Double = 0.01
    var running: Bool = false
    var threadId: DWORD = 0
    var exitCode: Int = 0

    nonisolated(unsafe) static var shared: Application? = nil

    private init() {
    }

    func terminate(exitCode: Int) {
        if self.running && self.threadId != 0 {
            self.exitCode = exitCode
            PostThreadMessageW(threadId, UINT(WM_QUIT), 0, 0)
        }
    }

    static func run(delegate: ApplicationDelegate?) -> Int{

        let app: Win32Application = Win32Application()
        self.shared = app
        app.running = true
        app.threadId = GetCurrentThreadId()

        if IsDebuggerPresent() == false {
            if keyboardHook != nil {
                Log.err("Keyboard hook state invalid. (already installed?)")
                UnhookWindowsHookEx(keyboardHook)
                keyboardHook = nil
            }

            let installHook = UserDefaults.standard.bool(forKey:"Win32.DisableWindowKey")

            if installHook {
                keyboardHook = SetWindowsHookExW(WH_KEYBOARD_LL, keyboardHookProc, GetModuleHandleW(nil), 0)
                if keyboardHook == nil {
                    Log.err("SetWindowsHookEx Failed.")
                }
            }
        }

        // Setup process DPI
        if SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) {
            Log.info("Windows DPI-Awareness: DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2")
        } else if SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE) {
            Log.info("Windows DPI-Awareness: DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE")
        } else {
            Log.warn("Windows DPI-Awareness not set, please check application manifest.")
        }

        delegate?.initialize(application: app)

        let timerProc: TIMERPROC = {
            (_: HWND?, elapse: UINT, timerId: UINT_PTR, _: DWORD) in
            processRunLoop()
        }
        let timerID = SetTimer(nil, 0, UINT(USER_TIMER_MINIMUM), timerProc)

        var msg = MSG()
        mainLoop: while true {
            while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                if msg.message == UINT(WM_QUIT) {
                    break mainLoop
                }
                TranslateMessage(&msg)
                DispatchMessageW(&msg)
            }
            processRunLoop()
            WaitMessage()
        }

        delegate?.finalize(application: app)
        appFinalize()

        KillTimer(nil, timerID)

        if keyboardHook != nil {
            UnhookWindowsHookEx(keyboardHook)
            keyboardHook = nil
        }

        self.shared = nil
        app.threadId = 0
        app.running = false
        return app.exitCode
    }
}
#endif //if ENABLE_WIN32
