//
//  File: EmptyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

public struct EmptyView: View {
    public init() {}

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        return _ViewOutputs(view: EmptyViewGenerator(graph: view), preferences: PreferenceOutputs(preferences: []))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        return _ViewListOutputs(viewList: .staticList([]), preferences: PreferenceOutputs(preferences: []))
    }

    public typealias Body = Never
}

extension EmptyView: _PrimitiveView {
}

private struct EmptyViewGenerator : ViewGenerator {
    let graph: _GraphValue<EmptyView>
    func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? { nil }
    func mergeInputs(_: _GraphInputs) {}
}
