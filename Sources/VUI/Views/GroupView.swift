//
//  File: GroupView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

extension Group: View where Content: View {
    @inlinable public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public static func _makeViewList(view: _GraphValue<Group<Content>>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Content._makeViewList(view: view[\.content], inputs: inputs)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        Content._viewListCount(inputs: inputs)
    }
}

extension Group {
    public init<Base, Result>(
        sections view: Base,
        @ViewBuilder transform: @escaping (SectionCollection) -> Result
    ) where Content == GroupSectionsOfContent<Base, Result>, Base: View, Result: View {
        self.content = GroupSectionsOfContent(sections: view, content: transform)
    }
}

extension Group: _PrimitiveView where Content: View {
}
