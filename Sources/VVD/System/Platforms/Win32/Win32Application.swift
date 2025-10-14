//
//  File: Win32Application.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_WIN32
import WinSDK
import Foundation

nonisolated(unsafe) private var keyboardHook: HHOOK? = nil
nonisolated(unsafe) private var getmsgHook: HHOOK? = nil
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

private func getmsgHookProc(_ nCode: Int32, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
    if nCode >= 0 {
        let msg = UnsafeMutablePointer<MSG>(bitPattern: UInt(lParam))?.pointee
        if let msg, msg.message == UINT(WM_QUIT) {
            Log.debug("WM_QUIT received with wParam: \(msg.wParam)")
            if let app = Win32Application.shared {
                app.terminate(exitCode: Int(msg.wParam))
            }
        }
    }
    return CallNextHookEx(getmsgHook, nCode, wParam, lParam)
}

final class Win32Application: Application, @unchecked Sendable {

    var activationPolicy: ActivationPolicy = .regular

    var threadId: DWORD = 0
    var requestExitWithCode: Int? = nil

    nonisolated(unsafe) static var shared: Win32Application? = nil

    private init() {}

    func terminate(exitCode: Int) {
        Task { @MainActor in
            self.requestExitWithCode = exitCode
        }
    }

    static var isActive: Bool {
        let foreground = GetForegroundWindow()
        var processID: DWORD = 0
        let threadID = GetWindowThreadProcessId(foreground, &processID)
        if threadID != 0 {
            return processID == GetCurrentProcessId()
        }
        return false
    }

    var isActive: Bool {
        Self.isActive
    }

    static func run(delegate: ApplicationDelegate?) -> Int{
        precondition(Thread.isMainThread, "\(#function) must be called on the main thread.")

        let app: Win32Application = Win32Application()
        let currentThreadId = GetCurrentThreadId()
        self.shared = app
        app.requestExitWithCode = nil
        app.threadId = currentThreadId

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
        let ignoreWMQuitMessage = UserDefaults.standard.bool(forKey: "Win32.ignoreWMQuitMessage")
        if ignoreWMQuitMessage == false {
            getmsgHook = SetWindowsHookExW(WH_GETMESSAGE, getmsgHookProc, GetModuleHandleW(nil), currentThreadId)
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

            // If any other events exist, let them dispatch.
            var msg = MSG()
            while (PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE | PM_NOYIELD))) {
                TranslateMessage(&msg)
                DispatchMessageW(&msg)
            }

            while true {
                let next = RunLoop.main.limitDate(forMode: .default)
                let s = next?.timeIntervalSinceNow ?? 1.0
                if s > 0.0 {
                    break
                }
            }
        }
        let timerID = SetTimer(nil, 0, UINT(USER_TIMER_MINIMUM), timerProc)

        var exitCode: Int = 0
        while RunLoop.main.run(mode: .default, before: Date.distantFuture) {
            if let ec = app.requestExitWithCode {
                exitCode = ec
                break
            }
        }

        delegate?.finalize(application: app)
        appFinalize()

        KillTimer(nil, timerID)

        if keyboardHook != nil {
            UnhookWindowsHookEx(keyboardHook)
            keyboardHook = nil
        }

        if getmsgHook != nil {
            UnhookWindowsHookEx(getmsgHook)
            getmsgHook = nil
        }

        assert(self.shared === app, "Shared application instance mismatch.")
        self.shared = nil
        app.threadId = 0
        return exitCode
    }
}
#endif //if ENABLE_WIN32
