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
            _ = graph.makeSideEffectRule {
                _ = dispatcher.value
                return ()
            }
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
        _ = graph.makeSideEffectRule {
            _ = dispatcher.value
            return ()
        }
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
            _ = graph.makeSideEffectRule {
                _ = dispatcher.value
                return ()
            }
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
    var viewPhase: Attribute<Phase>
    var prefersLast: OptionalAttribute<Bool>
    var cycleDetector: UpdateCycleDetector
    var oldResetSeed: UInt32?
    var oldOutput: Provider.Output?
    var viewGraph: WeakObject<ViewGraph>

    init(
        provider: Provider,
        inputs: Attribute<[Provider.Input]>,
        viewPhase: Attribute<Phase>,
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
                Update.enqueueAction(reason: 0x11) {
                    _ = graph
                    action()
                }
            }
        }
        oldOutput = newOutput
        _AGGraph.setStatefulOutput(())
    }
}
