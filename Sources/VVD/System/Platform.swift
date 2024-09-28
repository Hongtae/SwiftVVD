//
//  File: Platform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVDHelper

public protocol PlatformFactory {
    func sharedApplication() -> Application?
    @MainActor
    func runApplication(delegate: ApplicationDelegate?) -> Int
    @MainActor
    func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window?
}

let numberOfThreadsToWaitBeforeExiting = Atomic<Int>(0)

func appFinalize() {
    var timer = TickCounter.now
    while true {
        let next = RunLoop.main.limitDate(forMode: .default)
        if let next = next, next.timeIntervalSinceNow <= 0.0 {
            continue
        }

        let numThreads = numberOfThreadsToWaitBeforeExiting.load(ordering: .sequentiallyConsistent)
        if numThreads > 0 {
            if timer.elapsed > 1.5 {
                Log.info("Waiting for system service threads to finish. (\(numThreads))")
                timer.reset()
            }
            Platform.threadYield()
            continue
        }
        break
    }
}

public class Platform {
    public static let headlessMode: Bool = {
        CommandLine.arguments.contains { $0.lowercased() == "--headless" }
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
    @MainActor
    public class func runApplication(delegate: ApplicationDelegate?) -> Int {
        factory.runApplication(delegate: delegate)
    }
    public class func sharedApplication() -> Application? {
        factory.sharedApplication()
    }
}

extension Platform {
    public static func threadSleep(_ d: Double) {
        VVDThreadSleep(d)
    }

    public static func threadYield() {
        VVDThreadYield()
    }

    public static func currentThreadID() -> UInt {
        return VVDThreadCurrentId()
    }

    public static func tickFrequency() -> UInt64 {
        return VVDTimerSystemTickFrequency()
    }

    public static func tick() -> UInt64 {
        return VVDTimerSystemTick()
    }
}
