//
//  File: AnyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

class AnyViewBox {
    let view: any View
    init(_ view: any View) {
        self.view = view
    }
}

public struct AnyView: View {
    var storage: AnyViewBox

    public init<V>(_ view: V) where V: View {
        if let view = view as? AnyView {
            self.storage = view.storage
        } else {
            self.storage = AnyViewBox(view)
        }
    }

    public init<V>(erasing view: V) where V: View {
        self.init(view)
    }

    public init?(_fromValue value: Any) {
        guard let view = value as? any View else {
            return nil
        }
        if let view = value as? AnyView {
            self.storage = view.storage
        } else {
            self.storage = AnyViewBox(view)
        }
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        func make<V: View>(_ v: V, inputs: _ViewInputs)->_ViewOutputs {
            V._makeView(view: _GraphValue(v), inputs: inputs)
        }
        let v = view[\.storage].value.view
        return make(v, inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        func make<V: View>(_ v: V, inputs: _ViewListInputs)->_ViewListOutputs {
            V._makeViewList(view: _GraphValue(v), inputs: inputs)
        }
        let v = view[\.storage].value.view
        return make(v, inputs: inputs)
    }

    public typealias Body = Never
}

extension AnyView: _PrimitiveView {
}
