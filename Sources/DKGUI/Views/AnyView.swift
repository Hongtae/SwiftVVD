//
//  File: AnyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

class AnyViewStorageBase {
    func makeView(graph: _Graph, inputs: _ViewInputs)->_ViewOutputs {
        fatalError()
    }
    func makeViewList(graph: _Graph, inputs: _ViewListInputs)->_ViewListOutputs {
        fatalError()
    }
    var viewProxyProvider: ViewProxyProvider? { nil }
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

class AnyViewBox: AnyViewStorageBase {
    override func makeView(graph: _Graph, inputs: _ViewInputs)->_ViewOutputs {
        view._makeView(graph: graph, inputs: inputs, _MakeViewFromAnyView(graph: graph))
    }
    override func makeViewList(graph: _Graph, inputs: _ViewListInputs)->_ViewListOutputs {
        view._makeViewList(graph: graph, inputs: inputs, _MakeViewFromAnyView(graph: graph))
    }

    let view: any View
    init(_ view: any View) {
        self.view = view
    }

    override var viewProxyProvider: ViewProxyProvider? {
        view as? ViewProxyProvider
    }
}

class AnyViewBoxType<T>: AnyViewStorageBase where T: View {
    override func makeView(graph: _Graph, inputs: _ViewInputs)->_ViewOutputs {
        T._makeView(view: _GraphValue<T>(view), inputs: inputs)
    }
    override func makeViewList(graph: _Graph, inputs: _ViewListInputs)->_ViewListOutputs {
        T._makeViewList(view: _GraphValue<T>(view), inputs: inputs)
    }

    let view: T
    init(_ view: T) {
        self.view = view
    }

    override var viewProxyProvider: ViewProxyProvider? {
        view as? ViewProxyProvider
    }
}

public struct AnyView: View {
    var storage: AnyViewStorageBase

    public init<V>(_ view: V) where V: View {
        if let view = view as? AnyView {
            self.storage = view.storage
        } else {
            self.storage = AnyViewBoxType(view)
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
        view.value.makeView(graph: _Graph(), inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        view.value.makeViewList(graph: _Graph(), inputs: inputs)
    }
    
    func makeView(graph: _Graph, inputs: _ViewInputs)->_ViewOutputs {
        return storage.makeView(graph: _Graph(), inputs: inputs)
    }

    func makeViewList(graph: _Graph, inputs: _ViewListInputs)->_ViewListOutputs {
        return storage.makeViewList(graph: _Graph(), inputs: inputs)
    }

    public typealias Body = Never
}

extension AnyView: PrimitiveView {
}

extension AnyView {
    var viewProxyProvider: ViewProxyProvider? {
        self.storage.viewProxyProvider
    }
}
