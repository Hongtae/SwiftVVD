//
//  File: ConditionalContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

public struct _ConditionalContent<TrueContent, FalseContent> {
    enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }
    let storage: Storage
}

extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        if case let .trueContent(content) = view[\.storage].value {
            return TrueContent._makeView(view: _GraphValue(content), inputs: inputs)
        } else if case let .falseContent(content) = view[\.storage].value {
            return FalseContent._makeView(view: _GraphValue(content), inputs: inputs)
        }
        fatalError()
    }
    
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if case let .trueContent(content) = view[\.storage].value {
            return TrueContent._makeViewList(view: _GraphValue(content), inputs: inputs)
        } else if case let .falseContent(content) = view[\.storage].value {
            return FalseContent._makeViewList(view: _GraphValue(content), inputs: inputs)
        }
        fatalError()
    }
}

extension _ConditionalContent: _PrimitiveView where Self: View {
}
