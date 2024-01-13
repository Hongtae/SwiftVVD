//
//  File: TupleView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct TupleView<T>: View {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let listInputs = _ViewListInputs(inputs: inputs)
        let listOutputs = Self._makeViewList(view: view, inputs: listInputs)
        let subviews = listOutputs.viewProxies
        let viewProxy = ViewGroupProxy(view: view.value,
                                       inputs: inputs,
                                       subviews: subviews,
                                       layout: inputs.defaultLayout)
        return _ViewOutputs(item: .view(viewProxy))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var viewList: [_ViewListOutputs] = []

        func makeOutput<V: View>(_ view: V, inputs: _ViewListInputs) -> _ViewListOutputs {
            V._makeViewList(view: _GraphValue(view), inputs: inputs)
        }

        Mirror(reflecting: view.value.value).children.forEach { label, value in
            if let v = value as? any View {
                let output = makeOutput(v, inputs: inputs)
                viewList.append(output)
            }
        }
        return _ViewListOutputs(item: .viewList(viewList))
    }

    public typealias Body = Never
}

extension TupleView: _PrimitiveView {
}
