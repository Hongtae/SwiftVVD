//
//  File: GestureResponder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// ViewRespondersKey

/// Built-in PreferenceKey that carries gesture responders upward through the view tree.
/// Each view that installs a gesture appends its ViewResponder here.
/// The root (WindowController / MultiViewResponder) collects the full array.
///
/// `_includesRemovedValues = true` so that the root can detect when responders are removed
/// and clean up bindings accordingly.
struct ViewRespondersKey: PreferenceKey {
    typealias Value = [any ViewResponder]
    static var defaultValue: [any ViewResponder] { [] }
    static var _includesRemovedValues: Bool { true }
    static func reduce(value: inout [any ViewResponder], nextValue: () -> [any ViewResponder]) {
        value.append(contentsOf: nextValue())
    }
}

// ViewResponder Protocol

/// A node in the gesture responder chain. Each gesture-enabled view creates one.
/// Carries hit-test geometry and gesture phase for event dispatch.
protocol ViewResponder: AnyObject {
    /// A per-instance key used for hit-test caching.
    var hitTestKey: UInt32 { get }

    /// The next node up the responder chain (usually the containing view's responder).
    var nextResponder: ResponderNode? { get set }

    /// An optional opaque gesture container for grouping and priority resolution.
    var gestureContainer: AnyObject? { get }

    /// Determines how this responder participates in hit testing.
    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy

    /// Returns the hit-test result for a set of points (global coordinate space).
    func containsGlobalPoints(_ points: [CGPoint], cacheKey: UInt32?, options: ContainsPointsOptions) -> ContainsPointsResult
}

// ViewResponder Nested Types (stand-alone for clarity)

/// Determines how a ViewResponder handles points during hit testing.
enum HitTestPolicy: Hashable {
    case include
    case exclude
    case passthrough
}

/// Options passed to `containsGlobalPoints`.
struct ContainsPointsOptions: OptionSet {
    var rawValue: UInt32
    init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// The result returned by `containsGlobalPoints`.
struct ContainsPointsResult {
    var mask: UInt64
    var priority: Double
    var children: [any ViewResponder]

    static func passthrough(to children: [any ViewResponder]) -> ContainsPointsResult {
        ContainsPointsResult(mask: 0, priority: 0, children: children)
    }

    static var stop: ContainsPointsResult {
        ContainsPointsResult(mask: 0, priority: 0, children: [])
    }
}

// ResponderNode

/// A node in the responder-chain tree.
class ResponderNode {
    weak var parent: ResponderNode?
    var children: [ResponderNode] = []

    init() {}

    func firstAncestor<A>(ofType type: A.Type) -> A? {
        var node: ResponderNode? = parent
        while let n = node {
            if let match = n as? A { return match }
            node = n.parent
        }
        return nil
    }

    var sequence: AnySequence<ResponderNode> {
        AnySequence(children)
    }
}

// MultiViewResponder

/// Root responder node that aggregates all `ViewResponder` instances collected via
/// `ViewRespondersKey`. Installed at the `WindowController` level.
class MultiViewResponder: ResponderNode {
    var host: AnyObject?
    var responders: [any ViewResponder] = []

    init(host: AnyObject? = nil) {
        self.host = host
        super.init()
    }

    /// Called when the `ViewRespondersKey` preference value changes.
    func updateChildren(_ result: (value: [any ViewResponder], changed: Bool)) {
        guard result.changed else { return }
        responders = result.value
        for r in responders {
            if r.nextResponder == nil { r.nextResponder = self }
        }
    }

    enum ResponderVisitorResult { case `continue`, stop }

    func visit(applying: (ResponderNode) -> ResponderVisitorResult) -> ResponderVisitorResult {
        for child in children {
            if case .stop = applying(child) { return .stop }
        }
        return .continue
    }

    func respondersContaining(point: CGPoint) -> [any ViewResponder] {
        responders.filter { responder in
            let result = responder.containsGlobalPoints(
                [point], cacheKey: nil, options: ContainsPointsOptions())
            return result.mask & 1 != 0
        }
    }
}

// GestureViewResponder

/// Concrete ViewResponder created by AddGestureModifier._makeView.
/// Carries the view frame (for hit testing) and the gesture phase output.
final class GestureViewResponder: ViewResponder {
    nonisolated(unsafe) private static var _nextKey: UInt32 = 1
    nonisolated(unsafe) private static var _lock = NSLock()

    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }

    /// AG attribute for the view's position (parent-local).
    let position: Attribute<CGPoint>

    /// AG attribute for the view's proposed size.
    let size: Attribute<ViewSize>

    /// AG attribute for the gesture's current phase (type-erased storage).
    let phaseAttr: AGAttribute

    /// The gesture mask controlling which gesture types are active.
    let gestureMask: GestureMask

    init(
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        phaseAttr: AGAttribute,
        gestureMask: GestureMask
    ) {
        GestureViewResponder._lock.lock()
        self.hitTestKey = GestureViewResponder._nextKey
        GestureViewResponder._nextKey &+= 1
        GestureViewResponder._lock.unlock()

        self.position = position
        self.size = size
        self.phaseAttr = phaseAttr
        self.gestureMask = gestureMask
    }

    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy {
        .include
    }

    func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ContainsPointsOptions
    ) -> ContainsPointsResult {
        let pos = position.value
        let sz = size.value.value
        let frame = CGRect(origin: pos, size: sz)

        var mask: UInt64 = 0
        for (i, pt) in points.prefix(64).enumerated() {
            if frame.contains(pt) { mask |= (1 << i) }
        }
        return ContainsPointsResult(mask: mask, priority: 0, children: [])
    }

    /// Reads the current gesture phase as GesturePhase<Void> (type-erased for dispatch).
    func currentPhaseAsVoid(in graph: AttributeGraph) -> GesturePhase<Void> {
        // We store the phase as a type-erased AGAttribute; at dispatch time
        // we retrieve the raw node and interpret it via a rule that maps → Void.
        // For now, return via opaque access (VUI-internal only).
        return .possible(nil)
    }
}
