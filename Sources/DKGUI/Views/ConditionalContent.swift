//
//  File: ConditionalContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct _ConditionalContent<TrueContent, FalseContent>: View where TrueContent: View, FalseContent: View {
    public enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }

    public typealias Body = Never
    public let storage: Storage

    init(storage: Storage) {
        self.storage = storage
    }

    public var body: Never { neverBody() }
}

extension _ConditionalContent {
    public static func _makeView(view: _GraphValue<_ConditionalContent<TrueContent, FalseContent>>, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewOutputs()
    }
    public static func _makeViewList(view: _GraphValue<_ConditionalContent<TrueContent, FalseContent>>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs()
    }
}
