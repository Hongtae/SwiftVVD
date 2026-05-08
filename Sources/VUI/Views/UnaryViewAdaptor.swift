//
//  File: UnaryViewAdaptor.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Adaptor that forces `Content` to occupy one view-list slot.
public struct _UnaryViewAdaptor<Content>: View where Content: View {
    public var content: Content

    @inlinable public init(_ content: Content) {
        self.content = content
    }

    public typealias Body = Never

    public var body: Never { neverBody() }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Content._makeView(view: view[\.content], inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(viewType: Self.self, inputs: inputs) { viewInputs in
            var viewInputs = viewInputs
            var mergedBase = inputs.base
            mergedBase.merge(viewInputs.base, ignoringPhase: false)
            viewInputs.base = mergedBase
            return Self._makeView(view: view, inputs: viewInputs)
        }
    }
}
