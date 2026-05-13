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
// Phase 4: AG ownership moved from WindowController to ViewGraph.
class WindowController: WindowInputEventHandler, WindowDelegate,
                        ViewRendererHost, ViewGraphRootValueUpdater,
                        ViewGraphRenderDelegate,
                        @unchecked Sendable {

    typealias AttachWindow = @MainActor (any PlatformWindow) -> Void
    typealias AttachWindowResolver = (AttachWindow?) -> Void

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
    // Phase 4: moved from `let graph: AttributeGraph` + scattered input/output attrs.
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
    // matching the pattern where NSHostingView also conforms to ViewGraphOwner independently.
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

        // Create GestureGraph first. It owns an independent AG, separate from ViewGraph's AG.
        self.gestureGraph = GestureGraph()
        // Wire rendererHost back-reference before ViewGraph.init. GestureResponder.init
        // reads viewGraph.rendererHost?.gestureGraph during _makeView.
        self.gestureGraph!.rendererHost = self

        // Create ViewGraph. This performs full AG wiring including _makeView,
        // which may create GestureResponders.
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
        // delegate (ViewGraphHostDelegate) is not set yet.
        // TODO: wire updateGraphInputs(_:inout _GraphInputs) once the call site is implemented.
        // self.viewGraph.delegate = self
    }

    // Sheet-specific init: content comes from a reactive attribute in a parent AG.
    // The ViewGraph creates a crossGraphRef to mirror the parent's attribute, so that
    // when parent @State changes, parent contentAttr re-evaluates and child graph updates.
    // contentAttr must already have a non-nil cached value in sourceGraph before this is called.
    init(crossGraphContent contentAttr: Attribute<AnyView>,
         sourceGraph: AttributeGraph,
         scene: WindowKey) {
        self._titleGraph = nil
        self._style = .genericWindow
        self.environment = EnvironmentValues()
        self.sharedContext = SharedContext()
        self.sceneResources = SceneResources()
        self.windowContext = nil
        self.scene = scene
        self.date = .now

        self.gestureGraph = GestureGraph()
        self.gestureGraph!.rendererHost = self

        self._viewGraph = ViewGraph(
            crossGraphContentAttr: contentAttr,
            sourceGraph: sourceGraph,
            rendererHost: self
        )
        self.viewGraph.renderDelegate = self
        self.viewGraph.updateDelegate = self
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
    private var hasDeliveredViewLayoutUpdate = false
    private(set) var cachedRootFittedSize: CGSize?
    private(set) var cachedContentSize: CGSize = .zero

    var observesRootFittedSizeForLayoutUpdates: Bool { false }

    func layoutContentSize(from contentSize: CGSize) -> CGSize {
        contentSize
    }

    func updateFrame(tick: UInt64, delta: Double, date: Date,
                     contentSize: CGSize, shouldDrawFrame: Bool,
                     _ withGC: WindowContext.WithGraphicsContext) {

        // Pull render context from delegate (ViewGraphRenderDelegate).
        // contentsScale: HiDPI scale factor for the current display.
        // opaqueBackground: whether the background is fully opaque (skip alpha clear).
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
        let layoutContentSize = layoutContentSize(from: contentSize)

        // Detect size change and mark the dirty bit.
        let sizeChanged = (layoutContentSize != cachedContentSize)
        if sizeChanged {
            cachedContentSize = layoutContentSize
            viewGraph.valuesNeedingUpdate.insert(.size)
        }

        let changeSet = AGChangeSet()
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

                let previousRootFittedSize = cachedRootFittedSize
                let rootFittedSize = observesRootFittedSizeForLayoutUpdates
                    ? viewGraph.rootFittedSize?.value
                    : nil
                if let rootFittedSize {
                    cachedRootFittedSize = rootFittedSize
                }
                let rootFittedSizeChanged = rootFittedSize.map { $0 != previousRootFittedSize } ?? false

                if !hasDeliveredViewLayoutUpdate || sizeChanged || rootFittedSizeChanged {
                    hasDeliveredViewLayoutUpdate = true
                    // Modal/aux controllers use this hook to fit their platform
                    // window after AG layout values are available. The hook is
                    // driven by the root fitted-size rule rather than the host
                    // window's proposed sizeAttr, because resource/content
                    // changes can alter natural modal size without changing the
                    // platform content size first.
                    onViewLayoutUpdated()
                }
            }
        }
        // Preserve redraw requests raised earlier in this frame, including
        // child modal input handled during the parent event pass.
        redraw = redraw || !changeSet.isEmpty || self.viewChangedWhileDrawing
        self.viewChangedWhileDrawing = false

        // Overlay aux children: update after self.
        for entry in self.auxChildWindows.withLock({ $0 }) {
            guard entry.isOverlay, entry.initiated else { continue }
            entry.controller.updateView(tick: tick, delta: delta, date: date,
                                        contentSize: contentSize, redraw: &redraw, withGC)
        }
        // Overlay modal child (at most one): update last.
        if let entry = self.modalChildren.withLock({ $0.first }),
           entry.isOverlay, entry.initiated {
            entry.controller.updateView(tick: tick, delta: delta, date: date,
                                        contentSize: contentSize, redraw: &redraw, withGC)
        }
    }

    func drawFrame(offset: CGPoint, _ context: GraphicsContext) {
        guard let rootDisplayList = viewGraph.rootDisplayList else { return }

        var context = context
        context.translateBy(x: offset.x, y: offset.y)

        viewGraph.data.withCurrent {
            let changeSet = AGChangeSet()
            AttributeGraph.$changeSet.withValue(changeSet) {
                let displayList = rootDisplayList.value
                for item in displayList.items {
                    item(context)
                }
                for item in displayList.debugItems {
                    item(context)
                }
            }
            self.viewChangedWhileDrawing = !changeSet.isEmpty
        }
        // Overlay aux children: draw on top after self.
        for entry in self.auxChildWindows.withLock({ $0 }) {
            guard entry.isOverlay, entry.initiated else { continue }
            entry.controller.drawFrame(offset: offset, context)
        }
        // Overlay modal child (at most one): draw on top of everything.
        if let entry = self.modalChildren.withLock({ $0.first }),
           entry.isOverlay, entry.initiated {
            entry.controller.drawFrame(offset: offset, context)
        }
    }

    func layoutBounds(_ bounds: CGRect) -> CGRect { bounds }

    func shouldClose(window: any PlatformWindow) -> Bool {
        modalChildren.withLock { $0.isEmpty }
    }

    func onWindowCreated(_: any PlatformWindow) {}

    var appWindowsController: AppWindowsController? { appContext?.appWindowsController }

    // MARK: - Aux child session callbacks (override in AuxiliaryWindowController)
    // Called by the parent on this controller when used as an aux child.
    func onParentWindowActivated()   {}
    func onParentWindowInactivated() {}
    func onParentWindowMoved()       {}
    func onParentWindowClosed() {
        dismissAllAuxiliaryWindows()
        dismissAllModalWindows() 
    }
    func onGestureInitiated(from initiator: AnyObject?, location: CGPoint) {}
    // Override to define the overlay hit-testable region (used by parent for mouse routing).
    func overlayHitTest(_ locationInParent: CGPoint) -> Bool { false }

    // MARK: - Modal session callbacks (override in ModalWindowController)
    var modalSessionPrefersPlatformWindow: Bool { false }
    // Called by the parent's _activateModal after attachWindow has been invoked.
    // At this point the entry is already initiated and the modal is visible.
    func onModalSessionInitiated() {}
    func onModalSessionDismissalRequested(reason: ModalDismissReason,
                                          completion: @escaping () -> Void) -> Bool {
        false
    }
    func onModalSessionDismissedByUser()   {}
    func onModalSessionDismissedByParent() {}
    func onModalSessionCancelled()         {}

    func onWindowClosing(_: any PlatformWindow) {
        self.auxChildWindows.withLock { $0.map(\.controller) }
            .forEach { $0.onParentWindowClosed() }
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
                    self?.auxChildWindows.withLock { $0.map(\.controller) }
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
                    self?.auxChildWindows.withLock { $0.map(\.controller) }
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
                    self?.auxChildWindows.withLock { $0.map(\.controller) }
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
                    self?.auxChildWindows.withLock { $0.map(\.controller) }
                        .forEach { $0.onParentWindowMoved() }
                })
            }
        default:
            break
        }
    }

    func onKeyboardEvent(event: KeyboardEvent) {
        // Only route to overlay modal if fully initiated (async Task may still be pending).
        let topModal: WindowController? = self.modalChildren.withLock {
            guard let e = $0.first, e.initiated, e.isOverlay else { return nil }
            return e.controller
        }
        if let topModal {
            topModal.onKeyboardEvent(event: event)
        } else {
            self.handleKeyboardEvent(event: event)
        }
    }

    func onMouseEvent(event: MouseEvent) {
        let topModal = self.modalChildren.withLock { $0.first }
        if let topModal, topModal.isOverlay, topModal.initiated {
            let modalController = topModal.controller
            let event = event
            if event.type == .wheel {
                _ = modalController.handleMouseWheel(at: event.location, delta: event.delta)
            } else {
                _ = modalController.handleMouseEvent(event: event)
                if event.type == .move || event.type == .buttonUp {
                    _ = modalController.handleMouseHover(at: event.location,
                                                         deviceID: event.deviceID,
                                                         isTopMost: true)
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
            $0.reversed().map { entry -> (id: ObjectIdentifier, action: (KeyboardEvent) -> Bool) in
                let child = entry.controller
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

            // Map deviceID to EventID, build the active event dictionary,
            // then forward to GestureGraph.
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
                guard let frame = entry.frame else { return nil }
                let child = entry.controller
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
            ? self.auxChildWindows.withLock { $0.map(\.controller) }
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
            guard let frame = entry.frame else { continue }
            let child = entry.controller
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
            let child = entry.controller
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

    // WindowController is the rendering host.
    // viewGraph.renderDelegate = self is set at end of init.
    // updateRenderContext is called once per frame in updateFrame (before updateView).

    // renderingRootView: the root platform object being rendered.
    // WindowController is the rendering host, so return self.
    var renderingRootView: AnyObject { self }

    // updateRenderContext: fills in per-frame render parameters.
    // contentsScale: from sceneResources (updated by WindowContext on window events).
    // opaqueBackground: true if config background has no transparency.
    func updateRenderContext(_ context: inout ViewGraphRenderContext) {
        context.contentsScale = sceneResources.contentScaleFactor
        // backgroundColor.opacity is 0.0-1.0; treat >= 1.0 as fully opaque.
        // backgroundColor is VVD.Color; .a is the alpha Scalar (0.0-1.0).
        context.opaqueBackground = (config.backgroundColor.a >= 1.0)
    }

    // withMainThreadRender: ensures body runs on the main render thread.
    // The VVD render loop already runs on the appropriate thread, so call body() directly.
    func withMainThreadRender(wasAsync: Bool, _ body: () -> Time) -> Time {
        return body()
    }

    // renderIntervalForDisplayLink: how long until the next frame should be rendered.
    // VVD controls frame pacing; returning 0.0 means "render at VVD frame rate".
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

    func updateSafeArea()      {}  // TODO: safe area not yet wired
    func updateContainerSize() {}  // TODO: container size not yet wired
    func updateTransform()         {}
    func updateFocusStore()        {}
    func updateFocusedItem()       {}
    func updateFocusedValues()     {}
    func updateAccessibilityEnvironment() {}

    // MARK: - Aux/Modal window management (nested structure)
    // WindowController owns its dynamic children directly (strong refs).
    // AppWindowsController is not involved in dynamic aux/modal lifetime.

    // Parent that opened this window (nil = root window).
    weak var parentWindow: WindowController?

    private struct AuxChildEntry: @unchecked Sendable {
        let controller: WindowController   // strong, WindowController owns its aux children
        var isOverlay: Bool = true
        var initiated: Bool = false
        var frame: CGRect? = nil           // overlay hit-test / draw offset (independent of isOverlay)
    }
    private let auxChildWindows = Mutex<[AuxChildEntry]>([])

    // Unified modal queue: first entry = active, rest = pending.
    // Uses the same active-plus-pending shape as window sheet queues.
    //
    // isOverlay is set at _activateModal time (not at enqueue time) based on:
    //   - the child controller's frozen modalSessionUsingPlatformWindow value
    //   - the parent's platform-window capability at activation time
    // Before activation, isOverlay defaults to false; queued entries are never drawn (initiated = false).
    //
    // In dismissAllModalWindows, position (first vs rest) determines reason:
    //   first = was active, so .byParent; rest = queued and never shown, so .cancelled.
    private struct ModalChildEntry: @unchecked Sendable {
        let controller: WindowController   // strong, WindowController owns its modal children
        var isOverlay: Bool = false   // set to true only when overlay is confirmed; false = platform window
        var initiated: Bool = false   // true once activation completes; updateView/drawFrame gate on this
        var session: PresentationSession
        var contentAttr: Attribute<AnyView>? = nil
        var attachWindow: AttachWindowResolver? = nil
    }
    private let modalChildren = Mutex<[ModalChildEntry]>([])

    // MARK: Aux child management

    func addAuxChild(_ child: WindowController,
                     attachWindow: AttachWindowResolver? = nil) {
        child.parentWindow = self
        let asOverlay = (self.window == nil)
        var entry = AuxChildEntry(controller: child)
        entry.isOverlay = false
        self.auxChildWindows.withLock { entries in
            entries.removeAll { $0.controller === child }
            entries.append(entry)
        }

        if !asOverlay, let attachWindow {
            attachWindow { [weak self, weak child] _ in
                self?.auxChildWindows.withLock { entries in
                    if let i = entries.firstIndex(where: { $0.controller === child }) {
                        entries[i].isOverlay = false
                        entries[i].initiated = true
                    }
                }
            }
            // attachWindow is allowed to hand off to the MainActor before calling the
            // AttachWindow callback. Enqueue the fallback on the same actor so a real
            // attach gets the first chance to mark this child as initiated.
            Task { @MainActor [weak self, weak child] in
                self?.auxChildWindows.withLock { entries in
                    // initiated == false means AttachWindow did not run.
                    if let i = entries.firstIndex(where: { $0.controller === child }),
                       !entries[i].initiated {
                        entries[i].isOverlay = true
                        entries[i].initiated = true
                    }
                }
            }
        } else {
            attachWindow?(nil)
            self.auxChildWindows.withLock { entries in
                if let i = entries.firstIndex(where: { $0.controller === child }) {
                    entries[i].isOverlay = true
                    entries[i].initiated = true
                }
            }
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
            return entries.map(\.controller)
        }
        children.forEach { child in
            child.parentWindow = nil
            child.onParentWindowClosed()
        }
    }

    // MARK: Modal child management

    // Called internally by preference-driven sheet/alert/dialog presentation.
    // isOverlay is not determined here. It is deferred to _activateModal when the entry
    // reaches the front of the queue and the parent's window state is known.
    func addModalChild(_ child: WindowController,
                       session: PresentationSession,
                       contentAttr: Attribute<AnyView>? = nil,
                       attachWindow: AttachWindowResolver? = nil) {
        child.parentWindow = self
        var entry = ModalChildEntry(controller: child, session: session)
        entry.contentAttr = contentAttr
        entry.attachWindow = attachWindow
        let isFirst = modalChildren.withLock {
            let first = $0.isEmpty
            $0.append(entry)
            return first
        }
        if isFirst {
            _activateModal(entry: entry)
        }
    }

    // Activate the front-of-queue entry.
    // Determines overlay vs platform-window based on session semantics + self.window,
    // then calls entry.activate(asOverlay:) to let the child prepare itself.
    private func _activateModal(entry: ModalChildEntry) {
        let child = entry.controller

        // ModalWindowController freezes modalSessionUsingPlatformWindow at
        // creation time. Later environment/session updates must not switch an
        // existing child between overlay and platform-window mode.
        let canUsePlatformWindow = child.modalSessionPrefersPlatformWindow &&
            entry.attachWindow != nil &&
            runOnMainQueueSync { self.window?.canPresentModalWindow == true }
        let asOverlay = !canUsePlatformWindow

        if !asOverlay, let attachWindow = entry.attachWindow {
            // Race guard: a preference-driven session can be dismissed before
            // attachWindow creates the platform window.
            if let presented = modalChildren.withLock({ $0.first?.session.isPresented }),
               !presented.wrappedValue {
                removeModalChild(child, reason: .cancelled)
                return
            }

            attachWindow { [weak self, weak child] childWindow in
                guard let self else { return }
                let ok = self.window?.presentModalWindow(
                    childWindow,
                    completionHandler: { [weak self, weak child] in
                        Task { @MainActor [weak self, weak child] in
                            guard let self, let child else { return }
                            self.removeModalChild(child, reason: .userAction)
                        }
                    }
                ) ?? false
                if ok {
                    let didInitiate = self.modalChildren.withLock { entries in
                        guard let child,
                              let i = entries.firstIndex(where: { $0.controller === child }) else {
                            return false
                        }
                        entries[i].isOverlay = false
                        entries[i].initiated = true
                        return true
                    }
                    if didInitiate {
                        child?.onModalSessionInitiated()
                    }
                } else {
                    Log.error("WindowController: presentModalWindow failed")
                    if let child {
                        self.removeModalChild(child, reason: .cancelled)
                    }
                }
            }

            // attachWindow is expected to create/attach the platform window through the
            // MainActor AttachWindow callback. Enqueue this fallback after that handoff;
            // if attach never marks the entry as initiated, default to overlay mode.
            Task { @MainActor [weak self, weak child] in
                guard let self, let child else { return }
                let result = self.modalChildren.withLock { entries -> (initiated: Bool, fallback: Bool) in
                    guard let i = entries.firstIndex(where: { $0.controller === child }) else {
                        return (false, false)
                    }
                    if entries[i].initiated {
                        return (true, false)
                    } else {
                        // initiated == false means AttachWindow did not run.
                        entries[i].isOverlay = true
                        entries[i].initiated = true
                        return (true, true)
                    }
                }
                if result.fallback {
                    child.onModalSessionInitiated()
                }
                if result.initiated {
                    self.resetGestureHandlers()
                    self.handleMouseHover(at: .zero, deviceID: 0, isTopMost: false)
                }
            }
        } else {
            // Overlay forced or no attachWindow: notify with nil, then mark initiated.
            entry.attachWindow?(nil)
            modalChildren.withLock { entries in
                if let i = entries.firstIndex(where: { $0.controller === child }) {
                    entries[i].isOverlay = true
                    entries[i].initiated = true
                }
            }
            child.onModalSessionInitiated()
            self.resetGestureHandlers()
            self.handleMouseHover(at: .zero, deviceID: 0, isTopMost: false)
        }
    }

    // Show the front of the queue after the previous active modal was removed.
    private func _showNextInQueue() {
        guard let entry = modalChildren.withLock({ $0.first }) else { return }
        let child = entry.controller
        // Race guard: skip if preference-driven session is already dismissed.
        if let presented = entry.session.isPresented, !presented.wrappedValue {
            removeModalChild(child, reason: .cancelled)
            return
        }
        // entry.initiated is false here (newly dequeued). _activateModal will set it after init.
        _activateModal(entry: entry)
    }

    // Notify a modal child that its presentation state has become dismissed.
    // The child owns the visible dismissal and calls the completion when it is
    // actually ready to be removed from the parent's modal queue.
    private func notifyModalChildDismissalRequested(_ child: WindowController,
                                                    reason: ModalDismissReason) {
        let shouldNotifyChild = modalChildren.withLock { entries -> Bool in
            guard let i = entries.firstIndex(where: { $0.controller === child }) else { return false }
            return i == 0 && entries[i].isOverlay && entries[i].initiated
        }
        if shouldNotifyChild,
           child.onModalSessionDismissalRequested(reason: reason, completion: { [weak self, weak child] in
               guard let self, let child else { return }
               self.removeModalChild(child, reason: reason)
           }) {
            return
        }
        removeModalChild(child, reason: reason)
    }

    // Actually remove a modal (active or queued) and clean up its session / callbacks.
    func removeModalChild(_ child: WindowController,
                          reason: ModalDismissReason = .byParent) {
        var removedEntry: ModalChildEntry?
        var wasFirst = false
        modalChildren.withLock { entries in
            if let i = entries.firstIndex(where: { $0.controller === child }) {
                wasFirst = (i == 0)
                removedEntry = entries.remove(at: i)
            }
        }
        child.parentWindow = nil

        if let e = removedEntry {
            // Preference-driven: clean up binding + onDismiss.
            e.session.cleanup(reason: reason)
            // Close the platform window if one was created.
            let ctrl = child
            Task { @MainActor [weak self, ctrl] in
                if let w = ctrl.window {
                    self?.window?.dismissModalWindow(w)
                    w.close()
                }
            }
        }

        if wasFirst { _showNextInQueue() }
    }


    func dismissAllModalWindows() {
        let entries = modalChildren.withLock { entries in
            defer { entries.removeAll() }
            return entries
        }
        for (i, entry) in entries.enumerated() {
            let child = entry.controller
            child.parentWindow = nil
            // first (index 0) was active, so byParent; rest were queued and never shown, so cancelled.
            let reason: ModalDismissReason = (i == 0) ? .byParent : .cancelled
            entry.session.cleanup(reason: reason)
        }
    }

    // MARK: - Preference-driven presentation (sheet / alert)

    // Sheet and alert presentations go through the unified modalChildren queue.

    /// Called from ViewGraph side-effect rule when SheetPreference.Key changes.
    func updateSheetPresentation(_ value: SheetPreference.Value) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(#function) must be called from within an AG context (side-effect rule).")
        }
        func rootContent(for pref: SheetPreference) -> AnyView {
            // The platform hosting root wraps erased presentation content in SheetContent.
            AnyView(SheetContent(content: pref.content))
        }
        let incoming: [SheetPreference]
        switch value {
        case .single(let pref): incoming = [pref]
        case .keyed:            incoming = []
        case .none:             incoming = []
        }

        func sid(_ p: SheetPreference) -> Namespace.ID {
            p.namespaceID
        }

        // Collect existing sheet sessions from the queue.
        let existing: [(Namespace.ID, WindowController)] = modalChildren.withLock {
            $0.compactMap { entry in
                guard case .sheet(let p) = entry.session else { return nil }
                return (sid(p), entry.controller)
            }
        }
        let incomingIDs = Set(incoming.map(sid))

        // Dismiss sessions that are no longer in incoming.
        for (id, ctrl) in existing {
            if !incomingIDs.contains(id) {
                notifyModalChildDismissalRequested(ctrl, reason: .dismissed)
            }
        }

        // Update existing sessions and enqueue new ones.
        let transaction = Transaction._current?.transaction ?? Transaction()
        for pref in incoming {
            let existingContentAttr: Attribute<AnyView>? = modalChildren.withLock { entries in
                guard let index = entries.firstIndex(where: {
                    guard case .sheet(let existing) = $0.session else { return false }
                    return sid(existing) == sid(pref)
                }) else {
                    return nil
                }
                entries[index].session = .sheet(pref)
                return entries[index].contentAttr
            }
            if let existingContentAttr {
                existingContentAttr.setValue(rootContent(for: pref), transaction: transaction)
                continue
            }

            let contentAttr: Attribute<AnyView> = graph.makeInput(value: rootContent(for: pref))

            let sheetKey = WindowKey(namespace: scene.namespace, sceneID: scene.sceneID)
            // ModalWindowController owns the modal-specific child policy:
            // fit content after layout, auto-resize the platform child, and keep
            // modal lifecycle hooks separate from the base window controller.
            //
            // FIXME: finalize the sheet bridge before this becomes the final architecture.
            let ctrl = ModalWindowController(crossGraphContent: contentAttr,
                                             sourceGraph: graph,
                                             scene: sheetKey,
                                             parentController: self,
                                             usesPlatformWindow: pref.usesPlatformWindow)
            addModalChild(ctrl, session: .sheet(pref), contentAttr: contentAttr) { [weak ctrl] attach in
                ctrl?.resolveModalWindowAttachment(attach)
            }

        }
    }

    /// Called from ViewGraph side-effect rule when ConfirmationDialogStorage.PreferenceKey changes.
    func updateConfirmationDialogPresentation(_ dialogs: [ConfirmationDialogPreference]) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(#function) must be called from within an AG context (side-effect rule).")
        }
        func sid(_ p: ConfirmationDialogPreference) -> ObjectIdentifier {
            ObjectIdentifier(p.isPresented.location)
        }
        let existing: [(ObjectIdentifier, WindowController)] = modalChildren.withLock {
            $0.compactMap { entry in
                guard case .confirmationDialog(let p) = entry.session else { return nil }
                return (sid(p), entry.controller)
            }
        }
        let existingIDs = Set(existing.map { $0.0 })
        for (id, ctrl) in existing {
            if !dialogs.contains(where: { sid($0) == id }) {
                notifyModalChildDismissalRequested(ctrl, reason: .dismissed)
            }
        }
        for pref in dialogs {
            guard !existingIDs.contains(sid(pref)) else { continue }
            let content = ConfirmationDialogOverlayView(preference: pref)
            let attr: Attribute<AnyView> = graph.makeInput(value: AnyView(content))
            let key = WindowKey(namespace: scene.namespace, sceneID: scene.sceneID)
            let ctrl = ModalWindowController(crossGraphContent: attr,
                                             sourceGraph: graph,
                                             scene: key,
                                             parentController: self,
                                             usesPlatformWindow: pref.usesPlatformWindow)
            addModalChild(ctrl, session: .confirmationDialog(pref)) { [weak ctrl] attach in
                ctrl?.resolveModalWindowAttachment(attach)
            }
        }
    }

    /// Called from ViewGraph side-effect rule when AlertStorage.PreferenceKey changes.
    func updateAlertPresentation(_ alerts: [AlertPreference]) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(#function) must be called from within an AG context (side-effect rule).")
        }
        func sid(_ p: AlertPreference) -> ObjectIdentifier {
            ObjectIdentifier(p.isPresented.location)
        }

        let existing: [(ObjectIdentifier, WindowController)] = modalChildren.withLock {
            $0.compactMap { entry in
                guard case .alert(let p) = entry.session else { return nil }
                return (sid(p), entry.controller)
            }
        }
        let existingIDs = Set(existing.map { $0.0 })

        // Dismiss removed alerts.
        for (id, ctrl) in existing {
            if !alerts.contains(where: { sid($0) == id }) {
                notifyModalChildDismissalRequested(ctrl, reason: .dismissed)
            }
        }

        // Enqueue new alerts as overlay controllers.
        for pref in alerts {
            guard !existingIDs.contains(sid(pref)) else { continue }

            let alertContent = AlertOverlayView(preference: pref)
            let alertAttr: Attribute<AnyView> = graph.makeInput(value: AnyView(alertContent))
            let alertKey = WindowKey(namespace: scene.namespace, sceneID: scene.sceneID)
            let ctrl = ModalWindowController(crossGraphContent: alertAttr,
                                             sourceGraph: graph,
                                             scene: alertKey,
                                             parentController: self,
                                             usesPlatformWindow: pref.usesPlatformWindow)
            addModalChild(ctrl, session: .alert(pref)) { [weak ctrl] attach in
                ctrl?.resolveModalWindowAttachment(attach)
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
