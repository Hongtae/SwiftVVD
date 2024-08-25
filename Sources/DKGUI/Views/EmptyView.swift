//
//  File: EmptyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

public struct EmptyView: View {
    public init() {}

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        return _ViewOutputs()
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        return _ViewListOutputs(viewList: .empty)
    }

    public typealias Body = Never
}

extension EmptyView: _PrimitiveView {
}

struct EmptyViewGenerator<T> : ViewGenerator {
    let graph: _GraphValue<T>
    func makeView<U>(encloser: U, graph: _GraphValue<U>) -> ViewContext? { nil }
    mutating func mergeInputs(_ inputs: _GraphInputs) {}
}
