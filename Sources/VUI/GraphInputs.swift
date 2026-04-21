//
//  File: GraphInputs.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// PropertyKey hierarchy
//
// PropertyKey (PropertyList.swift): base defaultValue and valuesEqual.
// GraphInput: adds AG reuse support.
// ViewInput: marker for keys stored in _ViewInputs.customInputs.

/// Opaque map passed to GraphReusable methods.
/// AG reuse optimization not yet implemented.
struct IndirectAttributeMap {}

/// Protocol for values that support AG node reuse.
protocol GraphReusable {
    mutating func makeReusable(indirectMap: IndirectAttributeMap)
    mutating func tryToReuse(by other: Self, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool
    static var isTriviallyReusable: Bool { get }
}

extension GraphReusable {
    mutating func makeReusable(indirectMap: IndirectAttributeMap) {}
    mutating func tryToReuse(by other: Self, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool { false }
    static var isTriviallyReusable: Bool { false }
}

/// Refinement of PropertyKey that participates in AG node reuse.
/// Keys conforming to GraphInput can be stored in _GraphInputs.customInputs (base channel).
protocol GraphInput: PropertyKey {
    static func makeReusable(indirectMap: IndirectAttributeMap, value: inout Value)
    static func tryToReuse(_ a: Value, by b: Value, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool
    static var isTriviallyReusable: Bool { get }
}

extension GraphInput {
    static func makeReusable(indirectMap: IndirectAttributeMap, value: inout Value) {}
    static func tryToReuse(_ a: Value, by b: Value, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool { false }
    static var isTriviallyReusable: Bool { false }
}

extension GraphInput where Value: GraphReusable {
    static func makeReusable(indirectMap: IndirectAttributeMap, value: inout Value) {
        value.makeReusable(indirectMap: indirectMap)
    }
    static func tryToReuse(_ a: Value, by b: Value, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool {
        var copy = a
        return copy.tryToReuse(by: b, indirectMap: indirectMap, testOnly: testOnly)
    }
    static var isTriviallyReusable: Bool { Value.isTriviallyReusable }
}

/// Marker refinement of GraphInput for view-level channel.
/// Keys conforming to ViewInput are stored in _ViewInputs.customInputs (view channel).
/// No additional requirements.
protocol ViewInput: GraphInput {}

/// A generic single-owner reference box.
/// Used in `_GraphInputs.cachedEnvironment` so that copying `_GraphInputs`
/// (a struct) still shares the same `CachedEnvironment` instance across
/// all descendants of the same view subtree.
final class MutableBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// Animation time value passed through the AG graph.
struct Time {
    var seconds: Double

    static var zero: Time { Time(seconds: 0) }
    static var infinity: Time { Time(seconds: Double.infinity) }
    static var systemUptime: Time { Time(seconds: ProcessInfo.processInfo.systemUptime) }

    init(seconds: Double = 0) { self.seconds = seconds }

    static func + (lhs: Time, rhs: Double) -> Time { Time(seconds: lhs.seconds + rhs) }
    static func - (lhs: Time, rhs: Double) -> Double { lhs.seconds - rhs }
    static func < (lhs: Time, rhs: Time) -> Bool { lhs.seconds < rhs.seconds }
    static func == (lhs: Time, rhs: Time) -> Bool { lhs.seconds == rhs.seconds }
}

/// Render phase passed through the AG graph.
struct Phase {
    var isBeingRemoved: Bool = false
    var resetSeed: UInt32 = 0

    var isInserted: Bool { !isBeingRemoved && resetSeed != 0 }

    static var invalid: Phase { Phase() }

    init() {}
    init(value: UInt32) {
        self.resetSeed = value
    }

    mutating func merge(_ other: Phase) {
        if other.isBeingRemoved { isBeingRemoved = true }
        if other.resetSeed != 0 { resetSeed = other.resetSeed }
    }
}

/// Animated view frame snapshot passed through the animation system.
struct ViewFrame: Equatable {
    var origin: CGPoint
    var size: ViewSize

    init(size: ViewSize) {
        self.origin = .zero
        self.size = size
    }
    init(origin: CGPoint, size: ViewSize) {
        self.origin = origin
        self.size = size
    }

    mutating func round(toMultipleOf value: CGFloat) {
        origin.x = (origin.x / value).rounded() * value
        origin.y = (origin.y / value).rounded() * value
        size.value.width  = (size.value.width  / value).rounded() * value
        size.value.height = (size.value.height / value).rounded() * value
    }
}

/// Shared environment cache passed down the view tree via `_GraphInputs`.
/// Copying `_GraphInputs` preserves the same `CachedEnvironment` reference
/// (via `MutableBox`) so all descendants share a single environment Attribute.
struct CachedEnvironment {

    // ID is represented directly as an Int value.
    struct ID {
        var value: Int
    }

    struct MapItem {
        var key: ID
        var value: AGAttribute
    }

    struct AnimatedFrame {
        var position:          Attribute<CGPoint>
        var size:              Attribute<ViewSize>
        var pixelLength:       Attribute<CGFloat>
        var time:              Attribute<Time>
        var transaction:       Attribute<Transaction>
        var viewPhase:         Attribute<Phase>
        var animatedFrame:     Attribute<ViewFrame>
        var _animatedPosition: Attribute<CGPoint>?
        var _animatedSize:     Attribute<ViewSize>?
        var _animatedCGSize:   Attribute<CGSize>?
    }

    /// The live `EnvironmentValues` AG node.
    /// Reading `.value` inside a rule registers a dependency so the rule
    /// re-evaluates automatically when the environment changes.
    var environment: Attribute<EnvironmentValues>

    /// Style-map items threaded through the environment cache.
    var mapItems: [MapItem]

    /// Per-frame animation layout snapshot.
    /// Nil until layout AG nodes are wired; animation modifiers read from here.
    var animatedFrame: AnimatedFrame?

    /// Cache of resolved shape styles keyed by ResolvedShapeStyles.
    /// Placeholder for resolved shape-style storage.
    var resolvedShapeStyles: Any?

    /// Platform-specific renderer cache (e.g. Metal layer reference).
    var platformCache: Any?

    init(environment: Attribute<EnvironmentValues>) {
        self.environment = environment
        self.mapItems = []
        self.animatedFrame = nil
        self.resolvedShapeStyles = nil
        self.platformCache = nil
    }
}

/// The bundle of AG context Attributes passed from parent to child during
/// `_makeView` traversal.  All fields are Attribute references (IDs), so
/// copying this struct is cheap.
public struct _GraphInputs {
    /// Arbitrary typed values threaded through the view tree, such as styles and options.
    var customInputs: PropertyList

    /// Current animation time.
    var time: Attribute<Time>

    /// Shared environment cache.  `MutableBox` ensures all copies of
    /// `_GraphInputs` in the same subtree point at the same `CachedEnvironment`.
    var cachedEnvironment: MutableBox<CachedEnvironment>

    /// Current render phase (referenced as `viewPhase` inside AnimatedFrame).
    var phase: Attribute<Phase>

    /// Current transaction (animation parameters, etc.).
    var transaction: Attribute<Transaction>

    /// Bitmask tracking which debug properties have changed since the last evaluation.
    var changedDebugProperties: UInt32

    /// Bitmask of options controlling view list traversal behavior.
    var options: UInt32

    /// Set of AG node IDs whose inputs have been merged into this context.
    var mergedInputs: Set<AGAttribute>

    // Base-channel subscript backed by customInputs.
    subscript<T: GraphInput>(_ key: T.Type) -> T.Value {
        get { customInputs.value(forKey: key) }
        set { customInputs.setValue(newValue, forKey: key) }
    }

    // Stack operations for base-channel keys with Stack values
    // Used by the ViewModifier body-input stack (BodyInput<Content>).

    /// Push an element onto the Stack stored for `key` in the base channel.
    mutating func append<T: GraphInput, E>(_ element: E, forKey key: T.Type) where T.Value == Stack<E> {
        var stack = customInputs.value(forKey: key)
        stack = .node(element, stack)
        customInputs.setValue(stack, forKey: key)
    }

    /// Pop and return the top element from the Stack stored for `key` in the base channel.
    /// Returns nil if the stack is empty.
    mutating func popLast<T: GraphInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        var stack = customInputs.value(forKey: key)
        let elem = stack.pop()
        customInputs.setValue(stack, forKey: key)
        return elem
    }

    /// Peek at the top element of the Stack stored for `key` without consuming it.
    /// Returns nil if the stack is empty.
    func top<T: GraphInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        customInputs.value(forKey: key).top
    }

    /// Returns true if any BodyInput<T> stack in customInputs is non-empty.
    var containsNonEmptyBodyStack: Bool { false }
}
