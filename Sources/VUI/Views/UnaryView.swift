//
//  File: UnaryView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

protocol UnaryView: View {
}

extension UnaryView {
    public static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        1
    }
}
