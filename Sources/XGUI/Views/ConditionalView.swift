//
//  File: ConditionalView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
    public typealias Body = Never
    
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let trueContent = TrueContent._makeView(view: view[\._trueContent], inputs: inputs)
        let falseContent = FalseContent._makeView(view: view[\._falseContent], inputs: inputs)
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            ConditionalViewContext(graph: graph,
                                   inputs: inputs,
                                   trueContent: trueContent.view?.makeView(),
                                   falseContent: falseContent.view?.makeView())
        }
        return _ViewOutputs(view: view)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let viewInputs = inputs.inputs
        let trueContent = TrueContent._makeView(view: view[\._trueContent], inputs: viewInputs)
        let falseContent = FalseContent._makeView(view: view[\._falseContent], inputs: viewInputs)
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            ConditionalViewContext(graph: graph,
                                   inputs: inputs,
                                   trueContent: trueContent.view?.makeView(),
                                   falseContent: falseContent.view?.makeView())
        }
        return _ViewListOutputs(views: .staticList(view))
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

private class ConditionalViewContext<TrueContent, FalseContent>: DynamicViewContext<_ConditionalContent<TrueContent, FalseContent>>
where TrueContent: View, FalseContent: View {
    typealias Content = _ConditionalContent<TrueContent, FalseContent>

    let trueContent: ViewContext?
    let falseContent: ViewContext?

    init(graph: _GraphValue<Content>, inputs: _GraphInputs, trueContent: ViewContext?, falseContent: ViewContext?) {
        self.trueContent = trueContent
        self.falseContent = falseContent

        super.init(graph: graph, inputs: inputs)
    }

    deinit {
        trueContent?.superview = nil
        falseContent?.superview = nil
    }

    override func updateView(_ view: inout _ConditionalContent<TrueContent, FalseContent>) {
        switch view.storage {
        case .trueContent(_):
            self.body = self.trueContent
        case .falseContent(_):
            self.body = self.falseContent
        }
    }
}
