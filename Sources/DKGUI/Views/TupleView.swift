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
        var children: [any ViewGenerator] = []
        if let viewType = T.self as? any View.Type {
            func _makeView<V: View>(_: V.Type, view: Any, inputs: _ViewInputs) -> _ViewOutputs {
                V._makeView(view: view as! _GraphValue<V>, inputs: inputs)
            }
            let outputs = _makeView(viewType, view: view[\.value], inputs: inputs)
            children.append(outputs.view)
        } else {
            func _makeView<V: View>(_: V.Type, view: _GraphValue<any View>, inputs: _ViewInputs) -> _ViewOutputs {
                V._makeView(view: view.unsafeCast(to: V.self), inputs: inputs)
            }
            func _makeViewList<V: View>(_: V.Type, view: _GraphValue<any View>, inputs: _ViewListInputs) -> _ViewListOutputs {
                return V._makeViewList(view: view.unsafeCast(to: V.self), inputs: inputs)
            }
            let subviews = self._subviewTypes
            let listInputs = _ViewListInputs(base: inputs.base, preferences: inputs.preferences)
            for (index, v) in subviews.enumerated() {
                if v.type is _PrimitiveView.Type {
                    let inputs = _ViewInputs(base: inputs.base, preferences: inputs.preferences, traits: inputs.traits)
                    let outputs = _makeView(v.type, view: view[\._subviews[index]], inputs: inputs)
                    children.append(outputs.view)
                } else {
                    let outputs = _makeViewList(v.type, view: view[\._subviews[index]], inputs: listInputs)
                    children.append(outputs.view)
                }
            }
        }
        let generator = TupleViewGenerator(view: view,
                                           subviews: children,
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
                return _ViewListOutputs(view: outputs.view, preferences: outputs.preferences)
            }
            let outputs = _makeViewList(viewType, view: view[\.value], inputs: inputs)
            children.append(outputs.view)
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
                    children.append(outputs.view)
                }
            }
        }
        let generator = TupleViewGenerator(view: view,
                                           subviews: children,
                                           baseInputs: inputs.base,
                                           preferences: inputs.preferences)
        return _ViewListOutputs(view: generator, preferences: .init(preferences: []))
    }

    public typealias Body = Never
}

extension TupleView: _PrimitiveView {
}

struct TupleViewGenerator<Content> : ViewGenerator where Content : View {
    var view: _GraphValue<Content>
    let subviews: [any ViewGenerator]
    var baseInputs: _GraphInputs
    var preferences: PreferenceInputs
    var traits: ViewTraitKeys = ViewTraitKeys()

    func makeView(view: Content) -> ViewContext? {
        func makeBody<T: ViewGenerator>(_ gen: T) -> ViewContext? {
            if let body = self.view.value(atPath: gen.view, from: view) {
                return gen.makeView(view: body)
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
                                    path: self.view)
        }
        if let first = subviews.first {
            return first
        }
        return nil
    }
}
