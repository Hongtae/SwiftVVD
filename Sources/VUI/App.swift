//
//  File: App.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

typealias Log = VVD.Log

public typealias Clipboard = VVD.Clipboard
public typealias ClipboardContentType = VVD.ClipboardContentType

public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Self.Body { get }

    init()
}

public extension App {
    static var clipboard: (any Clipboard)? {
        sharedApplication()?.clipboard
    }
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
                                 commandsListAttr: graph.commandsListAttr,
                                 rootEnvironmentAttr: graph.rootEnvironmentAttr,
                                 focusedValuesAttr: graph.focusedValuesAttr,
                                 configurationOverrideAttr: graph.windowConfigurationOverrideAttr,
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
        AppLifetimeResource.purgeAllResources(reason: .appTermination)
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

enum ResourcePurgeReason {
    case lowMemory
    case appTermination
}

class AppLifetimeResource: @unchecked Sendable {
    init() {
        Self._appResources.withLock { resources in
            var res = resources.filter { $0.value != nil }
            res.append(WeakObject(self))
            resources = res
        }
    }

    func purgeResources(reason: ResourcePurgeReason) {
    }

    private static let _appResources = Mutex<[WeakObject<AppLifetimeResource>]>([])

    fileprivate static func purgeAllResources(reason: ResourcePurgeReason = .appTermination) {
        let res = _appResources.withLock { resources in
            let live = resources.compactMap { $0.value }
            if reason == .appTermination {
                resources.removeAll()
            } else {
                resources = resources.filter { $0.value != nil }
            }
            return live
        }
        res.reversed().forEach { $0.purgeResources(reason: reason) }
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
