//
//  File: EnvironmentalView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

protocol EnvironmentalView: PrimitiveView, UnaryView {
    associatedtype EnvironmentBody: View

    func body(environment: EnvironmentValues) -> EnvironmentBody
}

private struct EnvironmentalViewChild<Content: EnvironmentalView>: StatefulRule {
    typealias Value = Content.EnvironmentBody

    var _view: Attribute<Content>
    var _env: Attribute<EnvironmentValues>
    var tracker: _PropertyListTracker

    mutating func updateValue() {
        let environment = _env.value
        if _AGGraph.currentStatefulOutput(Value.self) != nil,
           !_AGGraphAnyInputsChanged(),
           !tracker.hasDifferentUsedValues(environment._plist) {
            return
        }

        tracker.reset()
        let trackedEnvironment = EnvironmentValues(
            environment._plist,
            tracker: tracker
        )
        _AGGraph.setStatefulOutput(
            _view.value.body(environment: trackedEnvironment)
        )
    }
}

extension EnvironmentalView {
    public static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let child = graph.makeStatefulRule(
            EnvironmentalViewChild(
                _view: view._attribute,
                _env: inputs.base.cachedEnvironment.value.environment,
                tracker: _PropertyListTracker()
            )
        )
        return EnvironmentBody._makeView(
            view: _GraphValue(_attribute: child),
            inputs: inputs
        )
    }
}
