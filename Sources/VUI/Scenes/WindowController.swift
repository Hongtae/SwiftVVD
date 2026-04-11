//
//  File: WindowController.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

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

// WindowController — owns ViewGraph and drives rendering + event dispatch.
// Non-generic: the Content type is used only at init for AG wiring, then discarded.
// Optionally owns a WindowContext — created lazily on the first makeWindow() call.
// Overlay-mode aux/modal controllers never call makeWindow(), so windowContext stays nil.
class WindowController: AuxiliaryWindowHost, ModalWindowHost,
                        WindowInputEventHandler, WindowDelegate,
                        ViewRendererHost, ViewGraphRootValueUpdater,
                        ViewGraphRenderDelegate,
                        @unchecked Sendable {

    var windowContext: WindowContext?

    private var _titleGraph: _GraphValue<Text>?
    private var _titleString: String = ""
    private var _style: PlatformWindowStyle

    var environment: EnvironmentValues
    var sharedContext: SharedContext
    let sceneResources: SceneResources

    // gestureGraph — owned directly by WindowController.
    // GestureGraph is the window-level coordinator.
    var gestureGraph: GestureGraph?

    // viewGraph — owns the view-tree AttributeGraph (GraphHost.data) and gesture routing.
    // moved from `let graph: AttributeGraph` + scattered input/output attrs.
    // IUO because gestureGraph must be created and wired before ViewGraph.init runs _makeView.
    var viewGraph: ViewGraph { _viewGraph }
    private var _viewGraph: ViewGraph!

    var date: Date  // render loop timing reference (animation)

    var title: String { _titleString }
    var style: PlatformWindowStyle { _style }

    var sceneConfiguration: SceneConfiguration = SceneConfiguration()
    var filterGestureTypes: Bool = true
    var allowedGestureTypes: _PrimitiveGestureTypes = .all

    var isValid: Bool { viewGraph.isValid }

    let scene: WindowKey

    var window: (any PlatformWindow)? { windowContext?.window }

    private var _config: WindowContext.Configuration = WindowContext.Configuration()
    var config: WindowContext.Configuration {
        get { windowContext?.config ?? _config }
        set {
            _config = newValue
            windowContext?.config = newValue
        }
    }

    enum InputEvent: @unchecked Sendable {
        case keyboard(KeyboardEvent)
        case mouse(MouseEvent)
    }
    private let inputEvents = Mutex<[InputEvent]>([])

    // ViewRendererHost / ViewGraphOwner stored state.
    // WindowController tracks its own owner-side state separately from ViewGraph's internal state,
    var currentTimestamp: Time = Time(seconds: 0)
    var valuesNeedingUpdate: ViewGraphRootValues = []
    var renderingPhase: ViewRenderingPhase = ViewRenderingPhase()
    var externalUpdateCount: Int = 0

    // ViewRendererHost
    var responderNode: ResponderNode? { gestureGraph?.rootResponder }

    init<Content: View>(content: _GraphValue<Content>,
                        title: _GraphValue<Text>? = nil,
                        style: PlatformWindowStyle = .genericWindow,
                        scene: WindowKey) {
        self._titleGraph = title
        self._style = style
        self.environment = EnvironmentValues()
        self.sharedContext = SharedContext()
        self.sceneResources = SceneResources()
        self.windowContext = nil
        self.scene = scene

        // Extract current values from the caller's AG context (AppGraph).
        // init must be called from within an active AG context (e.g. AppGraph.syncWindowControllers).
        guard AttributeGraph.current != nil else {
            fatalError("\(Self.self).init called outside an active AttributeGraph context.")
        }
        let contentValue = content._attribute.value
        if let titleText = title.map({ $0._attribute.value }) {
            self._titleString = titleText._resolveText(in: EnvironmentValues())
        }
        self.date = .now

        // Create GestureGraph first — it owns an independent AG.
        // GraphHost.Data.init() internally for an independent AG. ViewGraph's AG is separate.
        // WindowController owns both GestureGraph and ViewGraph.
        self.gestureGraph = GestureGraph()
        // Wire rendererHost back-reference before ViewGraph.init — GestureResponder.init
        // reads viewGraph.rendererHost?.gestureGraph during _makeView.
        self.gestureGraph!.rendererHost = self

        // Create ViewGraph — does full AG wiring including _makeView which may create GestureResponders.
        // rendererHost: self must be set on GestureGraph before this call.
        self._viewGraph = ViewGraph(rootViewType: Content.self, content: contentValue, rendererHost: self)
        
        // Wire ViewGraph delegate slots.
        // renderDelegate: WindowController provides contentsScale, opaqueBackground, and
        //   render thread handling. Implemented below (ViewGraphRenderDelegate).
        self.viewGraph.renderDelegate = self
        // updateDelegate: WindowController provides root value updates (size, env, etc.).
        //   updateSize() / updateEnvironment() etc. called inline in updateView for now.
        //   Full invalidateProperties(_:mayDeferUpdate:) wiring is a future step.
        self.viewGraph.updateDelegate = self
        // self.viewGraph.delegate = self
    }

    deinit {
        sharedContext.resourceData.removeAll()
    }

    @MainActor
    func makeWindow() -> (any PlatformWindow)? {
        let isNew = windowContext?.window == nil
        if windowContext == nil {
            let ctx = WindowContext(sceneResources: self.sceneResources)
            ctx.config = self._config
            ctx.updateFrame = { [weak self] tick, delta, date, size, drawFrame, withGC in
                self?.updateFrame(tick: tick, delta: delta, date: date,
                                  contentSize: size, shouldDrawFrame: drawFrame,
                                  withGC)
            }
            self.windowContext = ctx
        }
        guard let ctx = windowContext else { return nil }
        let window = ctx.makeWindow(title: self.title, style: self.style, delegate: self)
        if isNew, let window {
            window.addEventObserver(self) { [weak self] (event: WindowEvent) in
                self?.handleWindowEvent(event: event)
            }
            window.addEventObserver(self) { [weak self] (event: KeyboardEvent) in
                self?.inputEvents.withLock { events in
                    events.append(.keyboard(event))
                }
            }
            window.addEventObserver(self) { [weak self] (event: MouseEvent) in
                self?.inputEvents.withLock { events in
                    events.append(.mouse(event))
                }
            }
            self.onWindowCreated(window)
        }
        return window
    }

    private var viewChangedWhileDrawing: Bool = false
    private var cachedContentSize: CGSize = .zero

    func updateFrame(tick: UInt64, delta: Double, date: Date,
                     contentSize: CGSize, shouldDrawFrame: Bool,
                     _ withGC: WindowContext.WithGraphicsContext) {

        // Pull render context from delegate (ViewGraphRenderDelegate).
        // contentsScale: HiDPI scale factor for the current display.
        // opaqueBackground: whether the background is fully opaque (skip alpha clear).
        // calls this once per frame before updateOutputs/render.
        var renderCtx = ViewGraphRenderContext(contentsScale: 1.0, opaqueBackground: false)
        viewGraph.renderDelegate?.updateRenderContext(&renderCtx)
        // TODO: propagate renderCtx.contentsScale to draw calls (HiDPI)

        var redraw = false
        self.updateView(tick: tick, delta: delta, date: date,
                        contentSize: contentSize, redraw: &redraw, withGC)

        if redraw || shouldDrawFrame {
            let clearColor = config.backgroundColor
            withGC(true) { context in
                context.clear(with: clearColor)
                self.drawFrame(offset: .zero, context)
            }
        }
    }

    func updateView(tick: UInt64, delta: Double, date: Date,
                    contentSize: CGSize, redraw: inout Bool,
                    _ withGC: WindowContext.WithGraphicsContext) {
        guard let rootLayoutComputer = viewGraph.rootLayoutComputer else { return }

        let time = Time(seconds: date.timeIntervalSince(self.date))

        // Detect size changes and set the dirty bit.
        let sizeChanged = (contentSize != cachedContentSize)
        if sizeChanged {
            cachedContentSize = contentSize
            valuesNeedingUpdate.insert(.size)
        }

        let changeSet = AttributeGraph.ChangeSet()
        AttributeGraph.$changeSet.withValue(changeSet) {

            // Drain platform input events before AG evaluation.
            let events = self.inputEvents.withLock { events in
                defer { events.removeAll() }
                return events
            }
            events.forEach {
                switch $0 {
                case .keyboard(let event): self.onKeyboardEvent(event: event)
                case .mouse(let event):    self.onMouseEvent(event: event)
                }
            }

            // updateOutputs handles dirty bits, flushes @State/@Observable, and evaluates AG.
            // Internally it performs data.withCurrent, inbox.drain, updateDelegate, and timeAttr.setValue.
            viewGraph.updateOutputs(at: time)

            // Resource loading requires GraphicsContext, so handle it separately after updateOutputs.
            viewGraph.data.withCurrent {
                if let resourceList = viewGraph.rootResourceList?.value,
                   !resourceList.items.isEmpty {
                    withGC(false) { context in
                        for task in resourceList.items {
                            task(context)
                        }
                    }
                    viewGraph.data.graph.inbox.drain()
                    viewGraph.data.graph.drainActions()
                }
            }

            // Layout placement determines the root view size and position after AG evaluation.
            viewGraph.data.withCurrent {
                let lc = rootLayoutComputer.value
                let proposal = ProposedViewSize(width: cachedContentSize.width,
                                               height: cachedContentSize.height)
                let center = CGPoint(x: cachedContentSize.width / 2,
                                     y: cachedContentSize.height / 2)
                lc.place(at: center, anchor: .center, proposal: proposal)
            }
        }
        redraw = !changeSet.ids.isEmpty || self.viewChangedWhileDrawing
        self.viewChangedWhileDrawing = false
    }

    func drawFrame(offset: CGPoint, _ context: GraphicsContext) {
        guard let rootDisplayList = viewGraph.rootDisplayList else { return }

        var context = context
        context.translateBy(x: offset.x, y: offset.y)

        viewGraph.data.withCurrent {
            let changeSet = AttributeGraph.ChangeSet()
            AttributeGraph.$changeSet.withValue(changeSet) {
                let displayList = rootDisplayList.value
                for item in displayList.items {
                    item(context)
                }
                for item in displayList.debugItems {
                    item(context)
                }
            }
            self.viewChangedWhileDrawing = !changeSet.ids.isEmpty
        }
    }

    func layoutBounds(_ bounds: CGRect) -> CGRect { bounds }

    func shouldClose(window: any PlatformWindow) -> Bool {
        modalClients.isEmpty
    }

    func onWindowCreated(_: any PlatformWindow) {}

    func onWindowClosing(_: any PlatformWindow) {
        self.auxClients.forEach { $0.onHostWindowClosed() }
    }

    func onViewLoaded() {}
    func onViewLayoutUpdated() {}

    @MainActor
    func handleWindowEvent(event: WindowEvent) {
        switch event.type {
        case .closed:
            DispatchQueue.main.async {
                appContext?.checkWindowActivities()
            }
            self.auxClients.forEach { $0.onHostWindowClosed() }

        case .hidden:
            self.sharedContext.focusedViews.removeAll()
            viewGraph.data.graph.inbox.enqueue {
                self.gestureGraph!.resetEvents()
            }
        case .activated:
            self.auxClients.forEach { $0.onHostWindowActivated() }

        case .inactivated:
            self.sharedContext.focusedViews.removeAll()
            viewGraph.data.graph.inbox.enqueue {
                self.gestureGraph!.resetEvents()
            }
            self.auxClients.forEach { $0.onHostWindowInactivated() }

        case .minimized:
            self.sharedContext.focusedViews.removeAll()
            viewGraph.data.graph.inbox.enqueue {
                self.gestureGraph!.resetEvents()
            }
        case .moved, .resized:
            self.auxClients.forEach { $0.onHostWindowMoved() }

        default:
            break
        }
    }

    func onKeyboardEvent(event: KeyboardEvent) {
        let modalClient = self.modalWindows.withLock { $0.first?.client }
        if let modalClient {
            modalClient.modalWindowInputEventHandler()?
                .handleKeyboardEvent(event: event)
        } else {
            self.handleKeyboardEvent(event: event)
        }
    }

    func onMouseEvent(event: MouseEvent) {
        let modalWindow = self.modalWindows.withLock { $0.first }
        if let modalClient = modalWindow?.client,
           let modalFrame = modalWindow?.frame {

            var updateHover = false
            if let handler = modalClient.modalWindowInputEventHandler() {
                var event = event
                event.location -= modalFrame.origin

                if event.type == .wheel {
                    handler.handleMouseWheel(at: event.location, delta: event.delta)
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
            if let window = self.window, window !== event.window { return false }
            Log.debug("WindowController.onKeyboardEvent: \(event)")
            if let _ = self.sharedContext.focusedViews[event.deviceID]?.value {
                fatalError("Implement with AG")
            }
            return false
        }

        var handlers = self.auxiliaryWindows.withLock {
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
        handlers.append((id: ObjectIdentifier(self), action: handleEvent))

        if let _lastKeyboardEventHandler,
           let index = handlers.firstIndex(where: { _lastKeyboardEventHandler == $0.id }) {
            let tmp = handlers.remove(at: index)
            handlers.insert(tmp, at: 0)
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
            if let window = self.window, window !== event.window { return false }
            if event.type == .wheel { return false }
            guard let gg = self.gestureGraph else { return false }

            // Route through EventBindingManager.sendDownstream.
            // Wrap as EventRecord -> eventBindingManager.sendDownstream -> GestureGraph.sendEvents.
            let record = EventRecord(event, at: self.currentTimestamp)
            let phase = gg.eventBindingManager.sendDownstream(record, host: gg)
            switch phase {
            case .active, .ended: return true
            default:              return false
            }
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
                            return true
                        }
                        return false
                    })
                }
                return nil
            }
        }
        handlers.append((target: self as AnyObject, action: handleEvent))

        var clients: [AuxiliaryWindowClient] = []
        if event.type == .buttonDown { clients = self.auxClients }

        if let _lastMouseEventHandler,
           let index = handlers.firstIndex(where: {
               _lastMouseEventHandler == ObjectIdentifier($0.target)
           }) {
            let tmp = handlers.remove(at: index)
            handlers.insert(tmp, at: 0)
        }
        for handler in handlers {
            if handler.action(event) {
                _lastMouseEventHandler = ObjectIdentifier(handler.target)
                clients.forEach { $0.initiatedGesture(from: handler.target, location: event.location) }
                return true
            }
        }
        _lastMouseEventHandler = nil
        clients.forEach { $0.initiatedGesture(from: nil, location: event.location) }
        return false
    }

    @discardableResult
    func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        for aux in self.auxiliaryWindows.withLock({ $0.reversed() }) {
            if let offset = aux.frame?.origin,
               let handler = aux.client?.auxiliaryWindowInputEventHandler() {
                let loc = location - offset
                if handler.handleMouseWheel(at: loc, delta: delta) { return true }
            }
        }
        return false
    }

    @discardableResult
    func handleMouseHover(at location: CGPoint, deviceID: Int, isTopMost: Bool) -> Bool {
        var topMost = isTopMost
        self.auxiliaryWindows.withLock({ $0.reversed() }).forEach { aux in
            if let offset = aux.frame?.origin,
               let handler = aux.client?.auxiliaryWindowInputEventHandler() {
                let loc = location - offset
                if handler.handleMouseHover(at: loc, deviceID: deviceID, isTopMost: topMost) {
                    topMost = false
                }
            }
            if topMost, let hitTest = aux.client?.auxiliaryWindowHitTest(location) {
                topMost = !hitTest
            }
        }
        return isTopMost != topMost
    }

    func resetGestureHandlers() {
        gestureGraph!.resetEvents()
    }

    // MARK: - ViewGraphRenderDelegate
    //
    // viewGraph.renderDelegate = self is set at end of init.
    // updateRenderContext is called once per frame in updateFrame (before updateView).

    // renderingRootView — the root "platform view" being rendered.
    // WindowController IS the rendering host, so return self.
    var renderingRootView: AnyObject { self }

    // updateRenderContext — fills in per-frame render parameters.
    // contentsScale: from sceneResources (updated by WindowContext on window events).
    // opaqueBackground: true if config background has no transparency.
    func updateRenderContext(_ context: inout ViewGraphRenderContext) {
        context.contentsScale = sceneResources.contentScaleFactor
        // backgroundColor.opacity is 0.0–1.0; treat >= 1.0 as fully opaque.
        // backgroundColor is VVD.Color; .a is the alpha Scalar (0.0–1.0).
        context.opaqueBackground = (config.backgroundColor.a >= 1.0)
    }

    // withMainThreadRender — ensures body runs on the main render thread.
    func withMainThreadRender(wasAsync: Bool, _ body: () -> Time) -> Time {
        return body()
    }

    // renderIntervalForDisplayLink — how long until the next frame should be rendered.
    func renderIntervalForDisplayLink(timestamp: Time) -> Double {
        return 0.0
    }

    // MARK: - ViewGraphRootValueUpdater

    func updateRootView() {
    }

    func updateEnvironment() {
        viewGraph.envAttr?.setValue(self.environment)
    }

    func updateSize() {
        viewGraph.sizeAttr?.setValue(ViewSize(cachedContentSize))
    }

    func updateSafeArea() {} // TODO: safe area not yet wired
    func updateContainerSize() {} // TODO: container size not yet wired
    func updateTransform() {}
    func updateFocusStore() {}
    func updateFocusedItem() {}
    func updateFocusedValues() {}
    func updateAccessibilityEnvironment() {}

    // MARK: - Aux/Modal window management

    private struct AuxiliaryWindow: @unchecked Sendable {
        weak var client: AuxiliaryWindowClient?
        var frame: CGRect? = nil
    }
    private let auxiliaryWindows = Mutex<[AuxiliaryWindow]>([])

    private struct ModalWindow: @unchecked Sendable {
        weak var client: ModalWindowClient?
        var frame: CGRect? = nil
        var initiated: Bool = false
    }
    private let modalWindows = Mutex<[ModalWindow]>([])

    private let modalSlots = Mutex<[AnyHashable: AnyWeakObject]>([:])

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
            slots = slots.filter { _, value in value.value != nil }
            let key = key.value
            if slots[key]?.value != nil { return false }
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
            if modalWindows.contains(where: { $0.client === client }) { return }
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
            if let index = modalWindows.firstIndex(where: { $0.client === client }) {
                initiated = modalWindows[index].initiated
                modalWindows.remove(at: index)
            }
        }
        guard let initiated else { return }
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
