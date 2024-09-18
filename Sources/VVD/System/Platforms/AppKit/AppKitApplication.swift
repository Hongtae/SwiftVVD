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

                let event = NSEvent.otherEvent(with: .applicationDefined,
                                               location: .zero,
                                               modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: 0,
                                               context: nil,
                                               subtype: 0, data1: 0, data2: 0)
                app.postEvent(event!, atStart:false)
            }
        }
    }

    public static func run(delegate: ApplicationDelegate?) -> Int {
        assert(Thread.isMainThread)

        let observers = [
            NotificationCenter.default
                .addObserver(forName: NSApplication.willFinishLaunchingNotification,
                             object: nil,
                             queue: nil) { notification in
                                 Log.debug("Notification: \(notification)")
                             },
            NotificationCenter.default
                .addObserver(forName: NSApplication.willTerminateNotification,
                             object: nil,
                             queue: nil) { notification in
                                 Log.debug("Notification: \(notification)")
                             }
        ]

        let app = AppKitApplication()
        app.delegate = delegate
        app.running = true

        self.shared = app

        delegate?.initialize(application: app)

        NSApplication.shared.run()
        app.running = false

        delegate?.finalize(application: app)

        observers.forEach { NotificationCenter.default.removeObserver($0) }

        self.shared = nil
        return app.exitCode
    }
}

#endif //if ENABLE_APPKIT
