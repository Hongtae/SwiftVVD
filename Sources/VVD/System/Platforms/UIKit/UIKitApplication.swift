//
//  File: UIKitApplication.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_UIKIT
import Foundation
import UIKit

nonisolated(unsafe) var activeWindowScenes: [UIWindowScene] = []
nonisolated(unsafe) var activeWindows: [UIWindow] = []

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let windowScene = scene as? UIWindowScene {
            activeWindowScenes.append(windowScene)
            if let window = activeWindows.first, window.windowScene == nil {
                window.windowScene = windowScene
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if scene is UIWindowScene {
            activeWindowScenes.removeAll { $0 === scene }
        }
    }
}

final class AppLoader: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?
    ) -> Bool {
        let app = UIKitApplication.shared as! UIKitApplication

        if app.initialized == false {
            app.delegate?.initialize(application: app)
            app.initialized = true
        }
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        let app = UIKitApplication.shared as! UIKitApplication

        if app.initialized {
            app.delegate?.finalize(application: app)
            app.initialized = false
        }
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {

        let config = UISceneConfiguration(name: nil,
                                          sessionRole: connectingSceneSession.role)
        config.sceneClass = UIWindowScene.self
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class UIKitApplication: Application, @unchecked Sendable {
    nonisolated(unsafe) public static var shared: Application? = nil

    var delegate: ApplicationDelegate?
    var initialized = false

    public func terminate(exitCode : Int) {
        if self.initialized {
            Task { @MainActor in
                self.delegate?.finalize(application: self)
                self.initialized = false
            }
        }

        DispatchQueue.main.async {
            exit(0)
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
