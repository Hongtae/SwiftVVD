//
//  File: GestureResponder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// AnyGestureResponder

/// Type-erased protocol for gesture responders used by GestureGraph.
/// Allows GestureGraph.createSession to work with any GestureResponder<M>
/// without knowing the concrete modifier type M.
protocol AnyGestureResponder: ViewResponder, AnyObject {
    var gestureViewInputs: _ViewInputs { get }
    var exclusionPolicy: GestureResponderExclusionPolicy { get }
    var gestureMask: GestureMask { get set }
    func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()>
}

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
        // Prepend so that views merged LATER (= higher z-order) appear first in the
        // hitResponders array and therefore win `.default` gesture priority.
        // e.g. merge([bg, main]) → [main, bg]: content gets events before background ✓
        //      merge([main, ov]) → [ov, main]: overlay gets events before content ✓
        value = nextValue() + value
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
        collectHits(from: responders, point: point)
    }

    /// Recursively collects hit responders, following `ContainsPointsResult.children`
    /// when a responder delegates to inner responders.
    ///
    /// `priority > 0` (e.g. GestureResponder returns 16.0) means the responder itself is
    /// a gesture hit — include it in the result in addition to recursing into children.
    /// `priority == 0` (e.g. ContentShapeResponder) means the responder is a shape filter
    /// only — recurse into children but do not add self to the hit list.
    private func collectHits(from responders: [any ViewResponder], point: CGPoint) -> [any ViewResponder] {
        var result: [any ViewResponder] = []
        for responder in responders {
            let r = responder.containsGlobalPoints(
                [point], cacheKey: nil, options: ContainsPointsOptions())
            guard r.mask & 1 != 0 else { continue }
            if r.children.isEmpty {
                result.append(responder)
            } else {
                if r.priority > 0 {
                    result.append(responder)
                }
                result.append(contentsOf: collectHits(from: r.children, point: point))
            }
        }
        return result
    }
}

// ActiveGestureSession

/// Represents one active gesture interaction for a single touch/click EventID.
///
/// Created when a touch hits a `GestureResponder` (touch began).
/// Torn down when the gesture phase becomes terminal (.ended or .failed).
///
/// All AG nodes produced by `_makeGesture` live inside `subgraph`.
/// Invalidating the subgraph releases the recognizer and all AG rules atomically.
final class ActiveGestureSession {
    /// AG subgraph holding all nodes created by `_makeGesture` for this interaction.
    let subgraph: Subgraph

    /// Session-local events attribute — only events for this EventID are written here.
    let eventsAttr: Attribute<[EventID: any EventType]>

    /// Derived attribute: true when the gesture phase is .ended or .failed.
    let isTerminalAttr: Attribute<Bool>

    /// Weak reference to the responder that owns this session.
    weak var responder: (any AnyGestureResponder)?

    init(
        subgraph: Subgraph,
        eventsAttr: Attribute<[EventID: any EventType]>,
        isTerminalAttr: Attribute<Bool>,
        responder: any AnyGestureResponder
    ) {
        self.subgraph = subgraph
        self.eventsAttr = eventsAttr
        self.isTerminalAttr = isTerminalAttr
        self.responder = responder
    }

    var isTerminal: Bool { isTerminalAttr.value }

    /// Tears down this session: invalidates the AG subgraph, releasing all gesture nodes
    /// and recognizers that were created for this interaction.
    func teardown() {
#if DEBUG
        assert(!_tornDown, "ActiveGestureSession.teardown() called more than once")
        _tornDown = true
#endif
        subgraph.invalidate()
        subgraph.removeFromParent()
    }

#if DEBUG
    private var _tornDown = false
#endif
}

// GestureResponder

/// Concrete ViewResponder created by AddGestureModifier._makeView (via GestureFilter rule).
///
/// Generic on the modifier type M so that `makeGesture` can call `M._makeSessionGesture`
/// directly at session-creation time — enabling dynamic gesture switching without a factory
/// closure capture. Stores `modifierAttr: Attribute<M>` rather than a baked-in factory.
///
/// Subclass of `MultiViewResponder` — inherits `responders` (inner ViewResponder list)
/// and `updateChildren` plumbing. The GestureFilter<M> rule writes to `responders` directly.
nonisolated(unsafe) private var _gestureResponderKeyCounter: UInt32 = 1

final class GestureResponder<M: GestureViewModifier>: MultiViewResponder, ViewResponder, AnyGestureResponder {
    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }

    /// The modifier attribute — read inside `makeGesture` at session-creation time.
    /// Using the attribute (not a baked value) ensures dynamic gesture changes are picked up.
    let modifierAttr: Attribute<M>

    /// How this responder interacts with other simultaneously-hit responders.
    let exclusionPolicy: GestureResponderExclusionPolicy

    /// The gesture mask controlling which gesture types are active.
    /// Updated by GestureFilter<M>.updateValue() whenever the modifier changes.
    var gestureMask: GestureMask

    /// The _ViewInputs captured at _makeView time.
    var viewInputs: _ViewInputs
    var gestureViewInputs: _ViewInputs { viewInputs }

    init(
        modifierAttr: Attribute<M>,
        exclusionPolicy: GestureResponderExclusionPolicy,
        gestureMask: GestureMask,
        viewInputs: _ViewInputs
    ) {
        self.hitTestKey = _gestureResponderKeyCounter
        _gestureResponderKeyCounter &+= 1
        self.modifierAttr = modifierAttr
        self.exclusionPolicy = exclusionPolicy
        self.gestureMask = gestureMask
        self.viewInputs = viewInputs
        super.init()
    }

    /// Instantiates the gesture graph for one session by delegating to the modifier type.
    /// Called inside a session Subgraph so all produced AG nodes are session-scoped.
    func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        M._makeSessionGesture(modifier: _GraphValue(_attribute: modifierAttr), inputs: inputs)
    }

    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy {
        .include
    }

    func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ContainsPointsOptions
    ) -> ContainsPointsResult {
        let sz = viewInputs.size.value.value
        let t = viewInputs.transform.value
        var localPts = Array(points.prefix(64))
        t.convertGlobal(to: .local, points: &localPts)
        let localBounds = CGRect(origin: .zero, size: sz)
        var mask: UInt64 = 0
        for (i, localPt) in localPts.enumerated() {
            if localBounds.contains(localPt) { mask |= (1 << i) }
        }
        guard mask != 0 else {
            return ContainsPointsResult(mask: 0, priority: 0, children: [])
        }
        // priority=16 signals to collectHits that this responder is itself a gesture hit
        // (not just a shape filter like ContentShapeResponder). responders carries the inner
        // view responders so the traversal can also activate nested gesture sessions.
        return ContainsPointsResult(mask: mask, priority: 16.0, children: responders)
    }
}
