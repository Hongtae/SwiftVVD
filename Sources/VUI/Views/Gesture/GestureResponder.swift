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
/// Does not inherit ViewResponder. GestureResponder<M> conforms to both
/// AnyGestureResponder and ViewResponder independently (via MultiViewResponder).
///
/// - makeSubviewsGesture delegates into the modifier's session gesture construction.
/// - makeWrappedGesture owns child-subgraph reuse and rebuild.
/// - gestureGraph is captured from the owning ViewGraph at init.
protocol AnyGestureResponder: AnyObject {
    /// AG attribute ID for the modifier, used for AG-level change tracking.
    var relatedAttribute: AGAttribute { get }

    /// View inputs captured at _makeView time (geometry, transform, environment, size).
    var inputs: _ViewInputs { get }

    /// Gesture-session subgraph. Created and managed by makeWrappedGesture.
    /// Persists across gesture sessions and is not torn down when a gesture ends.
    var childSubgraph: AGSubgraph? { get set }

    /// View-level subgraph that owns the responder's AG nodes.
    var childViewSubgraph: AGSubgraph? { get set }

    /// Per-responder events attribute. Created on first session and reused across sessions.
    /// makeWrappedGesture bakes this into the gesture chain. Subsequent sessions write to it.
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
    /// Delegates into the modifier's session gesture construction.
    func makeSubviewsGesture(inputs: _GestureInputs) -> _GestureOutputs<()>

    /// Returns whether this responder can start from the given event payload type.
    func accepts(eventType: Any.Type) -> Bool
}

// ViewResponder extension

extension ViewResponder {
    func resetGesture() {}

    func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        inputs.makeDefaultOutputs()
    }

    /// Returns true if self appears in the nextResponder chain leading up to ancestor.
    ///
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

// AnyGestureResponder extension defaults.

extension AnyGestureResponder {
    /// Reads the tap-count requirement published by the responder's gesture graph.
    var requiredTapCount: Int? {
        guard let id = cachedGestureOutputs?.preferences.value(for: RequiredTapCountKey.self) else {
            return nil
        }
        return gestureGraph.data.withCurrent {
            Attribute<Int?>(id).value
        }
    }

    /// Reads the strongest recognition dependency published by the responder's gesture graph.
    var dependency: GestureDependency {
        guard let id = cachedGestureOutputs?.preferences.value(for: GestureDependency.Key.self) else {
            return .none
        }
        return gestureGraph.data.withCurrent {
            Attribute<GestureDependency>(id).value
        }
    }

    /// Returns true if self is a descendant of other in the nextResponder chain.
    /// Convenience wrapper for exclusionPolicy checks.
    func isDescendant(of other: any AnyGestureResponder) -> Bool {
        guard let selfVR = self as? any ViewResponder,
              let otherNode = other as? ResponderNode else { return false }
        return selfVR.isDescendant(of: otherNode)
    }

    /// Returns true if first and second should run simultaneously given policy.
    ///
    /// exclusionPolicy is owned by `first`:
    ///   tag 0 (.descendants): second is a descendant of first
    ///   tag 1 (.ancestors):   first is a descendant of second
    ///   tag 2 (.global):      true
    ///   tag 3/4:              false
    static func isSimultaneous(
        _ first: any AnyGestureResponder,
        with second: any AnyGestureResponder,
        exclusionPolicy policy: GestureResponderExclusionPolicy
    ) -> Bool {
        guard let first = first as? any ViewResponder,
              let second = second as? any ViewResponder else {
            return false
        }
        return isSimultaneous(first, with: second, exclusionPolicy: policy)
    }

    private static func isSimultaneous(
        _ first: any ViewResponder,
        with second: any ViewResponder,
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
                guard let first = first as? ResponderNode else { return false }
                return second.isDescendant(of: first)
            case .ancestors:
                guard let second = second as? ResponderNode else { return false }
                return first.isDescendant(of: second)
            }
        }
    }

    /// Evaluates both responders' coexistence policies. Each policy is applied
    /// in its owner's direction, making the combined result symmetric.
    func isSimultaneous(with other: any AnyGestureResponder) -> Bool {
        let otherExclusionPolicy = other.exclusionPolicy
        guard let other = other as? any ViewResponder else { return false }
        return isSimultaneous(
            with: other,
            otherExclusionPolicy: otherExclusionPolicy
        )
    }

    /// Evaluates simultaneous recognition using the policy supplied for `other`.
    func isSimultaneous(
        with other: any ViewResponder,
        otherExclusionPolicy: GestureResponderExclusionPolicy
    ) -> Bool {
        guard let selfResponder = self as? any ViewResponder else { return false }
        return Self.isSimultaneous(
            selfResponder,
            with: other,
            exclusionPolicy: exclusionPolicy
        ) || Self.isSimultaneous(
            other,
            with: selfResponder,
            exclusionPolicy: otherExclusionPolicy
        )
    }

    /// Returns whether this responder has recognition priority over `other`.
    func isPrioritized(
        over other: any ViewResponder,
        otherExclusionPolicy: GestureResponderExclusionPolicy
    ) -> Bool {
        guard let selfResponder = self as? any ViewResponder,
              let selfNode = selfResponder as? ResponderNode,
              let otherNode = other as? ResponderNode else {
            return false
        }
        guard !isSimultaneous(
            with: other,
            otherExclusionPolicy: otherExclusionPolicy
        ) else {
            return false
        }

        switch exclusionPolicy {
        case .default:
            if otherExclusionPolicy == .highPriority {
                return false
            }
            return selfResponder.isDescendant(of: otherNode)
        case .highPriority:
            if otherExclusionPolicy == .default {
                return true
            }
            if otherExclusionPolicy == .highPriority {
                return other.isDescendant(of: selfNode)
            }
            return selfResponder.isDescendant(of: otherNode)
        case .simultaneous:
            return selfResponder.isDescendant(of: otherNode)
        }
    }

    /// Returns whether this responder may force `other` to fail recognition.
    func canPrevent(
        _ other: any ViewResponder,
        otherExclusionPolicy: GestureResponderExclusionPolicy
    ) -> Bool {
        guard isPrioritized(
            over: other,
            otherExclusionPolicy: otherExclusionPolicy
        ) else {
            return false
        }
        guard let other = other as? any AnyGestureResponder else {
            return true
        }
        switch other.dependency {
        case .none, .failIfActive:
            return true
        case .pausedWhileActive, .pausedUntilFailed:
            return false
        }
    }

    /// Returns whether this responder must wait for `other` to fail.
    func shouldRequireFailure(of other: any AnyGestureResponder) -> Bool {
        guard let selfResponder = self as? any ViewResponder,
              let otherResponder = other as? any ViewResponder else {
            return false
        }

        if !isSimultaneous(
            with: otherResponder,
            otherExclusionPolicy: other.exclusionPolicy
        ), let selfCount = requiredTapCount,
           let otherCount = other.requiredTapCount,
           selfCount != otherCount {
            return selfCount < otherCount
        }

        return other.isPrioritized(
            over: selfResponder,
            otherExclusionPolicy: exclusionPolicy
        ) && dependency != .none
    }

    /// Manages the childSubgraph lifecycle and delegates to makeSubviewsGesture.
    ///
    /// Build path (first call, or after invalidation):
    ///   - Creates childSubgraph, stores eventsAttr/resetSeedAttr from inputs.
    ///   - Calls makeChild inside the subgraph so the gesture chain is built there.
    ///   - Caches _GestureOutputs.
    ///
    /// Reuse path (childSubgraph already built, needsRebuild == false):
    ///   - Returns cachedGestureOutputs directly.
    ///   - eventsAttr and resetSeedAttr on the responder are already wired in.
    ///   - Subsequent sessions write to the same eventsAttr and resetSeed increments on session end.
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

        // Rebuild path: modifier changed. Tear down the old chain if one exists.
        if needsRebuild {
            if let sub = childSubgraph {
                sub.invalidate()
                childSubgraph = nil
                cachedGestureOutputs = nil
            }
            needsRebuild = false  // always reset, even when no prior chain exists
        }

        // Build path.
        guard _AGGraph.current != nil else {
            fatalError("makeWrappedGesture: no _AGGraph context")
        }

        // Store the per-responder attrs from inputs.
        // These are created by createSession and passed through _GestureInputs.
        eventsAttr = inputs.events
        resetSeedAttr = inputs.resetSeed

        let newSubgraph = AGSubgraph()
        childSubgraph = newSubgraph

        let outputs = AGSubgraph.withCurrent(newSubgraph) {
            makeChild(inputs)
        }
        cachedGestureOutputs = outputs
        return outputs
    }

    /// Convenience entry point used by GestureGraph.createSession.
    /// Not a protocol requirement. Calls makeWrappedGesture which calls makeSubviewsGesture.
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
        // Example: merge([background, main]) -> [main, background], so content gets
        // events before background. Overlay merges likewise stay ahead of content.
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

    /// Clears gesture-session state owned by this responder and its descendants.
    func resetGesture()

    /// Determines how this responder participates in hit testing.
    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy

    /// Returns the hit-test result for a set of points (global coordinate space).
    func containsGlobalPoints(_ points: [CGPoint], cacheKey: UInt32?, options: ContainsPointsOptions) -> ContainsPointsResult

    /// Builds this responder's gesture subtree for layout gesture routing.
    func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()>
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
        childrenDidChange()
    }

    func childrenDidChange() {
    }

    func resetGesture() {
        for responder in responders {
            responder.resetGesture()
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
    /// a gesture hit: include it in the result in addition to recursing into children.
    /// `priority == 0` (e.g. ContentShapeResponder) means the responder is a shape filter
    /// only: recurse into children but do not add self to the hit list.
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

// DefaultLayoutViewResponder

nonisolated(unsafe) private var _defaultLayoutViewResponderKeyCounter: UInt32 = 1

final class DefaultLayoutViewResponder: MultiViewResponder, ViewResponder {
    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }
    var scrollTarget: ((ScrollGeometry, LayoutDirection) -> ScrollTarget?)?
    var gestureSubgraph1: AGSubgraph?
    var gestureSubgraph2: AGSubgraph?
    private weak var layoutGestureInvalidationHost: GraphHost?
    private weak var layoutGestureGraph: _AGGraph?
    private var layoutGestureAttribute: AGWeakAttribute?

    init(
        responders: [any ViewResponder] = [],
        scrollTarget: ((ScrollGeometry, LayoutDirection) -> ScrollTarget?)? = nil
    ) {
        self.hitTestKey = _defaultLayoutViewResponderKeyCounter
        _defaultLayoutViewResponderKeyCounter &+= 1
        self.scrollTarget = scrollTarget
        super.init()
        update(responders: responders, scrollTarget: scrollTarget)
    }

    func update(
        responders: [any ViewResponder],
        scrollTarget: ((ScrollGeometry, LayoutDirection) -> ScrollTarget?)?
    ) {
        self.scrollTarget = scrollTarget
        updateChildren((value: responders, changed: true))
    }

    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy {
        .passthrough
    }

    func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ContainsPointsOptions
    ) -> ContainsPointsResult {
        let count = min(points.count, 64)
        let mask = count == 64 ? UInt64.max : ((UInt64(1) << UInt64(count)) - 1)
        return ContainsPointsResult(mask: mask, priority: 0, children: responders)
    }

    func scrollTarget(
        in geometry: ScrollGeometry,
        layoutDirection: LayoutDirection
    ) -> ScrollTarget? {
        scrollTarget?(geometry, layoutDirection)
    }

    func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        let defaultOutputs: _GestureOutputs<()> = inputs.makeDefaultOutputs()
        guard let viewSubgraph = inputs.viewSubgraph, viewSubgraph.isValid else {
            return defaultOutputs
        }

        resetSubgraph(&gestureSubgraph2)
        resetSubgraph(&gestureSubgraph1)

        let firstSubgraph = AGSubgraph.withCurrent(viewSubgraph) {
            AGSubgraph()
        }
        gestureSubgraph1 = firstSubgraph

        if inputs.options.contains(.gestureGraph) {
            let secondSubgraph = AGSubgraph.withCurrent(firstSubgraph) {
                AGSubgraph()
            }
            gestureSubgraph2 = secondSubgraph
        }

        let activeSubgraph = gestureSubgraph2 ?? firstSubgraph
        return AGSubgraph.withCurrent(activeSubgraph) {
            guard let graph = _AGGraph.current else {
                fatalError("DefaultLayoutViewResponder.makeGesture requires AG context")
            }
            var childInputs = inputs
            childInputs.viewSubgraph = activeSubgraph
            let gestureAttr = graph.makeInput(value: DefaultLayoutGesture(responder: self))
            layoutGestureAttribute = graph.weakAttributeIfValid(for: gestureAttr.identifier)
            layoutGestureGraph = graph
            layoutGestureInvalidationHost = _AGGraphContext.current?.context as? GraphHost
            return DefaultLayoutGesture._makeGesture(
                gesture: _GraphValue(_attribute: gestureAttr),
                inputs: childInputs
            )
        }
    }

    override func childrenDidChange() {
        invalidateLayoutGesture()
        super.childrenDidChange()
    }

    override func resetGesture() {
        scrollTarget = nil
        layoutGestureAttribute = nil
        layoutGestureGraph = nil
        layoutGestureInvalidationHost = nil
        resetSubgraph(&gestureSubgraph1)
        resetSubgraph(&gestureSubgraph2)
        super.resetGesture()
    }

    private func invalidateLayoutGesture() {
        guard let layoutGestureAttribute else { return }
        if let host = layoutGestureInvalidationHost {
            host.asyncTransaction(
                Transaction.current,
                id: Transaction.id,
                mutation: InvalidatingGraphMutation(attribute: layoutGestureAttribute),
                style: .deferred,
                mayDeferUpdate: true
            )
            return
        }

        guard let graph = _AGGraph.current,
              graph === layoutGestureGraph,
              layoutGestureAttribute.isValid(in: graph) else {
            return
        }
        graph.invalidateAttribute(
            layoutGestureAttribute.toStrong(),
            transaction: Transaction.current,
            propagateTransaction: !Transaction.current.isEmpty
        )
    }

    private func resetSubgraph(_ subgraph: inout AGSubgraph?) {
        guard let current = subgraph else { return }
        if let graph = _AGGraph.current, graph === current.graph {
            current.invalidate()
        }
        subgraph = nil
    }
}

struct DefaultLayoutGesture: LayoutGesture, PrimitiveDebuggableGesture, LayoutGestureResponderProvider {
    var responder: MultiViewResponder

    typealias Value = Void
    typealias Body = Never

    var layoutGestureResponder: MultiViewResponder {
        responder
    }
}

struct DefaultLayoutResponderFilter: StatefulRule {
    typealias Value = [any ViewResponder]

    var children: Attribute<[any ViewResponder]>
    var responder: DefaultLayoutViewResponder

    init(
        children: Attribute<[any ViewResponder]>,
        responder: DefaultLayoutViewResponder
    ) {
        self.children = children
        self.responder = responder
    }

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        let childrenChanged = _AGGraph.currentStatefulInputChanged(children.identifier)
        responder.updateChildren((value: children.value, changed: isInitialValue || childrenChanged))
        _AGGraph.setStatefulOutput([responder])
    }
}

// ActiveGestureSession

/// Represents one active gesture interaction for a single touch/click EventID.
///
/// Created when a touch hits a `GestureResponder` (touch began).
/// Torn down when the gesture phase becomes terminal (.ended or .failed).
///
/// Event storage belongs to the responder so a recognizer waiting on another
/// recognizer's failure can remain dormant until its dependency resolves.
/// On teardown, resetSeedAttr is incremented so the persistent gesture chain resets.
final class ActiveGestureSession {
    /// The responder-local event input wired into this gesture chain.
    let eventsAttr: Attribute<[EventID: any EventType]>

    /// The full gesture phase distinguishes successful recognition from failure.
    let phaseAttr: Attribute<GesturePhase<Void>>

    /// Derived attribute: true when the gesture phase is .ended or .failed.
    let isTerminalAttr: Attribute<Bool>

    /// Lower-priority recognizers that start only if this session fails.
    var failureFallbacks: [ActiveGestureSession] = []

    /// Initial event batch retained for replay into a failure fallback.
    var beganEvents: [EventID: any EventType] = [:]

    /// Weak reference to the responder that owns this session.
    weak var responder: (any AnyGestureResponder)?

    init(
        eventsAttr: Attribute<[EventID: any EventType]>,
        phaseAttr: Attribute<GesturePhase<Void>>,
        isTerminalAttr: Attribute<Bool>,
        responder: any AnyGestureResponder
    ) {
        self.eventsAttr = eventsAttr
        self.phaseAttr = phaseAttr
        self.isTerminalAttr = isTerminalAttr
        self.responder = responder
    }

    var isTerminal: Bool { isTerminalAttr.value }

    var phase: GesturePhase<Void> { phaseAttr.value }

    /// Ends this session: increments the responder's per-session resetSeedAttr so the
    /// persistent gesture chain resets itself.
    /// Does not invalidate childSubgraph. It persists for the next session.
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

    // AnyGestureResponder stored fields
    let modifierAttr: Attribute<M>
    let exclusionPolicy: GestureResponderExclusionPolicy
    var mask: GestureMask
    var inputs: _ViewInputs

    // AnyGestureResponder protocol fields.
    // gestureGraph is stored at init from the current ViewGraph's renderer host.
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

    /// Current modifier value, updated by GestureFilter.updateValue() on each evaluation.
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
        // GestureResponder is created while ViewGraph is current. Follow the renderer host
        // to the owning GestureGraph.
        guard let ref = _AGGraphContext.current,
              let viewGraph = ref.context as? ViewGraph,
              let gestureGraph = viewGraph.rendererHost?.gestureGraph else {
            fatalError("GestureResponder.init: must be called within a ViewGraph AG context with rendererHost.gestureGraph")
        }
        self.gestureGraph = gestureGraph
        super.init()
    }

    // AnyGestureResponder gesture creation

    func makeSubviewsGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        // Runs in GestureGraph's AG context (called via createSession -> makeGesture).
        // Creates a GestureGraph-local input node from the snapshot modifier value so that
        // the gesture chain contains no cross-graph attribute references.
        guard let graph = _AGGraph.current else {
            fatalError("GestureResponder.makeSubviewsGesture: no AG context")
        }
        let localModifierAttr: Attribute<M> = graph.makeInput(value: currentModifier)
        return M._makeSessionGesture(modifier: _GraphValue(_attribute: localModifierAttr), inputs: inputs)
    }

    func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        makeWrappedGesture(inputs: inputs) { [self] modifiedInputs in
            makeSubviewsGesture(inputs: modifiedInputs)
        }
    }

    func accepts(eventType: Any.Type) -> Bool {
        currentModifier.acceptsEventType(eventType)
    }

    override func resetGesture() {
        if let subgraph = childSubgraph,
           let graph = _AGGraph.current,
           graph === subgraph.graph {
            subgraph.invalidate()
            childSubgraph = nil
            needsRebuild = false
        } else if childSubgraph != nil {
            needsRebuild = true
        }
        eventsAttr = nil
        resetSeedAttr = nil
        cachedGestureOutputs = nil
        super.resetGesture()
    }

    // ViewResponder hit testing
    // (keep the priority=16 convention: signals to collectHits that this is a gesture hit)

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
        // attribute access causes an index-out-of-range in _AGGraph.value(for:).
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
        // priority=16 makes collectHits include self as a gesture hit and recurse into responders.
        return ContainsPointsResult(mask: mask, priority: 16.0, children: responders)
    }
}
