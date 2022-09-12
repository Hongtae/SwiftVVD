//
//  File: AppKitApplication.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
import AppKit

public class AppKitApplication: Application {
    public static var shared: Application? = nil

    weak var delegate: ApplicationDelegate?

    var running = false
    var exitCode: Int = 0

    public func terminate(exitCode : Int) {
        if self.running {
            DispatchQueue.main.async {
                let app = NSApplication.shared
                NotificationCenter.default.post(name: NSApplication.willTerminateNotification,
                                                object: app)
                app.stop(nil)
                self.exitCode = exitCode
            }
        }
    }

    public static func run(delegate: ApplicationDelegate?) -> Int {
        assert(Thread.isMainThread)

        let app = AppKitApplication()
        app.delegate = delegate
        app.running = true

        self.shared = app

        Task { @MainActor in
            await delegate?.initialize(application: app)
            NotificationCenter.default.post(name: NSApplication.willFinishLaunchingNotification,
                                            object: NSApplication.shared)
        }

        NSApplication.shared.run()
        app.running = false

        Task { @MainActor in
            await delegate?.finalize(application: app)
        }

        self.shared = nil
        return app.exitCode
    }
}

#endif //if ENABLE_APPKIT
