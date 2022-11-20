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
    var scenes: [SceneProxy] = []
    var windowProxies: [WindowProxy] = []
    var activeWindows: [Window] = []

    func initialize(application: Application) {
        self.scenes = A.Body._makeSceneProxies(app.body)
        self.windowProxies = self.scenes.flatMap { scene in
            scene.makeWindowProxies()
        }
        for proxy in self.windowProxies {
            if let window = proxy.makeWindow() {
                self.activeWindows.append(window)
                Task { @MainActor in window.activate() }
                break
            }
        }
    }

    func finalize(application: Application) {
    }

    init() {
        self.app = A()
    }
}

extension App {
    public static func main() {
        let app = AppMain<Self>()
        let _ = runApplication(delegate: app)
    }
}
