//
//  File: App.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import DKGame

public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Self.Body { get }

    init()
}

class AppMain<A>: ApplicationDelegate where A: App {
    let app: A
    var scene: any SceneProxy
    var activeWindows: [Window] = []

    func initialize(application: Application) {
        let windows = self.scene.windows
        Task { @MainActor in
            for windowProxy in windows {
                if let window = windowProxy.makeWindow() {
                    self.activeWindows.append(window)
                    window.activate()
                    break
                }
            }
        }
    }

    func finalize(application: Application) {
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
