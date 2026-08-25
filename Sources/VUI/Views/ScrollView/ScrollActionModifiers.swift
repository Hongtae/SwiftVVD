//
//  File: ScrollActionModifiers.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Extra geometry and velocity payload supplied to phase-change callbacks.
public struct ScrollPhaseChangeContext {
    public let geometry: ScrollGeometry
    public let velocity: CGVector?

    init(geometry: ScrollGeometry, velocity: CGVector?) {
        self.geometry = geometry
        self.velocity = velocity
    }
}

extension View {
    nonisolated public func onScrollTargetVisibilityChange<ID>(
        idType: ID.Type,
        threshold: Double = 0.5,
        _ action: @escaping ([ID]) -> Void
    ) -> some View where ID: Hashable {
        // Ordered comparisons intentionally map NaN and negative values to
        // zero before applying the upper bound.
        let nonnegativeThreshold = threshold >= 0 ? threshold : 0
        let normalizedThreshold = nonnegativeThreshold > 1 ? 1 : nonnegativeThreshold
        return modifier(
            ScrollTargetVisibilityChangeModifier(
                threshold: normalizedThreshold,
                action: action
            )
        )
    }

    nonisolated public func onScrollVisibilityChange(
        threshold: Double = 0.5,
        _ action: @escaping (Bool) -> Void
    ) -> some View {
        // Ordered comparisons intentionally map NaN and negative values to
        // zero before applying the upper bound.
        let nonnegativeThreshold = threshold >= 0 ? threshold : 0
        let normalizedThreshold = nonnegativeThreshold > 1 ? 1 : nonnegativeThreshold
        return modifier(
            OnScrollVisibilityChangeModifier(
                threshold: normalizedThreshold,
                action: action
            )
        )
    }

    public func onScrollPhaseChange(
        _ action: @escaping (ScrollPhase, ScrollPhase) -> Void
    ) -> some View {
        modifier(OnScrollPhaseChangeModifier(action: action))
    }

    public func onScrollPhaseChange(
        _ action: @escaping (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void
    ) -> some View {
        modifier(OnScrollPhaseContextChangeModifier(action: action))
    }

    public func onScrollGeometryChange<T>(
        for type: T.Type,
        of transform: @escaping (ScrollGeometry) -> T,
        action: @escaping (T, T) -> Void
    ) -> some View where T: Equatable {
        modifier(
            OnScrollGeometryChangeModifier(
                transform: transform,
                action: action,
                prefersLast: false
            )
        )
    }

    public func onScrollGeometryChange<T>(
        for type: T.Type,
        prefersLast: Bool,
        of transform: @escaping (ScrollGeometry) -> T,
        action: @escaping (T, T) -> Void
    ) -> some View where T: Equatable {
        modifier(
            OnScrollGeometryChangeModifier(
                transform: transform,
                action: action,
                prefersLast: prefersLast
            )
        )
    }
}

/// Keeps collection visibility tracking active only while the modified view
/// remains attached to the live view graph.
struct ScrollTargetVisibilityChangeModifier<ID: Hashable>: ViewModifier {
    var threshold: Double
    var action: ([ID]) -> Void
    @State private var isActive = false

    func body(content: Content) -> some View {
        content
            .modifier(
                PrimitiveTargetVisibilityModifier(
                    isActive: isActive,
                    threshold: threshold,
                    action: action
                )
            )
            .onAppear {
                isActive = true
            }
            .onDisappear {
                isActive = false
            }
    }
}

/// Requests collection-role preferences and owns the retained ID comparison
/// state independently from view-local visibility callbacks.
struct PrimitiveTargetVisibilityModifier<ID: Hashable>: UnaryViewModifier {
    typealias Body = Never

    var isActive: Bool
    var threshold: Double
    var action: ([ID]) -> Void

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("PrimitiveTargetVisibilityModifier._makeView called outside an active _AGGraph context.")
        }

        var contentInputs = inputs
        contentInputs.preferences.keys.add(ScrollTargetRole.Key.self)
        let outputs = body(_Graph(), contentInputs)

        if let targetCollections = outputs.preferences.value(for: ScrollTargetRole.Key.self) {
            let dispatcher: Attribute<Void> = graph.makeStatefulRule(
                VisibilityActionDispatcher(
                    _modifier: modifier._attribute,
                    _targetCollection: Attribute(targetCollections)
                )
            )
            dispatcher.flags = .transactional
        }
        return outputs
    }

    /// Retains the prior typed ID array and emits only changes while the
    /// appearance-controlled modifier is active.
    struct VisibilityActionDispatcher: StatefulRule {
        typealias Value = Void

        var _modifier: Attribute<PrimitiveTargetVisibilityModifier>
        var _targetCollection: Attribute<ScrollTargetRole.Key.Value>
        var wasActive = false
        var cycleDetector = UpdateCycleDetector()
        var oldResetSeed = UInt32.max
        var oldVisibleIDs: [ID] = []

        mutating func updateValue() {
            let modifier = _modifier.value
            if modifier.isActive {
                if let visibleIDs = updatedVisibleIDs(),
                   cycleDetector.dispatch(label: "onScrollTargetVisibilityChange") {
                    enqueueAction(ids: visibleIDs)
                }
                wasActive = true
            } else {
                if wasActive {
                    oldVisibleIDs = []
                    enqueueAction(ids: [])
                }
                wasActive = false
            }
            _AGGraph.setStatefulOutput(())
        }

        private mutating func updatedVisibleIDs() -> [ID]? {
            let threshold = _modifier.value.threshold
            var visibleIDs: [ID] = []

            // Each concrete collection owns its visible-subview order. The
            // callback preserves both dictionary traversal and collection order.
            for (_, collections) in _targetCollection.value {
                for collection in collections {
                    collection.forEachVisibleSubview { subview, _ in
                        guard let id = subview.id.explicitID(for: ID.self) else {
                            return
                        }

                        let frame = subview.frame
                        var clippedFrame = frame
                        clippedFrame.convertAndClipToScrollView(
                            to: .global,
                            transform: subview.transform
                        )
                        let originalArea = frame.width * frame.height
                        let visibleArea = clippedFrame.width * clippedFrame.height
                        let visibleFraction = visibleArea / originalArea
                        if threshold <= visibleFraction {
                            visibleIDs.append(id)
                        }
                    }
                }
            }

            defer { oldVisibleIDs = visibleIDs }
            return visibleIDs == oldVisibleIDs ? nil : visibleIDs
        }

        private func enqueueAction(ids: [ID]) {
            let action = _modifier.value.action
            Update.enqueueAction(reason: .scrollChanged) {
                action(ids)
            }
        }
    }
}

/// Keeps the direct geometry action active only while the modified view is
/// attached to the live view graph.
struct OnScrollVisibilityChangeModifier: ViewModifier {
    var threshold: Double
    var action: (Bool) -> Void
    @State private var isActive = false

    func body(content: Content) -> some View {
        content
            .modifier(
                OnScrollVisibilityGeometryAction(
                    threshold: threshold,
                    action: action,
                    isActive: isActive
                )
            )
            .onAppear {
                isActive = true
            }
            .onDisappear {
                isActive = false
            }
    }
}

/// Reads the modified view's own geometry inputs instead of requesting a
/// scroll-container preference from its descendants.
struct OnScrollVisibilityGeometryAction: UnaryViewModifier {
    typealias Body = Never

    var threshold: Double
    var action: (Bool) -> Void
    var isActive: Bool

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("OnScrollVisibilityGeometryAction._makeView called outside an active _AGGraph context.")
        }

        let binder: Attribute<Void> = graph.makeStatefulRule(
            OnScrollVisibilityGeometryActionBinder(
                _modifier: modifier._attribute,
                _position: inputs.position,
                _size: inputs.size,
                _transform: inputs.transform,
                _environment: inputs.base.cachedEnvironment.value.environment,
                _safeAreaInsets: inputs.safeAreaInsets,
                _phase: inputs.base.phase
            )
        )
        binder.flags = .transactional
        return body(_Graph(), inputs)
    }

    /// Retains the last delivered Boolean across ordinary geometry updates and
    /// resets that comparison state when the view-graph phase is replaced.
    struct OnScrollVisibilityGeometryActionBinder: StatefulRule {
        typealias Value = Void

        var _modifier: Attribute<OnScrollVisibilityGeometryAction>
        var _position: Attribute<CGPoint>
        var _size: Attribute<ViewSize>
        var _transform: Attribute<ViewTransform>
        var _environment: Attribute<EnvironmentValues>
        var _safeAreaInsets: OptionalAttribute<SafeAreaInsets>
        var _phase: Attribute<_GraphInputs.Phase>
        var cycleDetector = UpdateCycleDetector()
        var lastResetSeed: UInt32 = 0
        var proxySeed: UInt32 = 0
        var lastValue: Bool?

        mutating func updateValue() {
            let modifier = _modifier.value
            guard modifier.isActive else {
                if lastValue == true {
                    enqueueAction(modifier.action, isVisible: false)
                }
                lastValue = nil
                _AGGraph.setStatefulOutput(())
                return
            }

            let phase = _phase.value
            if lastResetSeed != phase.resetSeed {
                lastResetSeed = phase.resetSeed
                cycleDetector.reset()
                lastValue = nil
            }

            proxySeed &+= 1
            let proxy = GeometryProxy(
                owner: context.attribute.identifier,
                size: _size,
                environment: _environment,
                transform: _transform,
                position: _position,
                safeAreaInsets: _safeAreaInsets.attribute,
                seed: proxySeed
            )
            let clippedFrame = proxy.frameClippedToScrollViews(in: .global).frame
            let size = proxy.size
            let widthFraction = clippedFrame.width / size.width
            let heightFraction = clippedFrame.height / size.height
            let visibleFraction = widthFraction < heightFraction
                ? widthFraction
                : heightFraction
            let isVisible = modifier.threshold <= visibleFraction

            guard lastValue != isVisible else {
                _AGGraph.setStatefulOutput(())
                return
            }
            lastValue = isVisible
            if cycleDetector.dispatch(label: "onScrollVisibilityChange") {
                enqueueAction(modifier.action, isVisible: isVisible)
            }
            _AGGraph.setStatefulOutput(())
        }

        private func enqueueAction(
            _ action: @escaping (Bool) -> Void,
            isVisible: Bool
        ) {
            Update.enqueueAction(reason: .scrollChanged) {
                action(isVisible)
            }
        }
    }
}

/// Registers a two-argument scroll phase callback on the nearest scroll container.
struct OnScrollPhaseChangeModifier: ViewModifier, MultiViewModifier {
    typealias Body = Never

    var action: (ScrollPhase, ScrollPhase) -> Void

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("OnScrollPhaseChangeModifier._makeView called outside an active _AGGraph context.")
        }

        var contentInputs = inputs
        contentInputs.preferences.keys.add(ScrollPhasePreferenceKey.self)
        let outputs = body(_Graph(), contentInputs)

        if let phaseValues = outputs.preferences.reducedValue(for: ScrollPhasePreferenceKey.self, in: graph) {
            let dispatcher: Attribute<Void> = graph.makeStatefulRule(
                ScrollActionDispatcher(
                    provider: PhaseActionProvider(modifier: modifier._attribute),
                    inputs: phaseValues,
                    viewPhase: inputs.base.phase,
                    prefersLast: OptionalAttribute()
                )
            )
            dispatcher.flags = .transactional
        }
        return outputs
    }

    struct PhaseActionProvider: ScrollActionProvider {
        typealias Input = ScrollPhaseState
        typealias Output = ScrollPhase

        var modifier: Attribute<OnScrollPhaseChangeModifier>

        func makeOutput(input: ScrollPhaseState) -> ScrollPhase? {
            input.phase
        }

        func makeAction(oldOutput: ScrollPhase, newOutput: ScrollPhase) -> () -> Void {
            let action = modifier.value.action
            return {
                action(oldOutput, newOutput)
            }
        }

        var debugDescription: String {
            "OnScrollPhaseChangeModifier.PhaseActionProvider"
        }
    }
}

/// Registers a scroll phase callback that also receives geometry and velocity context.
struct OnScrollPhaseContextChangeModifier: ViewModifier, MultiViewModifier {
    typealias Body = Never

    var action: (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("OnScrollPhaseContextChangeModifier._makeView called outside an active _AGGraph context.")
        }

        var contentInputs = inputs
        contentInputs.preferences.keys.add(ScrollPhasePreferenceKey.self)
        contentInputs.preferences.keys.add(ScrollGeometryPreferenceKey.self)
        let outputs = body(_Graph(), contentInputs)

        guard let phaseValues = outputs.preferences.reducedValue(for: ScrollPhasePreferenceKey.self, in: graph) else {
            return outputs
        }
        let geometryValues = outputs.preferences.reducedValue(for: ScrollGeometryPreferenceKey.self, in: graph)
        let dispatcher: Attribute<Void> = graph.makeStatefulRule(
            ScrollActionDispatcher(
                provider: PhaseContextActionProvider(
                    modifier: modifier._attribute,
                    geometryStates: geometryValues.map(OptionalAttribute.init) ?? OptionalAttribute()
                ),
                inputs: phaseValues,
                viewPhase: inputs.base.phase,
                prefersLast: OptionalAttribute()
            )
        )
        dispatcher.flags = .transactional
        return outputs
    }

    struct PhaseContextActionProvider: ScrollActionProvider {
        typealias Input = ScrollPhaseState
        typealias Output = ScrollPhaseState

        var modifier: Attribute<OnScrollPhaseContextChangeModifier>
        var geometryStates: OptionalAttribute<[ScrollGeometryState]>

        func makeOutput(input: ScrollPhaseState) -> ScrollPhaseState? {
            input
        }

        func makeAction(oldOutput: ScrollPhaseState, newOutput: ScrollPhaseState) -> () -> Void {
            let action = modifier.value.action
            let geometry = geometryStates.attribute?.value.first?.geometry ?? ScrollGeometry()
            let context = ScrollPhaseChangeContext(geometry: geometry, velocity: newOutput.velocity)
            return {
                action(oldOutput.phase, newOutput.phase, context)
            }
        }

        var debugDescription: String {
            "OnScrollPhaseContextChangeModifier.PhaseContextActionProvider"
        }
    }
}

/// Tracks a transformed scroll geometry value and dispatches when it changes.
struct OnScrollGeometryChangeModifier<T: Equatable>: ViewModifier, MultiViewModifier {
    typealias Body = Never

    var transform: (ScrollGeometry) -> T
    var action: (T, T) -> Void
    var prefersLast: Bool

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("OnScrollGeometryChangeModifier._makeView called outside an active _AGGraph context.")
        }

        var contentInputs = inputs
        contentInputs.preferences.keys.add(ScrollGeometryPreferenceKey.self)
        let outputs = body(_Graph(), contentInputs)

        if let geometryValues = outputs.preferences.reducedValue(for: ScrollGeometryPreferenceKey.self, in: graph) {
            let dispatcher: Attribute<Void> = graph.makeStatefulRule(
                ScrollActionDispatcher(
                    provider: GeometryActionProvider(modifier: modifier._attribute),
                    inputs: geometryValues,
                    viewPhase: inputs.base.phase,
                    prefersLast: OptionalAttribute(modifier[\.prefersLast]._attribute)
                )
            )
            dispatcher.flags = .transactional
        }
        return outputs
    }

    struct GeometryActionProvider: ScrollActionProvider {
        typealias Input = ScrollGeometryState
        typealias Output = T

        var modifier: Attribute<OnScrollGeometryChangeModifier<T>>

        func makeOutput(input: ScrollGeometryState) -> T? {
            modifier.value.transform(input.geometry)
        }

        func makeAction(oldOutput: T, newOutput: T) -> () -> Void {
            let action = modifier.value.action
            return {
                action(oldOutput, newOutput)
            }
        }

        var debugDescription: String {
            "OnScrollGeometryChangeModifier.GeometryActionProvider"
        }
    }
}

/// Adapts scroll preference inputs into comparable outputs and queued actions.
protocol ScrollActionProvider: CustomDebugStringConvertible {
    associatedtype Input: Equatable
    associatedtype Output: Equatable

    func makeOutput(input: Input) -> Output?
    func makeAction(oldOutput: Output, newOutput: Output) -> () -> Void
}

/// Stateful dispatcher that detects output changes and schedules scroll callbacks.
struct ScrollActionDispatcher<Provider: ScrollActionProvider>: StatefulRule {
    typealias Value = Void

    var provider: Provider
    var inputs: Attribute<[Provider.Input]>
    var viewPhase: Attribute<_GraphInputs.Phase>
    var prefersLast: OptionalAttribute<Bool>
    var cycleDetector: UpdateCycleDetector
    var oldResetSeed: UInt32?
    var oldOutput: Provider.Output?
    var viewGraph: WeakObject<ViewGraph>

    init(
        provider: Provider,
        inputs: Attribute<[Provider.Input]>,
        viewPhase: Attribute<_GraphInputs.Phase>,
        prefersLast: OptionalAttribute<Bool>,
        cycleDetector: UpdateCycleDetector = UpdateCycleDetector(),
        viewGraph: ViewGraph? = _AGGraphContext.current?.context as? ViewGraph
    ) {
        self.provider = provider
        self.inputs = inputs
        self.viewPhase = viewPhase
        self.prefersLast = prefersLast
        self.cycleDetector = cycleDetector
        self.oldResetSeed = nil
        self.oldOutput = nil
        self.viewGraph = WeakObject(viewGraph)
    }

    mutating func updateValue() {
        let phase = viewPhase.value
        if oldResetSeed != phase.resetSeed {
            oldOutput = nil
            oldResetSeed = phase.resetSeed
            cycleDetector.reset()
        }

        let sourceValues = inputs.value
        let preferLast = prefersLast.attribute?.value ?? false
        let source = preferLast ? sourceValues.last : sourceValues.first
        guard let source,
              let newOutput = provider.makeOutput(input: source) else {
            oldOutput = nil
            _AGGraph.setStatefulOutput(())
            return
        }

        if let oldOutput,
           oldOutput != newOutput {
            if cycleDetector.dispatch(label: provider.debugDescription) {
                let action = provider.makeAction(oldOutput: oldOutput, newOutput: newOutput)
                let graph = viewGraph.value
                Update.enqueueAction(reason: .scrollChanged) {
                    _ = graph
                    action()
                }
            }
        }
        oldOutput = newOutput
        _AGGraph.setStatefulOutput(())
    }
}
