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

    // AG Attributes (owned by this GestureGraph)

    /// Source-of-truth attribute for the current event dictionary.
    /// Updated by the WindowController each time platform events are converted.
    private(set) var eventsAttribute: Attribute<[EventID: any EventType]>!

    /// Source-of-truth for the gesture reset seed. Incrementing forces all
    /// gesture recognizers in the tree to reset their state.
    private(set) var resetSeedAttribute: Attribute<UInt32>!

    /// Source-of-truth for inherited phase (initial value = .active).
    private(set) var inheritedPhaseAttribute: Attribute<_GestureInputs.InheritedPhase>!

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

    /// Called once by `WindowController.init` inside the AG graph context to create
    /// the input attributes that drive the gesture system.
    func setupAttributes(in graph: AttributeGraph) {
        assert(eventsAttribute == nil, "GestureGraph.setupAttributes called twice")
        eventsAttribute = graph.makeInput(value: [:] as [EventID: any EventType])
        resetSeedAttribute = graph.makeInput(value: UInt32(0))
        inheritedPhaseAttribute = graph.makeInput(value: _GestureInputs.InheritedPhase.active)
    }

    // Event Dispatch

    /// Converts a platform mouse event to the event dictionary format and dispatches.
    ///
    /// - Returns: the combined gesture phase after processing (`.failed` if nothing was hit).
    @discardableResult
    func sendMouseEvent(
        _ event: MouseEvent,
        in graph: AttributeGraph
    ) -> GesturePhase<Void> {
        guard let eventsAttr = eventsAttribute else { return .failed }

        var events: [EventID: any EventType] = [:]

        switch event.type {
        case .buttonDown:
            let serial = nextSerial()
            let eventID = EventID(type: TappableEvent.self, serial: serial)
            let tappable = TappableEvent(location: event.location, phase: .began, buttonID: event.buttonID)
            events[eventID] = tappable

            // Hit test to find which responders to bind this event to
            let hit = rootResponder.respondersContaining(point: event.location)
            if hit.isEmpty { return .failed }
            // Bind all hit responders to this event
            for responder in hit {
                if let node = responder.nextResponder {
                    eventBindingManager.rebindEvent(eventID, to: node)
                }
            }

        case .buttonUp:
            // End all active bindings with a tap-ended event
            for (id, binding) in eventBindingManager.bindings {
                let tappable = TappableEvent(location: event.location, phase: .ended, buttonID: event.buttonID)
                events[id] = tappable
                _ = binding
            }
            eventBindingManager.bindings.removeAll()

        case .move:
            // Forward move to all active bindings
            for (id, _) in eventBindingManager.bindings {
                let tappable = TappableEvent(location: event.location, phase: .moved, buttonID: event.buttonID)
                events[id] = tappable
            }

        default:
            return .failed
        }

        if events.isEmpty { return .possible(nil) }

        // Update the events attribute — AG will propagate to all dependent gesture rules
        eventsAttr.setValue(events)

        return .active(())
    }

    func resetEvents() {
        eventsAttribute?.setValue([:])
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
