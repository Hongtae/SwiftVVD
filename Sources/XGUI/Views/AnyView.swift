//
//  File: AnyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

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
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            TypeErasedViewContext(graph: graph, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            TypeErasedViewContext(graph: graph, inputs: inputs)
        }
        return _ViewListOutputs(views: .staticList(view))
    }

    public typealias Body = Never
}

extension AnyView {
    var _view: any View { storage.view }
}

extension AnyView: _PrimitiveView {
}

private class TypeErasedViewContext: DynamicViewContext<AnyView> {
    override func updateContent() {
        var oldViewType: (any View.Type)?
        if let oldView = self.view?._view {
            oldViewType = type(of: oldView)
        }
        self.view = nil
        if var view = value(atPath: self.graph) {
            self.resolveGraphInputs()
            self.updateView(&view)
            self.requiresContentUpdates = false
            self.view = view
        }
        if let view = self.view?._view {
            if self.body == nil || type(of: view) == oldViewType {
                func _makeView<V: View, U>(_: V.Type, view: _GraphValue<U>, inputs: _ViewInputs) -> _ViewOutputs {
                    V._makeView(view: view.unsafeCast(to: V.self), inputs: inputs)
                }
                let viewType = type(of: view)
                let graph = self.graph.unsafeCast(to: AnyView.self)[\._view]
                let outputs = _makeView(viewType, view: graph, inputs: _ViewInputs(base: self.inputs))
                self.body = outputs.view?.makeView(sharedContext: self.sharedContext)
            }
            self.body?.updateContent()
        } else {
            self.invalidate()
        }
        self.sharedContext.needsLayout = true
    }
}
