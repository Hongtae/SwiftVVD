//
//  File: WindowContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

class WindowContext<Content>: WindowProxy, Scene, _PrimitiveScene, WindowDelegate where Content: View {

    let contextType: Any.Type
    let identifier: String
    let title: String

    private(set) var swapChain: SwapChain?
    private(set) var window: Window?

    var modifiers: [any _SceneModifier] = []
    var view: ViewContext?
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext

    var gestureHandlers: [_GestureHandler] = []

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
    private let stateLock = SpinLock()
    private var state = State()
    private var config = Configuration()

    private var task: Task<Void, Never>?

    private func runWindowUpdateTask() -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { @MainActor [weak self] in
            Log.info("WindowContext<\(Content.self)> update task is started.")
            var tickCounter = TickCounter()

            var contentBounds: CGRect = .null
            var contentScaleFactor: CGFloat = 1
            var renderTargets: GraphicsContext.RenderTargets? = nil
            var viewLoaded = false

            //let clearColor = VVD.Color(rgba8: (245, 242, 241, 255))
            let clearColor = VVD.Color(rgba8: (255, 255, 241, 255))

            mainLoop: while true {
                guard let self = self else { break }
                if Task.isCancelled { break }

                let swapChain = self.swapChain
                let (state, config) = synchronizedBy(locking: self.stateLock) {
                    (self.state, self.config)
                }

                guard let view = self.view
                else {
                    if state.visible, let swapChain {
                        var renderPass = swapChain.currentRenderPassDescriptor()
                        if let commandBuffer = swapChain.commandQueue.makeCommandBuffer() {
                            renderPass.colorAttachments[0].clearColor = clearColor
                            renderPass.colorAttachments[0].loadAction = .clear
                            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
                                encoder.endEncoding()
                            }
                            commandBuffer.commit()
                            _=swapChain.present()
                        }
                    }
                    let frameInterval = config.inactiveFrameInterval
                    repeat {
                        if Task.isCancelled { break mainLoop }
                        await Task.yield()
                    } while tickCounter.elapsed < frameInterval
                    continue
                }

                let frameInterval = state.activated ? config.activeFrameInterval : config.inactiveFrameInterval

                let delta = tickCounter.reset()
                let tick = tickCounter.timestamp
                let date = Date(timeIntervalSinceNow: 0)

                if state.bounds != contentBounds || state.contentScaleFactor != contentScaleFactor {

                    if state.contentScaleFactor != contentScaleFactor {
                        sharedContext.contentScaleFactor = state.contentScaleFactor
                        self.environmentValues.displayScale = state.contentScaleFactor
                        view.updateEnvironment(self.environmentValues)
                        viewLoaded = false
                    }

                    contentBounds = state.bounds
                    contentScaleFactor = state.contentScaleFactor

                    let bounds = state.bounds.standardized
                    sharedContext.contentBounds = bounds
                    sharedContext.contentScaleFactor = state.contentScaleFactor

                    if viewLoaded == false {
                        if let commandBuffer = appContext?.graphicsDeviceContext?.renderQueue()?.makeCommandBuffer() {
                            let width = 4, height = 4
                            if var context = GraphicsContext(sharedContext: sharedContext,
                                                             environment: environmentValues,
                                                             viewport: CGRect(x: 0, y: 0, width: width, height: height),
                                                             contentOffset: .zero,
                                                             contentScaleFactor: contentScaleFactor,
                                                             resolution: CGSize(width: width, height: height),
                                                             commandBuffer: commandBuffer) {
                                context.environment = view.environmentValues
                                view.loadResources(context)
                                commandBuffer.commit()
                            } else {
                                Log.error("GraphicsContext failed.")
                            }
                        } else {
                            Log.error("GraphicsDeviceContext.makeCommandBuffer failed.")
                        }
                        viewLoaded = true
                    }
                    view.place(at: CGPoint(x: bounds.midX, y: bounds.midY),
                               anchor: .center,
                               proposal: ProposedViewSize(bounds.size))
                    view.update(transform: .identity, origin: .zero)
                }
                assert(viewLoaded)
                if sharedContext.needsLayout {
                    sharedContext.needsLayout = false
                    let bounds = contentBounds
                    //view.layoutSubviews()
                    view.place(at: CGPoint(x: bounds.midX, y: bounds.midY),
                               anchor: .center,
                               proposal: ProposedViewSize(bounds.size))
                    view.update(transform: .identity, origin: .zero)
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

                    renderPass.colorAttachments[0].clearColor = clearColor
                    if let renderTargets,
                       let commandBuffer = swapChain.commandQueue.makeCommandBuffer() {

                        if let context = GraphicsContext(
                            sharedContext: self.sharedContext,
                            environment: view.environmentValues,
                            viewport: CGRect(x: 0, y: 0,
                                             width: backBuffer.width,
                                             height: backBuffer.height),
                            contentOffset: contentBounds.origin,
                            contentScaleFactor: contentScaleFactor,
                            renderTargets: renderTargets,
                            commandBuffer: commandBuffer) {

                            context.clear(with: clearColor)
                            view.drawView(frame: view.frame, context: context)

                            if let rp = context.beginRenderPass(descriptor: renderPass,
                                                                viewport: context.viewport) {
                                context.encodeDrawTextureCommand(
                                    renderPass: rp,
                                    texture: context.backdrop,
                                    frame: contentBounds,
                                    textureFrame: context.viewport,
                                    blendState: .opaque,
                                    color: .white)
                                rp.end()
                            } else {
                                Log.error("beginRenderPass failed.")
                            }
                        } else {
                            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
                                encoder.endEncoding()
                            }
                        }

                        commandBuffer.commit()
                        _=swapChain.present()
                    }
                }

                await Task.yield() // unblock main thread

                let tickGranularity = 0.012
                while tickCounter.elapsed < frameInterval - tickGranularity {
                    if Task.isCancelled { break mainLoop }
                    await Task.yield()
                }
                // It's less than the tick granularity, so we can't call sleep.
                while tickCounter.elapsed < frameInterval {
                    if Task.isCancelled { break mainLoop }
                    threadYield()
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

        let properties = PropertyList(
            DefaultLayoutPropertyItem(layout: VStackLayout()),
            DefaultPaddingEdgeInsetsPropertyItem(insets: EdgeInsets(_all: 16))
        )

        let baseInputs = _GraphInputs(properties: properties,
                                      environment: self.environmentValues,
                                      sharedContext: self.sharedContext)

        let graph = _GraphValue<Content>.root()
        let inputs = _ViewInputs.inputs(with: baseInputs)

        let outputs = Content._makeView(view: graph, inputs: inputs)

        self.view = outputs.view?.makeView(encloser: content, graph: graph)
        if let view {
            if view.validatePath(encloser: content, graph: graph) == false {
                fatalError("Invalid path")
            }
            view.resolveGraphInputs(encloser: content, graph: graph)
        }
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

            if let window = VVD.makeWindow(name: self.title,
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
        self.applyModifiers()
        return self.window
    }

    @MainActor
    func applyModifiers() {
        if let frameRate = self.modifiers.first(where: { $0 is _UpdateFrameRate }) as? _UpdateFrameRate {
            self.config.activeFrameInterval = frameRate.activeFrameRate
            self.config.inactiveFrameInterval = frameRate.inactiveFrameRate
        }
    }

    func makeSceneProxy(modifiers: [any _SceneModifier]) -> any SceneProxy {
        self.modifiers = modifiers
        return SceneContext(scene: self, modifiers: modifiers, window: self)
    }

    @MainActor
    func onWindowEvent(event: WindowEvent) {
        if event.window !== self.window { return }
        Log.debug("WindowContext.onWindowEvent: \(event)")
        self.stateLock.lock()
        defer { self.stateLock.unlock() }

        let releaseEventHandlers = {
            self.sharedContext.focusedViews.forEach {
                (deviceID, weakViewProxy) in
                weakViewProxy.value?.onLostFocus(for: deviceID)
            }
            self.sharedContext.focusedViews.removeAll()
            self.gestureHandlers.forEach {
                $0.reset()
            }
            self.gestureHandlers.removeAll()
        }

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
            releaseEventHandlers()
            self.state.visible = false
            self.state.activated = false
        case .shown:
            self.state.visible = true
        case .activated:
            self.state.visible = true
            self.state.activated = true
        case .inactivated:
            releaseEventHandlers()
            self.state.activated = false
        case .minimized:
            releaseEventHandlers()
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
        if let focusedView = self.sharedContext.focusedViews[event.deviceID]?.value {
            _ = focusedView.processKeyboardEvent(type: event.type,
                                            deviceID: event.deviceID,
                                            key: event.key,
                                            text: event.text)
        }
    }

    @MainActor
    func onMouseEvent(event: MouseEvent) {
        if event.window !== self.window { return }
        if event.type != .move && event.type != .pointing {
            //Log.debug("WindowContext.onMouseEvent: \(event)")
        }

        guard let view = self.view else { return }

        if event.type == .wheel {
            _ = view.handleMouseWheel(at: event.location,
                                                delta: event.delta)
            return
        }

        var gestureHandlers = self.gestureHandlers
        defer {
            self.gestureHandlers = gestureHandlers
        }

        if gestureHandlers.isEmpty {
            if event.type == .buttonDown {
                let outputs = view.gestureHandlers(at: event.location)
                gestureHandlers = outputs.highPriorityGestures + outputs.gestures + outputs.simultaneousGestures
            }
        }

        let activeHandlers = {
            gestureHandlers.compactMap {
                if $0.state == .ready || $0.state == .processing {
                    return $0
                }
                return nil
            }
        }

        gestureHandlers = activeHandlers()

        if gestureHandlers.isEmpty { return }
        switch event.type {
        case .buttonDown:
            gestureHandlers.forEach {
                $0.began(deviceID: event.deviceID, buttonID: event.buttonID, location: event.location)
            }
        case .buttonUp:
            gestureHandlers.forEach {
                $0.ended(deviceID: event.deviceID, buttonID: event.buttonID)
            }
        case .move:
            gestureHandlers.forEach {
                $0.moved(deviceID: event.deviceID, buttonID: event.buttonID, location: event.location)
            }
        default:
            break
        }
        gestureHandlers = activeHandlers()
    }
}
