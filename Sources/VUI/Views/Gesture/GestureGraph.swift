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
            lastDirectConsumedEventIDs =
                (delegate as? any DirectEventBindingManagerDelegate)?
                .receiveDirectEvents(events, in: self) ?? []
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
        let callback: (any EventBindingManagerDelegate)? = bridge ?? delegate
        for eventID in events.keys {
            if let binding = bindings[eventID] {
                callback?.didBind(to: binding, id: eventID)
            }
        }
        callback?.didUpdate(phase: phase, in: self)
        if let category = host.gestureCategory() {
            callback?.didUpdate(gestureCategory: category, in: self)
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

protocol DirectEventBindingManagerDelegate: AnyObject {
    func receiveDirectEvents(
        _ events: [EventID: any EventType],
        in manager: EventBindingManager
    ) -> Set<EventID>
}

extension DirectEventBindingManagerDelegate {
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

    func didBind(to binding: EventBinding, id: EventID) {
        for source in eventSources {
            source.didBind(to: binding, id: id, in: self)
        }
    }

    func didUpdate(phase: GesturePhase<Void>, in manager: EventBindingManager) {
        for source in eventSources {
            source.didUpdate(phase: phase, in: self)
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

    var responderNode: ResponderNode? {
        (rootResponder as? ResponderNode) ?? eventBindingManager.rootResponder
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
        if let responder = rootResponder as? ResponderNode {
            eventBindingManager.rootResponder = responder
        }
    }

    deinit {
        gestureGraphRuntimeStates.withLock { states in
            states.removeValue(forKey: ObjectIdentifier(self))
        }
    }

    func eventBinding(at location: CGPoint, accepting eventType: Any.Type) -> EventBinding? {
        guard let responder = hitTestResponders(
            at: location
        ).first,
              let node = responder as? ResponderNode else {
            return nil
        }
        return EventBinding(responder: node)
    }

    // MARK: - EventGraphHost

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
            let candidates: [any AnyGestureResponder]
            if let bound = events.values.compactMap({ event -> AnyGestureResponder? in
                (event as? any ResponderBoundEvent)?.binding?.responder
                    as? any AnyGestureResponder
            }).first {
                candidates = [bound]
            } else if let location = events.values.compactMap({ event in
                (event as? any HitTestableEventType)?.hitTestLocation
            }).first {
                candidates = hitTestResponders(at: location)
            } else {
                candidates = []
            }
            let phases = candidates.compactMap { responder -> GesturePhase<Void>? in
                guard let node = responder as? ResponderNode else { return nil }
                return responder.gestureGraph.sendEvents(events, rootNode: node, at: time)
            }
            if phases.contains(where: { $0.isActive }) { return .active(()) }
            if phases.contains(where: { $0.isEnded }) { return .ended(()) }
            if !phases.isEmpty && phases.allSatisfy({ $0.isFailed }) { return .failed }
            return .possible(nil)
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

    /// Returns hit responders at a given point, filtered by exclusion policy.
    ///
    /// .simultaneous(.global): always included alongside any other policy.
    /// .simultaneous(.descendants/.ancestors): included only when the hierarchy relationship
    ///   is satisfied with at least one other hit responder (via isDescendant chain).
    private func hitTestCandidateResponders(
        at location: CGPoint
    ) -> [any AnyGestureResponder] {
        let root = gestureGraphRuntimeState(self).ownedRootResponder
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
            (rootResponder as? ResponderNode)?.resetGesture()
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
