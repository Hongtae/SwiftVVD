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

    return CallNextHookEx(keyboardHook, nCode, wParam, lParam);
}

public class Win32Application : Application {

    let eventLoopMaximumInterval: Double = 0.0

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
            PostThreadMessageW(threadId, UINT(WM_NULL), 0, 0);
        }
    }

    static public func run(delegate: ApplicationDelegate?) -> Int{

        let app: Win32Application = Win32Application()
        self.shared = app
        app.running = true
        app.threadId = GetCurrentThreadId()

        if IsDebuggerPresent() == false {
            if keyboardHook != nil {
                Log.err("Keyboard hook state invalid. (already installed?)")
                UnhookWindowsHookEx(keyboardHook)
                keyboardHook = nil;
            }

            let installHook = UserDefaults.standard.bool(forKey:"Win32.DisableWindowKey")

            if installHook {
                keyboardHook = SetWindowsHookExW(WH_KEYBOARD_LL, keyboardHookProc, GetModuleHandleW(nil), 0)
                if keyboardHook == nil {
                    Log.err("SetWindowsHookEx Failed.");
                }
            }
        }

        // Setup thread DPI
        SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)   

        delegate?.initialize(application: app)

        var timerId: UINT_PTR = 0
        var msg: MSG = MSG()
        var next: Date? = nil

        PostMessageW(nil, UINT(WM_NULL), 0, 0); // To process first enqueued events.
        mainLoop: while true {
            while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                if msg.message == UINT(WM_QUIT) {
                    break mainLoop
                }
                TranslateMessage(&msg)
                DispatchMessageW(&msg)
            }

            if app.running {
                repeat {
                    next = RunLoop.main.limitDate(forMode: .default)
                } while (next?.timeIntervalSinceNow ?? 1.0) <= 0.0
                
                if let nextInterval = next?.timeIntervalSinceNow {
                    var elapse: UINT = 0
                    if nextInterval * 1000 > Double(USER_TIMER_MAXIMUM) {
                        elapse = UINT(USER_TIMER_MAXIMUM)
                    } else {
                        elapse = UINT(max(nextInterval, 0.0) * 1000)
                    }
                    timerId = SetTimer(nil, timerId, elapse, nil)
                } else {
                    if app.eventLoopMaximumInterval > 0.0 {
                        let elapse: UINT = UINT(app.eventLoopMaximumInterval * 1000)
                        timerId = SetTimer(nil, timerId, elapse, nil)
                    } else if timerId != 0 {
                        // kill timer and wait for next event.
                        KillTimer(nil, timerId)
                        timerId = 0
                    }
                }
                WaitMessage()
            } else {
                PostQuitMessage(0)
            }
        }

        if timerId != 0 {
            KillTimer(nil, timerId);
        }

        delegate?.finalize(application: app)

        repeat {
            next = RunLoop.main.limitDate(forMode: .default)
        } while (next?.timeIntervalSinceNow ?? 1.0) <= 0.0

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