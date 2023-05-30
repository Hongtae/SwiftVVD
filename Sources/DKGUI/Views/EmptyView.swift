//
//  File: EmptyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct EmptyView: View {
}

extension EmptyView: _PrimitiveView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let listOutputs = _ViewListOutputs(views: [])
        let viewProxy = ViewContext(view: view, inputs: inputs, listOutputs: listOutputs)
        return _ViewOutputs(viewProxy: viewProxy)
    }
}
