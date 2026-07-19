//
//  File: Gesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// Gesture Protocol

public protocol Gesture<Value> {
    associatedtype Value
    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Self.Value>
    associatedtype Body: Gesture
    var body: Self.Body { get }
}

extension Never: Gesture {
    public typealias Value = Never
}

extension Gesture where Self.Value == Self.Body.Value {
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Self.Body.Value> {
        Self.Body._makeGesture(gesture: gesture[\.body], inputs: inputs)
    }
}

extension Gesture where Self.Body == Never {
    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

extension Optional: Gesture where Wrapped: Gesture {
    public typealias Value = Wrapped.Value
    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Wrapped.Value> {
        Wrapped._makeGesture(gesture: gesture[\.unsafelyUnwrapped], inputs: inputs)
    }
    public typealias Body = Never
}

// GesturePhase

/// The current phase of a gesture interaction.
public enum GesturePhase<V> {
    /// Gesture is waiting for sufficient input to recognize. Optional pre-computed value.
    case possible(V?)
    /// Gesture is active and delivering continuous updates.
    case active(V)
    /// Gesture has completed successfully.
    case ended(V)
    /// Gesture failed or was cancelled.
    case failed

    public var isPossible: Bool {
        if case .possible = self { return true }
        return false
    }
    public var isActive: Bool {
        switch self {
        case .active, .ended:
            return true
        default:
            return false
        }
    }
    public var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }
    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
    public var isTerminal: Bool { isEnded || isFailed }

    public var unwrapped: V? {
        switch self {
        case .active(let v): return v
        case .ended(let v): return v
        default: return nil
        }
    }

    public func map<A>(_ transform: (V) -> A) -> GesturePhase<A> {
        switch self {
        case .possible(let v): return .possible(v.map(transform))
        case .active(let v): return .active(transform(v))
        case .ended(let v): return .ended(transform(v))
        case .failed: return .failed
        }
    }

    public func withValue<A>(_ a: @autoclosure () -> A) -> GesturePhase<A> {
        switch self {
        case .possible: return .possible(nil)
        case .active: return .active(a())
        case .ended: return .ended(a())
        case .failed: return .failed
        }
    }
}

extension GesturePhase: Equatable where V: Equatable {
    public static func == (lhs: GesturePhase<V>, rhs: GesturePhase<V>) -> Bool {
        switch (lhs, rhs) {
        case (.possible(let a), .possible(let b)): return a == b
        case (.active(let a), .active(let b)): return a == b
        case (.ended(let a), .ended(let b)): return a == b
        case (.failed, .failed): return true
        default: return false
        }
    }
}

extension GesturePhase: Defaultable {
    /// The default phase used by an uninstantiated gesture output.
    public static var defaultValue: GesturePhase<V> { .failed }

    /// Combines two phases into a single phase carrying a tuple value.
    /// Both must be active/ended for the result to be active/ended;
    /// either failing causes combined failure.
    public func and<A>(_ other: GesturePhase<A>) -> GesturePhase<(V, A)> {
        and(other) { ($0, $1) }
    }

    /// Combines two phases into a single phase with a custom value transform.
    public func and<A, B>(_ other: GesturePhase<A>, value: (V, A) -> B) -> GesturePhase<B> {
        switch (self, other) {
        case (.ended(let v),  .ended(let a)):  return .ended(value(v, a))
        case (.ended(let v),  .active(let a)): return .ended(value(v, a))
        case (.active(let v), .ended(let a)):  return .ended(value(v, a))
        case (.active(let v), .active(let a)): return .active(value(v, a))
        case (.failed, _), (_, .failed):        return .failed
        default:                                return .possible(nil)
        }
    }
}

// Event Types

/// Identifies a unique event stream. A single interaction (e.g., finger 1) has
/// a stable EventID for its lifetime; each new interaction gets a new serial.
struct EventID: Hashable, CustomStringConvertible {
    var type: Any.Type
    var serial: Int

    init(type: Any.Type, serial: Int) {
        self.type = type
        self.serial = serial
    }

    static func == (lhs: EventID, rhs: EventID) -> Bool {
        lhs.type == rhs.type && lhs.serial == rhs.serial
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type))
        hasher.combine(serial)
    }

    var description: String { "\(type)#\(serial)" }
}

/// Common lifecycle phase shared by all EventType values.
enum EventPhase: Equatable, Hashable {
    case began
    case active
    case ended
    case failed

    var isTerminal: Bool {
        self == .ended || self == .failed
    }
}

protocol EventType {
    var phase: EventPhase { get }
    var timestamp: Time { get }
    var binding: EventBinding? { get set }
    var customHitTestOptions: ViewResponder.ContainsPointsOptions? { get }
    init?(_ event: any EventType)
}

extension EventType {
    var customHitTestOptions: ViewResponder.ContainsPointsOptions? { nil }

    init?(_ event: any EventType) {
        guard let event = event as? Self else { return nil }
        self = event
    }

    var isFocusEvent: Bool { false }
}

protocol ModifiersEventType: EventType {
    var modifiers: EventModifiers { get set }
}

struct Event: EventType {
    var phase: EventPhase
    var timestamp: Time
    var binding: EventBinding?
    var customHitTestOptions: ViewResponder.ContainsPointsOptions?

    init(_ event: any EventType) {
        phase = event.phase
        timestamp = event.timestamp
        binding = event.binding
        customHitTestOptions = event.customHitTestOptions
    }
}

struct TappableEvent: Equatable, EventType, TappableEventType {
    var phase: EventPhase
    var timestamp: Time
    var binding: EventBinding?
    var customHitTestOptions: ViewResponder.ContainsPointsOptions?

    init<E>(_ event: E) where E: TappableEventType {
        phase = event.phase
        timestamp = event.timestamp
        binding = event.binding
        customHitTestOptions = event.customHitTestOptions
    }

    init(_ event: any TappableEventType) {
        phase = event.phase
        timestamp = event.timestamp
        binding = event.binding
        customHitTestOptions = event.customHitTestOptions
    }

    init?(_ event: any EventType) {
        guard let event = event as? any TappableEventType else { return nil }
        self.init(event)
    }
}

protocol SpatialEventType: EventType {
    var globalLocation: CGPoint { get set }
    var location: CGPoint { get set }
    var radius: CGFloat { get }
    var kind: SpatialEvent.Kind? { get }
}

struct SpatialEvent: EventType, SpatialEventType, Equatable {
    enum Kind: Hashable {
        case touch
        case mouse
        case pan
    }

    var phase: EventPhase
    var timestamp: Time
    var binding: EventBinding?
    var kind: Kind?
    var globalLocation: CGPoint
    var location: CGPoint
    var radius: CGFloat
    var customHitTestOptions: ViewResponder.ContainsPointsOptions?

    init<E>(_ event: E) where E: SpatialEventType {
        phase = event.phase
        timestamp = event.timestamp
        binding = event.binding
        kind = event.kind
        globalLocation = event.globalLocation
        location = event.location
        radius = event.radius
        customHitTestOptions = event.customHitTestOptions
    }

    init(_ event: any SpatialEventType) {
        phase = event.phase
        timestamp = event.timestamp
        binding = event.binding
        kind = event.kind
        globalLocation = event.globalLocation
        location = event.location
        radius = event.radius
        customHitTestOptions = event.customHitTestOptions
    }

    init?(_ event: any EventType) {
        guard let event = event as? any SpatialEventType else { return nil }
        self.init(event)
    }
}

struct MouseEvent: EventType,
                   SpatialEventType,
                   TappableEventType,
                   ModifiersEventType,
                   HitTestableEventType,
                   Equatable {
    struct Button: RawRepresentable, Hashable, Sendable {
        var rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        static let primary = Button(rawValue: 1)
        static let secondary = Button(rawValue: 2)

        static func other(_ rawValue: Int) -> Button {
            Button(rawValue: rawValue)
        }
    }

    var timestamp: Time
    var binding: EventBinding?
    var button: Button
    var phase: EventPhase
    var location: CGPoint
    var globalLocation: CGPoint
    var modifiers: EventModifiers

    var radius: CGFloat { 0.0 }
    var kind: SpatialEvent.Kind? { .mouse }
}

struct ScrollEvent: EventType,
                    ModifiersEventType,
                    PanEventType,
                    HitTestableEventType,
                    TouchTypeProviding,
                    Equatable {
    var timestamp: Time
    var phase: EventPhase
    var binding: EventBinding?
    var translation: CGSize
    var modifiers: EventModifiers
    var hitTestLocation: CGPoint

    var globalTranslation: CGSize { translation }
    var touchType: TouchType { .indirect }
    var hitTestRadius: CGFloat { 0.0 }
}

struct HoverEvent: EventType, HitTestableEventType, NonGestureEventType, Equatable {
    var timestamp: Time
    var phase: EventPhase
    var binding: EventBinding?
    var globalLocation: CGPoint

    var hitTestLocation: CGPoint { globalLocation }
    var hitTestRadius: CGFloat { 0.0 }

    var customHitTestOptions: ViewResponder.ContainsPointsOptions? {
        [.platformDefault, .includeHoverResponders]
    }
}

struct MagnifyEvent: EventType, SpatialEventType, HitTestableEventType, Equatable {
    var timestamp: Time
    var phase: EventPhase
    var binding: EventBinding?
    var globalLocation: CGPoint
    var scaleDelta: CGFloat
    var initialScale: CGFloat

    var location: CGPoint {
        get { globalLocation }
        set { globalLocation = newValue }
    }

    var radius: CGFloat { 0.0 }
    var kind: SpatialEvent.Kind? { nil }
}

struct RotateEvent: EventType, SpatialEventType, HitTestableEventType, Equatable {
    var timestamp: Time
    var phase: EventPhase
    var binding: EventBinding?
    var globalLocation: CGPoint
    var angleDelta: Angle
    var initialAngle: Angle

    var location: CGPoint {
        get { globalLocation }
        set { globalLocation = newValue }
    }

    var radius: CGFloat { 0.0 }
    var kind: SpatialEvent.Kind? { nil }
}

struct KeyEvent: EventType, ModifiersEventType, NonGestureEventType, Equatable {
    var phase: EventPhase
    var timestamp: Time
    var binding: EventBinding?
    var modifiers: EventModifiers
    var keys: String
    var stringValue: String
    var keyID: AnyHashable
}

// GestureMask

public struct GestureMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let none = GestureMask([])
    public static let gesture = GestureMask(rawValue: 1)
    public static let subviews = GestureMask(rawValue: 2)
    public static let all = GestureMask(rawValue: 3)
    public typealias RawValue = UInt32
}

// PlatformGestureInputs

/// Platform-specific gesture inputs, reserved for recognizer bridge state.
struct PlatformGestureInputs {}

// PrimitiveGesture / PubliclyPrimitiveGesture / LayoutGesture / TappableEventType

/// Marker protocol for gestures implemented by an internal primitive route.
protocol PrimitiveGesture: Gesture {}

/// Marker protocol for gesture types that implement recognition via `body` computed property.
///
/// Body-based gesture construction is handled by the generic `Gesture`
/// implementation using `gesture[\.body]` key-path nodes, then recursing into the
/// returned modifier chain.
protocol PubliclyPrimitiveGesture: PrimitiveGesture {
    associatedtype InternalBody: Gesture where InternalBody.Value == Value
    var internalBody: InternalBody { get }
}

extension PubliclyPrimitiveGesture {
    static func makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        InternalBody._makeGesture(
            gesture: gesture[\.internalBody],
            inputs: inputs
        )
    }

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        makeGesture(gesture: gesture, inputs: inputs)
    }
}

extension StaticIf: Gesture
    where Predicate: ViewInputPredicate,
          TrueContent: Gesture,
          FalseContent: Gesture,
          TrueContent.Value == FalseContent.Value {
    typealias Body = Never
    typealias Value = TrueContent.Value

    static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Value> {
        if Predicate.evaluate(inputs: inputs.viewInputs.base) {
            return TrueContent._makeGesture(
                gesture: gesture[\.trueBody],
                inputs: inputs
            )
        }
        return FalseContent._makeGesture(
            gesture: gesture[\.falseBody],
            inputs: inputs
        )
    }
}

protocol PrimitiveDebuggableGesture: PrimitiveGesture {}

final class LayoutGestureBox {
    struct ChildRecord {
        var responder: (ViewResponder)?
        var seed: UInt32
        var events: [EventID: any EventType]
        var phase: GesturePhase<Void>
        var subgraph: AGSubgraph? = nil
        var outputs: _GestureOutputs<Void>? = nil

        func binds(_ binding: EventBinding) -> Bool {
            guard let responderNode = responder as? ResponderNode else {
                return false
            }
            if binding.responder === responderNode {
                return true
            }
            return (binding.responder as? ViewResponder)?.isDescendant(of: responderNode) ?? false
        }

        func containsGlobalLocation(_ location: CGPoint) -> Bool {
            guard let responder else {
                return false
            }
            let result = responder.containsGlobalPoints(
                [location],
                cacheKey: nil,
                options: ViewResponder.ContainsPointsOptions()
            )
            return result.mask[0]
        }
    }

    var eventBindingManager: EventBindingManager?
    private(set) var children: [ChildRecord] = []
    private(set) var generation: UInt32 = 0
    private var nextChildSeed: UInt32 = 0
    private var resetSeed: UInt32 = 0

    init(eventBindingManager: EventBindingManager? = nil) {
        self.eventBindingManager = eventBindingManager
    }

    var childCount: Int {
        children.count
    }

    func updateResetSeed(_ seed: UInt32) {
        guard resetSeed != seed else { return }
        resetSeed = seed
        if !children.isEmpty {
            for index in children.indices {
                children[index].events.removeAll()
                children[index].phase = .possible(nil)
                resetChildSubgraph(at: index)
                bumpChildSeed(at: index)
            }
        }
        bumpGeneration()
    }

    func updateResponder(_ responder: MultiViewResponder) {
        var oldChildren = children
        var newChildren: [ChildRecord] = []
        var changed = oldChildren.count != responder.children.count

        for childResponder in responder.children {
            if let oldIndex = oldChildren.firstIndex(where: { $0.responder === childResponder }) {
                var child = oldChildren.remove(at: oldIndex)
                child.responder = childResponder
                if oldIndex != newChildren.count {
                    changed = true
                }
                newChildren.append(child)
            } else {
                newChildren.append(ChildRecord(
                    responder: childResponder,
                    seed: nextSeed(),
                    events: [:],
                    phase: .possible(nil)
                ))
                changed = true
            }
        }

        if !oldChildren.isEmpty {
            for oldChild in oldChildren {
                invalidateChildSubgraph(oldChild.subgraph)
            }
            changed = true
        }
        guard changed else { return }
        children = newChildren
        bumpGeneration()
    }

    func child(at index: Int) -> LayoutGestureChildProxy.Child {
        precondition(children.indices.contains(index), "LayoutGestureChildProxy index out of range")
        return LayoutGestureChildProxy.Child(responder: children[index].responder)
    }

    func childEvents(at index: Int) -> [EventID: any EventType] {
        precondition(children.indices.contains(index), "LayoutGestureBox child index out of range")
        return children[index].events
    }

    func childEventsForRule(at index: Int) -> [EventID: any EventType] {
        guard children.indices.contains(index) else { return [:] }
        return children[index].events
    }

    func childSeed(at index: Int) -> UInt32 {
        precondition(children.indices.contains(index), "LayoutGestureBox child index out of range")
        return children[index].seed &+ resetSeed
    }

    func childSeedForRule(at index: Int) -> UInt32 {
        guard children.indices.contains(index) else {
            return 0x10000 &+ resetSeed
        }
        return children[index].seed &+ resetSeed
    }

    func childSubgraph(at index: Int) -> AGSubgraph? {
        precondition(children.indices.contains(index), "LayoutGestureBox child index out of range")
        return children[index].subgraph
    }

    func setChildSubgraph(_ subgraph: AGSubgraph?, at index: Int) {
        precondition(children.indices.contains(index), "LayoutGestureBox child index out of range")
        children[index].subgraph = subgraph
    }

    func bindChild(
        index: Int,
        event: any EventType,
        id: EventID
    ) -> (from: EventBinding?, to: EventBinding?)? {
        precondition(children.indices.contains(index), "LayoutGestureChildProxy index out of range")
        guard let eventBindingManager else {
            return nil
        }
        let child = children[index]
        let target: ResponderNode?
        if let event = event as? any HitTestableEventType {
            target = child.containsGlobalLocation(event.hitTestLocation)
                ? child.responder as? ResponderNode
                : nil
        } else {
            target = child.responder as? ResponderNode
        }

        let movement = eventBindingManager.rebindEvent(id, to: target)
        if let oldBinding = movement?.from,
           let oldIndex = children.firstIndex(where: { $0.binds(oldBinding) }) {
            bumpChildSeed(at: oldIndex)
            bumpGeneration()
        }
        return movement
    }

    func willSendEvents<G: LayoutGesture>(
        _ events: [EventID: any EventType],
        gesture: G,
        inputs: _GestureInputs? = nil,
        boxValueAttribute: Attribute<LayoutGestureBoxValue>? = nil
    ) {
        clearStoredChildEvents()
        guard !events.isEmpty else { return }

        var mutableEvents = events
        G.updateEventBindings(&mutableEvents, proxy: LayoutGestureChildProxy(box: self))
        guard !mutableEvents.isEmpty else { return }

        for index in children.indices {
            let filtered = childEvents(from: mutableEvents, index: index)
            guard !filtered.isEmpty else { continue }
            children[index].events = filtered
            bumpGeneration()
        }

        guard let inputs, let boxValueAttribute else { return }
        for index in children.indices where !children[index].events.isEmpty {
            ensureChildGesture(
                at: index,
                inputs: inputs,
                boxValueAttribute: boxValueAttribute
            )
        }
    }

    func phase() -> GesturePhase<Void> {
        var sawActive = false
        var sawEnded = false

        for index in children.indices {
            switch childPhase(at: index) {
            case .failed:
                return .failed
            case .ended:
                sawEnded = true
            case .active:
                sawActive = true
            case .possible:
                continue
            }
        }

        if sawEnded {
            return .ended(())
        }
        if sawActive {
            return .active(())
        }
        return .possible(nil)
    }

    func resetTerminalChildren() {
        var changed = false
        for index in children.indices where childPhase(at: index).isTerminal {
            children[index].phase = .possible(nil)
            children[index].events.removeAll()
            resetChildSubgraph(at: index)
            bumpChildSeed(at: index)
            changed = true
        }
        if changed {
            bumpGeneration()
        }
    }

    func setChildPhase(_ phase: GesturePhase<Void>, at index: Int) {
        precondition(children.indices.contains(index), "LayoutGestureBox child index out of range")
        children[index].phase = phase
        children[index].outputs = nil
        bumpGeneration()
    }

    func preferenceValue<K: PreferenceKey>(for key: K.Type) -> K.Value {
        var result = K.defaultValue
        var hasValue = false
        for child in children {
            guard let preferenceAttr = child.outputs?.preferences.value(for: K.self) else {
                continue
            }
            let value = Attribute<K.Value>(preferenceAttr).value
            if hasValue {
                K.reduce(value: &result) { value }
            } else {
                result = value
                hasValue = true
            }
        }
        return result
    }

    private func ensureChildGesture(
        at index: Int,
        inputs: _GestureInputs,
        boxValueAttribute: Attribute<LayoutGestureBoxValue>
    ) {
        guard children.indices.contains(index),
              children[index].outputs == nil,
              let responder = children[index].responder else {
            return
        }
        guard _AGGraph.current != nil else {
            fatalError("LayoutGestureBox.ensureChildGesture requires AG context")
        }

        let parentSubgraph = inputs.viewSubgraph
        let childSubgraph = AGSubgraph.withCurrent(parentSubgraph) {
            AGSubgraph()
        }

        guard let graph = _AGGraph.current else {
            fatalError("LayoutGestureBox.ensureChildGesture requires AG context")
        }

        let outputs = AGSubgraph.withCurrent(childSubgraph) {
            var childInputs = inputs
            childInputs.viewSubgraph = childSubgraph
            let childEvents = graph.makeRule(LayoutChildEvents(
                boxValue: boxValueAttribute,
                index: index
            ))
            let childSeed = graph.makeRule(LayoutChildSeed(
                boxValue: boxValueAttribute,
                index: index
            ))
            childInputs._events = childEvents
            childInputs._resetSeed = childSeed
            return responder.makeGesture(inputs: childInputs)
        }
        children[index].subgraph = childSubgraph
        children[index].outputs = outputs
    }

    private func childEvents(
        from events: [EventID: any EventType],
        index: Int
    ) -> [EventID: any EventType] {
        guard let eventBindingManager else { return [:] }
        let child = children[index]
        var filtered: [EventID: any EventType] = [:]
        for (eventID, event) in events {
            guard let binding = eventBindingManager.bindings[eventID],
                  child.binds(binding) else {
                continue
            }
            filtered[eventID] = event
        }
        return filtered
    }

    private func clearStoredChildEvents() {
        var changed = false
        for index in children.indices where !children[index].events.isEmpty {
            children[index].events.removeAll()
            changed = true
        }
        if changed {
            bumpGeneration()
        }
    }

    private func resetChildSubgraph(at index: Int) {
        invalidateChildSubgraph(children[index].subgraph)
        children[index].subgraph = nil
        children[index].outputs = nil
    }

    private func invalidateChildSubgraph(_ subgraph: AGSubgraph?) {
        guard let subgraph else { return }
        if let graph = _AGGraph.current, graph === subgraph.graph, AGSubgraphIsValid(subgraph) {
            subgraph.invalidate()
        }
    }

    private func nextSeed() -> UInt32 {
        defer { nextChildSeed &+= 1 }
        return nextChildSeed
    }

    private func bumpChildSeed(at index: Int) {
        children[index].seed &+= 1
    }

    private func bumpGeneration() {
        generation &+= 1
    }

    private func childPhase(at index: Int) -> GesturePhase<Void> {
        guard children.indices.contains(index) else { return .possible(nil) }
        if let outputs = children[index].outputs {
            return outputs.phase.value
        }
        return children[index].phase
    }
}

struct LayoutGestureBoxValue {
    var box: LayoutGestureBox
    var seed: UInt32
}

private struct LayoutChildEvents: Rule {
    typealias Value = [EventID: any EventType]

    var boxValue: Attribute<LayoutGestureBoxValue>
    var index: Int

    var value: [EventID: any EventType] {
        boxValue.value.box.childEventsForRule(at: index)
    }
}

private struct LayoutChildSeed: Rule {
    typealias Value = UInt32

    var boxValue: Attribute<LayoutGestureBoxValue>
    var index: Int

    var value: UInt32 {
        boxValue.value.box.childSeedForRule(at: index)
    }
}

struct LayoutGestureChildProxy: RandomAccessCollection {
    struct Child {
        var responder: (ViewResponder)?

        func binds(_ binding: EventBinding) -> Bool {
            guard let responderNode = responder as? ResponderNode else {
                return false
            }
            if binding.responder === responderNode {
                return true
            }
            return (binding.responder as? ViewResponder)?.isDescendant(of: responderNode) ?? false
        }

        func containsGlobalLocation(_ location: CGPoint) -> Bool {
            guard let responder else {
                return false
            }
            let result = responder.containsGlobalPoints(
                [location],
                cacheKey: nil,
                options: ViewResponder.ContainsPointsOptions()
            )
            return result.mask[0]
        }
    }

    typealias Index = Int
    typealias Element = Child

    private var box: LayoutGestureBox?

    init() {
        self.box = nil
    }

    init(
        responder: MultiViewResponder,
        eventBindingManager: EventBindingManager? = nil
    ) {
        let box = LayoutGestureBox(eventBindingManager: eventBindingManager)
        box.updateResponder(responder)
        self.box = box
    }

    init(box: LayoutGestureBox) {
        self.box = box
    }

    var startIndex: Int {
        0
    }

    var endIndex: Int {
        box?.childCount ?? 0
    }

    subscript(position: Int) -> Child {
        guard let box else {
            preconditionFailure("LayoutGestureChildProxy index out of range")
        }
        return box.child(at: position)
    }

    func bindChild(
        index: Int,
        event: any EventType,
        id: EventID
    ) -> (from: EventBinding?, to: EventBinding?)? {
        box?.bindChild(index: index, event: event, id: id)
    }
}

protocol LayoutGesture: PrimitiveDebuggableGesture, PrimitiveGesture where Value == Void {
    var responder: MultiViewResponder { get }

    static func updateEventBindings(
        _ eventBindings: inout [EventID: any EventType],
        proxy: LayoutGestureChildProxy
    )
}

private func currentLayoutGestureEventBindingManager() -> EventBindingManager? {
    guard let context = _AGGraphContext.current?.context else {
        return nil
    }
    if let eventGraphHost = context as? any EventGraphHost {
        return eventGraphHost.eventBindingManager
    }
    if let viewGraph = context as? ViewGraph {
        return (viewGraph.rendererHost as? WindowController)?
            .gestureGraph?
            .eventBindingManager
    }
    if let rendererHost = context as? any ViewRendererHost {
        return (rendererHost as? WindowController)?
            .gestureGraph?
            .eventBindingManager
    }
    return nil
}

private struct LayoutGestureUpdateRule<G: LayoutGesture>: StatefulRule {
    typealias Value = LayoutGestureBoxValue

    var gesture: Attribute<G>
    var events: Attribute<[EventID: any EventType]>
    var resetSeed: Attribute<UInt32>
    var inputs: _GestureInputs
    var box: LayoutGestureBox

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        let eventsChanged = _AGGraph.currentStatefulInputChanged(events.identifier)
        box.updateResetSeed(resetSeed.value)
        let gestureValue = gesture.value
        box.updateResponder(gestureValue.responder)

        if isInitialValue || eventsChanged {
            box.willSendEvents(
                events.value,
                gesture: gestureValue,
                inputs: inputs,
                boxValueAttribute: context.attribute
            )
        }

        _AGGraph.setStatefulOutput(LayoutGestureBoxValue(box: box, seed: box.generation))
    }
}

private struct LayoutGesturePreferenceCombiner<K: PreferenceKey>: Rule, AsyncAttribute {
    typealias Value = K.Value

    var boxValue: Attribute<LayoutGestureBoxValue>

    var value: K.Value {
        boxValue.value.box.preferenceValue(for: K.self)
    }
}

extension LayoutGesture {
    static func updateEventBindings(
        _ eventBindings: inout [EventID: any EventType],
        proxy: LayoutGestureChildProxy
    ) {}

    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Void> {
        guard let graph = _AGGraph.current else {
            fatalError("LayoutGesture._makeGesture requires AG context")
        }
        let box = LayoutGestureBox(eventBindingManager: currentLayoutGestureEventBindingManager())
        let update = graph.makeStatefulRule(LayoutGestureUpdateRule(
            gesture: gesture._attribute,
            events: inputs.events,
            resetSeed: inputs.resetSeed,
            inputs: inputs,
            box: box
        ))
        let phase: Attribute<GesturePhase<Void>> = graph.makeRule {
            let value = update.value
            let phase = value.box.phase()
            value.box.resetTerminalChildren()
            return phase
        }
        var outputs = _GestureOutputs(phase: phase)
        for key in inputs.preferences.keys.keys {
            func appendPreference<K: PreferenceKey>(_ key: K.Type) {
                let attr = graph.makeRule(LayoutGesturePreferenceCombiner<K>(boxValue: update))
                outputs.preferences.append(K.self, node: attr.identifier)
            }
            appendPreference(key)
        }
        return outputs
    }
}

protocol TappableEventType: EventType {}

// EventListener

/// Primitive gesture that listens for a specific EventType stream.
/// All high-level gestures (TapGesture, LongPressGesture, DragGesture) are built on top
/// of EventListener or compose it internally.
///
/// _makeGesture creates an EventListenerPhase<E> StatefulRule AG node that processes
/// incoming events and transitions the phase.
struct EventListener<E: EventType>: Gesture, PrimitiveGesture,
    PrimitiveDebuggableGesture {
    var ignoresOtherEvents: Bool

    init(ignoresOtherEvents: Bool = false) {
        self.ignoresOtherEvents = ignoresOtherEvents
    }

    // EventListener<E>.Value is the event type projected from EventListenerPhase output.
    typealias Value = E
    typealias Body = Never

    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        guard let graph = _AGGraph.current else {
            fatalError("EventListener._makeGesture requires AG context")
        }
        // Build the stateful recognizer node and expose only its phase field.
        let phase = EventListenerPhase<E>(
            _listener: gesture._attribute,
            _events: inputs.events,
            _position: inputs.position,
            _transform: inputs.transform,
            _resetSeed: inputs.resetSeed,
            preconvertedEventLocations: inputs.options.contains(.preconvertedEventLocations),
            allowsIncompleteEventSequences: inputs.options.contains(.allowsIncompleteEventSequences),
            trackingID: nil,
            lastResetSeed: 0
        )
        let valueAttr = graph.makeStatefulRule(phase)
        let outputPhase: Attribute<GesturePhase<E>> = graph.subscriptNode(
            parent: valueAttr,
            keyPath: \.phase
        )
        return _GestureOutputs(phase: outputPhase)
    }
}

// ResettableGestureRule
//
// Sub-protocol of StatefulRule. Standardises the gesture session reset mechanism.
// Adopted by EventListenerPhase and CallbacksPhase.

protocol ResettableGestureRule: StatefulRule {
    /// Generic parameter: the phase value type (E, V, Double, etc.).
    associatedtype PhaseValue
    /// Current gesture session seed (UInt32 value, NOT an Attribute).
    var resetSeed: UInt32 { get }
    /// Last seed value processed by this rule.
    var lastResetSeed: UInt32 { get set }
    /// Current output phase read from the AG node's cached stateful output.
    var phaseValue: GesturePhase<PhaseValue> { get }
    /// Resets the gesture phase to its initial state (.possible(nil)).
    mutating func resetPhase()
}

extension ResettableGestureRule where Value == GesturePhase<PhaseValue> {
    /// Default phaseValue implementation for conformers whose Value IS GesturePhase<PhaseValue>.
    /// Reads the previous stateful output directly from the AG node cache.
    var phaseValue: GesturePhase<PhaseValue> {
        _AGGraph.currentStatefulOutput() ?? .possible(nil)
    }
}

extension ResettableGestureRule {
    /// Compares the current seed against lastResetSeed to determine whether a reset is needed.
    ///
    /// Reset algorithm:
    ///   defer { lastResetSeed = resetSeed }
    ///   if lastResetSeed == resetSeed: return !phaseValue.isTerminal
    ///   else: resetPhase(); return true
    ///
    /// - Returns: true if updateValue should proceed with normal processing.
    ///            false if the current output is already terminal (skip re-evaluation).
    mutating func resetIfNeeded() -> Bool {
        let currentSeed = resetSeed
        defer { lastResetSeed = currentSeed }
        if lastResetSeed == currentSeed {
            return !phaseValue.isTerminal
        }
        resetPhase()
        return true
    }
}

// EventListenerPhase<E>: StatefulRule
//
// Low-level AG node that processes raw events for EventListener<E>.
// Reads eventsAttr (filtered by E type), applies position/transform geometry,
// and drives the EventListenerPhase.Value output.
struct EventListenerPhase<E: EventType>: StatefulRule, ResettableGestureRule,
    CustomStringConvertible
{

    enum FailureReason: Equatable, Hashable {
        case rebound
        case eventArrivedMidstream
        case multipleMatchingEvents
        case unexpectedEvent
        case eventFailed
    }

    struct Value {
        var phase: GesturePhase<E>
        var trackingID: EventID?
        var failureReason: FailureReason?
    }

    var _listener: Attribute<EventListener<E>>
    var _events: Attribute<[EventID: any EventType]>
    var _position: Attribute<CGPoint>
    var _transform: Attribute<ViewTransform>
    var _resetSeed: Attribute<UInt32>
    var preconvertedEventLocations: Bool
    var allowsIncompleteEventSequences: Bool
    var trackingID: EventID?
    var lastResetSeed: UInt32

    typealias PhaseValue = E
    var resetSeed: UInt32 { _resetSeed.value }
    var phaseValue: GesturePhase<E> {
        (_AGGraph.currentStatefulOutput(Value.self))?.phase ?? .possible(nil)
    }

    mutating func updateValue() {
        // Reset stale tracked state before processing the current event dictionary.
        guard resetIfNeeded() else { return }
        let events = _events.value
        let output: Value

        // Helper: convert event's global location to local view coordinates (when not pre-converted).
        // preconvertedBool=true skips this (events already in local coords).
        func localised(_ event: E) -> E {
            guard !preconvertedEventLocations,
                  var spatialEvent = event as? any SpatialEventType else {
                return event
            }
            var pts = [spatialEvent.globalLocation]
            var transform = _transform.value
            transform.appendPosition(_position.value)
            transform.convertGlobal(to: .local, points: &pts)
            spatialEvent.location = pts[0]
            return E(spatialEvent) ?? event
        }

        if let tid = trackingID {
            if let sourceEvent = events[tid], let event = E(sourceEvent) {
                switch event.phase {
                case .began, .active:
                    output = Value(phase: .active(localised(event)), trackingID: tid, failureReason: nil)
                case .ended:
                    trackingID = nil
                    output = Value(phase: .ended(localised(event)), trackingID: nil, failureReason: nil)
                case .failed:
                    trackingID = nil
                    output = Value(phase: .failed, trackingID: nil, failureReason: nil)
                }
            } else {
                // Treat a missing tracked event as implicit cancellation.
                trackingID = nil
                output = Value(phase: .failed, trackingID: nil, failureReason: nil)
            }
        } else {
            // Search for a new began event
            var found: (EventID, E)?
            for (id, event) in events {
                if let typed = E(event), typed.phase == .began {
                    found = (id, typed)
                    break
                }
            }
            if let (id, event) = found {
                trackingID = id
                output = Value(phase: .active(localised(event)), trackingID: id, failureReason: nil)
            } else {
                output = Value(phase: .possible(nil), trackingID: nil, failureReason: nil)
            }
        }
        _AGGraph.setStatefulOutput(output)
    }

    mutating func resetPhase() {
        trackingID = nil
        _AGGraph.setStatefulOutput(Value(phase: .possible(nil), trackingID: nil, failureReason: nil))
    }

    var description: String {
        var description = "Listener[\(E.self)]"
        if let trackingID {
            description += " \(trackingID)"
        }
        return description
    }
}

// _GestureInputs

/// Inputs passed to `Gesture._makeGesture`.
///
/// Stored fields carry view inputs, event/time/reset attributes, inherited combiner
/// phase, gesture preferences, traversal options, and platform-specific inputs.
/// Computed accessors expose the derived environment and geometry attributes.
public struct _GestureInputs {

    // InheritedPhase

    /// Phase state inherited from ancestor gesture combiners (e.g. ExclusiveGesture).
    struct InheritedPhase: OptionSet, Defaultable, Sendable, CustomStringConvertible {
        var rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }
        /// bit0: a parent/sibling gesture has failed, so this gesture may proceed.
        static let failed = InheritedPhase(rawValue: 1)   // bit 0
        /// bit1: a parent/sibling gesture is active, so this gesture must wait.
        static let active = InheritedPhase(rawValue: 2)   // bit 1
        /// Default value: .failed (= 1). "Nobody is blocking" = proceed allowed.
        static var defaultValue: InheritedPhase { .failed }
        var description: String {
            var parts: [String] = []
            if contains(.failed) { parts.append("failed") }
            if contains(.active) { parts.append("active") }
            return "[\(parts.joined(separator: ", "))]"
        }
    }

    // Options

    /// Flags controlling gesture graph traversal and dispatch behaviour.
    /// Reserved bit assignments:
    ///   preconvertedEventLocations=0x01, allowsIncompleteEventSequences=0x02,
    ///   skipCombiners=0x04, includeDebugOutput=0x08, gestureGraph=0x10, hasChangedCallbacks=0x20
    struct Options: OptionSet, Sendable {
        var rawValue: UInt32
        init(rawValue: UInt32) { self.rawValue = rawValue }
        static let preconvertedEventLocations    = Options(rawValue: 0x01)  // bit 0
        static let allowsIncompleteEventSequences = Options(rawValue: 0x02) // bit 1
        static let skipCombiners                 = Options(rawValue: 0x04)  // bit 2
        static let includeDebugOutput            = Options(rawValue: 0x08)  // bit 3
        static let gestureGraph                  = Options(rawValue: 0x10)  // bit 4
        static let hasChangedCallbacks           = Options(rawValue: 0x20)  // bit 5
    }

    // Stored Properties

    /// The view inputs from which this gesture input is derived.
    var viewInputs: _ViewInputs

    /// The view subgraph that owns gesture construction for view-responder shells.
    var viewSubgraph: AGSubgraph?

    /// AG attribute holding the current event dictionary.
    var _events: Attribute<[EventID: any EventType]>

    /// AG attribute carrying animation time from the enclosing view inputs.
    var _time: Attribute<Time>

    /// AG attribute for gesture recognizer reset seed counter.
    var _resetSeed: Attribute<UInt32>

    /// AG attribute for phase state inherited from parent gesture combiners.
    var _inheritedPhase: Attribute<InheritedPhase>

    /// Preference key tracking for gestures (includes gesture-registered keys).
    var preferences: PreferencesInputs

    /// Traversal / dispatch option flags.
    var options: Options

    /// Platform-specific inputs.
    var platformInputs: PlatformGestureInputs

    // Computed Properties

    /// The environment values attribute (derived from viewInputs).
    var environment: Attribute<EnvironmentValues> {
        viewInputs.base.cachedEnvironment.value.environment
    }

    /// The view's proposed size attribute.
    var size: Attribute<ViewSize> { viewInputs.size }

    /// The view's position attribute (parent-local coords).
    var position: Attribute<CGPoint> { viewInputs.position }

    /// The cumulative coordinate transform for this view.
    var transform: Attribute<ViewTransform> { viewInputs.transform }

    /// The current event dictionary attribute.
    var events: Attribute<[EventID: any EventType]> { _events }

    /// The animation time attribute.
    var time: Attribute<Time> { _time }

    /// The gesture reset seed attribute.
    var resetSeed: Attribute<UInt32> { _resetSeed }

    /// The inherited phase attribute.
    var inheritedPhase: Attribute<InheritedPhase> { _inheritedPhase }

    // Init

    /// Designated initializer.
    init(
        _ viewInputs: _ViewInputs,
        viewSubgraph: AGSubgraph?,
        events: Attribute<[EventID: any EventType]>,
        time: Attribute<Time>,
        resetSeed: Attribute<UInt32>,
        inheritedPhase: Attribute<InheritedPhase>,
        gesturePreferenceKeys: Attribute<PreferenceKeys>
    ) {
        self.viewInputs = viewInputs
        self.viewSubgraph = viewSubgraph
        self._events = events
        self._time = time
        self._resetSeed = resetSeed
        self._inheritedPhase = inheritedPhase
        self.preferences = PreferencesInputs(keys: PreferenceKeys(), hostKeys: gesturePreferenceKeys)
        self.options = []
        self.platformInputs = PlatformGestureInputs()
    }

    // Factory Methods

    /// Creates a default (no-op) gesture outputs: phase = .possible(nil), empty preferences.
    func makeDefaultOutputs<A>() -> _GestureOutputs<A> {
        guard let graph = _AGGraph.current else {
            fatalError("_GestureInputs.makeDefaultOutputs requires AG context")
        }
        let phase: Attribute<GesturePhase<A>> = graph.makeRule(DefaultRule<GesturePhase<A>>())
        var outputs = _GestureOutputs(phase: phase)
        outputs.preferences = preferences.makeIndirectOutputs()
        return outputs
    }

    /// Creates indirect (lazy) outputs backed by a forward reference that can be wired up later.
    func makeIndirectOutputs<A>() -> _GestureOutputs<A> {
        guard let graph = _AGGraph.current else {
            fatalError("_GestureInputs.makeIndirectOutputs requires AG context")
        }
        let phase = graph.makeIndirectAttribute(
            defaultValue: GesturePhase<A>.defaultValue
        )
        var outputs = _GestureOutputs(phase: phase)
        outputs.preferences = preferences.makeIndirectOutputs()
        return outputs
    }
}

// _GestureOutputs

/// Outputs produced by `Gesture._makeGesture`.
///
/// Carries the phase attribute and preference outputs.
public struct _GestureOutputs<V> {
    /// The AG attribute that delivers the current phase of this gesture.
    var phase: Attribute<GesturePhase<V>>

    /// Preference outputs produced by this gesture graph (e.g., accessibility, debug).
    var preferences: PreferencesOutputs

    init(phase: Attribute<GesturePhase<V>>) {
        self.phase = phase
        self.preferences = PreferencesOutputs()
    }

    /// Returns a copy of this output with a different phase attribute.
    func withPhase<A>(_ newPhase: Attribute<GesturePhase<A>>) -> _GestureOutputs<A> {
        var out = _GestureOutputs<A>(phase: newPhase)
        out.preferences = self.preferences
        return out
    }

    mutating func appendPreference<K: PreferenceKey>(key: K.Type, value: Attribute<K.Value>) {
        preferences.append(K.self, node: value.identifier)
    }

    mutating func setIndirectDependency(_ attr: AGAttribute?) {
        guard let attr, let graph = _AGGraph.current else { return }
        graph.setIndirectDependency(phase.identifier, dependsOn: attr)
        preferences.setIndirectDependency(attr)
    }

    func attachIndirectOutputs(_ outputs: _GestureOutputs<V>) {
        guard let graph = _AGGraph.current else {
            fatalError("_GestureOutputs.attachIndirectOutputs requires AG context")
        }
        graph.setIndirectTarget(outputs.phase, to: phase)
        preferences.attachIndirectOutputs(to: outputs.preferences)
    }

    func detachIndirectOutputs() {
        guard let graph = _AGGraph.current else {
            fatalError("_GestureOutputs.detachIndirectOutputs requires AG context")
        }
        graph.setIndirectTarget(phase.identifier, to: nil)
        preferences.detachIndirectOutputs()
    }
}
