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

extension Optional: GestureEventTypeAccepting where Wrapped: Gesture {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        gestureTypeAcceptsEvent(Wrapped.self, eventType: eventType)
    }
}

extension Optional: DynamicGestureEventTypeAccepting where Wrapped: Gesture {
    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        switch self {
        case .some(let wrapped):
            return gestureValueAcceptsEvent(wrapped, eventType: eventType)
        case .none:
            return gestureTypeAcceptsEvent(Wrapped.self, eventType: eventType)
        }
    }
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

extension GesturePhase {
    /// The default phase: waiting for input, no pre-computed value.
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
enum EventPhase: UInt8 {
    case began     = 0
    case moved     = 1
    case ended     = 2
    case cancelled = 3
}

/// Base protocol for all event payloads carried in the event dictionary.
protocol EventType {
    /// The lifecycle phase of this event.
    var eventPhase: EventPhase { get }
    /// The global position of this event, if applicable.
    /// Mutable so coordinate-space gestures can create transformed copies.
    var location: CGPoint? { get set }
}

protocol ModifiersEventType: EventType {
    var modifiers: EventModifiers { get }
}

protocol GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool
}

protocol DynamicGestureEventTypeAccepting {
    func acceptsEventType(_ eventType: Any.Type) -> Bool
}

func gestureTypeAcceptsEvent<G: Gesture>(
    _ gestureType: G.Type,
    eventType: Any.Type
) -> Bool {
    guard let accepting = gestureType as? any GestureEventTypeAccepting.Type else {
        return true
    }
    return accepting.acceptsEventType(eventType)
}

func gestureValueAcceptsEvent<G: Gesture>(
    _ gesture: G,
    eventType: Any.Type
) -> Bool {
    if let accepting = gesture as? any DynamicGestureEventTypeAccepting {
        return accepting.acceptsEventType(eventType)
    }
    return gestureTypeAcceptsEvent(G.self, eventType: eventType)
}

/// Represents a tap/click interaction on desktop (mouse button press).
struct TappableEvent: EventType {
    var location: CGPoint?
    var eventPhase: EventPhase
    var buttonID: Int

    init(location: CGPoint, phase: EventPhase, buttonID: Int = 0) {
        self.location = location
        self.eventPhase = phase
        self.buttonID = buttonID
    }
}

// EventType refinement for spatial pointer/touch events.
// location stays Optional through EventType, but spatial events are expected to fill it.
protocol SpatialEventType: EventType {
    var globalLocation: CGPoint { get set }
    var radius: CGFloat { get }
    var kind: SpatialEvent.Kind? { get }
}

// Spatial event payload used by primitive spatial gesture chains.
// Separate from TappableEvent because it carries spatial kind, radius, and global location.
struct SpatialEvent: EventType, SpatialEventType, Equatable {
    // nil kind is used as the unclassified/default sentinel.
    enum Kind: UInt8, Hashable, Equatable {
        case pointer = 1  // mouse/trackpad pointer
        case touch   = 2  // direct touch (finger/pencil)
    }

    // EventType requirement
    var location: CGPoint?          // always non-nil for spatial events
    // SpatialEventType requirements
    var globalLocation: CGPoint
    var radius: CGFloat
    var kind: Kind?
    // Common EventType fields
    var eventPhase: EventPhase

    var timestamp: Double              // event timestamp (seconds)

    init(location: CGPoint?, globalLocation: CGPoint, phase: EventPhase,
         timestamp: Double = 0.0, kind: Kind? = nil, radius: CGFloat = 0.0) {
        self.location = location
        self.globalLocation = globalLocation
        self.eventPhase = phase
        self.timestamp = timestamp
        self.kind = kind
        self.radius = radius
    }

    static func == (lhs: SpatialEvent, rhs: SpatialEvent) -> Bool {
        lhs.location == rhs.location &&
        lhs.globalLocation == rhs.globalLocation &&
        lhs.eventPhase == rhs.eventPhase &&
        lhs.radius == rhs.radius &&
        lhs.kind == rhs.kind
    }
}

struct ScrollEvent: EventType, ModifiersEventType, Equatable {
    var delta: CGSize
    var translation: CGSize
    var previousTranslation: CGSize
    var location: CGPoint?
    var eventPhase: EventPhase
    var modifiers: EventModifiers

    init(
        delta: CGSize,
        translation: CGSize,
        previousTranslation: CGSize,
        location: CGPoint,
        phase: EventPhase,
        modifiers: EventModifiers = []
    ) {
        self.delta = delta
        self.translation = translation
        self.previousTranslation = previousTranslation
        self.location = location
        self.eventPhase = phase
        self.modifiers = modifiers
    }
}

struct HoverEvent: EventType, ModifiersEventType, Equatable {
    var location: CGPoint?
    var eventPhase: EventPhase
    var modifiers: EventModifiers
    var deviceID: Int

    init(
        location: CGPoint,
        phase: EventPhase,
        deviceID: Int,
        modifiers: EventModifiers = []
    ) {
        self.location = location
        self.eventPhase = phase
        self.deviceID = deviceID
        self.modifiers = modifiers
    }
}

struct MagnifyEvent: EventType, ModifiersEventType, Equatable {
    var magnification: CGFloat
    var previousMagnification: CGFloat
    var location: CGPoint?
    var eventPhase: EventPhase
    var modifiers: EventModifiers
    var timestamp: Double

    init(
        magnification: CGFloat,
        previousMagnification: CGFloat,
        location: CGPoint,
        phase: EventPhase,
        timestamp: Double,
        modifiers: EventModifiers = []
    ) {
        self.magnification = magnification
        self.previousMagnification = previousMagnification
        self.location = location
        self.eventPhase = phase
        self.timestamp = timestamp
        self.modifiers = modifiers
    }
}

struct RotateEvent: EventType, ModifiersEventType, Equatable {
    var rotation: Angle
    var previousRotation: Angle
    var location: CGPoint?
    var eventPhase: EventPhase
    var modifiers: EventModifiers
    var timestamp: Double

    init(
        rotation: Angle,
        previousRotation: Angle,
        location: CGPoint,
        phase: EventPhase,
        timestamp: Double,
        modifiers: EventModifiers = []
    ) {
        self.rotation = rotation
        self.previousRotation = previousRotation
        self.location = location
        self.eventPhase = phase
        self.timestamp = timestamp
        self.modifiers = modifiers
    }
}

struct KeyEvent: EventType, ModifiersEventType {
    var key: KeyEquivalent?
    var virtualKey: VirtualKey
    var characters: String
    var location: CGPoint?
    var eventPhase: EventPhase
    var modifiers: EventModifiers

    init(
        key: KeyEquivalent?,
        virtualKey: VirtualKey,
        characters: String,
        phase: EventPhase,
        modifiers: EventModifiers = []
    ) {
        self.key = key
        self.virtualKey = virtualKey
        self.characters = characters
        self.location = nil
        self.eventPhase = phase
        self.modifiers = modifiers
    }
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
protocol PubliclyPrimitiveGesture: PrimitiveGesture {}

protocol PrimitiveDebuggableGesture: PrimitiveGesture {}

struct LayoutGestureChildProxy {}

protocol LayoutGesture: PrimitiveGesture where Value == Void {}

extension LayoutGesture {
    static func updateEventBindings(
        _ eventBindings: inout [EventID: any EventType],
        proxy: LayoutGestureChildProxy
    ) {}

    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Void> {
        inputs.makeDefaultOutputs()
    }
}

/// Protocol for tap/click event types that carry a button identifier.
protocol TappableEventType: EventType {
    var buttonID: Int { get }
}

extension TappableEvent: TappableEventType {}

// EventListener

/// Primitive gesture that listens for a specific EventType stream.
/// All high-level gestures (TapGesture, LongPressGesture, DragGesture) are built on top
/// of EventListener or compose it internally.
///
/// _makeGesture creates an EventListenerPhase<E> StatefulRule AG node that processes
/// incoming events and transitions the phase.
struct EventListener<E: EventType>: Gesture {
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
            listenerAttr: gesture._attribute,
            eventsAttr: inputs.events,
            positionAttr: inputs.position,
            transformAttr: inputs.transform,
            resetSeedAttr: inputs.resetSeed,
            preconvertedBool: inputs.options.contains(.preconvertedEventLocations),
            ignoresOtherEvents: false,
            trackingID: nil,
            lastResetSeed: 0
        )
        let valueAttr = graph.makeStatefulRule(phase)
        let phaseAttr: Attribute<GesturePhase<E>> = graph.subscriptNode(parent: valueAttr, keyPath: \.phase)
        return _GestureOutputs(phase: phaseAttr)
    }
}

extension EventListener: GestureEventTypeAccepting {
    static func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == E.self
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
struct EventListenerPhase<E: EventType>: StatefulRule, ResettableGestureRule {

    // Failure causes carried by EventListenerPhase output. The error payload cannot
    // participate in Equatable/Hashable synthesis, so conformance is manual.
    enum FailureReason: Equatable, Hashable {
        case excluded
        case failureDependency(on: AnyHashable)
        case error(Error)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.excluded, .excluded): return true
            case (.failureDependency(let a), .failureDependency(let b)): return a == b
            case (.error, .error): return true
            default: return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .excluded:
                hasher.combine(0)
            case .failureDependency(let v):
                hasher.combine(1)
                hasher.combine(v)
            case .error:
                hasher.combine(2)
            }
        }
    }

    // StatefulRule.Value = EventListenerPhase<E>.Value
    struct Value: Equatable {
        var phase: GesturePhase<E>
        var trackingID: EventID?
        var failureReason: FailureReason?

        // GesturePhase<E> has no E: Equatable constraint, so auto-synthesis is unavailable.
        // Compare cases only; payload equality is not available here.
        static func == (lhs: Self, rhs: Self) -> Bool {
            guard lhs.trackingID == rhs.trackingID,
                  lhs.failureReason == rhs.failureReason else { return false }
            switch (lhs.phase, rhs.phase) {
            case (.possible, .possible), (.active, .active), (.ended, .ended), (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }

    // Stateful rule inputs and local tracking state.
    let listenerAttr: Attribute<EventListener<E>>           // reactive ignoresOtherEvents source
    let eventsAttr: Attribute<[EventID: any EventType]>     // raw event dictionary
    let positionAttr: Attribute<CGPoint>                    // animated position
    let transformAttr: Attribute<ViewTransform>             // view transform
    let resetSeedAttr: Attribute<UInt32>                    // gesture session seed
    let preconvertedBool: Bool                              // skip transform step when true
    let ignoresOtherEvents: Bool                            // ignore events from other streams
    var trackingID: EventID?                                // currently tracked EventID
    var lastResetSeed: UInt32                               // last processed reset seed

    // ResettableGestureRule conformance
    typealias PhaseValue = E
    var resetSeed: UInt32 { resetSeedAttr.value }
    // phaseValue: EventListenerPhase.Value != GesturePhase<E>, so no default impl applies.
    // Read previous stateful output and extract the .phase field.
    var phaseValue: GesturePhase<E> {
        (_AGGraph.currentStatefulOutput() as Value?)?.phase ?? .possible(nil)
    }

    mutating func updateValue() {
        // Reset stale tracked state before processing the current event dictionary.
        guard resetIfNeeded() else { return }
        let events = eventsAttr.value
        let output: Value

        // Helper: convert event's global location to local view coordinates (when not pre-converted).
        // preconvertedBool=true skips this (events already in local coords).
        func localised(_ event: E) -> E {
            guard !preconvertedBool, let globalLoc = event.location else { return event }
            var e = event
            var pts = [globalLoc]
            transformAttr.value.convertGlobal(to: .local, points: &pts)
            e.location = pts[0]
            return e
        }

        if let tid = trackingID {
            if let event = events[tid] as? E {
                switch event.eventPhase {
                case .began, .moved:
                    output = Value(phase: .active(localised(event)), trackingID: tid, failureReason: nil)
                case .ended:
                    trackingID = nil
                    output = Value(phase: .ended(localised(event)), trackingID: nil, failureReason: nil)
                case .cancelled:
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
                if let typed = event as? E, typed.eventPhase == .began {
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
    struct InheritedPhase: OptionSet, Sendable, CustomStringConvertible {
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

    /// AG attribute for animation time (mirrors _ViewInputs.base.time).
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
        let phase: Attribute<GesturePhase<A>> = graph.makeInput(value: .possible(nil))
        return _GestureOutputs(phase: phase)
    }

    /// Creates indirect (lazy) outputs backed by a forward reference that can be wired up later.
    func makeIndirectOutputs<A>() -> _GestureOutputs<A> {
        guard let graph = _AGGraph.current else {
            fatalError("_GestureInputs.makeIndirectOutputs requires AG context")
        }
        let phase: Attribute<GesturePhase<A>> = graph.makeInput(value: .possible(nil))
        return _GestureOutputs(phase: phase)
    }
}

// _GestureOutputs

/// Outputs produced by `Gesture._makeGesture`.
///
/// Carries the phase attribute, preference outputs, and optional debug data.
public struct _GestureOutputs<V> {
    /// The AG attribute that delivers the current phase of this gesture.
    var phase: Attribute<GesturePhase<V>>

    /// Preference outputs produced by this gesture graph (e.g., accessibility, debug).
    var preferences: PreferencesOutputs

    /// Optional debug data attribute.
    var debugData: Attribute<_ViewDebug.Data>?

    init(phase: Attribute<GesturePhase<V>>) {
        self.phase = phase
        self.preferences = PreferencesOutputs()
        self.debugData = nil
    }

    /// Returns a copy of this output with a different phase attribute.
    func withPhase<A>(_ newPhase: Attribute<GesturePhase<A>>) -> _GestureOutputs<A> {
        var out = _GestureOutputs<A>(phase: newPhase)
        out.preferences = self.preferences
        out.debugData = self.debugData
        return out
    }

    mutating func appendPreference<K: PreferenceKey>(key: K.Type, value: Attribute<K.Value>) {
        preferences.append(K.self, node: value.identifier)
    }

    mutating func setIndirectDependency(_ attr: AGAttribute?) {
        // No-op for direct (non-lazy) instantiation.
    }
}
