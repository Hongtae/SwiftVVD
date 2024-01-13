//
//  File: Win32Application.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_WIN32
import WinSDK
import Foundation

private var keyboardHook: HHOOK? = nil
private let disableWindowKey: Bool = true
internal var numActiveWindows: Int = 0

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

private var mainLoopMaxInterval: UINT = 10
private var mainLoopTimerId: UINT_PTR = 0

private func processMainRunLoop(_ maxInterval: UINT = UINT(USER_TIMER_MAXIMUM)) -> UINT {
    while true {
        let next = RunLoop.main.limitDate(forMode: .default)
        let s = next?.timeIntervalSinceNow ?? 1.0
        if s > 0.0 {
            if s * 1000 > Double(USER_TIMER_MAXIMUM) {
                return min(UINT(USER_TIMER_MAXIMUM), maxInterval)
            }
            return min(UINT(s * 1000), maxInterval)
        }
    }
}

private let mainLoopTimerProc: TIMERPROC = { (_: HWND?, elapse: UINT, timerId: UINT_PTR, _: DWORD) in
    let next = processMainRunLoop(mainLoopMaxInterval)
    mainLoopTimerId = SetTimer(nil, timerId, next, mainLoopTimerProc)
}

public class Win32Application : Application {

    let mainLoopMaximumInterval: Double = 0.01

    var running: Bool = false
    var threadId: DWORD = 0
    var exitCode: Int = 0

    public static var shared: Application? = nil

    private init() {
    }

    public func terminate(exitCode: Int) {
        if self.running && threadId != 0 {
            self.running = false
            self.exitCode = exitCode
            PostThreadMessageW(threadId, UINT(WM_NULL), 0, 0)
        }
    }

    public static func run(delegate: ApplicationDelegate?) -> Int{

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

        mainLoopMaxInterval = UINT(app.mainLoopMaximumInterval * 1000)
        mainLoopTimerId = SetTimer(nil, 0, mainLoopMaxInterval, mainLoopTimerProc)

        var msg = MSG()
        mainLoop: while true {
            while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                if msg.message == UINT(WM_QUIT) {
                    break mainLoop
                }
                TranslateMessage(&msg)
                DispatchMessageW(&msg)
            }

            if app.running {
                mainLoopMaxInterval = UINT(app.mainLoopMaximumInterval * 1000)

                let next = processMainRunLoop(mainLoopMaxInterval)
                mainLoopTimerId = SetTimer(nil, mainLoopTimerId, next, mainLoopTimerProc)

                WaitMessage()
            } else {
                PostQuitMessage(0)
            }
        }

        if mainLoopTimerId != 0 {
            KillTimer(nil, mainLoopTimerId)
            mainLoopTimerId = 0
        }

        delegate?.finalize(application: app)

        appFinalize()

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
