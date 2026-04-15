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

/// Internal event wrapper used when bridging platform events into the gesture pipeline.
/// Kept separate from EventGraphHost.sendEvents, which accepts event dictionaries.
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

/// Manages the mapping from EventID to EventBinding.
/// When a new touch/click begins, `rebindEvent` routes subsequent events for that ID
/// to the responder that won the hit test.
class EventBindingManager {
    var bindings: [EventID: EventBinding] = [:]
    var rootResponder: ResponderNode?
    var focusedResponder: ResponderNode?

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

    /// Routes a pre-computed event dictionary downstream to the appropriate EventGraphHost.
    ///
    /// EventBindingBridge is not implemented yet, so host is passed directly.
    /// Remove the host parameter once EventBindingBridge is available.
    @discardableResult
    func sendDownstream(
        _ events: [EventID: any EventType],
        host: any EventGraphHost,
        at time: Time
    ) -> GesturePhase<Void> {
        guard let rootNode = rootResponder else { return .possible(nil) }
        return host.sendEvents(events, rootNode: rootNode, at: time)
    }
}

// GestureGraphDelegate

/// Protocol adopted by the entity that drives the gesture graph lifecycle
/// (typically the WindowController's event bridge).
protocol GestureGraphDelegate: AnyObject {
    func enqueueAction(_ action: @escaping () -> Void)
}

// EventGraphHost
/// Protocol for objects that own an EventBindingManager and can receive event streams.
///
/// Provides the minimal host interface needed for gesture event routing.
/// Platform-specific hooks have default no-op / false implementations.
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
    /// Default implementation returns false when no platform hierarchy is available.
    func isDescendant(of host: AnyObject) -> Bool

    /// Notifies the host that a platform event was consumed.
    /// Default implementation is a no-op when platform event passthrough is unavailable.
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
/// - Owns an independent `AttributeGraph` (NOT shared with ViewGraph).
/// - Performs hit testing via `MultiViewResponder` to determine which `ViewResponder`
///   receives each event stream.
/// - Dispatches events to matched responders and manages `ActiveGestureSession` lifecycles.
/// GestureFilter nodes live in ViewGraph's AG. GestureGraph.current resolves via
/// the active AttributeGraphRef context when GestureGraph's own AG is evaluated.
class GestureGraph: GraphHost, EventGraphHost, @unchecked Sendable {

    // current resolves the active GestureGraph from the AG evaluation context
    // reads AttributeGraphRef.current?.context (set by data.withCurrent).
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
    ///
    /// Injected externally in GestureGraph.init(rootResponder:); lifetime managed by caller.
    ///
    /// _ownedRootResponder keeps a local fallback owner. When used with WindowController, ownership should
    /// transfer to WindowController; currently held internally by GestureGraph pending migration.
    private var _ownedRootResponder: MultiViewResponder  // currently owned by GestureGraph
    weak var rootResponder: MultiViewResponder?

    /// Back-reference to the owning ViewRendererHost (WindowController).
    /// Session nodes live in ViewGraph's AG (accessed via rendererHost.viewGraph).
    /// Set by WindowController.init immediately after creating GestureGraph.
    weak var rendererHost: (any ViewRendererHost)?

    // active gesture sessions, one list per hit EventID
    var activeSessions: [EventID: [ActiveGestureSession]] = [:]

    // GestureGraph-level shared event dictionary attribute.
    // All EventListenerPhase nodes across all sessions read from this single attr.
    // Per-session eventsAttr is replaced by this single shared attr.
    var eventsAttr: Attribute<[EventID: any EventType]>?

    // Per-batch reset seed, incremented once per sendEvents call.
    // Different from per-responder resetSeed (used for individual session teardown).
    var batchResetSeedAttr: Attribute<UInt32>?

    // Active flag, true while sendEvents is processing events.
    // Prevents re-entrant sendEvents and gates enqueueAction to the internal queue.
    private var _isProcessingEvents: Bool = false

    // Action queue. Actions enqueued during AG evaluation are drained between
    // SubgraphUpdate iterations.
    var pendingActions: [() -> Void] = []

    // current event state last published to eventsAttr
    // set from sendEvents and cleared by teardownSessions
    var currentEvents: [EventID: any EventType] = [:]

    // GestureGraph-local time attribute.
    // Created lazily inside GestureGraph's AG context on the first event call.
    var globalTimeAttr: Attribute<Time>?

    // root inherited-phase input shared by all sessions
    // created alongside eventsAttr in ensureAttrsInitialised
    // initial value = [] (= .failed = all gestures may proceed)
    var inheritedPhaseAttr: Attribute<_GestureInputs.InheritedPhase>?

    // aggregate GesturePhase of the current event batch
    // written after session lifecycle changes in sendEvents and read as the return value
    var phaseAttr: Attribute<GesturePhase<Void>>?

    // Init
    /// Creates a GestureGraph with its own independent AttributeGraph.
    override init() {
        let mvr = MultiViewResponder()
        self._ownedRootResponder = mvr
        self.eventBindingManager = EventBindingManager()
        super.init()
        self.rootResponder = mvr
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
    /// _GestureInputs.events uses the shared eventsAttr across all sessions.
    /// Per-session resetSeedAttr is kept for individual session teardown signalling.
    private func createSession(for responder: any AnyGestureResponder) -> ActiveGestureSession {
        guard let graph = AttributeGraph.current else {
            fatalError("GestureGraph.createSession: no active AttributeGraph context")
        }
        guard let sharedEventsAttr = eventsAttr else {
            fatalError("GestureGraph.createSession: eventsAttr not initialised. Call sendEvents first.")
        }
        guard let sharedInheritedPhaseAttr = inheritedPhaseAttr else {
            fatalError("GestureGraph.createSession: inheritedPhaseAttr not initialised. Call sendEvents first.")
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
        // eventsAttr on the responder must match the current shared eventsAttr.
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
        // Per-session resetSeedAttr is created fresh; makeWrappedGesture stores it on the responder.
        let perSessionResetSeedAttr: Attribute<UInt32> = graph.makeInput(value: UInt32(0))

        var gi = _GestureInputs(
            localViewInputs, viewSubgraph: nil,
            events: sharedEventsAttr, time: timeAttr,
            resetSeed: perSessionResetSeedAttr, inheritedPhase: sharedInheritedPhaseAttr,
            gesturePreferenceKeys: localPreferenceKeysAttr
        )
        gi.options = .gestureGraph

        // makeGesture -> makeWrappedGesture builds childSubgraph in GestureGraph's AG
        // and caches sharedEventsAttr and perSessionResetSeedAttr on the responder
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
    /// Must be called at the top of every sendEvents / sendMouseEvent entry point.
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

    /// Drains actions queued during gesture AG evaluation.
    ///
    /// AG evaluation is synchronous after setValue, so this loop exists only to drain
    /// actions enqueued while rules were evaluating.
    private func runEventLoop() {
        for _ in 0..<8 {
            guard !pendingActions.isEmpty else { break }
            let actions = pendingActions
            pendingActions = []
            for action in actions { action() }
            // no explicit subgraph update is needed because synchronous evaluation already ran
        }
    }

    /// Delivers `events` to the shared eventsAttr, triggering synchronous AG evaluation.
    private func publishEvents() {
        eventsAttr?.setValue(currentEvents)
    }

    // MARK: - EventGraphHost

    /// EventGraphHost.sendEvents is the sole event entry point.
    ///
    /// WindowController builds the [EventID: EventType] dictionary and calls this method.
    /// Session lifecycle is driven by event phases in the dictionary, so no separate
    /// sendMouseEvent / sendGestureEvent entry point is needed.
    ///
    /// Flow:
    ///   1. ensureAttrsInitialised
    ///   2. active flag = true
    ///   3. batchResetSeed += 1
    ///   4. time update
    ///   5. create sessions for new .began events (hit test + exclusion policy)
    ///   6. publish event dictionary
    ///   7. session lifecycle: teardown .ended/.cancelled, cleanup terminated
    ///   8. drain queued actions
    @discardableResult
    func sendEvents(
        _ events: [EventID: any EventType],
        rootNode: ResponderNode,
        at time: Time
    ) -> GesturePhase<Void> {
        data.withCurrent {
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
                    // teardownSessions increments resetSeedAttr which resets the chain;
                    // dispatch must run while the phase is still .ended/.triggered.
                    cleanupTerminatedSessions(for: eventID)
                    runEventLoop()
                    teardownSessions(for: eventID)
                default:
                    cleanupTerminatedSessions(for: eventID)
                }
            }

            runEventLoop()

            // write aggregate phase to phaseAttr, then read back
            let phase = aggregatePhase(for: events)
            phaseAttr?.setValue(phase)
            return phaseAttr?.value ?? phase
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
                    // check from the other responder's perspective
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
            if session.isTerminal { session.teardown(); return false }
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
        // tear down sessions explicitly, then nil all lazy AG attrs so they are
        // recreated fresh on the next sendEvents call
        for sessions in activeSessions.values {
            for session in sessions { session.teardown() }
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
        // called when the window becomes active and connects indirect outputs
    }

    func uninstantiateOutputs() {
        // called when the window deactivates
    }

    func timeDidChange() {
        // notifies gesture recognizers that time has advanced
    }

    /// Enqueues an action to be drained by the event loop.
    ///
    /// During sendEvents (_isProcessingEvents == true), actions are appended to
    /// pendingActions and drained in runEventLoop.
    /// Outside of event processing, falls back to delegate or DispatchQueue.main.
    func enqueueAction(_ action: @escaping () -> Void) {
        if _isProcessingEvents {
            pendingActions.append(action)
        } else if let d = delegate {
            d.enqueueAction(action)
        } else {
            // fallback: defer to outbox, drained by WindowController after AG evaluation
            data.graph.actionOutbox.append(action)
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
