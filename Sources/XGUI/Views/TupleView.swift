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
        let outputs = Self._makeViewList(view: view, inputs: inputs.listInputs)
        let generator = GenericViewGenerator(graph: view, inputs: inputs) { content, inputs in
            let subviews = outputs.viewList.makeViewList(encloser: content, graph: view).compactMap {
                $0.makeView(encloser: content, graph: view)
            }
            if subviews.count > 1 {
                let layout = inputs.base.properties
                    .find(type: DefaultLayoutPropertyItem.self)?
                    .layout ?? DefaultLayoutPropertyItem.default
                return ViewGroupContext(view: content,
                                        subviews: subviews,
                                        layout: layout,
                                        inputs: inputs.base,
                                        graph: view)
            }
            return subviews.first
        }
        return _ViewOutputs(view: generator)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var children: [any ViewListGenerator] = []
        if let viewType = T.self as? any View.Type {
            let outputs = makeViewList(viewType, view: view[\.value].unsafeCast(to: Any.self), inputs: inputs)
            children.append(outputs.viewList)
        } else {
            let subviews = self._subviewTypes
            for (index, v) in subviews.enumerated() {
                let outputs = makeViewList(v.type, view: view[\._subviews[index]].unsafeCast(to: Any.self), inputs: inputs)
                children.append(outputs.viewList)
            }
        }
        return _ViewListOutputs(viewList: .dynamicList(children))
    }

    public typealias Body = Never
}

extension TupleView: _PrimitiveView {}
