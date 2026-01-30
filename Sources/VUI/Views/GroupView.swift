//
//  File: GroupView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

extension Group: View where Content: View {
    @inlinable public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public static func _makeViewList(view: _GraphValue<Group<Content>>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError()
    }
}

extension Group: _PrimitiveView where Content: View {
}
