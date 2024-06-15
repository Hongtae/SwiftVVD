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

    //var _empty: EmptyView { .init() }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        func _makeView<V: View>(_: V.Type, view: Any, inputs: _ViewInputs) -> _ViewOutputs {
            V._makeView(view: view as! _GraphValue<V>, inputs: inputs)
        }

        if let viewType = T.self as? any View.Type {
            return _makeView(viewType, view: view[\.value], inputs: inputs)
        }

        let subviews = self._subviewTypes
        if subviews.count > 1 {
            func _makeViewList<V: View>(_: V.Type, view: _GraphValue<any View>, inputs: _ViewListInputs) -> _ViewListOutputs {
                return V._makeViewList(view: view.unsafeCast(to: V.self), inputs: inputs)
            }
            let listInputs = _ViewListInputs(base: inputs.base, preferences: inputs.preferences)

            var views: [any ViewGenerator] = []
            for (index, v) in subviews.enumerated() {
                let outputs = _makeViewList(v.type, view: view[\._subviews[index]], inputs: listInputs)
                views.append(outputs.view)
            }
            let generator = TupleViewGenerator(view: view,
                                               subviews: views,
                                               baseInputs: inputs.base,
                                               preferences: inputs.preferences)
            return _ViewOutputs(view: generator, preferences: .init(preferences: []))
        }
        if let first = subviews.first {
            return _makeView(first.type, view: view[\._subviews[0]], inputs: inputs)
        }
        fatalError()
        //return EmptyView._makeView(view: view[\._empty], inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        func _makeViewList<V: View>(_: V.Type, view: Any, inputs: _ViewListInputs) -> _ViewListOutputs {
            V._makeViewList(view: view as! _GraphValue<V>, inputs: inputs)
        }

        if let viewType = T.self as? any View.Type {
            return _makeViewList(viewType, view: view[\.value], inputs: inputs)
        }

        let subviews = self._subviewTypes
        if subviews.count > 1 {
            func _makeViewList<V: View>(_: V.Type, view: _GraphValue<any View>, inputs: _ViewListInputs) -> _ViewListOutputs {
                V._makeViewList(view: view.unsafeCast(to: V.self), inputs: inputs)
            }

            var views: [any ViewGenerator] = []
            for (index, v) in subviews.enumerated() {
                let outputs = _makeViewList(v.type,
                                            view: view[\._subviews[index]],
                                            inputs: inputs)
                views.append(outputs.view)
            }
            let generator = TupleViewGenerator(view: view,
                                               subviews: views,
                                               baseInputs: inputs.base,
                                               preferences: inputs.preferences)
            return _ViewListOutputs(view: generator, preferences: .init(preferences: []))
        }
        if let first = subviews.first {
            return _makeViewList(first.type, view: view[\._subviews[0]], inputs: inputs)
        }
        fatalError()
        //return EmptyView._makeViewList(view: view[\._empty], inputs: inputs)
    }

    public typealias Body = Never
}

extension TupleView: _PrimitiveView {
}

struct TupleViewGenerator<Content> : ViewGenerator where Content: View {
    let view: _GraphValue<Content>
    let subviews: [any ViewGenerator]
    var baseInputs: _GraphInputs
    var preferences: PreferenceInputs
    var traits: ViewTraitKeys = ViewTraitKeys()

    func makeView(view: Content) -> ViewContext {
        fatalError()
    }
}
