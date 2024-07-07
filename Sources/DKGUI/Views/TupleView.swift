//
//  File: TupleView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

public struct TupleView<T>: View {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    static var _subviewTypes: [(name: String, offset: Int, type: any View.Type)] {
        var types: [(name: String, offset: Int,  type: any View.Type)] = []
        _forEachField(of: T.self) { charPtr, offset, fieldType in
            if let viewType = fieldType as? any View.Type {
                let name = String(cString: charPtr)
                types.append((name: name, offset: offset, type: viewType))
            }
            return true
        }
        return types
    }

    var _subviews: [any View] {
        var views: [any View] = []
        func restore<V: View>(_ ptr: UnsafeRawPointer, _: V.Type) -> V {
            let view = ptr.assumingMemoryBound(to: V.self)
            return view.pointee
        }
        _forEachField(of: T.self) { charPtr, offset, fieldType in
            if let viewType = fieldType as? any View.Type {
                withUnsafeBytes(of: self.value) {
                    let ptr = $0.baseAddress!.advanced(by: offset)
                    let view = restore(ptr, viewType)
                    views.append(view)
                }
            }
            return true
        }
        return views
    }

    func _subview(name: String) -> any View {
        var view: (any View)?

        func restore<V: View>(_ ptr: UnsafeRawPointer, _: V.Type) -> V {
            let view = ptr.assumingMemoryBound(to: V.self)
            return view.pointee
        }
        _forEachField(of: T.self) { charPtr, offset, fieldType in
            if let viewType = fieldType as? any View.Type {
                let field = String(cString: charPtr)
                if name == field {
                    withUnsafeBytes(of: self.value) {
                        let ptr = $0.baseAddress!.advanced(by: offset)
                        view = restore(ptr, viewType)
                    }
                    return false
                }
            }
            return true
        }
        if let view {
            return view
        }
        fatalError("Field: \(name) not found!")
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let listInputs = _ViewListInputs(base: inputs.base, preferences: inputs.preferences)
        let listOutputs = Self._makeViewList(view: view, inputs: listInputs)

        let generator = TupleViewGenerator(graph: view,
                                           subviews: listOutputs.viewList,
                                           baseInputs: inputs.base,
                                           preferences: inputs.preferences)
        return _ViewOutputs(view: generator, preferences: .init(preferences: []))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var children: [any ViewGenerator] = []
        if let viewType = T.self as? any View.Type {
            if T.self is _PrimitiveView.Type {
                let inputs = _ViewInputs(base: inputs.base, preferences: inputs.preferences, traits: inputs.traits)
                let outputs = makeView(viewType, view: view[\.value].unsafeCast(to: Any.self), inputs: inputs)
                children.append(outputs.view)
            } else {
                let outputs = makeViewList(viewType, view: view[\.value].unsafeCast(to: Any.self), inputs: inputs)
                children.append(contentsOf: outputs.viewList)
            }
        } else {
            let subviews = self._subviewTypes
            for (index, v) in subviews.enumerated() {
                if v.type is _PrimitiveView.Type {
                    let inputs = _ViewInputs(base: inputs.base, preferences: inputs.preferences, traits: inputs.traits)
                    let outputs = makeView(v.type, view: view[\._subviews[index]].unsafeCast(to: Any.self), inputs: inputs)
                    children.append(outputs.view)
                } else {
                    let outputs = makeViewList(v.type, view: view[\._subviews[index]].unsafeCast(to: Any.self), inputs: inputs)
                    children.append(contentsOf: outputs.viewList)
                }
            }
        }
        return _ViewListOutputs(viewList: children, preferences: .init(preferences: []))
    }

    public typealias Body = Never
}

extension TupleView: _PrimitiveView {
}

struct TupleViewGenerator<Content> : ViewGenerator where Content : View {
    var graph: _GraphValue<Content>
    let subviews: [any ViewGenerator]
    var baseInputs: _GraphInputs
    var preferences: PreferenceInputs
    var traits: ViewTraitKeys = ViewTraitKeys()

    func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
        if let view = graph.value(atPath: self.graph, from: encloser) {
            let subviews = self.subviews.compactMap {
                $0.makeView(encloser: view, graph: self.graph)
            }
            if subviews.count > 1 {
                let layout = baseInputs.properties
                    .find(type: DefaultLayoutPropertyItem.self)?
                    .layout ?? DefaultLayoutPropertyItem.default
                return ViewGroupContext(view: view,
                                        subviews: subviews,
                                        layout: layout,
                                        inputs: baseInputs,
                                        graph: self.graph)
            }
            if let first = subviews.first {
                return first
            }
        }
        return nil
    }

}
