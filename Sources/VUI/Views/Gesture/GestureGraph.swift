//
//  File: GestureGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

// EventRecord

/// Event wrapper used internally when bridging platform events into the gesture pipeline.
/// Retained as a local bridge type. It is not part of EventGraphHost.sendEvents signature.
struct EventRecord {
    var mouseEvent: MouseEvent
    var time: Time

    init(_ mouseEvent: MouseEvent, at time: Time = Time(seconds: 0)) {
        self.mouseEvent = mouseEvent
        self.time = time
    }
}

// GestureCategory

/// Classifies the primary gesture type active in a gesture graph.
struct GestureCategory: OptionSet, Sendable {
    var rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let magnify    = GestureCategory(rawValue: 1)   // bit 0
    static let rotate     = GestureCategory(rawValue: 2)   // bit 1
    static let drag       = GestureCategory(rawValue: 4)   // bit 2
    static let select     = GestureCategory(rawValue: 8)   // bit 3
    static let longPress  = GestureCategory(rawValue: 16)  // bit 4
    static let windowDrag = GestureCategory(rawValue: 32)  // bit 5
}

// EventBinding / EventBindingManager

/// Binds a single EventID to a specific ResponderNode for the duration of an interaction.
struct EventBinding: Equatable {
    var responder: ResponderNode

    init(responder: ResponderNode) {
        self.responder = responder
    }

    static func == (lhs: EventBinding, rhs: EventBinding) -> Bool {
        lhs.responder === rhs.responder
    }
}

/// Manages the mapping from EventID to EventBinding (which responder owns which event stream).
/// When a new touch/click begins, `rebindEvent` routes subsequent events for that ID
/// to the responder that won the hit test.
///
/// This local manager currently stores bindings plus root/focused responders. Host/delegate
/// forwarding is represented by the explicit host argument to sendDownstream.
class EventBindingManager {
    var bindings: [EventID: EventBinding] = [:]
    weak var host: (any EventGraphHost)?
    weak var delegate: (any EventBindingManagerDelegate)?
    var rootResponder: ResponderNode?
    var focusedResponder: ResponderNode?
    private(set) var lastDirectConsumedEventIDs: Set<EventID> = []
    private var hoverUpdatePending = false
    private let lock = Mutex(())

    init() {}

    /// Routes `eventID` to `responder`. Returns the old and new bindings.
    @discardableResult
    func rebindEvent(_ eventID: EventID, to responder: ResponderNode?) -> (from: EventBinding?, to: EventBinding?)? {
        let old = bindings[eventID]
        if let r = responder {
            let new = EventBinding(responder: r)
            bindings[eventID] = new
            return (from: old, to: new)
        } else {
            bindings.removeValue(forKey: eventID)
            return (from: old, to: nil)
        }
    }

    /// Removes the binding for a given event ID (called when interaction ends).
    func willRemoveResponder(_ responder: ResponderNode) {
        bindings = bindings.filter { $0.value.responder !== responder }
    }

    /// Routes events produced directly by a platform host.
    @discardableResult
    func send(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> GesturePhase<Void> {
        withDispatchScope {
            lastDirectConsumedEventIDs = delegate?.receiveDirectEvents(events, in: self) ?? []
            return sendDownstreamBody(events, bridge: nil, at: time)
        }
    }

    /// Routes a pre-computed event dictionary downstream to the appropriate EventGraphHost.
    ///
    @discardableResult
    func sendDownstream(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> GesturePhase<Void> {
        sendDownstream(events, bridge: nil, at: time)
    }

    /// Routes a pre-computed event dictionary downstream to the appropriate EventGraphHost.
    @discardableResult
    func sendDownstream(
        _ events: [EventID: any EventType],
        bridge: EventBindingBridge?,
        at time: Time
    ) -> GesturePhase<Void> {
        withDispatchScope {
            sendDownstreamBody(events, bridge: bridge, at: time)
        }
    }

    private func withDispatchScope<Result>(_ body: () -> Result) -> Result {
        lock.withLock { _ in
            Update.begin()
            defer {
                Update.end()
            }
            return body()
        }
    }

    private func sendDownstreamBody(
        _ events: [EventID: any EventType],
        bridge: EventBindingBridge?,
        at time: Time
    ) -> GesturePhase<Void> {
        guard let host else { return .possible(nil) }
        guard let rootNode = rootResponder ?? host.responderNode else { return .possible(nil) }
        guard !events.isEmpty else { return .possible(nil) }
        let phase = host.sendEvents(events, rootNode: rootNode, at: time)
        for eventID in events.keys {
            bridge?.didBind(to: bindings[eventID], id: eventID)
        }
        bridge?.didUpdate(phase: phase, in: self)
        if let category = host.gestureCategory() {
            bridge?.didUpdate(gestureCategory: category)
        }
        return phase
    }

    /// Backward-compatible entry for callers that still carry the host explicitly.
    @discardableResult
    func sendDownstream(
        _ events: [EventID: any EventType],
        host explicitHost: any EventGraphHost,
        at time: Time
    ) -> GesturePhase<Void> {
        withDispatchScope {
            sendDownstreamBody(events, host: explicitHost, at: time)
        }
    }

    private func sendDownstreamBody(
        _ events: [EventID: any EventType],
        host explicitHost: any EventGraphHost,
        at time: Time
    ) -> GesturePhase<Void> {
        guard let rootNode = rootResponder ?? explicitHost.responderNode else { return .possible(nil) }
        guard !events.isEmpty else { return .possible(nil) }
        return explicitHost.sendEvents(events, rootNode: rootNode, at: time)
    }

    func reset() {
        bindings.removeAll()
        lastDirectConsumedEventIDs.removeAll()
    }

    func enqueueHoverUpdateIfNeeded() {
        guard !hoverUpdatePending else { return }
        hoverUpdatePending = true
        delegate?.requestHoverUpdate(in: self)
    }

    func clearHoverUpdatePending() {
        hoverUpdatePending = false
    }
}

// GestureGraphDelegate

/// Protocol adopted by the entity that drives the gesture graph lifecycle
/// (typically the WindowController's event bridge).
protocol GestureGraphDelegate: AnyObject {
    func enqueueAction(_ action: @escaping () -> Void)
}

// EventBindingSource / EventBindingManagerDelegate / EventBindingBridge

protocol EventBindingSource: AnyObject {
    func didBind(to binding: EventBinding?, id: EventID)
    func didUpdate(phase: GesturePhase<Void>)
    func didUpdate(gestureCategory: GestureCategory)
    func didRequestHoverUpdate()
}

extension EventBindingSource {
    func didBind(to binding: EventBinding?, id: EventID) {}
    func didUpdate(phase: GesturePhase<Void>) {}
    func didUpdate(gestureCategory: GestureCategory) {}
    func didRequestHoverUpdate() {}
}

protocol EventBindingManagerDelegate: AnyObject {
    func requestHoverUpdate(in manager: EventBindingManager)
    func receiveDirectEvents(
        _ events: [EventID: any EventType],
        in manager: EventBindingManager
    ) -> Set<EventID>
}

extension EventBindingManagerDelegate {
    func receiveDirectEvents(
        _ events: [EventID: any EventType],
        in manager: EventBindingManager
    ) -> Set<EventID> {
        []
    }
}

private final class WeakEventBindingSource {
    weak var value: (any EventBindingSource)?

    init(_ value: any EventBindingSource) {
        self.value = value
    }
}

/// Bridge between concrete platform event producers and the shared event manager.
class EventBindingBridge: GestureGraphDelegate {
    struct TrackedEventState {
        var sourceID: ObjectIdentifier
        var resetForwardedEventDispatchers: Bool
    }

    weak var manager: EventBindingManager?
    private var trackedStates: [EventID: TrackedEventState] = [:]
    private var weakSources: [WeakEventBindingSource] = []
    private var pendingActions: [() -> Void] = []
    private(set) var lastPhase: GesturePhase<Void> = .possible(nil)

    init(manager: EventBindingManager? = nil) {
        self.manager = manager
    }

    var eventSources: [any EventBindingSource] {
        weakSources = weakSources.filter { $0.value != nil }
        return weakSources.compactMap(\.value)
    }

    func addEventSource(_ source: any EventBindingSource) {
        let id = ObjectIdentifier(source as AnyObject)
        guard !eventSources.contains(where: { ObjectIdentifier($0 as AnyObject) == id }) else {
            return
        }
        weakSources.append(WeakEventBindingSource(source))
    }

    @discardableResult
    func send(
        _ events: [EventID: any EventType],
        source: any EventBindingSource,
        at time: Time
    ) -> Set<EventID> {
        addEventSource(source)
        guard !events.isEmpty else {
            lastPhase = .possible(nil)
            return []
        }

        let sourceID = ObjectIdentifier(source as AnyObject)
        var downstream: [EventID: any EventType] = [:]
        for (eventID, event) in events {
            downstream[eventID] = event
            switch event.eventPhase {
            case .began, .moved:
                trackedStates[eventID] = TrackedEventState(
                    sourceID: sourceID,
                    resetForwardedEventDispatchers: false
                )
            case .ended, .cancelled:
                trackedStates.removeValue(forKey: eventID)
            }
        }

        lastPhase = manager?.sendDownstream(downstream, bridge: self, at: time) ?? .possible(nil)
        flushActions()
        switch lastPhase {
        case .active, .ended:
            return Set(downstream.keys)
        case .possible, .failed:
            return []
        }
    }

    func reset(eventSource: (any EventBindingSource)? = nil,
               resetForwardedEventDispatchers: Bool = false) {
        if let eventSource {
            let sourceID = ObjectIdentifier(eventSource as AnyObject)
            trackedStates = trackedStates.filter { _, state in
                state.sourceID != sourceID
            }
        } else {
            trackedStates.removeAll()
        }
        if resetForwardedEventDispatchers {
            manager?.reset()
        }
    }

    func resetEvents() {
        for eventID in trackedStates.keys {
            if var state = trackedStates[eventID] {
                state.resetForwardedEventDispatchers = true
                trackedStates[eventID] = state
            }
        }
    }

    func didBind(to binding: EventBinding?, id: EventID) {
        for source in eventSources {
            source.didBind(to: binding, id: id)
        }
    }

    func didUpdate(phase: GesturePhase<Void>, in manager: EventBindingManager) {
        for source in eventSources {
            source.didUpdate(phase: phase)
        }
    }

    func didUpdate(gestureCategory: GestureCategory) {
        for source in eventSources {
            source.didUpdate(gestureCategory: gestureCategory)
        }
    }

    func requestHoverUpdate() {
        for source in eventSources {
            source.didRequestHoverUpdate()
        }
    }

    func enqueueAction(_ action: @escaping () -> Void) {
        pendingActions.append(action)
        flushActions()
    }

    func flushActions() {
        guard !pendingActions.isEmpty else { return }
        let actions = pendingActions
        pendingActions.removeAll()
        Update.enqueueAction {
            for action in actions {
                action()
            }
        }
    }
}

// EventGraphHost

/// Protocol for objects that own an EventBindingManager and can receive event streams.
/// WindowController fills the platform host role. GestureGraph owns the graph-side entry point.
/// isDescendant / didConsumePlatformEvent are platform-specific, so local defaults are
/// no-op / false implementations.
protocol EventGraphHost: AnyObject {
    /// Manager for EventID to ResponderNode bindings.
    var eventBindingManager: EventBindingManager { get }

    /// The root responder node for this host.
    var responderNode: ResponderNode? { get }

    /// The currently focused responder.
    var focusedResponder: ResponderNode? { get }

    /// Earliest time at which the next gesture update is needed.
    var nextGestureUpdateTime: Time { get }

    /// Delivers a pre-computed event dictionary through the responder tree.
    /// Called by EventBindingBridge to route events to the correct EventGraphHost.
    @discardableResult
    func sendEvents(
        _ events: [EventID: any EventType],
        rootNode: ResponderNode,
        at time: Time
    ) -> GesturePhase<Void>

    /// Tears down all active gesture sessions.
    func resetEvents()

    /// Returns the primary gesture category active in this host.
    func gestureCategory() -> GestureCategory?

    /// Returns true if this host is a descendant of the given host.
    /// Local backend has no platform view hierarchy here, so the default is false.
    func isDescendant(of host: AnyObject) -> Bool

    /// Notifies the host that a platform event was consumed.
    /// Local backend has no platform event passthrough here, so the default is no-op.
    func didConsumePlatformEvent(_ event: AnyObject)
}

extension EventGraphHost {
    func isDescendant(of host: AnyObject) -> Bool { false }
    func didConsumePlatformEvent(_ event: AnyObject) {}
}

// GestureGraph

/// Manages the entire gesture processing pipeline for a single window/view-graph.
///
/// Responsibilities:
/// - Owns an independent `AttributeGraph` that is not shared with ViewGraph.
/// - Performs hit testing via `MultiViewResponder` to determine which `ViewResponder`
///   receives each event stream.
/// - Dispatches events to matched responders and manages `ActiveGestureSession` lifecycles.
///
/// GestureFilter nodes live in ViewGraph's AttributeGraph. GestureGraph.current resolves
/// through AttributeGraphRef.current while GestureGraph's graph is active.
///
/// Adopts EventGraphHost for graph-side event delivery.
class GestureGraph: GraphHost, EventGraphHost, @unchecked Sendable {

    // Resolves the active GestureGraph from the AG evaluation context.
    static var current: GestureGraph {
        guard let ref = AttributeGraphRef.current, let g = ref.context as? GestureGraph else {
            fatalError("GestureGraph.current accessed outside a gesture-enabled AG context")
        }
        return g
    }

    // State

    var responderNode: ResponderNode?
    var focusedResponder: ResponderNode?
    var delegate: GestureGraphDelegate?
    var nextGestureUpdateTime: Time = .infinity

    let eventBindingManager: EventBindingManager

    /// The root multi-view responder that aggregates all ViewResponders from the view tree.
    /// Kept strongly by `_ownedRootResponder` so `rootResponder` can stay weak.
    private var _ownedRootResponder: MultiViewResponder
    weak var rootResponder: MultiViewResponder?

    /// Back-reference to the owning ViewRendererHost (WindowController).
    /// Used to access ViewGraph geometry attributes for cross-graph gesture inputs.
    /// Set by WindowController.init immediately after creating GestureGraph.
    weak var rendererHost: (any ViewRendererHost)?

    // Active gesture sessions: each EventID maps to one session per hit responder.
    var activeSessions: [EventID: [ActiveGestureSession]] = [:]

    // All EventListenerPhase nodes across all sessions read from this single attr.
    // Each session uses this shared event input instead of a separate event attribute.
    var eventsAttr: Attribute<[EventID: any EventType]>?

    // Per-batch reset seed, incremented once per sendEvents call.
    // Different from per-responder resetSeed (used for individual session teardown).
    var batchResetSeedAttr: Attribute<UInt32>?

    // Active while sendEvents is processing events.
    // Prevents re-entrant sendEvents and gates enqueueAction to the internal queue.
    private var _isProcessingEvents: Bool = false

    // Actions enqueued during AG evaluation are drained by runEventLoop.
    var pendingActions: [() -> Void] = []

    // Current event state: the last dict published to eventsAttr.
    // Set from the events parameter in sendEvents and cleared by teardownSessions.
    var currentEvents: [EventID: any EventType] = [:]

    // GestureGraph-local time attribute.
    // Created lazily inside GestureGraph's AG context on the first event call.
    var globalTimeAttr: Attribute<Time>?

    // Root inherited-phase input shared by all sessions.
    // Created alongside eventsAttr in ensureAttrsInitialised.
    // Initial value = [] (= .failed = all gestures may proceed).
    var inheritedPhaseAttr: Attribute<_GestureInputs.InheritedPhase>?

    // Aggregate GesturePhase of the current event batch.
    // Written after session lifecycle changes in sendEvents and read to produce the return value.
    var phaseAttr: Attribute<GesturePhase<Void>>?

    // Init

    /// Creates a GestureGraph with its own independent AttributeGraph.
    /// The gesture graph's AG is independent and not shared with ViewGraph.
    override init() {
        let mvr = MultiViewResponder()
        self._ownedRootResponder = mvr
        self.eventBindingManager = EventBindingManager()
        super.init()
        self.rootResponder = mvr
        self.eventBindingManager.host = self
        self.eventBindingManager.rootResponder = mvr
    }

    // Session Management

    /// Creates an `ActiveGestureSession` for a hit responder.
    ///
    /// Must be called while GestureGraph's own AG is current (established by sendEvents
    /// via self.data.withCurrent). All session nodes live in GestureGraph's AG.
    ///
    /// Cross-graph isolation:
    ///   GestureFilter (ViewGraph context) snapshots plain Swift values into GestureResponder.
    ///   createSession (GestureGraph context) calls graph.makeInput(value: snapshot) to create
    ///   GestureGraph-local attrs that mirror the ViewGraph geometry without cross-graph refs.
    ///
    /// _GestureInputs.events uses the graph-level shared eventsAttr for all sessions.
    /// Per-session resetSeedAttr is kept for individual session teardown signalling.
    private func createSession(for responder: any AnyGestureResponder) -> ActiveGestureSession {
        guard let graph = AttributeGraph.current else {
            fatalError("GestureGraph.createSession: no active AttributeGraph context")
        }
        guard let sharedEventsAttr = eventsAttr else {
            fatalError("GestureGraph.createSession: eventsAttr not initialised - call sendEvents first")
        }
        guard let sharedInheritedPhaseAttr = inheritedPhaseAttr else {
            fatalError("GestureGraph.createSession: inheritedPhaseAttr not initialised - call sendEvents first")
        }

        let timeAttr = globalTimeAttr ?? {
            let t = graph.makeInput(value: Time(seconds: 0))
            globalTimeAttr = t
            return t
        }()

        // Build GestureGraph-local _ViewInputs.
        // transform and size: use cross-graph refs when the ViewGraph AG attributes are
        // available so that gesture coordinate nodes always reflect the latest ViewGraph
        // geometry (e.g. during animations). Fall back to snapshot copies otherwise.
        let sourceGraph = rendererHost?.viewGraph.data.graph
        var localViewInputs = responder.inputs
        if let tAttr = responder.transformAttr, let sAttr = responder.sizeAttr,
           let sourceGraph {
            localViewInputs.transform = graph.makeCrossGraphRef(source: tAttr, in: sourceGraph)
            localViewInputs.size      = graph.makeCrossGraphRef(source: sAttr, in: sourceGraph)
        } else {
            localViewInputs.transform = graph.makeInput(value: responder.snapshotTransform)
            localViewInputs.size      = graph.makeInput(value: responder.snapshotSize)
        }
        localViewInputs.base.time = timeAttr
        let localPreferenceKeysAttr: Attribute<PreferenceKeys> =
            graph.makeInput(value: responder.snapshotPreferenceKeys)

        // Reuse path: responder already has a built gesture chain and needsRebuild is false.
        // The responder's eventsAttr must match the current shared eventsAttr.
        if let cachedEventsAttr = responder.eventsAttr,
           cachedEventsAttr.identifier == sharedEventsAttr.identifier,
           let resetSeedAttr = responder.resetSeedAttr,
           let sub = responder.childSubgraph, !sub.nodes.isEmpty,
           !responder.needsRebuild {
            var gi = _GestureInputs(
                localViewInputs, viewSubgraph: nil,
                events: sharedEventsAttr, time: timeAttr,
                resetSeed: resetSeedAttr, inheritedPhase: sharedInheritedPhaseAttr,
                gesturePreferenceKeys: localPreferenceKeysAttr
            )
            gi.options = .gestureGraph
            let outputs = responder.makeGesture(inputs: gi)
            let isTerminalAttr: Attribute<Bool> = graph.makeRule {
                outputs.phase.value.isTerminal
            }
            return ActiveGestureSession(isTerminalAttr: isTerminalAttr, responder: responder)
        }

        // Build path: first session or modifier changed (needsRebuild).
        // Per-session resetSeedAttr is created fresh. makeWrappedGesture stores it on the responder.
        let perSessionResetSeedAttr: Attribute<UInt32> = graph.makeInput(value: UInt32(0))

        var gi = _GestureInputs(
            localViewInputs, viewSubgraph: nil,
            events: sharedEventsAttr, time: timeAttr,
            resetSeed: perSessionResetSeedAttr, inheritedPhase: sharedInheritedPhaseAttr,
            gesturePreferenceKeys: localPreferenceKeysAttr
        )
        gi.options = .gestureGraph

        // makeGesture calls makeWrappedGesture to build childSubgraph in GestureGraph's AG.
        // It caches sharedEventsAttr and perSessionResetSeedAttr on the responder.
        let outputs = responder.makeGesture(inputs: gi)
        let isTerminalAttr: Attribute<Bool> = graph.makeRule {
            outputs.phase.value.isTerminal
        }
        return ActiveGestureSession(isTerminalAttr: isTerminalAttr, responder: responder)
    }

    /// Tears down all sessions bound to `eventID` and removes their bindings.
    private func teardownSessions(for eventID: EventID) {
        guard let sessions = activeSessions.removeValue(forKey: eventID) else { return }
        for session in sessions { session.teardown() }
        eventBindingManager.bindings.removeValue(forKey: eventID)
        currentEvents.removeValue(forKey: eventID)
    }

    // MARK: - Event Dispatch

    /// Lazily initialises GestureGraph-level shared AG attributes inside data.withCurrent.
    /// Must be called at the top of the sendEvents entry point.
    private func ensureAttrsInitialised(time: Time) {
        guard let graph = AttributeGraph.current else {
            fatalError("GestureGraph.ensureAttrsInitialised: no AG context")
        }
        if eventsAttr == nil {
            eventsAttr = graph.makeInput(value: [:] as [EventID: any EventType])
        }
        if batchResetSeedAttr == nil {
            batchResetSeedAttr = graph.makeInput(value: UInt32(0))
        }
        if globalTimeAttr == nil {
            globalTimeAttr = graph.makeInput(value: time)
        }
        if inheritedPhaseAttr == nil {
            inheritedPhaseAttr = graph.makeInput(value: [] as _GestureInputs.InheritedPhase)
        }
        if phaseAttr == nil {
            phaseAttr = graph.makeInput(value: GesturePhase<Void>.possible(nil))
        }
    }

    /// Drains actions enqueued during AG evaluation.
    /// AG evaluation is synchronous here, so the loop only drains queued actions.
    private func runEventLoop() {
        for _ in 0..<8 {
            guard !pendingActions.isEmpty else { break }
            let actions = pendingActions
            pendingActions = []
            for action in actions { action() }
            // No explicit subgraph update is needed because synchronous evaluation already ran.
        }
    }

    /// Delivers `events` to the shared eventsAttr, triggering synchronous AG evaluation.
    private func publishEvents() {
        eventsAttr?.setValue(currentEvents)
    }

    // MARK: - EventGraphHost

    /// EventGraphHost.sendEvents: the graph-side event entry point.
    ///
    /// WindowController builds the [EventID: EventType] dictionary
    /// and calls this method. Session lifecycle (create / teardown) is driven by event phases
    /// in the dictionary. Mouse and gesture event types share the same entry point.
    ///
    /// Processing steps:
    ///   1. ensureAttrsInitialised
    ///   2. active flag = true
    ///   3. batchResetSeed += 1
    ///   4. time update
    ///   5. create sessions for new .began events (hit test + exclusion policy)
    ///   6. publish event dictionary
    ///   7. session lifecycle: teardown .ended/.cancelled, cleanup terminated
    ///   8. action drain
    @discardableResult
    func sendEvents(
        _ events: [EventID: any EventType],
        rootNode: ResponderNode,
        at time: Time
    ) -> GesturePhase<Void> {
        refreshResponderGeometrySnapshots()
        return data.withCurrent {
            // Drain cross-graph invalidations enqueued by ViewGraph since the last sendEvents.
            // Cross-graph ref nodes (e.g. transform, size mirrors) are marked dirty here so
            // that gesture coordinate nodes re-evaluate with the latest ViewGraph geometry.
            data.graph.inbox.drain()

            ensureAttrsInitialised(time: time)
            _isProcessingEvents = true
            defer { _isProcessingEvents = false }

            if let seed = batchResetSeedAttr { seed.setValue(seed.value &+ 1) }
            if let t = globalTimeAttr, !(t.value == time) { t.setValue(time) }

            // Create sessions for new events (.began phase, no existing session).
            // Sessions must be wired BEFORE publishing so gesture nodes are ready.
            for (eventID, event) in events where activeSessions[eventID] == nil {
                guard event.eventPhase == .began,
                      let location = event.location else { continue }
                let responders = hitTestResponders(at: location)
                    .filter { $0.accepts(eventType: eventID.type) }
                guard !responders.isEmpty else { continue }
                var sessions: [ActiveGestureSession] = []
                for responder in responders {
                    sessions.append(createSession(for: responder))
                }
                activeSessions[eventID] = sessions
                eventBindingManager.rebindEvent(eventID, to: rootResponder as ResponderNode?)
            }

            // Publish event dictionary to eventsAttr.
            currentEvents = events
            publishEvents()

            // Session lifecycle after publishing.
            // For .ended/.cancelled: evaluate gesture chain first so dispatch() fires
            // (e.g. action() for triggered gestures), THEN tear down sessions.
            // For .began/.moved: cleanup already-terminal sessions only.
            for eventID in events.keys {
                switch events[eventID]!.eventPhase {
                case .ended, .cancelled:
                    // Force AG evaluation before teardown so triggered gestures fire action().
                    // teardownSessions increments resetSeedAttr, which resets the chain.
                    // dispatch must run while the phase is still .ended/.triggered.
                    cleanupTerminatedSessions(for: eventID)
                    runEventLoop()
                    teardownSessions(for: eventID)
                default:
                    cleanupTerminatedSessions(for: eventID)
                }
            }

            runEventLoop()

            // Write aggregate phase to phaseAttr, then read back.
            let phase = aggregatePhase(for: events)
            phaseAttr?.setValue(phase)
            return phaseAttr?.value ?? phase
        }
    }

    private func refreshResponderGeometrySnapshots() {
        guard let viewGraph = rendererHost?.viewGraph,
              let rootResponder else { return }
        viewGraph.data.withCurrent {
            func refresh(_ responder: any ViewResponder) {
                if let gesture = responder as? any AnyGestureResponder,
                   let transformAttr = gesture.transformAttr,
                   let sizeAttr = gesture.sizeAttr {
                    gesture.snapshotTransform = transformAttr.value
                    gesture.snapshotSize = sizeAttr.value
                }
                if let multi = responder as? MultiViewResponder {
                    for child in multi.responders {
                        refresh(child)
                    }
                }
            }
            for responder in rootResponder.responders {
                refresh(responder)
            }
        }
    }

    /// Returns hit responders at a given point, filtered by exclusion policy.
    ///
    /// .simultaneous(.global): always included alongside any other policy.
    /// .simultaneous(.descendants/.ancestors): included only when the hierarchy relationship
    ///   is satisfied with at least one other hit responder (via isDescendant chain).
    private func hitTestResponders(at location: CGPoint) -> [any AnyGestureResponder] {
        guard let rootResponder else { return [] }
        let hits = rootResponder.respondersContaining(point: location)
            .compactMap { $0 as? any AnyGestureResponder }
            .filter { $0.mask.contains(.gesture) }
        guard !hits.isEmpty else { return [] }
        let hasHighPriority = hits.contains { $0.exclusionPolicy == .highPriority }
        var result: [any AnyGestureResponder] = []
        var sawDefault = false
        for responder in hits {
            switch responder.exclusionPolicy {
            case .highPriority:
                result.append(responder)
            case .default:
                if !hasHighPriority && !sawDefault {
                    result.append(responder)
                    sawDefault = true
                }
            case .simultaneous(let constraint):
                let include: Bool
                switch constraint {
                case .global:
                    include = true
                case .descendants, .ancestors:
                    // Include if any other hit responder considers itself simultaneous with this one.
                    // isSimultaneous is asymmetric: child.isSim(parent)=true, parent.isSim(child)=false.
                    include = hits.contains { other in
                        other !== responder && other.isSimultaneous(with: responder)
                    }
                }
                if include { result.append(responder) }
            }
        }
        return result
    }

    /// Computes the aggregate GesturePhase for the current batch.
    private func aggregatePhase(for events: [EventID: any EventType]) -> GesturePhase<Void> {
        let hasTerminal = events.values.contains {
            $0.eventPhase == .ended || $0.eventPhase == .cancelled
        }
        if hasTerminal { return .ended(()) }
        if activeSessions.isEmpty { return .possible(nil) }
        return .active(())
    }

    /// Removes sessions whose gesture phase has become terminal.
    private func cleanupTerminatedSessions(for eventID: EventID) {
        guard var sessions = activeSessions[eventID] else { return }
        let before = sessions.count
        sessions = sessions.filter { session in
            if session.isTerminal {
                session.teardown()
                return false
            }
            return true
        }
        if sessions.isEmpty {
            activeSessions.removeValue(forKey: eventID)
            eventBindingManager.bindings.removeValue(forKey: eventID)
            currentEvents.removeValue(forKey: eventID)
        } else if sessions.count != before {
            activeSessions[eventID] = sessions
        }
    }

    func resetEvents() {
        // Tear down sessions explicitly, then nil all lazy AG attrs so they are
        // recreated fresh on the next sendEvents call.
        data.withCurrent {
            for sessions in activeSessions.values {
                for session in sessions { session.teardown() }
            }
            rootResponder?.resetGesture()
        }
        activeSessions.removeAll()
        eventBindingManager.bindings.removeAll()
        currentEvents.removeAll()
        eventsAttr = nil
        batchResetSeedAttr = nil
        globalTimeAttr = nil
        inheritedPhaseAttr = nil
        phaseAttr = nil
    }

    func instantiateOutputs() {
        // Called when the window becomes active and connects indirect outputs.
    }

    func uninstantiateOutputs() {
        // Called when the window deactivates.
    }

    func timeDidChange() {
        // Notifies gesture recognizers that time has advanced.
    }

    /// Enqueues an action to be drained by the event loop.
    /// During sendEvents (_isProcessingEvents == true), actions are appended to
    /// pendingActions and drained in runEventLoop.
    /// Outside of event processing, falls back to delegate or DispatchQueue.main.
    func enqueueAction(_ action: @escaping () -> Void) {
        if _isProcessingEvents {
            pendingActions.append(action)
        } else if let d = delegate {
            d.enqueueAction(action)
        } else {
            // Fallback: defer to outbox, drained by WindowController after AG evaluation.
            data.graph.actionOutbox.append(action)
        }
    }

    /// Enqueues an action ahead of ordinary gesture callbacks for the same event turn.
    ///
    /// Gesture-state terminal cleanup must run before terminal callbacks observe the
    /// state. This preserves ordinary callback append ordering while giving cleanup
    /// work a deterministic earlier drain slot.
    func enqueueActionBeforeCallbacks(_ action: @escaping () -> Void) {
        if _isProcessingEvents {
            pendingActions.insert(action, at: 0)
        } else if delegate != nil {
            enqueueAction(action)
        } else {
            data.graph.actionOutbox.insert(action, at: 0)
        }
    }

    func gestureCategory() -> GestureCategory? { nil }

    func isAutoScrollEnabled() -> Bool { false }

    // ViewRespondersKey update

    /// Called when the ViewRespondersKey preference value changes at the root.
    func updateResponders(_ responders: [any ViewResponder]) {
        rootResponder?.updateChildren((value: responders, changed: true))
    }
}

// _PrimitiveGestureTypes (compatibility shim, now maps to GestureMask internally)

/// Bitmask of primitive gesture recognizer types.
/// Used internally by recognizers to filter which events they handle.
struct _PrimitiveGestureTypes: OptionSet {
    let rawValue: UInt
    static let tap              = Self(rawValue: 1 << 0)
    static let longPress        = Self(rawValue: 1 << 1)
    static let drag             = Self(rawValue: 1 << 2)
    static let magnification    = Self(rawValue: 1 << 3)
    static let rotation         = Self(rawValue: 1 << 4)
    static let rotation3D       = Self(rawValue: 1 << 5)
    static let button           = Self(rawValue: 1 << 6)

    static let all = Self(rawValue: .max)
    static let none: Self = []
}
