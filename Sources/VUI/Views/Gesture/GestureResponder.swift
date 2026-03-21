//
//  File: GestureResponder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

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
    /// when a responder (e.g. `ContentShapeResponder`) delegates to inner responders.
    private func collectHits(from responders: [any ViewResponder], point: CGPoint) -> [any ViewResponder] {
        var result: [any ViewResponder] = []
        for responder in responders {
            let r = responder.containsGlobalPoints(
                [point], cacheKey: nil, options: ContainsPointsOptions())
            guard r.mask & 1 != 0 else { continue }
            if r.children.isEmpty {
                result.append(responder)
            } else {
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
    weak var responder: GestureResponder?

    init(
        subgraph: Subgraph,
        eventsAttr: Attribute<[EventID: any EventType]>,
        isTerminalAttr: Attribute<Bool>,
        responder: GestureResponder
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

/// Concrete ViewResponder created by AddGestureModifier._makeView.
///
/// Stores view geometry for hit testing and a factory closure that calls
/// `Gesture._makeGesture` on demand when a touch begins.
/// This deferred approach means dynamic views get fresh gesture sessions
/// each time they are touched.
final class GestureResponder: ViewResponder {
    private static let _nextKey = Mutex<UInt32>(1)

    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }

    /// AG attribute for the view's position (window-global coords, for hit testing).
    let position: Attribute<CGPoint>

    /// AG attribute for the view's proposed size (for hit testing).
    let size: Attribute<ViewSize>

    /// How this responder interacts with other simultaneously-hit responders.
    /// Derived from `Combiner.exclusionPolicy` at _makeView time.
    let exclusionPolicy: GestureResponderExclusionPolicy

    /// The gesture mask controlling which gesture types are active.
    let gestureMask: GestureMask

    /// The _ViewInputs captured at _makeView time.
    /// Provides position, size, time, and preference key context to sessions.
    let viewInputs: _ViewInputs

    /// Factory closure: called inside a session subgraph to instantiate the gesture graph.
    /// Takes the session-local _GestureInputs and returns an Attribute<Bool> that is
    /// true when the gesture phase is terminal (.ended or .failed).
    typealias Factory = (_GestureInputs) -> Attribute<Bool>
    let factory: Factory

    init(
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        exclusionPolicy: GestureResponderExclusionPolicy,
        gestureMask: GestureMask,
        viewInputs: _ViewInputs,
        factory: @escaping Factory
    ) {
        self.hitTestKey = GestureResponder._nextKey.withLock { key in
            defer { key &+= 1 }
            return key
        }

        self.position = position
        self.size = size
        self.exclusionPolicy = exclusionPolicy
        self.gestureMask = gestureMask
        self.viewInputs = viewInputs
        self.factory = factory
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
        let globalToLocal = viewInputs.transform.value.matrix.inverted()
        
        // Use pos as the origin if transform does not include the view's position translation,
        // or .zero if transform is the fully accumulated local transform. 
        // Assuming VUI's transform does not automatically include the parent-assigned position:
        let localBounds = CGRect(origin: pos, size: sz)

        var mask: UInt64 = 0
        for (i, globalPt) in points.prefix(64).enumerated() {
            let localPt = globalPt.applying(globalToLocal)
            if localBounds.contains(localPt) { 
                mask |= (1 << i) 
            }
        }
        return ContainsPointsResult(mask: mask, priority: 0, children: [])
    }
}
