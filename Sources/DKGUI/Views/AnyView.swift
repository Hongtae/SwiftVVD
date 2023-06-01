//
//  File: AnyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct AnyView: View {

    let makeView: (_: _ViewInputs)->_ViewOutputs
    let makeViewList: (_: _ViewListInputs)->_ViewListOutputs

    public init<V>(_ view: V) where V: View {
        self.makeView = { inputs in
            V._makeView(view: _GraphValue<V>(view), inputs: inputs)
        }
        self.makeViewList = { inputs in
            V._makeViewList(view: _GraphValue<V>(view), inputs: inputs)
        }
    }

    public init<V>(erasing view: V) where V: View {
        self.makeView = { inputs in
            V._makeView(view: _GraphValue<V>(view), inputs: inputs)
        }
        self.makeViewList = { inputs in
            V._makeViewList(view: _GraphValue<V>(view), inputs: inputs)
        }
    }
}

extension AnyView: _PrimitiveView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        return view.value.makeView(inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        return view.value.makeViewList(inputs)
    }
}
