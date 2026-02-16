//
//  File: App.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

typealias Log = VVD.Log
typealias UnsafeBox<T> = VVD.UnsafeBox<T>
typealias WeakObject<T: AnyObject> = VVD.WeakObject<T>
typealias AnyWeakObject = VVD.AnyWeakObject

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
    
    var isActive: Bool { get }
}

extension AppContext {
    var isActive: Bool {
        sharedApplication()?.isActive ?? false
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
    var scene: SceneContext?
    var terminateAfterLastWindowClosed = true

    var activeWindows: [WindowContext] {
        var windows: [WindowContext] = []
        if let scene {
            scene.primaryWindows.forEach { window in
                if !windows.contains(where: { $0 === window }) {
                    windows.append(window)
                }
            }
            scene.windows.forEach { window in
                if !windows.contains(where: { $0 === window }) {
                    windows.append(window)
                }
            }
        }
        return windows.filter {
            $0.isValid && $0.window != nil
        }
    }

    func checkWindowActivities() {
        if self.activeWindows.isEmpty {
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

        let root = TypedSceneRoot(root: app.body, graph: _GraphValue<A.Body>.root(), app: self)
        let inputs = _SceneInputs(root: root, environment: EnvironmentValues())
        let outputs = A.Body._makeScene(scene: root.graph, inputs: inputs)
        self.scene = outputs.scene?.makeScene()

        if let scene {
            let primaryWindows = scene.primaryWindows

            Task { @MainActor in
                scene.updateContent()
                for window in primaryWindows {
                    if let win = window.makeWindow() {
                        win.activate()
                    }
                }
            }
            
            if primaryWindows.isEmpty == false {
                application.activationPolicy = .regular
            }
        }
    }

    func finalize(application: Application) {
        self.scene = nil
        self.graphicsDeviceContext = nil
        self.audioDeviceContext = nil
        self.resources = [:]
    }

    init() {
        self.app = A()
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
