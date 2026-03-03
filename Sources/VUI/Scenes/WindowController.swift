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

// WindowController  View content, AG graph, and aux/modal window management.
// Non-generic: the Content type is used only at init for AG wiring, then discarded.
// Optionally owns a WindowContext — created lazily on the first makeWindow() call.
// Overlay-mode aux/modal controllers never call makeWindow(), so windowContext stays nil.
class WindowController: AuxiliaryWindowHost, ModalWindowHost,
                        WindowInputEventHandler, WindowDelegate, @unchecked Sendable {

    var windowContext: WindowContext?

    // Title graph captured at init; read when updateContent() is implemented.
    private var _titleGraph: _GraphValue<Text>?
    private var _titleString: String = ""
    private var _style: PlatformWindowStyle

    var environment: EnvironmentValues
    var sharedContext: SharedContext
    let sceneResources: SceneResources

    // AG context — owns the view-tree AttributeGraph (GraphHost).
    // Created unconditionally in init; valid for the lifetime of this controller.
    let graph: AttributeGraph
    var date: Date // date of initialization, for animation timing reference

    // AG input nodes for the root of the view tree — updated on resize, environment change, etc.
    private(set) var viewSizeAttr: Attribute<ViewSize>? = nil
    private(set) var viewEnvAttr: Attribute<EnvironmentValues>? = nil
    private(set) var timeAttr: Attribute<Time>? = nil
    private(set) var phaseAttr: Attribute<Phase>? = nil

    // AG root outputs — set after Content._makeView(...) completes.
    private(set) var rootLayoutComputer: Attribute<LayoutComputer>? = nil
    private(set) var rootDisplayList: Attribute<DisplayList>? = nil
    private(set) var rootResourceList: Attribute<ResourceList>? = nil

    var title: String { _titleString }
    var style: PlatformWindowStyle { _style }

    // Creation-time window hints from scene modifiers (defaultSize, defaultPosition, …).
    // Applied when makeWindow() creates the platform window (stub: stored for future use).
    var sceneConfiguration: SceneConfiguration = SceneConfiguration()

    var filterGestureTypes: Bool = true
    var allowedGestureTypes: _PrimitiveGestureTypes = .all

    // true if the AG graph has been wired and the window is ready to render.
    var isValid: Bool { rootLayoutComputer != nil }

    let scene: WindowKey

    // Convenience passthrough to windowContext (nil when in overlay mode)
    var window: (any PlatformWindow)? { windowContext?.window }

    // config is stored locally; applied to WindowContext when makeWindow() creates it.
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
    

    init<Content: View>(content: _GraphValue<Content>,
                        title: _GraphValue<Text>? = nil,
                        style: PlatformWindowStyle = .genericWindow,
                        scene: WindowKey) {
        self._titleGraph = title  // AppGraph-side reference: stays live across syncWindowControllers updates
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
        // Snapshot the title string now; AppGraph has no periodic update cycle yet,
        // so this is the only safe moment to read the AppGraph-side title node.
        if let titleText = title.map({ $0._attribute.value }) {
            self._titleString = titleText._resolveText(in: EnvironmentValues())
        }

        // Create this window's own AttributeGraph (GraphHost).
        // All view-tree nodes belong to ownGraph; AppGraph is only used for scene-level wiring.
        let ownGraph = AttributeGraph()
        let time = Time(seconds: 0)

        var sizeAttrResult:  Attribute<ViewSize>?          = nil
        var envAttrResult:   Attribute<EnvironmentValues>? = nil
        var rootLCResult:    Attribute<LayoutComputer>?    = nil
        var rootDLResult:    Attribute<DisplayList>?       = nil
        var rootRLResult:    Attribute<ResourceList>?      = nil
        var timeAttrResult:  Attribute<Time>?              = nil
        var phaseAttrResult: Attribute<Phase>?             = nil

        AttributeGraph.$current.withValue(ownGraph) {
            // Bridge: lift the extracted content value into ownGraph as an input node.
            let contentAttr = ownGraph.makeInput(value: contentValue)
            let contentGV   = _GraphValue<Content>(_attribute: contentAttr)

            let timeAttr        = ownGraph.makeInput(value: time)
            let phaseAttr       = ownGraph.makeInput(value: Phase(value: 1))
            let transactionAttr = ownGraph.makeInput(value: Transaction())
            let envAttr         = ownGraph.makeInput(value: EnvironmentValues())
            let graphInputs = _GraphInputs(
                customInputs: PropertyList(),
                time: timeAttr,
                cachedEnvironment: MutableBox(CachedEnvironment(environment: envAttr)),
                phase: phaseAttr,
                transaction: transactionAttr,
                changedDebugProperties: 0,
                options: 0,
                mergedInputs: []
            )
            var prefKeys     = PreferenceKeys()
            prefKeys.insert(DisplayList.Key.self)
            prefKeys.insert(ResourceList.Key.self)
            
            let hostKeysAttr = ownGraph.makeInput(value: prefKeys)
            let prefsInputs  = PreferencesInputs(keys: prefKeys, hostKeys: hostKeysAttr)

            let transformAttr    = ownGraph.makeInput(value: ViewTransform.identity)
            let positionAttr     = ownGraph.makeInput(value: CGPoint.zero)
            let containerPosAttr = ownGraph.makeInput(value: CGPoint.zero)
            let sizeAttr         = ownGraph.makeInput(value: ViewSize(.zero))
            let viewInputs = _ViewInputs(
                base: graphInputs,
                preferences: prefsInputs,
                transform: transformAttr,
                position: positionAttr,
                containerPosition: containerPosAttr,
                size: sizeAttr,
                safeAreaInsets: OptionalAttribute(),
                containerSize: OptionalAttribute()
            )

            let outputs = Content._makeView(view: contentGV, inputs: viewInputs)

            // 1. collect DisplayList and ResourceList nodes from preferences
            let resourceNodes = outputs.preferences.values(for: ResourceList.Key.self)
            let displayNodes = outputs.preferences.values(for: DisplayList.Key.self)
            // 2. merge ResourceList
            if !resourceNodes.isEmpty {
                rootRLResult = ownGraph.makeRule {
                    var combined = ResourceList.Key.defaultValue
                    for nodeID in resourceNodes {
                        let list = Attribute<ResourceList>(nodeID).value
                        ResourceList.Key.reduce(value: &combined) { list }
                    }
                    return combined
                }
            }
            // 3. merge DisplayList
            if !displayNodes.isEmpty {
                rootDLResult = ownGraph.makeRule {
                    var combined = DisplayList.Key.defaultValue
                    for nodeID in displayNodes {
                        let list = Attribute<DisplayList>(nodeID).value
                        DisplayList.Key.reduce(value: &combined) { list }
                    }
                    return combined
                }
            }

            sizeAttrResult  = sizeAttr
            envAttrResult   = envAttr
            timeAttrResult  = timeAttr
            phaseAttrResult = phaseAttr
            rootLCResult    = outputs._layoutComputer.attribute
        }

        self.graph              = ownGraph
        self.viewSizeAttr       = sizeAttrResult
        self.viewEnvAttr        = envAttrResult
        self.timeAttr           = timeAttrResult
        self.phaseAttr          = phaseAttrResult
        self.rootLayoutComputer = rootLCResult
        self.rootResourceList   = rootRLResult
        self.rootDisplayList    = rootDLResult

        self.date = .now
    }

    deinit {
        sharedContext.gestureHandlers.removeAll()
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
    
    // Set by drawView() when AG nodes change during rendering (e.g. lazy-evaluated views).
    // Causes the next updateView() to force a redraw even if the update itself produced no changes.
    private var viewChangedWhileDrawing: Bool = false
    private var cachedContentSize: CGSize = .zero

    func updateFrame(tick: UInt64, delta: Double, date: Date,
                     contentSize: CGSize, shouldDrawFrame: Bool,
                     _ withGC: WindowContext.WithGraphicsContext) {

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

    // Per-frame AG evaluation: drains the inbox, pull-evaluates the dirty sub-graph,
    // then sets redraw = true if any AG node value changed.
    func updateView(tick: UInt64, delta: Double, date: Date,
                    contentSize: CGSize, redraw: inout Bool,
                    _ withGC: WindowContext.WithGraphicsContext) {
        guard let rootLayoutComputer else { return }

        let time = Time(seconds: date.timeIntervalSince(self.date))

        let sizeChanged = (contentSize != cachedContentSize)
        if sizeChanged {
            cachedContentSize = contentSize
        }

        AttributeGraph.$current.withValue(graph) {
            let changeSet = AttributeGraph.ChangeSet()
            AttributeGraph.$changeSet.withValue(changeSet) {
                
                // handle deferred mouse event
                let events = self.inputEvents.withLock { events in
                    defer { events.removeAll() }
                    return events
                }
                events.forEach {
                    switch $0 {
                    case .keyboard(let event):
                        self.onKeyboardEvent(event: event)
                    case .mouse(let event):
                        self.onMouseEvent(event: event)
                    }
                }
                
                // Flush @State / @Observable invalidations enqueued from arbitrary threads.

                // 1. drain queue
                graph.inbox.drain()
                graph.drainActions()

                // 2. update layout if needed
                if sizeChanged {
                    viewSizeAttr?.setValue(ViewSize(contentSize))
                }
                // 3. update time/tick inputs for animation interpolation.
                self.timeAttr?.setValue(time)

                // 4. load graphical resources if needed.
                if let resourceList = self.rootResourceList?.value,
                   !resourceList.items.isEmpty {
                    withGC(false) { context in
                        for task in resourceList.items {
                            task(context)
                        }
                    }

                    // update & synchronize from resource-loading
                    graph.inbox.drain()
                    graph.drainActions()
                }

                // 5. final update
                // Pull-evaluate the root LC and run the full layout pass.
                let lc = rootLayoutComputer.value
                let proposal = ProposedViewSize(width: cachedContentSize.width, height: cachedContentSize.height)
                let center = CGPoint(x: cachedContentSize.width / 2, y: cachedContentSize.height / 2)
                lc.place(at: center, anchor: .center, proposal: proposal)
            }
            redraw = !changeSet.ids.isEmpty || self.viewChangedWhileDrawing
        }
        self.viewChangedWhileDrawing = false

        // TODO: aux window updates (refactor target)
        // TODO: modal window updates (refactor target)
    }

    // Per-frame AG rendering: evaluates the display list inside the AG context
    // and records any node changes that occurred during drawing.
    func drawFrame(offset: CGPoint, _ context: GraphicsContext) {
        guard let rootDisplayList else { return }

        var context = context
        context.translateBy(x: offset.x, y: offset.y)

        AttributeGraph.$current.withValue(graph) {
            let changeSet = AttributeGraph.ChangeSet()
            AttributeGraph.$changeSet.withValue(changeSet) {
                // draw with DisplayList (with offset of top-left)
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

        // TODO: chain auxiliary window draw calls here (refactor target)
        // TODO: draw modal windows last (refactor target)
    }

    func layoutBounds(_ bounds: CGRect) -> CGRect { bounds }

    func shouldClose(window: any PlatformWindow) -> Bool {
        modalClients.isEmpty
    }

    // Lifecycle hooks  called by WindowContext.
    func onWindowCreated(_: any PlatformWindow) {}

    func onWindowClosing(_: any PlatformWindow) {
        // TODO: notify aux clients (refactor target)
        self.auxClients.forEach { $0.onHostWindowClosed() }
    }

    func onViewLoaded() {}
    func onViewLayoutUpdated() {}

    // Window event handling forwarded from WindowContext after state update.
    @MainActor
    func handleWindowEvent(event: WindowEvent) {
        switch event.type {
        case .closed:
            DispatchQueue.main.async {
                appContext?.checkWindowActivities()
            }
            // TODO: aux clients (refactor target)
            self.auxClients.forEach { $0.onHostWindowClosed() }

        case .hidden:
            // TODO: release focused views (Implement with AG)
            self.sharedContext.focusedViews.removeAll()
            self.sharedContext.gestureHandlers.forEach { $0.reset() }
            self.sharedContext.gestureHandlers.removeAll()

        case .activated:
            // TODO: aux clients (refactor target)
            self.auxClients.forEach { $0.onHostWindowActivated() }

        case .inactivated:
            // TODO: release focused views (Implement with AG)
            self.sharedContext.focusedViews.removeAll()
            self.sharedContext.gestureHandlers.forEach { $0.reset() }
            self.sharedContext.gestureHandlers.removeAll()
            // TODO: aux clients (refactor target)
            self.auxClients.forEach { $0.onHostWindowInactivated() }

        case .minimized:
            // TODO: release focused views (Implement with AG)
            self.sharedContext.focusedViews.removeAll()
            self.sharedContext.gestureHandlers.forEach { $0.reset() }
            self.sharedContext.gestureHandlers.removeAll()

        case .moved, .resized:
            // TODO: aux clients (refactor target)
            self.auxClients.forEach { $0.onHostWindowMoved() }

        default:
            break
        }
    }

    // Keyboard/Mouse routing  forwarded from WindowContext raw event receivers.
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

            Log.debug("WindowController.onKeyboardEvent: \(event)")
            if let _ = self.sharedContext.focusedViews[event.deviceID]?.value {
                fatalError("Implement with AG")
                // return focusedView.processKeyboardEvent(...)
            }
            return false
        }

        // TODO: aux window keyboard routing (refactor target)
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
            if event.type == .wheel {
                return false
            }

            return false
            //guard let view = self.view else { return false }

            var gestureHandlers = self.sharedContext.gestureHandlers
            defer {
                self.sharedContext.gestureHandlers = gestureHandlers
            }

            if gestureHandlers.isEmpty {
                if event.type == .buttonDown {
                    fatalError("Implement with AG")
                    // let location = event.location.applying(view.transformToContainer.inverted())
                    // let outputs = view.gestureHandlers(at: location)
                    // gestureHandlers = ...
                }
            }

            let activeHandlers = { (states: _GestureHandler.State...) -> [_GestureHandler] in
                gestureHandlers.compactMap {
                    if states.contains($0.state) { return $0 }
                    return nil
                }
            }

            gestureHandlers = activeHandlers(.ready, .processing)
            if gestureHandlers.isEmpty { return false }

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

        // TODO: aux window mouse routing (refactor target)
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
                    $0.initiatedGesture(from: handler.target, location: event.location)
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
        // TODO: aux window wheel routing (refactor target)
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

        // TODO: hit-test view tree and dispatch wheel event (Gesture system)
        return false
    }

    @discardableResult
    func handleMouseHover(at location: CGPoint, deviceID: Int, isTopMost: Bool) -> Bool {
        var topMost = isTopMost
        // TODO: aux window hover routing (refactor target)
        self.auxiliaryWindows.withLock({ $0.reversed() }).forEach { aux in
            if let offset = aux.frame?.origin {
                if let handler = aux.client?.auxiliaryWindowInputEventHandler() {
                    let loc = location - offset
                    if handler.handleMouseHover(at: loc, deviceID: deviceID, isTopMost: topMost) {
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
        // TODO: hit-test view tree and dispatch hover event (Gesture system)
        return isTopMost != topMost
    }

    func resetGestureHandlers() {
        let handlers = self.sharedContext.gestureHandlers
        handlers.forEach { $0.reset() }
        self.sharedContext.gestureHandlers.removeAll()
    }

    // Aux/Modal management  TODO: refactor for new scene architecture
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

    // key-based slot registry for modal dedup  covers both platform and overlay modals.
    // ModalWindowSceneContext is @unchecked Sendable; claimModalSlot/releaseModalSlot are
    // always called on the main thread (same pattern as modalContext in ModalWindowSceneContext).
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
