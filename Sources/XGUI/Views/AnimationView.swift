//
//  File: AnimationView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _AnimationView<Content> : View where Content: Equatable, Content : View {
    public var content: Content
    public var animation: Animation?

    @inlinable public init(content: Content, animation: Animation?) {
        self.content = content
        self.animation = animation
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError()
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError()
    }

    public typealias Body = Never
}

extension _AnimationView : _PrimitiveView {
}
