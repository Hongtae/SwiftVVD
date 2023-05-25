//
//  File: HStack.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

public struct HStack<Content>: View where Content: View {
    public var body: Never { neverBody() }
    public var _tree: _VariadicView.Tree<_HStackLayout, Content>

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        _tree = .init(
            root: _HStackLayout(alignment: alignment, spacing: spacing), content: content())
    }
}

extension HStack: _PrimitiveView {
    func makeViewProxy(modifiers: [any ViewModifier],
                       environmentValues: EnvironmentValues,
                       sharedContext: SharedContext) -> any ViewProxy {
        ViewContext(view: self,
                    modifiers: modifiers,
                    environmentValues: environmentValues,
                    sharedContext: sharedContext)
    }
}
