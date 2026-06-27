//
//  File: ScrollableLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Layout-time scroll viewport description passed to scrollable layout code.
public struct _ScrollLayout: Equatable {
    public var contentOffset: CGPoint
    public var size: CGSize
    public var visibleRect: CGRect

    public init(contentOffset: CGPoint, size: CGSize, visibleRect: CGRect) {
        self.contentOffset = contentOffset
        self.size = size
        self.visibleRect = visibleRect
    }
}

/// Supplies the content and root view used by the older scroll-view shell.
public protocol _ScrollableContentProvider {
    associatedtype ScrollableContent: View
    var scrollableContent: Self.ScrollableContent { get }

    associatedtype Root: View
    func root(scrollView: _ScrollView<Self>.Main) -> Self.Root
    func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint?
}

extension _ScrollableContentProvider {
    public func root(scrollView: _ScrollView<Self>.Main) -> _ScrollViewRoot<Self> {
        _ScrollViewRoot(scrollView: scrollView)
    }

    public func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint? {
        nil
    }
}

/// Provides gesture policy for a scroll-view proxy.
public protocol _ScrollViewGestureProvider {
    func scrollableDirections(proxy: _ScrollViewProxy) -> _EventDirections
    func gestureMask(proxy: _ScrollViewProxy) -> GestureMask
}

extension _ScrollViewGestureProvider {
    public func defaultScrollableDirections(proxy: _ScrollViewProxy) -> _EventDirections {
        .all
    }

    public func defaultGestureMask(proxy: _ScrollViewProxy) -> GestureMask {
        .all
    }

    public func scrollableDirections(proxy: _ScrollViewProxy) -> _EventDirections {
        defaultScrollableDirections(proxy: proxy)
    }

    public func gestureMask(proxy: _ScrollViewProxy) -> GestureMask {
        defaultGestureMask(proxy: proxy)
    }
}

/// Default gesture provider that uses the protocol fallback policy.
private struct DefaultScrollViewGestureProvider: _ScrollViewGestureProvider {
}

/// Configuration payload shared by the older scroll-view shell and proxy.
public struct _ScrollViewConfig {
    public static let decelerationRateNormal: Double = 0.998
    public static let decelerationRateFast: Double = 0.99

    public enum ContentOffset {
        case initially(CGPoint)
        case binding(Binding<CGPoint>)
    }

    public var contentOffset: ContentOffset
    public var contentInsets: EdgeInsets
    public var decelerationRate: Double
    public var alwaysBounceVertical: Bool
    public var alwaysBounceHorizontal: Bool
    public var gestureProvider: any _ScrollViewGestureProvider
    public var stopDraggingImmediately: Bool
    public var isScrollEnabled: Bool
    public var showsHorizontalIndicator: Bool
    public var showsVerticalIndicator: Bool
    public var indicatorInsets: EdgeInsets

    public init() {
        self.contentOffset = .initially(.zero)
        self.contentInsets = EdgeInsets()
        self.decelerationRate = 0.995
        self.alwaysBounceVertical = false
        self.alwaysBounceHorizontal = false
        self.gestureProvider = DefaultScrollViewGestureProvider()
        self.stopDraggingImmediately = false
        self.isScrollEnabled = true
        self.showsHorizontalIndicator = true
        self.showsVerticalIndicator = true
        self.indicatorInsets = EdgeInsets()
    }
}

/// Older scroll-view shell driven by a content provider.
public struct _ScrollView<Provider>: View where Provider: _ScrollableContentProvider {
    public var contentProvider: Provider
    public var config: _ScrollViewConfig

    public init(contentProvider: Provider, config: _ScrollViewConfig = _ScrollViewConfig()) {
        self.contentProvider = contentProvider
        self.config = config
    }

    public var body: Provider.Root {
        contentProvider.root(
            scrollView: Main(contentProvider: contentProvider, config: config)
        )
    }

    public struct Main: View {
        var contentProvider: Provider
        var config: _ScrollViewConfig

        public typealias Body = Never

        public var body: Never {
            neverBody()
        }

        public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
            guard let graph = AttributeGraph.current else {
                fatalError("_ScrollView.Main._makeView called outside an active AttributeGraph context.")
            }

            let contentOffset = graph.makeInput(
                value: _initialContentOffset(from: view._attribute.value.config)
            )
            let node = ScrollViewNode(
                graphRef: AttributeGraphRef.current ?? AttributeGraphRef(graph: graph),
                contentOffset: contentOffset,
                config: view._attribute.value.config,
                pixelLength: graph.makeRule {
                    inputs.base.cachedEnvironment.value.environment.value.animationPixelLength
                }
            )
            node.container = _ScrollViewMainScrollable.node(
                from: inputs.weakScrollable,
                graph: graph
            )
            let scrollView: Attribute<_ScrollViewProxy> = graph.makeStatefulRule(
                ScrollViewUpdate(
                    _node: node,
                    _view: view._attribute,
                    _containerSize: inputs.size,
                    _environment: inputs.base.cachedEnvironment.value.environment,
                    _time: inputs.base.time,
                    _transaction: inputs.base.transaction,
                    _phase: inputs.base.phase
                )
            )
            let contentAttr: Attribute<Provider.ScrollableContent> = graph.makeRule {
                view._attribute.value.contentProvider.scrollableContent
            }
            let scrollableAttr: Attribute<any Scrollable> = graph.makeRule(
                _ScrollViewMainScrollableProvider(
                    scrollable: _ScrollViewMainScrollable(
                        node: node,
                        parent: inputs.weakScrollable
                    )
                )
            )
            var contentInputs = inputs
            contentInputs[ScrollableLayoutScrollViewProxyKey.self] = OptionalAttribute(scrollView)
            contentInputs[ContainingScrollViewInput.self] = _ContainingScrollView(
                proxy: scrollView,
                contentOffset: contentOffset
            )
            contentInputs.scrollable = OptionalAttribute(scrollableAttr)
            contentInputs.requestsLayoutComputer = true
            contentInputs.preferences.keys.insert(ScrollablePreferenceKey.self)
            contentInputs = ScrollViewGeometry.rewrite(inputs: contentInputs)

            let contentOutputs = Provider.ScrollableContent._makeView(
                view: _GraphValue(_attribute: contentAttr),
                inputs: contentInputs
            )

            let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
                inputs.base.cachedEnvironment.value.environment.value.layoutDirection
            }
            let geometry: Attribute<ScrollGeometry> = graph.makeRule(
                _ScrollViewMainGeometryProvider(
                    node: node,
                    proxy: scrollView,
                    layoutComputer: contentOutputs._layoutComputer,
                    layoutDirection: layoutDirection
                )
            )
            node.bind(
                proxy: scrollView,
                geometry: geometry,
                layoutDirection: layoutDirection
            )
            if let childScrollables = contentOutputs.preferences.value(for: ScrollablePreferenceKey.self) {
                node.bindChildScrollables(Attribute<[any Scrollable]>(childScrollables))
            }

            var outputs = contentOutputs
            outputs.preferences.setValue(nil, for: ScrollablePreferenceKey.self)
            if inputs.preferences.keys.contains(ViewRespondersKey.self) {
                let childResponders: Attribute<[any ViewResponder]>
                if let childRespondersID = contentOutputs.preferences.value(for: ViewRespondersKey.self) {
                    childResponders = Attribute<[any ViewResponder]>(childRespondersID)
                } else {
                    childResponders = graph.makeInput(value: ViewRespondersKey.defaultValue)
                }
                let responder: Attribute<[any ViewResponder]> = graph.makeStatefulRule(
                    _ScrollViewDefaultLayoutResponderRule(childResponders: childResponders)
                )
                outputs.preferences.setValue(responder.identifier, for: ViewRespondersKey.self)
            }
            if inputs.preferences.keys.contains(ScrollablePreferenceKey.self) {
                let preferenceAttr: Attribute<[any Scrollable]> = graph.makeRule(
                    UnaryScrollablePreferenceProvider(scrollable: scrollableAttr)
                )
                outputs.preferences.setValue(preferenceAttr.identifier, for: ScrollablePreferenceKey.self)
            }
            return outputs
        }

        private static func _initialContentOffset(from config: _ScrollViewConfig) -> CGPoint {
            switch config.contentOffset {
            case .initially(let point):
                return point
            case .binding(let binding):
                return binding.wrappedValue
            }
        }
    }
}

extension _ScrollView.Main: _PrimitiveView {
}

private struct _ContainingScrollView {
    var proxy: Attribute<_ScrollViewProxy>
    var contentOffset: Attribute<CGPoint>
}

private struct ContainingScrollViewInput: ViewInput {
    static var defaultValue: _ContainingScrollView? { nil }

    static func valuesEqual(_ a: _ContainingScrollView?, _ b: _ContainingScrollView?) -> Bool {
        a?.proxy.identifier == b?.proxy.identifier &&
            a?.contentOffset.identifier == b?.contentOffset.identifier
    }
}

private enum ScrollViewGeometry {
    static func rewrite(inputs: _ViewInputs) -> _ViewInputs {
        guard let graph = AttributeGraph.current,
              let scrollView = inputs[ContainingScrollViewInput.self] else {
            return inputs
        }

        var rewritten = inputs
        rewritten.position = graph.makeRule(
            _ScrollViewMainContentOffset(
                basePosition: inputs.position,
                scrollView: scrollView.proxy
            )
        )
        rewritten.size = graph.makeRule {
            let proxy = scrollView.proxy.value
            let visibleSize = proxy.pageSize.inset(by: proxy.config.contentInsets)
            return ViewSize(visibleSize, proposal: ProposedViewSize(visibleSize))
        }
        return rewritten
    }
}

private struct _ScrollViewMainContentOffset: Rule {
    typealias Value = CGPoint

    var basePosition: Attribute<CGPoint>
    var scrollView: Attribute<_ScrollViewProxy>

    func updateValue() -> CGPoint {
        let base = basePosition.value
        let proxy = scrollView.value
        let insets = proxy.config.contentInsets
        let adjustedOffset = CGPoint(
            x: proxy.contentOffset.x - insets.leading,
            y: proxy.contentOffset.y - insets.top
        )
        return CGPoint(
            x: base.x - adjustedOffset.x,
            y: base.y - adjustedOffset.y
        )
    }
}

private func _scrollViewMaxContentOffset(
    contentSize: CGSize,
    containerSize: CGSize,
    contentInsets: EdgeInsets
) -> CGPoint {
    let visibleSize = containerSize.inset(by: contentInsets)
    return CGPoint(
        x: max(contentSize.width - visibleSize.width, 0),
        y: max(contentSize.height - visibleSize.height, 0)
    )
}

private func _scrollViewClampContentOffset(
    _ offset: CGPoint,
    maxContentOffset: CGPoint
) -> CGPoint {
    CGPoint(
        x: min(max(offset.x, 0), maxContentOffset.x),
        y: min(max(offset.y, 0), maxContentOffset.y)
    )
}

private let scrollDecelerationForceStep = 1.0 / 240.0
private let scrollDecelerationFrameStep = 1.0 / 120.0
private let scrollDecelerationLowVelocityThreshold = 0.00001
private let scrollDecelerationProjectionMultiplier = 0.001
private let scrollDecelerationTargetSnapTolerance = 0.5
private let scrollDecelerationEstimatedTargetVelocityThreshold = 50.0
private let scrollDecelerationEstimatedTargetDrag = 10.0
private let scrollDecelerationEstimatedTargetStiffnessScale = 30.0
private let scrollRubberBandingMinimumMagnitude = CGFloat(Double.ulpOfOne)
private let scrollRubberBandingScale = CGFloat(0.1)

func _scrollViewAddRubberBandingToResidue(_ residue: CGSize, range: CGSize) -> CGSize {
    CGSize(
        width: _scrollViewAddRubberBandingToResidue(residue.width, range: range.width),
        height: _scrollViewAddRubberBandingToResidue(residue.height, range: range.height)
    )
}

private func _scrollViewAddRubberBandingToResidue(_ residue: CGFloat, range: CGFloat) -> CGFloat {
    guard abs(residue) >= scrollRubberBandingMinimumMagnitude,
          abs(range) >= scrollRubberBandingMinimumMagnitude else {
        return residue
    }
    let direction: CGFloat = residue < 0 ? -1 : 1
    let scaledDistance = (residue / range) * direction * scrollRubberBandingScale
    return direction * range * (1 - 1 / (1 + scaledDistance))
}

struct ScalarDeceleration: Equatable {
    var time: Double
    var offset: Double
    var velocity: _Velocity<Double>
    var drag: Double
    var force: Double
    var bounceStiffness: Double
    var bounceDrag: Double
    var springStiffness: Double
    var springTarget: Double
    var stoppedVelocity: _Velocity<Double>
    var bounced: Bool

    init(
        time: Double,
        offset: Double,
        velocity: _Velocity<Double>,
        drag: Double,
        force: Double? = nil,
        bounceStiffness: Double,
        bounceDrag: Double,
        springStiffness: Double = 0,
        springTarget: Double = 0,
        stoppedVelocity: _Velocity<Double>,
        bounced: Bool = false
    ) {
        self.time = time
        self.offset = offset
        self.velocity = velocity
        self.drag = drag
        self.force = force ?? (-drag * velocity.valuePerSecond)
        self.bounceStiffness = bounceStiffness
        self.bounceDrag = bounceDrag
        self.springStiffness = springStiffness
        self.springTarget = springTarget
        self.stoppedVelocity = stoppedVelocity
        self.bounced = bounced
    }

    var initialValue: CGFloat {
        CGFloat(offset)
    }

    var initialVelocity: CGFloat {
        CGFloat(velocity.valuePerSecond)
    }

    var target: CGFloat? {
        springStiffness == 0 ? nil : CGFloat(springTarget)
    }

    mutating func updateTarget(_ target: CGFloat?) {
        guard let target else {
            springStiffness = 0
            springTarget = 0
            bounced = false
            return
        }

        let targetValue = Double(target)
        guard springTarget != targetValue || springStiffness == 0 else {
            return
        }
        springStiffness = 100
        springTarget = targetValue
        drag = 17
    }

    @discardableResult
    mutating func iter(_ targetTime: Double, minValue: Double?, maxValue: Double?) -> Bool {
        if springStiffness == 0 {
            updateBounceTarget(minValue: minValue, maxValue: maxValue)
        }

        while time < targetTime {
            velocity.valuePerSecond += force * scrollDecelerationForceStep
            offset += velocity.valuePerSecond * scrollDecelerationFrameStep
            force = springStiffness * (springTarget - offset) - drag * velocity.valuePerSecond
            velocity.valuePerSecond += force * scrollDecelerationForceStep
            time += scrollDecelerationFrameStep
        }

        guard abs(velocity.valuePerSecond) < stoppedVelocity.valuePerSecond else {
            return false
        }

        if springStiffness == 0 {
            offset = offset.rounded()
            return true
        }

        guard abs(springTarget - offset) < scrollDecelerationTargetSnapTolerance else {
            return false
        }

        offset = springTarget
        velocity.valuePerSecond = 0
        force = 0
        return true
    }

    mutating func updateEstimatedTarget(_ target: CGFloat) {
        guard !bounced else {
            return
        }
        let speed = abs(velocity.valuePerSecond)
        guard speed < scrollDecelerationEstimatedTargetVelocityThreshold else {
            return
        }
        springTarget = Double(target)
        springStiffness = (1 - speed / scrollDecelerationEstimatedTargetVelocityThreshold) *
            scrollDecelerationEstimatedTargetStiffnessScale
        drag = scrollDecelerationEstimatedTargetDrag
    }

    private mutating func updateBounceTarget(minValue: Double?, maxValue: Double?) {
        if let minValue, offset < minValue {
            let projectedMomentum = velocity.valuePerSecond * drag
            let distance = (minValue - offset) * 2
            if projectedMomentum < distance {
                installBounceTarget(minValue)
            }
            bounced = true
            return
        }

        if let maxValue, offset > maxValue {
            let projectedMomentum = velocity.valuePerSecond * drag
            let distance = (maxValue - offset) * 2
            if distance < projectedMomentum {
                installBounceTarget(maxValue)
            }
            bounced = true
        }
    }

    private mutating func installBounceTarget(_ target: Double) {
        guard !bounced else {
            return
        }
        springTarget = target
        springStiffness = bounceStiffness
        drag = bounceDrag
    }
}

struct Deceleration2D: Equatable {
    var _v: [ScalarDeceleration]

    init(
        time: Double,
        offset: CGSize,
        velocity: _Velocity<CGSize>,
        drag: Double,
        bounceStiffness: Double,
        bounceDrag: Double,
        stoppedVelocity: _Velocity<CGFloat>
    ) {
        let stoppedVelocity = stoppedVelocity.map { Double($0) }
        let xVelocity = velocity.map { Double($0.width) }
        let yVelocity = velocity.map { Double($0.height) }
        self._v = [
            ScalarDeceleration(
                time: time,
                offset: Double(offset.width),
                velocity: xVelocity,
                drag: drag,
                bounceStiffness: bounceStiffness,
                bounceDrag: bounceDrag,
                stoppedVelocity: stoppedVelocity
            ),
            ScalarDeceleration(
                time: time,
                offset: Double(offset.height),
                velocity: yVelocity,
                drag: drag,
                bounceStiffness: bounceStiffness,
                bounceDrag: bounceDrag,
                stoppedVelocity: stoppedVelocity
            ),
        ]
    }

    init(
        offset: CGPoint,
        velocity: _Velocity<CGSize>,
        decelerationRate: Double,
        target: CGPoint? = nil
    ) {
        let drag = min(max(1 - decelerationRate, 0), 1)
        self.init(
            time: 0,
            offset: CGSize(width: offset.x, height: offset.y),
            velocity: velocity,
            drag: drag,
            bounceStiffness: 0,
            bounceDrag: 0,
            stoppedVelocity: _Velocity(valuePerSecond: CGFloat(2.5))
        )
        updateTarget(target)
    }

    var x: ScalarDeceleration {
        get {
            _v[0]
        }
        set {
            _v[0] = newValue
        }
    }

    var y: ScalarDeceleration {
        get {
            _v[1]
        }
        set {
            _v[1] = newValue
        }
    }

    mutating func updateTarget(_ target: CGPoint?) {
        guard _v.count >= 2 else {
            return
        }
        _v[0].updateTarget(target?.x)
        _v[1].updateTarget(target?.y)
    }

    var offset: CGPoint {
        CGPoint(x: CGFloat(x.offset), y: CGFloat(y.offset))
    }

    var velocity: _Velocity<CGSize> {
        _Velocity(valuePerSecond: CGSize(
            width: CGFloat(x.velocity.valuePerSecond),
            height: CGFloat(y.velocity.valuePerSecond)
        ))
    }

    @discardableResult
    mutating func iter(_ time: Double, minValue: CGPoint, maxValue: CGPoint) -> Bool {
        precondition(_v.count >= 2, "Deceleration2D requires two scalar axes")
        let xCompleted = _v[0].iter(time, minValue: Double(minValue.x), maxValue: Double(maxValue.x))
        let yCompleted = _v[1].iter(time, minValue: Double(minValue.y), maxValue: Double(maxValue.y))
        return xCompleted && yCompleted
    }

    mutating func updateEstimatedTarget(_ target: CGPoint) {
        guard _v.count >= 2 else {
            return
        }
        _v[0].updateEstimatedTarget(target.x)
        _v[1].updateEstimatedTarget(target.y)
    }
}

struct ScrollViewBehavior {
    typealias Completion = (Bool) -> Void

    enum Phase {
        case dragging(DragState)
        case decelerating(DecelerationState)
        case idle
    }

    struct DragState {
        var offset: CGPoint
        var beganOffset: CGPoint
        var translation: CGSize
        var velocity: _Velocity<CGSize>
        var scrollingVertically: Bool
        var scrollingHorizontally: Bool
        var ended: Bool
    }

    struct DecelerationState {
        var targetOffset: CGPoint?
        var beginTime: Time?
        var completion: Completion?
        var simulation: Deceleration2D
    }

    struct ContainerInfo {
        weak var node: ScrollViewNode?
        var offset: CGPoint
        var seed: UInt32
    }

    var phase: Phase
    var seed: UInt32
    var containers: [ContainerInfo]

    init(
        phase: Phase = .idle,
        seed: UInt32 = 0,
        containers: [ContainerInfo] = []
    ) {
        self.phase = phase
        self.seed = seed
        self.containers = containers
    }

    @discardableResult
    mutating func resetDeceleration() -> Bool {
        guard case .decelerating(let state) = phase else {
            return false
        }
        if let completion = state.completion {
            enqueueCompletion(completion, finished: false)
        }
        phase = .idle
        seed &+= 1
        return true
    }

    @discardableResult
    mutating func updateDeceleration(
        node: ScrollViewNode,
        target: CGPoint?,
        velocity: _Velocity<CGSize>?,
        completion: Completion?
    ) -> Bool {
        if case .idle = phase {
            let requestedVelocity = velocity?.valuePerSecond ?? .zero
            let targetIsCurrent = target.map { $0 == node.presentationOffset } ?? true
            if targetIsCurrent && requestedVelocity == .zero {
                if let completion {
                    enqueueCompletion(completion, finished: true)
                }
                return false
            }
        }

        var deceleration: Deceleration2D
        var previousCompletion: Completion?

        switch phase {
        case .decelerating(let state):
            deceleration = state.simulation
            previousCompletion = state.completion
        case .dragging(let state):
            let sourceVelocity = velocity ?? state.velocity.negated()
            deceleration = Deceleration2D(
                offset: state.offset,
                velocity: sourceVelocity,
                decelerationRate: node.config.decelerationRate,
                target: target
            )
        case .idle:
            reloadContainers(node: node)
            deceleration = Deceleration2D(
                offset: node.presentationOffset,
                velocity: velocity ?? _Velocity(valuePerSecond: .zero),
                decelerationRate: node.config.decelerationRate,
                target: target
            )
        }

        deceleration.updateTarget(target)
        if let previousCompletion {
            enqueueCompletion(previousCompletion, finished: false)
        }

        phase = .decelerating(DecelerationState(
            targetOffset: target,
            beginTime: .systemUptime,
            completion: completion,
            simulation: deceleration
        ))
        seed &+= 1
        return true
    }

    func estimatedDeceleration(from offset: CGPoint, node: ScrollViewNode) -> CGPoint {
        let sourceOffset: CGPoint
        let sourceVelocity: _Velocity<CGSize>
        switch phase {
        case .decelerating(let state):
            if let targetOffset = state.targetOffset {
                return targetOffset
            }
            sourceOffset = state.simulation.offset
            sourceVelocity = state.simulation.velocity
        case .dragging(let state):
            sourceOffset = state.offset
            sourceVelocity = state.velocity.negated()
        case .idle:
            return offset
        }

        let velocity = sourceVelocity.valuePerSecond
        return CGPoint(
            x: sourceOffset.x + projectedDecelerationDistance(
                velocity: Double(velocity.width),
                decelerationRate: node.config.decelerationRate
            ),
            y: sourceOffset.y + projectedDecelerationDistance(
                velocity: Double(velocity.height),
                decelerationRate: node.config.decelerationRate
            )
        )
    }

    @discardableResult
    mutating func iterateDeceleration(
        node: ScrollViewNode,
        time: Time,
        offset: inout CGPoint,
        estimatedTarget: CGPoint?
    ) -> Bool {
        guard case .decelerating(var state) = phase else {
            return true
        }

        let elapsed: Double
        if let beginTime = state.beginTime {
            elapsed = time.seconds - beginTime.seconds
        } else {
            state.beginTime = Time(seconds: time.seconds - (1.0 / 60.0))
            elapsed = 1.0 / 60.0
        }

        let maxOffset = maxContentOffset(node: node)
        if state.simulation.iter(max(elapsed, 0), minValue: .zero, maxValue: maxOffset) {
            if let targetOffset = state.targetOffset {
                offset = _scrollViewClampContentOffset(targetOffset, maxContentOffset: maxOffset)
            }
            reset(completed: true)
            return true
        }

        if state.targetOffset == nil, let estimatedTarget {
            state.simulation.updateEstimatedTarget(estimatedTarget)
        }

        phase = .decelerating(state)
        seed &+= 1
        offset = overflowContentOffset(state.simulation.offset, node: node)
        return false
    }

    private mutating func reloadContainers(node: ScrollViewNode) {
        containers.removeAll(keepingCapacity: true)
        var parent = node.container
        var visited: Set<ObjectIdentifier> = []
        while let containerNode = parent,
              visited.insert(ObjectIdentifier(containerNode)).inserted {
            guard !containerNode.config.stopDraggingImmediately else {
                break
            }
            containerNode.behavior.revalidateContainersForReload(owner: containerNode)
            containerNode.behavior.resetContainersForReload()
            containers.append(ContainerInfo(
                node: containerNode,
                offset: containerNode.presentationOffset,
                seed: containerNode.behavior.seed
            ))
            parent = containerNode.container
        }
    }

    private mutating func revalidateContainersForReload(owner: ScrollViewNode) {
        let currentContainers = containers
        for container in currentContainers {
            guard let containerNode = container.node,
                  containerNode !== owner,
                  container.seed == containerNode.behavior.seed else {
                continue
            }
            _ = containerNode.commitContentOffset(
                container.offset,
                containerSize: containerNode.containerSize,
                config: containerNode.config
            )
        }
    }

    private mutating func resetContainersForReload() {
        if case .decelerating(let state) = phase,
           let completion = state.completion {
            enqueueCompletion(completion, finished: false)
        }
        phase = .idle
        seed &+= 1
        containers.removeAll(keepingCapacity: true)
    }

    private func enqueueCompletion(_ completion: @escaping Completion, finished: Bool) {
        Update.enqueueAction {
            completion(finished)
        }
    }

    private func projectedDecelerationDistance(
        velocity: Double,
        decelerationRate: Double
    ) -> CGFloat {
        let speed = abs(velocity)
        guard speed > scrollDecelerationLowVelocityThreshold else {
            return 0
        }
        let magnitude = speed *
            scrollDecelerationProjectionMultiplier *
            decelerationRate *
            ((-2.5 / speed) + 1) /
            (1 - decelerationRate)
        return CGFloat(velocity.sign == .minus ? -magnitude : magnitude)
    }

    private func maxContentOffset(node: ScrollViewNode) -> CGPoint {
        guard let contentSize = node.contentSize,
              let containerSize = node.containerSize else {
            return .zero
        }
        return _scrollViewMaxContentOffset(
            contentSize: contentSize,
            containerSize: containerSize,
            contentInsets: node.config.contentInsets
        )
    }

    mutating func overflowContentOffset(_ offset: CGPoint, node: ScrollViewNode) -> CGPoint {
        let maxOffset = maxContentOffset(node: node)
        let clamped = _scrollViewClampContentOffset(offset, maxContentOffset: maxOffset)
        var residue = CGSize(
            width: clamped.x - offset.x,
            height: clamped.y - offset.y
        )

        if case .dragging(let drag) = phase,
           !drag.ended,
           let containerSize = node.containerSize {
            residue = _scrollViewAddRubberBandingToResidue(
                residue,
                range: containerSize.inset(by: node.config.contentInsets)
            )
        }

        if maxOffset.x <= 0 && !node.config.alwaysBounceHorizontal {
            residue.width = 0
        }
        if maxOffset.y <= 0 && !node.config.alwaysBounceVertical {
            residue.height = 0
        }

        for index in containers.indices {
            guard let containerNode = containers[index].node,
                  containerNode !== node else {
                continue
            }

            if containers[index].seed != containerNode.behavior.seed {
                guard case .dragging(let drag) = phase, !drag.ended else {
                    break
                }
                containers[index].offset = containerNode.presentationOffset
                containers[index].seed = containerNode.behavior.seed
            }

            let containerMaxOffset = maxContentOffset(node: containerNode)
            let proposedOffset = CGPoint(
                x: containers[index].offset.x - residue.width,
                y: containers[index].offset.y - residue.height
            )
            let consumedOffset = _scrollViewClampContentOffset(
                proposedOffset,
                maxContentOffset: containerMaxOffset
            )

            guard consumedOffset != containerNode.presentationOffset else {
                continue
            }

            _ = containerNode.commitContentOffset(
                consumedOffset,
                containerSize: containerNode.containerSize,
                config: containerNode.config
            )
            residue.width -= containers[index].offset.x - consumedOffset.x
            residue.height -= containers[index].offset.y - consumedOffset.y
        }

        return CGPoint(
            x: clamped.x - residue.width,
            y: clamped.y - residue.height
        )
    }

    private mutating func reset(completed: Bool) {
        if case .decelerating(let state) = phase,
           let completion = state.completion {
            enqueueCompletion(completion, finished: completed)
        }
        phase = .idle
        seed &+= 1
    }
}

private extension _Velocity where Value == CGSize {
    func negated() -> _Velocity<CGSize> {
        map { CGSize(width: -$0.width, height: -$0.height) }
    }
}

struct ScrollViewCommitInfo {
    typealias ContentOffset = (CGPoint, bindingValue: CGPoint?)
    typealias TargetOffset = (
        CGPoint,
        bindingValue: CGPoint?,
        velocity: _Velocity<CGSize>?,
        completion: ScrollViewBehavior.Completion?
    )

    var contentOffset: ContentOffset
    var targetOffset: TargetOffset?

    init(
        contentOffset: ContentOffset,
        targetOffset: TargetOffset? = nil
    ) {
        self.contentOffset = contentOffset
        self.targetOffset = targetOffset
    }
}

typealias ScrollViewBindingOffset = (value: CGPoint, changed: Bool)

private let scrollViewContentOffsetBindingReadWarning =
    "ScrollView contentOffset binding has been read; this will cause grossly inefficient view performance as the ScrollView's content will be updated whenever its contentOffset changes. Read the contentOffset binding in a view that is not parented between the creator of the binding and the ScrollView to avoid this."

private final class ScrollViewNodeBindings {
    var proxy: Attribute<_ScrollViewProxy>?
    var geometry: Attribute<ScrollGeometry>?
    var layoutDirection: Attribute<LayoutDirection>?
    var childScrollables: Attribute<[any Scrollable]>?
}

nonisolated(unsafe) private var scrollViewNodeBindings: [ObjectIdentifier: ScrollViewNodeBindings] = [:]

private func _scrollViewNodeBindings(for node: ScrollViewNode) -> ScrollViewNodeBindings {
    let key = ObjectIdentifier(node)
    if let bindings = scrollViewNodeBindings[key] {
        return bindings
    }
    let bindings = ScrollViewNodeBindings()
    scrollViewNodeBindings[key] = bindings
    return bindings
}

private func _removeScrollViewNodeBindings(for node: ScrollViewNode) {
    scrollViewNodeBindings.removeValue(forKey: ObjectIdentifier(node))
}

final class ScrollViewNode {
    let host: AttributeGraphRef
    var attribute: WeakAttribute<CGPoint>
    var uniqueId: UInt32
    var modelOffset: CGPoint
    var presentationOffset: CGPoint
    var behavior: ScrollViewBehavior
    var isInitialized: Bool
    var resetSeed: UInt32
    var config: _ScrollViewConfig
    var contentSize: CGSize?
    var containerSize: CGSize?
    var decelerationTarget: CGPoint?
    weak var container: ScrollViewNode?
    var topScrollIndicatorFollowsContentOffset: Bool
    var pixelLength: Attribute<CGFloat>
    var propertySeed: UInt32

    init(
        graphRef: AttributeGraphRef,
        contentOffset: Attribute<CGPoint>,
        config: _ScrollViewConfig,
        pixelLength: Attribute<CGFloat>
    ) {
        let initialOffset = contentOffset.value
        self.host = graphRef
        self.attribute = contentOffset.asWeak()
        self.uniqueId = contentOffset.identifier.rawValue
        self.modelOffset = initialOffset
        self.presentationOffset = initialOffset
        self.behavior = ScrollViewBehavior()
        self.isInitialized = false
        self.resetSeed = 0
        self.config = config
        self.contentSize = nil
        self.containerSize = nil
        self.decelerationTarget = nil
        self.container = nil
        self.topScrollIndicatorFollowsContentOffset = false
        self.pixelLength = pixelLength
        self.propertySeed = 0
    }

    deinit {
        _removeScrollViewNodeBindings(for: self)
    }

    func bind(
        proxy: Attribute<_ScrollViewProxy>,
        geometry: Attribute<ScrollGeometry>,
        layoutDirection: Attribute<LayoutDirection>
    ) {
        let bindings = _scrollViewNodeBindings(for: self)
        bindings.proxy = proxy
        bindings.geometry = geometry
        bindings.layoutDirection = layoutDirection
    }

    func bindChildScrollables(_ childScrollables: Attribute<[any Scrollable]>) {
        _scrollViewNodeBindings(for: self).childScrollables = childScrollables
    }

    func withCurrent<R>(_ body: () -> R) -> R {
        host.withCurrent(body)
    }

    func updateConfig(_ config: _ScrollViewConfig) {
        self.config = config
    }

    @discardableResult
    func update(resetSeed: UInt32) -> Bool {
        guard self.resetSeed != resetSeed else {
            return false
        }
        self.resetSeed = resetSeed
        isInitialized = false
        return true
    }

    @discardableResult
    func commitContentOffset(
        _ offset: CGPoint,
        containerSize: CGSize? = nil,
        config: _ScrollViewConfig? = nil
    ) -> CGPoint {
        let resolvedContainerSize = containerSize ?? self.containerSize ?? currentProxy?.pageSize ?? .zero
        let resolvedConfig = config ?? currentProxy?.config ?? self.config
        let safeOffset = bindingSafeOffset(
            offset,
            containerSize: resolvedContainerSize,
            config: resolvedConfig
        )
        commitScrollTransaction(value: safeOffset, config: resolvedConfig)
        return safeOffset
    }

    func updateContentSize(
        _ newContentSize: CGSize,
        containerSize: CGSize,
        config: _ScrollViewConfig
    ) -> CGPoint {
        self.containerSize = containerSize
        guard contentSize != newContentSize else {
            return currentContentOffset
        }
        contentSize = newContentSize
        propertySeed &+= 1
        return clampContentOffset(containerSize: containerSize, config: config)
    }

    private func clampContentOffset(
        containerSize: CGSize,
        config: _ScrollViewConfig
    ) -> CGPoint {
        guard let contentSize else {
            return currentContentOffset
        }
        let maxOffset = _scrollViewMaxContentOffset(
            contentSize: contentSize,
            containerSize: containerSize,
            contentInsets: config.contentInsets
        )
        let current = currentContentOffset
        let clamped = _scrollViewClampContentOffset(current, maxContentOffset: maxOffset)
        guard clamped != current else {
            return current
        }
        return commitContentOffset(
            clamped,
            containerSize: containerSize,
            config: config
        )
    }

    private func bindingSafeOffset(
        _ offset: CGPoint,
        containerSize: CGSize,
        config: _ScrollViewConfig
    ) -> CGPoint {
        let rounded = pixelRounded(offset)
        guard let contentSize else {
            return rounded
        }
        let maxOffset = _scrollViewMaxContentOffset(
            contentSize: contentSize,
            containerSize: containerSize,
            contentInsets: config.contentInsets
        )
        return _scrollViewClampContentOffset(rounded, maxContentOffset: maxOffset)
    }

    private func pixelRounded(_ offset: CGPoint) -> CGPoint {
        let length = pixelLength.value
        guard length.isFinite, length > 0 else {
            return offset
        }
        if length == 1 {
            return CGPoint(x: offset.x.rounded(), y: offset.y.rounded())
        }
        return CGPoint(
            x: (offset.x / length).rounded() * length,
            y: (offset.y / length).rounded() * length
        )
    }

    private func commitScrollTransaction(value: CGPoint, config: _ScrollViewConfig) {
        let binding: Binding<CGPoint>?
        let bindingValue: CGPoint?
        switch config.contentOffset {
        case .initially:
            binding = nil
            bindingValue = nil
        case .binding(let contentOffsetBinding):
            binding = contentOffsetBinding
            bindingValue = contentOffsetBinding.wrappedValue
        }
        var transaction = Transaction.current
        transaction[scrollInfo: uniqueId] = ScrollViewCommitInfo(
            contentOffset: (value, bindingValue: bindingValue)
        )
        if let graphHost = host.context as? GraphHost {
            graphHost.emptyTransaction(transaction)
        }
        if updateContentOffset(in: transaction, bindingOffset: nil) {
            propertySeed &+= 1
        }
        attribute.toStrong().setValue(value, transaction: transaction)
        guard let binding, bindingValue != value else {
            return
        }
        Update.enqueueAction {
            withTransaction(transaction) {
                binding.wrappedValue = value
            }
        }
    }

    @discardableResult
    func updateContentOffset(
        in transaction: Transaction,
        bindingOffset: ScrollViewBindingOffset?
    ) -> Bool {
        initializeContentOffsetIfNeeded(bindingOffset: bindingOffset)

        if let commitInfo = transaction[scrollInfo: uniqueId] {
            return applyCommitInfo(commitInfo, bindingOffset: bindingOffset)
        }

        guard let bindingOffset,
              bindingOffset.changed,
              bindingOffset.value != modelOffset else {
            return false
        }

        modelOffset = bindingOffset.value
        if shouldWriteBindingChangeDirectly(in: transaction) {
            let didReset = behavior.resetDeceleration()
            let oldPresentation = presentationOffset
            presentationOffset = bindingOffset.value
            return didReset || oldPresentation != presentationOffset
        }
        _ = behavior.updateDeceleration(
            node: self,
            target: bindingOffset.value,
            velocity: nil,
            completion: nil
        )
        return true
    }

    private func initializeContentOffsetIfNeeded(bindingOffset: ScrollViewBindingOffset?) {
        guard !isInitialized else {
            return
        }
        isInitialized = true
        let initialOffset: CGPoint
        if let bindingOffset {
            initialOffset = bindingOffset.value
        } else {
            switch config.contentOffset {
            case .initially(let point):
                initialOffset = point
            case .binding(let binding):
                initialOffset = binding.wrappedValue
            }
        }
        modelOffset = initialOffset
        presentationOffset = initialOffset
    }

    private func applyCommitInfo(
        _ commitInfo: ScrollViewCommitInfo,
        bindingOffset: ScrollViewBindingOffset?
    ) -> Bool {
        let contentOffset = commitInfo.contentOffset.0
        let fallbackBindingValue = commitInfo.contentOffset.bindingValue ?? contentOffset
        guard let targetOffset = commitInfo.targetOffset else {
            let didReset = behavior.resetDeceleration()
            let oldModel = modelOffset
            let oldPresentation = presentationOffset
            modelOffset = bindingOffset?.value ?? fallbackBindingValue
            presentationOffset = contentOffset
            return didReset ||
                oldModel != modelOffset ||
                oldPresentation != presentationOffset
        }

        let targetBindingValue = targetOffset.bindingValue ?? targetOffset.0
        let bindingMatchesTarget = bindingOffset.map { $0.value == targetBindingValue } ?? true
        let effectiveTarget = bindingMatchesTarget ? Optional.some(targetOffset.0) : nil
        let oldModel = modelOffset
        modelOffset = bindingMatchesTarget ? targetBindingValue : contentOffset
        let didUpdate = behavior.updateDeceleration(
            node: self,
            target: effectiveTarget,
            velocity: targetOffset.velocity,
            completion: targetOffset.completion
        )
        return oldModel != modelOffset || didUpdate
    }

    private func shouldWriteBindingChangeDirectly(in transaction: Transaction) -> Bool {
        if transaction.disablesAnimations {
            return true
        }
        switch transaction._scrollViewAnimates {
        case .never:
            return true
        case .discreteChanges:
            return transaction.isContinuous
        case .always:
            return false
        }
    }

    var currentContentOffset: CGPoint {
        presentationOffset
    }

    var currentContentSize: CGSize? {
        contentSize
    }

    var currentGeometry: ScrollGeometry? {
        scrollViewNodeBindings[ObjectIdentifier(self)]?.geometry?.value
    }

    var currentLayoutDirection: LayoutDirection? {
        scrollViewNodeBindings[ObjectIdentifier(self)]?.layoutDirection?.value
    }

    var children: [any Scrollable]? {
        scrollViewNodeBindings[ObjectIdentifier(self)]?.childScrollables?.value
    }

    var currentProxy: _ScrollViewProxy? {
        scrollViewNodeBindings[ObjectIdentifier(self)]?.proxy?.value
    }
}

private struct ScrollViewUpdate<Provider>: StatefulRule where Provider: _ScrollableContentProvider {
    typealias Value = _ScrollViewProxy

    var _node: ScrollViewNode
    var _view: Attribute<_ScrollView<Provider>.Main>
    var _containerSize: Attribute<ViewSize>
    var _environment: Attribute<EnvironmentValues>
    var _time: Attribute<Time>
    var _transaction: Attribute<Transaction>
    var _phase: Attribute<Phase>
    var bindingWarned: Bool
    var bindingValue: CGPoint
    var bindingHadObservation: Bool

    init(
        _node: ScrollViewNode,
        _view: Attribute<_ScrollView<Provider>.Main>,
        _containerSize: Attribute<ViewSize>,
        _environment: Attribute<EnvironmentValues>,
        _time: Attribute<Time>,
        _transaction: Attribute<Transaction>,
        _phase: Attribute<Phase>
    ) {
        self._node = _node
        self._view = _view
        self._containerSize = _containerSize
        self._environment = _environment
        self._time = _time
        self._transaction = _transaction
        self._phase = _phase
        self.bindingWarned = false
        self.bindingValue = .zero
        self.bindingHadObservation = false
    }

    mutating func updateValue() {
        let current = _view.value
        _node.updateConfig(current.config)
        _node.update(resetSeed: _phase.value.resetSeed)
        _ = _environment.value
        let time = _time.value

        let sourceAttribute = _node.attribute.toStrong()
        _ = sourceAttribute.value
        let transaction = AttributeGraph.withoutTracking {
            _transaction.value
        }
        let pageSize = _containerSize.value.value
        _node.containerSize = pageSize

        warnIfBindingWasRead(in: current.config)
        let bindingOffset = updateBindingOffset(for: current.config)
        var nodeChanged = _node.updateContentOffset(in: transaction, bindingOffset: bindingOffset)
        let behaviorSeed = _node.behavior.seed
        var presentationOffset = _node.presentationOffset
        _ = _node.behavior.iterateDeceleration(
            node: _node,
            time: time,
            offset: &presentationOffset,
            estimatedTarget: _node.decelerationTarget
        )
        if presentationOffset != _node.presentationOffset {
            _node.presentationOffset = presentationOffset
            nodeChanged = true
        }
        if behaviorSeed != _node.behavior.seed {
            nodeChanged = true
        }
        if nodeChanged {
            _node.propertySeed &+= 1
        }

        AttributeGraph.setStatefulOutput(_ScrollViewProxy(
            config: current.config,
            contentOffset: _node.currentContentOffset,
            contentSize: _node.currentContentSize ?? pageSize,
            pageSize: pageSize
        ))
    }

    private mutating func warnIfBindingWasRead(in config: _ScrollViewConfig) {
        guard case .binding(let binding) = config.contentOffset,
              !bindingWarned,
              binding.location.wasReadValue() else {
            return
        }
        Log.warning(scrollViewContentOffsetBindingReadWarning)
        bindingWarned = true
    }

    private mutating func updateBindingOffset(
        for config: _ScrollViewConfig
    ) -> ScrollViewBindingOffset? {
        guard case .binding(let binding) = config.contentOffset else {
            bindingHadObservation = false
            bindingValue = .zero
            bindingWarned = false
            return nil
        }

        let observation = ObservationCenter.current._withObservationStashed {
            binding.location.update()
        }
        let (value, locationChanged) = observation.value
        let changed = locationChanged ||
            (bindingHadObservation && (bindingWarned || value != bindingValue))
        bindingValue = value
        bindingHadObservation = observation.accessOccurred
        bindingWarned = false
        return (value: value, changed: changed)
    }
}

private struct _ScrollViewMainScrollableProvider: Rule {
    typealias Value = any Scrollable

    var scrollable: _ScrollViewMainScrollable

    func updateValue() -> any Scrollable {
        scrollable
    }
}

private struct _ScrollViewDefaultLayoutResponderRule: StatefulRule {
    typealias Value = [any ViewResponder]

    var childResponders: Attribute<[any ViewResponder]>
    var responder: DefaultLayoutViewResponder?

    mutating func updateValue() {
        let currentResponder: DefaultLayoutViewResponder
        if let responder {
            currentResponder = responder
        } else {
            currentResponder = DefaultLayoutViewResponder()
            responder = currentResponder
        }
        currentResponder.update(responders: childResponders.value, scrollTarget: nil)
        AttributeGraph.setStatefulOutput([currentResponder])
    }
}

private final class _ScrollViewMainScrollable: Scrollable {
    private let node: ScrollViewNode
    private let parent: WeakAttribute<any Scrollable>

    init(node: ScrollViewNode, parent: WeakAttribute<any Scrollable>) {
        self.node = node
        self.parent = parent
    }

    static func node(
        from parent: WeakAttribute<any Scrollable>,
        graph: AttributeGraph
    ) -> ScrollViewNode? {
        guard parent.isValid(in: graph),
              let scrollable = parent.toStrong().value as? _ScrollViewMainScrollable else {
            return nil
        }
        return scrollable.node
    }

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        node.withCurrent {
            guard let children = node.children else { return false }
            for child in children {
                if child.scroll(to: id) {
                    return true
                }
            }
            return false
        }
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        node.withCurrent {
            guard let geometry = node.currentGeometry,
                  let layoutDirection = node.currentLayoutDirection,
                  let target = target(geometry, layoutDirection) else {
                return false
            }
            node.commitContentOffset(
                target.contentOffset(in: geometry),
                containerSize: geometry.containerSize,
                config: node.currentProxy?.config
            )
            return true
        }
    }

    var allowsContentOffsetAdjustments: Bool {
        true
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        node.withCurrent {
            let current = node.currentContentOffset
            node.commitContentOffset(
                CGPoint(
                    x: current.x + offset.width,
                    y: current.y + offset.height
                )
            )
            return true
        }
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        node.withCurrent {
            if let children = node.children {
                for child in children {
                    if let typedChild = child as? A {
                        return body(typedChild)
                    }
                    if let result = child.mapFirstChild(ofType: type, body: body) {
                        return result
                    }
                }
            }
            guard let graph = AttributeGraph.current,
                  parent.isValid(in: graph) else {
                return nil
            }
            return parent.toStrong().value.mapFirstChild(ofType: type, body: body)
        }
    }
}

private struct _ScrollViewMainGeometryProvider: Rule {
    typealias Value = ScrollGeometry

    var node: ScrollViewNode
    var proxy: Attribute<_ScrollViewProxy>
    var layoutComputer: OptionalAttribute<LayoutComputer>
    var layoutDirection: Attribute<LayoutDirection>

    func updateValue() -> ScrollGeometry {
        let proxyValue = proxy.value
        let containerSize = proxyValue.pageSize
        let proposedSize = containerSize.inset(by: proxyValue.config.contentInsets)
        let contentSize = layoutComputer.attribute?.value.sizeThatFits(
            ProposedViewSize(proposedSize)
        ) ?? proxyValue.contentSize
        let contentOffset = node.updateContentSize(
            contentSize,
            containerSize: containerSize,
            config: proxyValue.config
        )
        proxyValue._setContentSize(contentSize)
        proxyValue._setContentOffset(contentOffset)
        let visibleSize = containerSize.outset(by: proxyValue.config.contentInsets)
        var geometry = ScrollGeometry(
            contentOffset: contentOffset,
            contentSize: contentSize,
            contentInsets: proxyValue.config.contentInsets,
            containerSize: containerSize,
            visibleRect: CGRect(origin: contentOffset, size: visibleSize)
        )
        geometry.applyLayoutDirection(layoutDirection.value)
        return geometry
    }
}

private extension ScrollTarget {
    func contentOffset(in geometry: ScrollGeometry) -> CGPoint {
        guard let anchor else {
            return rect.origin
        }
        return CGPoint(
            x: rect.minX + rect.width * anchor.x - geometry.visibleRect.width * anchor.x,
            y: rect.minY + rect.height * anchor.y - geometry.visibleRect.height * anchor.y
        )
    }
}

/// Default root that mounts a provider's scroll-view main view directly.
public struct _ScrollViewRoot<P>: View where P: _ScrollableContentProvider {
    var scrollView: _ScrollView<P>.Main

    public var body: _ScrollView<P>.Main {
        scrollView
    }
}

/// Mutable scroll-view proxy shared with scrollable layout implementations.
public struct _ScrollViewProxy: Equatable {
    public var config: _ScrollViewConfig {
        storage.config
    }

    public var contentOffset: CGPoint {
        get { storage.contentOffset }
        set { storage.contentOffset = newValue }
    }

    public var minContentOffset: CGPoint { .zero }
    public var maxContentOffset: CGPoint {
        _scrollViewMaxContentOffset(
            contentSize: contentSize,
            containerSize: pageSize,
            contentInsets: config.contentInsets
        )
    }
    public var contentSize: CGSize { storage.contentSize }
    public var pageSize: CGSize { storage.pageSize }
    public var visibleRect: CGRect {
        CGRect(
            x: contentOffset.x - config.contentInsets.leading,
            y: contentOffset.y - config.contentInsets.top,
            width: pageSize.width,
            height: pageSize.height
        )
    }
    public var isDragging: Bool { false }
    public var isDecelerating: Bool { false }
    public var isScrolling: Bool { isDragging || isDecelerating }
    public var isScrollingHorizontally: Bool { false }
    public var isScrollingVertically: Bool { false }

    private var storage: Storage

    init(
        config: _ScrollViewConfig = _ScrollViewConfig(),
        contentOffset: CGPoint = .zero,
        contentSize: CGSize = .zero,
        pageSize: CGSize = .zero
    ) {
        self.storage = Storage(
            config: config,
            contentOffset: contentOffset,
            contentSize: contentSize,
            pageSize: pageSize
        )
    }

    public func setContentOffset(
        _ newOffset: CGPoint,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        completion?(false)
    }

    public func scrollRectToVisible(
        _ rect: CGRect,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        completion?(false)
    }

    public func contentOffsetOfNextPage(_ directions: _EventDirections) -> CGPoint {
        contentOffset
    }

    func _setContentOffset(_ contentOffset: CGPoint) {
        storage.contentOffset = contentOffset
    }

    func _setContentSize(_ contentSize: CGSize) {
        storage.contentSize = contentSize
    }

    public static func == (lhs: _ScrollViewProxy, rhs: _ScrollViewProxy) -> Bool {
        lhs.storage === rhs.storage
    }

    private final class Storage {
        var config: _ScrollViewConfig
        var contentOffset: CGPoint
        var contentSize: CGSize
        var pageSize: CGSize

        init(
            config: _ScrollViewConfig,
            contentOffset: CGPoint,
            contentSize: CGSize,
            pageSize: CGSize
        ) {
            self.config = config
            self.contentOffset = contentOffset
            self.contentSize = contentSize
            self.pageSize = pageSize
        }
    }
}

/// Layout protocol that chooses visible scroll items and their placements.
public protocol _ScrollableLayout: Animatable {
    associatedtype StateType = Void
    static func initialState() -> Self.StateType
    func update(state: inout Self.StateType, proxy: inout _ScrollableLayoutProxy)

    associatedtype ItemModifier: ViewModifier = EmptyModifier
    func modifier(
        for item: _ScrollableLayoutItem,
        layout: _ScrollLayout,
        state: Self.StateType
    ) -> Self.ItemModifier

    func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint?
}

extension _ScrollableLayout where Self.StateType == Void {
    public static func initialState() -> Self.StateType {
        ()
    }
}

extension _ScrollableLayout where Self.ItemModifier == EmptyModifier {
    public func modifier(
        for item: _ScrollableLayoutItem,
        layout: _ScrollLayout,
        state: Self.StateType
    ) -> Self.ItemModifier {
        EmptyModifier()
    }
}

extension _ScrollableLayout {
    public func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint? {
        nil
    }

    public subscript<T>(data: T) -> _ScrollView<_ScrollableLayoutView<T, Self>>
        where T: RandomAccessCollection, T.Element: View, T.Index: Hashable {
        _ScrollView(contentProvider: _ScrollableLayoutView(data: data, layout: self))
    }
}

extension _ScrollableLayout where Self: RandomAccessCollection, Self.Element: View, Self.Index: Hashable {
    public subscript() -> _ScrollView<_ScrollableLayoutView<Self, Self>> {
        _ScrollView(contentProvider: _ScrollableLayoutView(data: self, layout: self))
    }
}

/// Mutable proxy used by scrollable layouts to measure and publish visible items.
public struct _ScrollableLayoutProxy: RandomAccessCollection {
    struct SizeRecord {
        var contentSeed: UInt32
        var proposal: CGSize
        var size: CGSize
    }

    final class Storage {
        var cachedSizes: [AnyHashable: SizeRecord] = [:]
    }

    public let size: CGSize
    public let visibleRect: CGRect
    public let count: Int
    public var visibleItems: [_ScrollableLayoutItem]
    public var contentSize: CGSize
    public var validRect: CGRect

    private var identifiers: [AnyHashable]
    private var contentSeed: UInt32
    private var storage: Storage
    private var measure: (AnyHashable, CGSize) -> CGSize

    init<Data>(
        data: Data,
        size: CGSize,
        visibleRect: CGRect,
        contentSeed: UInt32 = 0,
        storage: Storage = Storage(),
        measure: @escaping (AnyHashable, CGSize) -> CGSize = { _, size in size }
    ) where Data: RandomAccessCollection, Data.Index: Hashable {
        var identifiers: [AnyHashable] = []
        var index = data.startIndex
        while index != data.endIndex {
            identifiers.append(AnyHashable(index))
            index = data.index(after: index)
        }
        self.size = size
        self.visibleRect = visibleRect
        self.count = identifiers.count
        self.visibleItems = []
        self.contentSize = size
        self.validRect = visibleRect
        self.identifiers = identifiers
        self.contentSeed = contentSeed
        self.storage = storage
        self.measure = measure
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public subscript(index: Int) -> AnyHashable {
        identifiers[index]
    }

    public mutating func size(
        of identifier: AnyHashable,
        in size: CGSize,
        validatingContent: Bool = true
    ) -> CGSize {
        if let cached = storage.cachedSizes[identifier],
           cached.proposal == size,
           (!validatingContent || cached.contentSeed == contentSeed) {
            return cached.size
        }
        let measuredSize = measure(identifier, size)
        storage.cachedSizes[identifier] = SizeRecord(
            contentSeed: contentSeed,
            proposal: size,
            size: measuredSize
        )
        return measuredSize
    }

    public mutating func size(
        at index: Int,
        in size: CGSize,
        validatingContent: Bool = true
    ) -> CGSize {
        self.size(of: self[index], in: size, validatingContent: validatingContent)
    }

    public mutating func removeSize(of identifier: AnyHashable) {
        storage.cachedSizes.removeValue(forKey: identifier)
    }

    public mutating func removeAllSizes() {
        storage.cachedSizes.removeAll()
    }
}

/// One item placement emitted by a scrollable layout.
public struct _ScrollableLayoutItem: Equatable {
    public var id: AnyHashable
    private var placement: _Placement

    public var proposedSize: CGSize {
        placement.proposedSize
    }

    public var anchor: UnitPoint {
        placement.anchor
    }

    public var anchorPosition: CGPoint {
        placement.anchorPosition
    }

    public init(
        id: AnyHashable,
        proposedSize: CGSize,
        anchoring anchor: UnitPoint = .topLeading,
        at position: CGPoint
    ) {
        self.id = id
        self.placement = _Placement(
            proposedSize: proposedSize,
            anchoring: anchor,
            at: position
        )
    }

    fileprivate init(id: AnyHashable, placement: _Placement) {
        self.id = id
        self.placement = placement
    }

    var _placement: _Placement {
        placement
    }

    public static func == (a: _ScrollableLayoutItem, b: _ScrollableLayoutItem) -> Bool {
        a.id == b.id && a.placement == b.placement
    }
}

/// View wrapper that turns a random-access collection into a scrollable dynamic list.
public struct _ScrollableLayoutView<Data, Layout>: View
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Element: View,
          Data.Index: Hashable {

    var data: Data
    var layout: Layout

    init(data: Data, layout: Layout) {
        self.data = data
        self.layout = layout
    }

    public typealias Body = Never

    public var body: Never {
        neverBody()
    }

    public static func _makeView(
        view: _GraphValue<_ScrollableLayoutView<Data, Layout>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("_ScrollableLayoutView._makeView called outside an active AttributeGraph context.")
        }

        let layoutState: Attribute<ScrollableLayoutStateValue<Data, Layout>> = graph.makeStatefulRule(
            ScrollableLayoutStateRule(
                data: view[\.data]._attribute,
                layout: view[\.layout]._attribute,
                scrollView: inputs[ScrollableLayoutScrollViewProxyKey.self],
                inputs: inputs
            )
        )
        let listState = ScrollableLayoutViewListState<Data, Layout>(
            view: view._attribute,
            layoutState: layoutState,
            inputs: _ViewListInputs(from: inputs)
        )
        let viewListAttr: Attribute<any ViewList> = graph.makeRule {
            guard let graph = AttributeGraph.current else {
                fatalError("ScrollableLayoutView view-list rule evaluated outside an active AttributeGraph context.")
            }
            let state = layoutState.value
            let current = view._attribute.value
            listState.update(view: current, state: state, graph: graph)
            return ScrollableLayoutViewList(state: listState, seed: listState.seed)
        }

        var dynamicInputs = inputs
        dynamicInputs[DynamicContainerMaxUnusedItems.self] = 1
        let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
            inputs.base.cachedEnvironment.value.environment.value.layoutDirection
        }
        dynamicInputs[ScrollableLayoutItemGeometryContextKey.self] = ScrollableLayoutItemGeometryContext(
            layoutDirection: layoutDirection,
            placement: { identifier in
                layoutState.value.placement(for: identifier)
            }
        )
        let geometryContext = dynamicInputs[ScrollableLayoutItemGeometryContextKey.self]
        let containerInfo: Attribute<DynamicContainer.Info> = graph.makeStatefulRule(
            DynamicContainerInfo(viewListAttr: viewListAttr, inputs: dynamicInputs)
        )
        geometryContext?.containerInfo = containerInfo
        let layoutComputer: Attribute<LayoutComputer> = graph.makeRule(
            ScrollableLayoutComputerRule(layoutState: layoutState, containerInfo: containerInfo)
        )
        let childGeometries: Attribute<[ViewGeometry]> = graph.makeRule(
            LayoutChildGeometries(
                parentSize: inputs.size,
                parentPosition: inputs.position,
                layoutComputer: layoutComputer
            )
        )

        var preferences = PreferencesOutputs()
        var childScrollables: Attribute<ScrollablePreferenceKey.Value>?
        for keyType in inputs.preferences.keys.keys {
            let nodeListAttr: Attribute<[AGWeakAttribute]> = graph.makeRule {
                let info = containerInfo.value
                return info.activeAndRemovedItems.flatMap { item in
                    item.preferenceOutputs.flatMap { preferences in
                        preferences.values(for: keyType).compactMap {
                            graph.weakAttributeIfValid(for: $0)
                        }
                    }
                }
            }
            let reducedID = _makeDynReduceAttr(keyType, nodeListAttr: nodeListAttr, in: graph)
            preferences.append(keyType, node: reducedID)
            if ObjectIdentifier(keyType) == ObjectIdentifier(ScrollablePreferenceKey.self) {
                childScrollables = Attribute<ScrollablePreferenceKey.Value>(reducedID)
            }
        }

        let parentScrollable = inputs.weakScrollable
        let data = view[\.data]._attribute
        let collection: Attribute<any ScrollableCollection> = graph.makeRule {
            ScrollableLayoutCollection(
                data: data,
                layoutState: layoutState,
                containerInfo: containerInfo,
                childGeometries: childGeometries,
                parentScrollable: parentScrollable,
                childScrollables: childScrollables
            ) as any ScrollableCollection
        }
        if inputs.preferences.keys.contains(ScrollTargetRole.ContentKey.self),
           let role = inputs.scrollTargetRole.attribute {
            let transform: Attribute<(inout ScrollTargetRole.ContentKey.Value) -> Void> = graph.makeRule(
                ScrollTargetRole.SetLayout(role: role, collection: collection)
            )
            preferences.makePreferenceTransformer(
                key: ScrollTargetRole.ContentKey.self,
                transformAttr: transform,
                graph: graph
            )
        }
        if inputs.preferences.keys.contains(ScrollTargetRole.Key.self),
           let role = inputs.scrollTargetRole.attribute {
            let transform: Attribute<(inout ScrollTargetRole.Key.Value) -> Void> = graph.makeRule(
                ScrollTargetRole.SetLayout(role: role, collection: collection)
            )
            preferences.makePreferenceTransformer(
                key: ScrollTargetRole.Key.self,
                transformAttr: transform,
                graph: graph
            )
        }
        if inputs.preferences.keys.contains(ScrollablePreferenceKey.self) {
            let transform: Attribute<(inout ScrollablePreferenceKey.Value) -> Void> = graph.makeRule {
                let scrollable = collection.value as any Scrollable
                return { value in
                    ScrollablePreferenceKey.reduce(value: &value) { [scrollable] }
                }
            }
            preferences.makePreferenceTransformer(
                key: ScrollablePreferenceKey.self,
                transformAttr: transform,
                graph: graph
            )
        }
        if inputs.preferences.keys.contains(UpdateScrollStateRequestKey.self) {
            let requests: Attribute<UpdateScrollStateRequestKey.Value> = graph.makeStatefulRule(
                ScrollStateRequestTransform(collection: collection, inputs: inputs)
            )
            let transform: Attribute<(inout UpdateScrollStateRequestKey.Value) -> Void> = graph.makeRule {
                let requests = requests.value
                return { value in
                    UpdateScrollStateRequestKey.reduce(value: &value) { requests }
                }
            }
            preferences.makePreferenceTransformer(
                key: UpdateScrollStateRequestKey.self,
                transformAttr: transform,
                graph: graph
            )
        }

        return _ViewOutputs(
            preferences: preferences,
            layoutComputer: OptionalAttribute(layoutComputer)
        )
    }
}

extension _ScrollableLayoutView: _PrimitiveView {
}

extension _ScrollableLayoutView: _ScrollableContentProvider {
    public var scrollableContent: _ScrollableLayoutView<Data, Layout> {
        self
    }

    public func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint? {
        layout.decelerationTarget(
            contentOffset: contentOffset,
            originalContentOffset: originalContentOffset,
            velocity: velocity,
            size: size
        )
    }
}

/// Maximum retained-unused dynamic items a scrollable layout may keep alive.
struct DynamicContainerMaxUnusedItems: ViewInput {
    static var defaultValue: Int { 0 }
}

/// Carries the scroll-view proxy into scrollable layout construction.
private struct ScrollableLayoutScrollViewProxyKey: ViewInput {
    static var defaultValue: OptionalAttribute<_ScrollViewProxy> { OptionalAttribute() }

    static func valuesEqual(
        _ lhs: OptionalAttribute<_ScrollViewProxy>,
        _ rhs: OptionalAttribute<_ScrollViewProxy>
    ) -> Bool {
        lhs.base.identifier == rhs.base.identifier
    }
}

/// Cached scrollable layout output shared by measurement, view-list, and placement rules.
private struct ScrollableLayoutStateValue<Data, Layout>
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Index: Hashable {

    var layoutState: Layout.StateType
    var stateSeed: UInt32
    var contentSeed: UInt32
    var scrollLayout: _ScrollLayout
    var identifiers: [Data.Index]
    var placements: [Data.Index: _Placement]
    var contentSize: CGSize
    var validRect: CGRect

    var visibleItems: [_ScrollableLayoutItem] {
        identifiers.compactMap { index in
            guard let placement = placements[index] else { return nil }
            return _ScrollableLayoutItem(id: AnyHashable(index), placement: placement)
        }
    }

    func placement(for identifier: AnyHashable) -> _Placement? {
        guard let index = identifier.base as? Data.Index else { return nil }
        return placements[index]
    }
}

private struct ScrollableLayoutCollection<Data, Layout>: ScrollableCollection
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Index: Hashable {

    var data: Attribute<Data>
    var layoutState: Attribute<ScrollableLayoutStateValue<Data, Layout>>
    var containerInfo: Attribute<DynamicContainer.Info>
    var childGeometries: Attribute<[ViewGeometry]>
    var parentScrollable: WeakAttribute<any Scrollable>
    var childScrollables: Attribute<[any Scrollable]>?

    var visibleCollectionViewIDs: [_ViewList_ID.Canonical] {
        layoutState.value.identifiers.map { canonicalID(for: $0) }
    }

    func forEachVisibleSubview(_ body: (ScrollableCollectionSubview, inout Bool) -> Void) {
        let state = layoutState.value
        let geometries = childGeometries.value
        for (offset, index) in state.identifiers.enumerated() {
            guard let placement = state.placements[index] else { continue }
            var stop = false
            let frame = frame(for: geometries, at: offset) ?? frame(for: placement)
            body(
                ScrollableCollectionSubview(
                    id: _ViewList_ID(explicitID: AnyHashable(index)),
                    frame: frame,
                    frameInContent: frame,
                    transform: .identity
                ),
                &stop
            )
            if stop { break }
        }
    }

    func subviewClosest(to rect: CGRect) -> ScrollableCollectionSubview? {
        var closest: (subview: ScrollableCollectionSubview, distance: CGFloat)?
        forEachVisibleSubview { subview, stop in
            let distance = subview.frame.midpointDistance(to: rect)
            if closest == nil || distance < closest!.distance {
                closest = (subview, distance)
            }
            stop = false
        }
        return closest?.subview
    }

    func nextVisibleCollectionViewID(
        towards point: UnitPoint,
        from id: _ViewList_ID.Canonical,
        border: CGSize,
        ignoring pinnedViews: PinnedScrollableViews
    ) -> _ViewList_ID.Canonical? {
        nil
    }

    static func hasMultipleViews(in axis: Axis) -> Bool {
        false
    }

    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int? {
        allCollectionViewIDs.firstIndex(of: id)
    }

    func applyCollectionViewIDs(
        from index: inout Int,
        to body: (_ViewList_ID.Canonical, inout Bool) -> Void
    ) -> Bool {
        let ids = allCollectionViewIDs
        guard index < ids.count else { return false }

        while index < ids.count {
            var stop = false
            body(ids[index], &stop)
            index += 1
            if stop { return false }
        }
        return true
    }

    func collectionViewID(for subgraph: AGSubgraph) -> _ViewList_ID.Canonical? {
        containerInfo.value.item(for: subgraph)?.uniqueId
    }

    func scroll(toCollectionViewID id: _ViewList_ID.Canonical, anchor: UnitPoint?) -> Bool {
        let state = layoutState.value
        guard let index = state.identifiers.first(where: { canonicalID(for: $0) == id }),
              let placement = state.placements[index] else {
            return false
        }
        let rect = frame(for: placement)
        return setContentTarget { _, _ in
            ScrollTarget(rect: rect, anchor: anchor)
        }
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        if let parent = resolvedParentScrollable,
           parent.setContentTarget(target) {
            return true
        }
        guard let childScrollables else { return false }
        for child in childScrollables.value {
            if child.setContentTarget(target) {
                return true
            }
        }
        return false
    }

    var allowsContentOffsetAdjustments: Bool {
        resolvedParentScrollable?.allowsContentOffsetAdjustments ?? false
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        guard let parent = resolvedParentScrollable else { return false }
        return parent.adjustContentOffset(by: offset, reason: reason)
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        nil
    }

    private func canonicalID(for index: Data.Index) -> _ViewList_ID.Canonical {
        _ViewList_ID(explicitID: AnyHashable(index)).canonicalID
    }

    private var allCollectionViewIDs: [_ViewList_ID.Canonical] {
        data.value.indices.map { canonicalID(for: $0) }
    }

    private func frame(for placement: _Placement) -> CGRect {
        let size = placement.proposedSize
        return CGRect(
            x: placement.anchorPosition.x - size.width * placement.anchor.x,
            y: placement.anchorPosition.y - size.height * placement.anchor.y,
            width: size.width,
            height: size.height
        )
    }

    private func frame(for geometries: [ViewGeometry], at offset: Int) -> CGRect? {
        guard geometries.indices.contains(offset) else { return nil }
        let geometry = geometries[offset]
        return CGRect(
            origin: geometry.origin,
            size: geometry.dimensions.size.value
        )
    }

    private var resolvedParentScrollable: (any Scrollable)? {
        guard let graph = AttributeGraph.current,
              parentScrollable.isValid(in: graph) else {
            return nil
        }
        return parentScrollable.toStrong().value
    }
}

private extension CGRect {
    func midpointDistance(to other: CGRect) -> CGFloat {
        let dx = midX - other.midX
        let dy = midY - other.midY
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Stateful rule that updates scroll layout state, content seed, and measurement cache.
private struct ScrollableLayoutStateRule<Data, Layout>: StatefulRule
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Element: View,
          Data.Index: Hashable {

    typealias Value = ScrollableLayoutStateValue<Data, Layout>

    var data: Attribute<Data>
    var layout: Attribute<Layout>
    var scrollView: OptionalAttribute<_ScrollViewProxy>
    var inputs: _ViewInputs
    var layoutState: Layout.StateType = Layout.initialState()
    var stateSeed: UInt32 = 0
    var contentSeed: UInt32 = 0
    var proxyStorage = _ScrollableLayoutProxy.Storage()
    var measurementTemplate: ScrollableLayoutMeasurementTemplate<Data>?

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("ScrollableLayoutStateRule.updateValue called outside an active AttributeGraph context.")
        }
        let dataValue = data.value
        let layoutValue = layout.value
        let proxyValue = scrollView.attribute?.value
        let containerSize = proxyValue?.pageSize ?? inputs.size.value.value
        let contentInsets = proxyValue?.config.contentInsets ?? EdgeInsets()
        let visibleSize = containerSize.inset(by: contentInsets)
        let contentOffset = proxyValue?.contentOffset ?? .zero
        let visibleRect = CGRect(
            x: contentOffset.x - contentInsets.leading,
            y: contentOffset.y - contentInsets.top,
            width: visibleSize.width,
            height: visibleSize.height
        )
        let scrollLayout = _ScrollLayout(
            contentOffset: contentOffset,
            size: visibleSize,
            visibleRect: visibleRect
        )
        if measurementTemplate == nil, let first = dataValue.first {
            measurementTemplate = ScrollableLayoutMeasurementTemplate(
                initialContent: first,
                inputs: inputs,
                graph: graph
            )
        }

        let previous = AttributeGraph.currentStatefulOutput(Value.self)
        let firstEvaluation = previous == nil
        let contentChanged = firstEvaluation ||
            AttributeGraph.currentStatefulInputChanged(data.identifier)
        let layoutChanged = firstEvaluation ||
            AttributeGraph.currentStatefulInputChanged(layout.identifier)
        if contentChanged {
            contentSeed &+= 1
        }
        let template = measurementTemplate

        if !layoutChanged,
           !contentChanged,
           let previous,
           previous.scrollLayout.size == scrollLayout.size,
           previous.validRect.contains(scrollLayout.visibleRect) {
            var value = previous
            value.scrollLayout = scrollLayout
            AttributeGraph.setStatefulOutput(value)
            return
        }

        var proxy = _ScrollableLayoutProxy(
            data: dataValue,
            size: visibleSize,
            visibleRect: visibleRect,
            contentSeed: contentSeed,
            storage: proxyStorage
        ) { identifier, proposedSize in
            guard let index = identifier.base as? Data.Index,
                  dataValue.indices.contains(index),
                  let template else {
                return proposedSize
            }
            return template.sizeThatFits(proposedSize, content: dataValue[index])
        }
        layoutValue.update(state: &layoutState, proxy: &proxy)

        var identifiers: [Data.Index] = []
        var placements: [Data.Index: _Placement] = [:]
        for item in proxy.visibleItems {
            guard let index = item.id.base as? Data.Index else { continue }
            identifiers.append(index)
            placements[index] = item._placement
        }

        // State changes every layout update; content changes only when the source
        // view payload changes, so proxy size caches survive pure geometry updates.
        stateSeed &+= 1
        AttributeGraph.setStatefulOutput(
            ScrollableLayoutStateValue<Data, Layout>(
                layoutState: layoutState,
                stateSeed: stateSeed,
                contentSeed: contentSeed,
                scrollLayout: scrollLayout,
                identifiers: identifiers,
                placements: placements,
                contentSize: proxy.contentSize,
                validRect: proxy.validRect
            )
        )
    }
}

/// Reusable hidden child used to measure arbitrary collection elements off the main list.
private final class ScrollableLayoutMeasurementTemplate<Data>
    where Data: RandomAccessCollection,
          Data.Element: View,
          Data.Index: Hashable {

    private let subgraph: AGSubgraph
    private let content: Attribute<Data.Element>
    private let delta: Attribute<UInt32>
    private let outputs: _ViewOutputs
    private var seed: UInt32 = 0

    init(
        initialContent: Data.Element,
        inputs: _ViewInputs,
        graph: AttributeGraph
    ) {
        let subgraph = AGSubgraph()
        let built = AGSubgraph.$current.withValue(subgraph) {
            var templateInputs = inputs
            templateInputs.copyCaches()
            templateInputs.position = graph.makeInput(value: CGPoint.zero)
            templateInputs.size = graph.makeInput(value: ViewSize(.zero))
            templateInputs.containerPosition = inputs.position
            templateInputs.containerSize = OptionalAttribute(inputs.size)

            let content = graph.makeInput(value: initialContent)
            let delta = graph.makeInput(value: UInt32.zero)
            let gatedContent: Attribute<Data.Element> = graph.makeRule {
                _ = delta.value
                return content.value
            }
            let outputs = Data.Element._makeView(
                view: _GraphValue(_attribute: gatedContent),
                inputs: templateInputs
            )
            return (content, delta, outputs)
        }

        self.subgraph = subgraph
        self.content = built.0
        self.delta = built.1
        self.outputs = built.2
    }

    deinit {
        guard AttributeGraph.current != nil else { return }
        subgraph.invalidate()
        subgraph.removeFromParent()
    }

    func sizeThatFits(_ proposal: CGSize, content newContent: Data.Element) -> CGSize {
        seed &+= 1
        delta.setValue(seed)
        content.setValue(newContent)
        let layoutComputer = outputs._layoutComputer.attribute?.value ?? LayoutComputer.defaultValue
        return layoutComputer.sizeThatFits(ProposedViewSize(proposal))
    }
}

/// Owns per-visible-item subgraphs and retains a small unused tail for scroll reuse.
private final class ScrollableLayoutViewListState<Data, Layout>
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Element: View,
          Data.Index: Hashable {

    typealias RowContent = ModifiedContent<Data.Element, Layout.ItemModifier>

    struct Item {
        var elements: _ViewList_SubgraphElements
        var subgraph: AGSubgraph
        var traitListAttr: OptionalAttribute<ViewTraitCollection>

        var traits: ViewTraitCollection {
            traitListAttr.attribute?.value ?? ViewTraitCollection()
        }

        func invalidate() {
            subgraph.invalidate()
            subgraph.removeFromParent()
        }
    }

    var view: Attribute<_ScrollableLayoutView<Data, Layout>>
    var layoutState: Attribute<ScrollableLayoutStateValue<Data, Layout>>
    var inputs: _ViewListInputs
    var items: [AnyHashable: Item] = [:]
    var order: [AnyHashable] = []
    var seed: UInt32 = 0

    init(
        view: Attribute<_ScrollableLayoutView<Data, Layout>>,
        layoutState: Attribute<ScrollableLayoutStateValue<Data, Layout>>,
        inputs: _ViewListInputs
    ) {
        self.view = view
        self.layoutState = layoutState
        self.inputs = inputs
    }

    func update(
        view current: _ScrollableLayoutView<Data, Layout>,
        state: ScrollableLayoutStateValue<Data, Layout>,
        graph: AttributeGraph
    ) {
        var nextOrder: [AnyHashable] = []
        var liveIDs = Set<AnyHashable>()

        for visibleItem in state.visibleItems {
            guard let index = visibleItem.id.base as? Data.Index,
                  current.data.indices.contains(index) else {
                continue
            }

            let id = visibleItem.id
            nextOrder.append(id)
            liveIDs.insert(id)

            if items[id] == nil {
                let subgraph = AGSubgraph()
                let contentAttr: Attribute<RowContent> = AGSubgraph.$current.withValue(subgraph) {
                    graph.makeRule {
                        let current = self.view.value
                        let state = self.layoutState.value
                        let element = current.data[index]
                        let item = state.visibleItems.first { $0.id == id } ?? visibleItem
                        let modifier = current.layout.modifier(
                            for: item,
                            layout: state.scrollLayout,
                            state: state.layoutState
                        )
                        return ModifiedContent(content: element, modifier: modifier)
                    }
                }
                let generator = TypedUnaryViewGenerator(
                    _GraphValue(_attribute: contentAttr),
                    inputs: inputs
                )
                var elements = _ViewList_SubgraphElements(base: UnaryElements(generator: generator))
                elements.wrap(subgraph: _ViewList_Subgraph(subgraph: subgraph))
                items[id] = Item(
                    elements: elements,
                    subgraph: subgraph,
                    traitListAttr: generator.traitListAttr
                )
            }
        }

        var retainedUnused = Set<AnyHashable>()
        for id in order where !liveIDs.contains(id) && retainedUnused.count < 1 {
            retainedUnused.insert(id)
        }
        for id in Array(items.keys) where !liveIDs.contains(id) && !retainedUnused.contains(id) {
            items[id]?.invalidate()
            items.removeValue(forKey: id)
        }

        if nextOrder != order {
            seed &+= 1
            order = nextOrder
        }
    }
}

/// ViewList facade over the visible item subgraphs owned by ScrollableLayoutViewListState.
private struct ScrollableLayoutViewList<Data, Layout>: ViewList
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Element: View,
          Data.Index: Hashable {

    var state: ScrollableLayoutViewListState<Data, Layout>
    var seed: UInt32

    func count(style: _ViewList_IteratorStyle) -> Int {
        state.order.count
    }

    func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
        state.order.count
    }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        for id in state.order {
            guard let item = state.items[id] else { continue }
            if from > 0 {
                from -= 1
                continue
            }
            let sublist = _ViewList_Sublist(
                start: 0,
                count: 1,
                id: _ViewList_ID(explicitID: id),
                elements: item.elements,
                traits: item.traits,
                list: list
            )
            let shouldContinue = to(&from, style, .sublist(sublist), transform)
            from = 0
            if !shouldContinue { return false }
        }
        return true
    }
}

/// Builds a layout computer that places retained dynamic item layout computers.
private struct ScrollableLayoutComputerRule<Data, Layout>: Rule
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Index: Hashable {

    typealias Value = LayoutComputer

    var layoutState: Attribute<ScrollableLayoutStateValue<Data, Layout>>
    var containerInfo: Attribute<DynamicContainer.Info>

    func updateValue() -> LayoutComputer {
        let state = layoutState.value
        let info = containerInfo.value
        let activeItems = Array(info.activeItems)
        let contentSize = state.contentSize
        let placements = state.placements

        for item in activeItems {
            _ = item.layoutAttributes.first?.layoutComputer.attribute?.value
        }

        return LayoutComputer(
            sizeThatFits: { proposal in
                contentSize == .zero ? proposal.replacingUnspecifiedDimensions() : contentSize
            },
            place: { position, anchor, proposal in
                let origin = CGPoint(
                    x: position.x - contentSize.width * anchor.x,
                    y: position.y - contentSize.height * anchor.y
                )
                for item in activeItems {
                    guard let index = item.item?.base as? Data.Index,
                          let placement = placements[index],
                          let childComputer = item.layoutAttributes.first?.layoutComputer.attribute?.value else {
                        continue
                    }
                    let anchorPosition = CGPoint(
                        x: origin.x + placement.anchorPosition.x,
                        y: origin.y + placement.anchorPosition.y
                    )
                    childComputer.place(
                        at: anchorPosition,
                        anchor: placement.anchor,
                        proposal: ProposedViewSize(placement.proposedSize)
                    )
                }
            },
            childGeometries: { _, origin in
                activeItems.compactMap { item in
                    guard let index = item.item?.base as? Data.Index,
                          let placement = placements[index],
                          let childComputer = item.layoutAttributes.first?.layoutComputer.attribute?.value else {
                        return nil
                    }
                    let proposedSize = placement.proposedSize
                    let childOrigin = CGPoint(
                        x: origin.x + placement.anchorPosition.x - proposedSize.width * placement.anchor.x,
                        y: origin.y + placement.anchorPosition.y - proposedSize.height * placement.anchor.y
                    )
                    return ViewGeometry(
                        origin: childOrigin,
                        dimensions: ViewDimensions(
                            guideComputer: childComputer,
                            size: ViewSize(proposedSize, proposal: ProposedViewSize(proposedSize))
                        )
                    )
                }
            }
        )
    }
}
