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
    var view: Content
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
            Log.info("Window upate task start.")
            var tickCounter = TickCounter()

            mainLoop: while true {
                guard let self = self else { break }
                if Task.isCancelled { break }

                let swapChain = self.swapChain
                let (state, config) = { (self.state, self.config) }()

                let frameInterval = state.activated ? config.activeFrameInterval : config.inactiveFrameInterval

                let delta = tickCounter.reset()
                let tick = tickCounter.timestamp
                let date = Date(timeIntervalSinceNow: 0)

                let view = self.viewProxy
                view.update(tick: tick, delta: delta, date: date)

                if state.visible, let swapChain {
                    var renderPass = swapChain.currentRenderPassDescriptor()
                    renderPass.colorAttachments[0].clearColor = .cyan

                    if let commandBuffer = swapChain.commandQueue.makeCommandBuffer() {
                        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
                            encoder.endEncoding()
                        }
                        commandBuffer.commit()
                    }

                    let device = swapChain.commandQueue.device
                    let backBuffer = renderPass.colorAttachments[0].renderTarget!
                    var maskRenderTarget = self.sharedContext.maskRenderTarget
                    var stencilBuffer = self.sharedContext.stencilBuffer
                    if let maskRenderTarget, maskRenderTarget.width == backBuffer.width && maskRenderTarget.height == backBuffer.height {
                    } else {
                        let desc = TextureDescriptor(textureType: .type2D,
                                                     pixelFormat: .r8Unorm,
                                                     width: backBuffer.width,
                                                     height: backBuffer.height,
                                                     usage: [.renderTarget, .sampled])
                        maskRenderTarget = device.makeTexture(descriptor: desc)
                    }
                    if let stencilBuffer, stencilBuffer.width == backBuffer.width && stencilBuffer.height == backBuffer.height {
                    } else {
                        let desc = TextureDescriptor(textureType: .type2D,
                                                     pixelFormat: .stencil8,
                                                     width: backBuffer.width,
                                                     height: backBuffer.height,
                                                     usage: [.renderTarget, .sampled])
                        stencilBuffer = device.makeTexture(descriptor: desc)
                    }

                    self.sharedContext.backBuffer = backBuffer
                    self.sharedContext.maskRenderTarget = maskRenderTarget
                    self.sharedContext.stencilBuffer = stencilBuffer

                    view.draw()
                    await swapChain.present()
                }

                while tickCounter.elapsed < frameInterval {
                    if Task.isCancelled {
                        break mainLoop
                    }
                    await Task.yield()
                }
            }
        }
    }

    init(content: Content, contextType: Any.Type, identifier: String, title: String) {
        self.contextType = contextType
        self.identifier = identifier
        self.title = title
        self.view = content
        self.environmentValues = EnvironmentValues()
        self.sharedContext = SharedContext(appContext: appContext!)
        self.viewProxy = _makeViewProxy(self.view,
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
                    if GraphicsPipelineStates.cacheContext(graphicsDevice) == false {
                        Log.error("Failed to cache GraphicsPipelineStates")
                    }
                    if let swapChain = graphicsDevice.renderQueue()?.makeSwapChain(target: window) {
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
                        self.window = window
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
            self.state.frame = event.windowFrame
            self.state.bounds = event.contentBounds
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
            self.state.frame = event.windowFrame
            self.state.bounds = event.contentBounds
            self.state.contentScaleFactor = event.contentScaleFactor
        case .update:
            break
        }
    }

    @MainActor
    func onKeyboardEvent(event: KeyboardEvent) {
        Log.debug("WindowContext.onKeyboardEvent: \(event)")
    }

    @MainActor
    func onMouseEvent(event: MouseEvent) {
        if event.type != .move {
            Log.debug("WindowContext.onMouseEvent: \(event)")
        }
    }
}
