//
//  File: App.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Self.Body { get }

    init()
}

protocol AppContext: AnyObject {
    var graphicsDeviceContext: GraphicsDeviceContext? { get }
    var audioDeviceContext: AudioDeviceContext? { get }

    func resourceData(forURL: URL) -> (any DataProtocol)?
    func setResource(data: (any DataProtocol)?, forURL: URL)

    func checkWindowActivities()
}

struct EmptyScene: Scene, _PrimitiveScene {
    func makeSceneProxy(modifiers: [any _SceneModifier]) -> any SceneProxy {
        SceneContext(scene: self, modifiers: modifiers, children: [])
    }
}

nonisolated(unsafe) var appContext: AppContext? = nil

class AppMain<A>: ApplicationDelegate, AppContext where A: App {

    var graphicsDeviceContext: GraphicsDeviceContext?
    var audioDeviceContext: AudioDeviceContext?
    var resources: [URL: (any DataProtocol)] = [:]

    func resourceData(forURL url: URL) -> (any DataProtocol)? {
        resources[url]
    }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {
        resources[url] = data
    }

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

        self.scene = _makeSceneProxy(self.app.body, modifiers: [])

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
        self.scene = EmptyScene().makeSceneProxy(modifiers: [])
        self.graphicsDeviceContext = nil
        self.audioDeviceContext = nil
        self.resources = [:]
    }

    init() {
        self.app = A()
        self.scene = EmptyScene().makeSceneProxy(modifiers: [])
    }
}

extension App {
    @MainActor
    public static func main() {
        let app = AppMain<Self>()
        appContext = app
        _ = runApplication(delegate: app)
    }
}
