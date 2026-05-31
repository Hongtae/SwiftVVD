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

// WindowController: owns ViewGraph and drives rendering + event dispatch.
// Non-generic: the Content type is used only at init for AG wiring, then discarded.
// Optionally owns a WindowContext, created lazily on the first makeWindow() call.
// Overlay-mode aux/modal controllers never call makeWindow(), so windowContext stays nil.
//
// Conforms to ViewRendererHost and ViewGraphRootValueUpdater.
// AG ownership lives in ViewGraph.
class WindowController: WindowInputEventHandler, WindowDelegate,
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

    // gestureGraph is owned directly by WindowController as the window-level gesture coordinator.
    var gestureGraph: GestureGraph?

    // Platform event to EventID routing table.
    // WindowController performs this mapping before forwarding to GestureGraph.
    private let _nextEventSerial: Atomic<Int> = Atomic(1)
    private var _touchEventIDs: [Int: EventID] = [:]    // deviceID to EventID (touch/stylus)
    private var _mouseEventID: EventID?                   // single mouse pointer EventID
    private var _spatialEventIDs: [Int: EventID] = [:]   // deviceID to spatial EventID (touch)
    private var _mouseSpatialEventID: EventID? = nil      // single mouse pointer spatial EventID
    private var _panEventID: EventID?                     // trackpad pan gesture EventID
    private var _panTranslation: CGPoint = .zero
    private var _activeEvents: [EventID: any EventType] = [:]  // current live event dict

    private func nextEventSerial() -> Int {
        _nextEventSerial.wrappingAdd(1, ordering: .relaxed).oldValue
    }

    // viewGraph owns the view-tree AttributeGraph (GraphHost.data) and gesture routing.
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
        case gesture(GestureEvent)
        case action(@Sendable () -> Void)
    }
    private let inputEvents = Mutex<[InputEvent]>([])

    // ViewRendererHost / ViewGraphOwner stored state.
    // WindowController tracks its own owner-side state separately from ViewGraph's internal state,
    // matching ViewRendererHost ownership needs.
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

        // Create GestureGraph first. It owns an independent AG.
        // WindowController owns both GestureGraph and ViewGraph.
        self.gestureGraph = GestureGraph()
        // Wire rendererHost back-reference before ViewGraph.init. GestureResponder.init
        // reads viewGraph.rendererHost?.gestureGraph during _makeView.
        self.gestureGraph!.rendererHost = self

        // Create ViewGraph. It does full AG wiring including _makeView, which may create GestureResponders.
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
        // self.viewGraph.delegate is not wired yet.
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
            window.addEventObserver(self) { [weak self] (event: GestureEvent) in
                self?.inputEvents.withLock { events in
                    events.append(.gesture(event))
                }
            }
            self.onWindowCreated(window)
        }
        return window
    }

    private var viewChangedWhileDrawing: Bool = false
    private(set) var cachedContentSize: CGSize = .zero

    func updateFrame(tick: UInt64, delta: Double, date: Date,
                     contentSize: CGSize, shouldDrawFrame: Bool,
                     _ withGC: WindowContext.WithGraphicsContext) {

        // Pull render context from delegate (ViewGraphRenderDelegate).
        // contentsScale: HiDPI scale factor for the current display.
        // opaqueBackground: whether the background is fully opaque (skip alpha clear).
        // Called once per frame before updateOutputs/render.
        var renderCtx = ViewGraphRenderContext(contentsScale: 1.0, opaqueBackground: false)
        viewGraph.renderDelegate?.updateRenderContext(&renderCtx)
        // TODO: propagate renderCtx.contentsScale to draw calls (HiDPI, Phase 5)

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

        // Detect size change and mark the dirty bit.
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
                case .gesture(let event):  self.handleGestureEvent(event: event)
                case .action(let action):  action()
                }
            }

            // Drain GestureGraph's action outbox: closures deferred from within GestureGraph
            // AG evaluation (enqueueAction fallback). Run here, outside any AG context,
            // after gesture events are fully processed.
            if let gg = self.gestureGraph {
                let actions = gg.data.graph.actionOutbox
                if !actions.isEmpty {
                    gg.data.graph.actionOutbox.removeAll()
                    actions.forEach { $0() }
                }
            }

            // updateOutputs: flush dirty bits, @State/@Observable changes, then evaluate AG.
            // Internally: data.withCurrent, inbox.drain, updateDelegate, then timeAttr.setValue.
            viewGraph.updateOutputs(at: time)

            // Resource loading: requires GraphicsContext, handled separately after updateOutputs.
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

            // Layout pass: determine root view size/position after AG evaluation completes.
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

        // Overlay aux children: update after self.
        for entry in self.auxChildWindows.withLock({ $0 }) {
            guard let child = entry.controller, entry.frame == nil else { continue }
            child.updateView(tick: tick, delta: delta, date: date,
                             contentSize: contentSize, redraw: &redraw, withGC)
        }
        // Overlay modal child (at most one): update last.
        if let entry = self.modalChildWindows.withLock({ $0.first }),
           let child = entry.controller, entry.frame == nil {
            child.updateView(tick: tick, delta: delta, date: date,
                             contentSize: contentSize, redraw: &redraw, withGC)
        }
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
        // Overlay aux children: draw on top after self.
        for entry in self.auxChildWindows.withLock({ $0 }) {
            guard let child = entry.controller, entry.frame == nil else { continue }
            child.drawFrame(offset: offset, context)
        }
        // Overlay modal child (at most one): draw on top of everything.
        if let entry = self.modalChildWindows.withLock({ $0.first }),
           let child = entry.controller, entry.frame == nil {
            child.drawFrame(offset: offset, context)
        }
    }

    func layoutBounds(_ bounds: CGRect) -> CGRect { bounds }

    func shouldClose(window: any PlatformWindow) -> Bool {
        modalChildWindows.withLock { $0.allSatisfy { $0.controller == nil } }
    }

    func onWindowCreated(_: any PlatformWindow) {}

    var appWindowsController: AppWindowsController? { appContext?.appWindowsController }

    // MARK: - Parent window event callbacks (override in subclass)
    func onParentWindowActivated()   {}
    func onParentWindowInactivated() {}
    func onParentWindowMoved()       {}
    func onParentWindowClosed()      { dismissAllAuxiliaryWindows(); dismissAllModalWindows() }

    // MARK: - Gesture initiation callback for dismissOnDeactivate logic
    func onGestureInitiated(from initiator: AnyObject?, location: CGPoint) {}

    // MARK: - Overlay hit-test (used by parent for mouse routing in overlay mode)
    // Override to define the hit-testable region. Default: bounding rect of content.
    func overlayHitTest(_ locationInParent: CGPoint) -> Bool { false }

    // MARK: - Modal session callbacks (override in ModalWindowController)
    func onModalSessionInitiated()         {}
    func onModalSessionDismissedByUser()   {}
    func onModalSessionDismissedByParent() {}
    func onModalSessionCancelled()         {}

    func onWindowClosing(_: any PlatformWindow) {
        self.auxChildWindows.withLock { $0.compactMap(\.controller) }
            .forEach { $0.onParentWindowClosed() }
        _onSheetWindowClosed?()
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
            inputEvents.withLock {
                $0.append(.action { [weak self] in
                    self?.auxChildWindows.withLock {
                        $0.compactMap(\.controller) }
                    .forEach { $0.onParentWindowClosed() }
                })
            }
        case .hidden:
            self.sharedContext.focusedViews.removeAll()
            viewGraph.data.graph.inbox.enqueue { [weak self] in
                self?.gestureGraph!.resetEvents()
            }
        case .activated:
            inputEvents.withLock {
                $0.append(.action { [weak self] in
                    self?.auxChildWindows.withLock {
                        $0.compactMap(\.controller) }
                    .forEach { $0.onParentWindowActivated() }
                })
            }
        case .inactivated:
            self.sharedContext.focusedViews.removeAll()
            viewGraph.data.graph.inbox.enqueue { [weak self] in
                self?.gestureGraph!.resetEvents()
            }
            inputEvents.withLock {
                $0.append(.action { [weak self] in
                    self?.auxChildWindows.withLock {
                        $0.compactMap(\.controller) }
                    .forEach { $0.onParentWindowInactivated() }
                })
            }
        case .minimized:
            self.sharedContext.focusedViews.removeAll()
            viewGraph.data.graph.inbox.enqueue { [weak self] in
                self?.gestureGraph!.resetEvents()
            }
        case .moved, .resized:
            inputEvents.withLock {
                $0.append(.action { [weak self] in
                    self?.auxChildWindows.withLock {
                        $0.compactMap(\.controller) }
                    .forEach { $0.onParentWindowMoved() }
                })
            }
        default:
            break
        }
    }

    func onKeyboardEvent(event: KeyboardEvent) {
        let topModal = self.modalChildWindows.withLock { $0.first?.controller }
        if let topModal {
            topModal.onKeyboardEvent(event: event)
        } else {
            self.handleKeyboardEvent(event: event)
        }
    }

    func onMouseEvent(event: MouseEvent) {
        let topModal = self.modalChildWindows.withLock { $0.first }
        if let modalController = topModal?.controller,
           let modalFrame = topModal?.frame {
            var event = event
            event.location -= modalFrame.origin
            if event.type == .wheel {
                modalController.handleMouseWheel(at: event.location, delta: event.delta)
            } else {
                if !modalController.handleMouseEvent(event: event) {
                    if event.type == .move || event.type == .buttonUp {
                        modalController.handleMouseHover(at: event.location,
                                                        deviceID: event.deviceID,
                                                        isTopMost: true)
                        self.handleMouseHover(at: event.location,
                                              deviceID: event.deviceID,
                                              isTopMost: false)
                    }
                }
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

        var handlers = self.auxChildWindows.withLock {
            $0.reversed().compactMap { entry -> (id: ObjectIdentifier, action: (KeyboardEvent) -> Bool)? in
                guard let child = entry.controller else { return nil }
                return (id: ObjectIdentifier(child), action: { event in
                    child.handleKeyboardEvent(event: event)
                })
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
            guard let gg = self.gestureGraph,
                  let rootResponder = gg.rootResponder else { return false }

            // Map deviceID to EventID, build the live event dictionary,
            // then forward it to GestureGraph.
            let time = self.currentTimestamp
            let isTouch = event.device == .touch || event.device == .stylus

            let phase: GesturePhase<Void>
            switch event.type {
            case .buttonDown:
                let serial = self.nextEventSerial()
                let tapEventID     = EventID(type: TappableEvent.self, serial: serial)
                let spatialEventID = EventID(type: SpatialEvent.self,  serial: serial)
                if isTouch {
                    self._touchEventIDs[event.deviceID] = tapEventID
                    self._spatialEventIDs[event.deviceID] = spatialEventID
                } else {
                    self._mouseEventID = tapEventID
                    self._mouseSpatialEventID = spatialEventID
                }
                self._activeEvents[tapEventID]     = TappableEvent(
                    location: event.location, phase: .began, buttonID: event.buttonID)
                self._activeEvents[spatialEventID] = SpatialEvent(
                    location: event.location, globalLocation: event.location,
                    phase: .began, timestamp: time.seconds)
                phase = gg.sendEvents(self._activeEvents, rootNode: rootResponder, at: time)

            case .move:
                let tapEventID     = isTouch ? self._touchEventIDs[event.deviceID]   : self._mouseEventID
                let spatialEventID = isTouch ? self._spatialEventIDs[event.deviceID] : self._mouseSpatialEventID
                guard let tapEventID else { return false }
                self._activeEvents[tapEventID] = TappableEvent(
                    location: event.location, phase: .moved, buttonID: event.buttonID)
                if let spatialEventID {
                    self._activeEvents[spatialEventID] = SpatialEvent(
                        location: event.location, globalLocation: event.location,
                        phase: .moved, timestamp: time.seconds)
                }
                phase = gg.sendEvents(self._activeEvents, rootNode: rootResponder, at: time)

            case .buttonUp:
                let tapEventID: EventID?
                let spatialEventID: EventID?
                if isTouch {
                    tapEventID     = self._touchEventIDs.removeValue(forKey: event.deviceID)
                    spatialEventID = self._spatialEventIDs.removeValue(forKey: event.deviceID)
                } else {
                    tapEventID     = self._mouseEventID;        self._mouseEventID = nil
                    spatialEventID = self._mouseSpatialEventID; self._mouseSpatialEventID = nil
                }
                guard let tapEventID else { return false }
                self._activeEvents[tapEventID] = TappableEvent(
                    location: event.location, phase: .ended, buttonID: event.buttonID)
                if let spatialEventID {
                    self._activeEvents[spatialEventID] = SpatialEvent(
                        location: event.location, globalLocation: event.location,
                        phase: .ended, timestamp: time.seconds)
                }
                phase = gg.sendEvents(self._activeEvents, rootNode: rootResponder, at: time)
                self._activeEvents.removeValue(forKey: tapEventID)
                if let spatialEventID { self._activeEvents.removeValue(forKey: spatialEventID) }

            default:
                return false
            }
            switch phase {
            case .active, .ended: return true
            default:              return false
            }
        }

        // Build handler list: aux children (reversed = top-first) then self.
        var handlers = self.auxChildWindows.withLock {
            $0.reversed().compactMap { entry -> (target: AnyObject, action: (MouseEvent) -> Bool)? in
                guard let child = entry.controller, let frame = entry.frame else { return nil }
                return (target: child, action: { event in
                    let loc = event.location - frame.origin
                    if child.overlayHitTest(loc) {
                        var e = event; e.location = loc
                        child.handleMouseEvent(event: e)
                        return true
                    }
                    return false
                })
            }
        }
        handlers.append((target: self as AnyObject, action: handleEvent))

        // Track which aux child initiated a gesture (for dismissOnDeactivate).
        let auxChildren = event.type == .buttonDown
            ? self.auxChildWindows.withLock { $0.compactMap(\.controller) }
            : []

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
                auxChildren.forEach { $0.onGestureInitiated(from: handler.target, location: event.location) }
                return true
            }
        }
        _lastMouseEventHandler = nil
        auxChildren.forEach { $0.onGestureInitiated(from: nil, location: event.location) }
        return false
    }

    @discardableResult
    func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        for entry in self.auxChildWindows.withLock({ $0.reversed() }) {
            guard let child = entry.controller, let frame = entry.frame else { continue }
            let loc = location - frame.origin
            if child.overlayHitTest(loc) {
                child.handleMouseWheel(at: loc, delta: delta)
                return true
            }
        }
        return false
    }

    @discardableResult
    func handleGestureEvent(event: GestureEvent) -> Bool {
        if let window = self.window, window !== event.window { return false }
        guard let gg = self.gestureGraph,
              let rootResponder = gg.rootResponder else { return false }
        let time = currentTimestamp

        switch event.type {
        case .pan:
            let phase: GesturePhase<Void>
            switch event.phase {
            case .began:
                let eventID = EventID(type: PanEvent.self, serial: nextEventSerial())
                _panEventID = eventID
                _panTranslation = .zero
                _activeEvents[eventID] = PanEvent(
                    translation: .zero, globalTranslation: .zero,
                    location: event.location, velocity: .zero, phase: .began)
                phase = gg.sendEvents(_activeEvents, rootNode: rootResponder, at: time)

            case .changed:
                guard let eventID = _panEventID else { return false }
                _panTranslation.x += event.delta.x
                _panTranslation.y += event.delta.y
                let t = CGSize(width: _panTranslation.x, height: _panTranslation.y)
                _activeEvents[eventID] = PanEvent(
                    translation: t, globalTranslation: t,
                    location: event.location, velocity: .zero, phase: .moved)
                phase = gg.sendEvents(_activeEvents, rootNode: rootResponder, at: time)

            case .ended:
                guard let eventID = _panEventID else { return false }
                let t = CGSize(width: _panTranslation.x, height: _panTranslation.y)
                _activeEvents[eventID] = PanEvent(
                    translation: t, globalTranslation: t,
                    location: event.location, velocity: .zero, phase: .ended)
                phase = gg.sendEvents(_activeEvents, rootNode: rootResponder, at: time)
                _activeEvents.removeValue(forKey: eventID)
                _panEventID = nil
                _panTranslation = .zero

            case .cancelled:
                guard let eventID = _panEventID else { return false }
                let t = CGSize(width: _panTranslation.x, height: _panTranslation.y)
                _activeEvents[eventID] = PanEvent(
                    translation: t, globalTranslation: t,
                    location: event.location, velocity: .zero, phase: .cancelled)
                _ = gg.sendEvents(_activeEvents, rootNode: rootResponder, at: time)
                _activeEvents.removeValue(forKey: eventID)
                _panEventID = nil
                _panTranslation = .zero
                return false
            }
            switch phase {
            case .active, .ended: return true
            default:              return false
            }

        case .magnify, .rotate:
            return false
        }
    }

    @discardableResult
    func handleMouseHover(at location: CGPoint, deviceID: Int, isTopMost: Bool) -> Bool {
        var topMost = isTopMost
        self.auxChildWindows.withLock({ $0.reversed() }).forEach { entry in
            guard let child = entry.controller else { return }
            if let offset = entry.frame?.origin {
                let loc = location - offset
                if child.handleMouseHover(at: loc, deviceID: deviceID, isTopMost: topMost) {
                    topMost = false
                }
            }
            if topMost && child.overlayHitTest(location - (entry.frame?.origin ?? .zero)) {
                topMost = false
            }
        }
        return isTopMost != topMost
    }

    func resetGestureHandlers() {
        gestureGraph?.resetEvents()
        _touchEventIDs.removeAll()
        _mouseEventID = nil
        _spatialEventIDs.removeAll()
        _mouseSpatialEventID = nil
        _panEventID = nil
        _panTranslation = .zero
        _activeEvents.removeAll()
    }

    // MARK: - ViewGraphRenderDelegate
    //
    // WindowController is the rendering host.
    //
    // viewGraph.renderDelegate = self is set at end of init.
    // updateRenderContext is called once per frame in updateFrame (before updateView).

    // renderingRootView is the root "platform view" being rendered.
    // WindowController is the rendering host, so return self.
    var renderingRootView: AnyObject { self }

    // updateRenderContext fills in per-frame render parameters.
    // contentsScale: from sceneResources (updated by WindowContext on window events).
    // opaqueBackground: true if config background has no transparency.
    func updateRenderContext(_ context: inout ViewGraphRenderContext) {
        context.contentsScale = sceneResources.contentScaleFactor
        // backgroundColor.opacity is 0.0-1.0. Treat >= 1.0 as fully opaque.
        // backgroundColor is VVD.Color. .a is the alpha Scalar (0.0-1.0).
        context.opaqueBackground = (config.backgroundColor.a >= 1.0)
    }

    // withMainThreadRender ensures body runs on the main render thread.
    // The VVD render loop already runs on the appropriate thread, so call body() directly.
    func withMainThreadRender(wasAsync: Bool, _ body: () -> Time) -> Time {
        return body()
    }

    // renderIntervalForDisplayLink returns how long until the next frame should be rendered.
    // VVD controls frame pacing; returning 0.0 means "render at VVD frame rate".
    func renderIntervalForDisplayLink(timestamp: Time) -> Double {
        return 0.0
    }

    // MARK: - ViewGraphRootValueUpdater

    func updateRootView() {
        // VUI: content is lifted into ViewGraph at init time; no separate root view setter.
    }

    func updateEnvironment() {
        viewGraph.envAttr?.setValue(self.environment)
    }

    func updateSize() {
        viewGraph.sizeAttr?.setValue(ViewSize(cachedContentSize))
    }

    func updateSafeArea()      {}  // TODO: safe area not yet wired
    func updateContainerSize() {}  // TODO: container size not yet wired
    func updateTransform()         {}
    func updateFocusStore()        {}
    func updateFocusedItem()       {}
    func updateFocusedValues()     {}
    func updateAccessibilityEnvironment() {}

    // MARK: - Aux/Modal window management (nested structure)
    // AppWindowsController owns all instances (strong refs).
    // WindowController holds weak refs for overlay rendering and cascade dismiss.

    // Parent that opened this window (nil = root window).
    weak var parentWindow: WindowController?

    private struct AuxChildEntry: @unchecked Sendable {
        weak var controller: WindowController?
        var frame: CGRect? = nil
    }
    private let auxChildWindows = Mutex<[AuxChildEntry]>([])

    private struct ModalChildEntry: @unchecked Sendable {
        weak var controller: WindowController?
        var frame: CGRect? = nil
        var initiated: Bool = false
    }
    // Active modal (at most one per WindowController).
    private let modalChildWindows = Mutex<[ModalChildEntry]>([])
    // Queue: waiting modals shown one-by-one as the active one is dismissed.
    private struct PendingModal: @unchecked Sendable {
        let controller: WindowController
        let initiated: Bool
    }
    private let pendingModalChildren = Mutex<[PendingModal]>([])

    // Called by AppWindowsController to register a child aux window.
    func addAuxChild(_ child: WindowController) {
        child.parentWindow = self
        let entry = AuxChildEntry(controller: child)
        self.auxChildWindows.withLock { entries in
            entries.removeAll { $0.controller == nil || $0.controller === child }
            entries.append(entry)
        }
    }

    func removeAuxChild(_ child: WindowController) {
        child.parentWindow = nil
        self.auxChildWindows.withLock { $0.removeAll { $0.controller === child } }
    }

    func updateAuxChildFrame(_ child: WindowController, frame: CGRect?) {
        self.auxChildWindows.withLock { entries in
            if let i = entries.firstIndex(where: { $0.controller === child }) {
                entries[i].frame = frame
            }
        }
    }

    func dismissAllAuxiliaryWindows() {
        let children = self.auxChildWindows.withLock { entries in
            defer { entries.removeAll() }
            return entries.compactMap(\.controller)
        }
        children.forEach { child in
            child.parentWindow = nil
            child.onParentWindowClosed()
        }
    }

    // Called by AppWindowsController to register a child modal window.
    // If a modal is already active, the child is queued and shown after the current one is dismissed.
    func addModalChild(_ child: WindowController, initiated: Bool) {
        child.parentWindow = self
        let hasActive = self.modalChildWindows.withLock {
            $0.contains { $0.controller != nil }
        }
        if hasActive {
            self.pendingModalChildren.withLock { $0.append(PendingModal(controller: child, initiated: initiated)) }
        } else {
            _showModalChild(child, initiated: initiated)
        }
    }

    private func _showModalChild(_ child: WindowController, initiated: Bool) {
        let entry = ModalChildEntry(controller: child, initiated: initiated)
        let isFirst = self.modalChildWindows.withLock { entries in
            let first = entries.isEmpty
            entries = [entry]
            return first
        }
        if isFirst {
            self.resetGestureHandlers()
            self.handleMouseHover(at: .zero, deviceID: 0, isTopMost: false)
        }
    }

    private func _showNextModal() {
        let next = self.pendingModalChildren.withLock { pending -> PendingModal? in
            guard !pending.isEmpty else { return nil }
            return pending.removeFirst()
        }
        if let next {
            next.controller.parentWindow = self
            _showModalChild(next.controller, initiated: next.initiated)
        }
    }

    func removeModalChild(_ child: WindowController) {
        var initiated: Bool?
        self.modalChildWindows.withLock { entries in
            if let i = entries.firstIndex(where: { $0.controller === child }) {
                initiated = entries[i].initiated
                entries.remove(at: i)
            }
        }
        child.parentWindow = nil
        guard let initiated else { return }
        if initiated {
            child.onModalSessionDismissedByParent()
        } else {
            child.onModalSessionCancelled()
        }
        _showNextModal()
    }

    func detachModalChild(_ child: WindowController) {
        var wasActive = false
        self.modalChildWindows.withLock {
            let before = $0.count
            $0.removeAll { $0.controller === child }
            wasActive = $0.count < before
        }
        self.pendingModalChildren.withLock { $0.removeAll { $0.controller === child } }
        child.parentWindow = nil
        if wasActive { _showNextModal() }
    }

    func updateModalChildFrame(_ child: WindowController, frame: CGRect?) {
        self.modalChildWindows.withLock { entries in
            if let i = entries.firstIndex(where: { $0.controller === child }) {
                entries[i].frame = frame
            }
        }
    }

    func dismissAllModalWindows() {
        // Cancel queued modals first.
        let pending = self.pendingModalChildren.withLock { p in defer { p.removeAll() }; return p }
        pending.forEach { item in
            item.controller.parentWindow = nil
            item.controller.onModalSessionCancelled()
        }
        let entries = self.modalChildWindows.withLock { entries in
            defer { entries.removeAll() }
            return entries
        }
        for entry in entries {
            guard let child = entry.controller else { continue }
            child.parentWindow = nil
            if entry.initiated {
                child.onModalSessionDismissedByParent()
            } else {
                child.onModalSessionCancelled()
            }
        }
    }

    // MARK: - Sheet presentation queue
    // Independent of modalChildWindows (which is for scene-based overlay modals).
    // Overlay and platform-window sheets are both queued here, one at a time,
    // shown in arrival order.

    private struct SheetEntry: @unchecked Sendable {
        var session: SheetPreference.Session
        var controller: WindowController?
    }

    // Active sheet being shown right now.
    private var _activeSheet: SheetEntry?
    // Sessions waiting to be shown (FIFO).
    // Not Mutex because access is single-threaded (AG side-effect rule / user dismiss callback).
    private var _pendingSheetSessions: [SheetPreference.Session] = []

    /// Called from ViewGraph side-effect rule. `value.sessions` = all currently-active
    /// sheet sessions from the entire view tree, collected via preference merge.
    func updateSheetPresentation(_ value: SheetPreference.Value) {
        let incoming = value.sessions

        // Compute stable IDs using the Binding's base-pointer identity.
        func id(of session: SheetPreference.Session) -> ObjectIdentifier {
            ObjectIdentifier(session.isPresented as AnyObject)
        }

        let activeID   = _activeSheet.map { id(of: $0.session) }
        let pendingIDs = _pendingSheetSessions.map { id(of: $0) }

        // Enqueue newly-arrived sessions that aren't already active or pending.
        for session in incoming {
            let sid = id(of: session)
            guard sid != activeID, !pendingIDs.contains(sid) else { continue }
            _pendingSheetSessions.append(session)
        }

        // Dismiss the active sheet if its session is no longer in incoming.
        if let active = _activeSheet {
            if !incoming.contains(where: { id(of: $0) == id(of: active.session) }) {
                _tearDownActiveSheet(reason: .dismissed)
            }
        }

        // Start the next sheet if nothing is showing.
        if _activeSheet == nil {
            _showNextSheet()
        }
    }

    private enum SheetDismissReason {
        case userAction   // user closed window, reset binding + onDismiss
        case dismissed    // programmatic (binding=false already), onDismiss only
        case byParent     // parent closed, reset binding + onDismiss
        case cancelled    // queued but never shown, reset binding and no onDismiss
    }

    private func _showNextSheet() {
        guard _activeSheet == nil else { return }
        guard !_pendingSheetSessions.isEmpty else { return }
        let session = _pendingSheetSessions.removeFirst()
        guard let graph = AttributeGraph.current else {
            // Called outside AG context (e.g. after user dismiss).
            // Re-enqueue at front. The side-effect rule will fire again.
            _pendingSheetSessions.insert(session, at: 0)
            return
        }

        let contentAttr = graph.makeInput(value: session.makeContent())
        let contentGV   = _GraphValue<AnyView>(_attribute: contentAttr)
        let sheetKey    = WindowKey(namespace: scene.namespace, sceneID: scene.sceneID)
        let controller  = WindowController(content: contentGV, scene: sheetKey)

        _activeSheet = SheetEntry(session: session, controller: controller)

        // .userAction: user closes the sheet window.
        controller._onSheetWindowClosed = { [weak self] in
            guard let self else { return }
            self._tearDownActiveSheet(reason: .userAction)
            self._showNextSheet()
        }

        Task { @MainActor [weak self, weak controller] in
            guard let self, let controller else { return }
            guard let parentWindow = self.window,
                  let sheetWindow  = controller.makeWindow() else { return }
            if !parentWindow.presentModalWindow(sheetWindow) {
                Log.error("WindowController: sheet window presentation failed")
                self._activeSheet = nil
                self._showNextSheet()
            }
        }
    }

    private func _tearDownActiveSheet(reason: SheetDismissReason) {
        guard let entry = _activeSheet else { return }
        _activeSheet = nil
        entry.controller?._onSheetWindowClosed = nil  // prevent re-entrancy

        switch reason {
        case .userAction:
            entry.session.isPresented.wrappedValue = false
            entry.session.onDismiss?()
        case .dismissed:
            entry.session.onDismiss?()
        case .byParent:
            entry.session.isPresented.wrappedValue = false
            entry.session.onDismiss?()
        case .cancelled:
            entry.session.isPresented.wrappedValue = false
            // onDismiss is not called because the sheet was never shown.
        }

        let sheetController = entry.controller
        Task { @MainActor [weak self, weak sheetController] in
            if let w = sheetController?.window {
                self?.window?.dismissModalWindow(w)
                w.close()
            }
        }
    }

    /// Set by the parent when this WindowController is acting as a sheet window.
    /// Fires on user-driven close only.
    fileprivate var _onSheetWindowClosed: (() -> Void)?
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
