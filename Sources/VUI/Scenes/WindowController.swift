//
//  File: WindowController.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

typealias PlatformMouseEvent = VVD.MouseEvent
typealias PlatformKeyboardEvent = VVD.KeyboardEvent

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
                        EventGraphHost, EventBindingManagerDelegate,
                        FocusedValueListHost,
                        RootToolbarStorageHost,
                        @unchecked Sendable {

    // MARK: - Types

    typealias AttachWindow = @MainActor (any PlatformWindow) -> Void

    // App-level command operations and their root materialization environment
    // remain owned by one source graph. Static scene roots share this carrier;
    // presentation children never receive it through inherited values.
    final class RootCommandsSource: @unchecked Sendable {
        weak var owner: AppWindowsController?
        let graph: _AGGraph
        let commandsList: Attribute<CommandsList>?
        let environment: Attribute<EnvironmentValues>
        let focusedValues: Attribute<FocusedValues>

        private let graphAccess = Mutex(())
        private let roots = Mutex<[WeakBox<WindowController>]>([])

        init(
            owner: AppWindowsController,
            graph: _AGGraph,
            commandsList: Attribute<CommandsList>?,
            environment: Attribute<EnvironmentValues>,
            focusedValues: Attribute<FocusedValues>
        ) {
            self.owner = owner
            self.graph = graph
            self.commandsList = commandsList
            self.environment = environment
            self.focusedValues = focusedValues
        }

        func register(_ root: WindowController) {
            roots.withLock { roots in
                roots.removeAll { $0.base == nil }
                if !roots.contains(where: { $0.base === root }) {
                    roots.append(WeakBox(root))
                }
            }
        }

        func unregister(_ root: WindowController) {
            roots.withLock { roots in
                roots.removeAll { $0.base == nil || $0.base === root }
            }
        }

        func scheduleRefreshForRoots() {
            let roots = roots.withLock { roots in
                roots.removeAll { $0.base == nil }
                return roots.compactMap(\.base)
            }
            for root in roots {
                root.scheduleRootCommandsRefresh(from: self)
            }
        }

        func updateFocusedValues(_ values: FocusedValues) {
            _ = graphAccess.withLock { _ in
                _AGGraph.withCurrent(graph) {
                    focusedValues.setValue(values)
                }
            }
        }

        fileprivate func resolve() -> ResolvedRootCommands {
            graphAccess.withLock { _ in
                _AGGraph.withCurrent(graph) {
                    var resolved = _ResolvedCommands()
                    commandsList?.value.resolveOperations(into: &resolved)
                    let environment = environment.value
                    return ResolvedRootCommands(
                        items: resolved.mainMenuItems(env: environment),
                        environment: environment,
                        focusedValues: focusedValues.value
                    )
                }
            }
        }
    }

    fileprivate struct ResolvedRootCommands {
        var items: [MainMenuItem]
        var environment: EnvironmentValues
        var focusedValues: FocusedValues
    }

    // This resolver is the one-shot boundary between graph evaluation and
    // platform-window work. The caller invokes it while the child graph's
    // update lane owns graph access. A resolver must therefore instantiate the
    // child graph, evaluate graph-backed layout, and reduce the result to plain
    // values before creating a MainActor task.
    //
    // The MainActor handoff is limited to platform-window creation and mutation
    // plus invocation of AttachWindow. It must not read ViewGraph, Attribute,
    // LayoutComputer, or any state whose accessor evaluates the graph.
    //
    // AttachWindow may be retained only by that first queued actor handoff. It
    // must not be held until a later layout or frame: the parent queues its
    // overlay decision as soon as this resolver returns, so a delayed callback
    // would allow both presentation paths to claim the same child.
    typealias AttachWindowResolver = (AttachWindow?) -> Void

    // Values inherited by presentation and modal windows from their parent.
    // The complete carrier uses the same path for initial attachment and later updates.
    struct InheritedValues {
        var configurationOverride = WindowConfiguration.Override()
    }

    private struct HostViewGraph: ViewGraphFeature {
        func modifyViewInputs(
            inputs: inout _ViewInputs,
            graph: ViewGraph
        ) {
            inputs[EventBindingBridgeFactoryInput.self] =
                WindowEventBindingBridge.self
        }
    }

    // MARK: - Core State

    var windowContext: WindowContext?

    // Each controller must start with an independent scheduling context so it
    // can act as a root. When it becomes a presentation child, parentWindow's
    // observer must replace this reference with the root tree's context. Do not
    // derive it dynamically from parentWindow: detachment clears that weak link
    // before teardown, while the child's final platform frame may still run
    // concurrently with the root.
    private var hostUpdateContext = Update.HostContext()

    private var _titleGraph: _GraphValue<Text>?
    private var _titleString: String = ""
    private var _style: PlatformWindowStyle

    let environmentWrapper: ViewGraphHostEnvironmentWrapper
    var environment: EnvironmentValues {
        get { environmentWrapper.environment }
        set { environmentWrapper.environment = newValue }
    }
    let sceneResources: SceneResources

    let eventBindingManager = EventBindingManager()
    private(set) lazy var gestureEnvironment =
        WindowGestureEnvironment(host: self)
    private var contextMenuRecognizer = ContextMenuRecognizer()

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
    private var _wheelScrollBinding: EventBinding?
    private var _wheelScrollLastTime: Time?
    private var _wheelScrollVelocity = _Velocity<CGSize>(valuePerSecond: .zero)

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
    private var _lastHoverRefresh: (location: CGPoint, deviceID: Int, isTopMost: Bool)?

    private func nextEventSerial() -> Int {
        _nextEventSerial.wrappingAdd(1, ordering: .relaxed).oldValue
    }

    private func configureForwardedEventDispatchers() {
        eventBindingManager.host = self
        eventBindingManager.delegate = self
        eventBindingManager.addForwardedEventDispatcher(HoverEventDispatcher())
        eventBindingManager.addForwardedEventDispatcher(KeyEventDispatcher())
    }

    private func sendRecognizerOwnedEvents(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> WindowGestureDispatchResult {
        gestureEnvironment.send(events, at: time)
    }

    private func sendHostEvents(
        _ events: [EventID: any EventType],
        track: Bool,
        at time: Time
    ) -> Set<EventID> {
        guard track else {
            return eventBindingManager.send(events)
        }

        var outbound: [EventID: any EventType] = [:]
        var consumed: Set<EventID> = []
        for (eventID, event) in events {
            let forwardsTrackedUpdates = event is KeyEvent
            switch event.phase {
            case .began:
                _hostTrackedEventIDs.insert(eventID)
                _hostForwardedEventIDs.insert(eventID)
                outbound[eventID] = event
                consumed.insert(eventID)
            case .active:
                if forwardsTrackedUpdates || !_hostForwardedEventIDs.contains(eventID) {
                    _hostTrackedEventIDs.insert(eventID)
                    _hostForwardedEventIDs.insert(eventID)
                    outbound[eventID] = event
                    consumed.insert(eventID)
                }
            case .ended, .failed:
                if forwardsTrackedUpdates || !_hostForwardedEventIDs.contains(eventID) {
                    outbound[eventID] = event
                    consumed.insert(eventID)
                }
                _hostTrackedEventIDs.remove(eventID)
                _hostForwardedEventIDs.remove(eventID)
            }
        }
        if !outbound.isEmpty {
            _ = eventBindingManager.send(outbound)
        }
        return consumed
    }

    private func eventPhase(from gesturePhase: GestureEventPhase) -> EventPhase {
        switch gesturePhase {
        case .began: return .began
        case .changed: return .active
        case .ended: return .ended
        case .cancelled: return .failed
        }
    }

    private func pointerEvent(
        from event: PlatformMouseEvent,
        phase: EventPhase,
        at time: Time
    ) -> any EventType {
        let usesTouchPayload = event.device == .touch ||
            (event.device == .stylus && event.buttonID == 0)
        if usesTouchPayload {
            let touchData = event.touchData
            return TouchEvent(
                timestamp: time,
                phase: phase,
                binding: nil,
                location: event.location,
                globalLocation: event.location,
                radius: touchData?.majorRadius ?? 0,
                force: event.pressure,
                maximumPossibleForce: Double(
                    touchData?.maximumPossiblePressure ?? 1
                ),
                modifiers: [],
                altitude: Angle(radians: Double(event.tilt.y)),
                azimuth: Angle(radians: Double(event.tilt.x)),
                touchType: event.device == .stylus ? .pencil : .direct
            )
        }
        return MouseEvent(
            timestamp: time,
            binding: nil,
            button: MouseEvent.Button(rawValue: event.buttonID + 1),
            phase: phase,
            location: event.location,
            globalLocation: event.location,
            modifiers: []
        )
    }

    private func keyCharacters(for event: KeyboardEvent) -> String {
        if !event.text.isEmpty {
            return event.text
        }
        if let character = event.key.shortcutCharacter {
            return String(character)
        }
        if event.key == .space {
            return " "
        }
        return ""
    }

    private func keyEventPhase(for event: KeyboardEvent) -> EventPhase? {
        switch event.type {
        case .keyDown:
            return event.isRepeat ? .active : .began
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
        let stringValue = keyCharacters(for: event)
        let key = KeyEquivalent(platformEvent: event)
        return KeyEvent(
            phase: phase,
            timestamp: currentTimestamp,
            binding: nil,
            modifiers: EventModifiers(platformFlags: event.modifiers),
            keys: key.map { String($0.character) } ?? stringValue,
            stringValue: stringValue,
            keyID: AnyHashable(key ?? KeyEquivalent("\0"))
        )
    }

    func requestHoverUpdate(in manager: EventBindingManager) {
        if let hover = _lastHoverRefresh {
            _ = sendHoverEvent(at: hover.location,
                               deviceID: hover.deviceID,
                               isTopMost: hover.isTopMost,
                               at: currentTimestamp)
        }
    }

    func didUpdate(
        phase: GesturePhase<Void>,
        in manager: EventBindingManager
    ) {}

    @discardableResult
    func sendEvents(
        _ events: [EventID: any EventType],
        rootNode: ResponderNode,
        at time: Time
    ) -> GesturePhase<Void> {
        viewGraph.sendEvents(events, rootNode: rootNode, at: time)
    }

    func resetEvents() {
        viewGraph.resetEvents()
    }

    func gestureCategory() -> GestureCategory? {
        viewGraph.gestureCategory()
    }

    // MARK: - View Graph State

    // Owns the view-tree _AGGraph and root output attributes.
    // _viewGraph is installed after stored host state is initialized.
    var viewGraph: ViewGraph { _viewGraph }
    private var _viewGraph: ViewGraph!
    private weak var crossGraphSourceGraph: _AGGraph?
    private(set) var rootCommandsSource: RootCommandsSource?
    private var resolvedRootCommands: ResolvedRootCommands?
    var platformCommandMenuPresenter: PlatformCommandMenuPresenter?
    private(set) var windowCommandMenuPresenter: WindowCommandMenuPresenter?
    private var rootToolbarBridge: RootToolbarBridge?
    private var staticRootContent: AnyView?
    private var rootPlatformMenuCapability: Bool?
    // MainActor-owned because changing it also mutates the platform window.
    private var appliedRootChromeHeight: CGFloat = 0

    private struct FocusedValuesState: @unchecked Sendable {
        var local = FocusedValues()
        var resolved = FocusedValues()
    }
    private let focusedValuesState = Mutex(FocusedValuesState())

    var resolvedFocusedValues: FocusedValues {
        focusedValuesState.withLock { $0.resolved }
    }

    var date: Date  // latest platform frame timestamp

    var title: String { _titleString }
    var style: PlatformWindowStyle { _style }

    private var _sceneConfiguration = WindowSceneConfiguration()
    var sceneConfiguration: WindowSceneConfiguration {
        get { windowContext?.sceneConfiguration ?? _sceneConfiguration }
        set {
            _sceneConfiguration = newValue
            windowContext?.sceneConfiguration = newValue

            // Scene configuration supplies the root default. View-level
            // presentation-specific environment values can still override it.
            environment.defaultPresentationHostMode =
                newValue.defaultPresentationHostMode
            viewGraph.valuesNeedingUpdate.insert(.environment)
            viewChangedWhileDrawing = true
            updateRootCommandMenuPresenter()
        }
    }
    var endSessionOnWindowClosed: Bool { true }

    var isValid: Bool { viewGraph.isValid }

    let scene: WindowKey

    var window: (any PlatformWindow)? { windowContext?.window }

    private var _baseConfiguration = WindowConfiguration()
    var baseConfiguration: WindowConfiguration {
        get { windowContext?.baseConfiguration ?? _baseConfiguration }
        set {
            _baseConfiguration = newValue
            windowContext?.baseConfiguration = newValue
        }
    }

    private var _inheritedValues = InheritedValues()
    var inheritedValues: InheritedValues {
        get { _inheritedValues }
        set {
            _inheritedValues = newValue
            windowContext?.configurationOverride = newValue.configurationOverride
            propagateInheritedValuesToChildren(newValue)
        }
    }

    var configurationOverride: WindowConfiguration.Override {
        get { inheritedValues.configurationOverride }
        set {
            var values = inheritedValues
            values.configurationOverride = newValue
            inheritedValues = values
        }
    }

    var configuration: WindowConfiguration {
        windowContext?.configuration
            ?? _baseConfiguration.applying(_inheritedValues.configurationOverride)
    }

    var contentScaleFactorOverride: CGFloat? {
        get { configuration.contentScaleFactorOverride }
        set {
            if let newValue {
                precondition(
                    newValue.isFinite && newValue > 0,
                    "The content scale factor must be positive and finite."
                )
            }
            var override = configurationOverride
            override.contentScaleFactor = newValue
            configurationOverride = override
        }
    }

    var contentScaleFactor: CGFloat {
        get {
            if let contentScaleFactorOverride {
                return contentScaleFactorOverride
            }
            if let windowContext {
                return windowContext.state.contentScaleFactor
            }
            if let parentWindow {
                return parentWindow.contentScaleFactor
            }
            return sceneResources.contentScaleFactor
        }
        set {
            contentScaleFactorOverride = newValue
        }
    }

    // MARK: - Input Queue

    enum InputEvent: @unchecked Sendable {
        case keyboard(KeyboardEvent, Time)
        case mouse(PlatformMouseEvent, Time)
        case gesture(GestureEvent, Time)
        case action(@Sendable () -> Void)
    }
    private struct InputEventStorage {
        var events: [InputEvent] = []
        var pressedMouseButtons: Set<Int> = []
    }
    private let inputEvents = Mutex(InputEventStorage())
    private struct InputTimeReference {
        var source: TimeInterval
        var local: Time
    }
    private let mouseInputTimeReference = Mutex<InputTimeReference?>(nil)
    private static let eventTimestampOrigin = Date.now

    // Event time follows wall-clock receipt time and is intentionally
    // independent from the scaled animation clock.
    private var inputTimestamp: Time {
        Time(seconds: Date.now.timeIntervalSince(Self.eventTimestampOrigin))
    }

    private func inputTimestamp(for event: PlatformMouseEvent) -> Time {
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
        inputEvents.withLock { storage in
            storage.events.append(.action(action))
        }
    }

    func enqueueMouseInputEvent(
        _ event: PlatformMouseEvent,
        at time: Time? = nil
    ) {
        let time = time ?? inputTimestamp(for: event)
        inputEvents.withLock { storage in
            // Preserve host event-loop cadence at the render-queue handoff.
            // Press streams and every non-move boundary remain lossless.
            let isUnpressedMouseMove = event.type == .move &&
                event.device == .genericMouse &&
                storage.pressedMouseButtons.isEmpty

            if isUnpressedMouseMove,
               let index = storage.events.indices.last,
               case .mouse(let previous, _) = storage.events[index] {
                let sameWindow: Bool
                switch (previous.window, event.window) {
                case (nil, nil):
                    sameWindow = true
                case let (lhs?, rhs?):
                    sameWindow = lhs === rhs
                default:
                    sameWindow = false
                }
                if previous.type == .move &&
                    previous.device == event.device &&
                    previous.deviceID == event.deviceID &&
                    previous.buttonID == event.buttonID &&
                    sameWindow {
                    storage.events[index] = .mouse(event, time)
                    return
                }
            }

            storage.events.append(.mouse(event, time))
            switch event.type {
            case .buttonDown:
                storage.pressedMouseButtons.insert(event.buttonID)
            case .buttonUp:
                storage.pressedMouseButtons.remove(event.buttonID)
            case .cancelled:
                storage.pressedMouseButtons.removeAll()
            default:
                break
            }
        }
    }

    // ViewRendererHost / ViewGraphOwner event time. ViewGraph animation and
    // presentation sampling use animationTimestamp instead.
    var currentTimestamp: Time = Time(
        seconds: Date.now.timeIntervalSince(WindowController.eventTimestampOrigin)
    )
    // Temporary process-wide diagnostic input until animation timing is
    // exposed through the view/environment configuration path.
    private static let animationTimeScaleStorage = Mutex<Double>({
        guard let rawValue = ProcessInfo.processInfo.environment[
            "VUI_ANIMATION_TIME_SCALE"
        ],
        let value = Double(rawValue),
        value.isFinite,
        value >= 0 else {
            return 1.0
        }
        return value
    }())
    static var animationTimeScale: Double {
        get { animationTimeScaleStorage.withLock { $0 } }
        set {
            precondition(newValue.isFinite && newValue >= 0)
            animationTimeScaleStorage.withLock { $0 = newValue }
        }
    }
    private(set) var animationTimestamp: Time = .zero
    private(set) var animationDelta: TimeInterval = 0
    private let displayListRenderer = DisplayList.GraphicsRenderer()
    var valuesNeedingUpdate: ViewGraphRootValues = []
    var renderingPhase: ViewRenderingPhase = ViewRenderingPhase()
    var externalUpdateCount: Int = 0

    // ViewRendererHost
    var responderNode: ResponderNode? { viewGraph.responderNode }
    var focusedResponder: ResponderNode? {
        nil
    }
    var nextGestureUpdateTime: Time {
        viewGraph.nextUpdate.gestures.time
    }
    private var nextGestureEventUpdateTime: Time {
        let direct = eventBindingManager.scheduledEventUpdateTime
        let responder = gestureEnvironment.nextGestureUpdateTime
        return responder < direct ? responder : direct
    }

    // MARK: - Initialization

    init<Content: View>(content: _GraphValue<Content>,
                        title: _GraphValue<Text>? = nil,
                        style: PlatformWindowStyle = .genericWindow,
                        scene: WindowKey,
                        environment: EnvironmentValues = .tracking()) {
        self._titleGraph = title
        self._style = style
        let environmentWrapper = ViewGraphHostEnvironmentWrapper()
        environmentWrapper.environment = environment.trackingCopy()
        self.environmentWrapper = environmentWrapper
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

        configureForwardedEventDispatchers()

        let staticRootContent = AnyView(contentValue)
        let rootToolbarBridge = RootToolbarBridge()
        self.staticRootContent = staticRootContent
        self.rootToolbarBridge = rootToolbarBridge
        let toolbarRoot = RootToolbarHost.hostRootView(
            sceneContent: staticRootContent,
            bridge: rootToolbarBridge
        )
        self._viewGraph = ViewGraph(
            replaceableContent: WindowCommandMenuPresenter.hostRootView(
                sceneContent: toolbarRoot,
                presenter: nil
            ),
            rendererHost: self,
            initialEnvironment: self.environment,
            features: [HostViewGraph(), RootToolbarViewGraph()]
        )
        self.crossGraphSourceGraph = nil
        
        // Wire ViewGraph delegate slots.
        // renderDelegate: WindowController provides contentsScale, opaqueBackground, and
        //   render thread handling. Implemented below (ViewGraphRenderDelegate).
        self.viewGraph.renderDelegate = self
        self.viewGraph.viewDelegate = self
        self.viewGraph.graphDelegate = self
        // updateDelegate: WindowController provides root value updates (size, env, etc.).
        self.viewGraph.updateDelegate = self
        installContentScaleFactorOverrideAction()
        // delegate (ViewGraphHostDelegate): not wired yet. Root input attributes
        // are updated directly through ViewGraphRootValueUpdater for now.
        // self.viewGraph.delegate = self
    }

    func setRootCommandsSource(_ source: RootCommandsSource?) {
        precondition(
            parentWindow == nil,
            "Only static scene roots can own the app command source."
        )
        if rootCommandsSource !== source {
            rootCommandsSource?.unregister(self)
            source?.register(self)
        }
        rootCommandsSource = source
        if let source {
            precondition(
                _AGGraph.current == source.graph,
                "The app command source must be resolved by its owning graph."
            )
            resolvedRootCommands = source.resolve()
        } else {
            resolvedRootCommands = nil
        }
        updateRootCommandMenuPresenter()
    }

    private func scheduleRootCommandsRefresh(from source: RootCommandsSource) {
        guard parentWindow == nil, rootCommandsSource === source else {
            return
        }
        enqueueInputAction { [weak self, weak source] in
            guard let self, let source,
                  self.parentWindow == nil,
                  self.rootCommandsSource === source else {
                return
            }
            self.resolvedRootCommands = source.resolve()
            self.updateRootCommandMenuPresenter()
        }
        requestUpdate(after: 0)
    }

    private func updateRootCommandMenuPresenter() {
        guard parentWindow == nil, let resolvedRootCommands else {
            platformCommandMenuPresenter?.invalidate()
            platformCommandMenuPresenter = nil
            setWindowCommandMenuPresenter(nil)
            return
        }

        let selection = sceneConfiguration.commandMenuPresentationStyle
            .rootPresenterSelection(
                platformControllerAvailable: rootPlatformMenuCapability
            )

        switch selection {
        case .window:
            platformCommandMenuPresenter?.invalidate()
            platformCommandMenuPresenter = nil
            let presenter = windowCommandMenuPresenter
                ?? WindowCommandMenuPresenter()
            presenter.update(
                items: resolvedRootCommands.items,
                environment: resolvedRootCommands.environment,
                hostEnvironment: environment,
                sceneResources: sceneResources
            )
            setWindowCommandMenuPresenter(presenter)
            return

        case .pendingPlatformCapability:
            // Keep an already-visible renderer presenter until the actual
            // window answers the capability query. At startup there is no
            // wrapper to install before that answer is known.
            windowCommandMenuPresenter?.update(
                items: resolvedRootCommands.items,
                environment: resolvedRootCommands.environment,
                hostEnvironment: environment,
                sceneResources: sceneResources
            )

        case .platform:
            setWindowCommandMenuPresenter(nil)
        }

        let presenter: PlatformCommandMenuPresenter
        if let current = platformCommandMenuPresenter {
            presenter = current
        } else {
            presenter = PlatformCommandMenuPresenter(owner: self)
            platformCommandMenuPresenter = presenter
        }
        presenter.update(
            items: resolvedRootCommands.items,
            environment: resolvedRootCommands.environment,
            focusedValues: resolvedRootCommands.focusedValues
        )

        if selection == .pendingPlatformCapability {
            Task { @MainActor [weak self] in
                self?.resolveRootPlatformMenuCapability()
            }
        }

        Task { @MainActor [weak self, weak presenter] in
            guard let self, let presenter,
                  self.platformCommandMenuPresenter === presenter,
                  let window = self.window else {
                return
            }
            presenter.attach(to: window)
        }
    }

    func setWindowCommandMenuPresenter(
        _ presenter: WindowCommandMenuPresenter?
    ) {
        let visibilityChanged = (windowCommandMenuPresenter != nil)
            != (presenter != nil)
        windowCommandMenuPresenter = presenter
        viewGraph.valuesNeedingUpdate.insert(.rootView)
        viewChangedWhileDrawing = true
        if visibilityChanged {
            Task { @MainActor [weak self] in
                self?.synchronizeRootChromeGeometry(
                    isInitialAttachment: false
                )
            }
        }
    }

    func focusedValueListDidChange(_ list: FocusedValueList) {
        let values = FocusedValues(resolving: list)
        let changed = focusedValuesState.withLock { state in
            guard state.local != values else { return false }
            state.local = values
            return true
        }
        if changed {
            // Preference delivery occurs while the root graph is evaluating.
            // Resolve and republish the value on the input lane so the same
            // graph is never invalidated reentrantly from its output rule.
            scheduleFocusedValuesRecompute()
        }
    }

    private func recomputeFocusedValues() {
        var values = focusedValuesState.withLock { $0.local }
        if let modalValues: FocusedValues = modalChildren.withLock({ entries in
            guard let first = entries.first, first.initiated else {
                return nil
            }
            return first.controller.resolvedFocusedValues
        }) {
            values.override(with: modalValues)
        }

        let changed = focusedValuesState.withLock { state in
            guard state.resolved != values else { return false }
            state.resolved = values
            return true
        }
        guard changed else { return }

        viewGraph.valuesNeedingUpdate.insert(.focusedValues)
        viewGraph.setNeedsUpdate(
            mayDeferUpdate: true,
            values: .focusedValues
        )
        if let parentWindow {
            parentWindow.scheduleFocusedValuesRecompute()
        } else if let owner = rootCommandsSource?.owner {
            // Static roots publish through the app coordinator so an inactive
            // root cannot replace the focus context used by app Commands.
            owner.updateWindowFocus(self, values: values)
        } else {
            // Standalone roots without an app command source retain the direct
            // semantic-host update path.
            platformCommandMenuPresenter?.updateFocusedValues(values)
        }
    }

    private func scheduleFocusedValuesRecompute() {
        enqueueInputAction { [weak self] in
            self?.recomputeFocusedValues()
        }
        requestUpdate(after: 0)
    }

    @MainActor
    private func resolveRootPlatformMenuCapability(
        isInitialAttachment: Bool = false
    ) {
        guard parentWindow == nil,
              sceneConfiguration.commandMenuPresentationStyle
                .resolvedForRootPresenter == .platform,
              let window else {
            synchronizeRootChromeGeometry(
                isInitialAttachment: isInitialAttachment
            )
            return
        }
        let controller = window.menuController
        rootPlatformMenuCapability = controller != nil
        updateRootCommandMenuPresenter()
        platformCommandMenuPresenter?.attach(to: controller)
        synchronizeRootChromeGeometry(
            isInitialAttachment: isInitialAttachment
        )
    }

    @MainActor
    private func synchronizeRootChromeGeometry(
        isInitialAttachment: Bool
    ) {
        guard let window else {
            appliedRootChromeHeight = 0
            return
        }
        let menuHeight = windowCommandMenuPresenter == nil
            ? 0
            : WindowCommandMenuPresenter.menuBarHeight
        let toolbarHeight = rootToolbarBridge?.allocatedHeight ?? 0
        let desiredHeight = menuHeight + toolbarHeight
        guard desiredHeight != appliedRootChromeHeight else { return }

        let size = window.contentSize
        let sceneHeight = max(0, size.height - appliedRootChromeHeight)
        window.contentSize = CGSize(
            width: size.width,
            height: sceneHeight + desiredHeight
        )
        appliedRootChromeHeight = desiredHeight

        // Initial default positioning must use the final outer size after the
        // renderer-owned chrome has expanded the logical client surface.
        if isInitialAttachment {
            WindowContext.applyInitialScenePosition(
                sceneConfiguration,
                to: window
            )
        }
    }

    func rootToolbarStorageDidChange(_ storage: ToolbarStorage) {
        guard parentWindow == nil,
              staticRootContent != nil,
              let rootToolbarBridge else {
            return
        }
        guard rootToolbarBridge.update(storage: storage) else { return }

        // The stable root host observes this controller-owned bridge directly.
        // Replacing the root input here would unnecessarily rebuild the Scene
        // wrapper every time toolbar content changes.
        viewChangedWhileDrawing = true
        Task { @MainActor [weak self] in
            self?.synchronizeRootChromeGeometry(
                isInitialAttachment: false
            )
        }
    }

    func performRootToolbarCommand(_ command: RootToolbarCommand) {
        guard parentWindow == nil,
              let rootToolbarBridge,
              rootToolbarBridge.perform(command) else {
            return
        }

        viewChangedWhileDrawing = true
        Task { @MainActor [weak self] in
            self?.synchronizeRootChromeGeometry(
                isInitialAttachment: false
            )
        }
    }

    func setRootSceneEnvironment(_ sceneEnvironment: EnvironmentValues) {
        precondition(
            parentWindow == nil,
            "Only static scene roots can receive a scene environment."
        )
        environment = sceneEnvironment.trackingCopy()
        environment.defaultPresentationHostMode =
            sceneConfiguration.defaultPresentationHostMode
        installContentScaleFactorOverrideAction()
        viewChangedWhileDrawing = true
    }

    init<Content: View>(content: Content,
                        environment: EnvironmentValues = .tracking(),
                        viewPhase: ViewGraphHost.Phase = ViewGraphHost.Phase(),
                        scene: WindowKey) {
        self._titleGraph = nil
        self._style = .genericWindow
        let environmentWrapper = ViewGraphHostEnvironmentWrapper()
        environmentWrapper.environment = environment.trackingCopy()
        environmentWrapper.phase = viewPhase
        self.environmentWrapper = environmentWrapper
        self.sceneResources = SceneResources()
        self.windowContext = nil
        self.scene = scene
        self.date = .now

        configureForwardedEventDispatchers()

        self._viewGraph = ViewGraph(
            replaceableContent: content,
            rendererHost: self,
            initialEnvironment: self.environment,
            features: [HostViewGraph()]
        )
        self.crossGraphSourceGraph = nil
        self.viewGraph.renderDelegate = self
        self.viewGraph.viewDelegate = self
        self.viewGraph.graphDelegate = self
        self.viewGraph.updateDelegate = self
        installContentScaleFactorOverrideAction()
    }

    deinit {
        endPresentationSession()
    }

    // Sheet-specific init: content comes from a reactive attribute in a parent AG.
    // The ViewGraph creates a cross-graph reference to observe the parent's attribute, so that
    // when parent state changes, parent contentAttr re-evaluates and the child graph updates.
    // contentAttr must already have a non-nil cached value in sourceGraph before this is called.
    init(crossGraphContent contentAttr: Attribute<AnyView>,
         sourceGraph: _AGGraph,
         environment: EnvironmentValues = .tracking(),
         viewPhase: ViewGraphHost.Phase = ViewGraphHost.Phase(),
         scene: WindowKey) {
        self._titleGraph = nil
        self._style = .genericWindow
        let environmentWrapper = ViewGraphHostEnvironmentWrapper()
        environmentWrapper.environment = environment.trackingCopy()
        environmentWrapper.phase = viewPhase
        self.environmentWrapper = environmentWrapper
        self.sceneResources = SceneResources()
        self.windowContext = nil
        self.scene = scene
        self.date = .now

        configureForwardedEventDispatchers()

        self._viewGraph = ViewGraph(
            crossGraphContentAttr: contentAttr,
            sourceGraph: sourceGraph,
            rendererHost: self,
            initialEnvironment: self.environment,
            features: [HostViewGraph()]
        )
        self.crossGraphSourceGraph = sourceGraph
        self.viewGraph.renderDelegate = self
        self.viewGraph.viewDelegate = self
        self.viewGraph.graphDelegate = self
        self.viewGraph.updateDelegate = self
        installContentScaleFactorOverrideAction()
    }

    private func installContentScaleFactorOverrideAction() {
        environment._contentScaleFactorOverride =
            _ContentScaleFactorOverrideAction { [weak self] value in
                guard let self else { return }
                self.contentScaleFactorOverride = value
                self.viewGraph.valuesNeedingUpdate.insert(.environment)
                self.viewChangedWhileDrawing = true
            }
        viewGraph.valuesNeedingUpdate.insert(.environment)
    }

    // MARK: - Platform Window Lifecycle

    // Presentation resolvers call this after leaving their graph update lane.
    // Keep the complete method graph-free: title, style, configuration, and
    // every other creation argument must already be cached plain state. The
    // same restriction applies to onWindowCreated overrides. If window setup
    // needs a graph-derived value, resolve it before the MainActor handoff and
    // pass the reduced value through the platform attachment path.
    @MainActor
    func makeWindow() -> (any PlatformWindow)? {
        let isNew = windowContext?.window == nil
        if windowContext == nil {
            let ctx = WindowContext(
                sceneResources: self.sceneResources,
                sceneConfiguration: self._sceneConfiguration,
                baseConfiguration: self._baseConfiguration,
                configurationOverride: self._inheritedValues.configurationOverride
            )
            ctx.updateFrame = { [weak self] tick, delta, date, size, drawFrame, withGC in
                self?.updateFrame(tick: tick, delta: delta, date: date,
                                  contentSize: size, shouldDrawFrame: drawFrame,
                                  withGC)
            }
            ctx.preferredFrameInterval = { [weak self] in
                guard let self else { return nil }
                return self.renderIntervalForDisplayLink(timestamp: self.animationTimestamp)
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
                self.inputEvents.withLock { storage in
                    storage.events.append(.keyboard(event, time))
                }
            }
            window.addEventObserver(self) { [weak self] (event: PlatformMouseEvent) in
                guard let self else { return }
                self.enqueueMouseInputEvent(event)
            }
            window.addEventObserver(self) { [weak self] (event: GestureEvent) in
                guard let self else { return }
                let time = self.inputTimestamp
                self.inputEvents.withLock { storage in
                    storage.events.append(.gesture(event, time))
                }
            }
            if parentWindow == nil,
               sceneConfiguration.commandMenuPresentationStyle
                .resolvedForRootPresenter == .platform {
                resolveRootPlatformMenuCapability(
                    isInitialAttachment: true
                )
            } else {
                synchronizeRootChromeGeometry(
                    isInitialAttachment: true
                )
            }
            self.onWindowCreated(window)
            self.platformCommandMenuPresenter?.attach(to: window)
        }
        return window
    }

    private var viewChangedWhileDrawing: Bool = false
    private var permitsIdleGraphSkip = false
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
        let hostUpdateContext = self.hostUpdateContext
        Update.withHostContext(hostUpdateContext) {
            Update.locked {
                updateFrameBody(
                    tick: tick,
                    delta: delta,
                    date: date,
                    contentSize: contentSize,
                    shouldDrawFrame: shouldDrawFrame,
                    withGC
                )
            }
        }
    }

    private func updateFrameBody(tick: UInt64, delta: Double, date: Date,
                                 contentSize: CGSize, shouldDrawFrame: Bool,
                                 _ withGC: WindowContext.WithGraphicsContext) {
        self.date = date

        // Pull render context from delegate (ViewGraphRenderDelegate).
        // contentsScale: HiDPI scale factor for the current display.
        // opaqueBackground: whether the background is fully opaque (skip alpha clear).
        // Refresh render context once per frame before updateOutputs/render.
        var renderCtx = ViewGraphRenderContext(contentsScale: 1.0, opaqueBackground: false)
        viewGraph.renderDelegate?.updateRenderContext(&renderCtx)
        precondition(
            renderCtx.contentsScale.isFinite && renderCtx.contentsScale > 0,
            "The rendering host must provide a positive finite contents scale."
        )
        if environment.displayScale != renderCtx.contentsScale ||
            environment._contentScaleFactor != renderCtx.contentsScale {
            viewGraph.valuesNeedingUpdate.insert(.environment)
        }

        var redraw = false
        self._updateView(
            tick: tick,
            delta: delta,
            date: date,
            contentSize: contentSize,
            redraw: &redraw,
            permitsIdleGraphSkip: shouldDrawFrame,
            withGC
        )

        if redraw || shouldDrawFrame {
            let clearColor = configuration.backgroundColor
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
        // Preserve the host-turn boundary: work emitted while the source graph
        // drains belongs to its next update rather than this snapshot.
        let deferredActions = sourceGraph.actionOutbox
        sourceGraph.actionOutbox.removeAll()
        _AGGraph.withCurrent(sourceGraph) {
            while sourceGraph.inbox.hasPendingWork {
                _ = sourceGraph.inbox.drainOne()
                sourceGraph.drainActions()
            }
        }
        deferredActions.forEach { $0() }
        return hadPendingWork
    }

    private func _updateView(tick: UInt64, delta: Double, date: Date,
                             contentSize: CGSize, redraw: inout Bool,
                             permitsIdleGraphSkip: Bool = false,
                             _ withGC: WindowContext.WithGraphicsContext) {
        let previousPermitsIdleGraphSkip = self.permitsIdleGraphSkip
        self.permitsIdleGraphSkip = permitsIdleGraphSkip
        defer {
            self.permitsIdleGraphSkip = previousPermitsIdleGraphSkip
        }
        Update.begin()
        updateView(
            tick: tick,
            delta: delta,
            date: date,
            contentSize: contentSize,
            redraw: &redraw,
            withGC
        )
        Update.end()
    }

    func updateView(tick: UInt64, delta: Double, date: Date,
                    contentSize: CGSize, redraw: inout Bool,
                    _ withGC: WindowContext.WithGraphicsContext) {
        let contentScaleFactor = self.contentScaleFactor
        if sceneResources.contentScaleFactor != contentScaleFactor {
            sceneResources.contentScaleFactor = contentScaleFactor
        }
        currentTimestamp = Time(
            seconds: date.timeIntervalSince(Self.eventTimestampOrigin)
        )
        animationDelta = delta * Self.animationTimeScale
        animationTimestamp = animationTimestamp + animationDelta
        let time = animationTimestamp
        guard viewGraph.rootGeometry != nil else { return }

        let layoutContentSize = layoutContentSize(from: contentSize)

        // Detect size change and mark the dirty bit.
        let sizeChanged = (layoutContentSize != cachedContentSize)
        if sizeChanged {
            cachedContentSize = layoutContentSize
            viewGraph.setSize(layoutContentSize)
            viewGraph.setContainerSize(ViewSize(layoutContentSize))
        }

        let events = self.inputEvents.withLock { storage in
            defer { storage.events.removeAll() }
            return storage.events
        }
        let hadRootValueUpdates = !viewGraph.valuesNeedingUpdate.isEmpty
        let hadScheduledViewUpdate = viewGraph.hasScheduledViewUpdate
        let hadGraphWork = viewGraph.hasPendingTransactions ||
            viewGraph.needsTransaction ||
            viewGraph.data.graph.inbox.hasPendingWork ||
            !viewGraph.data.graph.pendingActions.isEmpty ||
            !viewGraph.data.graph.actionOutbox.isEmpty
        let hadViewChangedWhileDrawing = self.viewChangedWhileDrawing
        let hadCrossGraphWork: Bool
        if window == nil, let sourceGraph = crossGraphSourceGraph {
            hadCrossGraphWork =
                sourceGraph.inbox.hasPendingWork ||
                !sourceGraph.pendingActions.isEmpty ||
                !sourceGraph.actionOutbox.isEmpty
        } else {
            hadCrossGraphWork = false
        }
        let gestureDeadlineReached =
            !(currentTimestamp < nextGestureEventUpdateTime)
        let hadGestureGraphWork = gestureEnvironment.hasPendingGraphWork

        var needsLayoutPass = !hasDeliveredViewLayoutUpdate ||
            sizeChanged ||
            hadRootValueUpdates ||
            hadGraphWork ||
            hadViewChangedWhileDrawing

        // The backend may present cached contents continuously, but graph
        // output evaluation is event-driven. Avoid advancing the graph's time
        // input when this host has no scheduled or pending update work.
        let needsRootUpdate =
            needsLayoutPass ||
            hadScheduledViewUpdate ||
            !events.isEmpty ||
            hadCrossGraphWork ||
            gestureDeadlineReached ||
            hadGestureGraphWork
        guard !permitsIdleGraphSkip || needsRootUpdate else {
            updateOverlayChildren(
                tick: tick,
                delta: delta,
                date: date,
                contentSize: contentSize,
                redraw: &redraw,
                withGC
            )
            return
        }

        var flushedCrossGraphSource = false
        var drainedGestureOutbox = false
        var drainedViewOutbox = false
        var loadedResources = false
        var resourcesUpdatedGraph = false
        // Snapshot only continuations queued by an earlier host turn. Output
        // evaluation can append work that must run after the next graph update.
        var deferredViewActions = viewGraph.data.graph.actionOutbox
        viewGraph.data.graph.actionOutbox.removeAll()

        func drainDeferredViewActions() -> Bool {
            guard !deferredViewActions.isEmpty else { return false }
            let actions = deferredViewActions
            deferredViewActions.removeAll()
            actions.forEach { $0() }
            return true
        }

        func runRootLayoutPass(
            notifiesLayoutUpdate: Bool,
            samplesDisplayList: Bool = false
        ) -> Bool {
            let layoutChangeSet = _AGChangeSet()
            _AGGraph.withChangeSet(layoutChangeSet) {
                // Pull the dependency-driven root geometry before sampling
                // outputs that consume its origin and size projections.
                viewGraph.data.withCurrent {
                    guard let rootGeometry = viewGraph.rootGeometry else {
                        fatalError("ViewGraph root geometry is not instantiated.")
                    }
                    _ = rootGeometry.value

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
            }
            return !layoutChangeSet.isEmpty
        }

        func loadRootResourcesIfNeeded() -> (
            didLoad: Bool,
            updatedGraph: Bool
        ) {
            var didLoadResources = false
            var didUpdateGraph = false
            viewGraph.data.withCurrent {
                guard let resourceList = viewGraph.rootResourceList?.value,
                      !resourceList.items.isEmpty else {
                    return
                }
                withGC(false) { context in
                    for task in resourceList.items {
                        guard task.isPending() else { continue }
                        didLoadResources = true
                        didUpdateGraph = didUpdateGraph || task.updatesGraph
                        if task.transaction.isEmpty {
                            task(context)
                        } else {
                            // Resource publication can invalidate both intrinsic size and
                            // presentation output, so sample both under its owning transaction.
                            viewGraph.runTransaction(task.transaction, do: {
                                task(context)
                                if task.updatesGraph {
                                    _ = runRootLayoutPass(
                                        notifiesLayoutUpdate: false,
                                        samplesDisplayList: true
                                    )
                                }
                            }, id: nil)
                        }
                    }
                }
            }
            return (didLoadResources, didUpdateGraph)
        }

        let updateChangeSet = _AGChangeSet()
        _AGGraph.withChangeSet(updateChangeSet) {
            // Complete work queued by the previous host turn before advancing
            // the graph update seed for this turn.
            viewGraph.flushTransactions()

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

            // Gesture deadlines are evaluated on unscaled event time. This
            // wakes recognizers that remain possible between input IDs, such as
            // the single-tap fallback beside a double tap.
            let sentDirectTimedEvents =
                eventBindingManager.sendScheduledEventUpdate(
                    at: currentTimestamp
                )
            let sentResponderTimedEvents =
                gestureEnvironment.updateTimedGestures(at: currentTimestamp)
            if sentDirectTimedEvents || sentResponderTimedEvents {
                drainedGestureOutbox = true
            }

            if gestureEnvironment.drainGestureActions() {
                drainedGestureOutbox = true
            }

            // updateOutputs flushes dirty bits, async changes, then evaluates AG.
            // Internally: data.withCurrent, inbox drain, dirty root update, time update.
            flushedCrossGraphSource = flushCrossGraphSourceIfNeeded()
            Update.dispatchActions()
            viewGraph.updateOutputs(at: time, afterTransaction: {
                // Backend resources are deferred until a graphics context exists.
                // Consume them before the next graph transaction begins.
                let resourceLoad = loadRootResourcesIfNeeded()
                if resourceLoad.didLoad {
                    loadedResources = true
                }
                if resourceLoad.updatedGraph {
                    resourcesUpdatedGraph = true
                }
            })

            Update.dispatchActions()
            viewGraph.flushTransactions()
            viewGraph.data.withCurrent {
                _ = viewGraph.rootDisplayList?.value
            }
            drainedViewOutbox = drainDeferredViewActions() || drainedViewOutbox

            // Resource loading: requires GraphicsContext, handled separately after updateOutputs.
            let resourceLoad = loadRootResourcesIfNeeded()
            if resourceLoad.didLoad {
                loadedResources = true
            }
            if resourceLoad.updatedGraph {
                resourcesUpdatedGraph = true
                viewGraph.data.withCurrent {
                    var lastResourceTransaction: Transaction?
                    while viewGraph.data.graph.inbox.hasPendingWork {
                        let pendingTransaction = viewGraph.data.graph.inbox.nextTransaction
                        viewGraph.runTransaction(pendingTransaction, do: {
                            lastResourceTransaction = viewGraph.data.graph.inbox.drainOne()
                            viewGraph.data.graph.drainActions()
                        }, id: nil)
                    }
                    _ = lastResourceTransaction
                }
            }
        }

        platformCommandMenuPresenter?.update(at: currentTimestamp)

        let updateChangedIDs = updateChangeSet.ids(for: viewGraph.data.graph)
        var clockIDs: Set<AGAttribute> = [
            viewGraph.data._updateSeed.identifier,
            viewGraph.data._transactionSeed.identifier
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
            resourcesUpdatedGraph ||
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
            redraw = shouldRedrawFrame || displayListChanged || drainedViewOutbox
        } else {
            redraw = shouldRedrawFrame
        }
        self.viewChangedWhileDrawing = false

        updateOverlayChildren(
            tick: tick,
            delta: delta,
            date: date,
            contentSize: contentSize,
            redraw: &redraw,
            withGC
        )
    }

    private func updateOverlayChildren(
        tick: UInt64,
        delta: Double,
        date: Date,
        contentSize: CGSize,
        redraw: inout Bool,
        _ withGC: WindowContext.WithGraphicsContext
    ) {
        // Overlay presentation children update after their parent.
        for entry in self.presentationChildren.withLock({ $0 }) {
            guard entry.isOverlay, entry.initiated else { continue }
            entry.controller._updateView(
                tick: tick,
                delta: delta,
                date: date,
                contentSize: contentSize,
                redraw: &redraw,
                permitsIdleGraphSkip: permitsIdleGraphSkip,
                withGC
            )
        }
        // The single overlay modal updates last.
        if let entry = self.modalChildren.withLock({ $0.first }),
           entry.isOverlay, entry.initiated {
            entry.controller._updateView(
                tick: tick,
                delta: delta,
                date: date,
                contentSize: contentSize,
                redraw: &redraw,
                permitsIdleGraphSkip: permitsIdleGraphSkip,
                withGC
            )
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
                    at: animationTimestamp,
                    in: context
                )
            }
            self.viewChangedWhileDrawing = !changeSet.isEmpty
        }
        if !(animationTimestamp < displayListRenderer.nextTime) {
            viewChangedWhileDrawing = true
        }
        if !viewGraph.data.graph.actionOutbox.isEmpty {
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

    // Called inside makeWindow and therefore inherits its graph-free rule.
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

    private func notifyRootCommandFocusActivated() {
        var root = self
        while let parent = root.parentWindow {
            root = parent
        }
        root.rootCommandsSource?.owner?.rootWindowDidActivate(root)
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

    private func propagateInheritedValuesToChildren(
        _ inheritedValues: InheritedValues
    ) {
        let presentationChildren = self.presentationChildren.withLock {
            $0.map(\.controller)
        }
        let modalChildren = self.modalChildren.withLock {
            $0.map(\.controller)
        }
        for child in presentationChildren {
            child.inheritedValues = inheritedValues
        }
        for child in modalChildren {
            child.inheritedValues = inheritedValues
        }
    }

    func onViewLoaded() {}
    func onViewLayoutUpdated() {}

    // MARK: - Platform Window Events

    @MainActor
    func handleWindowEvent(event: WindowEvent) {
        switch event.type {
        case .closed:
            rootPlatformMenuCapability = nil
            appliedRootChromeHeight = 0
            if parentWindow == nil {
                rootCommandsSource?.owner?.rootWindowDidClose(self)
            }
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
                self?.resetGestureHandlers(reason: "window hidden")
            }
        case .activated:
            enqueueInputAction { [weak self] in
                guard let self else { return }
                self.notifyRootCommandFocusActivated()
                self.forEachPresentationChild {
                    $0.onParentWindowActivated()
                }
            }
        case .inactivated:
            viewGraph.data.graph.inbox.enqueue { [weak self] in
                self?.resetGestureHandlers(reason: "window inactivated")
            }
            enqueueInputAction { [weak self] in
                self?.forEachPresentationChild { $0.onParentWindowInactivated() }
            }
        case .minimized:
            viewGraph.data.graph.inbox.enqueue { [weak self] in
                self?.resetGestureHandlers(reason: "window minimized")
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

    func onMouseEvent(event: PlatformMouseEvent, at time: Time? = nil) {
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

        let eventTime = time ?? currentTimestamp
        switch event.type {
        case .wheel:
            self.handleMouseWheel(event: event, time: eventTime)

        case .entered, .exited:
            // Window-boundary events carry hover lifetime only. They must not
            // begin, update, or cancel a pressed pointer gesture.
            if event.device != .touch {
                self.handleMouseHover(
                    at: event.location,
                    deviceID: event.deviceID,
                    isTopMost: event.type == .entered,
                    at: eventTime
                )
            }

        default:
            self.handleMouseEvent(
                event: event,
                at: eventTime
            )
            // Direct touch has no hover phase independent of contact.
            if event.device != .touch {
                let hasActivePointerGesture = event.device == .stylus
                    ? _touchEventIDs[event.deviceID] != nil
                    : _mouseEventID != nil
                // Movement owned by an active press is a drag sample. Keep it
                // on the recognizer stream; release publishes the final hover.
                if event.type == .pointing || event.type == .buttonUp ||
                    (event.type == .move && !hasActivePointerGesture) {
                    self.handleMouseHover(
                        at: event.location,
                        deviceID: event.deviceID,
                        isTopMost: true,
                        at: eventTime
                    )
                } else if event.type == .cancelled {
                    self.handleMouseHover(
                        at: event.location,
                        deviceID: event.deviceID,
                        isTopMost: false,
                        at: eventTime
                    )
                }
            }
        }
    }

    // MARK: - Input Handling

    private struct KeyboardEventHandlerStream: Hashable {
        var handlerID: ObjectIdentifier
        var deviceID: Int
        var key: VirtualKey
    }

    // Preserve key-down/key-up ownership without letting an unrelated next key
    // bypass a newly opened presentation child.
    private var _lastKeyboardEventHandler: KeyboardEventHandlerStream? = nil
    private var _lastMouseEventHandler: ObjectIdentifier? = nil

    @discardableResult
    func handleKeyboardEvent(event: KeyboardEvent) -> Bool {
        handleKeyboardEvent(event: event, at: currentTimestamp)
    }

    func handleMenuBoundaryKeyboardEvent(_ event: KeyboardEvent) -> Bool {
        windowCommandMenuPresenter?.handleKeyboardEvent(
            event,
            in: self,
            isMenuBoundary: true
        ) == true
    }

    @discardableResult
    func handleKeyboardEvent(event: KeyboardEvent, at time: Time) -> Bool {
        let handleEvent = { (event: KeyboardEvent) -> Bool in
            if let window = self.window, window !== event.window { return false }
            if self.windowCommandMenuPresenter?.handleKeyboardEvent(
                event,
                in: self
            ) == true {
                return true
            }
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
           _lastKeyboardEventHandler.deviceID == event.deviceID,
           _lastKeyboardEventHandler.key == event.key,
           let index = handlers.firstIndex(where: {
               _lastKeyboardEventHandler.handlerID == $0.id
           }) {
            let tmp = handlers.remove(at: index)
            handlers.insert(tmp, at: 0)
        }
        for handler in handlers {
            if handler.action(event) {
                _lastKeyboardEventHandler = KeyboardEventHandlerStream(
                    handlerID: handler.id,
                    deviceID: event.deviceID,
                    key: event.key
                )
                return true
            }
        }
        _lastKeyboardEventHandler = nil
        return false
    }

    @discardableResult
    func handleMouseEvent(event: PlatformMouseEvent) -> Bool {
        handleMouseEvent(event: event, at: currentTimestamp)
    }

    @discardableResult
    func handleMouseEvent(event: PlatformMouseEvent, at time: Time) -> Bool {
        let handleEvent = { (event: PlatformMouseEvent) -> Bool in
            if let window = self.window, window !== event.window { return false }
            if event.type == .wheel { return false }
            guard let rootResponder = self.responderNode
                as? MultiViewResponder else {
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
            // Map backend device IDs to EventID values before forwarding to GestureGraph.
            let hasIndependentPointerIdentity = event.device == .touch ||
                event.device == .stylus
            let usesTouchPayload = event.device == .touch ||
                (event.device == .stylus && event.buttonID == 0)
            let pointerScrollKey = PointerScrollKey(
                isTouch: hasIndependentPointerIdentity,
                deviceID: hasIndependentPointerIdentity ? event.deviceID : 0
            )

            let dispatchResult: WindowGestureDispatchResult
            switch event.type {
            case .buttonDown:
                let serial = self.nextEventSerial()
                let eventType: Any.Type = usesTouchPayload
                    ? TouchEvent.self
                    : MouseEvent.self
                let pointerEventID = EventID(type: eventType, serial: serial)
                if hasIndependentPointerIdentity {
                    self._touchEventIDs[event.deviceID] = pointerEventID
                } else {
                    self._mouseEventID = pointerEventID
                }
                self._activeEvents[pointerEventID] = self.pointerEvent(
                    from: event,
                    phase: .began,
                    at: time
                )
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
                        timestamp: time,
                        phase: .began,
                        binding: nil,
                        translation: .zero,
                        modifiers: [],
                        hitTestLocation: event.location
                    )
                }
                dispatchResult = self.sendRecognizerOwnedEvents(
                    self._activeEvents,
                    at: time
                )

            case .move:
                let pointerEventID = hasIndependentPointerIdentity
                    ? self._touchEventIDs[event.deviceID]
                    : self._mouseEventID
                guard let pointerEventID else { return false }
                self._activeEvents[pointerEventID] = self.pointerEvent(
                    from: event,
                    phase: .active,
                    at: time
                )
                if var scrollState = self._pointerScrollStates[pointerScrollKey] {
                    // Accumulate from raw locations instead of backend deltas;
                    // some backends omit or coalesce the latter during a drag.
                    let delta = CGSize(
                        width: event.location.x - scrollState.previousLocation.x,
                        height: event.location.y - scrollState.previousLocation.y
                    )
                    scrollState.translation.width += delta.width
                    scrollState.translation.height += delta.height
                    scrollState.previousLocation = event.location
                    self._pointerScrollStates[pointerScrollKey] = scrollState
                    self._activeEvents[scrollState.eventID] = ScrollEvent(
                        timestamp: time,
                        phase: .active,
                        binding: nil,
                        translation: scrollState.translation,
                        modifiers: [],
                        hitTestLocation: event.location
                    )
                }
                dispatchResult = self.sendRecognizerOwnedEvents(
                    self._activeEvents,
                    at: time
                )

            case .buttonUp, .cancelled:
                let terminalPhase: EventPhase = event.type == .cancelled
                    ? .failed
                    : .ended
                let pointerEventID: EventID?
                if hasIndependentPointerIdentity {
                    pointerEventID = self._touchEventIDs.removeValue(forKey: event.deviceID)
                } else {
                    pointerEventID = self._mouseEventID
                    self._mouseEventID = nil
                }
                guard let pointerEventID else { return false }
                self._activeEvents[pointerEventID] = self.pointerEvent(
                    from: event,
                    phase: terminalPhase,
                    at: time
                )
                let scrollState = self._pointerScrollStates.removeValue(forKey: pointerScrollKey)
                if let scrollState {
                    let delta = CGSize(
                        width: event.location.x - scrollState.previousLocation.x,
                        height: event.location.y - scrollState.previousLocation.y
                    )
                    let translation = CGSize(
                        width: scrollState.translation.width + delta.width,
                        height: scrollState.translation.height + delta.height
                    )
                    self._activeEvents[scrollState.eventID] = ScrollEvent(
                        timestamp: time,
                        phase: terminalPhase,
                        binding: nil,
                        translation: translation,
                        modifiers: [],
                        hitTestLocation: event.location
                    )
                }
                dispatchResult = self.sendRecognizerOwnedEvents(
                    self._activeEvents,
                    at: time
                )
                self._activeEvents.removeValue(forKey: pointerEventID)
                if let scrollState { self._activeEvents.removeValue(forKey: scrollState.eventID) }

            default:
                return false
            }
            return dispatchResult.handlesPlatformEvent
        }

        // Build handler list: presentation children (reversed = top-first) then self.
        var handlers = self.presentationChildren.withLock {
            $0.reversed().compactMap { entry -> (target: AnyObject, action: (PlatformMouseEvent) -> Bool)? in
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
                      let rootResponder = self.responderNode
                        as? MultiViewResponder else {
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
    private func handleMouseWheel(event: PlatformMouseEvent, time: Time) -> Bool {
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

        guard scrollData.phase != nil || scrollData.nativeMomentumPhase != nil else {
            return dispatchDiscreteWheel(
                at: event.location,
                delta: event.delta,
                time: time
            )
        }

        var handled = false
        if let phase = scrollData.phase {
            // A handoff event can carry the terminal direct phase and the first
            // native momentum phase together. Its displacement belongs to the
            // inertial stream, which is intentionally replaced by host motion.
            let directDelta = scrollData.nativeMomentumPhase == nil
                ? event.delta
                : .zero
            handled = dispatchContinuousWheel(
                at: event.location,
                delta: directDelta,
                phase: phase,
                time: time
            )
        }

        if scrollData.nativeMomentumPhase != nil {
            // The host already owns one deceleration model. Native inertial
            // samples are acknowledged but never applied a second time.
            handled = (gestureEnvironment.eventBinding(
                at: event.location,
                accepting: SystemWheelEvent.self
            ) != nil) || handled
        }
        return handled
    }

    private func dispatchDiscreteWheel(
        at location: CGPoint,
        delta: CGPoint,
        time: Time
    ) -> Bool {
        guard let binding = gestureEnvironment.eventBinding(
            at: location,
            accepting: SystemWheelEvent.self
        ) else {
            // Preserve the scalar wheel carrier for the single-axis scroll route.
            guard delta.x == 0,
                  let legacyBinding = gestureEnvironment.eventBinding(
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
            let beganResult = sendRecognizerOwnedEvents([eventID: began], at: time)
            let ended = WheelEvent(
                timestamp: time,
                phase: .ended,
                binding: legacyBinding,
                offset: Double(delta.y)
            )
            let endedResult = sendRecognizerOwnedEvents([eventID: ended], at: time)
            return beganResult.handlesPlatformEvent ||
                endedResult.handlesPlatformEvent
        }

        let eventID = EventID(type: SystemWheelEvent.self, serial: nextEventSerial())
        let began = SystemWheelEvent(
            timestamp: time,
            phase: .began,
            binding: binding,
            scrollingDelta: CGSize(width: delta.x, height: delta.y)
        )
        let beganResult = sendRecognizerOwnedEvents([eventID: began], at: time)
        let ended = SystemWheelEvent(
            timestamp: time,
            phase: .ended,
            binding: binding,
            scrollingDelta: CGSize(width: delta.x, height: delta.y)
        )
        let endedResult = sendRecognizerOwnedEvents([eventID: ended], at: time)
        return beganResult.handlesPlatformEvent ||
            endedResult.handlesPlatformEvent
    }

    private func dispatchContinuousWheel(
        at location: CGPoint,
        delta: CGPoint,
        phase: ScrollEventPhase,
        time: Time
    ) -> Bool {
        if phase == .mayBegin {
            return gestureEnvironment.eventBinding(
                at: location,
                accepting: SystemWheelEvent.self
            ) != nil
        }

        let gestureDelta = CGSize(width: delta.x, height: delta.y)
        let eventPhase: EventPhase
        let eventID: EventID
        let binding: EventBinding
        switch phase {
        case .began:
            guard let resolvedBinding = gestureEnvironment.eventBinding(
                at: location,
                accepting: SystemWheelEvent.self
            ) else { return false }
            eventPhase = .began
            eventID = EventID(type: SystemWheelEvent.self, serial: nextEventSerial())
            _wheelScrollEventID = eventID
            _wheelScrollBinding = resolvedBinding
            _wheelScrollLastTime = time
            _wheelScrollVelocity = _Velocity(valuePerSecond: .zero)
            binding = resolvedBinding
        case .stationary, .changed:
            eventPhase = .active
            if let activeID = _wheelScrollEventID,
               let activeBinding = _wheelScrollBinding {
                eventID = activeID
                binding = activeBinding
            } else {
                guard let resolvedBinding = gestureEnvironment.eventBinding(
                    at: location,
                    accepting: SystemWheelEvent.self
                ) else { return false }
                eventID = EventID(type: SystemWheelEvent.self, serial: nextEventSerial())
                _wheelScrollEventID = eventID
                _wheelScrollBinding = resolvedBinding
                _wheelScrollLastTime = time
                _wheelScrollVelocity = _Velocity(valuePerSecond: .zero)
                binding = resolvedBinding
                let began = SystemWheelEvent(
                    timestamp: time,
                    phase: .began,
                    binding: resolvedBinding,
                    scrollingDelta: .zero,
                    kind: .continuous
                )
                _ = sendRecognizerOwnedEvents([eventID: began], at: time)
            }
        case .ended:
            eventPhase = .ended
            guard let activeID = _wheelScrollEventID,
                  let activeBinding = _wheelScrollBinding else { return false }
            eventID = activeID
            binding = activeBinding
        case .cancelled:
            eventPhase = .failed
            guard let activeID = _wheelScrollEventID,
                  let activeBinding = _wheelScrollBinding else { return false }
            eventID = activeID
            binding = activeBinding
        case .mayBegin:
            return false
        }

        if eventPhase == .active {
            let elapsed = time.seconds - (_wheelScrollLastTime ?? time).seconds
            if elapsed.isFinite, elapsed > 0 {
                _wheelScrollVelocity = _Velocity(valuePerSecond: CGSize(
                    width: gestureDelta.width / elapsed,
                    height: gestureDelta.height / elapsed
                ))
            } else {
                _wheelScrollVelocity = _Velocity(valuePerSecond: gestureDelta)
            }
            _wheelScrollLastTime = time
        }
        let scrollEvent = SystemWheelEvent(
            timestamp: time,
            phase: eventPhase,
            binding: binding,
            scrollingDelta: CGSize(width: delta.x, height: delta.y),
            velocity: _wheelScrollVelocity,
            kind: .continuous
        )
        let result = sendRecognizerOwnedEvents([eventID: scrollEvent], at: time)
        if eventPhase.isTerminal {
            _wheelScrollEventID = nil
            _wheelScrollBinding = nil
            _wheelScrollLastTime = nil
            _wheelScrollVelocity = _Velocity(valuePerSecond: .zero)
        }
        return result.handlesPlatformEvent
    }

    @discardableResult
    func handleGestureEvent(event: GestureEvent) -> Bool {
        handleGestureEvent(event: event, at: currentTimestamp)
    }

    @discardableResult
    func handleGestureEvent(event: GestureEvent, at time: Time) -> Bool {
        if let window = self.window, window !== event.window { return false }
        guard responderNode != nil else { return false }

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
            _scrollTranslation.width += delta.width
            _scrollTranslation.height += delta.height
            let scrollEvent = ScrollEvent(
                timestamp: time,
                phase: eventPhase,
                binding: nil,
                translation: _scrollTranslation,
                modifiers: [],
                hitTestLocation: event.location
            )
            // Platform pan input is already classified, but it still needs a
            // recognizer-owned session; direct-host tracking may suppress later
            // values after forwarding ownership to another host path.
            let result = sendRecognizerOwnedEvents([eventID: scrollEvent], at: time)
            if eventPhase.isTerminal {
                _scrollEventID = nil
                _scrollTranslation = .zero
            }
            return result.handlesPlatformEvent

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
            let initialScale = _magnification
            let magnifyEvent = MagnifyEvent(
                timestamp: time,
                phase: eventPhase,
                binding: nil,
                globalLocation: event.location,
                scaleDelta: event.magnification,
                initialScale: initialScale
            )
            let result = sendRecognizerOwnedEvents([eventID: magnifyEvent], at: time)
            _magnification = initialScale + event.magnification
            if eventPhase.isTerminal {
                _magnifyEventID = nil
                _magnification = 1.0
            }
            return result.handlesPlatformEvent

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
            let initialAngle = _rotation
            let angleDelta = Angle(degrees: event.rotation)
            let rotateEvent = RotateEvent(
                timestamp: time,
                phase: eventPhase,
                binding: nil,
                globalLocation: event.location,
                angleDelta: angleDelta,
                initialAngle: initialAngle
            )
            let result = sendRecognizerOwnedEvents([eventID: rotateEvent], at: time)
            _rotation = initialAngle + angleDelta
            if eventPhase.isTerminal {
                _rotateEventID = nil
                _rotation = .zero
            }
            return result.handlesPlatformEvent
        }
    }

    @discardableResult
    func handleMouseHover(at location: CGPoint,
                          deviceID: Int,
                          isTopMost: Bool,
                          at time: Time) -> Bool {
        _lastHoverRefresh = (location: location, deviceID: deviceID, isTopMost: isTopMost)
        var topMost = isTopMost
        self.presentationChildren.withLock({ $0.reversed() }).forEach { entry in
            guard entry.isOverlay, entry.initiated else { return }
            let child = entry.controller
            if entry.frame != nil {
                let loc = child.presentationPointInLocal(fromParentPoint: location)
                // Hover-end delivery may be consumed by the child that owned
                // the preceding sample. Consumption does not make that child
                // the frontmost surface at the new location. Resolve current
                // ownership geometrically, including descendants that extend
                // beyond their ancestor popup's frame.
                let childOwnsTopMost = topMost && (
                    child.overlayHitTest(loc) ||
                    child.containsOverlayPresentation(at: loc)
                )
                _ = child.handleMouseHover(
                    at: loc,
                    deviceID: deviceID,
                    isTopMost: childOwnsTopMost,
                    at: time
                )
                if childOwnsTopMost {
                    topMost = false
                }
            }
        }
        if topMost {
            onTopMostMouseHover(
                at: location,
                deviceID: deviceID,
                at: time
            )
        }
        if sendHoverEvent(at: location,
                          deviceID: deviceID,
                          isTopMost: topMost,
                          at: time) {
            topMost = false
        }
        return isTopMost != topMost
    }

    private func containsOverlayPresentation(at location: CGPoint) -> Bool {
        for entry in presentationChildren.withLock({ $0.reversed() }) {
            guard entry.isOverlay, entry.initiated, entry.frame != nil else {
                continue
            }
            let child = entry.controller
            let localPoint = child.presentationPointInLocal(
                fromParentPoint: location
            )
            if child.overlayHitTest(localPoint) ||
                child.containsOverlayPresentation(at: localPoint) {
                return true
            }
        }
        return false
    }

    // Subclasses that own a rectangular tracking surface can react after
    // nested overlay hit testing has selected this controller as the frontmost
    // hover target. Running this hook before descendant routing would let
    // overlapping parent and child surfaces fight over transient state.
    func onTopMostMouseHover(
        at location: CGPoint,
        deviceID: Int,
        at time: Time
    ) {}

    @discardableResult
    private func sendHoverEvent(at location: CGPoint,
                                deviceID: Int,
                                isTopMost: Bool,
                                at time: Time) -> Bool {
        let eventID: EventID
        let phase: EventPhase
        if isTopMost {
            if let currentID = _hoverEventIDs[deviceID] {
                eventID = currentID
                phase = .active
            } else {
                eventID = EventID(type: HoverEvent.self, serial: nextEventSerial())
                _hoverEventIDs[deviceID] = eventID
                phase = .began
            }
        } else if let currentID = _hoverEventIDs[deviceID] {
            eventID = currentID
            phase = .ended
        } else {
            return false
        }

        let hoverEvent = HoverEvent(
            timestamp: time,
            phase: phase,
            binding: nil,
            globalLocation: location
        )
        let consumed = sendHostEvents(
            [eventID: hoverEvent],
            track: false,
            at: time
        )
        if phase.isTerminal {
            _hoverEventIDs.removeValue(forKey: deviceID)
        }
        return consumed.contains(eventID)
    }

    func resetGestureHandlers() {
        resetGestureHandlers(reason: "unspecified")
    }

    private func resetGestureHandlers(reason: String) {
        gestureEnvironment.reset()
        eventBindingManager.reset(
            resetForwardedEventDispatchers: true
        )
        contextMenuRecognizer.reset()
        _touchEventIDs.removeAll()
        _mouseEventID = nil
        _spatialEventIDs.removeAll()
        _mouseSpatialEventID = nil
        _scrollEventID = nil
        _scrollTranslation = .zero
        _wheelScrollEventID = nil
        _wheelScrollBinding = nil
        _wheelScrollLastTime = nil
        _wheelScrollVelocity = _Velocity(valuePerSecond: .zero)
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
    // opaqueBackground: true if the resolved background has no transparency.
    func updateRenderContext(_ context: inout ViewGraphRenderContext) {
        let contentScaleFactor = self.contentScaleFactor
        sceneResources.contentScaleFactor = contentScaleFactor
        context.contentsScale = contentScaleFactor
        // backgroundColor.opacity is 0.0-1.0. Treat >= 1.0 as fully opaque.
        // The backend color alpha is stored as a normalized Scalar.
        context.opaqueBackground = (configuration.backgroundColor.a >= 1.0)
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
        // This graph is owned by the WindowContext update lane. Wake that lane
        // so updateView drains the pending transaction without entering the
        // graph concurrently from a second thread.
        setNeedsUpdate()
    }

    // MARK: - ViewGraphRootValueUpdater

    func updateRootView() {
        guard let staticRootContent,
              let rootToolbarBridge,
              let rootInput = viewGraph.rootAnyViewContentInput else {
            return
        }
        let toolbarRoot = RootToolbarHost.hostRootView(
            sceneContent: staticRootContent,
            bridge: rootToolbarBridge
        )
        rootInput.setValue(
            WindowCommandMenuPresenter.hostRootView(
                sceneContent: toolbarRoot,
                presenter: windowCommandMenuPresenter
            )
        )
    }

    func updateEnvironment() {
        let contentScaleFactor = self.contentScaleFactor
        environment.displayScale = contentScaleFactor
        environment._contentScaleFactor = contentScaleFactor
        viewGraph.setEnvironment(
            environment,
            wrapper: environmentWrapper
        )
    }

    // Presentation roots own a distinct ViewGraph, but begin with the
    // environment at the source presentation site. Platform presentation
    // graphs run on their own render thread, so route later updates through
    // the child graph's inbox instead of entering that graph from the source
    // graph's thread.
    func setPresentationEnvironment(
        _ environment: EnvironmentValues,
        viewPhase: ViewGraphHost.Phase
    ) {
        let wrapper = ViewGraphHostEnvironmentWrapper()
        wrapper.environment = environment.untrackedCopy()
        wrapper.phase = viewPhase
        let snapshot = UnsafeBox(wrapper)
        viewGraph.data.graph.inbox.enqueue { [weak self, snapshot] in
            guard let self else { return }
            var environment = snapshot.value.environment.trackingCopy()
            let contentScaleFactor = self.contentScaleFactor
            environment.displayScale = contentScaleFactor
            environment._contentScaleFactor = contentScaleFactor
            self.environment = environment
            self.environmentWrapper.phase = snapshot.value.phase
            self.viewGraph.setEnvironment(
                environment,
                wrapper: self.environmentWrapper
            )

            guard let phase = self.viewGraph.phaseAttr else {
                fatalError("Presentation environment propagation requires an instantiated ViewGraph.")
            }
            let childPhase = ViewGraphHost.Phase(base: phase.value)
            let childEnvironment = environment.untrackedCopy()
            self.forEachPresentationChild {
                $0.setPresentationEnvironment(
                    childEnvironment,
                    viewPhase: childPhase
                )
            }
        }
    }

    func updateSize() {
        viewGraph.sizeAttr?.setValue(ViewSize(cachedContentSize))
    }

    func updateSafeArea()      {}  // Safe area is not wired yet.
    func updateContainerSize() {
        viewGraph.setContainerSize(ViewSize(cachedContentSize))
    }
    func updateTransform()         {}  // Transform root input is not wired yet.
    func updateFocusStore()        {}  // Focus store is not wired yet.
    func updateFocusedItem()       {}  // Focused item is not wired yet.
    func updateFocusedValues() {
        viewGraph.setFocusedValues(resolvedFocusedValues)
    }
    func updateAccessibilityEnvironment() {}  // Accessibility root input is not wired yet.

    // MARK: - Presentation Child / Modal Management (nested structure)
    // WindowController owns its dynamic children directly (strong refs).
    // AppWindowsController is not involved in dynamic presentation-child/modal lifetime.

    // Parent that opened this window (nil = root window). Keep the inherited
    // host context when the parent is cleared so teardown and any in-flight
    // final frame remain serialized with the presentation tree. A later
    // reparenting replaces it with the new tree's context.
    weak var parentWindow: WindowController? {
        didSet {
            if let parentWindow {
                hostUpdateContext = parentWindow.hostUpdateContext
            }
        }
    }

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
        child.inheritedValues = inheritedValues
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
        child.inheritedValues = inheritedValues
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
            // its window resolver creates the platform window.
            if let presented = modalChildren.withLock({ $0.first?.session.isPresented }),
               !presented.wrappedValue {
                removeModal(child: child, reason: .cancelled)
                return
            }

            attachWindow({ [weak self, weak child] childWindow in
                guard let self, let child else {
                    childWindow.close()
                    return
                }

                let isCurrent = self.modalChildren.withLock { entries in
                    guard let first = entries.indices.first else { return false }
                    return entries[first].controller === child &&
                        !entries[first].initiated
                }
                guard isCurrent else {
                    childWindow.close()
                    return
                }

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
                        guard let first = entries.indices.first,
                              entries[first].controller === child,
                              !entries[first].initiated else {
                            return false
                        }
                        entries[first].isOverlay = false
                        entries[first].initiated = true
                        return true
                    }
                    if didInitiate {
                        child.onModalSessionInitiated(
                            transaction: entry.presentationTransaction
                        )
                        self.enqueueModalSessionInputReset(
                            reason: "modal session initiated"
                        )
                    } else {
                        _ = self.window?.dismissModalWindow(childWindow)
                        childWindow.close()
                    }
                } else {
                    Log.error("WindowController: presentModalWindow failed")
                    self.removeModal(child: child, reason: .cancelled)
                }
            })

            // The resolver may enqueue one MainActor handoff before invoking
            // AttachWindow. Queue the fallback afterwards so that handoff gets
            // the first opportunity to mark this entry as initiated.
            Task { @MainActor [weak self, weak child] in
                guard let self, let child else { return }
                let didInitiate = self.modalChildren.withLock { entries in
                    guard let first = entries.indices.first,
                          entries[first].controller === child,
                          !entries[first].initiated else {
                        return false
                    }
                    entries[first].isOverlay = true
                    entries[first].initiated = true
                    return true
                }
                if didInitiate {
                    child.onModalSessionInitiated(
                        transaction: entry.presentationTransaction
                    )
                    self.enqueueModalSessionInputReset(
                        reason: "modal overlay fallback initiated"
                    )
                }
            }
        } else {
            entry.attachWindow?(nil)
            modalChildren.withLock { entries in
                if let i = entries.firstIndex(where: { $0.controller === child }) {
                    entries[i].isOverlay = true
                    entries[i].initiated = true
                }
            }
            child.onModalSessionInitiated(transaction: entry.presentationTransaction)
            self.resetGestureHandlers(reason: "modal overlay initiated")
            self.handleMouseHover(at: .zero,
                                  deviceID: 0,
                                  isTopMost: false,
                                  at: self.currentTimestamp)
            recomputeFocusedValues()
        }
    }

    private func enqueueModalSessionInputReset(reason: String) {
        // Platform presentation completion runs on the main actor while the
        // owning graph may be evaluated elsewhere. Graph-backed input state
        // must always be reset through that graph's input lane.
        enqueueInputAction { [weak self] in
            guard let self else { return }
            self.resetGestureHandlers(reason: reason)
            self.handleMouseHover(at: .zero,
                                  deviceID: 0,
                                  isTopMost: false,
                                  at: self.currentTimestamp)
            self.recomputeFocusedValues()
        }
    }

    // Show the front of the queue after the previous active modal was removed.
    private func _showNextInQueue() {
        guard modalChildren.withLock({ !$0.isEmpty }) else { return }

        // Removal can originate in a platform completion callback. Resolve the
        // next child's graph-backed attachment from this controller's update
        // lane instead of evaluating that child on the callback thread.
        enqueueInputAction { [weak self] in
            self?._activateNextModalInQueue()
        }
    }

    private func _activateNextModalInQueue() {
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

        if wasFirst {
            scheduleFocusedValuesRecompute()
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
        if !entries.isEmpty {
            scheduleFocusedValuesRecompute()
        }
    }

    // MARK: - Preference-driven presentation (sheet / alert)
    // Sheet, alert, and dialog presentation go through the unified modalChildren queue.

    /// Called from ViewGraph side-effect rule when SheetPreference.Key changes.
    func updateSheetPresentation(_ value: SheetPreference.Value,
                                 transaction: Transaction = Transaction(),
                                 viewPhase: ViewGraphHost.Phase) {
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
            let existingPresentation: (Attribute<AnyView>, ModalWindowController)? = modalChildren.withLock { entries in
                guard let index = entries.firstIndex(where: {
                    guard case .sheet(let existing) = $0.session else { return false }
                    return sid(existing) == sid(pref)
                }) else {
                    return nil
                }
                entries[index].session = .sheet(pref)
                guard let contentAttr = entries[index].contentAttr else { return nil }
                return (contentAttr, entries[index].controller)
            }
            if let (existingContentAttr, controller) = existingPresentation {
                controller.setPresentationEnvironment(
                    pref.presentationEnvironment,
                    viewPhase: viewPhase
                )
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
                                             environment: pref.presentationEnvironment,
                                             viewPhase: viewPhase,
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
    func updateConfirmationDialogPresentation(
        _ dialogs: [ConfirmationDialogPreference],
        viewPhase: ViewGraphHost.Phase
    ) {
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
                                             viewPhase: viewPhase,
                                             scene: key,
                                             parentController: self,
                                             usesPlatformWindow: pref.usesPlatformWindow)
            addModal(child: ctrl, session: .confirmationDialog(pref)) { [weak ctrl] attach in
                ctrl?.resolveModalWindowAttachment(attach)
            }
        }
    }

    /// Called from ViewGraph side-effect rule when AlertStorage.PreferenceKey changes.
    func updateAlertPresentation(
        _ alerts: [AlertPreference],
        viewPhase: ViewGraphHost.Phase
    ) {
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
                                             viewPhase: viewPhase,
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
