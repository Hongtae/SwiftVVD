//
//  File: PrimitiveView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

protocol PrimitiveView: View where Body == Never {
}

extension PrimitiveView {
    public var body: Never {
        fatalError("body() should not be called on \(Self.self).")
    }
}

protocol PubliclyPrimitiveView: PrimitiveView {
    associatedtype InternalBody: View

    @ViewBuilder var internalBody: InternalBody { get }
}

private struct MakeBody<V: PubliclyPrimitiveView>: Rule {
    var view: Attribute<V>

    var value: V.InternalBody {
        view.value.internalBody
    }
}

extension PubliclyPrimitiveView {
    public static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard _AGGraph.current != nil else {
            fatalError(
                "\(self)._makeView called outside an active _AGGraph context."
            )
        }
        return InternalBody._makeView(
            view: _GraphValue(MakeBody(view: view._attribute)),
            inputs: inputs
        )
    }

    public static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError(
                "\(self)._makeViewList called outside an active _AGGraph context."
            )
        }
        return InternalBody._makeViewList(
            view: _GraphValue(MakeBody(view: view._attribute)),
            inputs: inputs
        )
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs
    ) -> Int? {
        InternalBody._viewListCount(inputs: inputs)
    }
}
