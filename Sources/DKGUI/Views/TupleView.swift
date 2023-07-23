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
        let defaultLayout = inputs.defaultLayout
        var inputs = inputs
        inputs.defaultLayout = nil
        let listInputs = _ViewListInputs(inputs: inputs)
        let listOutputs = Self._makeViewList(view: view, inputs: listInputs)
        let subviews = listOutputs.viewProxies
        let viewProxy: ViewProxy
        if let defaultLayout {
            viewProxy = ViewGroupProxy(view: view.value, inputs: inputs, subviews: subviews, layout: defaultLayout)
        } else {
            viewProxy = ViewProxy(inputs: inputs, subviews: subviews)
        }
        return _ViewOutputs(item: .view(viewProxy))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var viewList: [_ViewListOutputs] = []
        Mirror(reflecting: view.value.value).children.forEach { label, value in
            if let v = value as? any View {
                let view = AnyView(v)
                if view.viewProxyProvider != nil {
                    viewList.append(_ViewListOutputs(item: .view(.init(view: view, inputs: inputs.inputs))))
                } else {
                    let outputs = view.makeViewList(graph: _Graph(), inputs: inputs)
                    viewList.append(outputs)
                }
            }
        }
        return _ViewListOutputs(item: .viewList(viewList))
    }

    public typealias Body = Never
}

extension TupleView: _PrimitiveView {
}
