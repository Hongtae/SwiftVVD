//
//  File: WindowContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import DKGame
import Foundation

class WindowContext<Content>: WindowProxy, Scene, _PrimitiveScene, WindowDelegate where Content: View {

    let contextType: Any.Type
    let identifier: String
    let title: String

    private(set) var swapChain: SwapChain?
    private(set) var window: Window?

    var viewProxy: any ViewProxy
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext

    struct State {
        var visible = false
        var activated = false
        var suspended = false
        var contentScaleFactor: CGFloat = 1.0
        var frame: CGRect = .zero
        var bounds: CGRect = .zero
    }
    struct Configuration {
        var activeFrameInterval = 1.0 / 60.0
        var inactiveFrameInterval = 1.0 / 30.0
    }
    @MainActor var state = State()
    @MainActor var config = Configuration()

    private var task: Task<Void, Never>?

    private func runWindowUpdateTask() -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { @MainActor [weak self] in
            Log.info("WindowContext<\(Content.self)> update task is started.")
            var tickCounter = TickCounter()

            var contentBounds: CGRect = .null
            var contentScaleFactor: CGFloat = 1
            var renderTargets: GraphicsContext.RenderTargets? = nil

            mainLoop: while true {
                guard let self = self else { break }
                if Task.isCancelled { break }

                let view = self.viewProxy

                let swapChain = self.swapChain
                let (state, config) = { (self.state, self.config) }()

                let frameInterval = state.activated ? config.activeFrameInterval : config.inactiveFrameInterval

                let delta = tickCounter.reset()
                let tick = tickCounter.timestamp
                let date = Date(timeIntervalSinceNow: 0)

                if state.bounds != contentBounds || state.contentScaleFactor != contentScaleFactor {

                    if state.contentScaleFactor != contentScaleFactor {
                        self.environmentValues.displayScale = state.contentScaleFactor
                        view.updateEnvironment(self.environmentValues)
                    }

                    view.layout(offset: state.bounds.origin,
                                size: state.bounds.size,
                                scaleFactor: state.contentScaleFactor)
                    contentBounds = state.bounds
                    contentScaleFactor = state.contentScaleFactor
                }
                view.update(tick: tick, delta: delta, date: date)

                if state.visible, let swapChain {
                    var renderPass = swapChain.currentRenderPassDescriptor()

                    let device = swapChain.commandQueue.device
                    let backBuffer = renderPass.colorAttachments[0].renderTarget!

                    let dim = { (tex: Texture) in (tex.width, tex.height, tex.depth) }

                    if let renderTargets, dim(renderTargets.backdrop) == dim(backBuffer) {
                    } else {
                        renderTargets = GraphicsContext.RenderTargets(
                            device: device,
                            width: backBuffer.width,
                            height: backBuffer.height)
                    }

                    renderPass.colorAttachments[0].clearColor = .darkGray
                    if let renderTargets,
                       let commandBuffer = swapChain.commandQueue.makeCommandBuffer() {

                        renderTargets.initialized = false
                        if let context = GraphicsContext(
                            sharedContext: self.sharedContext,
                            environment: view.environmentValues,
                            viewport: CGRect(x: 0, y: 0,
                                             width: backBuffer.width,
                                             height: backBuffer.height),
                            contentOffset: contentBounds.origin,
                            contentScaleFactor: state.contentScaleFactor,
                            renderTargets: renderTargets,
                            commandBuffer: commandBuffer) {
                            view.draw(frame: contentBounds, context: context)

                            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
                                if renderTargets.initialized {
                                    let backdrop = renderTargets.backdrop
                                    renderTargets.backdrop = backBuffer
                                    defer {
                                        renderTargets.backdrop = backdrop
                                    }
                                    
                                    context.encodeDrawTextureCommand(
                                        texture: backdrop,
                                        in: contentBounds,
                                        textureFrame: CGRect(x: 0, y: 0,
                                                             width: backBuffer.width,
                                                             height: backBuffer.height),
                                        blendState: .opaque,
                                        color: .white,
                                        encoder: encoder)
                                }
                                encoder.endEncoding()
                            }
                        } else {
                            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
                                encoder.endEncoding()
                            }
                        }

                        commandBuffer.commit()
                        await swapChain.present()
                    }
                }

                let t = frameInterval - tickCounter.elapsed
                if t > 0 {
                    do {
                        try await Task.sleep(until: .now + .seconds(t), clock: .suspending)
                    } catch {
                        break mainLoop
                    }
                }
            }
            Log.info("WindowContext<\(Content.self)> update task is finished.")
        }
    }

    init(content: Content, contextType: Any.Type, identifier: String, title: String) {
        self.contextType = contextType
        self.identifier = identifier
        self.title = title

        self.environmentValues = EnvironmentValues()
        self.sharedContext = SharedContext(appContext: appContext!)
        self.viewProxy = _makeViewProxy(content,
                                        modifiers: [],
                                        environmentValues: self.environmentValues,
                                        sharedContext: self.sharedContext)
    }

    deinit {
        self.task?.cancel()
        self.swapChain = nil
        self.window = nil
    }

    @MainActor
    func makeWindow() -> Window? {
        if self.window == nil {
            self.task?.cancel()
            self.task = nil
            self.swapChain = nil

            if let window = DKGame.makeWindow(name: self.title,
                                              style: [.genericWindow],
                                              delegate: self) {

                if let graphicsDevice = appContext?.graphicsDeviceContext {
                    if GraphicsContext.cachePipelineContext(graphicsDevice) == false {
                        Log.error("Failed to cache GraphicsPipelineStates")
                    }
                    if let swapChain = graphicsDevice.renderQueue()?.makeSwapChain(target: window) {
                        self.state.frame = window.windowFrame.standardized
                        self.state.bounds = window.contentBounds.standardized
                        self.state.contentScaleFactor = window.contentScaleFactor
                        self.state.visible = window.visible
                        self.state.activated = window.activated
                        self.window = window

                        window.addEventObserver(self) {
                            [weak self](event: WindowEvent) in
                            if let self = self { self.onWindowEvent(event: event) }
                        }
                        window.addEventObserver(self) {
                            [weak self](event: KeyboardEvent) in
                            if let self = self { self.onKeyboardEvent(event: event) }
                        }
                        window.addEventObserver(self) {
                            [weak self](event: MouseEvent) in
                            if let self = self { self.onMouseEvent(event: event) }
                        }

                        self.swapChain = swapChain
                        self.sharedContext.window = self.window
                        self.sharedContext.commandQueue = swapChain.commandQueue
                        self.task = self.runWindowUpdateTask()
                    } else {
                        Log.error("Failed to create swapChain.")
                    }
                } else {
                    Log.error("GraphicsDeviceContext is nil")
                }
            }
        }
        return self.window
    }

    func makeSceneProxy() -> any SceneProxy {
        SceneContext(scene: self, window: self)
    }

    @MainActor
    func onWindowEvent(event: WindowEvent) {
        if event.window !== self.window { return }
        Log.debug("WindowContext.onWindowEvent: \(event)")
        switch event.type {
        case .closed:
            self.sharedContext.window = nil
            self.sharedContext.commandQueue = nil

            self.task?.cancel()
            self.window?.removeEventObserver(self)

            self.swapChain = nil
            self.window = nil
            self.task = nil

            DispatchQueue.main.async {
                appContext?.checkWindowActivities()
            }
        case .created:
            self.state.frame = event.windowFrame.standardized
            self.state.bounds = event.contentBounds.standardized
            self.state.contentScaleFactor = event.contentScaleFactor
        case .hidden:
            self.state.visible = false
            self.state.activated = false
        case .shown:
            self.state.visible = true
        case .activated:
            self.state.visible = true
            self.state.activated = true
        case .inactivated:
            self.state.activated = false
        case .minimized:
            self.state.activated = false
            self.state.visible = false
        case .moved, .resized:
            self.state.frame = event.windowFrame.standardized
            self.state.bounds = event.contentBounds.standardized
            self.state.contentScaleFactor = event.contentScaleFactor
        case .update:
            break
        }
    }

    @MainActor
    func onKeyboardEvent(event: KeyboardEvent) {
        if event.window !== self.window { return }
        Log.debug("WindowContext.onKeyboardEvent: \(event)")
    }

    @MainActor
    func onMouseEvent(event: MouseEvent) {
        if event.window !== self.window { return }
        if event.type != .move {
            Log.debug("WindowContext.onMouseEvent: \(event)")
        }
    }
}
