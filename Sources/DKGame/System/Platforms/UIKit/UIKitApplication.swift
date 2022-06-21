//
//  File: UIKitApplication.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
import UIKit

class AppLoader: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?) -> Bool {
        let app = UIKitApplication.shared as! UIKitApplication
        Task { @MainActor in
            if app.initialized == false {
                await app.delegate?.initialize(application: app)
                app.initialized = true
            }
        }
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        let app = UIKitApplication.shared as! UIKitApplication
        Task { @MainActor in
            if app.initialized {
                await app.delegate?.finalize(application: app)
                app.initialized = false
            }
        }
    }
}

public class UIKitApplication: Application {
    public static var shared: Application? = nil

    var delegate: ApplicationDelegate?
    var initialized = false

    public func terminate(exitCode : Int) {
        Task { @MainActor in
            if self.initialized {
                await self.delegate?.finalize(application: self)
                self.initialized = false
            }

            DispatchQueue.main.async {
                exit(0)
            }
        }
    }

    public static func run(delegate: ApplicationDelegate?) -> Int {
        assert(Thread.isMainThread)

        let app = UIKitApplication()
        app.delegate = delegate
        self.shared = app

        UIApplicationMain(CommandLine.argc,
                          CommandLine.unsafeArgv,
                          nil,
                          NSStringFromClass(AppLoader.self))

        self.shared = nil
        return 0
    }
}

#endif //if ENABLE_UIKIT
