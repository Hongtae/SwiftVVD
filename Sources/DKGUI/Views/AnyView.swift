//
//  File: AnyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

protocol AnyViewStorageBase {
    func makeView(graph: _Graph, inputs: _ViewInputs)->_ViewOutputs
    func makeViewList(graph: _Graph, inputs: _ViewListInputs)->_ViewListOutputs

    var view: any View { get }
}

private struct _MakeViewFromAnyView {
    let graph: _Graph
}

private extension View {
    func _makeView(graph: _Graph, inputs: _ViewInputs, _: _MakeViewFromAnyView) -> _ViewOutputs {
        Self._makeView(view: _GraphValue<Self>(self), inputs: inputs)
    }
    func _makeViewList(graph: _Graph, inputs: _ViewListInputs, _: _MakeViewFromAnyView) -> _ViewListOutputs {
        Self._makeViewList(view: _GraphValue<Self>(self), inputs: inputs)
    }
}

struct AnyViewBox: AnyViewStorageBase {
    let view: any View
    func makeView(graph: _Graph, inputs: _ViewInputs)->_ViewOutputs {
        view._makeView(graph: graph, inputs: inputs, _MakeViewFromAnyView(graph: graph))
    }
    func makeViewList(graph: _Graph, inputs: _ViewListInputs)->_ViewListOutputs {
        view._makeViewList(graph: graph, inputs: inputs, _MakeViewFromAnyView(graph: graph))
    }
    init(_ view: any View) { self.view = view }
}

struct AnyViewBoxType<T>: AnyViewStorageBase where T: View {
    let _view: T
    func makeView(graph: _Graph, inputs: _ViewInputs)->_ViewOutputs {
        T._makeView(view: _GraphValue<T>(_view), inputs: inputs)
    }
    func makeViewList(graph: _Graph, inputs: _ViewListInputs)->_ViewListOutputs {
        T._makeViewList(view: _GraphValue<T>(_view), inputs: inputs)
    }
    var view: any View { _view }
    init(_ view: T) { self._view = view }
}

public struct AnyView: View {
    public typealias Body = Never

    let storage: any AnyViewStorageBase

    public init<V>(_ view: V) where V: View {
        self.storage = AnyViewBoxType(view)
    }

    public init<V>(erasing view: V) where V: View {
        self.init(view)
    }

    public init?(_fromValue value: Any) {
        guard let view = value as? any View else {
            return nil
        }
        self.storage = AnyViewBox(view)
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let storage = view[\.storage].value
        return storage.makeView(graph: _Graph(), inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let storage = view[\.storage].value
        if storage.view is _PrimitiveView {
            return _ViewListOutputs(item: .makeView({ graph, inputs in
                storage.makeView(graph: graph, inputs: inputs)
            }))
        }
        return storage.makeViewList(graph: _Graph(), inputs: inputs)
    }
}
