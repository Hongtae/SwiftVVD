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
    static var _subviewTypes: [
        (name: String, index: Int, offset: Int, type: any View.Type)
    ] {
        if let viewType = T.self as? any View.Type {
            return [(name: "", index: 0, offset: 0, type: viewType)]
        }

        var types: [
            (name: String, index: Int, offset: Int, type: any View.Type)
        ] = []
        var index = 0
        _forEachField(of: T.self) { charPtr, offset, fieldType in
            if let viewType = fieldType as? any View.Type {
                let name = String(cString: charPtr)
                types.append(
                    (
                        name: name,
                        index: index,
                        offset: offset,
                        type: viewType
                    )
                )
            }
            index += 1
            return true
        }
        return types
    }

    var _subviews: [any View] {
        if let view = value as? any View {
            return [view]
        }

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

    struct MakeUnary: ViewTypeVisitor {
        var view: _GraphValue<TupleView<T>>
        var inputs: _ViewInputs
        var outputs: _ViewOutputs?

        mutating func visit<V>(type: V.Type) where V: View {
            outputs = V._makeView(
                view: view.unsafeBitCast(to: type),
                inputs: inputs
            )
        }
    }

    struct MakeList: ViewTypeVisitor {
        var view: _GraphValue<TupleView<T>>
        var inputs: _ViewListInputs
        var index: Int
        var offset: Int
        var wrapChildren: Bool
        var includeOffsets: Bool
        var outputs: [_ViewListOutputs]

        mutating func visit<V>(type: V.Type) where V: View {
            var childInputs = inputs
            childInputs.base.pushStableIndex(index)

            let child = _GraphValue<V>(
                _attribute: view._attribute.unsafeOffset(
                    at: offset,
                    as: type
                )
            )
            let output: _ViewListOutputs
            if wrapChildren {
                output = .unaryViewList(
                    view: child,
                    inputs: childInputs
                )
            } else {
                output = V._makeViewList(
                    view: child,
                    inputs: childInputs
                )
            }

            outputs.append(output)
            inputs.implicitID = output.nextImplicitID
            if includeOffsets {
                inputs.updateContentOffset(outputs: output)
            }
        }
    }

    struct CountViews: ViewTypeVisitor {
        var inputs: _ViewListCountInputs
        var count: Int?

        mutating func visit<V>(type: V.Type) where V: View {
            guard let count,
                  let childCount = V._viewListCount(inputs: inputs) else {
                self.count = nil
                return
            }
            self.count = count + childCount
        }
    }
}

extension TupleView {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let subviewTypes = _subviewTypes
        switch subviewTypes.count {
        case 0:
            return _ViewOutputs()
        case 1:
            var visitor = MakeUnary(
                view: view,
                inputs: inputs,
                outputs: nil
            )
            let viewType = subviewTypes[0].type
            func open<V: View>(_ type: V.Type) {
                visitor.visit(type: type)
            }
            open(viewType)
            guard let outputs = visitor.outputs else {
                fatalError(
                    "\(Self.self).MakeUnary did not produce view outputs."
                )
            }
            return outputs
        default:
            return makeImplicitRoot(view: view, inputs: inputs)
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }

        let createsUnaryElements =
            inputs.options.contains(.tupleViewCreatesUnaryElements)
        let requiresContentOffsets =
            inputs.options.contains(.requiresContentOffsets)

        var childInputs = inputs
        if createsUnaryElements {
            childInputs.options.remove(.tupleViewCreatesUnaryElements)
        }

        var visitor = MakeList(
            view: view,
            inputs: childInputs,
            index: 0,
            offset: 0,
            wrapChildren: createsUnaryElements,
            includeOffsets: requiresContentOffsets,
            outputs: []
        )
        for descriptor in _subviewTypes {
            visitor.index = descriptor.index
            visitor.offset = descriptor.offset
            func open<V: View>(_ type: V.Type) {
                visitor.visit(type: type)
            }
            open(descriptor.type)
        }

        return .concat(
            visitor.outputs,
            inputs: visitor.inputs
        )
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        let subviewTypes = _subviewTypes
        if inputs.options.contains(.tupleViewCreatesUnaryElements) {
            return subviewTypes.count
        }

        var visitor = CountViews(inputs: inputs, count: 0)
        for descriptor in subviewTypes {
            guard visitor.count != nil else { break }
            func open<V: View>(_ type: V.Type) {
                visitor.visit(type: type)
            }
            open(descriptor.type)
        }
        return visitor.count
    }
}

@available(*, unavailable)
extension TupleView: Sendable {
}

extension TupleView: PrimitiveView {
}
