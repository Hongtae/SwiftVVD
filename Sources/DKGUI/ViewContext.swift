//
//  File: ViewContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import DKGame

protocol ViewProxy {
    associatedtype Content: View
    var view: Content { get }
    var modifiers: [any ViewModifier] { get }
    var subviews: [any ViewProxy] { get }
}

struct ViewContext<Content>: ViewProxy where Content: View {
    var view: Content
    var modifiers: [any ViewModifier]
    var subviews: [any ViewProxy]

    init(view: Content, modifiers: [any ViewModifier], subviews: [any ViewProxy]) {
        self.view = view
        self.modifiers = modifiers
        self.subviews = subviews
    }
    init(view: Content) {
        self.view = view
        self.modifiers = []
        self.subviews = []
    }
}

func _makeViewProxy<Content>(_ view: Content) -> any ViewProxy where Content: View {
    if let prim = view as? (any _PrimitiveView) {
        return prim.makeViewProxy()
    }
    return _makeViewProxy(view.body)
}
