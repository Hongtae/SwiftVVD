//
//  File: StyleContextWriter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//


struct StyleContextWriter<Style>: ViewModifier where Style: StyleContext {
    typealias Body = Never
    let style: Style
}

extension StyleContextWriter: _ViewInputsModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewInputs called outside an active AttributeGraph context.")
        }
        let parentEnvAttr = inputs.base.cachedEnvironment.value.environment
        let newEnvAttr: Attribute<EnvironmentValues> = graph.makeRule {
            let m = modifier._attribute.value
            var env = parentEnvAttr.value
            env._overrideStyleContext = m.style
            return env
        }
        inputs.base.cachedEnvironment = MutableBox(CachedEnvironment(environment: newEnvAttr))
    }
}
