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
        return _ViewListOutputs(viewList: .staticList([generator]), preferences: .init(preferences: []))
    }

    public typealias Body = Never
}

extension AnyView: _PrimitiveView {
}

private struct TypeErasedViewGenerator : ViewGenerator {
    let graph: _GraphValue<AnyView>
    var inputs: _ViewInputs

    func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
        if let value = graph.value(atPath: self.graph, from: encloser) {
            let outputs = DKGUI.makeView(view: self.graph[\.storage.view].unsafeCast(to: type(of: value)), inputs: inputs)
            return outputs.view.makeView(encloser: value, graph: self.graph)
        }
        return nil
    }

    mutating func mergeInputs(_ inputs: _GraphInputs) {
        self.inputs.base.mergedInputs.append(inputs)
    }
}
