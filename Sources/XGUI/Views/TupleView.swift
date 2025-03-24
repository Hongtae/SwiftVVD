//
//  File: TupleView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct TupleView<T> : View {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    public typealias Body = Never
}

extension TupleView {
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

        if let staticList = outputs.views as? StaticViewList {
            let views = staticList.views.map { $0.makeView() }
            let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
                StaticViewGroupContext(graph: graph, subviews: views, inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }
        else {
            let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
                DynamicViewGroupContext(graph: graph, body: outputs.views, inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        func _makeViewList<V: View, U>(_ type: V.Type, view: _GraphValue<U>, inputs: _ViewListInputs) -> _ViewListOutputs {
            return type._makeViewList(view: view.unsafeCast(to: V.self), inputs: inputs)
        }
        var subviews: [any ViewListGenerator] = []
        if let viewType = T.self as? any View.Type {
            let outputs = _makeViewList(viewType, view: view[\.value], inputs: inputs)
            subviews.append(outputs.views)
        } else {
            let subviewTypes = self._subviewTypes
            for (index, v) in subviewTypes.enumerated() {
                let outputs = _makeViewList(v.type, view: view[\._subviews[index]], inputs: inputs)
                subviews.append(outputs.views)
            }
        }

        let staticList = subviews.compactMap { $0 as? StaticViewList }
        if staticList.count == subviews.count { // all static
            let views = staticList.flatMap(\.views)
            return _ViewListOutputs(views: StaticViewListGenerator(views: views))
        } else {
            return _ViewListOutputs(views: .dynamicList(subviews))
        }
    }
}

extension TupleView : _PrimitiveView {
}
