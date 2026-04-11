//
//  File: Gesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

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
        if case .active = self { return true }
        return false
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
        case .possible(let v): return v
        case .active(let v): return v
        case .ended(let v): return v
        case .failed: return nil
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
    public static var defaultValue: GesturePhase<V> { .possible(nil) }

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

/// Base protocol for all event payloads carried in the event dictionary.
protocol EventType {}

/// Represents a tap/click interaction on desktop (mouse button press).
struct TappableEvent: EventType {
    enum Phase { case began, moved, ended, cancelled }
    var location: CGPoint
    var phase: Phase
    var buttonID: Int

    init(location: CGPoint, phase: Phase, buttonID: Int = 0) {
        self.location = location
        self.phase = phase
        self.buttonID = buttonID
    }
}

/// Represents a pan/drag interaction (continuous positional movement).
struct PanEvent: EventType {
    var translation: CGSize
    var globalTranslation: CGSize
    var location: CGPoint
    var velocity: CGSize

    init(translation: CGSize, globalTranslation: CGSize, location: CGPoint, velocity: CGSize = .zero) {
        self.translation = translation
        self.globalTranslation = globalTranslation
        self.location = location
        self.velocity = velocity
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

/// Platform-specific gesture inputs. Empty for VUI (no UIKit/AppKit gesture recognizer pipeline).
struct PlatformGestureInputs {}

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

    typealias Value = Void
    typealias Body = Never

    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("EventListener._makeGesture requires AG context")
        }
        let phase: Attribute<GesturePhase<Value>> = graph.makeInput(value: .possible(nil))
        return _GestureOutputs(phase: phase)
    }
}

// ResettableGestureRule
//
// StatefulRule subprotocol that standardizes the gesture session reset mechanism.
// Adopted by EventListenerPhase and CallbacksPhase.
protocol ResettableGestureRule: StatefulRule {
    /// AG node for the gesture session seed. Changes when a new session starts.
    var resetSeedAttr: Attribute<UInt32> { get }
    /// Last processed seed stored on the instance.
    var lastResetSeed: UInt32 { get set }
    /// Resets the gesture phase to its initial state, `.possible(nil)`.
    mutating func resetPhase()
}

extension ResettableGestureRule {
    /// Checks whether a reset is needed by comparing the current seed with lastResetSeed.
    ///
    /// - Returns: true if updateValue should continue processing.
    ///            false if the session has already ended and should be skipped.
    mutating func resetIfNeeded() -> Bool {
        let currentSeed = resetSeedAttr.value
        if lastResetSeed == currentSeed {
            // Same session: skip if the phase is already .ended or .failed.
            return true
        }
        // New session: reset state.
        resetPhase()
        lastResetSeed = currentSeed
        return true
    }
}

// EventListenerPhase<E>: StatefulRule
//
// Low-level AG node that processes raw events for EventListener<E>.
// Reads eventsAttr (filtered by E type), applies position/transform geometry,
// and drives the EventListenerPhase.Value output.
struct EventListenerPhase<E: EventType>: StatefulRule, ResettableGestureRule {

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

    // StatefulRule.Value = EventListenerPhase<E>.Value, not GesturePhase<Void>.
    // EventListener.Value is Void, so phase is GesturePhase<Void>.
    struct Value: Equatable {
        var phase: GesturePhase<Void>
        var trackingID: EventID?
        var failureReason: FailureReason?

        // GesturePhase<Void> requires Void: Equatable, so synthesized Equatable is unavailable.
        // Implement equality manually.
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

    let listenerAttr: Attribute<EventListener<E>>
    let eventsAttr: Attribute<[EventID: any EventType]>
    let positionAttr: Attribute<CGPoint>
    let transformAttr: Attribute<ViewTransform>
    let resetSeedAttr: Attribute<UInt32>
    let preconvertedBool: Bool
    let ignoresOtherEvents: Bool

    var trackingID: EventID?
    var lastResetSeed: UInt32

    mutating func updateValue() {
        // updateValue() centers on creating and updating GestureComponentResponder<TapComponent<MouseEvent>>.
        // Full implementation requires Gestures.framework integration, so this remains a stub.
        // Flow: resetIfNeeded -> iterate eventsAttr -> filter TappableEvent -> GestureComponentResponder.
        guard resetIfNeeded() else { return }
    }

    mutating func resetPhase() {
        // Clear trackingID and reset the output to .possible(nil).
        trackingID = nil
        AttributeGraph.setStatefulOutput(Value(phase: .possible(nil), trackingID: nil, failureReason: nil))
    }
}

// _GestureInputs
/// Inputs passed to `Gesture._makeGesture`.
public struct _GestureInputs {

    // InheritedPhase

    /// Phase state inherited from ancestor gesture combiners, such as ExclusiveGesture.
    struct InheritedPhase: OptionSet, Sendable, CustomStringConvertible {
        var rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }
        /// bit0: parent/sibling gesture failed, so this gesture may proceed ("allowed").
        static let failed = InheritedPhase(rawValue: 1)   // bit 0
        /// bit1: parent/sibling gesture is active, so this gesture must wait ("blocked").
        static let active = InheritedPhase(rawValue: 2)   // bit 1
        /// Default value: .failed (= 1). No active blocker means this gesture may proceed.
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

    /// Platform-specific inputs (empty on VUI).
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
        self._events = events
        self._time = time
        self._resetSeed = resetSeed
        self._inheritedPhase = inheritedPhase
        self.preferences = PreferencesInputs(keys: PreferenceKeys(), hostKeys: gesturePreferenceKeys)
        self.options = []
        self.platformInputs = PlatformGestureInputs()
        _ = viewSubgraph // captured for AG subgraph registration (stored opaquely)
    }

    // Factory Methods

    /// Creates a default (no-op) gesture outputs: phase = .possible(nil), empty preferences.
    func makeDefaultOutputs<A>() -> _GestureOutputs<A> {
        guard let graph = AttributeGraph.current else {
            fatalError("_GestureInputs.makeDefaultOutputs requires AG context")
        }
        let phase: Attribute<GesturePhase<A>> = graph.makeInput(value: .possible(nil))
        return _GestureOutputs(phase: phase)
    }

    /// Creates indirect (lazy) outputs backed by a forward reference that can be wired up later.
    func makeIndirectOutputs<A>() -> _GestureOutputs<A> {
        guard let graph = AttributeGraph.current else {
            fatalError("_GestureInputs.makeIndirectOutputs requires AG context")
        }
        let phase: Attribute<GesturePhase<A>> = graph.makeInput(value: .possible(nil))
        return _GestureOutputs(phase: phase)
    }
}

// _GestureOutputs

/// Outputs produced by `Gesture._makeGesture`.
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
    }
}
