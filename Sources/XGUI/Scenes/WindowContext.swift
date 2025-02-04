//
//  File: WindowContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

final class WindowContext<Content> : WindowProxy, Scene, _PrimitiveScene, WindowDelegate, @unchecked Sendable where Content : View {
    let contextType: Any.Type
    let identifier: String
    let title: Text

    private(set) var swapChain: SwapChain?
    private(set) var window: Window?

    var modifiers: [any _SceneModifier] = []
    var view: ViewContext?
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

    private let stateConfig = Mutex<(state: State, config: Configuration)>((state: State(), config: Configuration()))

    private var task: Task<Void, Never>?

    private func runWindowUpdateTask() -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { @MainActor @Sendable [weak self] in
            Log.info("WindowContext<\(Content.self)> update task is started.")
            var tickCounter = TickCounter.now

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
                let (state, config) = self.stateConfig.withLock {
                    ($0.state, $0.config)
                }

                guard let view = self.view, view.isValid
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

                var viewsToReload = sharedContext.viewsNeedToReloadResources.compactMap { $0.value }
                sharedContext.viewsNeedToReloadResources.removeAll()

                if viewLoaded {
                    if viewsToReload.contains(where: {
                        $0 === view
                    }) {
                        viewLoaded = false
                    } else {
                        func getRoot(_ view: ViewContext) -> ViewContext {
                            if let superview = view.superview {
                                return getRoot(superview)
                            }
                            return view
                        }
                        // Unless the view is the root view, a superview must exist.
                        viewsToReload = viewsToReload.filter { getRoot($0) === view }
                    }
                }
                if viewLoaded == false {
                    viewsToReload = [view]
                }

                if state.bounds != contentBounds || state.contentScaleFactor != contentScaleFactor ||
                    viewsToReload.isEmpty == false {

                    if state.contentScaleFactor != contentScaleFactor {
                        sharedContext.contentScaleFactor = state.contentScaleFactor
                        self.environmentValues.displayScale = state.contentScaleFactor
                        view.updateEnvironment(self.environmentValues)
                        viewLoaded = false
                        viewsToReload = [view]
                    }

                    contentBounds = state.bounds
                    contentScaleFactor = state.contentScaleFactor

                    let bounds = state.bounds.standardized
                    sharedContext.contentBounds = bounds
                    sharedContext.contentScaleFactor = state.contentScaleFactor

                    if viewsToReload.isEmpty == false {
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
                                viewsToReload.forEach { view in
                                    view.loadResources(context)
                                }
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
                    view.update(transform: .identity)
                }
                assert(viewLoaded)
                if sharedContext.needsLayout {
                    sharedContext.needsLayout = false
                    let bounds = contentBounds
                    //view.layoutSubviews()
                    view.place(at: CGPoint(x: bounds.midX, y: bounds.midY),
                               anchor: .center,
                               proposal: ProposedViewSize(bounds.size))
                    view.update(transform: .identity)
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
                    Platform.threadYield()
                }
            }
            Log.info("WindowContext<\(Content.self)> update task is finished.")
        }
    }

    init(content: ()->Content, contextType: Any.Type, identifier: String, title: Text) {
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

        self.sharedContext.viewContentRoot = (content(), graph.unsafeCast(to: Any.self))

        // initialize root-view instance
        self.view = outputs.view?.makeView()
         if let view {
             view.updateContent()
             if view.validate() == false {
                 Log.err("View(type:\(Content.self) validation failed.")
             }
         }
    }

    deinit {
        Log.debug("WindowContext<\(Content.self)> deinit")
        self.task?.cancel()
        self.sharedContext.gestureHandlers.removeAll()
        self.sharedContext.resourceData.removeAll()
        self.sharedContext.resourceObjects.removeAll()
        self.swapChain = nil
        self.window = nil
        self.view = nil
    }

    @MainActor
    func makeWindow() -> Window? {
        if self.window == nil {
            self.task?.cancel()
            self.task = nil
            self.swapChain = nil

            let windowTitle = self.title._resolveText(in: self.environmentValues)
            if let window = VVD.makeWindow(name: windowTitle,
                                              style: [.genericWindow],
                                              delegate: self) {

                if let graphicsDevice = appContext?.graphicsDeviceContext {
                    if GraphicsContext.cachePipelineContext(graphicsDevice) == false {
                        Log.error("Failed to cache GraphicsPipelineStates")
                    }
                    if let swapChain = graphicsDevice.renderQueue()?.makeSwapChain(target: window) {
                        self.stateConfig.withLock {
                            $0.state.frame = window.windowFrame.standardized
                            $0.state.bounds = window.contentBounds.standardized
                            $0.state.contentScaleFactor = window.contentScaleFactor
                            $0.state.visible = window.visible
                            $0.state.activated = window.activated
                        }
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

    func applyModifiers() {
        if let frameRate = self.modifiers.first(where: { $0 is _UpdateFrameRate }) as? _UpdateFrameRate {
            self.stateConfig.withLock {
                $0.config.activeFrameInterval = frameRate.activeFrameRate
                $0.config.inactiveFrameInterval = frameRate.inactiveFrameRate
            }
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

        let releaseEventHandlers = {
            self.sharedContext.focusedViews.forEach {
                (deviceID, weakViewProxy) in
                weakViewProxy.value?.onLostFocus(for: deviceID)
            }
            self.sharedContext.focusedViews.removeAll()
            self.sharedContext.gestureHandlers.forEach {
                $0.reset()
            }
            self.sharedContext.gestureHandlers.removeAll()
        }

        switch event.type {
        case .closed:
            self.task?.cancel()
            self.window?.removeEventObserver(self)

            self.swapChain = nil
            self.window = nil
            self.task = nil

            DispatchQueue.main.async {
                appContext?.checkWindowActivities()
            }
        case .created:
            self.stateConfig.withLock {
                $0.state.frame = event.windowFrame.standardized
                $0.state.bounds = event.contentBounds.standardized
                $0.state.contentScaleFactor = event.contentScaleFactor
            }
        case .hidden:
            releaseEventHandlers()
            self.stateConfig.withLock {
                $0.state.visible = false
                $0.state.activated = false
            }
        case .shown:
            self.stateConfig.withLock {
                $0.state.visible = true
            }
        case .activated:
            self.stateConfig.withLock {
                $0.state.visible = true
                $0.state.activated = true
            }
        case .inactivated:
            releaseEventHandlers()
            self.stateConfig.withLock {
                $0.state.activated = false
            }
        case .minimized:
            releaseEventHandlers()
            self.stateConfig.withLock {
                $0.state.activated = false
                $0.state.visible = false
            }
        case .moved, .resized:
            self.stateConfig.withLock {
                $0.state.frame = event.windowFrame.standardized
                $0.state.bounds = event.contentBounds.standardized
                $0.state.contentScaleFactor = event.contentScaleFactor
            }
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

        var gestureHandlers = self.sharedContext.gestureHandlers
        defer {
            self.sharedContext.gestureHandlers = gestureHandlers
        }

        if gestureHandlers.isEmpty {
            if event.type == .buttonDown {
                let location = event.location.applying(view.transformToContainer.inverted())
                let outputs = view.gestureHandlers(at: location)
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
        self.sharedContext.gestureHandlers = gestureHandlers

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
