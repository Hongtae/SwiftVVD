//
//  File: EmptyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct EmptyView: View {
    public init() {}

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let generator = PrimitiveViewGenerator(view: view,
                                               baseInputs: inputs.base,
                                               preferences: inputs.preferences,
                                               traits: inputs.traits)
        return _ViewOutputs(view: generator,
                            preferences: PreferenceOutputs(preferences: []))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let generator = PrimitiveViewGenerator(view: view,
                                               baseInputs: inputs.base,
                                               preferences: inputs.preferences,
                                               traits: inputs.traits)
        return _ViewListOutputs(view: generator,
                                preferences: PreferenceOutputs(preferences: []))
    }

    public typealias Body = Never
}

extension EmptyView: _PrimitiveView {
}
