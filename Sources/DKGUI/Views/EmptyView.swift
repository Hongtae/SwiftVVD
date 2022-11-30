//
//  File: EmptyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct EmptyView: View {
    public typealias Body = Never
}

extension EmptyView {
    public var body: Never { neverBody() }
}

extension EmptyView {
    public static func _makeView(view: _GraphValue<EmptyView>, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewOutputs()
    }

    public static func _makeViewList(view: _GraphValue<EmptyView>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs()
    }
}
