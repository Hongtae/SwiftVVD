//
//  File: WindowContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

protocol WindowContext: AnyObject {
    typealias Window = VVD.Window
    typealias WindowStyle = VVD.WindowStyle

    var scene: SceneContext { get }
    var window: Window? { get }
    var isValid: Bool { get }

    func updateContent()
    
    func updateView(tick: UInt64, delta: Double, date: Date)
    func drawFrame(_: GraphicsContext, offset: CGPoint)
    
    var view: ViewContext? { get }

    @MainActor
    func makeWindow() -> Window?
}

protocol WindowInputEventHandler {
    func handleKeyboardEvent(event: KeyboardEvent) -> Bool
    func handleMouseEvent(event: MouseEvent) -> Bool
    func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool
}

class GenericWindowContext<Content>: WindowContext, AuxiliaryWindowHost, WindowInputEventHandler, WindowDelegate, @unchecked Sendable where Content: View {
    typealias Window = WindowContext.Window

    private(set) var swapChain: SwapChain?
    private(set) var window: Window?

    var view: ViewContext?
    let content: _GraphValue<Content>
    var environment: EnvironmentValues
    var sharedContext: SharedContext
    var scene: SceneContext {
        sharedContext.scene
    }
    var title: String { "" }
    var style: WindowStyle { .genericWindow }

    var filterGestureTypes: Bool = true
    var allowedGestureTypes: _PrimitiveGestureTypes = .all

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

    private struct AuxiliaryWindow {
        let window: WindowContext
        let offset: CGPoint
        let color: Color
        let filter: GraphicsContext.Filter?
    }
    private var auxiliaryWindows: [AuxiliaryWindow] = []
    
    init(content: _GraphValue<Content>, scene: SceneContext) {
        let sceneInputs = scene.inputs
        self.content = content
        self.environment = sceneInputs.environment
        self.sharedContext = SharedContext(scene: scene)
        self.sharedContext._window = self

        var properties = PropertyList()
        properties.setValue(VStackLayout(), forKey: DefaultLayoutProperty.self)
        properties.setValue(EdgeInsets(_all: 16), forKey: DefaultPaddingEdgeInsetsProperty.self)

        self.view = SharedContext.$taskLocalContext.withValue(sharedContext) {
            let baseInputs = _GraphInputs(properties: properties,
                                          environment: sceneInputs.environment,
                                          modifiers: sceneInputs.modifiers,
                                          _modifierTypeGraphs: sceneInputs._modifierTypeGraphs)
            let inputs = _ViewInputs.inputs(with: baseInputs)
            let outputs = Content._makeView(view: content, inputs: inputs)
            return outputs.view?.makeView()
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

    func updateContent() {
        if let content = scene.value(atPath: self.content) {
            self.sharedContext.root = TypedViewRoot(root: content, graph: self.content, scene: self.scene)
            if let view {
                view.updateContent()
                if view.validate() == false {
                    Log.err("View(type:\(Content.self) validation failed.")
                }
            }
        } else {
            fatalError("Unable to recover view for \(content)")
        }
    }

    var isValid: Bool {
        if let view {
            return view.isValid
        }
        return false
    }

    @MainActor
    func makeWindow() -> Window? {
        if self.window == nil {

            self.task?.cancel()
            self.task = nil
            self.swapChain = nil

            let title = self.title
            let style = self.style

            if let window = VVD.makeWindow(name: title,
                                           style: style,
                                           delegate: self) {
                if let graphicsDevice = appContext?.graphicsDeviceContext {
                    if GraphicsContext.cachePipelineContext(graphicsDevice) == false {
                        Log.error("Failed to cache GraphicsPipelineStates")
                    }
                    self.onWindowCreated(window)
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
                        self.onSwapchainCreated(swapChain)
                        self.task = self.runUpdateTask()
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
        // TODO: check modifiers..
    }
    
    func updateView(tick: UInt64, delta: Double, date: Date) {
        if let view, view.isValid {
            var viewsToReload = sharedContext.viewsNeedToReloadResources.compactMap { $0.value }
            sharedContext.viewsNeedToReloadResources.removeAll()

            if viewsToReload.contains(where: {
                $0 === view
            }) {
                viewsToReload = [view]
            } else if viewsToReload.isEmpty == false {
                let copiedList = viewsToReload
                let rootView = view
                let isValidToReload = { (_ view: ViewContext) -> Bool in
                    var view = Optional(view)
                    while let superview = view?.superview {
                        // when the view is reloaded, its subviews are also reloaded.
                        if copiedList.contains(where: { $0 === superview }) {
                            return false
                        }
                        view = superview
                    }
                    // the root view must be the same.
                    return view === rootView
                }
                viewsToReload = viewsToReload.filter { isValidToReload($0) }
            }

            if viewsToReload.isEmpty == false {
                if let commandBuffer = appContext?.graphicsDeviceContext?.renderQueue()?.makeCommandBuffer() {
                    let width = 4, height = 4
                    let scaleFactor = sharedContext.contentScaleFactor
                    if var context = GraphicsContext(sharedContext: sharedContext,
                                                     environment: environment,
                                                     viewport: CGRect(x: 0, y: 0, width: width, height: height),
                                                     contentOffset: .zero,
                                                     contentScaleFactor: scaleFactor,
                                                     resolution: CGSize(width: width, height: height),
                                                     commandBuffer: commandBuffer) {
                        context.environment = view.environment
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
                self.onViewLoaded()
            }

            if sharedContext.needsLayout {
                let bounds = sharedContext.contentBounds
                sharedContext.needsLayout = false
                view.place(at: CGPoint(x: bounds.midX, y: bounds.midY),
                           anchor: .center,
                           proposal: ProposedViewSize(bounds.size))
                view.update(transform: .identity)
                if sharedContext.needsLayout == false {
                    self.onViewLayoutUpdated()
                }
            }
            view.update(tick: tick, delta: delta, date: date)
        }
        
        self.auxiliaryWindows.forEach {
            let window = $0.window
            window.updateView(tick: tick, delta: delta, date: date)
        }
    }
    
    func drawFrame(_ context: GraphicsContext, offset: CGPoint) {
        if let view, view.isValid {
            let frame = view.frame.offsetBy(dx: offset.x, dy: offset.y)
            view.drawView(frame: frame, context: context)
        }
        
        self.auxiliaryWindows.forEach {
            let window = $0.window
            let offset = $0.offset + offset
            if let view = window.view, let filter = $0.filter {
                var context = context
                let frame = view.frame.offsetBy(dx: offset.x, dy: offset.y)
                let path = Rectangle().path(in: frame)
                context.addFilter(filter)
                context.fill(path, with: .color($0.color))
            }
            window.drawFrame(context, offset: offset)
        }
    }

    private func runUpdateTask() -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { @MainActor @Sendable [weak self] in
            Log.info("WindowContext<\(Content.self)> update task is started.")
            var tickCounter = TickCounter.now
            
            var contentBounds: CGRect = .null
            var contentScaleFactor: CGFloat = 1
            var renderTargets: GraphicsContext.RenderTargets? = nil
            
            //let clearColor = VVD.Color(rgba8: (245, 242, 241, 255))
            let clearColor = VVD.Color(rgba8: (255, 255, 241, 255))
            
            var additionalDeltaTimes: Double = 0.0
            
            mainLoop: while true {
                guard let self = self else { break }
                if Task.isCancelled { break }
                
                let swapChain = self.swapChain
                let (state, config) = self.stateConfig.withLock {
                    ($0.state, $0.config)
                }
                
                let delta = tickCounter.reset() + additionalDeltaTimes
                let tick = tickCounter.timestamp
                let date = Date(timeIntervalSinceNow: 0)
                additionalDeltaTimes = 0.0
                
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
                    additionalDeltaTimes = delta
                    let frameInterval = config.inactiveFrameInterval
                    repeat {
                        if Task.isCancelled { break mainLoop }
                        await Task.yield()
                    } while tickCounter.elapsed < frameInterval
                    continue
                }

                if state.bounds != contentBounds || state.contentScaleFactor != contentScaleFactor {
                    if state.contentScaleFactor != contentScaleFactor {
                        sharedContext.contentScaleFactor = state.contentScaleFactor
                        self.environment.displayScale = state.contentScaleFactor
                        view.updateEnvironment(self.environment)
                        self.sharedContext.viewsNeedToReloadResources = [.init(view)]
                    }
                    
                    contentBounds = state.bounds
                    contentScaleFactor = state.contentScaleFactor

                    let bounds = state.bounds.standardized
                    sharedContext.contentBounds = bounds
                    sharedContext.contentScaleFactor = state.contentScaleFactor
                    sharedContext.needsLayout = true
                }
                
                self.updateView(tick: tick, delta: delta, date: date)
                
                var swapChainToPresent: SwapChain? = nil
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
                            environment: self.environment,
                            viewport: CGRect(x: 0, y: 0,
                                             width: backBuffer.width,
                                             height: backBuffer.height),
                            contentOffset: .zero,
                            contentScaleFactor: state.contentScaleFactor,
                            renderTargets: renderTargets,
                            commandBuffer: commandBuffer) {
                            
                            context.clear(with: clearColor)
                            self.drawFrame(context, offset: state.bounds.origin)
                            
                            if let rp = context.beginRenderPass(descriptor: renderPass,
                                                                viewport: context.viewport) {
                                context.encodeDrawTextureCommand(
                                    renderPass: rp,
                                    texture: context.backdrop,
                                    frame: state.bounds,
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
                        swapChainToPresent = swapChain
                    }
                }

                let frameInterval = state.activated ? config.activeFrameInterval : config.inactiveFrameInterval
                let minTimeOfBusyState = state.activated ? 0.008 : 0.0
                repeat {
                    if Task.isCancelled { break mainLoop }
                    await Task.yield()
                } while tickCounter.elapsed < frameInterval - minTimeOfBusyState
                
                // It's time to busy wait.
                while tickCounter.elapsed < frameInterval {
                    if Task.isCancelled { break mainLoop }
                    Platform.threadYield()
                }
                
                if let swapChain = swapChainToPresent {
                    _ = swapChain.present()
                }
            }
            Log.info("WindowContext<\(Content.self)> update task is finished.")
        }
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

            if let window {
                self.onWindowClosing(window)
            }

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
        _=self.handleKeyboardEvent(event: event)
    }
    
    @MainActor
    func onMouseEvent(event: MouseEvent) {
        if event.type == .wheel {
            _=self.handleMouseWheel(at: event.location, delta: event.delta)
        } else {
            _=self.handleMouseEvent(event: event)
        }
    }
    
    private var _lastKeyboardEventHandler: ObjectIdentifier? = nil
    private var _lastMouseEventHandler: ObjectIdentifier? = nil

    func handleKeyboardEvent(event: KeyboardEvent) -> Bool {
        let handleEvent = { (event: KeyboardEvent) -> Bool in
            
            if let window = self.window, window !== event.window {
                return false
            }

            Log.debug("WindowContext.onKeyboardEvent: \(event)")
            if let focusedView = self.sharedContext.focusedViews[event.deviceID]?.value {
                return focusedView.processKeyboardEvent(type: event.type,
                                                        deviceID: event.deviceID,
                                                        key: event.key,
                                                        text: event.text)
            }
            return false
        }

        var handlers = self.auxiliaryWindows.reversed().map {
            let window = $0.window
            return (id: ObjectIdentifier(window),
                    action: { (event: KeyboardEvent) -> Bool in
                if let handler = window as? WindowInputEventHandler {
                    return handler.handleKeyboardEvent(event: event)
                }
                return false
            })
        }
        handlers.append( (id: ObjectIdentifier(self), action: handleEvent))

        if let _lastKeyboardEventHandler {
            if let index = handlers.firstIndex(where: {
                _lastKeyboardEventHandler == $0.id
            }) {
                let tmp = handlers.remove(at: index)
                handlers.insert(tmp, at: 0)
            }
        }
        for handler in handlers {
            if handler.action(event) {
                _lastKeyboardEventHandler = handler.id
                return true
            }
        }
        _lastKeyboardEventHandler = nil
        return false
    }
    
    func handleMouseEvent(event: MouseEvent) -> Bool {
        let handleEvent = { (event: MouseEvent) -> Bool in
            
            if let window = self.window, window !== event.window {
                return false
            }
            if event.type != .move && event.type != .pointing {
                //Log.debug("WindowContext.onMouseEvent: \(event)")
            }
            if event.type == .wheel {
                return false
            }

            guard let view = self.view else { return false }

            var gestureHandlers = self.sharedContext.gestureHandlers
            defer {
                self.sharedContext.gestureHandlers = gestureHandlers
            }

            if gestureHandlers.isEmpty {
                if event.type == .buttonDown {
                    let location = event.location.applying(view.transformToContainer.inverted())
                    let outputs = view.gestureHandlers(at: location)
                    gestureHandlers = outputs.highPriorityGestures + outputs.gestures + outputs.simultaneousGestures

                    if self.filterGestureTypes {
                        var typeFilter = self.allowedGestureTypes
                        gestureHandlers = gestureHandlers.filter {
                            let include = typeFilter.contains($0.type)
                            typeFilter = $0.setTypeFilter(typeFilter)
                            return include
                        }
                    }
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
            if gestureHandlers.isEmpty {
                return false
            }

            // before processing the event, copy the handlers to the shared context
            // so that subviews can access them.
            self.sharedContext.gestureHandlers = gestureHandlers

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
            return gestureHandlers.isEmpty == false
        }

        var handlers = self.auxiliaryWindows.reversed().map {
            let window = $0.window
            let offset = $0.offset
            return (id: ObjectIdentifier(window),
                    action: { (event: MouseEvent) -> Bool in
                if let handler = window as? WindowInputEventHandler {
                    var event = event
                    event.location -= offset
                    return handler.handleMouseEvent(event: event)
                }
                return false
            })
        }
        handlers.append((id: ObjectIdentifier(self), action: handleEvent))

        if let _lastMouseEventHandler {
            if let index = handlers.firstIndex(where: {
                _lastMouseEventHandler == $0.id
            }) {
                let tmp = handlers.remove(at: index)
                handlers.insert(tmp, at: 0)
            }
        }
        for handler in handlers {
            if handler.action(event) {
                _lastMouseEventHandler = handler.id
                return true
            }
        }
        _lastMouseEventHandler = nil
        return false
    }

    func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        for aux in self.auxiliaryWindows.reversed() {
            if let handler = aux.window as? WindowInputEventHandler {
                let loc = location - aux.offset
                if handler.handleMouseWheel(at: loc, delta: delta) {
                    return true
                }
            }
        }
        
        if let view {
            return view.handleMouseWheel(at: location, delta: delta)
        }
        return false
    }

    func onWindowCreated(_: Window) {}
    func onWindowClosing(_: Window) {}
    func onSwapchainCreated(_: SwapChain) {}
    func onViewLoaded() {}
    func onViewLayoutUpdated() {}

    func addAuxiliaryWindow(_ window: some WindowContext, position: CGPoint) -> Bool {
        if let index = self.auxiliaryWindows.firstIndex(where: { $0.window === window }) {
            self.auxiliaryWindows.remove(at: index)
        }
        let filter = GraphicsContext.Filter.shadow(radius: 4.0, x: 0, y: 0)
        let aux = AuxiliaryWindow(window: window, offset: position, color: .white, filter: filter)
        self.auxiliaryWindows.append(aux)
        return true
    }
    
    func removeAuxiliaryWindow(_ window: some WindowContext) {
        if let index = self.auxiliaryWindows.firstIndex(where: { $0.window === window }) {
            self.auxiliaryWindows.remove(at: index)
        }
    }
}
