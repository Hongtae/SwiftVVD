//
//  File: WindowContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

typealias PlatformWindow = VVD.Window
typealias PlatformWindowStyle = VVD.WindowStyle

protocol WindowContext: AnyObject {
    var scene: SceneContext { get }
    var window: (any PlatformWindow)? { get }
    var isValid: Bool { get }

    func updateContent()

    func updateView(tick: UInt64, delta: Double, date: Date)
    func drawFrame(_: GraphicsContext, offset: CGPoint)

    @MainActor
    func makeWindow() -> (any PlatformWindow)?
}

protocol WindowInputEventHandler {
    @discardableResult
    func handleKeyboardEvent(event: KeyboardEvent) -> Bool
    @discardableResult
    func handleMouseEvent(event: MouseEvent) -> Bool
    @discardableResult
    func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool
    @discardableResult
    func handleMouseHover(at location: CGPoint, deviceID: Int, isTopMost: Bool) -> Bool

    func resetGestureHandlers()
}

class GenericWindowContext<Content>: WindowContext,
                                     AuxiliaryWindowHost,
                                     ModalWindowHost,
                                     WindowInputEventHandler,
                                     WindowDelegate,
                                     @unchecked Sendable where Content: View {
    private(set) var swapChain: SwapChain?
    private(set) var window: (any PlatformWindow)?

    var view: ViewContext?
    let content: _GraphValue<Content>
    var environment: EnvironmentValues
    var sharedContext: SharedContext
    var scene: SceneContext {
        sharedContext.scene
    }
    var title: String { "" }
    var style: PlatformWindowStyle { .genericWindow }

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
        var backgroundColor: VVD.Color = .white
        var drawDebugInfo: _DrawDebug.Info = []
    }

    var state: State {
        stateConfig.withLock { $0.state }
    }
    var config: Configuration {
        get { stateConfig.withLock { $0.config } }
        set { stateConfig.withLock { $0.config = newValue } }
    }

    private let stateConfig = Mutex<(state: State, config: Configuration)>((state: State(), config: Configuration()))
    private var task: Task<Void, Never>?

    private struct AuxiliaryWindow: @unchecked Sendable {
        weak var client: AuxiliaryWindowClient?
        var frame: CGRect? = nil // cached frame
    }
    private let auxiliaryWindows = Mutex<[AuxiliaryWindow]>([])

    private struct ModalWindow: @unchecked Sendable {
        weak var client: ModalWindowClient?
        var frame: CGRect? = nil // cached frame
        var initiated: Bool = false
    }
    private let modalWindows = Mutex<[ModalWindow]>([])

    // key-based slot registry for modal dedup — covers both platform and overlay modals.
    // ModalWindowSceneContext is @unchecked Sendable; claimModalSlot/releaseModalSlot are
    // always called on the main thread (same pattern as modalContext in ModalWindowSceneContext).
    private let modalSlots = Mutex<[AnyHashable: AnyWeakObject]>([:])

    init(content: _GraphValue<Content>, scene: SceneContext) {
        let sceneInputs = scene.inputs
        self.content = content
        self.environment = sceneInputs.environment
        self.sharedContext = SharedContext(scene: scene)
        self.sharedContext._window = self

        var properties = PropertyList()
        properties.setValue(VStackLayout(), forKey: DefaultLayoutProperty.self)
        properties.setValue(EdgeInsets(_all: 16), forKey: DefaultPaddingEdgeInsetsProperty.self)

        let baseInputs = _GraphInputs(sharedContext: self.sharedContext,
                                      properties: properties,
                                      environment: sceneInputs.environment,
                                      modifiers: sceneInputs.modifiers,
                                      _modifierTypeGraphs: sceneInputs._modifierTypeGraphs)
        let inputs = _ViewInputs.inputs(with: baseInputs)
        let outputs = Content._makeView(view: content, inputs: inputs)
        self.view = outputs.view?.makeView()
    }

    deinit {
        //Log.debug("WindowContext<\(Content.self)> deinit")
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
    func makeWindow() -> (any PlatformWindow)? {
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
        if let modifier = self.scene.inputs.modifierTypeGraph(of: _UpdateFrameRate.self) {
            if let frameRate = self.scene.value(atPath: modifier) {
                let active = 1.0 / max(frameRate.active, 1.0)
                let inactive = 1.0 / max(frameRate.inactive, 1.0)
                self.stateConfig.withLock {
                    $0.config.activeFrameInterval = active
                    $0.config.inactiveFrameInterval = inactive
                }
            }
        }
        if let modifier = self.scene.inputs.modifierTypeGraph(of: _DrawDebug.self) {
            if let drawDebug = self.scene.value(atPath: modifier) {
                self.stateConfig.withLock {
                    $0.config.drawDebugInfo = drawDebug.selectedValues
                }
            }
        }
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

        // filter valid clients
        let clients = self.auxiliaryWindows.withLock {
            let clients = $0.compactMap(\.client)
            $0 = $0.filter { $0.client != nil }
            return clients
        }
        // update clients
        clients.forEach {
            $0.updateAuxiliaryWindowContent(tick: tick, delta: delta, date: date)
        }
        // update frame
        self.auxiliaryWindows.withLock {
            $0.updateEach { window in
                window.frame = window.client?.auxiliaryWindowFrame()
            }
        }

        var modalClient: ModalWindowClient? = nil
        var modalClientInitiated: Bool = false
        self.modalWindows.withLock { windows in
            windows = windows.filter { $0.client != nil }
            if let modalWindow = windows.first {
                modalClient = modalWindow.client
                modalClientInitiated = modalWindow.initiated
            }
        }

        if let modalClient {
            if modalClientInitiated == false {
                modalClient.onModalSessionInitiated()
                modalClientInitiated = true
            }
            modalClient.updateModalWindowContent(tick: tick, delta: delta, date: date)
            self.modalWindows.withLock {
                if $0.count > 0 {
                    $0[0].initiated = modalClientInitiated
                    $0[0].frame = modalClient.modalWindowFrame()
                }
            }
        }
    }

    func drawFrame(_ context: GraphicsContext, offset: CGPoint) {
        if let view, view.isValid {
            let frame = view.frame.offsetBy(dx: offset.x, dy: offset.y)
            view.drawView(frame: frame, context: context)
        }

        self.auxClients.forEach {
            $0.drawAuxiliaryWindowBackground(offset: offset, with: context)
            $0.drawAuxiliaryWindowContent(offset: offset, with: context)
            $0.drawAuxiliaryWindowOverlay(offset: offset, with: context)
        }

        let modalClient = self.modalWindows.withLock { $0.first?.client }
        if let modalClient {
            modalClient.drawModalWindowBackground(offset: offset, with: context)
            modalClient.drawModalWindowContent(offset: offset, with: context)
            modalClient.drawModalWindowOverlay(offset: offset, with: context)
        }
    }

    private func runUpdateTask() -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { @MainActor @Sendable [weak self] in
            Log.info("WindowContext<\(Content.self)> update task is started.")

            var timestamp = DispatchTime.now()

            let elapsed = {
                let now = DispatchTime.now()
                let delta = Double(now.uptimeNanoseconds - timestamp.uptimeNanoseconds)
                return delta * 0.000_000_001
            }
            let resetTimestamp = {
                let now = DispatchTime.now()
                let delta = Double(now.uptimeNanoseconds - timestamp.uptimeNanoseconds)
                timestamp = now
                return delta * 0.000_000_001
            }

            var contentBounds: CGRect = .null
            var contentScaleFactor: CGFloat = 1
            var renderTargets: GraphicsContext.RenderTargets? = nil

            var additionalDeltaTimes: Double = 0.0
            let debugDrawEnabled = self?.style.contains(.auxiliaryWindow) == false

            mainLoop: while true {
                guard let self = self else { break }
                if Task.isCancelled { break }

                let swapChain = self.swapChain
                let (state, config) = self.stateConfig.withLock {
                    ($0.state, $0.config)
                }

                let clearColor = config.backgroundColor

                let delta = resetTimestamp() + additionalDeltaTimes
                let tick = timestamp.uptimeNanoseconds
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
                    } while elapsed() < frameInterval
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
                            
                            if debugDrawEnabled {
                                var offset = CGPoint(x: 5, y: 5)
                                let drawText = { (text: Text) in
                                    let resolvedText = context.resolve(text)
                                    context.draw(resolvedText, at: offset, anchor: .topLeading)
                                    offset.y += resolvedText.measure().height
                                }

                                if config.drawDebugInfo.contains(.fps) {
                                    let d = max(delta, 0.001001) // up to 999
                                    drawText(Text(String(format: "%.1f FPS (%f)", 1.0 / d, delta)))
                                }
                                if config.drawDebugInfo.contains(.thread) {
                                    drawText(Text("thread: \(Platform.currentThreadID())"))
                                }
                                if config.drawDebugInfo.contains(.queue) {
                                    drawText(Text("dispatch-queue: \(isMainQueue() ? "main" : "global")"))
                                }
                                if config.drawDebugInfo.contains(.appState) {
                                    drawText(Text("app-active: \(appContext?.isActive ?? false)"))
                                }
                                if config.drawDebugInfo.contains(.windowState) {
                                    drawText(Text("foreground: \(state.activated)"))
                                }
                            }

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
                        _=swapChain.present()
                    }
                }

                let frameInterval = state.activated ? config.activeFrameInterval : config.inactiveFrameInterval
                let timeForBusyWait = state.activated ? 0.001 : 0.0

                repeat {
                    if Task.isCancelled { break mainLoop }
                    await Task.yield()
                } while elapsed() < frameInterval - timeForBusyWait

                // busy waiting, remaining time is too short to yield.
                while elapsed() < frameInterval {
                    if Task.isCancelled { break mainLoop }
                    Platform.threadYield()
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
            self.auxClients.forEach {
                $0.onHostWindowClosed()
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
            self.auxClients.forEach {
                $0.onHostWindowActivated()
            }
        case .inactivated:
            releaseEventHandlers()
            self.stateConfig.withLock {
                $0.state.activated = false
            }
            self.auxClients.forEach {
                $0.onHostWindowInactivated()
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
            self.auxClients.forEach {
                $0.onHostWindowMoved()
            }
        case .update:
            break
        }
    }

    @MainActor
    func onKeyboardEvent(event: KeyboardEvent) {
        let modalClient = self.modalWindows.withLock { $0.first?.client }
        if let modalClient {
            modalClient.modalWindowInputEventHandler()?
                .handleKeyboardEvent(event: event)
        } else {
            self.handleKeyboardEvent(event: event)
        }
    }

    @MainActor
    func onMouseEvent(event: MouseEvent) {
        let modalWindow = self.modalWindows.withLock { $0.first }
        if let modalClient = modalWindow?.client,
           let modalFrame = modalWindow?.frame {

            var updateHover = false
            if let handler = modalClient.modalWindowInputEventHandler() {
                var event = event
                event.location -= modalFrame.origin

                if event.type == .wheel {
                    handler.handleMouseWheel(at: event.location,
                                             delta: event.delta)                
                } else {
                    if handler.handleMouseEvent(event: event) == false {
                        if event.type == .move || event.type == .buttonUp {
                            handler.handleMouseHover(at: event.location,
                                                     deviceID: event.deviceID,
                                                     isTopMost: true)
                            updateHover = true
                        }
                    }
                }
            }
            if updateHover {
                self.handleMouseHover(at: event.location,
                                      deviceID: event.deviceID,
                                      isTopMost: false)
            }
            return
        }

        if event.type == .wheel {
            self.handleMouseWheel(at: event.location, delta: event.delta)
        } else {
            self.handleMouseEvent(event: event)
            
            if event.type == .move || event.type == .buttonUp {
                self.handleMouseHover(at: event.location,
                                      deviceID: event.deviceID,
                                      isTopMost: true)
            }
        }
    }

    private var _lastKeyboardEventHandler: ObjectIdentifier? = nil
    private var _lastMouseEventHandler: ObjectIdentifier? = nil

    @discardableResult
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

        var handlers = self.auxiliaryWindows.withLock{
            $0.reversed().compactMap {
                if let client = $0.client {
                    return (id: ObjectIdentifier(client),
                            action: { (event: KeyboardEvent) -> Bool in
                        if let handler = client.auxiliaryWindowInputEventHandler() {
                            return handler.handleKeyboardEvent(event: event)
                        }
                        return false
                    })
                }
                return nil
            }
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

    @discardableResult
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

            let activeHandlers = { (states: _GestureHandler.State...) -> [_GestureHandler] in
                gestureHandlers.compactMap {
                    if states.contains($0.state) {
                        return $0
                    }
                    return nil
                }
            }

            gestureHandlers = activeHandlers(.ready, .processing)
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

            if event.type == .move {
                gestureHandlers = activeHandlers(.ready, .processing)
            } else {
                gestureHandlers = activeHandlers(.processing)
            }
            return gestureHandlers.isEmpty == false
        }

        var handlers = self.auxiliaryWindows.withLock {
            $0.reversed().compactMap {
                if let client = $0.client, let frame = $0.frame {
                    return (target: client as AnyObject,
                            action: { (event: MouseEvent) -> Bool in
                        if client.auxiliaryWindowHitTest(event.location) {
                            if let handler = client.auxiliaryWindowInputEventHandler() {
                                var event = event
                                event.location -= frame.origin
                                handler.handleMouseEvent(event: event)
                            }
                            return true // don't pass event to other aux windows
                        }
                        return false
                    })
                }
                return nil
            }
        }
        handlers.append((target: self as AnyObject, action: handleEvent))

        var clients: [AuxiliaryWindowClient] = []
        if event.type == .buttonDown {
            clients = self.auxClients
        }
        
        if let _lastMouseEventHandler {
            if let index = handlers.firstIndex(where: {
                _lastMouseEventHandler == ObjectIdentifier($0.target)
            }) {
                let tmp = handlers.remove(at: index)
                handlers.insert(tmp, at: 0)
            }
        }
        for handler in handlers {
            if handler.action(event) {
                _lastMouseEventHandler = ObjectIdentifier(handler.target)
                clients.forEach {
                    $0.initiatedGesture(from: handler.target,
                                        location: event.location) 
                }
                return true
            }
        }
        _lastMouseEventHandler = nil
        clients.forEach {
            $0.initiatedGesture(from: nil, location: event.location) 
        }
        return false
    }

    @discardableResult
    func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        for aux in self.auxiliaryWindows.withLock({ $0.reversed() }) {
            if let offset = aux.frame?.origin {
                if let handler = aux.client?.auxiliaryWindowInputEventHandler() {
                    let loc = location - offset
                    if handler.handleMouseWheel(at: loc, delta: delta) {
                        return true
                    }
                }
            }
        }

        if let view {
            let location = location.applying(view.transformToContainer.inverted())
            return view.handleMouseWheel(at: location, delta: delta)
        }
        return false
    }

    @discardableResult
    func handleMouseHover(at location: CGPoint, deviceID: Int, isTopMost: Bool) -> Bool {
        var topMost = isTopMost
        self.auxiliaryWindows.withLock({ $0.reversed() }).forEach { aux in
            if let offset = aux.frame?.origin {
                if let handler = aux.client?.auxiliaryWindowInputEventHandler() {
                    let loc = location - offset
                    if handler.handleMouseHover(at: loc,
                                                deviceID: deviceID,
                                                isTopMost: topMost) {
                        topMost = false
                    }
                }
            }
            if topMost {
                if let hitTest = aux.client?.auxiliaryWindowHitTest(location) {
                    topMost = !hitTest
                }
            }
        }

        if let view {
            let location = location.applying(view.transformToContainer.inverted())
            if view.handleMouseHover(at: location, deviceID: deviceID, isTopMost: topMost) {
                topMost = false
            }
        }
        return isTopMost != topMost
    }

    func resetGestureHandlers() {
        let handlers = self.sharedContext.gestureHandlers
        handlers.forEach { $0.reset() }
        self.sharedContext.gestureHandlers.removeAll()
    }

    func onWindowCreated(_: any PlatformWindow) {}

    func onWindowClosing(_: any PlatformWindow) {
        self.auxClients.forEach {
            $0.onHostWindowClosed()
        }
    }

    func onSwapchainCreated(_: SwapChain) {}
    func onViewLoaded() {}
    func onViewLayoutUpdated() {}

    func addAuxiliaryWindow(_ client: AuxiliaryWindowClient) -> Bool {
        let aux = AuxiliaryWindow(client: client)

        self.auxiliaryWindows.withLock { auxiliaryWindows in
            if let index = auxiliaryWindows.firstIndex(where: { $0.client === client }) {
                auxiliaryWindows.remove(at: index)
            }
            auxiliaryWindows = auxiliaryWindows.filter { $0.client != nil }
            auxiliaryWindows.append(aux)
        }
        return true
    }

    func removeAuxiliaryWindow(_ client: AuxiliaryWindowClient) {
        self.auxiliaryWindows.withLock { auxiliaryWindows in
            if let index = auxiliaryWindows.firstIndex(where: { $0.client === client }) {
                auxiliaryWindows.remove(at: index)
            }
        }
    }

    func dismissAllAuxiliaryWindows() {
        let clients = self.auxiliaryWindows.withLock { aux in
            defer { aux.removeAll() }
            return aux.compactMap(\.client)
        }
        clients.forEach { $0.onHostWindowClosed() }
    }

    var auxClients: [AuxiliaryWindowClient] {
        self.auxiliaryWindows.withLock { $0.compactMap(\.client) }
    }

    var modalClients: [ModalWindowClient] {
        self.modalWindows.withLock { $0.compactMap(\.client) }
    }

    func claimModalSlot(key: AnyHashable, client: ModalWindowClient) -> Bool {
        let key = UnsafeBox(key)
        let slot = UnsafeBox(client)
        return modalSlots.withLock { slots in
            // stale cleanup
            slots = slots.filter { _, value in value.value != nil }
            let key = key.value
            if slots[key]?.value != nil {
                return false  // already occupied
            }
            slots[key] = AnyWeakObject(slot.value as AnyObject)
            return true
        }
    }

    func releaseModalSlot(key: AnyHashable) {
        let key = UnsafeBox(key)
        modalSlots.withLock { slots in
            let key = key.value
            slots.removeValue(forKey: key)
        }
    }

    func addModalWindow(_ client: ModalWindowClient) -> Bool {
        var prepareForFirstModal = false
        let modal = ModalWindow(client: client)

        self.modalWindows.withLock { modalWindows in
            prepareForFirstModal = modalWindows.isEmpty

            if modalWindows.contains(where: { $0.client === client }) {
                return // already added
            }
            modalWindows.append(modal)
        }

        if prepareForFirstModal {
            self.resetGestureHandlers()
            self.handleMouseHover(at: .zero, deviceID: 0, isTopMost: false)
        }
        return true
    }

    func detachModalWindow(_ client: ModalWindowClient) {
        self.modalWindows.withLock { modalWindows in
            modalWindows.removeAll { $0.client === client }
        }
    }

    func removeModalWindow(_ client: ModalWindowClient) {
        var initiated: Bool? = nil
        self.modalWindows.withLock { modalWindows in
            if let index = modalWindows.firstIndex(where: {
                $0.client === client }) {

                initiated = modalWindows[index].initiated
                modalWindows.remove(at: index)
            }
        }
        guard let initiated else {
            return  // client was not found
        }
        if initiated {
            client.onModalSessionDismissedByParent()
        } else {
            client.onModalSessionCancelled()
        }
    }

    func dismissAllModalWindows() {
        let clients = self.modalWindows.withLock { modals in
            defer { modals.removeAll() }
            return modals.compactMap {
                modal -> (client: ModalWindowClient, initiated: Bool)? in
                guard let client = modal.client else { return nil }
                return (client, modal.initiated)
            }
        }
        for (client, initiated) in clients {
            if initiated {
                client.onModalSessionDismissedByParent()
            } else {
                client.onModalSessionCancelled()
            }
        }
    }

    func shouldClose(window: any PlatformWindow) -> Bool {
        self.modalClients.isEmpty
    }
}

public struct _WindowContextDebugDraw: EnvironmentKey {
    public static var defaultValue: Bool { false }
}

public extension EnvironmentValues {
    var _windowContextDebugDraw: Bool {
        get { self[_WindowContextDebugDraw.self] }
        set { self[_WindowContextDebugDraw.self] = newValue }
    }
}
