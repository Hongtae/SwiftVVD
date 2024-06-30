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
            func _makeView<V: View>(_: V.Type, view: Any, inputs: _ViewInputs) -> _ViewOutputs {
                V._makeView(view: view as! _GraphValue<V>, inputs: inputs)
            }
            func _makeViewList<V: View>(_: V.Type, view: Any, inputs: _ViewListInputs) -> _ViewListOutputs {
                V._makeViewList(view: view as! _GraphValue<V>, inputs: inputs)
            }
            if T.self is _PrimitiveView.Type {
                let inputs = _ViewInputs(base: inputs.base, preferences: inputs.preferences, traits: inputs.traits)
                let outputs = _makeView(viewType, view: view[\.value], inputs: inputs)
                children.append(outputs.view)
            } else {
                let outputs = _makeViewList(viewType, view: view[\.value], inputs: inputs)
                children.append(contentsOf: outputs.viewList)
            }
        } else {
            func _makeView<V: View>(_: V.Type, view: _GraphValue<any View>, inputs: _ViewInputs) -> _ViewOutputs {
                V._makeView(view: view.unsafeCast(to: V.self), inputs: inputs)
            }
            func _makeViewList<V: View>(_: V.Type, view: _GraphValue<any View>, inputs: _ViewListInputs) -> _ViewListOutputs {
                V._makeViewList(view: view.unsafeCast(to: V.self), inputs: inputs)
            }
            let subviews = self._subviewTypes
            for (index, v) in subviews.enumerated() {
                if v.type is _PrimitiveView.Type {
                    let inputs = _ViewInputs(base: inputs.base, preferences: inputs.preferences, traits: inputs.traits)
                    let outputs = _makeView(v.type, view: view[\._subviews[index]], inputs: inputs)
                    children.append(outputs.view)
                } else {
                    let outputs = _makeViewList(v.type, view: view[\._subviews[index]], inputs: inputs)
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

    func makeView(content view: Content) -> ViewContext? {
        func makeBody<T: ViewGenerator>(_ gen: T) -> ViewContext? {
            if let body = self.graph.value(atPath: gen.graph, from: view) {
                return gen.makeView(content: body)
            }
            return nil
        }
        let subviews = self.subviews.compactMap { makeBody($0) }
        if subviews.count > 1 {
            let layout = baseInputs.properties?
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
        return nil
    }
}
