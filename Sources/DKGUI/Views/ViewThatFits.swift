//
//  File: ViewThatFits.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct ViewThatFits<Content>: View where Content: View {
    var _tree: _VariadicView.Tree<_SizeFittingRoot, Content>
    public init(in axes: Axis.Set = [.horizontal, .vertical], @ViewBuilder content: () -> Content) {
        _tree = .init(root: _SizeFittingRoot(axes: axes), content: content())
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _VariadicView.Tree<_SizeFittingRoot, Content>._makeView(view: view[\._tree], inputs: inputs)
    }

    public typealias Body = Never
}

extension ViewThatFits: PrimitiveView {
}

public struct _SizeFittingRoot: _VariadicView.UnaryViewRoot {
    var axes: Axis.Set
    init(axes: Axis.Set) { self.axes = axes }
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        fatalError()
    }
    public typealias Body = Never
}
