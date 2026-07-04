//
//  File: TupleView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct TupleView<T>: View {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    public typealias Body = Never
}

private extension TupleView {
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
}

extension TupleView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        // Delegates to VStackLayout as the default layout for a bare TupleView.
        // This mirrors the behaviour when a view's body returns a TupleView directly,
        // which the framework wraps in a VStack-equivalent root.
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let body: (_Graph, _ViewInputs) -> _ViewListOutputs = { _, viewInputs in
            Self._makeViewList(view: view, inputs: _ViewListInputs(from: viewInputs))
        }
        let rootAttr: Attribute<VStackLayout> = graph.makeInput(value: VStackLayout())
        let rootGraph = _GraphValue<VStackLayout>(_attribute: rootAttr)
        return VStackLayout._makeLayoutView(root: rootGraph, inputs: inputs, body: body)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }

        var children: [_ViewListOutputs] = []

        // For each View-typed field in T, create an AG rule node that extracts that field
        // from the TupleView attribute.  Reading `view._attribute.value` inside the rule
        // registers a dependency on the TupleView node, so any update to the TupleView
        // propagates automatically.
        func makeChild<V: View>(_: V.Type, offset: Int) {
            let childAttr: Attribute<V> = graph.makeRule {
                let t = view._attribute.value.value   // TupleView<T>.value is T
                return withUnsafeBytes(of: t) { buf in
                    buf.baseAddress!
                        .advanced(by: offset)
                        .assumingMemoryBound(to: V.self)
                        .pointee
                }
            }
            let childGraph = _GraphValue<V>(_attribute: childAttr)
            children.append(V._makeViewList(view: childGraph, inputs: inputs))
        }

        _forEachField(of: T.self) { _, offset, fieldType in
            if let viewType = fieldType as? any View.Type {
                func open<V: View>(_: V.Type) { makeChild(V.self, offset: offset) }
                open(viewType)
            }
            return true
        }

        if inputs.needsSectionListOutputs {
            return _ViewListOutputs.sectionListOutputs(children, inputs: inputs)
        }

        if children.contains(where: { output in
            if case .dynamicList = output.views { return true }
            return false
        }) {
            let listAttributes: [Attribute<any ViewList>] = children.map { output in
                switch output.views {
                case .staticList(let elements):
                    return graph.makeRule {
                        BaseViewList(elements: elements)
                    }
                case .dynamicList(let attr, _):
                    return attr
                }
            }
            let viewListAttr: Attribute<any ViewList> = graph.makeRule {
                let lists: [(list: any ViewList, attribute: Attribute<any ViewList>)] = listAttributes.map { attr in
                    (attr.value, attr)
                }
                return _ViewList_Group(lists: lists)
            }
            return _ViewListOutputs(
                views: .dynamicList(viewListAttr, nil),
                nextImplicitID: 0,
                staticCount: nil
            )
        }

        let count = children.count
        return _ViewListOutputs(
            views: .staticList(.merged(children)),
            nextImplicitID: count,
            staticCount: count
        )
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        _subviewTypes.count
    }
}

extension TupleView: _PrimitiveView {
}
