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
    var mouseEvent: PlatformMouseEvent
    var time: Time

    init(_ mouseEvent: PlatformMouseEvent, at time: Time = Time(seconds: 0)) {
        self.mouseEvent = mouseEvent
        self.time = time
    }
}

// GestureCategory

/// Classifies the primary gesture type active in a gesture graph.
struct GestureCategory: OptionSet, Defaultable, Sendable {
    var rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let magnify    = GestureCategory(rawValue: 1)   // bit 0
    static let rotate     = GestureCategory(rawValue: 2)   // bit 1
    static let drag       = GestureCategory(rawValue: 4)   // bit 2
    static let select     = GestureCategory(rawValue: 8)   // bit 3
    static let longPress  = GestureCategory(rawValue: 16)  // bit 4
    static let windowDrag = GestureCategory(rawValue: 32)  // bit 5

    static var defaultValue: GestureCategory { [] }

    struct Key: PreferenceKey {
        static var defaultValue: GestureCategory { [] }
        static var _includesRemovedValues: Bool { true }

        static func reduce(
            value: inout GestureCategory,
            nextValue: () -> GestureCategory
        ) {
            value.formUnion(nextValue())
        }
    }
}

struct GestureLabelKey: PreferenceKey {
    static var defaultValue: String? { nil }

    static func reduce(value: inout String?, nextValue: () -> String?) {
        if value == nil {
            value = nextValue()
        }
    }
}

struct IsCancellableGestureKey: PreferenceKey {
    static var defaultValue: Bool { false }

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct ScrollViewDragAutoScrollKey: PreferenceKey {
    static var defaultValue: Bool { false }

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// EventBinding / EventBindingManager

/// Receives backend events at a responder-owned platform boundary without
/// materializing a view gesture around that boundary.
protocol ResponderEventConsumer: AnyObject {
    func acceptsEventType(_ eventType: Any.Type) -> Bool
    func consumeEvents(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> GesturePhase<Void>
}

protocol GestureArbitratingEventConsumer: ResponderEventConsumer
where Self: ViewResponder {
    func isPrevented(by responder: any AnyGestureResponder) -> Bool
    func preventRecognition(for events: [EventID: any EventType])
    func cancels(_ responder: any AnyGestureResponder) -> Bool
}

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

protocol ForwardedEventDispatcher {
    static var eventType: any EventType.Type { get }
    var isActive: Bool { get }

    func wantsEvent(
        _ event: any EventType,
        manager: EventBindingManager
    ) -> Bool

    mutating func receiveEvents(
        _ events: [EventID: any EventType],
        manager: EventBindingManager
    ) -> Set<EventID>

    mutating func reset()
}

extension ForwardedEventDispatcher {
    var isActive: Bool { false }

    func wantsEvent(
        _ event: any EventType,
        manager: EventBindingManager
    ) -> Bool {
        true
    }

    mutating func reset() {}
}

/// Manages the mapping from EventID to EventBinding (which responder owns which event stream).
/// When a new touch/click begins, `rebindEvent` routes subsequent events for that ID
/// to the responder that won the hit test.
class EventBindingManager {
    private var forwardedEventDispatchers:
        [ObjectIdentifier: any ForwardedEventDispatcher] = [:]
    var bindings: [EventID: EventBinding] = [:]
    weak var host: (any EventGraphHost)?
    weak var delegate: (any EventBindingManagerDelegate)?
    var rootResponder: ResponderNode?
    var focusedResponder: ResponderNode?
    private var isActive = false
    private var hoverUpdatePending = false
    private let lock = Mutex(())

    static var current: EventBindingManager? {
        guard let viewGraph = GraphHost.currentHost as? ViewGraph,
              let rendererHost = viewGraph.rendererHost else {
            return nil
        }
        if let eventGraphHost = rendererHost as? any EventGraphHost {
            return eventGraphHost.eventBindingManager
        }
        return (rendererHost as? WindowController)?
            .gestureGraph?
            .eventBindingManager
    }

    init() {}

    func addForwardedEventDispatcher(
        _ dispatcher: any ForwardedEventDispatcher
    ) {
        let eventType = type(of: dispatcher).eventType
        forwardedEventDispatchers[ObjectIdentifier(eventType)] = dispatcher
    }

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
    ) -> Set<EventID> {
        withDispatchScope {
            var consumed = dispatchNonGestureEvents(events)
            let downstreamEvents = events.filter {
                forwardedEventDispatchers[
                    ObjectIdentifier(type(of: $0.value))
                ] == nil
            }
            let phase = sendDownstreamBody(
                downstreamEvents,
                bridge: nil,
                at: time
            )
            if phase.isActive || phase.isEnded {
                consumed.formUnion(downstreamEvents.keys)
            }
            return consumed
        }
    }

    private func dispatchNonGestureEvents(
        _ events: [EventID: any EventType]
    ) -> Set<EventID> {
        var consumed: Set<EventID> = []
        for key in Array(forwardedEventDispatchers.keys) {
            guard var dispatcher = forwardedEventDispatchers[key] else {
                continue
            }
            let eventType = type(of: dispatcher).eventType
            let forwardedEvents = events.filter {
                ObjectIdentifier(type(of: $0.value)) ==
                    ObjectIdentifier(eventType)
            }
            guard !forwardedEvents.isEmpty else { continue }
            consumed.formUnion(dispatcher.receiveEvents(
                forwardedEvents,
                manager: self
            ))
            forwardedEventDispatchers[key] = dispatcher
        }
        return consumed
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
        let callback: (any EventBindingManagerDelegate)? = bridge ?? delegate
        var boundEvents: [EventID: any EventType] = [:]
        var terminalEventIDs: [EventID] = []

        for (eventID, sourceEvent) in events {
            var event = sourceEvent
            let binding: EventBinding
            if let existingBinding = bindings[eventID] {
                binding = existingBinding
            } else {
                let responder: ResponderNode?
                if event.isFocusEvent,
                   let focusedResponder = focusedResponder ?? host.focusedResponder {
                    responder = focusedResponder.bindEvent(event)
                } else {
                    responder = rootNode.bindEvent(event)
                }
                guard let responder else { continue }
                binding = EventBinding(responder: responder)
                bindings[eventID] = binding
                isActive = true
                callback?.didBind(to: binding, id: eventID)
            }

            event.binding = binding
            bindings[eventID] = binding
            boundEvents[eventID] = event
            if event.phase.isTerminal {
                terminalEventIDs.append(eventID)
            }
        }

        guard isActive else { return .possible(nil) }
        let phase = host.sendEvents(boundEvents, rootNode: rootNode, at: time)
        callback?.didUpdate(phase: phase, in: self)
        if let category = host.gestureCategory() {
            callback?.didUpdate(gestureCategory: category, in: self)
        }

        for eventID in terminalEventIDs {
            bindings.removeValue(forKey: eventID)
        }
        if bindings.isEmpty {
            isActive = false
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

    func reset(resetForwardedEventDispatchers: Bool = false) {
        if resetForwardedEventDispatchers {
            for key in Array(forwardedEventDispatchers.keys) {
                guard var dispatcher = forwardedEventDispatchers[key] else {
                    continue
                }
                dispatcher.reset()
                forwardedEventDispatchers[key] = dispatcher
            }
        }
        bindings.removeAll()
        isActive = false
        hoverUpdatePending = false
        // Tear down outputs after the current event callbacks have drained.
        Update.enqueueAction { [weak host] in
            host?.resetEvents()
        }
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
    func attach(to bridge: EventBindingBridge)
    func `as`<T>(_ type: T.Type) -> T?
    func didUpdate(phase: GesturePhase<Void>, in bridge: EventBindingBridge)
    func didUpdate(gestureCategory: GestureCategory, in bridge: EventBindingBridge)
    func didBind(to binding: EventBinding, id: EventID, in bridge: EventBindingBridge)
    func didRequestHoverUpdate(in bridge: EventBindingBridge)
}

extension EventBindingSource {
    func `as`<T>(_ type: T.Type) -> T? { self as? T }
    func didUpdate(phase: GesturePhase<Void>, in bridge: EventBindingBridge) {}
    func didUpdate(gestureCategory: GestureCategory, in bridge: EventBindingBridge) {}
    func didBind(to binding: EventBinding, id: EventID, in bridge: EventBindingBridge) {}
    func didRequestHoverUpdate(in bridge: EventBindingBridge) {}
}

protocol EventBindingManagerDelegate: AnyObject {
    func didBind(to binding: EventBinding, id: EventID)
    func didUpdate(phase: GesturePhase<Void>, in manager: EventBindingManager)
    func didUpdate(gestureCategory: GestureCategory, in manager: EventBindingManager)
    func requestHoverUpdate(in manager: EventBindingManager)
}

extension EventBindingManagerDelegate {
    func didBind(to binding: EventBinding, id: EventID) {}
    func didUpdate(gestureCategory: GestureCategory, in manager: EventBindingManager) {}
    func requestHoverUpdate(in manager: EventBindingManager) {}
}

private final class WeakEventBindingSource {
    weak var value: (any EventBindingSource)?

    init(_ value: any EventBindingSource) {
        self.value = value
    }
}

/// Bridge between concrete platform event producers and the shared event manager.
class EventBindingBridge: GestureGraphDelegate, EventBindingManagerDelegate {
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
        manager?.delegate = self
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
        source.attach(to: self)
        guard !events.isEmpty else {
            lastPhase = .possible(nil)
            return []
        }

        let sourceID = ObjectIdentifier(source as AnyObject)
        var downstream: [EventID: any EventType] = [:]
        for (eventID, event) in events {
            downstream[eventID] = event
            switch event.phase {
            case .began, .active:
                trackedStates[eventID] = TrackedEventState(
                    sourceID: sourceID,
                    resetForwardedEventDispatchers: false
                )
            case .ended, .failed:
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
        if !trackedStates.values.contains(where: {
            !$0.resetForwardedEventDispatchers
        }) {
            manager?.reset(
                resetForwardedEventDispatchers: resetForwardedEventDispatchers
            )
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

    func didBind(to binding: EventBinding, id: EventID) {
        for source in eventSources {
            source.didBind(to: binding, id: id, in: self)
        }
    }

    func didUpdate(phase: GesturePhase<Void>, in manager: EventBindingManager) {
        for source in eventSources {
            source.didUpdate(phase: phase, in: self)
        }
        if phase.isTerminal {
            resetEvents()
        }
    }

    func didUpdate(gestureCategory: GestureCategory, in manager: EventBindingManager) {
        for source in eventSources {
            source.didUpdate(gestureCategory: gestureCategory, in: self)
        }
    }

    func requestHoverUpdate(in manager: EventBindingManager) {
        for source in eventSources {
            source.didRequestHoverUpdate(in: self)
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

extension _ViewInputs {
    func makeEventBindingBridge(
        bindingManager: EventBindingManager,
        responder: any AnyGestureResponder
    ) -> EventBindingBridge {
        EventBindingBridge(manager: bindingManager)
    }

    func makeGestureContainer(
        responder: any AnyGestureContainingResponder
    ) -> AnyObject {
        if let gestureResponder = responder as? any AnyGestureResponder {
            return gestureResponder.gestureGraph.eventBindingManager
        }
        fatalError("Gesture container requires an AnyGestureResponder")
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

private final class GestureGraphRuntimeState: @unchecked Sendable {
    let ownedRootResponder: MultiViewResponder
    weak var rendererHost: (any ViewRendererHost)?

    init(ownedRootResponder: MultiViewResponder) {
        self.ownedRootResponder = ownedRootResponder
    }
}

private let gestureGraphRuntimeStates = Mutex<[
    ObjectIdentifier: GestureGraphRuntimeState
]>([:])

private func gestureGraphRuntimeState(
    _ graph: GestureGraph
) -> GestureGraphRuntimeState {
    gestureGraphRuntimeStates.withLock { states in
        guard let state = states[ObjectIdentifier(graph)] else {
            fatalError("GestureGraph runtime state is not installed")
        }
        return state
    }
}

func connectGestureGraph(
    _ graph: GestureGraph,
    rendererHost: (any ViewRendererHost)?
) {
    gestureGraphRuntimeState(graph).rendererHost = rendererHost
}

/// Manages the entire gesture processing pipeline for a single window/view-graph.
///
/// Responsibilities:
/// - Owns an independent `_AGGraph` that is not shared with ViewGraph.
/// - Performs hit testing via `MultiViewResponder` to determine which `ViewResponder`
///   receives each event stream.
/// - Dispatches events to the gesture graph owned by each matched responder.
///
/// GestureFilter nodes live in ViewGraph's _AGGraph. GestureGraph.current resolves
/// through _AGGraphContext.current while GestureGraph's graph is active.
///
/// Adopts EventGraphHost for graph-side event delivery.
class GestureGraph: GraphHost, EventGraphHost, CustomStringConvertible,
    @unchecked Sendable
{

    var description: String {
        let gestureType = rootResponder.map {
            String(describing: $0.gestureType)
        } ?? "nil"
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        return "GestureGraph<\(gestureType)> \(pointer)"
    }

    override func hostKind() -> CustomEventTrace.InstantiationEventType.Kind {
        .gesture
    }

    // Resolves the active GestureGraph from the AG evaluation context.
    static var current: GestureGraph {
        guard let ref = _AGGraphContext.current, let g = ref.context as? GestureGraph else {
            fatalError("GestureGraph.current accessed outside a gesture-enabled AG context")
        }
        return g
    }

    weak var rootResponder: (any AnyGestureResponder)?
    weak var delegate: (any GestureGraphDelegate)?
    var eventBindingManager: EventBindingManager
    var _gestureTime: Attribute<Time>
    var _gestureEvents: Attribute<[EventID: any EventType]>
    var _inheritedPhase: Attribute<_GestureInputs.InheritedPhase>
    var _gestureResetSeed: Attribute<UInt32>
    var _rootPhase: OptionalAttribute<GesturePhase<Void>>
    var _gestureCategoryAttr: OptionalAttribute<GestureCategory>
    var _gestureLabelAttr: OptionalAttribute<String?>
    var _isCancellableAttr: OptionalAttribute<Bool>
    var _requiredTapCountAttr: OptionalAttribute<Int?>
    var _gestureDependencyAttr: OptionalAttribute<GestureDependency>
    var _autoScrollEnabledAttr: OptionalAttribute<Bool>
    var _gesturePreferenceKeys: Attribute<PreferenceKeys>
    var nextUpdateTime: Time
    private var activeGestureResponders: [Int: [any AnyGestureResponder]]
    private var cancelledGestureResponders: [Int: Set<ObjectIdentifier>]

    var responderNode: ResponderNode? {
        if let rootResponder {
            return rootResponder
        }
        return eventBindingManager.rootResponder
    }

    var focusedResponder: ResponderNode? {
        eventBindingManager.focusedResponder
    }

    var nextGestureUpdateTime: Time {
        nextUpdateTime
    }

    var rendererHost: (any ViewRendererHost)? {
        gestureGraphRuntimeState(self).rendererHost
    }

    func scheduleGestureUpdate(at time: Time) {
        if time < nextUpdateTime {
            nextUpdateTime = time
        }
    }

    // Init

    /// Creates a GestureGraph with its own independent _AGGraph.
    /// The gesture graph's AG is independent and not shared with ViewGraph.
    init() {
        let data = GraphHost.Data()
        let graph = data.graph
        let mvr = MultiViewResponder()
        var gestureTime: Attribute<Time>!
        var gestureEvents: Attribute<[EventID: any EventType]>!
        var inheritedPhase: Attribute<_GestureInputs.InheritedPhase>!
        var gestureResetSeed: Attribute<UInt32>!
        var gesturePreferenceKeys: Attribute<PreferenceKeys>!
        data.withCurrent {
            gestureTime = graph.makeInput(value: .zero)
            gestureEvents = graph.makeInput(value: [:])
            inheritedPhase = graph.makeInput(value: .defaultValue)
            gestureResetSeed = graph.makeInput(value: 0)
            gesturePreferenceKeys = graph.makeInput(value: PreferenceKeys())
        }
        self.rootResponder = nil
        self.delegate = nil
        self.eventBindingManager = EventBindingManager()
        self._gestureTime = gestureTime
        self._gestureEvents = gestureEvents
        self._inheritedPhase = inheritedPhase
        self._gestureResetSeed = gestureResetSeed
        self._rootPhase = OptionalAttribute()
        self._gestureCategoryAttr = OptionalAttribute()
        self._gestureLabelAttr = OptionalAttribute()
        self._isCancellableAttr = OptionalAttribute()
        self._requiredTapCountAttr = OptionalAttribute()
        self._gestureDependencyAttr = OptionalAttribute()
        self._autoScrollEnabledAttr = OptionalAttribute()
        self._gesturePreferenceKeys = gesturePreferenceKeys
        self.nextUpdateTime = .infinity
        self.activeGestureResponders = [:]
        self.cancelledGestureResponders = [:]
        super.init(data: data)
        gestureGraphRuntimeStates.withLock { states in
            states[ObjectIdentifier(self)] = GestureGraphRuntimeState(
                ownedRootResponder: mvr
            )
        }
        self.eventBindingManager.host = self
        self.eventBindingManager.rootResponder = mvr
    }

    convenience init(rootResponder: any AnyGestureResponder) {
        self.init()
        self.rootResponder = rootResponder
        eventBindingManager.rootResponder = rootResponder
    }

    deinit {
        _ = gestureGraphRuntimeStates.withLock { states in
            states.removeValue(forKey: ObjectIdentifier(self))
        }
    }

    func eventBinding(at location: CGPoint, accepting eventType: Any.Type) -> EventBinding? {
        if let consumer = hitTestEventConsumer(
            at: location,
            accepting: eventType
        ), let responder = consumer as? ResponderNode {
            return EventBinding(responder: responder)
        }
        guard let responder = hitTestResponders(
            at: location
        ).first else {
            return nil
        }
        let node: ResponderNode = responder
        return EventBinding(responder: node)
    }

    // MARK: - EventGraphHost

    func sendRecognizerEvents(
        _ events: [EventID: any EventType],
        source: any EventBindingSource,
        at time: Time
    ) -> GesturePhase<Void> {
        guard rootResponder == nil,
              eventBindingManager.rootResponder != nil else {
            return .possible(nil)
        }
        // Keep responder callbacks and platform-consumer commits in one event
        // turn so queued actions drain only after every recipient has observed
        // the sample.
        return Update.ensure {
            sendRootEvents(
                events,
                source: source,
                at: time
            )
        }
    }

    @discardableResult
    func sendEvents(
        _ events: [EventID: any EventType],
        rootNode: ResponderNode,
        at time: Time
    ) -> GesturePhase<Void> {
        if let responder = rootNode as? any AnyGestureResponder,
           responder.gestureGraph !== self {
            return responder.gestureGraph.sendEvents(
                events,
                rootNode: rootNode,
                at: time
            )
        }

        if rootResponder == nil {
            return sendRootEvents(
                events,
                source: nil,
                at: time
            )
        }

        return data.withCurrent {
            data.graph.inbox.drain()
            instantiateIfNeeded()
            if _gestureTime.value != time {
                _gestureTime.setValue(time)
                timeDidChange()
            }
            _gestureEvents.setValue(events)
            let phase = _rootPhase.attribute?.value ?? .possible(nil)
            if events.values.contains(where: { $0.phase == .failed }) {
                _gestureResetSeed.setValue(_gestureResetSeed.value &+ 1)
            }
            return phase
        }
    }

    private func sendRootEvents(
        _ events: [EventID: any EventType],
        source: (any EventBindingSource)?,
        at time: Time
    ) -> GesturePhase<Void> {
        let eventSerials = Set(events.keys.map(\.serial))
        let candidates = gestureCandidates(for: events)
        let activeCandidates = candidates.filter { responder in
            let identifier = ObjectIdentifier(responder as AnyObject)
            return !eventSerials.contains { serial in
                cancelledGestureResponders[serial]?.contains(identifier) == true
            }
        }
        let gestureDispatches = activeCandidates.map { responder in
            let graph = responder.gestureGraph
            let manager = graph.eventBindingManager
            let phase: GesturePhase<Void>
            if let source {
                _ = responder.eventSources
                if let bridge = graph.delegate as? EventBindingBridge {
                    _ = bridge.send(events, source: source, at: time)
                    phase = bridge.lastPhase
                } else {
                    phase = manager.sendDownstream(events, at: time)
                }
            } else {
                phase = manager.sendDownstream(events, at: time)
            }
            return GestureResponderDispatch(
                responder: responder,
                manager: manager,
                phase: phase
            )
        }
        let consumerResult = dispatchToEventConsumers(
            events,
            at: time,
            gestureDispatches: gestureDispatches
        )
        var resetManagerIDs = consumerResult.cancelledManagerIDs
        for dispatch in gestureDispatches where dispatch.phase.isTerminal {
            let identifier = ObjectIdentifier(dispatch.manager)
            guard resetManagerIDs.insert(identifier).inserted else { continue }
            dispatch.manager.reset()
        }
        var phases = gestureDispatches.map(\.phase)
        phases.append(contentsOf: consumerResult.phases)

        var phasesBySerial: [Int: [EventPhase]] = [:]
        for (eventID, event) in events {
            phasesBySerial[eventID.serial, default: []].append(event.phase)
        }
        for (serial, eventPhases) in phasesBySerial
        where eventPhases.allSatisfy(\.isTerminal) {
            activeGestureResponders.removeValue(forKey: serial)
            cancelledGestureResponders.removeValue(forKey: serial)
        }

        if phases.contains(where: { $0.isActive }) { return .active(()) }
        if phases.contains(where: { $0.isEnded }) { return .ended(()) }
        if !phases.isEmpty && phases.allSatisfy({ $0.isFailed }) { return .failed }
        return .possible(nil)
    }

    private func gestureCandidates(
        for events: [EventID: any EventType]
    ) -> [any AnyGestureResponder] {
        var result: [any AnyGestureResponder] = []
        var seen: Set<ObjectIdentifier> = []

        for serial in Set(events.keys.map(\.serial)).sorted() {
            let serialEvents = events.filter { $0.key.serial == serial }
            let candidates: [any AnyGestureResponder]
            if serialEvents.values.contains(where: { $0.phase == .began }) {
                cancelledGestureResponders.removeValue(forKey: serial)
                candidates = initialGestureCandidates(for: serialEvents)
                activeGestureResponders[serial] = candidates
            } else if let active = activeGestureResponders[serial] {
                candidates = active
            } else {
                candidates = initialGestureCandidates(for: serialEvents)
            }

            for candidate in candidates {
                let identifier = ObjectIdentifier(candidate as AnyObject)
                if seen.insert(identifier).inserted {
                    result.append(candidate)
                }
            }
        }
        return result
    }

    private func initialGestureCandidates(
        for events: [EventID: any EventType]
    ) -> [any AnyGestureResponder] {
        var boundResponders: [any AnyGestureResponder] = []
        var seen: Set<ObjectIdentifier> = []
        for event in events.values {
            guard let boundNode = event.binding?.responder else { continue }
            for responder in boundNode.sequence.compactMap({
                $0 as? any AnyGestureResponder
            }) where responder.mask.contains(.gesture) {
                let identifier = ObjectIdentifier(responder as AnyObject)
                if seen.insert(identifier).inserted {
                    boundResponders.append(responder)
                }
            }
        }
        if !boundResponders.isEmpty {
            return selectHitResponders(from: boundResponders)
        }

        guard let location = events.values.compactMap({ event in
            (event as? any HitTestableEventType)?.hitTestLocation
        }).first else {
            return []
        }
        let hasArbitratingPlatformHost = events.values.contains { event in
            guard let hitTestable = event as? any HitTestableEventType else {
                return false
            }
            return hitTestEventConsumer(
                at: hitTestable.hitTestLocation,
                accepting: type(of: event)
            ) is any GestureArbitratingEventConsumer
        }
        if hasArbitratingPlatformHost {
            return hitTestCandidateResponders(at: location)
        }
        return hitTestResponders(at: location)
    }

    private struct GestureResponderDispatch {
        var responder: any AnyGestureResponder
        var manager: EventBindingManager
        var phase: GesturePhase<Void>
    }

    private func dispatchToEventConsumers(
        _ events: [EventID: any EventType],
        at time: Time,
        gestureDispatches: [GestureResponderDispatch]
    ) -> (phases: [GesturePhase<Void>], cancelledManagerIDs: Set<ObjectIdentifier>) {
        struct Dispatch {
            var consumer: any ResponderEventConsumer
            var responder: ResponderNode
            var events: [EventID: any EventType]
            var terminalIDs: [EventID]
        }

        var dispatches: [ObjectIdentifier: Dispatch] = [:]
        for (eventID, event) in events {
            let eventType = type(of: event)
            let consumerAndResponder: (
                consumer: any ResponderEventConsumer,
                responder: ResponderNode
            )?

            if let responder = event.binding?.responder,
               let consumer = responder as? any ResponderEventConsumer {
                consumerAndResponder = (consumer, responder)
            } else if let responder = eventBindingManager.bindings[eventID]?.responder,
                      let consumer = responder as? any ResponderEventConsumer {
                consumerAndResponder = (consumer, responder)
            } else if let event = event as? any HitTestableEventType,
                      let consumer = hitTestEventConsumer(
                        at: event.hitTestLocation,
                        accepting: eventType
                      ),
                      let responder = consumer as? ResponderNode {
                consumerAndResponder = (consumer, responder)
            } else {
                consumerAndResponder = nil
            }

            guard let consumerAndResponder else { continue }
            if event.phase == .began {
                eventBindingManager.rebindEvent(
                    eventID,
                    to: consumerAndResponder.responder
                )
            }
            let identifier = ObjectIdentifier(
                consumerAndResponder.consumer as AnyObject
            )
            var dispatch = dispatches[identifier] ?? Dispatch(
                consumer: consumerAndResponder.consumer,
                responder: consumerAndResponder.responder,
                events: [:],
                terminalIDs: []
            )
            dispatch.events[eventID] = event
            if event.phase.isTerminal {
                dispatch.terminalIDs.append(eventID)
            }
            dispatches[identifier] = dispatch
        }

        var phases: [GesturePhase<Void>] = []
        var cancelledManagers: [ObjectIdentifier: EventBindingManager] = [:]
        for dispatch in dispatches.values {
            let arbitrator = dispatch.consumer as? any GestureArbitratingEventConsumer
            if let arbitrator {
                for gestureDispatch in gestureDispatches
                where gestureDispatch.phase.isActive &&
                    arbitrator.isPrevented(by: gestureDispatch.responder) {
                    arbitrator.preventRecognition(for: dispatch.events)
                }
            }
            let phase = dispatch.consumer.consumeEvents(
                dispatch.events,
                at: time
            )
            if phase.isActive, let arbitrator {
                for gestureDispatch in gestureDispatches
                where !gestureDispatch.phase.isTerminal &&
                    arbitrator.cancels(gestureDispatch.responder) {
                    let responderID = ObjectIdentifier(
                        gestureDispatch.responder as AnyObject
                    )
                    for eventID in dispatch.events.keys {
                        cancelledGestureResponders[eventID.serial, default: []]
                            .insert(responderID)
                    }
                    let managerID = ObjectIdentifier(gestureDispatch.manager)
                    cancelledManagers[managerID] = gestureDispatch.manager
                }
            }
            for eventID in dispatch.terminalIDs {
                eventBindingManager.rebindEvent(eventID, to: nil)
            }
            phases.append(phase)
        }
        for manager in cancelledManagers.values {
            manager.reset()
        }
        return (phases, Set(cancelledManagers.keys))
    }

    private func hitTestEventConsumer(
        at location: CGPoint,
        accepting eventType: Any.Type
    ) -> (any ResponderEventConsumer)? {
        let root = (eventBindingManager.rootResponder as? MultiViewResponder)
            ?? gestureGraphRuntimeState(self).ownedRootResponder

        func firstConsumer(
            in responders: [ViewResponder]
        ) -> (any ResponderEventConsumer)? {
            for responder in responders.reversed() {
                guard responder.features.isSuperset(of: .platformViews) else {
                    continue
                }
                let options = ViewResponder.ContainsPointsOptions.platformDefault
                guard responder.hitTestPolicy(options: options) != .exclude else {
                    continue
                }
                let result = responder.containsGlobalPoints(
                    [location],
                    cacheKey: nil,
                    options: options
                )
                guard result.mask[0] else { continue }
                if let descendant = firstConsumer(in: result.children) {
                    return descendant
                }
                if let consumer = responder as? any ResponderEventConsumer,
                   consumer.acceptsEventType(eventType) {
                    return consumer
                }
            }
            return nil
        }

        return firstConsumer(in: root.children)
    }

    /// Returns hit responders at a given point, filtered by exclusion policy.
    ///
    /// .simultaneous(.global): always included alongside any other policy.
    /// .simultaneous(.descendants/.ancestors): included only when the hierarchy relationship
    ///   is satisfied with at least one other hit responder (via isDescendant chain).
    private func hitTestCandidateResponders(
        at location: CGPoint
    ) -> [any AnyGestureResponder] {
        let root = (eventBindingManager.rootResponder as? MultiViewResponder)
            ?? gestureGraphRuntimeState(self).ownedRootResponder
        return root.respondersContaining(point: location)
            .compactMap { $0 as? any AnyGestureResponder }
            .filter { $0.mask.contains(.gesture) }
    }

    private func hitTestResponders(
        at location: CGPoint
    ) -> [any AnyGestureResponder] {
        selectHitResponders(
            from: hitTestCandidateResponders(at: location)
        )
    }

    private func selectHitResponders(
        from hits: [any AnyGestureResponder]
    ) -> [any AnyGestureResponder] {
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
                    // Include when either responder's hierarchy-scoped policy
                    // permits the pair; the combined helper is symmetric.
                    include = hits.contains { other in
                        other !== responder && other.isSimultaneous(with: responder)
                    }
                }
                if include { result.append(responder) }
            }
        }
        return result
    }

    func resetEvents() {
        uninstantiate(immediately: false)
    }

    override func instantiateOutputs() {
        guard let rootResponder else { return }

        var inputs = _GestureInputs(
            rootResponder.inputs,
            viewSubgraph: nil,
            events: _gestureEvents,
            time: _gestureTime,
            resetSeed: _gestureResetSeed,
            inheritedPhase: _inheritedPhase,
            gesturePreferenceKeys: _gesturePreferenceKeys
        )
        inputs.options = .gestureGraph
        inputs.preferences.add(GestureCategory.Key.self)
        inputs.preferences.add(ScrollViewDragAutoScrollKey.self)
        inputs.preferences.add(GestureLabelKey.self)
        inputs.preferences.add(IsCancellableGestureKey.self)
        inputs.preferences.add(RequiredTapCountKey.self)
        inputs.preferences.add(GestureDependency.Key.self)

        let outputs = rootResponder.makeGesture(inputs: inputs)
        func preferenceAttribute<K: PreferenceKey>(
            _ key: K.Type
        ) -> OptionalAttribute<K.Value> {
            guard let value = outputs.preferences.value(for: key) else {
                return OptionalAttribute()
            }
            return OptionalAttribute(Attribute<K.Value>(value))
        }
        _rootPhase = OptionalAttribute(outputs.phase)
        _gestureCategoryAttr = preferenceAttribute(GestureCategory.Key.self)
        _gestureLabelAttr = preferenceAttribute(GestureLabelKey.self)
        _isCancellableAttr = preferenceAttribute(IsCancellableGestureKey.self)
        _requiredTapCountAttr = preferenceAttribute(RequiredTapCountKey.self)
        _gestureDependencyAttr = preferenceAttribute(GestureDependency.Key.self)
        _autoScrollEnabledAttr = preferenceAttribute(ScrollViewDragAutoScrollKey.self)
    }

    override func uninstantiateOutputs() {
        data.withCurrent {
            _gestureEvents.setValue([:])
            _inheritedPhase.setValue(.defaultValue)
            _gestureResetSeed.setValue(0)
            _gesturePreferenceKeys.setValue(PreferenceKeys())
            rootResponder?.resetGesture()
        }
        _rootPhase = OptionalAttribute()
        _gestureCategoryAttr = OptionalAttribute()
        _gestureLabelAttr = OptionalAttribute()
        _isCancellableAttr = OptionalAttribute()
        _requiredTapCountAttr = OptionalAttribute()
        _gestureDependencyAttr = OptionalAttribute()
        _autoScrollEnabledAttr = OptionalAttribute()
        nextUpdateTime = .infinity
    }

    override func timeDidChange() {
        nextUpdateTime = .infinity
    }

    /// Advances time-only recognizers when their scheduled deadline is reached.
    @discardableResult
    func updateTimedGestures(at time: Time) -> Bool {
        guard !(time < nextGestureUpdateTime) else { return false }
        return data.withCurrent {
            instantiateIfNeeded()
            guard isInstantiated else {
                return false
            }
            if _gestureTime.value != time {
                _gestureTime.setValue(time)
            }
            timeDidChange()
            _ = _rootPhase.attribute?.value
            return true
        }
    }

    func enqueueAction(_ action: @escaping () -> Void) {
        delegate?.enqueueAction(action)
    }

    func gestureCategory() -> GestureCategory? {
        data.withCurrent {
            instantiateIfNeeded()
            return _gestureCategoryAttr.attribute?.value
        }
    }

    func isAutoScrollEnabled() -> Bool {
        data.withCurrent {
            instantiateIfNeeded()
            return _autoScrollEnabledAttr.attribute?.value ?? false
        }
    }

    // ViewRespondersKey update

    /// Called when the ViewRespondersKey preference value changes at the root.
    func updateResponders(_ responders: [ViewResponder]) {
        gestureGraphRuntimeState(self).ownedRootResponder.updateChildren(
            (value: responders, changed: true)
        )
    }
}
