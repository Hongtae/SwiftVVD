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

public protocol AppContext {
    var graphicsDeviceContext: GraphicsDeviceContext? { get }
    var audioDeviceContext: AudioDeviceContext? { get }

    func checkWindowActivities()
}

struct EmptyScene: Scene, _PrimitiveScene {
    func makeSceneProxy() -> any SceneProxy {
        SceneContext(scene: self, children: [])
    }
}

public var appContext: AppContext? = nil

class AppMain<A>: ApplicationDelegate, AppContext where A: App {

    var graphicsDeviceContext: GraphicsDeviceContext?
    var audioDeviceContext: AudioDeviceContext?

    let app: A
    var scene: any SceneProxy
    var terminateAfterLastWindowClosed = true

    func checkWindowActivities() {
        let activeWindows: [Window] = self.scene.windows.compactMap { $0.window }
        if activeWindows.isEmpty {
            if self.terminateAfterLastWindowClosed {
                let app = sharedApplication()
                app!.terminate(exitCode: 0)
                Log.debug("window closed, request app exit!")
            }
        }
    }

    func initialize(application: Application) {
        self.graphicsDeviceContext = makeGraphicsDeviceContext()
        self.audioDeviceContext = makeAudioDeviceContext()

        self.scene = _makeSceneProxy(self.app.body)

        let windows = self.scene.windows
        Task { @MainActor in
            for windowProxy in windows {
                if let window = windowProxy.makeWindow() {
                    window.activate()
                    break
                }
            }
        }
    }

    func finalize(application: Application) {
        self.scene = EmptyScene().makeSceneProxy()
        self.graphicsDeviceContext = nil
        self.audioDeviceContext = nil
    }

    init() {
        self.app = A()
        self.scene = EmptyScene().makeSceneProxy()
    }
}

extension App {
    public static func main() {
        let app = AppMain<Self>()
        appContext = app
        _ = runApplication(delegate: app)
    }
}
