//
//  File: EmptyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct EmptyView: View {
    public init() {}

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        // EmptyView has no layout and produces no preferences.
        _ViewOutputs()
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        // EmptyView contributes zero children to any list.
        _ViewListOutputs(views: .staticList(.merged([])),
                         nextImplicitID: 0,
                         staticCount: 0)
    }

    public typealias Body = Never
}

extension EmptyView: PrimitiveView {
}
