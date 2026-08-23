//
//  File: ValueActionModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Defines the value and callback operations shared by value-action modifiers.
protocol ValueActionModifierProtocol: ViewModifier where Value: Equatable {
    associatedtype Value

    var value: Value { get }

    func sendAction(old: Self?)
}

/// Stores a two-value change callback without adding a modifier body.
struct _ValueActionModifier2<Value>: ViewModifier where Value: Equatable {
    var value: Value
    var action: (Value, Value) -> Void

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        installDispatcher(modifier: modifier, phase: inputs.base.phase)
        return body(_Graph(), inputs)
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        installDispatcher(modifier: modifier, phase: inputs.base.phase)
        return body(_Graph(), inputs)
    }

    private static func installDispatcher(
        modifier: _GraphValue<Self>,
        phase: Attribute<_GraphInputs.Phase>
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self).installDispatcher called outside an active _AGGraph context.")
        }
        let dispatcher = graph.makeStatefulRule(
            ValueActionDispatcher(modifier: modifier._attribute, phase: phase)
        )
        dispatcher.flags = [.transactional]
    }
}

extension _ValueActionModifier2: ValueActionModifierProtocol {
    func sendAction(old: Self?) {
        guard let old else { return }
        action(old.value, value)
    }
}

/// Retains the previous modifier value and schedules callbacks after evaluation.
struct ValueActionDispatcher<Modifier>: StatefulRule
where Modifier: ValueActionModifierProtocol {
    typealias Value = Void

    var modifier: Attribute<Modifier>
    var phase: Attribute<_GraphInputs.Phase>
    var oldValue: Modifier?
    var lastResetSeed: UInt32
    var cycleDetector: UpdateCycleDetector

    init(
        modifier: Attribute<Modifier>,
        phase: Attribute<_GraphInputs.Phase>,
        oldValue: Modifier? = nil,
        lastResetSeed: UInt32 = 0,
        cycleDetector: UpdateCycleDetector = UpdateCycleDetector()
    ) {
        self.modifier = modifier
        self.phase = phase
        self.oldValue = oldValue
        self.lastResetSeed = lastResetSeed
        self.cycleDetector = cycleDetector
    }

    mutating func updateValue() {
        let resetSeed = phase.value.resetSeed
        if lastResetSeed != resetSeed {
            lastResetSeed = resetSeed
            oldValue = nil
            cycleDetector.reset()
        }

        let current = modifier.value
        if let oldValue,
           oldValue.value != current.value,
           cycleDetector.dispatch(label: "onChange(of: \(Modifier.Value.self)) action") {
            Update.enqueueAction(reason: .onChange) {
                current.sendAction(old: oldValue)
            }
        }
        oldValue = current
        _AGGraph.setStatefulOutput(())
    }
}

extension View {
    /// Adds an action that runs after an equatable value changes.
    nonisolated public func onChange<V>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void
    ) -> some View where V: Equatable {
        let initialAction: (() -> Void)? = initial
            ? { action(value, value) }
            : nil
        return modifier(_ValueActionModifier2(value: value, action: action))
            .modifier(_AppearanceActionModifier(appear: initialAction, disappear: nil))
    }

    /// Adds a parameterless action that runs after an equatable value changes.
    nonisolated public func onChange<V>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View where V: Equatable {
        onChange(of: value, initial: initial) { _, _ in action() }
    }
}
