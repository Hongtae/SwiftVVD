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
    func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) -> Window?
}

typealias UUID = Foundation.UUID
let detachedServiceTasks = Mutex<[UUID:String]>([:])

func appFinalize() {
    let timeout = DispatchTimeInterval.milliseconds(2500)
    var timestamp = DispatchTime.now()

    while true {
        let next = RunLoop.main.limitDate(forMode: .default)
        if let next = next, next.timeIntervalSinceNow <= 0.0 {
            continue
        }

        let tasks: [UUID:String] = detachedServiceTasks.withLock { $0 }
        if tasks.isEmpty == false {
            if DispatchTime.now() > timestamp + timeout {
                Log.info("Waiting for system service threads to finish. (\(tasks.count))")
                tasks.values.forEach { task in
                    Log.debug(" -- Task: \(task)")
                }
                timestamp = DispatchTime.now()
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
    public class func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) -> Window? {
        factory.makeWindow(name: name, style: style, delegate: delegate, data: data)
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
    public typealias ThreadID = UInt

    public static func threadSleep(_ d: Double) {
        VVDThreadSleep(d)
    }

    public static func threadYield() {
        VVDThreadYield()
    }

    public static func currentThreadID() -> ThreadID {
        return VVDThreadCurrentId()
    }
}

extension DispatchQueue {
    private static let _mainKey: DispatchSpecificKey<()> = {
        let key = DispatchSpecificKey<()>()
        DispatchQueue.main.setSpecific(key: key, value: ())
        return key
    }()

    public static var isMain: Bool {
        return DispatchQueue.getSpecific(key: _mainKey) != nil
    }
}

public func isMainQueue() -> Bool {
    DispatchQueue.isMain
}

public func isMainThreadOrQueue() -> Bool {
    Thread.isMainThread || DispatchQueue.isMain
}

public func runOnMainQueueSync<T>(_ block: @escaping @MainActor () -> T) -> T where T: Sendable {
    if DispatchQueue.isMain {
        return MainActor.assumeIsolated {
            block()
        }
    } else {
        return DispatchQueue.main.sync {
            block()
        }
    }
}
