//
//  File: App.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import DKGame
import Foundation

public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Self.Body { get }

    init()
}

let DKGUIAppWindowClosedNotification = NSNotification.Name("DKGUIAppWindowClosedNotification")

class AppMain<A>: ApplicationDelegate where A: App {
    let app: A
    var scene: any SceneProxy
    var observer: NSObjectProtocol?
    var terminateAfterLastWindowClosed = true

    func initialize(application: Application) {
        let windows = self.scene.windows
        Task { @MainActor in
            for windowProxy in windows {
                if let window = windowProxy.makeWindow() {
                    window.activate()
                    break
                }
            }
        }
        self.observer = NotificationCenter.default.addObserver(forName: DKGUIAppWindowClosedNotification,
                                                               object: nil,
                                                               queue: nil) { _ in
            let activeWindows: [Window] = self.scene.windows.compactMap { $0.window }
            if activeWindows.isEmpty {
                if self.terminateAfterLastWindowClosed {
                    let app = sharedApplication()
                    app!.terminate(exitCode: 0)
                    Log.debug("window closed, request app exit!")
                }
            }
        }
    }

    func finalize(application: Application) {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    init() {
        self.app = A()
        self.scene = _makeSceneProxy(self.app.body)
    }
}

extension App {
    public static func main() {
        let app = AppMain<Self>()
        let _ = runApplication(delegate: app)
    }
}
