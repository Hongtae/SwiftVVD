//
//  File: TupleView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct TupleView<T>: View {
    public var value: T
    public typealias Body = Never

    public init(_ value: T) {
        self.value = value
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let listInputs = _ViewListInputs(inputs: inputs)
        let listOutputs = Self._makeViewList(view: view, inputs: listInputs)
        let makeView: _ViewOutputs.MakeView = {
            ViewContext(view: view, inputs: inputs, outputs: listOutputs)
        }
        return _ViewOutputs(makeView: makeView)
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var viewList: [_ViewListOutputs] = []
        Mirror(reflecting: view.value.value).children.forEach { label, value in
            if let v = value as? any View {
                let outputs = v._makeViewList(graph: _Graph(), inputs: inputs, _MakeViewFromTuple(graph: view))
                viewList.append(outputs)
            }
        }
        return _ViewListOutputs(item: .viewList(viewList))
    }
}

private struct _MakeViewFromTuple<T> {
    let graph: _GraphValue<TupleView<T>>
}

private extension View {
    func _makeViewList<T>(graph: _Graph, inputs: _ViewListInputs, _: _MakeViewFromTuple<T>) -> _ViewListOutputs {
        let view = _GraphValue<Self>(self)
        if self is any _PrimitiveView {
            let makeView: _ViewListOutputs.MakeView = { graph, inputs in
                Self._makeView(view: view, inputs: inputs)
            }
            return _ViewListOutputs(item: .makeView(makeView))
        }
        return Self._makeViewList(view: view, inputs: inputs)
    }
}
