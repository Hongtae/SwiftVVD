//
//  File: GestureGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

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

struct WindowDragGestureIsActiveKey: PreferenceKey {
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
    var eventBindings: [EventID: EventBinding] = [:]
    weak var host: (any EventGraphHost)?
    weak var delegate: (any EventBindingManagerDelegate)?
    private(set) var isActive = false
    // The window backend wakes its frame loop at this absolute graph deadline.
    // It replaces the one-shot host timer while preserving manager lifetime.
    private(set) var scheduledEventUpdateTime: Time = .infinity
    private var hasPendingHoverUpdate = false
    private let lock = Mutex(())

    var rootResponder: ResponderNode? {
        host?.responderNode
    }

    var focusedResponder: ResponderNode? {
        host?.focusedResponder
    }

    static var current: EventBindingManager? {
        guard let viewGraph = GraphHost.currentHost as? ViewGraph,
              let rendererHost = viewGraph.rendererHost else {
            return nil
        }
        return (rendererHost as? any EventGraphHost)?.eventBindingManager
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
        let old = eventBindings[eventID]
        if let r = responder {
            let new = EventBinding(responder: r)
            eventBindings[eventID] = new
            return (from: old, to: new)
        } else {
            eventBindings.removeValue(forKey: eventID)
            return (from: old, to: nil)
        }
    }

    /// Removes the binding for a given event ID (called when interaction ends).
    func willRemoveResponder(_ responder: ResponderNode) {
        eventBindings = eventBindings.filter {
            $0.value.responder !== responder
        }
    }

    /// Routes events produced directly by a platform host.
    @discardableResult
    func send(
        _ events: [EventID: any EventType]
    ) -> Set<EventID> {
        withDispatchScope {
            sendDownstreamBody(events)
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
        _ events: [EventID: any EventType]
    ) -> Set<EventID> {
        withDispatchScope {
            sendDownstreamBody(events)
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
        _ events: [EventID: any EventType]
    ) -> Set<EventID> {
        var consumed = dispatchNonGestureEvents(events)
        let downstreamEvents = events.filter {
            forwardedEventDispatchers[
                ObjectIdentifier(type(of: $0.value))
            ] == nil
        }
        guard let host else { return consumed }
        let rootNode = host.responderNode
        var boundEvents: [EventID: any EventType] = [:]
        var terminalEventIDs: [EventID] = []

        for (eventID, sourceEvent) in downstreamEvents {
            var event = sourceEvent
            let binding: EventBinding
            if let existingBinding = eventBindings[eventID] {
                binding = existingBinding
            } else {
                let responder: ResponderNode?
                if event.isFocusEvent,
                   let focusedResponder = host.focusedResponder {
                    responder = focusedResponder.bindEvent(event)
                } else {
                    responder = rootNode?.bindEvent(event)
                }
                guard let responder else { continue }
                binding = EventBinding(responder: responder)
                eventBindings[eventID] = binding
                isActive = true
                delegate?.didBind(to: binding, id: eventID)
            }

            event.binding = binding
            eventBindings[eventID] = binding
            boundEvents[eventID] = event
            if event.phase.isTerminal {
                terminalEventIDs.append(eventID)
            }
        }

        if isActive, let rootNode {
            let time = Time.systemUptime
            let phase = host.sendEvents(
                boundEvents,
                rootNode: rootNode,
                at: time
            )
            let nextUpdateTime = host.nextGestureUpdateTime
            let category = host.gestureCategory()

            if !phase.isFailed {
                consumed.formUnion(boundEvents.keys)
            }
            delegate?.didUpdate(phase: phase, in: self)
            if let category {
                delegate?.didUpdate(gestureCategory: category, in: self)
            }
            scheduledEventUpdateTime = nextUpdateTime
        }

        for eventID in terminalEventIDs {
            eventBindings.removeValue(forKey: eventID)
        }
        return consumed
    }

    @discardableResult
    func sendScheduledEventUpdate(at time: Time) -> Bool {
        guard isActive,
              !(scheduledEventUpdateTime == .infinity),
              !(time < scheduledEventUpdateTime) else {
            return false
        }
        scheduledEventUpdateTime = .infinity
        _ = sendDownstream([:])
        return true
    }

    func reset(resetForwardedEventDispatchers: Bool = false) {
        Update.ensure {
            if resetForwardedEventDispatchers {
                for key in Array(forwardedEventDispatchers.keys) {
                    guard var dispatcher = forwardedEventDispatchers[key] else {
                        continue
                    }
                    dispatcher.reset()
                    forwardedEventDispatchers[key] = dispatcher
                }
            }
            // Tear down outputs after the current event callbacks have drained.
            Update.enqueueAction { [weak host] in
                host?.resetEvents()
            }
            eventBindings.removeAll()
            scheduledEventUpdateTime = .infinity
            isActive = false
        }
    }

    func enqueueHoverUpdateIfNeeded() {
        guard !hasPendingHoverUpdate else { return }
        hasPendingHoverUpdate = true
        Update.enqueueAction { [weak self] in
            guard let self else { return }
            self.hasPendingHoverUpdate = false
            self.delegate?.requestHoverUpdate(in: self)
        }
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

enum EventSourceType: CaseIterable, Equatable, Hashable {
    case platformGestureRecognizer
    case hoverGestureRecognizer
    case selectGestureRecognizer

    static var allCases: [EventSourceType] { [] }
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

/// Bridge between concrete platform event producers and the shared event manager.
class EventBindingBridge: EventBindingManagerDelegate {
    struct TrackedEventState {
        var sourceID: ObjectIdentifier
        var reset: Bool
    }

    weak var eventBindingManager: EventBindingManager?
    private var trackedEvents: [EventID: TrackedEventState] = [:]

    init() {}

    init(eventBindingManager: EventBindingManager) {
        self.eventBindingManager = eventBindingManager
    }

    var eventSources: [any EventBindingSource] {
        []
    }

    func source(
        for type: EventSourceType
    ) -> (any EventBindingSource)? {
        nil
    }

    @discardableResult
    func send(
        _ events: [EventID: any EventType],
        source: any EventBindingSource
    ) -> Set<EventID> {
        guard !events.isEmpty else { return [] }

        let sourceID = ObjectIdentifier(source as AnyObject)
        var downstream: [EventID: any EventType] = [:]
        for (eventID, event) in events {
            downstream[eventID] = event
            if event is any NonGestureEventType {
                continue
            }
            switch event.phase {
            case .began:
                break
            case .active:
                trackedEvents[eventID] = TrackedEventState(
                    sourceID: sourceID,
                    reset: false
                )
            case .ended, .failed:
                trackedEvents.removeValue(forKey: eventID)
            }
        }

        return eventBindingManager?.sendDownstream(downstream) ?? []
    }

    func reset(
        eventSource: any EventBindingSource,
        resetForwardedEventDispatchers: Bool = false
    ) {
        let sourceID = ObjectIdentifier(eventSource as AnyObject)
        trackedEvents = trackedEvents.filter { _, state in
            state.sourceID != sourceID
        }
        if !trackedEvents.values.contains(where: {
            !$0.reset
        }) {
            eventBindingManager?.reset(
                resetForwardedEventDispatchers: resetForwardedEventDispatchers
            )
        }
    }

    func resetEvents() {
        for eventID in trackedEvents.keys {
            if var state = trackedEvents[eventID] {
                state.reset = true
                trackedEvents[eventID] = state
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

}

protocol EventBindingBridgeFactory {
    static func makeEventBindingBridge(
        bindingManager: EventBindingManager,
        responder: any AnyGestureResponder
    ) -> EventBindingBridge & GestureGraphDelegate
}

struct EventBindingBridgeFactoryInput: ViewInput {
    static var defaultValue: (any EventBindingBridgeFactory.Type)? { nil }

    static func valuesEqual(
        _ lhs: (any EventBindingBridgeFactory.Type)?,
        _ rhs: (any EventBindingBridgeFactory.Type)?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        default:
            return false
        }
    }
}

extension _ViewInputs {
    func makeEventBindingBridge(
        bindingManager: EventBindingManager,
        responder: any AnyGestureResponder
    ) -> EventBindingBridge & GestureGraphDelegate {
        guard let factory = self[EventBindingBridgeFactoryInput.self] else {
            fatalError("Event binding factory must be configured")
        }
        return factory.makeEventBindingBridge(
            bindingManager: bindingManager,
            responder: responder
        )
    }

    func makeGestureContainer(
        responder: any AnyGestureContainingResponder
    ) -> AnyObject {
        fatalError("Gesture container factory must be configured")
    }
}

// EventGraphHost

/// Protocol for objects that own an EventBindingManager and can receive event streams.
/// Rendering hosts own direct-event sessions, while GestureGraph owns a responder-specific
/// graph entry point. Graph-only hosts use false/no-op topology and passthrough defaults.
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
    /// A standalone graph has no host hierarchy, so the default is false.
    func isDescendant(of host: AnyObject) -> Bool

    /// Notifies the host that a platform event was consumed.
    /// A standalone graph has no upstream event producer, so the default is no-op.
    func didConsumePlatformEvent(_ event: AnyObject)
}

extension EventGraphHost {
    func isDescendant(of host: AnyObject) -> Bool { false }
    func didConsumePlatformEvent(_ event: AnyObject) {}
}

// GestureGraph

/// Owns the independent gesture graph for one gesture responder.
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
        rootResponder
    }

    var focusedResponder: ResponderNode? {
        guard let viewResponder = rootResponder as? ViewResponder,
              let host = viewResponder.host as? any EventGraphHost else {
            return nil
        }
        return host.focusedResponder
    }

    var nextGestureUpdateTime: Time {
        nextUpdateTime
    }

    func scheduleGestureUpdate(at time: Time) {
        if time < nextUpdateTime {
            nextUpdateTime = time
        }
    }

    // Init

    init(rootResponder: any AnyGestureResponder) {
        let data = GraphHost.Data()
        let graph = data.graph
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
        self.rootResponder = rootResponder
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
        self.eventBindingManager.host = self
    }

    override init(data: GraphHost.Data) {
        fatalError("GestureGraph.init(data:) is unavailable")
    }

    // MARK: - EventGraphHost

    @discardableResult
    func sendEvents(
        _ events: [EventID: any EventType],
        rootNode: ResponderNode,
        at time: Time
    ) -> GesturePhase<Void> {
        return data.withCurrent {
            guard rootResponder != nil else { return .failed }
            data.graph.inbox.drain()
            instantiateIfNeeded()
            startTransactionUpdate()
            if _gestureTime.value != time {
                _gestureTime.setValue(time)
                data._updateSeed.setValue(data._updateSeed.value &+ 1)
                timeDidChange()
            }
            _gestureEvents.setValue(events)
            finishTransactionUpdate(
                in: rootSubgraph,
                postUpdate: { needsFollowUp in
                    if needsFollowUp && !events.isEmpty {
                        _gestureEvents.setValue([:])
                    }
                },
                id: nil
            )
            return _rootPhase.attribute?.value ?? .possible(nil)
        }
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

}
