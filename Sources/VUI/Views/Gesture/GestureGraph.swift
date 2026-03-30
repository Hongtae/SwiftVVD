//
//  File: GestureGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

// GestureCategory

/// Classifies the primary gesture type active in a gesture graph.
struct GestureCategory: RawRepresentable, Equatable, Sendable {
    var rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let drag     = GestureCategory(rawValue: 1 << 0)
    static let rotate   = GestureCategory(rawValue: 1 << 1)
    static let magnify  = GestureCategory(rawValue: 1 << 2)
    static let select   = GestureCategory(rawValue: 1 << 3)
    static let longPress = GestureCategory(rawValue: 1 << 4)
    static let windowDrag = GestureCategory(rawValue: 1 << 5)
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

/// Manages the mapping from EventID → EventBinding (which responder owns which event stream).
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
}

// GestureGraphDelegate

/// Protocol adopted by the entity that drives the gesture graph lifecycle
/// (typically the WindowController's event bridge).
protocol GestureGraphDelegate: AnyObject {
    func enqueueAction(_ action: @escaping @Sendable () -> Void)
}

// GestureGraph

/// Manages the entire gesture processing pipeline for a single window/view-graph.
///
/// Responsibilities:
/// - Owns the `eventsAttribute: Attribute<[EventID: any EventType]>` input node that
///   drives all gesture rules in the AG graph.
/// - Performs hit testing via `MultiViewResponder` to determine which `ViewResponder`
///   receives each event stream.
/// - Dispatches events to matched responders and updates the event bindings.
class GestureGraph: @unchecked Sendable {

    // TaskLocal current

    @TaskLocal static var _current: GestureGraph? = nil

    /// The currently active gesture graph for the running `_makeView` pass.
    /// Fatal if accessed outside a view layout pass that set up the gesture graph.
    static var current: GestureGraph {
        guard let g = _current else {
            fatalError("GestureGraph.current accessed outside a gesture-enabled layout pass")
        }
        return g
    }

    // State

    var responderNode: ResponderNode?
    var focusedResponder: ResponderNode?
    var delegate: GestureGraphDelegate?
    var nextGestureUpdateTime: Time = .zero

    let eventBindingManager: EventBindingManager

    /// The root multi-view responder that aggregates all ViewResponders from the view tree.
    let rootResponder: MultiViewResponder

    // Active gesture sessions
    // Each EventID maps to a list of sessions (one per hit responder).
    var activeSessions: [EventID: [ActiveGestureSession]] = [:]

    // Serial counter for EventID assignment
    private let _nextSerial: Mutex<Int> = Mutex(1)

    func nextSerial() -> Int {
        _nextSerial.withLock { s in
            defer { s += 1 }
            return s
        }
    }

    // Init

    public init() {
        self.rootResponder = MultiViewResponder()
        self.eventBindingManager = EventBindingManager()
        self.eventBindingManager.rootResponder = rootResponder
    }

    // Session Management

    /// Creates an `ActiveGestureSession` for a hit responder.
    ///
    /// Must be called inside an active `AttributeGraph.$current` context.
    /// All AG nodes created by `_makeGesture` are registered to the session's subgraph.
    private func createSession(
        for responder: any AnyGestureResponder,
        in graph: AttributeGraph
    ) -> ActiveGestureSession {
        // Create a standalone subgraph (no parent — managed by GestureGraph directly)
        let subgraph = Subgraph()
        let viewInputs = responder.inputs

        let (eventsAttr, isTerminalAttr) = Subgraph.$current.withValue(subgraph) {
            let eventsAttr: Attribute<[EventID: any EventType]> = graph.makeInput(value: [:])
            let resetSeedAttr: Attribute<UInt32> = graph.makeInput(value: UInt32(0))
            let inheritedPhaseAttr: Attribute<_GestureInputs.InheritedPhase> =
                graph.makeInput(value: [])

            let gestureInputs = _GestureInputs(
                viewInputs,
                viewSubgraph: nil,
                events: eventsAttr,
                time: viewInputs.base.time,
                resetSeed: resetSeedAttr,
                inheritedPhase: inheritedPhaseAttr,
                gesturePreferenceKeys: viewInputs.preferences.hostKeys
            )
            // Signal that this _makeGesture call is running inside the GestureGraph dispatch pipeline.
            var gestureInputsWithFlags = gestureInputs
            gestureInputsWithFlags.options = .gestureGraph

            let outputs = responder.makeGesture(inputs: gestureInputsWithFlags)
            let isTerminalAttr: Attribute<Bool> = graph.makeRule {
                outputs.phase.value.isTerminal
            }

            return (eventsAttr, isTerminalAttr)
        }

        return ActiveGestureSession(
            subgraph: subgraph,
            eventsAttr: eventsAttr,
            isTerminalAttr: isTerminalAttr,
            responder: responder
        )
    }

    /// Tears down all sessions bound to `eventID` and removes their bindings.
    private func teardownSessions(for eventID: EventID) {
        guard let sessions = activeSessions.removeValue(forKey: eventID) else { return }
        for session in sessions { session.teardown() }
        eventBindingManager.bindings.removeValue(forKey: eventID)
    }

    // Event Dispatch

    /// Processes a platform mouse event using the session model:
    ///
    ///   .buttonDown  → hit test → create one ActiveGestureSession per hit responder →
    ///                  feed initial event → check terminal
    ///   .move        → feed event to all bound sessions → check terminal
    ///   .buttonUp    → feed ended event → check terminal → tear down
    ///
    /// All gesture AG rules fire synchronously inside `eventsAttr.setValue`, so
    /// session terminal state is accurate immediately after each setValue call.
    @discardableResult
    func sendMouseEvent(
        _ event: MouseEvent,
        in graph: AttributeGraph
    ) -> GesturePhase<Void> {
        assert(AttributeGraph.current != nil, "GestureGraph.sendMouseEvent requires AG context")

        switch event.type {
        case .buttonDown:
            // Hit test: find all GestureResponders that contain the touch point.
            // Results are in child-first order (ViewRespondersKey.reduce appends leaves before root).
            let hitResponders = rootResponder.respondersContaining(point: event.location)
                .compactMap { $0 as? any AnyGestureResponder }
                .filter { $0.mask.contains(.gesture) }
            guard !hitResponders.isEmpty else { return .failed }

            // --- GestureResponderExclusionPolicy filtering ---
            //
            //  .highPriority    — always creates a session; suppresses all .default sessions
            //  .default         — only the first (child-most) gets a session,
            //                     cancelled entirely when a .highPriority responder is hit
            //  .simultaneous(*) — always creates a session, coexists with all others
            let hasHighPriority = hitResponders.contains { $0.exclusionPolicy == .highPriority }
            var activeResponders: [any AnyGestureResponder] = []
            var sawDefault = false
            for responder in hitResponders {
                switch responder.exclusionPolicy {
                case .highPriority:
                    activeResponders.append(responder)
                case .default:
                    if !hasHighPriority && !sawDefault {
                        activeResponders.append(responder)
                        sawDefault = true
                    }
                case .simultaneous:
                    activeResponders.append(responder)
                }
            }
            guard !activeResponders.isEmpty else { return .failed }

            let serial = nextSerial()
            let eventID = EventID(type: TappableEvent.self, serial: serial)
            let initialEvent = TappableEvent(location: event.location, phase: .began, buttonID: event.buttonID)

            // Create one session per active responder.
            var sessions: [ActiveGestureSession] = []
            for responder in activeResponders {
                let session = createSession(for: responder, in: graph)
                sessions.append(session)
            }
            activeSessions[eventID] = sessions

            // Bind the event for future move/up routing.
            eventBindingManager.rebindEvent(eventID, to: rootResponder)

            // Feed the initial began event to all sessions.
            let events: [EventID: any EventType] = [eventID: initialEvent]
            for session in sessions {
                session.eventsAttr.setValue(events)
            }

            // Tear down sessions that already terminated (e.g., instant failure).
            cleanupTerminatedSessions(for: eventID)

            return activeSessions[eventID] != nil ? .active(()) : .failed

        case .move:
            if activeSessions.isEmpty { return .possible(nil) }
            let movedEvent = TappableEvent(location: event.location, phase: .moved, buttonID: event.buttonID)
            for (eventID, sessions) in activeSessions {
                let events: [EventID: any EventType] = [eventID: movedEvent]
                for session in sessions { session.eventsAttr.setValue(events) }
                cleanupTerminatedSessions(for: eventID)
            }
            return activeSessions.isEmpty ? .possible(nil) : .active(())

        case .buttonUp:
            if activeSessions.isEmpty { return .possible(nil) }
            var anyEnded = false
            for eventID in Array(activeSessions.keys) {
                let endedEvent = TappableEvent(location: event.location, phase: .ended, buttonID: event.buttonID)
                let events: [EventID: any EventType] = [eventID: endedEvent]
                if let sessions = activeSessions[eventID] {
                    for session in sessions { session.eventsAttr.setValue(events) }
                    anyEnded = true
                }
                teardownSessions(for: eventID)
            }
            return anyEnded ? .ended(()) : .failed

        default:
            return .failed
        }
    }

    /// Removes sessions whose gesture phase has become terminal and tears them down.
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
        } else if sessions.count != before {
            activeSessions[eventID] = sessions
        }
    }

    func resetEvents() {
        // Tear down all active sessions and clear bindings.
        for sessions in activeSessions.values {
            for session in sessions { session.teardown() }
        }
        activeSessions.removeAll()
        eventBindingManager.bindings.removeAll()
    }

    func instantiateOutputs() {
        // Called when the window becomes active — connects indirect outputs.
    }

    func uninstantiateOutputs() {
        // Called when the window deactivates.
    }

    func timeDidChange() {
        // Notifies gesture recognizers that time has advanced.
    }

    func enqueueAction(_ action: @escaping @Sendable () -> Void) {
        if let d = delegate {
            d.enqueueAction(action)
        } else {
            DispatchQueue.main.async { action() }
        }
    }

    func gestureCategory() -> GestureCategory? { nil }

    func isAutoScrollEnabled() -> Bool { false }

    // ViewRespondersKey update

    /// Called when the ViewRespondersKey preference value changes at the root.
    func updateResponders(_ responders: [any ViewResponder]) {
        rootResponder.updateChildren((value: responders, changed: true))
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
