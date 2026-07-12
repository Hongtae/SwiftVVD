//
//  File: WindowController.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

// WindowController owns ViewGraph and drives rendering plus event dispatch.
// Non-generic: the Content type is used only at init for AG wiring, then discarded.
// Optionally owns a WindowContext, created lazily on the first makeWindow() call.
// Overlay-mode presentation-child/modal controllers never call makeWindow(), so windowContext stays nil.
//
// Conforms to ViewRendererHost plus ViewGraphRootValueUpdater as the platform host.
class WindowController: WindowDelegate,
                        ViewRendererHost, ViewGraphRootValueUpdater,
                        ViewGraphRenderDelegate,
                        ViewGraphDelegate,
                        GraphDelegate,
                        EventBindingSource, EventBindingManagerDelegate,
                        @unchecked Sendable {

    // MARK: - Types

    typealias AttachWindow = @MainActor (any PlatformWindow) -> Void
    typealias AttachWindowResolver = (AttachWindow?) -> Void

    // MARK: - Core State

    var windowContext: WindowContext?

    private var _titleGraph: _GraphValue<Text>?
    private var _titleString: String = ""
    private var _style: PlatformWindowStyle

    var environment: EnvironmentValues
    let sceneResources: SceneResources

    // Window-level gesture coordinator owned by the platform host.
    var gestureGraph: GestureGraph?
    private let eventBridge = EventBindingBridge()
    private var contextMenuRecognizer = ContextMenuRecognizer()
    private var menuPresentationTrigger = MenuPresentationTrigger()

    // MARK: - Platform Event Routing

    private struct KeyEventStreamKey: Hashable {
        var deviceID: Int
        var key: VirtualKey
    }

    // Platform event to EventID routing table.
    // WindowController maps backend device identifiers before forwarding events
    // to the gesture graph.
    private let _nextEventSerial: Atomic<Int> = Atomic(1)
    private var _touchEventIDs: [Int: EventID] = [:]    // deviceID to EventID (touch/stylus)
    private var _mouseEventID: EventID?                   // single mouse pointer EventID
    private var _spatialEventIDs: [Int: EventID] = [:]   // deviceID to spatial EventID (touch)
    private var _mouseSpatialEventID: EventID? = nil      // single mouse pointer spatial EventID
    private var _scrollEventID: EventID?
    private var _scrollTranslation: CGSize = .zero
    private var _wheelScrollEventID: EventID?
    private var _wheelScrollTranslation: CGSize = .zero

    // Pointer scrolling shares the pointer lifetime but keeps its own EventID so
    // tap and pan recognizers can resolve the same physical interaction independently.
    private struct PointerScrollKey: Hashable {
        var isTouch: Bool
        var deviceID: Int
    }
    private struct PointerScrollState {
        var eventID: EventID
        var translation: CGSize
        var previousLocation: CGPoint
    }
    private var _pointerScrollStates: [PointerScrollKey: PointerScrollState] = [:]
    private var _keyEventIDs: [KeyEventStreamKey: EventID] = [:]
    private var _hoverEventIDs: [Int: EventID] = [:]
    private var _magnifyEventID: EventID?
    private var _magnification: CGFloat = 1.0
    private var _rotateEventID: EventID?
    private var _rotation: Angle = .zero
    private var _activeEvents: [EventID: any EventType] = [:]  // current live event dict
    private var _hostTrackedEventIDs: Set<EventID> = []
    private var _hostForwardedEventIDs: Set<EventID> = []
    private let hoverEventDispatcher = HoverEventDispatcher()
    private let keyEventDispatcher = KeyEventDispatcher()
    private var _lastHoverRefresh: (location: CGPoint, deviceID: Int, isTopMost: Bool)?

    private func nextEventSerial() -> Int {
        _nextEventSerial.wrappingAdd(1, ordering: .relaxed).oldValue
    }

    private func configureGestureEventBridge() {
        guard let gestureGraph else { return }
        gestureGraph.eventBindingManager.host = gestureGraph
        gestureGraph.eventBindingManager.delegate = self
        eventBridge.manager = gestureGraph.eventBindingManager
        eventBridge.addEventSource(self)
        gestureGraph.delegate = eventBridge
    }

    private func sendRecognizerOwnedEvents(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> GesturePhase<Void> {
        configureGestureEventBridge()
        _ = eventBridge.send(events, source: self, at: time)
        return eventBridge.lastPhase
    }

    private func sendHostEvents(
        _ events: [EventID: any EventType],
        track: Bool,
        at time: Time
    ) -> Set<EventID> {
        configureGestureEventBridge()
        guard let manager = gestureGraph?.eventBindingManager else { return [] }
        guard track else {
            let phase = manager.send(events, at: time)
            let directConsumed = manager.lastDirectConsumedEventIDs
            if !directConsumed.isEmpty {
                return directConsumed
            }
            switch phase {
            case .active, .ended:
                return Set(events.keys)
            case .possible, .failed:
                return []
            }
        }

        var outbound: [EventID: any EventType] = [:]
        var consumed: Set<EventID> = []
        for (eventID, event) in events {
            let forwardsTrackedUpdates = event is KeyEvent
            switch event.eventPhase {
            case .began:
                _hostTrackedEventIDs.insert(eventID)
                _hostForwardedEventIDs.insert(eventID)
                outbound[eventID] = event
                consumed.insert(eventID)
            case .moved:
                if forwardsTrackedUpdates || !_hostForwardedEventIDs.contains(eventID) {
                    _hostTrackedEventIDs.insert(eventID)
                    _hostForwardedEventIDs.insert(eventID)
                    outbound[eventID] = event
                    consumed.insert(eventID)
                }
            case .ended, .cancelled:
                if forwardsTrackedUpdates || !_hostForwardedEventIDs.contains(eventID) {
                    outbound[eventID] = event
                    consumed.insert(eventID)
                }
                _hostTrackedEventIDs.remove(eventID)
                _hostForwardedEventIDs.remove(eventID)
            }
        }
        if !outbound.isEmpty {
            _ = manager.send(outbound, at: time)
        }
        return consumed
    }

    private func eventPhase(from gesturePhase: GestureEventPhase) -> EventPhase {
        switch gesturePhase {
        case .began: return .began
        case .changed: return .moved
        case .ended: return .ended
        case .cancelled: return .cancelled
        }
    }

    private func keyCharacter(for key: VirtualKey) -> Character? {
        switch key {
        case .a: return "a"
        case .b: return "b"
        case .c: return "c"
        case .d: return "d"
        case .e: return "e"
        case .f: return "f"
        case .g: return "g"
        case .h: return "h"
        case .i: return "i"
        case .j: return "j"
        case .k: return "k"
        case .l: return "l"
        case .m: return "m"
        case .n: return "n"
        case .o: return "o"
        case .p: return "p"
        case .q: return "q"
        case .r: return "r"
        case .s: return "s"
        case .t: return "t"
        case .u: return "u"
        case .v: return "v"
        case .w: return "w"
        case .x: return "x"
        case .y: return "y"
        case .z: return "z"
        case .num0, .pad0: return "0"
        case .num1, .pad1: return "1"
        case .num2, .pad2: return "2"
        case .num3, .pad3: return "3"
        case .num4, .pad4: return "4"
        case .num5, .pad5: return "5"
        case .num6, .pad6: return "6"
        case .num7, .pad7: return "7"
        case .num8, .pad8: return "8"
        case .num9, .pad9: return "9"
        case .period, .padPeriod: return "."
        case .comma: return ","
        case .slash, .padSlash: return "/"
        case .accentTilde: return "`"
        case .semicolon: return ";"
        case .quote: return "'"
        case .backslash: return "\\"
        case .equal, .padEqual: return "="
        case .hyphen, .padMinus: return "-"
        case .padAsterisk: return "*"
        case .padPlus: return "+"
        case .openBracket: return "["
        case .closeBracket: return "]"
        default: return nil
        }
    }

    private func keyEquivalent(for event: KeyboardEvent) -> KeyEquivalent? {
        if let character = event.text.first {
            return KeyEquivalent(character)
        }
        if let character = keyCharacter(for: event.key) {
            return KeyEquivalent(character)
        }
        switch event.key {
        case .escape: return .escape
        case .tab: return .tab
        case .space: return .space
        case .return, .enter: return .return
        case .backspace: return .delete
        case .delete: return .deleteForward
        case .home: return .home
        case .end: return .end
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .up: return .upArrow
        case .down: return .downArrow
        case .left: return .leftArrow
        case .right: return .rightArrow
        default: return nil
        }
    }

    private func keyCharacters(for event: KeyboardEvent) -> String {
        if !event.text.isEmpty {
            return event.text
        }
        if let character = keyCharacter(for: event.key) {
            return String(character)
        }
        if event.key == .space {
            return " "
        }
        return ""
    }

    private func eventModifiers(from flags: KeyboardModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.numericPad) { modifiers.insert(.numericPad) }
        if flags.contains(.function) { modifiers.insert(.function) }
        return modifiers
    }

    private func keyEventPhase(for event: KeyboardEvent) -> EventPhase? {
        switch event.type {
        case .keyDown:
            return event.isRepeat ? .moved : .began
        case .keyUp:
            return .ended
        case .textInput, .textComposition:
            return nil
        }
    }

    private func keyEventID(for event: KeyboardEvent) -> EventID {
        let streamKey = KeyEventStreamKey(deviceID: event.deviceID, key: event.key)
        switch event.type {
        case .keyDown:
            if event.isRepeat, let eventID = _keyEventIDs[streamKey] {
                return eventID
            }
            let eventID = EventID(type: KeyEvent.self, serial: nextEventSerial())
            _keyEventIDs[streamKey] = eventID
            return eventID
        case .keyUp:
            return _keyEventIDs.removeValue(forKey: streamKey)
                ?? EventID(type: KeyEvent.self, serial: nextEventSerial())
        case .textInput, .textComposition:
            return EventID(type: KeyEvent.self, serial: nextEventSerial())
        }
    }

    private func keyEvent(from event: KeyboardEvent) -> KeyEvent? {
        guard let phase = keyEventPhase(for: event) else { return nil }
        return KeyEvent(
            key: keyEquivalent(for: event),
            virtualKey: event.key,
            characters: keyCharacters(for: event),
            phase: phase,
            modifiers: eventModifiers(from: event.modifiers)
        )
    }

    func requestHoverUpdate(in manager: EventBindingManager) {
        manager.clearHoverUpdatePending()
        eventBridge.requestHoverUpdate()
        if let hover = _lastHoverRefresh {
            _ = sendHoverEvent(at: hover.location,
                               deviceID: hover.deviceID,
                               isTopMost: hover.isTopMost)
            eventBridge.flushActions()
        }
    }

    func receiveDirectEvents(
        _ events: [EventID: any EventType],
        in manager: EventBindingManager
    ) -> Set<EventID> {
        let rootResponder = gestureGraph?.rootResponder
        let enqueueAction = { [weak self] action in
            if let gestureGraph = self?.gestureGraph {
                gestureGraph.enqueueAction(action)
            } else {
                action()
            }
        }
        var consumed = hoverEventDispatcher.receiveEvents(
            events,
            rootResponder: rootResponder,
            enqueueAction: enqueueAction
        )
        consumed.formUnion(keyEventDispatcher.receiveEvents(
            events,
            rootResponder: rootResponder,
            enqueueAction: enqueueAction
        ))
        return consumed
    }

    // MARK: - View Graph State

    // Owns the view-tree _AGGraph and root output attributes.
    // _viewGraph is an implicitly unwrapped optional because GestureGraph must be
    // created and wired before ViewGraph.init runs _makeView.
    var viewGraph: ViewGraph { _viewGraph }
    private var _viewGraph: ViewGraph!
    private weak var crossGraphSourceGraph: _AGGraph?

    var date: Date  // render loop timing reference (animation)

    var title: String { _titleString }
    var style: PlatformWindowStyle { _style }

    var sceneConfiguration: SceneConfiguration = SceneConfiguration()
    var filterGestureTypes: Bool = true
    var allowedGestureTypes: _PrimitiveGestureTypes = .all
    var endSessionOnWindowClosed: Bool { true }

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

    // MARK: - Input Queue

    enum InputEvent: @unchecked Sendable {
        case keyboard(KeyboardEvent, Time)
        case mouse(MouseEvent, Time)
        case gesture(GestureEvent, Time)
        case action(@Sendable () -> Void)
    }
    private let inputEvents = Mutex<[InputEvent]>([])
    private struct InputTimeReference {
        var source: TimeInterval
        var local: Time
    }
    private let mouseInputTimeReference = Mutex<InputTimeReference?>(nil)

    // Input samples and graph frames must use the same epoch. Preserving the
    // receipt time here keeps queued samples distinct when rendering hitches.
    private var inputTimestamp: Time {
        Time(seconds: Date.now.timeIntervalSince(date))
    }

    private func inputTimestamp(for event: MouseEvent) -> Time {
        let receiptTime = inputTimestamp
        guard event.timestamp.isFinite, event.timestamp > 0 else {
            return receiptTime
        }
        return mouseInputTimeReference.withLock { reference in
            if let current = reference {
                let elapsed = event.timestamp - current.source
                if elapsed >= 0 {
                    return current.local + elapsed
                }
            }
            reference = InputTimeReference(
                source: event.timestamp,
                local: receiptTime
            )
            return receiptTime
        }
    }

    func enqueueInputAction(_ action: @escaping @Sendable () -> Void) {
        inputEvents.withLock { events in
            events.append(.action(action))
        }
    }

    // ViewRendererHost / ViewGraphOwner stored state.
    // WindowController tracks its owner-side state separately from ViewGraph's internal state.
    var currentTimestamp: Time = Time(seconds: 0)
    private let displayListRenderer = DisplayList.GraphicsRenderer()
    var valuesNeedingUpdate: ViewGraphRootValues = []
    var renderingPhase: ViewRenderingPhase = ViewRenderingPhase()
    var externalUpdateCount: Int = 0

    // ViewRendererHost
    var responderNode: ResponderNode? { gestureGraph?.rootResponder }

    // MARK: - Initialization

    init<Content: View>(content: _GraphValue<Content>,
                        title: _GraphValue<Text>? = nil,
                        style: PlatformWindowStyle = .genericWindow,
                        scene: WindowKey) {
        self._titleGraph = title
        self._style = style
        self.environment = EnvironmentValues.tracking()
        self.sceneResources = SceneResources()
        self.windowContext = nil
        self.scene = scene

        // Extract current values from the caller's AG context (AppGraph).
        // init must be called from within an active AG context (e.g. AppGraph.syncWindowControllers).
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self).init called outside an active _AGGraph context.")
        }
        let contentValue = content._attribute.value
        if let titleText = title.map({ $0._attribute.value }) {
            self._titleString = titleText._resolveText(in: EnvironmentValues())
        }
        self.date = .now

        // Create GestureGraph first. It owns an independent AG from ViewGraph.
        self.gestureGraph = GestureGraph()
        // Wire rendererHost back-reference before ViewGraph.init. GestureResponder.init
        // reads viewGraph.rendererHost?.gestureGraph during _makeView.
        self.gestureGraph!.rendererHost = self
        configureGestureEventBridge()

        // Create ViewGraph with full AG wiring, including _makeView responder construction.
        // rendererHost: self must be set on GestureGraph before this call.
        self._viewGraph = ViewGraph(rootViewType: Content.self, content: contentValue, rendererHost: self)
        self.crossGraphSourceGraph = nil
        
        // Wire ViewGraph delegate slots.
        // renderDelegate: WindowController provides contentsScale, opaqueBackground, and
        //   render thread handling. Implemented below (ViewGraphRenderDelegate).
        self.viewGraph.renderDelegate = self
        self.viewGraph.viewDelegate = self
        self.viewGraph.graphDelegate = self
        // updateDelegate: WindowController provides root value updates (size, env, etc.).
        self.viewGraph.updateDelegate = self
        // delegate (ViewGraphHostDelegate): not wired yet. Root input attributes
        // are updated directly through ViewGraphRootValueUpdater for now.
        // self.viewGraph.delegate = self
    }

    init<Content: View>(content: Content,
                        scene: WindowKey) {
        self._titleGraph = nil
        self._style = .genericWindow
        self.environment = EnvironmentValues.tracking()
        self.sceneResources = SceneResources()
        self.windowContext = nil
        self.scene = scene
        self.date = .now

        self.gestureGraph = GestureGraph()
        self.gestureGraph!.rendererHost = self
        configureGestureEventBridge()

        self._viewGraph = ViewGraph(replaceableContent: content, rendererHost: self)
        self.crossGraphSourceGraph = nil
        self.viewGraph.renderDelegate = self
        self.viewGraph.viewDelegate = self
        self.viewGraph.graphDelegate = self
        self.viewGraph.updateDelegate = self
    }

    deinit {
        endPresentationSession()
    }

    // Sheet-specific init: content comes from a reactive attribute in a parent AG.
    // The ViewGraph creates a crossGraphRef to mirror the parent's attribute, so that
    // when parent state changes, parent contentAttr re-evaluates and the child graph updates.
    // contentAttr must already have a non-nil cached value in sourceGraph before this is called.
    init(crossGraphContent contentAttr: Attribute<AnyView>,
         sourceGraph: _AGGraph,
         scene: WindowKey) {
        self._titleGraph = nil
        self._style = .genericWindow
        self.environment = EnvironmentValues.tracking()
        self.sceneResources = SceneResources()
        self.windowContext = nil
        self.scene = scene
        self.date = .now

        self.gestureGraph = GestureGraph()
        self.gestureGraph!.rendererHost = self
        configureGestureEventBridge()

        self._viewGraph = ViewGraph(
            crossGraphContentAttr: contentAttr,
            sourceGraph: sourceGraph,
            rendererHost: self
        )
        self.crossGraphSourceGraph = sourceGraph
        self.viewGraph.renderDelegate = self
        self.viewGraph.viewDelegate = self
        self.viewGraph.graphDelegate = self
        self.viewGraph.updateDelegate = self
    }

    // MARK: - Platform Window Lifecycle

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
            ctx.preferredFrameInterval = { [weak self] in
                guard let self else { return nil }
                return self.renderIntervalForDisplayLink(timestamp: self.currentTimestamp)
            }
            ctx.onFinalize = { [weak self] in
                guard let self, self.endSessionOnWindowClosed else { return }
                self.endPresentationSession()
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
                guard let self else { return }
                let time = self.inputTimestamp
                self.inputEvents.withLock { events in
                    events.append(.keyboard(event, time))
                }
            }
            window.addEventObserver(self) { [weak self] (event: MouseEvent) in
                guard let self else { return }
                let time = self.inputTimestamp(for: event)
                self.inputEvents.withLock { events in
                    events.append(.mouse(event, time))
                }
            }
            window.addEventObserver(self) { [weak self] (event: GestureEvent) in
                guard let self else { return }
                let time = self.inputTimestamp
                self.inputEvents.withLock { events in
                    events.append(.gesture(event, time))
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

    private static let displayLinkRequestDelayLimit: Double = 0.25

    var observesRootFittedSizeForLayoutUpdates: Bool { false }

    // MARK: - Frame Update and Rendering

    func layoutContentSize(from contentSize: CGSize) -> CGSize {
        contentSize
    }

    func updateFrame(tick: UInt64, delta: Double, date: Date,
                     contentSize: CGSize, shouldDrawFrame: Bool,
                     _ withGC: WindowContext.WithGraphicsContext) {

        // Pull render context from delegate (ViewGraphRenderDelegate).
        // contentsScale: HiDPI scale factor for the current display.
        // opaqueBackground: whether the background is fully opaque (skip alpha clear).
        // Refresh render context once per frame before updateOutputs/render.
        var renderCtx = ViewGraphRenderContext(contentsScale: 1.0, opaqueBackground: false)
        viewGraph.renderDelegate?.updateRenderContext(&renderCtx)
        // Pending parity: propagate renderCtx.contentsScale to draw calls.

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

    @discardableResult
    private func flushCrossGraphSourceIfNeeded() -> Bool {
        guard let sourceGraph = crossGraphSourceGraph else { return false }
        guard window == nil else {
            // Platform presentation children have their own render task. Their
            // source graph is owned by the parent window's update loop, so
            // draining it here would make one _AGGraph run on two threads.
            return false
        }
        let hadPendingWork = sourceGraph.inbox.hasPendingWork ||
            !sourceGraph.actionOutbox.isEmpty
        _AGGraph.withCurrent(sourceGraph) {
            while sourceGraph.inbox.hasPendingWork {
                _ = sourceGraph.inbox.drainOne()
                sourceGraph.drainActions()
            }
        }
        let drainedOutbox = drainActionOutbox(sourceGraph)
        return hadPendingWork || drainedOutbox
    }

    @discardableResult
    private func drainActionOutbox(_ graph: _AGGraph) -> Bool {
        let actions = graph.actionOutbox
        guard !actions.isEmpty else { return false }
        graph.actionOutbox.removeAll()
        actions.forEach { $0() }
        return true
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

        let events = self.inputEvents.withLock { events in
            defer { events.removeAll() }
            return events
        }
        let hadRootValueUpdates = !viewGraph.valuesNeedingUpdate.isEmpty
        let hadScheduledViewUpdate = viewGraph.hasScheduledViewUpdate
        let hadGraphWork = viewGraph.hasPendingTransactions ||
            viewGraph.hasPendingGraphMutations ||
            viewGraph.data.graph.inbox.hasPendingWork ||
            !viewGraph.data.graph.actionOutbox.isEmpty
        let hadViewChangedWhileDrawing = self.viewChangedWhileDrawing

        var needsLayoutPass = !hasDeliveredViewLayoutUpdate ||
            sizeChanged ||
            hadRootValueUpdates ||
            hadGraphWork ||
            hadViewChangedWhileDrawing

        var flushedCrossGraphSource = false
        var drainedGestureOutbox = false
        var drainedViewOutbox = false
        var loadedResources = false

        func runRootLayoutPass(
            notifiesLayoutUpdate: Bool,
            samplesDisplayList: Bool = false
        ) -> Bool {
            let layoutChangeSet = _AGChangeSet()
            _AGGraph.withChangeSet(layoutChangeSet) {
                // Layout pass: determine root view size/position after AG evaluation completes.
                viewGraph.data.withCurrent {
                    let lc = rootLayoutComputer.value
                    let proposal = ProposedViewSize(width: cachedContentSize.width,
                                                   height: cachedContentSize.height)
                    let center = CGPoint(x: cachedContentSize.width / 2,
                                         y: cachedContentSize.height / 2)
                    lc.place(at: center, anchor: .center, proposal: proposal)

                    if samplesDisplayList, let rootDisplayList = viewGraph.rootDisplayList {
                        _ = rootDisplayList.value
                    }
                    if samplesDisplayList, let rootResourceList = viewGraph.rootResourceList {
                        _ = rootResourceList.value
                    }

                    guard notifiesLayoutUpdate else { return }
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
                        // Modal/presentation-child controllers use this hook to fit their platform
                        // window after AG layout values are available. The hook is
                        // driven by the root fitted-size rule rather than the host
                        // window's proposed sizeAttr, because resource/content
                        // changes can alter natural modal size without changing the
                        // platform content size first.
                        onViewLayoutUpdated()
                    }
                }
                drainedViewOutbox = drainActionOutbox(viewGraph.data.graph) || drainedViewOutbox
            }
            return !layoutChangeSet.isEmpty
        }

        func loadRootResourcesIfNeeded() -> Bool {
            var didLoadResources = false
            viewGraph.data.withCurrent {
                guard let resourceList = viewGraph.rootResourceList?.value,
                      !resourceList.items.isEmpty else {
                    return
                }
                didLoadResources = true
                withGC(false) { context in
                    for task in resourceList.items {
                        task(context)
                    }
                }
            }
            return didLoadResources
        }

        let updateChangeSet = _AGChangeSet()
        _AGGraph.withChangeSet(updateChangeSet) {

            // Drain platform input events before AG evaluation.
            events.forEach {
                switch $0 {
                case .keyboard(let event, let time):
                    self.onKeyboardEvent(event: event, at: time)
                case .mouse(let event, let time):
                    self.onMouseEvent(event: event, at: time)
                case .gesture(let event, let time):
                    self.handleGestureEvent(event: event, at: time)
                case .action(let action):  action()
                }
            }

            // Gesture deadlines are evaluated on the same controller-relative
            // clock as input samples. This wakes recognizers that remain possible
            // between input IDs, such as the single-tap fallback beside a double tap.
            if let gestureGraph,
               gestureGraph.updateTimedGestures(at: time) {
                drainedGestureOutbox = true
            }

            // Drain GestureGraph's action outbox - closures deferred from within GestureGraph
            // AG evaluation (enqueueAction fallback). Run here, outside any AG context,
            // after gesture events are fully processed.
            if let gg = self.gestureGraph {
                let actions = gg.data.graph.actionOutbox
                if !actions.isEmpty {
                    drainedGestureOutbox = true
                    gg.data.graph.actionOutbox.removeAll()
                    actions.forEach { $0() }
                }
            }

            // updateOutputs flushes dirty bits, async changes, then evaluates AG.
            // Internally: data.withCurrent, inbox drain, dirty root update, time update.
            flushedCrossGraphSource = flushCrossGraphSourceIfNeeded()
            var lastViewInboxTransaction: Transaction?
            while viewGraph.data.graph.inbox.hasPendingWork {
                viewGraph.beginNextUpdate(at: time)
                viewGraph.data.withCurrent {
                    lastViewInboxTransaction = viewGraph.data.graph.inbox.drainOne()
                    viewGraph.data.graph.drainActions()
                }
                viewGraph.setCurrentUpdateTransaction(lastViewInboxTransaction)
                drainedViewOutbox = drainActionOutbox(viewGraph.data.graph) || drainedViewOutbox
                let currentRequiresPresentation =
                    lastViewInboxTransaction?.effectiveAnimation != nil ||
                    lastViewInboxTransaction?.hasLocalAnimationCompletionState == true
                let nextTransaction = viewGraph.data.graph.inbox.nextTransaction
                let nextRequiresPresentation =
                    nextTransaction?.effectiveAnimation != nil ||
                    nextTransaction?.hasLocalAnimationCompletionState == true
                // Plain writes queued in the same frame do not own an observable
                // presentation boundary. Animated and completion-owning writes
                // still sample the current outputs before the next transaction.
                let coalescesPlainWrites =
                    !currentRequiresPresentation &&
                    !nextRequiresPresentation
                if viewGraph.data.graph.inbox.hasPendingWork,
                   !coalescesPlainWrites {
                    _ = runRootLayoutPass(
                        notifiesLayoutUpdate: false,
                        samplesDisplayList: true
                    )
                    if loadRootResourcesIfNeeded() {
                        loadedResources = true
                        _ = runRootLayoutPass(
                            notifiesLayoutUpdate: false,
                            samplesDisplayList: true
                        )
                    }
                }
            }
            viewGraph.setCurrentUpdateTransaction(lastViewInboxTransaction)
            viewGraph.updateOutputs(at: time)
            drainedViewOutbox = drainActionOutbox(viewGraph.data.graph) || drainedViewOutbox

            // Resource loading: requires GraphicsContext, handled separately after updateOutputs.
            if loadRootResourcesIfNeeded() {
                loadedResources = true
                viewGraph.data.withCurrent {
                    var lastResourceTransaction: Transaction?
                    while viewGraph.data.graph.inbox.hasPendingWork {
                        viewGraph.beginNextUpdate(at: time)
                        lastResourceTransaction = viewGraph.data.graph.inbox.drainOne()
                        viewGraph.data.graph.drainActions()
                        viewGraph.setCurrentUpdateTransaction(lastResourceTransaction)
                    }
                    drainedViewOutbox = drainActionOutbox(viewGraph.data.graph) || drainedViewOutbox
                }
            }
        }

        let updateChangedIDs = updateChangeSet.ids(for: viewGraph.data.graph)
        var clockIDs: Set<AGAttribute> = [
            viewGraph.data.updateSeedAttribute.identifier,
            viewGraph.data.transactionSeedAttribute.identifier
        ]
        if let timeID = viewGraph.timeAttr?.identifier {
            clockIDs.insert(timeID)
        }
        if let transactionID = viewGraph.transactionAttr?.identifier {
            clockIDs.insert(transactionID)
        }
        let meaningfulUpdateChange = updateChangedIDs.contains { id in
            !clockIDs.contains(id)
        }
        needsLayoutPass = needsLayoutPass ||
            flushedCrossGraphSource ||
            drainedGestureOutbox ||
            drainedViewOutbox ||
            loadedResources ||
            meaningfulUpdateChange

        var layoutChanged = false
        if needsLayoutPass {
            layoutChanged = runRootLayoutPass(notifiesLayoutUpdate: true)
        }
        // Preserve redraw requests raised earlier in this frame, including
        // child modal input handled during the parent event pass.
        let shouldRedrawFrame = redraw ||
            hadScheduledViewUpdate ||
            meaningfulUpdateChange ||
            layoutChanged ||
            flushedCrossGraphSource ||
            drainedGestureOutbox ||
            drainedViewOutbox ||
            loadedResources ||
            hadViewChangedWhileDrawing
        if shouldRedrawFrame, let rootDisplayList = viewGraph.rootDisplayList {
            var displayListChanged = false
            viewGraph.data.withCurrent {
                let displayListChangeSet = _AGChangeSet()
                _AGGraph.withChangeSet(displayListChangeSet) {
                    _ = rootDisplayList.value
                }
                displayListChanged = !displayListChangeSet.isEmpty
            }
            drainedViewOutbox = drainActionOutbox(viewGraph.data.graph) || drainedViewOutbox
            redraw = shouldRedrawFrame || displayListChanged || drainedViewOutbox
        } else {
            redraw = shouldRedrawFrame
        }
        self.viewChangedWhileDrawing = false

        // Overlay presentation children: update after self.
        for entry in self.presentationChildren.withLock({ $0 }) {
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
            let changeSet = _AGChangeSet()
            _AGGraph.withChangeSet(changeSet) {
                let displayList = rootDisplayList.value
                displayListRenderer.render(
                    list: displayList,
                    at: currentTimestamp,
                    in: context
                )
            }
            self.viewChangedWhileDrawing = !changeSet.isEmpty
        }
        if !(currentTimestamp < displayListRenderer.nextTime) {
            viewChangedWhileDrawing = true
        }
        if drainActionOutbox(viewGraph.data.graph) {
            viewChangedWhileDrawing = true
        }
        // Overlay presentation children: draw on top after self.
        for entry in self.presentationChildren.withLock({ $0 }) {
            guard entry.isOverlay, entry.initiated else { continue }
            // The graphics context is already translated into this controller's
            // coordinate space, so nested overlay children only apply their own
            // frame origin.
            entry.controller.drawFrame(offset: .zero, context)
        }
        // Overlay modal child (at most one): draw on top of everything.
        if let entry = self.modalChildren.withLock({ $0.first }),
           entry.isOverlay, entry.initiated {
            // Keep nested overlay modal positioning relative to the already
            // translated parent context.
            entry.controller.drawFrame(offset: .zero, context)
        }
    }

    func layoutBounds(_ bounds: CGRect) -> CGRect { bounds }

    // MARK: - WindowDelegate

    func shouldClose(window: any PlatformWindow) -> Bool {
        modalChildren.withLock { $0.isEmpty }
    }

    func onWindowCreated(_: any PlatformWindow) {}

    var appWindowsController: AppWindowsController? { appContext?.appWindowsController }

    // MARK: - Presentation Session Lifecycle

    func onParentWindowActivated() {
        forEachPresentationChild { $0.onParentWindowActivated() }
    }
    func onParentWindowInactivated() {
        forEachPresentationChild { $0.onParentWindowInactivated() }
    }
    func onParentWindowMoved() {
        forEachPresentationChild { $0.onParentWindowMoved() }
    }
    func onParentWindowClosed() {
        if endSessionOnWindowClosed {
            endPresentationSession()
        }
    }

    private var didEndPresentationSession = false
    func endPresentationSession() {
        guard !didEndPresentationSession else { return }
        didEndPresentationSession = true
        dismissAllPresentationChildren()
        dismissAllModalWindows()
        if let window {
            Task { @MainActor [weak window] in
                window?.close()
            }
        }
    }

    func forEachPresentationChild(_ body: (PresentationChildWindowController) -> Void) {
        self.presentationChildren.withLock { $0.map(\.controller) }
            .forEach(body)
    }

    func onViewLoaded() {}
    func onViewLayoutUpdated() {}

    // MARK: - Platform Window Events

    @MainActor
    func handleWindowEvent(event: WindowEvent) {
        switch event.type {
        case .closed:
            if endSessionOnWindowClosed {
                enqueueInputAction { [weak self] in
                    self?.endPresentationSession()
                }
            }
            DispatchQueue.main.async {
                appContext?.checkWindowActivities()
            }
        case .hidden:
            viewGraph.data.graph.inbox.enqueue { [weak self] in
                self?.gestureGraph!.resetEvents()
            }
        case .activated:
            enqueueInputAction { [weak self] in
                self?.forEachPresentationChild { $0.onParentWindowActivated() }
            }
        case .inactivated:
            viewGraph.data.graph.inbox.enqueue { [weak self] in
                self?.gestureGraph!.resetEvents()
            }
            enqueueInputAction { [weak self] in
                self?.forEachPresentationChild { $0.onParentWindowInactivated() }
            }
        case .minimized:
            viewGraph.data.graph.inbox.enqueue { [weak self] in
                self?.gestureGraph!.resetEvents()
            }
        case .geometryInvalidated, .resizeBegan:
            enqueueInputAction { [weak self] in
                self?.forEachPresentationChild { $0.onParentWindowMoved() }
            }
        case .moved, .resized:
            enqueueInputAction { [weak self] in
                self?.forEachPresentationChild { $0.onParentWindowMoved() }
            }
        default:
            break
        }
    }

    // MARK: - Input Dispatch

    func onKeyboardEvent(event: KeyboardEvent, at time: Time? = nil) {
        // Only route to overlay modal if fully initiated (async Task may still be pending).
        let topModal: ModalWindowController? = self.modalChildren.withLock {
            guard let e = $0.first, e.initiated, e.isOverlay else { return nil }
            return e.controller
        }
        if let topModal {
            topModal.onKeyboardEvent(event: event, at: time)
        } else {
            self.handleKeyboardEvent(event: event, at: time ?? currentTimestamp)
        }
    }

    func onMouseEvent(event: MouseEvent, at time: Time? = nil) {
        let topModal = self.modalChildren.withLock { $0.first }
        if let topModal, topModal.isOverlay, topModal.initiated {
            let modalController = topModal.controller
            var event = event
            event.location = modalController.presentationPointInLocal(
                fromParentPoint: event.location
            )
            // Re-enter the child's dispatch boundary so another overlay modal
            // can repeat the same conversion and routing at any nesting depth.
            modalController.onMouseEvent(event: event, at: time)
            return
        }

        if event.type == .wheel {
            self.handleMouseWheel(event: event, time: time ?? currentTimestamp)
        } else {
            self.handleMouseEvent(event: event, at: time ?? currentTimestamp)
            if event.type == .move || event.type == .buttonUp {
                self.handleMouseHover(at: event.location,
                                      deviceID: event.deviceID,
                                      isTopMost: true)
            }
        }
    }

    // MARK: - Input Handling

    private var _lastKeyboardEventHandler: ObjectIdentifier? = nil
    private var _lastMouseEventHandler: ObjectIdentifier? = nil

    @discardableResult
    func handleKeyboardEvent(event: KeyboardEvent) -> Bool {
        handleKeyboardEvent(event: event, at: currentTimestamp)
    }

    @discardableResult
    func handleKeyboardEvent(event: KeyboardEvent, at time: Time) -> Bool {
        let handleEvent = { (event: KeyboardEvent) -> Bool in
            if let window = self.window, window !== event.window { return false }
            self.contextMenuRecognizer.handleKeyboardEvent(event)
            var keyConsumed = false
            if let keyEvent = self.keyEvent(from: event) {
                let eventID = self.keyEventID(for: event)
                keyConsumed = !self.sendHostEvents(
                    [eventID: keyEvent],
                    track: true,
                    at: time
                ).isEmpty
            }
            Log.debug("WindowController.onKeyboardEvent: \(event)")
            return keyConsumed
        }

        var handlers = self.presentationChildren.withLock {
            $0.reversed().compactMap { entry -> (id: ObjectIdentifier, action: (KeyboardEvent) -> Bool)? in
                guard entry.isOverlay, entry.initiated else { return nil }
                let child = entry.controller
                return (id: ObjectIdentifier(child), action: { event in
                    child.handleKeyboardEvent(event: event, at: time)
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
        handleMouseEvent(event: event, at: currentTimestamp)
    }

    @discardableResult
    func handleMouseEvent(event: MouseEvent, at time: Time) -> Bool {
        let handleEvent = { (event: MouseEvent) -> Bool in
            if let window = self.window, window !== event.window { return false }
            if event.type == .wheel { return false }
            guard let rootResponder = self.gestureGraph?.rootResponder else {
                return false
            }
            let contextMenuConsumed = self.contextMenuRecognizer.handleMouseEvent(
                event,
                viewGraph: self.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { [weak self] sessionID, delay in
                    self?.scheduleContextMenuLongPress(sessionID: sessionID,
                                                       delay: delay)
                },
                open: { [weak self] responder, location in
                    guard let self else { return }
                    responder.present(from: self, at: location)
                }
            )
            if contextMenuConsumed {
                return true
            }
            let menuPresentationConsumed = self.menuPresentationTrigger.handleMouseEvent(
                event,
                viewGraph: self.viewGraph,
                rootResponder: rootResponder,
                open: { [weak self] responder in
                    guard let self else { return }
                    responder.present(from: self)
                }
            )
            if menuPresentationConsumed {
                return true
            }

            // Map backend device IDs to EventID values before forwarding to GestureGraph.
            let isTouch = event.device == .touch || event.device == .stylus
            let pointerScrollKey = PointerScrollKey(
                isTouch: isTouch,
                deviceID: isTouch ? event.deviceID : 0
            )

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
                if event.buttonID == 0 {
                    // Keep the scroll stream in the same batch as the tap/spatial
                    // streams so recognizers see one coherent pointer update.
                    let scrollEventID = EventID(type: ScrollEvent.self, serial: serial)
                    self._pointerScrollStates[pointerScrollKey] = PointerScrollState(
                        eventID: scrollEventID,
                        translation: .zero,
                        previousLocation: event.location
                    )
                    self._activeEvents[scrollEventID] = ScrollEvent(
                        delta: .zero,
                        translation: .zero,
                        previousTranslation: .zero,
                        location: event.location,
                        phase: .began
                    )
                }
                phase = self.sendRecognizerOwnedEvents(self._activeEvents, at: time)

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
                if var scrollState = self._pointerScrollStates[pointerScrollKey] {
                    // Accumulate from raw locations instead of backend deltas;
                    // some backends omit or coalesce the latter during a drag.
                    let delta = CGSize(
                        width: event.location.x - scrollState.previousLocation.x,
                        height: event.location.y - scrollState.previousLocation.y
                    )
                    let previousTranslation = scrollState.translation
                    scrollState.translation.width += delta.width
                    scrollState.translation.height += delta.height
                    scrollState.previousLocation = event.location
                    self._pointerScrollStates[pointerScrollKey] = scrollState
                    self._activeEvents[scrollState.eventID] = ScrollEvent(
                        delta: delta,
                        translation: scrollState.translation,
                        previousTranslation: previousTranslation,
                        location: event.location,
                        phase: .moved
                    )
                }
                phase = self.sendRecognizerOwnedEvents(self._activeEvents, at: time)

            case .buttonUp:
                let tapEventID: EventID?
                let spatialEventID: EventID?
                if isTouch {
                    tapEventID     = self._touchEventIDs.removeValue(forKey: event.deviceID)
                    spatialEventID = self._spatialEventIDs.removeValue(forKey: event.deviceID)
                } else {
                    tapEventID = self._mouseEventID
                    self._mouseEventID = nil
                    spatialEventID = self._mouseSpatialEventID
                    self._mouseSpatialEventID = nil
                }
                guard let tapEventID else { return false }
                self._activeEvents[tapEventID] = TappableEvent(
                    location: event.location, phase: .ended, buttonID: event.buttonID)
                if let spatialEventID {
                    self._activeEvents[spatialEventID] = SpatialEvent(
                        location: event.location, globalLocation: event.location,
                        phase: .ended, timestamp: time.seconds)
                }
                let scrollState = self._pointerScrollStates.removeValue(forKey: pointerScrollKey)
                if let scrollState {
                    let delta = CGSize(
                        width: event.location.x - scrollState.previousLocation.x,
                        height: event.location.y - scrollState.previousLocation.y
                    )
                    let previousTranslation = scrollState.translation
                    let translation = CGSize(
                        width: previousTranslation.width + delta.width,
                        height: previousTranslation.height + delta.height
                    )
                    self._activeEvents[scrollState.eventID] = ScrollEvent(
                        delta: delta,
                        translation: translation,
                        previousTranslation: previousTranslation,
                        location: event.location,
                        phase: .ended
                    )
                }
                phase = self.sendRecognizerOwnedEvents(self._activeEvents, at: time)
                self._activeEvents.removeValue(forKey: tapEventID)
                if let spatialEventID { self._activeEvents.removeValue(forKey: spatialEventID) }
                if let scrollState { self._activeEvents.removeValue(forKey: scrollState.eventID) }

            default:
                return false
            }
            switch phase {
            case .active, .ended:
                return true
            default:
                return false
            }
        }

        // Build handler list: presentation children (reversed = top-first) then self.
        var handlers = self.presentationChildren.withLock {
            $0.reversed().compactMap { entry -> (target: AnyObject, action: (MouseEvent) -> Bool)? in
                guard entry.isOverlay, entry.initiated else { return nil }
                guard entry.frame != nil else { return nil }
                let child = entry.controller
                return (target: child, action: { event in
                    let loc = child.presentationPointInLocal(
                        fromParentPoint: event.location
                    )
                    if child.overlayHitTest(loc) {
                        var e = event
                        e.location = loc
                        child.handleMouseEvent(event: e, at: time)
                        return true
                    }
                    return false
                })
            }
        }
        handlers.append((target: self as AnyObject, action: handleEvent))

        // Parent mouse-down deactivates any presentation child that was not the event target.
        // Platform child windows do not participate in the overlay hit-test path.
        let presentationChildren = event.type == .buttonDown
            ? self.presentationChildren.withLock { $0.map(\.controller) }
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
                presentationChildren.forEach {
                    if $0 === handler.target {
                        $0.onPresentationChildWindowActivated()
                    } else {
                        $0.onPresentationChildWindowInactivated()
                    }
                }
                return true
            }
        }
        _lastMouseEventHandler = nil
        presentationChildren.forEach {
            $0.onPresentationChildWindowInactivated()
        }
        return false
    }

    private func scheduleContextMenuLongPress(sessionID: UInt64,
                                              delay: TimeInterval) {
        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            self?.enqueueInputAction { [weak self] in
                guard let self,
                      let gg = self.gestureGraph,
                      let rootResponder = gg.rootResponder else {
                    return
                }
                _ = self.contextMenuRecognizer.fireLongPress(
                    sessionID: sessionID,
                    viewGraph: self.viewGraph,
                    rootResponder: rootResponder,
                    open: { [weak self] responder, location in
                        guard let self else { return }
                        responder.present(from: self, at: location)
                    }
                )
            }
        }
    }

    @discardableResult
    func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        handleMouseWheel(at: location, delta: delta, time: currentTimestamp)
    }

    @discardableResult
    func handleMouseWheel(at location: CGPoint, delta: CGPoint, time: Time) -> Bool {
        for entry in self.presentationChildren.withLock({ $0.reversed() }) {
            guard entry.isOverlay, entry.initiated else { continue }
            guard entry.frame != nil else { continue }
            let child = entry.controller
            let loc = child.presentationPointInLocal(fromParentPoint: location)
            if child.overlayHitTest(loc) {
                child.handleMouseWheel(at: loc, delta: delta, time: time)
                return true
            }
        }
        return dispatchDiscreteWheel(at: location, delta: delta, time: time)
    }

    @discardableResult
    private func handleMouseWheel(event: MouseEvent, time: Time) -> Bool {
        for entry in self.presentationChildren.withLock({ $0.reversed() }) {
            guard entry.isOverlay, entry.initiated else { continue }
            guard entry.frame != nil else { continue }
            let child = entry.controller
            let loc = child.presentationPointInLocal(fromParentPoint: event.location)
            if child.overlayHitTest(loc) {
                var childEvent = event
                childEvent.location = loc
                child.handleMouseWheel(event: childEvent, time: time)
                return true
            }
        }

        guard let scrollData = event.scrollData else {
            return dispatchDiscreteWheel(
                at: event.location,
                delta: event.delta,
                time: time
            )
        }

        // Native inertial samples are preserved by VVD for low-level clients,
        // but VUI uses one cross-platform deceleration model and must not apply
        // both streams to the same scroll view.
        if scrollData.nativeMomentumPhase != nil {
            return gestureGraph?.eventBinding(
                at: event.location,
                accepting: ScrollEvent.self
            ) != nil
        }

        guard let phase = scrollData.phase else {
            return dispatchDiscreteWheel(
                at: event.location,
                delta: event.delta,
                time: time
            )
        }
        return dispatchContinuousWheel(
            at: event.location,
            delta: event.delta,
            phase: phase,
            time: time
        )
    }

    private func dispatchDiscreteWheel(
        at location: CGPoint,
        delta: CGPoint,
        time: Time
    ) -> Bool {
        guard let gestureGraph else { return false }
        guard let binding = gestureGraph.eventBinding(
            at: location,
            accepting: SystemWheelEvent.self
        ) else {
            // Preserve the scalar wheel carrier for the legacy scroll route.
            guard delta.x == 0,
                  let legacyBinding = gestureGraph.eventBinding(
                    at: location,
                    accepting: WheelEvent.self
                  ) else { return false }
            let eventID = EventID(type: WheelEvent.self, serial: nextEventSerial())
            let began = WheelEvent(
                timestamp: time,
                phase: .began,
                binding: legacyBinding,
                offset: Double(delta.y)
            )
            let beganPhase = sendRecognizerOwnedEvents([eventID: began], at: time)
            let ended = WheelEvent(
                timestamp: time,
                phase: .ended,
                binding: legacyBinding,
                offset: Double(delta.y)
            )
            let endedPhase = sendRecognizerOwnedEvents([eventID: ended], at: time)
            switch (beganPhase, endedPhase) {
            case (.active, _), (.ended, _), (_, .active), (_, .ended):
                return true
            default:
                return false
            }
        }

        let eventID = EventID(type: SystemWheelEvent.self, serial: nextEventSerial())
        let gestureDelta = CGSize(width: -delta.x, height: -delta.y)
        let began = SystemWheelEvent(
            timestamp: time,
            phase: .began,
            binding: binding,
            delta: gestureDelta
        )
        let beganPhase = sendRecognizerOwnedEvents([eventID: began], at: time)
        let ended = SystemWheelEvent(
            timestamp: time,
            phase: .ended,
            binding: binding,
            delta: gestureDelta
        )
        let endedPhase = sendRecognizerOwnedEvents([eventID: ended], at: time)
        switch (beganPhase, endedPhase) {
        case (.active, _), (.ended, _), (_, .active), (_, .ended):
            return true
        default:
            return false
        }
    }

    private func dispatchContinuousWheel(
        at location: CGPoint,
        delta: CGPoint,
        phase: ScrollEventPhase,
        time: Time
    ) -> Bool {
        if phase == .mayBegin {
            return gestureGraph?.eventBinding(
                at: location,
                accepting: ScrollEvent.self
            ) != nil
        }

        let gestureDelta = CGSize(width: -delta.x, height: -delta.y)
        let eventPhase: EventPhase
        let eventID: EventID
        switch phase {
        case .began:
            eventPhase = .began
            eventID = EventID(type: ScrollEvent.self, serial: nextEventSerial())
            _wheelScrollEventID = eventID
            _wheelScrollTranslation = .zero
        case .stationary, .changed:
            eventPhase = .moved
            if let activeID = _wheelScrollEventID {
                eventID = activeID
            } else {
                eventID = EventID(type: ScrollEvent.self, serial: nextEventSerial())
                _wheelScrollEventID = eventID
                _wheelScrollTranslation = .zero
                let began = ScrollEvent(
                    delta: .zero,
                    translation: .zero,
                    previousTranslation: .zero,
                    location: location,
                    phase: .began
                )
                _ = sendRecognizerOwnedEvents([eventID: began], at: time)
            }
        case .ended:
            eventPhase = .ended
            guard let activeID = _wheelScrollEventID else { return false }
            eventID = activeID
        case .cancelled:
            eventPhase = .cancelled
            guard let activeID = _wheelScrollEventID else { return false }
            eventID = activeID
        case .mayBegin:
            return false
        }

        let previousTranslation = _wheelScrollTranslation
        _wheelScrollTranslation.width += gestureDelta.width
        _wheelScrollTranslation.height += gestureDelta.height
        let scrollEvent = ScrollEvent(
            delta: gestureDelta,
            translation: _wheelScrollTranslation,
            previousTranslation: previousTranslation,
            location: location,
            phase: eventPhase
        )
        let result = sendRecognizerOwnedEvents([eventID: scrollEvent], at: time)
        if eventPhase == .ended || eventPhase == .cancelled {
            _wheelScrollEventID = nil
            _wheelScrollTranslation = .zero
        }
        switch result {
        case .active, .ended:
            return true
        case .possible, .failed:
            return false
        }
    }

    @discardableResult
    func handleGestureEvent(event: GestureEvent) -> Bool {
        handleGestureEvent(event: event, at: currentTimestamp)
    }

    @discardableResult
    func handleGestureEvent(event: GestureEvent, at time: Time) -> Bool {
        if let window = self.window, window !== event.window { return false }
        guard self.gestureGraph?.rootResponder != nil else { return false }

        switch event.type {
        case .pan:
            let eventPhase = eventPhase(from: event.phase)
            let delta = CGSize(width: event.delta.x, height: event.delta.y)
            let eventID: EventID
            switch event.phase {
            case .began:
                eventID = EventID(type: ScrollEvent.self, serial: nextEventSerial())
                _scrollEventID = eventID
                _scrollTranslation = .zero

            case .changed, .ended, .cancelled:
                guard let currentID = _scrollEventID else { return false }
                eventID = currentID
            }
            let previousTranslation = _scrollTranslation
            _scrollTranslation.width += delta.width
            _scrollTranslation.height += delta.height
            let scrollEvent = ScrollEvent(
                delta: delta,
                translation: _scrollTranslation,
                previousTranslation: previousTranslation,
                location: event.location,
                phase: eventPhase
            )
            // Platform pan input is already classified, but it still needs a
            // recognizer-owned session; direct-host tracking may suppress later
            // values after forwarding ownership to another host path.
            let phase = sendRecognizerOwnedEvents([eventID: scrollEvent], at: time)
            if eventPhase == .ended || eventPhase == .cancelled {
                _scrollEventID = nil
                _scrollTranslation = .zero
            }
            switch phase {
            case .active, .ended:
                return true
            case .possible, .failed:
                return false
            }

        case .magnify:
            let eventPhase = eventPhase(from: event.phase)
            let eventID: EventID
            switch event.phase {
            case .began:
                eventID = EventID(type: MagnifyEvent.self, serial: nextEventSerial())
                _magnifyEventID = eventID
                _magnification = 1.0
            case .changed, .ended, .cancelled:
                guard let currentID = _magnifyEventID else { return false }
                eventID = currentID
            }
            let previousMagnification = _magnification
            _magnification += event.magnification
            let magnifyEvent = MagnifyEvent(
                magnification: _magnification,
                previousMagnification: previousMagnification,
                location: event.location,
                phase: eventPhase,
                timestamp: time.seconds
            )
            let phase = sendRecognizerOwnedEvents([eventID: magnifyEvent], at: time)
            if eventPhase == .ended || eventPhase == .cancelled {
                _magnifyEventID = nil
                _magnification = 1.0
            }
            switch phase {
            case .active, .ended: return true
            case .possible, .failed: return false
            }

        case .rotate:
            let eventPhase = eventPhase(from: event.phase)
            let eventID: EventID
            switch event.phase {
            case .began:
                eventID = EventID(type: RotateEvent.self, serial: nextEventSerial())
                _rotateEventID = eventID
                _rotation = .zero
            case .changed, .ended, .cancelled:
                guard let currentID = _rotateEventID else { return false }
                eventID = currentID
            }
            let previousRotation = _rotation
            _rotation += Angle(degrees: event.rotation)
            let rotateEvent = RotateEvent(
                rotation: _rotation,
                previousRotation: previousRotation,
                location: event.location,
                phase: eventPhase,
                timestamp: time.seconds
            )
            let phase = sendRecognizerOwnedEvents([eventID: rotateEvent], at: time)
            if eventPhase == .ended || eventPhase == .cancelled {
                _rotateEventID = nil
                _rotation = .zero
            }
            switch phase {
            case .active, .ended: return true
            case .possible, .failed: return false
            }
        }
    }

    @discardableResult
    func handleMouseHover(at location: CGPoint, deviceID: Int, isTopMost: Bool) -> Bool {
        _lastHoverRefresh = (location: location, deviceID: deviceID, isTopMost: isTopMost)
        var topMost = isTopMost
        self.presentationChildren.withLock({ $0.reversed() }).forEach { entry in
            guard entry.isOverlay, entry.initiated else { return }
            let child = entry.controller
            if entry.frame != nil {
                let loc = child.presentationPointInLocal(fromParentPoint: location)
                if child.handleMouseHover(at: loc, deviceID: deviceID, isTopMost: topMost) {
                    topMost = false
                }
            }
            if topMost && child.overlayHitTest(
                child.presentationPointInLocal(fromParentPoint: location)
            ) {
                topMost = false
            }
        }
        if sendHoverEvent(at: location, deviceID: deviceID, isTopMost: topMost) {
            topMost = false
        }
        return isTopMost != topMost
    }

    @discardableResult
    private func sendHoverEvent(at location: CGPoint,
                                deviceID: Int,
                                isTopMost: Bool) -> Bool {
        let hasHit = isTopMost &&
            !(gestureGraph?.rootResponder?.hoverResponders(containing: location).isEmpty ?? true)
        let wasActive = hoverEventDispatcher.hasActiveResponders(deviceID: deviceID)

        let eventID: EventID
        let phase: EventPhase
        if hasHit {
            if let currentID = _hoverEventIDs[deviceID] {
                eventID = currentID
                phase = .moved
            } else {
                eventID = EventID(type: HoverEvent.self, serial: nextEventSerial())
                _hoverEventIDs[deviceID] = eventID
                phase = .began
            }
        } else if let currentID = _hoverEventIDs[deviceID] {
            eventID = currentID
            phase = .ended
        } else if wasActive {
            eventID = EventID(type: HoverEvent.self, serial: nextEventSerial())
            phase = .ended
        } else {
            return false
        }

        let hoverEvent = HoverEvent(location: location, phase: phase, deviceID: deviceID)
        let consumed = sendHostEvents([eventID: hoverEvent], track: false, at: currentTimestamp)
        if phase == .ended || phase == .cancelled {
            _hoverEventIDs.removeValue(forKey: deviceID)
        }
        return consumed.contains(eventID)
    }

    private func endAllHoverResponders() {
        hoverEventDispatcher.reset { [weak self] action in
            if let gestureGraph = self?.gestureGraph {
                gestureGraph.enqueueAction(action)
            } else {
                action()
            }
        }
    }

    func resetGestureHandlers() {
        resetGestureHandlers(reason: "unspecified")
    }

    private func resetGestureHandlers(reason: String) {
        endAllHoverResponders()
        gestureGraph?.resetEvents()
        contextMenuRecognizer.reset()
        menuPresentationTrigger.reset()
        _touchEventIDs.removeAll()
        _mouseEventID = nil
        _spatialEventIDs.removeAll()
        _mouseSpatialEventID = nil
        _scrollEventID = nil
        _scrollTranslation = .zero
        _wheelScrollEventID = nil
        _wheelScrollTranslation = .zero
        _pointerScrollStates.removeAll()
        _keyEventIDs.removeAll()
        _hoverEventIDs.removeAll()
        _magnifyEventID = nil
        _magnification = 1.0
        _rotateEventID = nil
        _rotation = .zero
        _hostTrackedEventIDs.removeAll()
        _hostForwardedEventIDs.removeAll()
        _lastHoverRefresh = nil
        _activeEvents.removeAll()
    }

    // MARK: - ViewGraphRenderDelegate

    // WindowController is the rendering host. There is no separate platform-view intermediary.
    // viewGraph.renderDelegate = self is set at the end of init.
    // updateRenderContext is called once per frame in updateFrame before updateView.

    // The root backend object being rendered.
    var renderingRootView: AnyObject { self }

    // Fills in per-frame render parameters.
    // contentsScale: from sceneResources (updated by WindowContext on window events).
    // opaqueBackground: true if config background has no transparency.
    func updateRenderContext(_ context: inout ViewGraphRenderContext) {
        context.contentsScale = sceneResources.contentScaleFactor
        // backgroundColor.opacity is 0.0-1.0. Treat >= 1.0 as fully opaque.
        // backgroundColor is VVD.Color. .a is the alpha Scalar (0.0-1.0).
        context.opaqueBackground = (config.backgroundColor.a >= 1.0)
    }

    // Ensures body runs on the main render thread.
    // The VVD render loop already runs on the appropriate thread. Call body directly.
    func withMainThreadRender(wasAsync: Bool, _ body: () -> Time) -> Time {
        return body()
    }

    // Returns how long until the next frame should be rendered.
    // Infinity/no scheduled view update is normalized by ViewGraph to 0.0 for
    // the current backend's continuous frame pacing.
    func renderIntervalForDisplayLink(timestamp: Time) -> Double {
        return viewGraph.nextUpdateInterval
    }

    // MARK: - ViewGraphDelegate

    func setNeedsUpdate() {
        requestUpdate(after: 0)
    }

    func requestUpdate(after: Double) {
        if after == 0 {
            viewChangedWhileDrawing = true
        } else if after < Self.displayLinkRequestDelayLimit {
            viewGraph.startDisplayLink(delay: after)
        } else {
            viewGraph.startUpdateTimer(delay: after)
        }
    }

    func `as`<T>(_ type: T.Type) -> T? {
        self as? T
    }

    // MARK: - GraphDelegate

    func beginTransaction() {
        setNeedsUpdate()
    }

    func updateGraph<T>(body: (GraphHost) -> T) -> T {
        body(viewGraph)
    }

    func graphDidChange() {
        setNeedsUpdate()
    }

    func preferencesDidChange() {
        setNeedsUpdate()
    }

    // MARK: - ViewGraphRootValueUpdater

    func updateRootView() {
        // Content is lifted into ViewGraph at init time. There is no separate root view setter.
    }

    func updateEnvironment() {
        if let parentGraph = parentWindow?.viewGraph {
            let parentPhase = parentGraph.data.withCurrent {
                parentGraph.data.phaseAttribute.value
            }
            viewGraph.updateGraphPhase(
                oldParentPhase: viewGraph.parentPhase,
                newParentPhase: parentPhase
            )
        }
        viewGraph.envAttr?.setValue(self.environment)
    }

    func updateSize() {
        viewGraph.sizeAttr?.setValue(ViewSize(cachedContentSize))
    }

    func updateSafeArea()      {}  // Safe area is not wired yet.
    func updateContainerSize() {}  // Container size is not wired yet.
    func updateTransform()         {}  // Transform root input is not wired yet.
    func updateFocusStore()        {}  // Focus store is not wired yet.
    func updateFocusedItem()       {}  // Focused item is not wired yet.
    func updateFocusedValues()     {}  // Focused values are not wired yet.
    func updateAccessibilityEnvironment() {}  // Accessibility root input is not wired yet.

    // MARK: - Presentation Child / Modal Management (nested structure)
    // WindowController owns its dynamic children directly (strong refs).
    // AppWindowsController is not involved in dynamic presentation-child/modal lifetime.

    // Parent that opened this window (nil = root window).
    weak var parentWindow: WindowController?

    // Overlay descendants use this hook while converting their local placement
    // into the nearest platform host's coordinate space. Root/platform
    // controllers keep the same point; overlay controller subclasses add their
    // own parent-relative origin.
    func presentationPointInParent(forLocalPoint point: CGPoint) -> CGPoint {
        point
    }

    func presentationPointInLocal(fromParentPoint point: CGPoint) -> CGPoint {
        point
    }

    private struct PresentationChildEntry: @unchecked Sendable {
        let controller: PresentationChildWindowController   // strong: WindowController owns presentation children
        var isOverlay: Bool = true
        var initiated: Bool = false
        var frame: CGRect? = nil           // overlay hit-test / draw offset (independent of isOverlay)
    }
    private let presentationChildren = Mutex<[PresentationChildEntry]>([])

    // Unified modal queue: first entry = active, rest = pending.
    // Equivalent to a single-active modal queue at the controller level.
    //
    // isOverlay is set at _activateModal time (not at enqueue time) based on:
    //   - the child controller's frozen modalSessionUsingPlatformWindow value
    //   - the parent's platform-window capability at activation time
    // Before activation, isOverlay defaults to false. Queued entries are never drawn.
    //
    // In dismissAllModalWindows, position (first vs rest) determines reason:
    //   first means the modal was active and uses .byParent.
    //   the rest were queued, never shown, and use .cancelled.
    private struct ModalChildEntry: @unchecked Sendable {
        let controller: ModalWindowController   // strong: WindowController owns modal children
        var isOverlay: Bool = false   // set to true only after overlay is confirmed. false means platform window
        var initiated: Bool = false   // true once activation completes. updateView/drawFrame gate on this
        var session: PresentationSession
        var contentAttr: Attribute<AnyView>? = nil
        var attachWindow: AttachWindowResolver? = nil
        var presentationTransaction: Transaction = Transaction()
        var dismissCallbackDelivered: Bool = false
    }
    private let modalChildren = Mutex<[ModalChildEntry]>([])

    // MARK: - Presentation Child Management
    //
    // UtilityWindowController and PopupWindowController use this one ownership
    // path for overlay fallback, platform-window attach, event forwarding, and
    // teardown. Do not add a separate popup child registry unless a real
    // lifecycle split is modeled.

    func addPresentationChild(child: PresentationChildWindowController,
                              attachWindow: AttachWindowResolver? = nil) {
        child.parentWindow = self
        let canUsePlatformWindow = child.prefersPlatformWindowPresentation &&
            attachWindow != nil &&
            runOnMainQueueSync { self.window != nil }
        let asOverlay = !canUsePlatformWindow
        var entry = PresentationChildEntry(controller: child)
        entry.isOverlay = false
        self.presentationChildren.withLock { entries in
            entries.removeAll { $0.controller === child }
            entries.append(entry)
        }
        viewChangedWhileDrawing = true

        if !asOverlay, let attachWindow {
            attachWindow { [weak self, weak child] _ in
                guard let self else { return }
                let didInitiate = self.presentationChildren.withLock { entries in
                    if let i = entries.firstIndex(where: { $0.controller === child }) {
                        entries[i].isOverlay = false
                        entries[i].initiated = true
                        return true
                    }
                    return false
                }
                if didInitiate {
                    child?.onPresentationChildSessionInitiated()
                }
            }
            // attachWindow is allowed to hand off to the MainActor before calling the
            // AttachWindow callback. Enqueue the fallback on the same actor so a real
            // attach gets the first chance to mark this child as initiated.
            Task { @MainActor [weak self, weak child] in
                guard let self, let child else { return }
                let didInitiate = self.presentationChildren.withLock { entries in
                    // initiated == false means AttachWindow did not run.
                    if let i = entries.firstIndex(where: { $0.controller === child }),
                       !entries[i].initiated {
                        entries[i].isOverlay = true
                        entries[i].initiated = true
                        return true
                    }
                    return false
                }
                if didInitiate {
                    child.onPresentationChildSessionInitiated()
                }
            }
        } else {
            attachWindow?(nil)
            let didInitiate = self.presentationChildren.withLock { entries in
                if let i = entries.firstIndex(where: { $0.controller === child }) {
                    entries[i].isOverlay = true
                    entries[i].initiated = true
                    return true
                }
                return false
            }
            if didInitiate {
                child.onPresentationChildSessionInitiated()
            }
        }
    }

    func removePresentationChild(child: PresentationChildWindowController) {
        let removed = self.presentationChildren.withLock { entries -> PresentationChildWindowController? in
            guard let i = entries.firstIndex(where: { $0.controller === child }) else {
                return nil
            }
            return entries.remove(at: i).controller
        }
        guard let removed else { return }
        removed.parentWindow = nil
        removed.endPresentationSession()
        viewChangedWhileDrawing = true
    }

    func updatePresentationChild(child: PresentationChildWindowController, frame: CGRect?) {
        self.presentationChildren.withLock { entries in
            if let i = entries.firstIndex(where: { $0.controller === child }) {
                entries[i].frame = frame
            }
        }
        viewChangedWhileDrawing = true
    }

    func dismissAllPresentationChildren() {
        let children = self.presentationChildren.withLock { entries in
            defer { entries.removeAll() }
            return entries.map(\.controller)
        }
        children.forEach { child in
            child.parentWindow = nil
            child.endPresentationSession()
        }
        if !children.isEmpty {
            viewChangedWhileDrawing = true
        }
    }

    // MARK: - Modal Child Management

    // Called internally by preference-driven sheet/alert/dialog presentation.
    // isOverlay is not determined here. It is deferred to _activateModal when the entry
    // reaches the front of the queue and the parent's window state is known.
    func addModal(child: ModalWindowController,
                  session: PresentationSession,
                  transaction: Transaction = Transaction(),
                  contentAttr: Attribute<AnyView>? = nil,
                  attachWindow: AttachWindowResolver? = nil) {
        child.parentWindow = self
        var entry = ModalChildEntry(controller: child, session: session)
        entry.contentAttr = contentAttr
        entry.attachWindow = attachWindow
        entry.presentationTransaction = transaction
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
                removeModal(child: child, reason: .cancelled)
                return
            }

            attachWindow { [weak self, weak child] childWindow in
                guard let self else { return }
                let ok = self.window?.presentModalWindow(
                    childWindow,
                    completionHandler: { [weak self, weak child] in
                        Task { @MainActor [weak self, weak child] in
                            guard let self, let child else { return }
                            self.removeModal(child: child, reason: .userAction)
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
                        child?.onModalSessionInitiated(transaction: entry.presentationTransaction)
                    }
                } else {
                    Log.error("WindowController: presentModalWindow failed")
                    if let child {
                        self.removeModal(child: child, reason: .cancelled)
                    }
                }
            }

            // attachWindow is expected to create/attach the platform window through the
            // MainActor AttachWindow callback. Enqueue this fallback after that handoff.
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
                    child.onModalSessionInitiated(transaction: entry.presentationTransaction)
                }
                if result.initiated {
                    self.resetGestureHandlers(reason: "modal session initiated")
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
            child.onModalSessionInitiated(transaction: entry.presentationTransaction)
            self.resetGestureHandlers(reason: "modal overlay initiated")
            self.handleMouseHover(at: .zero, deviceID: 0, isTopMost: false)
        }
    }

    // Show the front of the queue after the previous active modal was removed.
    private func _showNextInQueue() {
        guard let entry = modalChildren.withLock({ $0.first }) else { return }
        let child = entry.controller
        // Race guard: skip if preference-driven session is already dismissed.
        if let presented = entry.session.isPresented, !presented.wrappedValue {
            removeModal(child: child, reason: .cancelled)
            return
        }
        // entry.initiated is false here. _activateModal will set it after init.
        _activateModal(entry: entry)
    }

    // Start modal dismissal. Active modal children own the dismissal timing
    // and call the completion when they are ready for final removal.
    private func dismissModal(child: ModalWindowController,
                              reason: ModalDismissReason,
                              transaction: Transaction = Transaction()) {
        let shouldNotifyChild = modalChildren.withLock { entries -> Bool in
            guard let i = entries.firstIndex(where: { $0.controller === child }) else { return false }
            return i == 0 && entries[i].initiated
        }
        if shouldNotifyChild,
           child.requestModalDismissal(reason: reason, transaction: transaction, completion: { [weak self, weak child] in
               guard let self, let child else { return }
               self.removeModal(child: child, reason: reason)
           }) {
            deliverSheetDismissCallbackIfNeeded(child: child, reason: reason)
            return
        }
        removeModal(child: child, reason: reason)
    }

    private func deliverSheetDismissCallbackIfNeeded(child: ModalWindowController,
                                                     reason: ModalDismissReason) {
        var sessionToNotify: PresentationSession?
        modalChildren.withLock { entries in
            guard let index = entries.firstIndex(where: { $0.controller === child }),
                  !entries[index].dismissCallbackDelivered,
                  case .sheet = entries[index].session else {
                return
            }
            entries[index].dismissCallbackDelivered = true
            sessionToNotify = entries[index].session
        }
        sessionToNotify?.cleanup(reason: reason)
    }

    // Immediately remove a modal (active or queued) and clean up its session / callbacks.
    private func removeModal(child: ModalWindowController,
                             reason: ModalDismissReason) {
        var removedEntry: ModalChildEntry?
        var wasFirst = false
        modalChildren.withLock { entries in
            if let i = entries.firstIndex(where: { $0.controller === child }) {
                wasFirst = (i == 0)
                removedEntry = entries.remove(at: i)
            }
        }
        guard let e = removedEntry else { return }

        // Ask the platform parent to detach the sheet window. Keep presentation session
        // cleanup on this path instead of moving AG-adjacent work onto MainActor.
        let ctrl = child
        Task { @MainActor [weak self, ctrl] in
            if let w = ctrl.window {
                self?.window?.dismissModalWindow(w)
            }
        }

        child.parentWindow = nil
        child.endPresentationSession()

        // Preference-driven: clean up binding + onDismiss.
        e.session.cleanup(reason: reason, notifyDismiss: !e.dismissCallbackDelivered)

        if wasFirst { _showNextInQueue() }
    }


    func dismissAllModalWindows() {
        let entries = modalChildren.withLock { entries in
            defer { entries.removeAll() }
            return entries
        }
        for (i, entry) in entries.enumerated() {
            let child = entry.controller
            // Ask the platform parent to detach the sheet window. Keep presentation session
            // cleanup on this path instead of moving AG-adjacent work onto MainActor.
            let ctrl = child
            Task { @MainActor [weak self, ctrl] in
                if let w = ctrl.window {
                    self?.window?.dismissModalWindow(w)
                }
            }

            child.parentWindow = nil
            child.endPresentationSession()
            // First entry was active and uses byParent. Queued entries were never shown and use cancelled.
            let reason: ModalDismissReason = (i == 0) ? .byParent : .cancelled
            entry.session.cleanup(reason: reason)
        }
    }

    // MARK: - Preference-driven presentation (sheet / alert)
    // Sheet, alert, and dialog presentation go through the unified modalChildren queue.

    /// Called from ViewGraph side-effect rule when SheetPreference.Key changes.
    func updateSheetPresentation(_ value: SheetPreference.Value,
                                 transaction: Transaction = Transaction()) {
        guard let graph = _AGGraph.current else {
            fatalError("\(#function) must be called from within an AG context (side-effect rule).")
        }
        func rootContent(for pref: SheetPreference) -> AnyView {
            // The sheet bridge wraps erased presentation content in SheetContent
            // before handing it to a modal child graph.
            AnyView(SheetContent(content: pref.content))
        }
        let incoming: [SheetPreference]
        let dismissalTransactions: [Namespace.ID: Transaction]
        switch value {
        case .single(let pref):
            incoming = [pref]
            dismissalTransactions = [:]
        case .keyed(let transactions):
            incoming = []
            dismissalTransactions = transactions
        case .none:
            incoming = []
            dismissalTransactions = [:]
        }

        func sid(_ p: SheetPreference) -> Namespace.ID {
            p.namespaceID
        }

        // Collect existing sheet sessions from the queue.
        let existing: [(Namespace.ID, ModalWindowController)] = modalChildren.withLock {
            $0.compactMap { entry in
                guard case .sheet(let p) = entry.session else { return nil }
                return (sid(p), entry.controller)
            }
        }
        let incomingIDs = Set(incoming.map(sid))

        // Dismiss sessions that are no longer in incoming.
        for (id, ctrl) in existing {
            if !incomingIDs.contains(id) {
                dismissModal(
                    child: ctrl,
                    reason: .dismissed,
                    transaction: dismissalTransactions[id] ?? transaction
                )
            }
        }

        // Update existing sessions and enqueue new ones.
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
            // Exact sheet bridge ownership still needs to be modeled before this
            // becomes the final architecture.
            let ctrl = ModalWindowController(crossGraphContent: contentAttr,
                                             sourceGraph: graph,
                                             scene: sheetKey,
                                             parentController: self,
                                             usesPlatformWindow: pref.usesPlatformWindow)
            addModal(
                child: ctrl,
                session: .sheet(pref),
                transaction: transaction,
                contentAttr: contentAttr
            ) { [weak ctrl] attach in
                ctrl?.resolveModalWindowAttachment(attach)
            }

        }
    }

    /// Called from ViewGraph side-effect rule when ConfirmationDialogStorage.PreferenceKey changes.
    func updateConfirmationDialogPresentation(_ dialogs: [ConfirmationDialogPreference]) {
        guard let graph = _AGGraph.current else {
            fatalError("\(#function) must be called from within an AG context (side-effect rule).")
        }
        func sid(_ p: ConfirmationDialogPreference) -> ObjectIdentifier {
            ObjectIdentifier(p.isPresented.location)
        }
        let existing: [(ObjectIdentifier, ModalWindowController)] = modalChildren.withLock {
            $0.compactMap { entry in
                guard case .confirmationDialog(let p) = entry.session else { return nil }
                return (sid(p), entry.controller)
            }
        }
        let existingIDs = Set(existing.map { $0.0 })
        for (id, ctrl) in existing {
            if !dialogs.contains(where: { sid($0) == id }) {
                dismissModal(child: ctrl, reason: .dismissed)
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
            addModal(child: ctrl, session: .confirmationDialog(pref)) { [weak ctrl] attach in
                ctrl?.resolveModalWindowAttachment(attach)
            }
        }
    }

    /// Called from ViewGraph side-effect rule when AlertStorage.PreferenceKey changes.
    func updateAlertPresentation(_ alerts: [AlertPreference]) {
        guard let graph = _AGGraph.current else {
            fatalError("\(#function) must be called from within an AG context (side-effect rule).")
        }
        func sid(_ p: AlertPreference) -> ViewIdentity {
            p.identity
        }

        let existing: [(ViewIdentity, ModalWindowController)] = modalChildren.withLock {
            $0.compactMap { entry in
                guard case .alert(let p) = entry.session else { return nil }
                return (sid(p), entry.controller)
            }
        }
        let existingIDs = Set(existing.map { $0.0 })

        // Dismiss removed alerts.
        for (id, ctrl) in existing {
            if !alerts.contains(where: { sid($0) == id }) {
                dismissModal(child: ctrl, reason: .dismissed)
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
            addModal(child: ctrl, session: .alert(pref)) { [weak ctrl] attach in
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
