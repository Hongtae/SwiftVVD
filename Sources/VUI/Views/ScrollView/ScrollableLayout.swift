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

        public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
            guard let graph = _AGGraph.current else {
                fatalError("_ScrollView.Main._makeView called outside an active _AGGraph context.")
            }

            let contentOffset = graph.makeInput(
                value: _initialContentOffset(from: view._attribute.value.config)
            )
            let node = ScrollViewNode(
                graphRef: _AGGraphContext.current ?? _AGGraphContext(graph: graph),
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
            contentInputs.preferences.keys.add(ScrollablePreferenceKey.self)

            let childModifier: Attribute<ScrollViewChildModifier.Value> = graph.makeRule(
                ScrollViewChildModifier(_proxy: scrollView, node: node)
            )
            let contentOutputs = ScrollViewChildModifier.Value._makeView(
                modifier: _GraphValue(_attribute: childModifier),
                inputs: contentInputs
            ) { _, inputs in
                Provider.ScrollableContent._makeView(
                    view: _GraphValue(_attribute: contentAttr),
                    inputs: inputs
                )
            }

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
                let childResponders: Attribute<[ViewResponder]>
                if let childRespondersID = contentOutputs.preferences.value(for: ViewRespondersKey.self) {
                    childResponders = Attribute<[ViewResponder]>(childRespondersID)
                } else {
                    childResponders = graph.makeInput(value: ViewRespondersKey.defaultValue)
                }
                let responder: Attribute<[ViewResponder]> = graph.makeStatefulRule(
                    DefaultLayoutResponderFilter(
                        children: childResponders,
                        responder: DefaultLayoutViewResponder(inputs: inputs)
                    )
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

extension _ScrollView.Main: PrimitiveView, UnaryView {
}

struct _ContainingScrollView {
    var proxy: Attribute<_ScrollViewProxy>
    var contentOffset: Attribute<CGPoint>
}

struct ContainingScrollViewInput: ViewInput {
    static var defaultValue: _ContainingScrollView? { nil }

    static func valuesEqual(_ a: _ContainingScrollView?, _ b: _ContainingScrollView?) -> Bool {
        a?.proxy.identifier == b?.proxy.identifier &&
            a?.contentOffset.identifier == b?.contentOffset.identifier
    }
}

struct ScrollViewChildModifier: Rule {
    typealias Value = ModifiedContent<
        ModifiedContent<
            ModifiedContent<
                ModifiedContent<_GeometryGroupEffect, ScrollViewGeometry>,
                _CoordinateSpaceModifier<ObjectIdentifier>
            >,
            _ContentShapeModifier<Rectangle>
        >,
        ScrollViewGesture
    >

    var _proxy: Attribute<_ScrollViewProxy>
    var node: ScrollViewNode

    var value: Value {
        _GeometryGroupEffect()
            .concat(ScrollViewGeometry())
            .concat(_CoordinateSpaceModifier(name: ObjectIdentifier(node)))
            .concat(_ContentShapeModifier(shape: Rectangle(), eoFill: false))
            .concat(ScrollViewGesture(proxy: _proxy.value))
    }
}

struct ScrollViewGeometry: MultiViewModifier {
    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _ = modifier
        guard let graph = _AGGraph.current,
              let scrollView = inputs[ContainingScrollViewInput.self] else {
            return body(_Graph(), inputs)
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
            return ViewSize(visibleSize, proposal: _ProposedSize(visibleSize))
        }
        return body(_Graph(), rewritten)
    }
}

private struct _ScrollViewMainContentOffset: Rule {
    typealias Value = CGPoint

    var basePosition: Attribute<CGPoint>
    var scrollView: Attribute<_ScrollViewProxy>

    var value: CGPoint {
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

func _scrollViewProjectedDecelerationDistance(
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

    struct GestureCommit {
        var presentation: CGPoint
        var target: CGPoint?
        var velocity: _Velocity<CGSize>?
    }

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

    mutating func dispatchPhase(
        _ gesturePhase: GesturePhase<ScrollGesture.Value>,
        node: ScrollViewNode
    ) -> GestureCommit? {
        switch gesturePhase {
        case .possible(.none):
            return nil
        case .possible(.some(let value)), .active(let value):
            return updateDragging(value: value, node: node)
        case .ended(let value):
            return stopDragging(value: value, node: node)
        case .failed:
            return stopDragging(value: nil, node: node)
        }
    }

    private mutating func updateDragging(
        value: ScrollGesture.Value,
        node: ScrollViewNode
    ) -> GestureCommit {
        let translation: CGSize
        let velocity: _Velocity<CGSize>
        switch value {
        case .pan(let pan):
            translation = pan.translation
            velocity = pan.velocity
        case .wheel(let offset):
            translation = offset
            velocity = _Velocity(valuePerSecond: .zero)
        }

        var drag: DragState
        switch phase {
        case .dragging(let current) where !current.ended:
            drag = current
        case .dragging, .decelerating, .idle:
            if case .decelerating = phase {
                _ = resetDeceleration()
            }
            reloadContainers(node: node)
            let beganOffset = node.removeRubberBanding(from: node.presentationOffset)
            drag = DragState(
                offset: beganOffset,
                beganOffset: beganOffset,
                translation: .zero,
                velocity: velocity,
                scrollingVertically: false,
                scrollingHorizontally: false,
                ended: false
            )
        }

        let delta = CGSize(
            width: translation.width - drag.translation.width,
            height: translation.height - drag.translation.height
        )
        drag.offset.x -= delta.width
        drag.offset.y -= delta.height
        drag.translation = translation
        drag.velocity = velocity
        drag.scrollingHorizontally = drag.scrollingHorizontally || delta.width != 0
        drag.scrollingVertically = drag.scrollingVertically || delta.height != 0
        drag.ended = false
        phase = .dragging(drag)
        seed &+= 1

        let presentation = overflowContentOffset(drag.offset, node: node)
        return GestureCommit(
            presentation: presentation,
            target: nil,
            velocity: nil
        )
    }

    private mutating func stopDragging(
        value: ScrollGesture.Value?,
        node: ScrollViewNode
    ) -> GestureCommit? {
        guard case .dragging(var drag) = phase, !drag.ended else {
            return nil
        }
        if case .pan(let pan)? = value {
            drag.velocity = pan.velocity
        }
        drag.ended = true
        phase = .dragging(drag)
        seed &+= 1

        let viewportSize = (node.containerSize ?? .zero).inset(by: node.config.contentInsets)
        let requestedTarget = node.decelerationTarget(
            drag.offset,
            drag.beganOffset,
            drag.velocity,
            viewportSize
        ) ?? estimatedDeceleration(from: drag.offset, node: node)
        let target = node.bindingSafeOffsetForGesture(requestedTarget)
        return GestureCommit(
            presentation: drag.offset,
            target: target,
            velocity: drag.velocity.negated()
        )
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
            beginTime: (node.host.context as? ViewGraph)?.currentTimestamp
                ?? .systemUptime,
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
            x: sourceOffset.x + _scrollViewProjectedDecelerationDistance(
                velocity: Double(velocity.width),
                decelerationRate: node.config.decelerationRate
            ),
            y: sourceOffset.y + _scrollViewProjectedDecelerationDistance(
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
    typealias DecelerationTarget = (
        CGPoint,
        CGPoint,
        _Velocity<CGSize>,
        CGSize
    ) -> CGPoint?

    let host: _AGGraphContext
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
    var decelerationTarget: DecelerationTarget
    weak var container: ScrollViewNode?
    var topScrollIndicatorFollowsContentOffset: Bool
    var pixelLength: Attribute<CGFloat>
    var propertySeed: UInt32

    init(
        graphRef: _AGGraphContext,
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
        self.decelerationTarget = { _, _, _, _ in nil }
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

    func dispatchScrollGesturePhase(_ phase: GesturePhase<ScrollGesture.Value>) {
        var nextBehavior = behavior
        let commit = nextBehavior.dispatchPhase(phase, node: self)
        behavior = nextBehavior
        if let commit {
            commitGestureOffset(
                presentation: commit.presentation,
                target: commit.target,
                velocity: commit.velocity
            )
        }
    }

    func removeRubberBanding(from offset: CGPoint) -> CGPoint {
        guard let contentSize, let containerSize else {
            return offset
        }
        return _scrollViewClampContentOffset(
            offset,
            maxContentOffset: _scrollViewMaxContentOffset(
                contentSize: contentSize,
                containerSize: containerSize,
                contentInsets: config.contentInsets
            )
        )
    }

    func bindingSafeOffsetForGesture(_ offset: CGPoint) -> CGPoint {
        bindingSafeOffset(
            offset,
            containerSize: containerSize ?? currentProxy?.pageSize ?? .zero,
            config: currentProxy?.config ?? config
        )
    }

    func commitGestureOffset(
        presentation: CGPoint,
        target: CGPoint?,
        velocity: _Velocity<CGSize>?
    ) {
        let resolvedConfig = currentProxy?.config ?? config
        let safeOffset = bindingSafeOffsetForGesture(target ?? presentation)
        let bindingState = contentOffsetBindingState(config: resolvedConfig)
        commitScrollTransaction(
            ScrollViewCommitInfo(
                contentOffset: (
                    presentation,
                    bindingValue: safeOffset
                ),
                targetOffset: target.map {
                    (
                        $0,
                        bindingValue: safeOffset,
                        velocity: velocity,
                        completion: nil
                    )
                }
            ),
            value: safeOffset,
            binding: bindingState.binding,
            previousBindingValue: bindingState.value
        )
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
        let bindingState = contentOffsetBindingState(config: resolvedConfig)
        commitScrollTransaction(
            ScrollViewCommitInfo(
                contentOffset: (
                    safeOffset,
                    bindingValue: bindingState.value
                )
            ),
            value: safeOffset,
            binding: bindingState.binding,
            previousBindingValue: bindingState.value
        )
        return safeOffset
    }

    func requestContentOffset(
        _ offset: CGPoint,
        animated: Bool,
        completion: ScrollViewBehavior.Completion?
    ) {
        if case .dragging(let state) = behavior.phase, !state.ended {
            if let completion {
                let finished = presentationOffset == offset
                Update.enqueueAction {
                    completion(finished)
                }
            }
            return
        }

        let resolvedContainerSize = containerSize ?? currentProxy?.pageSize ?? .zero
        let resolvedConfig = currentProxy?.config ?? config
        let safeOffset = bindingSafeOffset(
            offset,
            containerSize: resolvedContainerSize,
            config: resolvedConfig
        )
        let finishedBeforeCommit = presentationOffset == offset
        let bindingState = contentOffsetBindingState(config: resolvedConfig)

        guard animated else {
            commitScrollTransaction(
                ScrollViewCommitInfo(
                    contentOffset: (
                        offset,
                        bindingValue: safeOffset
                    )
                ),
                value: safeOffset,
                binding: bindingState.binding,
                previousBindingValue: bindingState.value
            )
            if let completion {
                Update.enqueueAction {
                    completion(finishedBeforeCommit)
                }
            }
            return
        }

        commitScrollTransaction(
            ScrollViewCommitInfo(
                contentOffset: (
                    offset,
                    bindingValue: nil
                ),
                targetOffset: (
                    safeOffset,
                    bindingValue: nil,
                    velocity: nil,
                    completion: completion
                )
            ),
            value: safeOffset,
            binding: bindingState.binding,
            previousBindingValue: bindingState.value
        )
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

    private func contentOffsetBindingState(
        config: _ScrollViewConfig
    ) -> (binding: Binding<CGPoint>?, value: CGPoint?) {
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
        return (binding, bindingValue)
    }

    private func commitScrollTransaction(
        _ commitInfo: ScrollViewCommitInfo,
        value: CGPoint,
        binding: Binding<CGPoint>?,
        previousBindingValue: CGPoint?
    ) {
        var transaction = Transaction.current
        transaction[scrollInfo: uniqueId] = commitInfo
        if let graphHost = host.context as? GraphHost {
            graphHost.emptyTransaction(transaction)
        }
        if updateContentOffset(in: transaction, bindingOffset: nil) {
            propertySeed &+= 1
        }
        attribute.toStrong().setValue(value, transaction: transaction)
        guard let binding, previousBindingValue != value else {
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
    var _phase: Attribute<_GraphInputs.Phase>
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
        _phase: Attribute<_GraphInputs.Phase>
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
        let contentProvider = current.contentProvider
        _node.decelerationTarget = { contentOffset, originalContentOffset, velocity, size in
            contentProvider.decelerationTarget(
                contentOffset: contentOffset,
                originalContentOffset: originalContentOffset,
                velocity: velocity,
                size: size
            )
        }
        _ = _environment.value
        let time = _time.value

        let sourceAttribute = _node.attribute.toStrong()
        _ = sourceAttribute.value
        let transaction = _AGGraph.withoutTracking {
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
            estimatedTarget: _node.modelOffset
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

        _AGGraph.setStatefulOutput(_ScrollViewProxy(
            config: current.config,
            contentOffset: _node.currentContentOffset,
            contentSize: _node.currentContentSize ?? pageSize,
            pageSize: pageSize,
            node: _node
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

    var value: any Scrollable {
        scrollable
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
        graph: _AGGraph
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
            guard let graph = _AGGraph.current,
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

    var value: ScrollGeometry {
        let proxyValue = proxy.value
        let containerSize = proxyValue.pageSize
        let proposedSize = containerSize.inset(by: proxyValue.config.contentInsets)
        let contentSize = layoutComputer.attribute?.value.sizeThatFits(
            _ProposedSize(proposedSize)
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
        storage.node?.config ?? storage.config
    }

    public var contentOffset: CGPoint {
        get { storage.node?.currentContentOffset ?? storage.contentOffset }
        set {
            if let node = storage.node {
                node.requestContentOffset(newValue, animated: false, completion: nil)
            } else {
                storage.contentOffset = _scrollViewClampContentOffset(
                    newValue,
                    maxContentOffset: maxContentOffset
                )
            }
        }
    }

    public var minContentOffset: CGPoint { .zero }
    public var maxContentOffset: CGPoint {
        _scrollViewMaxContentOffset(
            contentSize: contentSize,
            containerSize: pageSize,
            contentInsets: config.contentInsets
        )
    }
    public var contentSize: CGSize { storage.node?.currentContentSize ?? storage.contentSize }
    public var pageSize: CGSize { storage.node?.containerSize ?? storage.pageSize }
    public var visibleRect: CGRect {
        CGRect(
            x: contentOffset.x - config.contentInsets.leading,
            y: contentOffset.y - config.contentInsets.top,
            width: pageSize.width,
            height: pageSize.height
        )
    }
    public var isDragging: Bool {
        guard let node = storage.node else { return false }
        if case .dragging = node.behavior.phase { return true }
        return false
    }
    public var isDecelerating: Bool {
        guard let node = storage.node else { return false }
        if case .decelerating = node.behavior.phase { return true }
        return false
    }
    public var isScrolling: Bool { isDragging || isDecelerating }
    var isMostlyDecelerating: Bool { isDecelerating }
    public var isScrollingHorizontally: Bool {
        guard let node = storage.node,
              case .dragging(let state) = node.behavior.phase else {
            return false
        }
        return state.scrollingHorizontally
    }
    public var isScrollingVertically: Bool {
        guard let node = storage.node,
              case .dragging(let state) = node.behavior.phase else {
            return false
        }
        return state.scrollingVertically
    }

    private var storage: Storage

    init(
        config: _ScrollViewConfig = _ScrollViewConfig(),
        contentOffset: CGPoint = .zero,
        contentSize: CGSize = .zero,
        pageSize: CGSize = .zero,
        node: ScrollViewNode? = nil
    ) {
        self.storage = Storage(
            config: config,
            contentOffset: contentOffset,
            contentSize: contentSize,
            pageSize: pageSize,
            node: node
        )
    }

    public func setContentOffset(
        _ newOffset: CGPoint,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        if let node = storage.node {
            node.requestContentOffset(newOffset, animated: animated, completion: completion)
            return
        }
        let finishedWithoutMovement = storage.contentOffset == newOffset
        storage.contentOffset = _scrollViewClampContentOffset(
            newOffset,
            maxContentOffset: maxContentOffset
        )
        if let completion {
            Update.enqueueAction {
                completion(finishedWithoutMovement)
            }
        }
    }

    public func scrollRectToVisible(
        _ rect: CGRect,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        let viewportSize = pageSize.inset(by: config.contentInsets)
        let visibleRect = CGRect(
            x: contentOffset.x - config.contentInsets.leading,
            y: contentOffset.y - config.contentInsets.top,
            width: viewportSize.width,
            height: viewportSize.height
        )
        guard !visibleRect.contains(rect) else {
            if let completion {
                Update.enqueueAction {
                    completion(true)
                }
            }
            return
        }

        var target = visibleRect.origin
        if rect.maxX > visibleRect.maxX {
            target.x = rect.minX < visibleRect.minX
                ? rect.minX
                : rect.maxX - visibleRect.width
        } else if rect.minX < visibleRect.minX {
            target.x = rect.minX
        }
        if rect.maxY > visibleRect.maxY {
            target.y = rect.minY < visibleRect.minY
                ? rect.minY
                : rect.maxY - visibleRect.height
        } else if rect.minY < visibleRect.minY {
            target.y = rect.minY
        }
        setContentOffset(target, animated: animated, completion: completion)
    }

    public func contentOffsetOfNextPage(_ directions: _EventDirections) -> CGPoint {
        let viewportSize = pageSize.inset(by: config.contentInsets)
        var target = contentOffset
        switch directions.intersection(.horizontal) {
        case .left:
            target.x -= viewportSize.width
        case .right:
            target.x += viewportSize.width
        default:
            break
        }
        switch directions.intersection(.vertical) {
        case .up:
            target.y -= viewportSize.height
        case .down:
            target.y += viewportSize.height
        default:
            break
        }
        return _scrollViewClampContentOffset(target, maxContentOffset: maxContentOffset)
    }

    func _setContentOffset(_ contentOffset: CGPoint) {
        storage.contentOffset = contentOffset
    }

    func _setContentSize(_ contentSize: CGSize) {
        storage.contentSize = contentSize
    }

    func _dispatchScrollGesturePhase(_ phase: GesturePhase<ScrollGesture.Value>) {
        storage.node?.withCurrent {
            storage.node?.dispatchScrollGesturePhase(phase)
        }
    }

    var node: ScrollViewNode? { storage.node }

    public static func == (lhs: _ScrollViewProxy, rhs: _ScrollViewProxy) -> Bool {
        if let lhsNode = lhs.storage.node, let rhsNode = rhs.storage.node {
            return lhsNode === rhsNode
        }
        return lhs.storage === rhs.storage
    }

    private final class Storage {
        var config: _ScrollViewConfig
        var contentOffset: CGPoint
        var contentSize: CGSize
        var pageSize: CGSize
        weak var node: ScrollViewNode?

        init(
            config: _ScrollViewConfig,
            contentOffset: CGPoint,
            contentSize: CGSize,
            pageSize: CGSize,
            node: ScrollViewNode?
        ) {
            self.config = config
            self.contentOffset = contentOffset
            self.contentSize = contentSize
            self.pageSize = pageSize
            self.node = node
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

    public static func _makeView(
        view: _GraphValue<_ScrollableLayoutView<Data, Layout>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_ScrollableLayoutView._makeView called outside an active _AGGraph context.")
        }

        let layoutState: Attribute<ScrollableLayoutStateValue<Data, Layout>> = graph.makeStatefulRule(
            ScrollableLayoutStateRule(
                data: view[\.data]._attribute,
                layout: view[\.layout]._attribute,
                scrollView: inputs[ScrollableLayoutScrollViewProxyKey.self],
                inputs: inputs
            )
        )
        let data = view[\.data]._attribute
        let dataAndCount: Attribute<(Data, Int)> = graph.makeRule {
            let data = data.value
            return (data, data.count)
        }
        let adaptor = ScrollableLayoutViewAdaptor<Data, Layout>(
            _dataAndCount: dataAndCount,
            _layout: view[\.layout]._attribute,
            _state: layoutState,
            items: [],
            itemsSeed: 0,
            lastContentOffset: .zero
        )
        let (_, containerOutputs) = DynamicContainer.makeContainer(
            adaptor: adaptor,
            inputs: inputs
        )

        var outputs = containerOutputs
        if inputs.requestsLayoutComputer {
            let contentSize = graph.subscriptNode(
                parent: layoutState,
                keyPath: \ScrollableLayoutStateValue<Data, Layout>.contentSize
            )
            let layoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
                ScrollableItemLayoutComputer(_contentSize: contentSize)
            )
            outputs._layoutComputer = OptionalAttribute(layoutComputer)
        }
        return outputs
    }
}

extension _ScrollableLayoutView: PrimitiveView, UnaryView {
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

    var state: Layout.StateType
    var stateSeed: UInt32
    var contentSeed: UInt32
    var scrollLayout: _ScrollLayout
    var identifiers: [Data.Index]
    var placements: [Data.Index: _Placement]
    var validRect: CGRect
    var contentSize: CGSize

}

private struct ScrollableLayoutViewAdaptor<Data, Layout>:
    DynamicContainerAdaptor
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Element: View,
          Data.Index: Hashable {
    typealias Item = AnyDynamicItem
    typealias Items = [AnyDynamicItem]
    typealias ItemLayout = Attribute<ViewGeometry>

    var _dataAndCount: Attribute<(Data, Int)>
    var _layout: Attribute<Layout>
    var _state: Attribute<ScrollableLayoutStateValue<Data, Layout>>
    var items: [(Data.Index, Data.Element)]
    var itemsSeed: UInt32
    var lastContentOffset: CGPoint

    static var maxUnusedItems: Int { 1 }

    mutating func updatedItems() -> [AnyDynamicItem]? {
        let stateResult = _state.changedValue(options: [])
        let state = stateResult.value
        if stateResult.changed, state.stateSeed != itemsSeed {
            return rebuildItems(state: state)
        }

        guard Layout.ItemModifier.self != EmptyModifier.self else {
            return nil
        }
        let layoutResult = _layout.changedValue(options: [])
        guard layoutResult.changed ||
                state.scrollLayout.contentOffset != lastContentOffset else {
            return nil
        }
        return rebuildItems(state: state, layout: layoutResult.value)
    }

    func makeItemLayout(
        item: AnyDynamicItem,
        uniqueId: UInt32,
        inputs: _ViewInputs,
        containerInfo: Attribute<DynamicContainer.Info>,
        containerInputs: (inout _ViewInputs) -> Void
    ) -> (_ViewOutputs, Attribute<ViewGeometry>) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "ScrollableLayoutViewAdaptor.makeItemLayout called outside an active AG context."
            )
        }

        let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
            inputs.base.cachedEnvironment.value.environment.value.layoutDirection
        }
        let identifier: Attribute<Data.Index?> = graph.makeRule(
            ScrollableItemIdentifier<Data, Layout>(
                _info: containerInfo,
                uniqueId: uniqueId
            )
        )
        var childInputs = inputs
        childInputs.copyCaches()
        containerInputs(&childInputs)
        let geometry: Attribute<ViewGeometry> = graph.makeRule(
            ScrollableItemGeometry<Data, Layout>(
                _identifier: identifier,
                _state: _state,
                _layoutDirection: layoutDirection,
                _parentPosition: inputs.position,
                _parentSize: inputs.size,
                _childLayoutComputer: OptionalAttribute()
            )
        )
        if childInputs.needsGeometry {
            childInputs.size = geometry.size()
            childInputs.position = geometry.origin()
            childInputs.requestsLayoutComputer = true
        }

        let outputs = item.makeView(
            uniqueId: uniqueId,
            container: containerInfo,
            inputs: childInputs,
            adaptor: Self.self
        )
        graph.mutateRule(
            geometry.identifier,
            as: ScrollableItemGeometry<Data, Layout>.self,
            invalidating: true
        ) { rule in
            rule._childLayoutComputer = outputs._layoutComputer
        }
        return (outputs, geometry)
    }

    func removeItemLayout(
        uniqueId: UInt32,
        itemLayout: Attribute<ViewGeometry>
    ) {
    }

    private mutating func rebuildItems(
        state: ScrollableLayoutStateValue<Data, Layout>,
        layout suppliedLayout: Layout? = nil
    ) -> [AnyDynamicItem] {
        let (data, count) = _dataAndCount.value
        let layout = suppliedLayout ?? _layout.value
        items.removeAll(keepingCapacity: true)
        items.reserveCapacity(min(count, state.identifiers.count))
        for index in state.identifiers {
            items.append((index, data[index]))
        }
        itemsSeed = state.stateSeed
        lastContentOffset = state.scrollLayout.contentOffset

        return items.map { index, content in
            if Layout.ItemModifier.self == EmptyModifier.self {
                return AnyDynamicItem(content, id: index)
            }
            let placement = state.placements[index] ?? _Placement(
                proposedSize: CGSize.zero,
                anchoring: .topLeading,
                at: CGPoint.zero
            )
            let item = _ScrollableLayoutItem(
                id: AnyHashable(index),
                placement: placement
            )
            let modifier = layout.modifier(
                for: item,
                layout: state.scrollLayout,
                state: state.state
            )
            return AnyDynamicItem(
                ModifiedContent(content: content, modifier: modifier),
                id: index
            )
        }
    }
}

private struct ScrollableItemIdentifier<Data, Layout>: Rule
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Element: View,
          Data.Index: Hashable {
    typealias Value = Data.Index?

    var _info: Attribute<DynamicContainer.Info>
    var uniqueId: UInt32

    var value: Data.Index? {
        guard let item = _info.value.item(for: uniqueId) else {
            return nil
        }
        return item
            .for(ScrollableLayoutViewAdaptor<Data, Layout>.self)
            .item
            .storage
            .identifier
            .base as? Data.Index
    }
}

/// Publishes only a scrollable layout's resolved content size to its parent.
///
/// Dynamic item placement is intentionally absent from this engine; each
/// materialized item owns a separate `ScrollableItemGeometry` dependency.
private struct ScrollableItemLayoutComputer: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer

    var _contentSize: Attribute<CGSize>

    /// Returns the content extent already resolved by the scrollable layout state.
    struct _LayoutEngine: LayoutEngine {
        var contentSize: CGSize

        mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            contentSize
        }
    }

    mutating func updateValue() {
        update(to: _LayoutEngine(contentSize: _contentSize.value))
    }
}

/// Resolves one materialized scroll item from collection identity and shared
/// layout state into the geometry consumed by that item's child graph.
private struct ScrollableItemGeometry<Data, Layout>: Rule, AsyncAttribute
    where Data: RandomAccessCollection,
          Layout: _ScrollableLayout,
          Data.Index: Hashable {

    var _identifier: Attribute<Data.Index?>
    var _state: Attribute<ScrollableLayoutStateValue<Data, Layout>>
    var _layoutDirection: Attribute<LayoutDirection>
    var _parentPosition: Attribute<CGPoint>
    var _parentSize: Attribute<ViewSize>
    var _childLayoutComputer: OptionalAttribute<LayoutComputer>

    var value: ViewGeometry {
        guard let identifier = _identifier.value,
              let placement = _state.value.placements[identifier] else {
            return .zero
        }

        guard let currentAttribute = _AGGraph.currentRuleContextAttribute else {
            fatalError(
                "ScrollableItemGeometry evaluated outside an active rule context."
            )
        }
        // The materialized item's geometry rule owns final measurement. The
        // child computer must never be promoted into an inferred rule context.
        let proxy = LayoutProxy(
            context: AnyRuleContext(attribute: currentAttribute),
            layoutComputer: _childLayoutComputer.attribute
        )
        var geometry = proxy.finallyPlaced(
            at: placement,
            in: _parentSize.value.value,
            layoutDirection: _layoutDirection.value
        )
        let parentPosition = _parentPosition.value
        geometry.origin.x += parentPosition.x
        geometry.origin.y += parentPosition.y
        return geometry
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
        guard let graph = _AGGraph.current else {
            fatalError("ScrollableLayoutStateRule.updateValue called outside an active _AGGraph context.")
        }
        let dataValue = data.value
        let layoutValue = layout.value
        let proxyValue = scrollView.attribute?.value
        let containerSize = proxyValue?.pageSize
            ?? inputs.containerSize.attribute?.value.value
            ?? inputs.size.value.value
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

        let previous = _AGGraph.currentStatefulOutput(Value.self)
        let firstEvaluation = previous == nil
        let contentChanged = firstEvaluation ||
            _AGGraph.currentStatefulInputChanged(data.identifier)
        let layoutChanged = firstEvaluation ||
            _AGGraph.currentStatefulInputChanged(layout.identifier)
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
            _AGGraph.setStatefulOutput(value)
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
        _AGGraph.setStatefulOutput(
            ScrollableLayoutStateValue<Data, Layout>(
                state: layoutState,
                stateSeed: stateSeed,
                contentSeed: contentSeed,
                scrollLayout: scrollLayout,
                identifiers: identifiers,
                placements: placements,
                validRect: proxy.validRect,
                contentSize: proxy.contentSize
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
        graph: _AGGraph
    ) {
        let subgraph = AGSubgraph()
        let built = AGSubgraph.withCurrent(subgraph) {
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
        guard _AGGraph.current != nil else { return }
        subgraph.invalidate()
        subgraph.removeFromParent()
    }

    func sizeThatFits(_ proposal: CGSize, content newContent: Data.Element) -> CGSize {
        seed &+= 1
        delta.setValue(seed)
        content.setValue(newContent)
        let layoutComputer = outputs._layoutComputer.attribute?.value ?? LayoutComputer.defaultValue
        return layoutComputer.sizeThatFits(_ProposedSize(proposal))
    }
}
