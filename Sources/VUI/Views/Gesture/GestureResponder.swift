//
//  File: GestureResponder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// AnyGestureResponder

protocol AnyGestureResponder: AnyGestureContainingResponder {
    var relatedAttribute: AGAttribute { get }
    var inputs: _ViewInputs { get }
    var childSubgraph: AGSubgraph? { get set }
    var childViewSubgraph: AGSubgraph? { get set }
    var exclusionPolicy: GestureResponderExclusionPolicy { get }
    var label: String? { get }
    var mask: GestureMask { get }
    var gestureGraph: GestureGraph { get }
    func makeSubviewsGesture(inputs: _GestureInputs) -> _GestureOutputs<()>
}

protocol AnyGestureContainingResponder: AnyObject {
    var viewSubgraph: AGSubgraph { get }
    var eventSources: [any EventBindingSource] { get }
    func detachContainer()
    var gestureType: Any.Type { get }
    var isValid: Bool { get }
}

// AnyGestureResponder extension defaults.

extension AnyGestureResponder {
    var exclusionPolicy: GestureResponderExclusionPolicy { .default }
    var label: String? { nil }
    var mask: GestureMask { .all }

    func makeSubviewsGesture(
        inputs: _GestureInputs
    ) -> _GestureOutputs<()> {
        inputs.makeDefaultOutputs()
    }

    var isCancellable: Bool {
        Update.ensure {
            gestureGraph.data.withCurrent {
                gestureGraph.instantiateIfNeeded()
                return gestureGraph._isCancellableAttr.attribute?.value ?? false
            }
        }
    }

    var requiredTapCount: Int? {
        Update.ensure {
            gestureGraph.data.withCurrent {
                gestureGraph.instantiateIfNeeded()
                return gestureGraph._requiredTapCountAttr.attribute?.value ?? nil
            }
        }
    }

    var dependency: GestureDependency {
        Update.ensure {
            gestureGraph.data.withCurrent {
                gestureGraph.instantiateIfNeeded()
                return gestureGraph._gestureDependencyAttr.attribute?.value ?? .none
            }
        }
    }

    /// Returns true if self is a descendant of other in the nextResponder chain.
    /// Convenience wrapper for exclusionPolicy checks.
    func isDescendant(of other: any AnyGestureResponder) -> Bool {
        guard let selfVR = self as? ViewResponder,
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
        guard let first = first as? ViewResponder,
              let second = second as? ViewResponder else {
            return false
        }
        return isSimultaneous(first, with: second, exclusionPolicy: policy)
    }

    private static func isSimultaneous(
        _ first: ViewResponder,
        with second: ViewResponder,
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
                return second.isDescendant(of: first)
            case .ancestors:
                return first.isDescendant(of: second)
            }
        }
    }

    /// Evaluates both responders' coexistence policies. Each policy is applied
    /// in its owner's direction, making the combined result symmetric.
    func isSimultaneous(with other: any AnyGestureResponder) -> Bool {
        let otherExclusionPolicy = other.exclusionPolicy
        guard let other = other as? ViewResponder else { return false }
        return isSimultaneous(
            with: other,
            otherExclusionPolicy: otherExclusionPolicy
        )
    }

    /// Evaluates simultaneous recognition using the policy supplied for `other`.
    func isSimultaneous(
        with other: ViewResponder,
        otherExclusionPolicy: GestureResponderExclusionPolicy
    ) -> Bool {
        guard let selfResponder = self as? ViewResponder else { return false }
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
        over other: ViewResponder,
        otherExclusionPolicy: GestureResponderExclusionPolicy
    ) -> Bool {
        guard let selfResponder = self as? ViewResponder else {
            return false
        }
        let selfNode: ResponderNode = selfResponder
        let otherNode: ResponderNode = other
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
        _ other: ViewResponder,
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
        guard let selfResponder = self as? ViewResponder,
              let otherResponder = other as? ViewResponder else {
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

    func makeWrappedGesture(
        inputs: _GestureInputs,
        makeChild: (_GestureInputs) -> _GestureOutputs<()>
    ) -> _GestureOutputs<()> {
        guard _AGGraph.current != nil, let parentSubgraph = AGSubgraph.current else {
            fatalError("makeWrappedGesture: no _AGGraph context")
        }
        if let childSubgraph, childSubgraph.isValid {
            return AGSubgraph.withCurrent(childSubgraph) {
                makeChild(inputs)
            }
        }

        let newSubgraph = AGSubgraph()
        childSubgraph = newSubgraph
        parentSubgraph.addSecondaryChild(newSubgraph)
        let outputs = AGSubgraph.withCurrent(newSubgraph) {
            makeChild(inputs)
        }
        switch outputs.phase.value {
        case .possible:
            return inputs.makeDefaultOutputs()
        case .active:
            return outputs
        case .ended, .failed:
            childSubgraph = nil
            return outputs
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
    typealias Value = [ViewResponder]
    static var defaultValue: [ViewResponder] { [] }
    static var _includesRemovedValues: Bool { true }
    static func reduce(value: inout [ViewResponder], nextValue: () -> [ViewResponder]) {
        value.append(contentsOf: nextValue())
    }
}

// ResponderNode

enum ResponderVisitorResult: Hashable {
    case next
    case skipToNextSibling
    case cancel
}

class ResponderNode {
    init() {}

    var nextResponder: ResponderNode? {
        fatalError("ResponderNode.nextResponder must be overridden")
    }

    func bindEvent(_ event: any EventType) -> ResponderNode? {
        fatalError("ResponderNode.bindEvent(_:) must be overridden")
    }

    func visit(
        applying body: (ResponderNode) -> ResponderVisitorResult
    ) -> ResponderVisitorResult {
        body(self)
    }

    func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        inputs.makeDefaultOutputs()
    }

    func resetGesture() {}

    func isDescendant(of ancestor: ResponderNode) -> Bool {
        var node: ResponderNode? = self
        while let current = node {
            if current === ancestor {
                return true
            }
            node = current.nextResponder
        }
        return false
    }

    var sequence: UnfoldSequence<ResponderNode, (ResponderNode?, Bool)> {
        Swift.sequence(first: self) { $0.nextResponder }
    }

    func firstAncestor<A>(ofType type: A.Type) -> A? {
        for responder in sequence {
            if let result = responder as? A {
                return result
            }
        }
        return nil
    }

    func log(action: String, data: Any?) {
    }
}

struct BitVector64: OptionSet {
    var rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    init() {
        self.rawValue = 0
    }

    subscript(index: Int) -> Bool {
        get {
            precondition((0..<64).contains(index))
            return rawValue & (UInt64(1) << UInt64(index)) != 0
        }
        set {
            precondition((0..<64).contains(index))
            let bit = UInt64(1) << UInt64(index)
            if newValue {
                rawValue |= bit
            } else {
                rawValue &= ~bit
            }
        }
    }
}

struct ContentPathChanges: OptionSet {
    var rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    static let data = ContentPathChanges(rawValue: 1 << 0)
    static let size = ContentPathChanges(rawValue: 1 << 1)
    static let transform = ContentPathChanges(rawValue: 1 << 2)
}

protocol ContentPathObserver: AnyObject {
    func respondersDidChange(for responder: ViewResponder)
    func contentPathDidChange(
        for responder: ViewResponder,
        changes: ContentPathChanges,
        transform: (old: ViewTransform, new: ViewTransform),
        finished: inout Bool
    )
}

struct ContentPathObservers {
    private struct Observer {
        weak var value: (any ContentPathObserver)?
    }

    private var observers: [Observer] = []

    mutating func add(observer: any ContentPathObserver) {
        observers.removeAll { $0.value == nil }
        guard !observers.contains(where: { $0.value === observer }) else {
            return
        }
        observers.append(Observer(value: observer))
    }

    mutating func takeObservers() -> [any ContentPathObserver] {
        let values = observers.compactMap(\.value)
        observers.removeAll()
        return values
    }
}

class ViewResponder: ResponderNode, CustomStringConvertible {
    // The responder tree owns access to this process-global, non-atomic counter.
    nonisolated(unsafe) private static var _hitTestKey: UInt32 = 0

    static var hitTestKey: UInt32 {
        _hitTestKey
    }

    static let minOpacityForHitTest = 0.001

    static func nextHitTestKey() -> UInt32 {
        _hitTestKey &+= 1
        return _hitTestKey
    }

    enum HitTestPolicy: Hashable {
        case include
        case exclude
        case passthrough
    }

    struct ContainsPointsCache {
        var storage: (key: UInt32, value: ViewResponder.ContainsPointsResult)?

        init() {}

        mutating func fetch(
            key: UInt32?,
            _ body: () -> ViewResponder.ContainsPointsResult
        ) -> ViewResponder.ContainsPointsResult {
            guard let key else {
                return body()
            }
            if let storage, storage.key == key {
                return storage.value
            }
            let value = body()
            storage = (key, value)
            return value
        }
    }

    struct ContainsPointsOptions: OptionSet {
        var rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        static let platformDefault = ViewResponder.ContainsPointsOptions([])
        static let allowDisabledViews = ViewResponder.ContainsPointsOptions(rawValue: 1 << 0)
        static let useZDistanceAsPriority = ViewResponder.ContainsPointsOptions(rawValue: 1 << 1)
        static let disablePointCloudHitTesting = ViewResponder.ContainsPointsOptions(rawValue: 1 << 2)
        static let allow3DResponders = ViewResponder.ContainsPointsOptions(rawValue: 1 << 3)
        static let crossingServerIDBoundary = ViewResponder.ContainsPointsOptions(rawValue: 1 << 4)
        static let uncached = ViewResponder.ContainsPointsOptions(rawValue: 1 << 5)
        static let includeHoverResponders = ViewResponder.ContainsPointsOptions(rawValue: 1 << 6)
    }

    struct ContainsPointsResult {
        var mask: BitVector64
        var priority: Double
        var children: [ViewResponder]

        init(mask: BitVector64, priority: Double, children: [ViewResponder]) {
            self.mask = mask
            self.priority = priority
            self.children = children
        }

        static func passthrough(to children: [ViewResponder]) -> ViewResponder.ContainsPointsResult {
            ViewResponder.ContainsPointsResult(mask: [], priority: 0, children: children)
        }

        static var stop: ViewResponder.ContainsPointsResult {
            ViewResponder.ContainsPointsResult(mask: [], priority: 0, children: [])
        }
    }

    struct Features: OptionSet {
        var rawValue: UInt16

        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        static let platformViews = Features(rawValue: 1 << 0)
        static let gestures = Features(rawValue: 1 << 1)
        static let gestureContainers = Features(rawValue: 1 << 2)
    }

    static let gestureContainmentPriority = 16.0

    weak var host: (any ViewGraphDelegate)?
    weak var parent: ViewResponder?

    override var nextResponder: ResponderNode? {
        parent
    }

    init(host: (any ViewGraphDelegate)?) {
        self.host = host
        super.init()
    }

    override init() {
        self.host = (_AGGraphContext.current?.context as? ViewGraph)?.viewDelegate
        super.init()
    }

    var gestureContainer: AnyObject? { nil }
    var opacity: Double { 1.0 }

    func hitTestPolicy(options: ViewResponder.ContainsPointsOptions) -> ViewResponder.HitTestPolicy {
        opacity < Self.minOpacityForHitTest ? .exclude : .include
    }

    func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        .stop
    }

    func addContentPath(
        to path: inout Path,
        kind: ContentShapeKinds,
        in coordinateSpace: CoordinateSpace,
        observer: (any ContentPathObserver)?
    ) {
    }

    func addObserver(_ observer: any ContentPathObserver) {
    }

    var children: [ViewResponder] { [] }
    var features: Features { [] }
    var description: String {
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        return "node(\(pointer) \(String(describing: type(of: self))))"
    }

    func extendPrintTree(string: inout String) {
    }
}

// MultiViewResponder

class MultiViewResponder: ViewResponder {
    private var _children: [ViewResponder] = []
    private var cache = ContainsPointsCache()
    private var observers = ContentPathObservers()

    override var children: [ViewResponder] {
        get { _children }
        set {
            guard !_children.elementsEqual(newValue, by: { $0 === $1 }) else {
                return
            }
            for child in _children where child.parent === self {
                child.parent = nil
            }
            _children = newValue
            for child in _children {
                child.parent = self
            }
            childrenDidChange()
        }
    }

    override func hitTestPolicy(
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.HitTestPolicy {
        .include
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        if hitTestPolicy(options: options) == .exclude {
            return .passthrough(to: children)
        }
        return cache.fetch(key: cacheKey) {
            var mask = BitVector64()
            var priority = 0.0
            for child in children where child.hitTestPolicy(options: options) != .exclude {
                let result = child.containsGlobalPoints(
                    points,
                    cacheKey: cacheKey,
                    options: options
                )
                mask.formUnion(result.mask)
                priority = max(priority, result.priority)
            }
            return ViewResponder.ContainsPointsResult(
                mask: mask,
                priority: priority,
                children: children
            )
        }
    }

    func updateChildren(_ result: (value: [ViewResponder], changed: Bool)) {
        guard result.changed else { return }
        children = result.value
    }

    func childrenDidChange() {
        let currentObservers = observers.takeObservers()
        for observer in currentObservers {
            observer.respondersDidChange(for: self)
        }
    }

    override func resetGesture() {
        for responder in children {
            responder.resetGesture()
        }
    }

    override func bindEvent(_ event: any EventType) -> ResponderNode? {
        for child in children {
            if let responder = child.bindEvent(event) {
                return responder
            }
        }
        return nil
    }

    override func visit(
        applying body: (ResponderNode) -> ResponderVisitorResult
    ) -> ResponderVisitorResult {
        let result = body(self)
        guard result == .next else {
            return result
        }
        for child in children {
            if child.visit(applying: body) == .cancel {
                return .cancel
            }
        }
        return .next
    }

    func respondersContaining(point: CGPoint) -> [ViewResponder] {
        collectHits(from: children, point: point)
    }

    /// Recursively collects hit responders, following `ViewResponder.ContainsPointsResult.children`
    /// when a responder delegates to inner responders.
    ///
    /// `priority > 0` (e.g. GestureResponder returns 16.0) means the responder itself is
    /// a gesture hit: include it in the result in addition to recursing into children.
    /// `priority == 0` (e.g. ContentShapeResponder) means the responder is a shape filter
    /// only: recurse into children but do not add self to the hit list.
    private func collectHits(from responders: [ViewResponder], point: CGPoint) -> [ViewResponder] {
        var result: [ViewResponder] = []
        for responder in responders {
            let r = responder.containsGlobalPoints(
                [point], cacheKey: nil, options: ViewResponder.ContainsPointsOptions())
            guard r.mask[0] else { continue }
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

    override func addContentPath(
        to path: inout Path,
        kind: ContentShapeKinds,
        in coordinateSpace: CoordinateSpace,
        observer: (any ContentPathObserver)?
    ) {
        for child in children {
            child.addContentPath(
                to: &path,
                kind: kind,
                in: coordinateSpace,
                observer: observer
            )
        }
    }

    override func addObserver(_ observer: any ContentPathObserver) {
        observers.add(observer: observer)
    }

    override var features: Features {
        children.reduce(into: []) { $0.formUnion($1.features) }
    }
}

// DefaultLayoutViewResponder

class DefaultLayoutViewResponder: MultiViewResponder {
    let inputs: _ViewInputs
    let viewSubgraph: AGSubgraph
    private var childSubgraph: AGSubgraph?
    private var childViewSubgraph: AGSubgraph?
    private var invalidateChildren: (() -> Void)?

    init(inputs: _ViewInputs) {
        guard let viewSubgraph = AGSubgraph.current else {
            fatalError("DefaultLayoutViewResponder.init(inputs:) requires a current AGSubgraph")
        }
        self.inputs = inputs
        self.viewSubgraph = viewSubgraph
        super.init()
    }

    init(inputs: _ViewInputs, viewSubgraph: AGSubgraph) {
        self.inputs = inputs
        self.viewSubgraph = viewSubgraph
        super.init()
    }

    override func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        let defaultOutputs: _GestureOutputs<()> = inputs.makeDefaultOutputs()
        guard viewSubgraph.isValid else {
            return defaultOutputs
        }

        if let childViewSubgraph, childViewSubgraph.isValid,
           let graph = _AGGraph.current, graph === childViewSubgraph.graph {
            childViewSubgraph.invalidate()
        }
        childViewSubgraph = nil
        if let childSubgraph, childSubgraph.isValid,
           let graph = _AGGraph.current, graph === childSubgraph.graph {
            childSubgraph.invalidate()
        }
        childSubgraph = nil

        let firstSubgraph = AGSubgraph.withCurrent(viewSubgraph) {
            AGSubgraph()
        }
        childSubgraph = firstSubgraph

        if inputs.options.contains(.gestureGraph) {
            let secondSubgraph = AGSubgraph.withCurrent(firstSubgraph) {
                AGSubgraph()
            }
            childViewSubgraph = secondSubgraph
        }

        let activeSubgraph = childViewSubgraph ?? firstSubgraph
        return AGSubgraph.withCurrent(activeSubgraph) {
            guard let graph = _AGGraph.current else {
                fatalError("DefaultLayoutViewResponder.makeGesture requires AG context")
            }
            var childInputs = inputs
            childInputs.viewSubgraph = activeSubgraph
            let gestureAttr = graph.makeInput(value: DefaultLayoutGesture(responder: self))
            let weakAttribute = graph.weakAttributeIfValid(for: gestureAttr.identifier)
            let host = _AGGraphContext.current?.context as? GraphHost
            if let weakAttribute {
                invalidateChildren = { [weak host] in
                    guard let host else { return }
                    host.asyncTransaction(
                        Transaction.current,
                        id: Transaction.id,
                        mutation: InvalidatingGraphMutation(attribute: weakAttribute),
                        style: .deferred,
                        mayDeferUpdate: true
                    )
                }
            } else {
                invalidateChildren = nil
            }
            return DefaultLayoutGesture._makeGesture(
                gesture: _GraphValue(_attribute: gestureAttr),
                inputs: childInputs
            )
        }
    }

    override func childrenDidChange() {
        invalidateChildren?()
        super.childrenDidChange()
    }

    override func resetGesture() {
        invalidateChildren = nil
        if let childSubgraph, childSubgraph.isValid,
           let graph = _AGGraph.current, graph === childSubgraph.graph {
            childSubgraph.invalidate()
        }
        childSubgraph = nil
        if let childViewSubgraph, childViewSubgraph.isValid,
           let graph = _AGGraph.current, graph === childViewSubgraph.graph {
            childViewSubgraph.invalidate()
        }
        childViewSubgraph = nil
        super.resetGesture()
    }
}

struct DefaultLayoutGesture: LayoutGesture, PrimitiveDebuggableGesture {
    var responder: MultiViewResponder

    typealias Value = Void
    typealias Body = Never

}

struct DefaultLayoutResponderFilter: StatefulRule {
    typealias Value = [ViewResponder]

    var children: Attribute<[ViewResponder]>
    var responder: MultiViewResponder

    init(
        children: Attribute<[ViewResponder]>,
        responder: MultiViewResponder
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

// GestureResponder

final class GestureResponder<M: GestureViewModifier>:
    DefaultLayoutViewResponder,
    AnyGestureResponder,
    AnyGestureContainingResponder
{
    private let modifier: Attribute<M>
    var mask: GestureMask
    var childSubgraph: AGSubgraph?
    var childViewSubgraph: AGSubgraph?
    lazy var gestureGraph = GestureGraph(rootResponder: self)
    lazy var bindingBridge = inputs.makeEventBindingBridge(
        bindingManager: gestureGraph.eventBindingManager,
        responder: self
    )
    private var _gestureContainer: AnyObject?

    init(modifier: Attribute<M>, inputs: _ViewInputs) {
        self.modifier = modifier
        self.mask = .all
        super.init(inputs: inputs)
    }

    var relatedAttribute: AGAttribute {
        modifier.identifier
    }

    var exclusionPolicy: GestureResponderExclusionPolicy {
        M.Combiner.exclusionPolicy
    }

    var label: String? {
        modifier[keyPath: \.name].value
    }

    override var gestureContainer: AnyObject? {
        if _gestureContainer == nil, viewSubgraph.isValid {
            _gestureContainer = inputs.makeGestureContainer(responder: self)
        }
        return _gestureContainer
    }

    var eventSources: [any EventBindingSource] {
        bindingBridge.eventSources
    }

    var gestureType: Any.Type {
        M.self
    }

    var isValid: Bool {
        _gestureContainer != nil && viewSubgraph.isValid
    }

    func detachContainer() {
        _gestureContainer = nil
    }

    func makeSubviewsGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        super.makeGesture(inputs: inputs)
    }

    override func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        makeWrappedGesture(inputs: inputs) { [modifier] inputs in
            guard let graph = _AGGraph.current else {
                fatalError("GestureResponder.makeGesture requires AG context")
            }
            let outputs = M.ContentGesture._makeGesture(
                gesture: _GraphValue(_attribute: modifier[keyPath: \.gesture]),
                inputs: inputs
            )
            let phase = graph.makeRule {
                outputs.phase.value.map { _ in () }
            }
            return outputs.withPhase(phase)
        }
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        var result = super.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options
        )
        if !options.contains(.useZDistanceAsPriority) {
            result.priority = Self.gestureContainmentPriority
        }
        return result
    }

    override var features: Features {
        super.features.union([.gestures, .gestureContainers])
    }
}
