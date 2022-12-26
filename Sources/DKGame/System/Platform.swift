//
//  File: Platform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol PlatformFactory {
    func sharedApplication() -> Application? 
    func runApplication(delegate: ApplicationDelegate?) -> Int
    @MainActor
    func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window?
}

var numberOfThreadsToWaitBeforeExiting = AtomicNumber64(0)

func runServiceThread(_ block: @escaping () -> Void) {
    Thread.detachNewThread {
        numberOfThreadsToWaitBeforeExiting.increment()
        block()
        numberOfThreadsToWaitBeforeExiting.decrement()
    }
}

func appFinalize() {
    var timer = TickCounter()
    while true {
        let next = RunLoop.main.limitDate(forMode: .default)
        if let next = next, next.timeIntervalSinceNow <= 0.0 {
            continue
        }

        let numThreads = numberOfThreadsToWaitBeforeExiting.load()
        if numThreads > 0 {
            if timer.elapsed > 1.5 {
                Log.info("Waiting for system service threads to finish. (\(numThreads))")
                timer.reset()
            }
            threadYield()
            continue
        }
        break
    }
}

public class Platform {
    public static var headlessMode: Bool = {
        let key = "DKGAME_HEADLESS"
        let value = ProcessInfo.processInfo.environment[key] ?? "0"
        if let v = Int(value), v != 0 {
            Log.info("HEADLESS-MODE: (\(key)=\(value))")
            return true 
        }
        return false
    }()

    public class var factory: PlatformFactory {
        if headlessMode {
            return PlatformFactoryHeadless()
        }

#if ENABLE_APPKIT
        return PlatformFactoryAppKit()
#elseif ENABLE_UIKIT
        return PlatformFactoryUIKit()
#elseif ENABLE_WIN32
        return PlatformFactoryWin32()
#elseif ENABLE_WAYLAND
        return PlatformFactoryWayland()
#else
#warning("Unknown platform, headless mode will be used")
        return PlatformFactoryHeadless()
#endif
    }

    @MainActor
    public class func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window? {
        factory.makeWindow(name: name, style: style, delegate: delegate)
    }
    public class func runApplication(delegate: ApplicationDelegate?) -> Int {
        factory.runApplication(delegate: delegate)
    }
    public class func sharedApplication() -> Application? {
        factory.sharedApplication()
    }
}
