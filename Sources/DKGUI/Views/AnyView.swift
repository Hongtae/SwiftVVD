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
        let generator = TypeErasedViewGenerator(graph: view, inputs: inputs)
        return _ViewOutputs(view: generator, preferences: .init(preferences: []))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let inputs = _ViewInputs(base: inputs.base, preferences: inputs.preferences, traits: inputs.traits)
        let generator = TypeErasedViewGenerator(graph: view, inputs: inputs)
        return _ViewListOutputs(viewList: [generator], preferences: .init(preferences: []))
    }

    public typealias Body = Never
}

extension AnyView: _PrimitiveView {
}

struct TypeErasedViewGenerator : ViewGenerator {
    let graph: _GraphValue<AnyView>
    let inputs: _ViewInputs

    func makeView(content view: AnyView) -> ViewContext? {
        func _makeView<V: View>(value: V, graph: _GraphValue<any View>, inputs: _ViewInputs) -> ViewContext? {
            let outputs = V._makeView(view: graph.unsafeCast(to: V.self), inputs: inputs)
            return AnyViewGenerator(outputs.view).makeView(content: value)
        }
        return _makeView(value: view.storage.view, graph: self.graph[\.storage.view], inputs: inputs)
    }
}
