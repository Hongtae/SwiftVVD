//
//  File: App.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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

    var appWindowsController: AppWindowsController? { get }

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
    var appGraph: AppGraph<A>?
    var windowsController: AppWindowsController?
    var appWindowsController: AppWindowsController? { windowsController }
    var terminateAfterLastWindowClosed = true

    var activeWindows: [WindowController] {
        guard let windowsController else { return [] }
        return windowsController.allWindowControllers.filter {
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

        let graph = AppGraph(app: app)
        let wc = AppWindowsController()
        wc.syncWindowControllers(sceneListAttr: graph.sceneListAttr,
                                 runtimeConfigAttr: graph.runtimeWindowConfigAttr,
                                 in: graph.graph)
        self.appGraph = graph
        self.windowsController = wc
        
        let primaryWindows = wc.allWindowControllers
        if primaryWindows.isEmpty == false {
            application.activationPolicy = .regular
        }
        Task { @MainActor in
            for window in primaryWindows {
                if let win = window.makeWindow() {
                    win.activate()
                }
            }
        }
    }

    func finalize(application: Application) {
        self.appGraph = nil
        self.windowsController = nil
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
