//
//  File: ConditionalContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
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
        fatalError()
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError()
    }
}

extension _ConditionalContent: PrimitiveView where Self: View {
}
