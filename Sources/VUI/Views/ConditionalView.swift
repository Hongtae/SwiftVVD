//
//  File: ConditionalView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never
    
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }

    var _trueContent: TrueContent {
        if case let .trueContent(content) = storage {
            return content
        }
        fatalError()
    }
    var _falseContent: FalseContent {
        if case let .falseContent(content) = storage {
            return content
        }
        fatalError()
    }
}

extension _ConditionalContent: _PrimitiveView where Self: View {
}

