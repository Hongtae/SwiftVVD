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
    var frame: Frame? { get }
}

struct ViewContext<Content>: ViewProxy where Content: View {
    var view: Content
    var graph: _GraphValue<Content>
    var inputs: _ViewInputs
    var outputs: _ViewOutputs
    var modifiers: [any ViewModifier]
    var subviews: [any ViewProxy]
    var frame: Frame? = nil
}
