//
//  File: VStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

public struct VStack<Content>: View where Content: View {
    public var body: Never { neverBody() }
    public var _tree: _VariadicView.Tree<_VStackLayout, Content>

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        _tree = .init(
            root: _VStackLayout(alignment: alignment, spacing: spacing), content: content())
    }
}

extension VStack: _PrimitiveView {
    func makeViewProxy(modifiers: [any ViewModifier],
                       environmentValues: EnvironmentValues,
                       sharedContext: SharedContext) -> any ViewProxy {
        var subviews: [any ViewProxy] = []
        return ViewGroupContext(view: self,
                                layout: self._tree.root,
                                subviews: subviews,
                                modifiers: modifiers,
                                environmentValues: environmentValues,
                                sharedContext: sharedContext)
    }
}
