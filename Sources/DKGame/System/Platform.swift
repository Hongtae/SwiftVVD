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

    public class var factory: PlatformFactory {
#if ENABLE_APPKIT
        PlatformFactoryAppKit()
#elseif ENABLE_UIKIT
        PlatformFactoryUIKit()
#elseif ENABLE_WIN32
        PlatformFactoryWin32()
#endif
    }

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
