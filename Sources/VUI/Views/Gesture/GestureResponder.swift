//
//  File: GestureResponder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// AnyGestureResponder

/// Protocol for all gesture responders in the system.
///
/// Does NOT inherit ViewResponder. GestureResponder<M> conforms to both
/// AnyGestureResponder and ViewResponder independently (via MultiViewResponder).
///
/// - makeSubviewsGesture calls M._makeSessionGesture.
/// - makeWrappedGesture manages childSubgraph reuse and rebuild.
/// - gestureGraph is stored at init from rendererHost?.gestureGraph.
protocol AnyGestureResponder: AnyObject {
    /// AG attribute ID for the modifier, enabling AG-level change tracking.
    var relatedAttribute: AGAttribute { get }

    /// View inputs captured at _makeView time (geometry, transform, environment, size).
    var inputs: _ViewInputs { get }

    /// Gesture-session subgraph. Created and managed by makeWrappedGesture.
    /// Persists across gesture sessions and is not torn down when a gesture ends.
    var childSubgraph: AGSubgraph? { get set }

    /// View-level subgraph that owns the responder's AG nodes.
    var childViewSubgraph: AGSubgraph? { get set }

    /// Per-responder events attribute. Created on first session, reused across sessions.
    /// makeWrappedGesture bakes this into the gesture chain; subsequent sessions write to it.
    var eventsAttr: Attribute<[EventID: any EventType]>? { get set }

    /// Per-responder reset seed attribute. Incremented when a gesture session ends/cancels.
    var resetSeedAttr: Attribute<UInt32>? { get set }

    /// Cached _GestureOutputs from the first makeWrappedGesture build.
    /// Returned directly on subsequent calls (reuse path).
    var cachedGestureOutputs: _GestureOutputs<()>? { get set }

    /// Controls how this responder coexists with other simultaneously-hit responders.
    var exclusionPolicy: GestureResponderExclusionPolicy { get }

    /// Accessibility label for this gesture (optional).
    var label: String? { get }

    /// Mask controlling which gesture categories are recognised.
    var mask: GestureMask { get }

    /// The GestureGraph that owns this responder.
    var gestureGraph: GestureGraph { get }

    // Snapshot fields.
    // GestureFilter (ViewGraph AG context) writes these plain Swift values.
    // createSession (GestureGraph AG context) reads them to create local input attrs
    // without touching cross-graph attribute slots.

    /// ViewGraph AG attribute for the view's coordinate transform.
    /// Stored by GestureFilter.updateValue() (ViewGraph context) so that createSession
    /// can create a cross-graph ref node instead of a static snapshot copy.
    var transformAttr: Attribute<ViewTransform>? { get set }

    /// ViewGraph AG attribute for the view's proposed size.
    var sizeAttr: Attribute<ViewSize>? { get set }

    /// Set to true when the modifier changes mid-life. makeWrappedGesture invalidates
    /// the old childSubgraph and rebuilds when this flag is set.
    var needsRebuild: Bool { get set }

    /// Snapshot of the view's cumulative coordinate transform (written by GestureFilter).
    var snapshotTransform: ViewTransform { get set }

    /// Snapshot of the view's proposed size (written by GestureFilter).
    var snapshotSize: ViewSize { get set }

    /// Snapshot of the gesture host's registered preference keys (written by GestureFilter).
    var snapshotPreferenceKeys: PreferenceKeys { get set }

    /// Produces gesture outputs for this responder's gesture cascade.
    func makeSubviewsGesture(inputs: _GestureInputs) -> _GestureOutputs<()>
}

// ViewResponder extension

extension ViewResponder {
    /// Returns true if self appears in the nextResponder chain leading up to ancestor.
    /// ResponderNode.parent chain is not used.
    func isDescendant(of ancestor: ResponderNode) -> Bool {
        var node: ResponderNode? = nextResponder
        while let n = node {
            if n === ancestor { return true }
            node = (n as? any ViewResponder)?.nextResponder
        }
        return false
    }
}

// AnyGestureResponder extension defaults

extension AnyGestureResponder {
    /// Returns true if self is a descendant of other in the nextResponder chain.
    /// Convenience wrapper for exclusionPolicy checks.
    func isDescendant(of other: any AnyGestureResponder) -> Bool {
        guard let selfVR = self as? any ViewResponder,
              let otherNode = other as? ResponderNode else { return false }
        return selfVR.isDescendant(of: otherNode)
    }

    /// Returns true if first and second should run simultaneously given policy.
    ///
    /// exclusionPolicy is applied as first's policy:
    ///   tag 0 (.descendants): isDescendant(first, of: second)
    ///   tag 1 (.ancestors):   isDescendant(second, of: first)
    ///   tag 2 (.global):      true
    ///   tag 3/4:              false
    static func isSimultaneous(
        _ first: any AnyGestureResponder,
        with second: any AnyGestureResponder,
        exclusionPolicy policy: GestureResponderExclusionPolicy
    ) -> Bool {
        switch policy {
        case .default, .highPriority:
            return false
        case .simultaneous(let constraint):
            switch constraint {
            case .global:
                return true
            case .descendants:
                return first.isDescendant(of: second)
            case .ancestors:
                return second.isDescendant(of: first)
            }
        }
    }

    /// Evaluates whether self and other should run simultaneously, using other's policy.
    ///
    /// self.exclusionPolicy is NOT consulted. Result can be asymmetric:
    ///   child.isSimultaneous(with: parent) = true  (parent has .descendants, child is in subtree)
    ///   parent.isSimultaneous(with: child) = false (child has .default, both calls return false)
    ///
    /// call1 = static(self,  other, other.policy)
    /// call2 = static(other, self,  other.policy)
    /// return call1 || call2
    func isSimultaneous(with other: any AnyGestureResponder) -> Bool {
        let p = other.exclusionPolicy
        let check1 = Self.isSimultaneous(self,  with: other, exclusionPolicy: p)
        let check2 = Self.isSimultaneous(other, with: self,  exclusionPolicy: p)
        return check1 || check2
    }

    /// Manages the childSubgraph lifecycle and delegates to makeSubviewsGesture.
    ///
    /// Build path (first call, or after invalidation):
    ///   - Creates childSubgraph, stores eventsAttr/resetSeedAttr from inputs.
    ///   - Calls makeChild inside the subgraph, building the gesture chain.
    ///   - Caches _GestureOutputs.
    ///
    /// Reuse path (childSubgraph already built, needsRebuild == false):
    ///   - Returns cachedGestureOutputs directly.
    ///   - eventsAttr and resetSeedAttr on the responder are already wired in.
    ///   - Subsequent sessions write to the same eventsAttr; resetSeed increments on session end.
    ///
    /// Rebuild path (needsRebuild == true, modifier changed):
    ///   - Invalidates old childSubgraph (all nodes removed from GestureGraph's AG).
    ///   - Falls through to build path to reconstruct the chain.
    func makeWrappedGesture(
        inputs: _GestureInputs,
        makeChild: (_GestureInputs) -> _GestureOutputs<()>
    ) -> _GestureOutputs<()> {
        // Reuse path: childSubgraph exists, has live nodes, and modifier has not changed.
        if let sub = childSubgraph, !sub.nodes.isEmpty, let cached = cachedGestureOutputs,
           !needsRebuild {
            return cached
        }

        // Rebuild path: modifier changed, tear down the old chain if one exists.
        if needsRebuild {
            if let sub = childSubgraph {
                sub.invalidate()
                childSubgraph = nil
                cachedGestureOutputs = nil
            }
            needsRebuild = false  // always reset, even when no prior chain exists
        }

        // Build path.
        guard AttributeGraph.current != nil else {
            fatalError("makeWrappedGesture: no AttributeGraph context")
        }

        // Store the per-responder attrs from inputs.
        // These are created by createSession and passed through _GestureInputs.
        eventsAttr = inputs.events
        resetSeedAttr = inputs.resetSeed

        let newSubgraph = AGSubgraph()
        childSubgraph = newSubgraph

        let outputs = AGSubgraph.$current.withValue(newSubgraph) {
            makeChild(inputs)
        }
        cachedGestureOutputs = outputs
        return outputs
    }

    /// Convenience entry point used by GestureGraph.createSession.
    /// Not a protocol requirement. Calls makeWrappedGesture, which calls makeSubviewsGesture.
    func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        makeWrappedGesture(inputs: inputs) { [self] modifiedInputs in
            makeSubviewsGesture(inputs: modifiedInputs)
        }
    }
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
        // e.g. merge([bg, main]) -> [main, bg]: content gets events before background
        //      merge([main, ov]) -> [ov, main]: overlay gets events before content
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

    /// An optional opaque gesture container (for grouping/priority resolution).
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
    /// a gesture hit, so include it in the result in addition to recursing into children.
    /// `priority == 0` (e.g. ContentShapeResponder) means the responder is a shape filter
    /// only. Recurse into children but do not add self to the hit list.
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
/// The shared eventsAttr lives at the GestureGraph level.
/// This session holds only the isTerminal check and per-responder teardown handle.
/// On teardown, the per-responder resetSeedAttr is incremented to signal the persistent
/// gesture chain to reset.
final class ActiveGestureSession {
    /// Derived attribute: true when the gesture phase is .ended or .failed.
    let isTerminalAttr: Attribute<Bool>

    /// Weak reference to the responder that owns this session.
    weak var responder: (any AnyGestureResponder)?

    init(isTerminalAttr: Attribute<Bool>, responder: any AnyGestureResponder) {
        self.isTerminalAttr = isTerminalAttr
        self.responder = responder
    }

    var isTerminal: Bool { isTerminalAttr.value }

    /// Ends this session: increments the responder's per-session resetSeedAttr so the
    /// persistent gesture chain resets itself.
    /// Does NOT invalidate childSubgraph. It persists for the next session.
    func teardown() {
#if DEBUG
        assert(!_tornDown, "ActiveGestureSession.teardown() called more than once")
        _tornDown = true
#endif
        if let resetSeedAttr = responder?.resetSeedAttr {
            let next = resetSeedAttr.value &+ 1
            resetSeedAttr.setValue(next)
        }
    }

#if DEBUG
    private var _tornDown = false
#endif
}

// GestureResponder

/// Concrete implementation of ViewResponder and AnyGestureResponder.
/// Created by GestureFilter<M>.updateValue() inside a dedicated AGSubgraph on first evaluation.
/// Updated in place on subsequent evaluations (mask, responders).
///
/// Subclass of MultiViewResponder. Inherits `responders: [any ViewResponder]` (inner-view
/// responder list) and `containsGlobalPoints` delegation logic.
///
/// Generic on M so makeSubviewsGesture can call M._makeSessionGesture without a factory closure.
nonisolated(unsafe) private var _gestureResponderKeyCounter: UInt32 = 1

final class GestureResponder<M: GestureViewModifier>: MultiViewResponder, ViewResponder, AnyGestureResponder {

    // ViewResponder requirements
    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }

    // AnyGestureResponder stored fields.
    let modifierAttr: Attribute<M>
    let exclusionPolicy: GestureResponderExclusionPolicy
    var mask: GestureMask
    var inputs: _ViewInputs

    // AnyGestureResponder protocol fields.
    // gestureGraph is resolved at init through the current ViewGraph context.
    var relatedAttribute: AGAttribute { modifierAttr.identifier }
    var childSubgraph: AGSubgraph? = nil
    var childViewSubgraph: AGSubgraph? = nil
    var eventsAttr: Attribute<[EventID: any EventType]>? = nil
    var resetSeedAttr: Attribute<UInt32>? = nil
    var cachedGestureOutputs: _GestureOutputs<()>? = nil
    var label: String? { nil }
    var gestureGraph: GestureGraph
    var transformAttr: Attribute<ViewTransform>? = nil
    var sizeAttr: Attribute<ViewSize>? = nil

    // Snapshot fields written by GestureFilter (ViewGraph AG context),
    // read by GestureGraph.createSession to construct GestureGraph-local input attrs.
    // These are plain Swift values (no AG attribute slots) so there is no cross-graph access.

    /// Current modifier value; updated by GestureFilter.updateValue() on each evaluation.
    var currentModifier: M

    /// Set when the modifier changes so makeWrappedGesture rebuilds the gesture chain.
    var needsRebuild: Bool = false

    /// Last-known cumulative coordinate transform (written by GestureFilter).
    var snapshotTransform: ViewTransform = .identity

    /// Last-known proposed size (written by GestureFilter).
    var snapshotSize: ViewSize = ViewSize(.zero)

    /// Last-known host preference keys (written by GestureFilter).
    var snapshotPreferenceKeys: PreferenceKeys = PreferenceKeys()

    init(
        modifierAttr: Attribute<M>,
        currentModifier: M,
        exclusionPolicy: GestureResponderExclusionPolicy,
        mask: GestureMask,
        inputs: _ViewInputs
    ) {
        self.hitTestKey = _gestureResponderKeyCounter
        _gestureResponderKeyCounter &+= 1
        self.modifierAttr = modifierAttr
        self.currentModifier = currentModifier
        self.exclusionPolicy = exclusionPolicy
        self.mask = mask
        self.inputs = inputs
        // Resolve GestureGraph through the current ViewGraph context.
        guard let ref = AttributeGraphRef.current,
              let viewGraph = ref.context as? ViewGraph,
              let gestureGraph = viewGraph.rendererHost?.gestureGraph else {
            fatalError("GestureResponder.init: must be called within a ViewGraph AG context with rendererHost.gestureGraph")
        }
        self.gestureGraph = gestureGraph
        super.init()
    }

    // AnyGestureResponder gesture creation.

    func makeSubviewsGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        // Runs in GestureGraph's AG context (called via createSession -> makeGesture).
        // Creates a GestureGraph-local input node from the snapshot modifier value so that
        // the gesture chain contains no cross-graph attribute references.
        guard let graph = AttributeGraph.current else {
            fatalError("GestureResponder.makeSubviewsGesture: no AG context")
        }
        let localModifierAttr: Attribute<M> = graph.makeInput(value: currentModifier)
        return M._makeSessionGesture(modifier: _GraphValue(_attribute: localModifierAttr), inputs: inputs)
    }

    // ViewResponder hit testing.
    // Keep the priority=16 convention: signals to collectHits that this is a gesture hit.

    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy {
        .include
    }

    func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ContainsPointsOptions
    ) -> ContainsPointsResult {
        // Use snapshot values (plain Swift, no AG attribute access) because
        // containsGlobalPoints is called from GestureGraph's AG context, while
        // inputs.size/inputs.transform are ViewGraph AG attributes. Cross-graph
        // attribute access causes an index-out-of-range in AttributeGraph.value(for:).
        let sz = snapshotSize.value
        let t = snapshotTransform
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
        // priority=16 means collectHits includes self as a gesture hit and recurses into responders.
        return ContainsPointsResult(mask: mask, priority: 16.0, children: responders)
    }
}
