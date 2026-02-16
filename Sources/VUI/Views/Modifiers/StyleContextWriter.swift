//
//  File: StyleContextWriter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

struct StyleContextProxy {
    let type: any StyleContext.Type
    let graph: _GraphValue<Any>
    init<S: StyleContext>(_ graph: _GraphValue<S>) {
        self.type = S.self
        self.graph = graph.unsafeCast(to: Any.self)
    }
    func resolve(_ resolver: some _GraphValueResolver) -> (any StyleContext)? {
        resolver.value(atPath: graph) as? (any StyleContext)
    }
}

struct StyleContextWriter<Style>: ViewModifier where Style: StyleContext {
    typealias Body = Never
    let style: Style
}

extension StyleContextWriter: _ViewInputsModifier where Self: ViewModifier {
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        inputs.base.styleContext = StyleContextProxy(modifier[\.style])
    }
}
