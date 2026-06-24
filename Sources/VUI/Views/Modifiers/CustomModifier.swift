//
//  File: CustomModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct CustomModifier<Source, Result>: ViewModifier where Source: View, Result: View {
    var result: Result

    init(result: Result) {
        self.result = result
    }

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("\(Self.self)._makeView called outside an active AttributeGraph context.")
        }
        var inputs = inputs
        inputs.base.append(BodyInputElement(makeView: body), forKey: BodyInput<PlaceholderContentView<Source>>.self)
        return Result._makeView(view: modifier[\.result], inputs: inputs)
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("\(Self.self)._makeViewList called outside an active AttributeGraph context.")
        }
        var inputs = inputs
        inputs.base.append(BodyInputElement(makeViewList: body), forKey: BodyInput<PlaceholderContentView<Source>>.self)
        return Result._makeViewList(view: modifier[\.result], inputs: inputs)
    }

    typealias Body = Never
}
